"""Style and voice analyzer for user-produced text.

Analyzes content_produced text samples to extract writing patterns,
tone, and formality characteristics.  Populates the procedure's
``voice_profile`` and ``content_samples`` fields for future
fine-tuning and personalization.

Pure Python — no ML dependencies.  Uses simple heuristics that are
surprisingly effective for characterizing writing style:
  * Sentence length distribution
  * Vocabulary richness (type-token ratio)
  * Formality score (contractions, pronouns, exclamation marks)
  * Punctuation patterns
  * Capitalization habits
"""

from __future__ import annotations

import logging
import re
from collections import Counter

logger = logging.getLogger(__name__)

# Formality markers
_INFORMAL_MARKERS = {
    "contractions": re.compile(
        r"\b(i'm|i've|i'll|i'd|we're|we've|we'll|they're|they've|"
        r"you're|you've|you'll|he's|she's|it's|that's|there's|"
        r"isn't|aren't|wasn't|weren't|don't|doesn't|didn't|"
        r"won't|wouldn't|shouldn't|couldn't|can't|hasn't|haven't)\b",
        re.IGNORECASE,
    ),
    "exclamations": re.compile(r"!"),
    "ellipsis": re.compile(r"\.{3}|…"),
    "emoji_like": re.compile(r"[:;][-']?[)(DPp/\\|]|<3|xD|lol|haha", re.IGNORECASE),
    "first_person": re.compile(r"\b(I|me|my|mine|myself)\b"),
}

_FORMAL_MARKERS = {
    "passive_voice": re.compile(
        r"\b(is|are|was|were|be|been|being)\s+(being\s+)?\w+ed\b",
        re.IGNORECASE,
    ),
    "hedging": re.compile(
        r"\b(perhaps|possibly|arguably|it seems|appears to|"
        r"may be|might be|could be|would suggest)\b",
        re.IGNORECASE,
    ),
}

_SENTENCE_SPLIT = re.compile(r"[.!?]+\s+|\n\n+")
_WORD_SPLIT = re.compile(r"\b\w+\b")


def analyze_style(texts: list[str]) -> dict:
    """Analyze a collection of user-produced texts.

    Args:
        texts: List of text samples (from content_produced full_value).

    Returns:
        A voice_profile dict with style characteristics.
    """
    if not texts:
        return {}

    combined = " ".join(texts)
    if len(combined) < 50:
        return {}  # Not enough text to analyze

    # Sentence analysis
    sentences = [s.strip() for s in _SENTENCE_SPLIT.split(combined) if s.strip()]
    words = _WORD_SPLIT.findall(combined.lower())

    if not words:
        return {}

    word_count = len(words)
    unique_words = len(set(words))

    # Sentence length
    sentence_lengths = [len(_WORD_SPLIT.findall(s)) for s in sentences] if sentences else [0]
    avg_sentence_length = sum(sentence_lengths) / max(len(sentence_lengths), 1)

    # Type-token ratio (vocabulary richness)
    ttr = unique_words / word_count if word_count > 0 else 0.0

    # Formality scoring
    informal_count = 0
    formal_count = 0
    for name, pattern in _INFORMAL_MARKERS.items():
        matches = len(pattern.findall(combined))
        informal_count += matches

    for name, pattern in _FORMAL_MARKERS.items():
        matches = len(pattern.findall(combined))
        formal_count += matches

    # Normalize by word count
    informal_rate = informal_count / max(word_count, 1) * 100
    formal_rate = formal_count / max(word_count, 1) * 100

    # Formality score: -1 (very informal) to +1 (very formal)
    if informal_rate + formal_rate > 0:
        formality = (formal_rate - informal_rate) / (formal_rate + informal_rate)
    else:
        formality = 0.0

    # Formality label
    if formality > 0.3:
        formality_label = "formal"
    elif formality < -0.3:
        formality_label = "casual"
    else:
        formality_label = "neutral"

    # Punctuation patterns
    exclamation_rate = combined.count("!") / max(len(sentences), 1)
    question_rate = combined.count("?") / max(len(sentences), 1)
    emoji_count = len(_INFORMAL_MARKERS["emoji_like"].findall(combined))

    # Capitalization (are they a caps-lock person?)
    upper_words = sum(1 for w in combined.split() if w.isupper() and len(w) > 1)
    caps_rate = upper_words / max(word_count, 1)

    return {
        "formality": formality_label,
        "formality_score": round(formality, 3),
        "avg_sentence_length": round(avg_sentence_length, 1),
        "vocabulary_richness": round(ttr, 3),
        "word_count_analyzed": word_count,
        "sample_count": len(texts),
        "exclamation_rate": round(exclamation_rate, 2),
        "question_rate": round(question_rate, 2),
        "uses_emoji": emoji_count > 0,
        "caps_rate": round(caps_rate, 3),
    }


