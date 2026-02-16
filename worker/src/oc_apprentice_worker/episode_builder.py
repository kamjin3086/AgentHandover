"""Episode Builder v1 — cluster events into episodes by app/URL/entities.

Implements section 8 of the OpenMimic spec: thread-multiplexed episode
construction with soft (time) and hard (event count) caps.

Thread Multiplexing Strategy:
- Cluster events by window/app identity (``app_id``) and URL domain
- Events with the same thread_id go to the same episode unless a cap is hit
- When a cap is exceeded the episode is split into linked segments

Episode Caps:
- Soft cap: 15 minutes duration — preferred split point
- Hard cap: 200 events — absolute maximum per segment
"""

from __future__ import annotations

import json
import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from urllib.parse import urlparse

logger = logging.getLogger(__name__)


@dataclass
class Episode:
    """A contiguous segment of events sharing a common thread."""

    episode_id: str
    segment_id: int = 0
    prev_segment_id: int | None = None
    thread_id: str = ""
    events: list[dict] = field(default_factory=list)
    start_time: datetime | None = None
    end_time: datetime | None = None

    @property
    def duration_minutes(self) -> float:
        """Elapsed wall-clock minutes between first and last event."""
        if self.start_time and self.end_time:
            return (self.end_time - self.start_time).total_seconds() / 60.0
        return 0.0

    @property
    def event_count(self) -> int:
        return len(self.events)

    def is_over_soft_cap(self) -> bool:
        """True when duration >= soft cap (15 min default)."""
        return self.duration_minutes >= 15.0

    def is_over_hard_cap(self) -> bool:
        """True when event count >= hard cap (200 default)."""
        return self.event_count >= 200

    def should_split(self) -> bool:
        """True when either cap is exceeded."""
        return self.is_over_soft_cap() or self.is_over_hard_cap()


class EpisodeBuilder:
    """Build episodes from a chronological stream of events.

    Parameters
    ----------
    soft_cap_minutes:
        Duration threshold in minutes that triggers a segment split.
    hard_cap_events:
        Maximum number of events in a single segment.
    """

    def __init__(
        self,
        soft_cap_minutes: float = 15.0,
        hard_cap_events: int = 200,
    ) -> None:
        self.soft_cap_minutes = soft_cap_minutes
        self.hard_cap_events = hard_cap_events

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def process_events(self, events: list[dict]) -> list[Episode]:
        """Process a batch of events and return completed episodes.

        Events are grouped by *thread_id* (derived from ``app_id`` and
        URL domain).  Within each thread the episode is split when the
        soft cap (duration) or hard cap (event count) is exceeded.
        """
        if not events:
            return []

        # Map thread_id -> current open Episode
        open_episodes: dict[str, Episode] = {}
        # Collect all completed (and still-open) episodes in order
        completed: list[Episode] = []

        for event in events:
            thread_id = self._get_thread_id(event)
            ts = self._parse_timestamp(event)

            current = open_episodes.get(thread_id)

            if current is None:
                # First event for this thread
                episode = self._new_episode(thread_id=thread_id)
                self._add_event(episode, event, ts)
                open_episodes[thread_id] = episode
            elif self._should_start_new_segment(event, current, ts):
                # Cap exceeded — finalise current, start a new segment
                completed.append(current)
                new_seg = self._split_episode(current)
                self._add_event(new_seg, event, ts)
                open_episodes[thread_id] = new_seg
            else:
                self._add_event(current, event, ts)

        # Flush remaining open episodes
        for ep in open_episodes.values():
            completed.append(ep)

        # Sort by start_time so output is deterministic
        completed.sort(key=lambda e: e.start_time or datetime.min.replace(tzinfo=timezone.utc))
        return completed

    # ------------------------------------------------------------------
    # Thread identification
    # ------------------------------------------------------------------

    def _get_thread_id(self, event: dict) -> str:
        """Determine thread ID from event's app_id and URL domain.

        Thread ID format:
        - ``{app_id}:{url_domain}`` when a URL is present in metadata
        - ``{app_id}`` when no URL is found
        - ``unknown`` when no app_id can be extracted
        """
        app_id = self._extract_app_id(event)
        url_domain = self._extract_url_domain(event)

        if not app_id:
            return "unknown"
        if url_domain:
            return f"{app_id}:{url_domain}"
        return app_id

    def _extract_app_id(self, event: dict) -> str:
        """Extract app_id from the event's window_json field."""
        window_json = event.get("window_json")
        if not window_json:
            return ""

        try:
            window = json.loads(window_json) if isinstance(window_json, str) else window_json
        except (json.JSONDecodeError, TypeError):
            return ""

        return window.get("app_id", "")

    def _extract_url_domain(self, event: dict) -> str:
        """Extract URL domain from the event's metadata_json field."""
        metadata_json = event.get("metadata_json")
        if not metadata_json:
            return ""

        try:
            metadata = json.loads(metadata_json) if isinstance(metadata_json, str) else metadata_json
        except (json.JSONDecodeError, TypeError):
            return ""

        url = metadata.get("url", "")
        if not url:
            return ""

        try:
            parsed = urlparse(url)
            return parsed.netloc or ""
        except Exception:
            return ""

    # ------------------------------------------------------------------
    # Splitting logic
    # ------------------------------------------------------------------

    def _should_start_new_segment(
        self,
        event: dict,
        current: Episode,
        event_ts: datetime | None,
    ) -> bool:
        """Check if the current episode should be split before adding *event*.

        A split occurs when:
        - The event count would reach the hard cap, OR
        - The duration would reach the soft cap
        """
        # Hard cap: would this event push us to the limit?
        if current.event_count >= self.hard_cap_events:
            return True

        # Soft cap: would this event push duration past the threshold?
        if event_ts and current.start_time:
            prospective_minutes = (event_ts - current.start_time).total_seconds() / 60.0
            if prospective_minutes >= self.soft_cap_minutes:
                return True

        return False

    def _split_episode(self, current: Episode) -> Episode:
        """Create a new segment linked to *current*."""
        new_segment = Episode(
            episode_id=current.episode_id,
            segment_id=current.segment_id + 1,
            prev_segment_id=current.segment_id,
            thread_id=current.thread_id,
        )
        return new_segment

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _new_episode(self, thread_id: str) -> Episode:
        """Create a brand-new episode (segment 0)."""
        return Episode(
            episode_id=str(uuid.uuid4()),
            segment_id=0,
            prev_segment_id=None,
            thread_id=thread_id,
        )

    def _add_event(
        self,
        episode: Episode,
        event: dict,
        ts: datetime | None,
    ) -> None:
        """Append *event* to *episode* and update time bookkeeping."""
        episode.events.append(event)
        if ts:
            if episode.start_time is None:
                episode.start_time = ts
            episode.end_time = ts

    @staticmethod
    def _parse_timestamp(event: dict) -> datetime | None:
        """Parse the ISO 8601 timestamp from an event dict."""
        raw = event.get("timestamp")
        if not raw:
            return None

        try:
            # Handle the 'Z' suffix and various ISO formats
            if isinstance(raw, str):
                raw = raw.replace("Z", "+00:00")
                return datetime.fromisoformat(raw)
        except (ValueError, TypeError):
            return None
        return None