def extract_content_samples(
    texts: list[str],
    max_samples: int = 5,
    min_length: int = 20,
    max_length: int = 500,
) -> list[dict]:
    """Select representative text samples from user-produced content.

    Picks diverse samples that best represent the user's writing style.
    Returns dicts with ``text`` and ``length`` fields.
    """
    if not texts:
        return []

    # Filter to reasonable lengths
    candidates = [
        t for t in texts
        if min_length <= len(t) <= max_length * 2
    ]
    if not candidates:
        # Try with relaxed constraints
        candidates = [t for t in texts if len(t) >= min_length]

    if not candidates:
        return []

    # Sort by length (prefer medium-length samples — most representative)
    candidates.sort(key=lambda t: abs(len(t) - 150))

    samples = []
    seen_prefixes: set[str] = set()

    for text in candidates:
        if len(samples) >= max_samples:
            break
        # Skip near-duplicates
        prefix = text[:30].lower()
        if prefix in seen_prefixes:
            continue
        seen_prefixes.add(prefix)

        samples.append({
            "text": text[:max_length],
            "length": len(text),
        })

    return samples


def analyze_procedure_style(procedure: dict) -> tuple[dict, list[dict]]:
    """Extract style profile from a procedure's evidence.

    Reads content_produced from extracted_evidence and analyzes
    the user's writing patterns.

    Returns:
        (voice_profile, content_samples) tuple.
    """
    evidence = procedure.get("evidence", {})
    extracted = evidence.get("extracted_evidence", {})
    content_items = extracted.get("content_produced", [])

    # Collect full_value texts
    texts = []
    for item in content_items:
        full = item.get("full_value", "")
        if full and len(full) > 10:
            texts.append(full)
        else:
            # Fallback to value_preview
            preview = item.get("value_preview", "")
            if preview and len(preview) > 10:
                texts.append(preview)

    voice_profile = analyze_style(texts)
    content_samples = extract_content_samples(texts)

    # Cumulative: merge with existing voice_profile if present
    existing_vp = procedure.get("voice_profile", {})
    if existing_vp and voice_profile:
        voice_profile = merge_voice_profiles(existing_vp, voice_profile)

    return voice_profile, content_samples


def merge_voice_profiles(existing: dict, new: dict) -> dict:
    """Merge two voice profiles, strengthening confidence over sessions.

    Weighted average based on sample counts — more data = stronger signal.
    The ``style_confidence`` field tracks how reliable the profile is:
    low (<5 samples), moderate (5-20), high (>20).
    """
    if not existing:
        return new
    if not new:
        return existing

    old_n = existing.get("word_count_analyzed", 0)
    new_n = new.get("word_count_analyzed", 0)
    total_n = old_n + new_n
    if total_n == 0:
        return new

    old_w = old_n / total_n
    new_w = new_n / total_n

    merged = {}

    # Weighted average for numeric fields
    for key in ("formality_score", "avg_sentence_length", "vocabulary_richness",
                "exclamation_rate", "question_rate", "caps_rate"):
        old_v = existing.get(key, 0.0)
        new_v = new.get(key, 0.0)
        merged[key] = round(old_v * old_w + new_v * new_w, 3)

    # Cumulative counts
    merged["word_count_analyzed"] = total_n
    total_samples = existing.get("sample_count", 0) + new.get("sample_count", 0)
    merged["sample_count"] = total_samples

    # Boolean OR
    merged["uses_emoji"] = existing.get("uses_emoji", False) or new.get("uses_emoji", False)

    # Re-derive formality label from merged score
    fs = merged["formality_score"]
    if fs > 0.3:
        merged["formality"] = "formal"
    elif fs < -0.3:
        merged["formality"] = "casual"
    else:
        merged["formality"] = "neutral"

    # Style confidence — strengthens with more data
    if total_samples >= 20:
        merged["style_confidence"] = "high"
    elif total_samples >= 5:
        merged["style_confidence"] = "moderate"
    else:
        merged["style_confidence"] = "low"

    return merged


def aggregate_user_style(procedures: list[dict]) -> dict:
    """Build a user-level style profile from all procedures.

    Aggregates voice_profiles across all procedures weighted by
    sample_count.  Returns a holistic profile suitable for profile.json.
    """
    all_profiles = []
    for proc in procedures:
        vp = proc.get("voice_profile", {})
        if vp and vp.get("word_count_analyzed", 0) > 0:
            all_profiles.append(vp)

    if not all_profiles:
        return {}

    # Weighted merge across all procedures
    result = all_profiles[0]
    for vp in all_profiles[1:]:
        result = merge_voice_profiles(result, vp)

    # Add per-context breakdown
    contexts = []
    for proc in procedures:
        vp = proc.get("voice_profile", {})
        if vp and vp.get("formality"):
            contexts.append({
                "procedure": proc.get("id", ""),
                "formality": vp.get("formality", "neutral"),
                "sample_count": vp.get("sample_count", 0),
            })

    if contexts:
        result["per_workflow"] = contexts

    return result
