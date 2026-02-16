"""Tests for the SOP Formatter — YAML frontmatter and manual edit detection."""

from __future__ import annotations

import hashlib
from pathlib import Path

import pytest
import yaml

from oc_apprentice_worker.sop_format import SOPFormatter


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _sample_sop_template(
    slug: str = "test_workflow",
    title: str = "Test Workflow",
    confidence_avg: float = 0.88,
    steps: list[dict] | None = None,
    variables: list[dict] | None = None,
    apps: list[str] | None = None,
) -> dict:
    if steps is None:
        steps = [
            {
                "step": "click",
                "target": "Submit button",
                "selector": "[aria-label='Submit']",
                "parameters": {"text": "Hello"},
                "confidence": 0.9,
            },
            {
                "step": "type",
                "target": "Email field",
                "selector": "#email",
                "parameters": {"text": "user@example.com"},
                "confidence": 0.85,
            },
        ]
    if variables is None:
        variables = []
    if apps is None:
        apps = ["Chrome"]

    return {
        "slug": slug,
        "title": title,
        "steps": steps,
        "variables": variables,
        "confidence_avg": confidence_avg,
        "episode_count": 5,
        "apps_involved": apps,
    }


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestFormatSOPWithFrontmatter:
    """Full YAML frontmatter generation."""

    def test_output_has_frontmatter(self):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        result = formatter.format_sop(template)

        # Must start with ---
        assert result.startswith("---\n")
        # Must have closing ---
        parts = result.split("---")
        assert len(parts) >= 3  # before, frontmatter, after

    def test_frontmatter_has_required_fields(self):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        result = formatter.format_sop(template)

        fm, _ = formatter._extract_frontmatter_and_body(result)

        assert fm["sop_version"] == 1
        assert fm["sop_slug"] == "test_workflow"
        assert fm["sop_title"] == "Test Workflow"
        assert "oc-apprentice" in fm["generated_by"]
        assert "generated_at" in fm
        assert fm["evidence_window"] == "last_30_days"
        assert "confidence_summary" in fm
        assert "confidence_score_avg" in fm
        assert "generated_body_hash" in fm
        assert fm["apps_involved"] == ["Chrome"]

    def test_body_contains_steps(self):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        result = formatter.format_sop(template)

        _, body = formatter._extract_frontmatter_and_body(result)

        assert "Submit button" in body
        assert "Email field" in body
        assert "Click" in body
        assert "Type" in body

    def test_body_has_numbered_steps(self):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        result = formatter.format_sop(template)

        _, body = formatter._extract_frontmatter_and_body(result)

        assert "1. **Click**" in body
        assert "2. **Type**" in body


class TestBodyHashComputation:
    """SHA-256 hash of body content."""

    def test_hash_is_sha256_prefixed(self):
        formatter = SOPFormatter()
        body = "# Test\n\nSome content"
        result = formatter._compute_body_hash(body)

        assert result.startswith("sha256:")
        hex_part = result[7:]
        assert len(hex_part) == 64  # SHA-256 hex digest length

    def test_hash_is_deterministic(self):
        formatter = SOPFormatter()
        body = "# Test\n\nSome content"
        h1 = formatter._compute_body_hash(body)
        h2 = formatter._compute_body_hash(body)
        assert h1 == h2

    def test_hash_changes_with_content(self):
        formatter = SOPFormatter()
        h1 = formatter._compute_body_hash("Content A")
        h2 = formatter._compute_body_hash("Content B")
        assert h1 != h2

    def test_hash_normalizes_line_endings(self):
        formatter = SOPFormatter()
        h1 = formatter._compute_body_hash("line1\nline2\n")
        h2 = formatter._compute_body_hash("line1\r\nline2\n")
        assert h1 == h2


class TestManualEditDetectionNoEdit:
    """Hash matches -> no edit detected."""

    def test_no_edit_detected(self, tmp_path: Path):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        content = formatter.format_sop(template)

        filepath = tmp_path / "test_sop.md"
        filepath.write_text(content, encoding="utf-8")

        was_edited, reason = formatter.detect_manual_edit(str(filepath))
        assert was_edited is False
        assert reason == "hash_matches"


class TestManualEditDetectionEdited:
    """Hash mismatch -> edit detected."""

    def test_edit_detected(self, tmp_path: Path):
        formatter = SOPFormatter()
        template = _sample_sop_template()
        content = formatter.format_sop(template)

        filepath = tmp_path / "test_sop.md"
        filepath.write_text(content, encoding="utf-8")

        # Simulate manual edit by appending to body
        modified = content + "\n\n<!-- Human note: reviewed and approved -->"
        filepath.write_text(modified, encoding="utf-8")

        was_edited, reason = formatter.detect_manual_edit(str(filepath))
        assert was_edited is True
        assert reason == "body_hash_mismatch"


class TestFrontmatterExtraction:
    """Parse existing SOP file into frontmatter and body."""

    def test_extracts_frontmatter_and_body(self):
        formatter = SOPFormatter()
        content = "---\nsop_version: 1\nsop_slug: test\n---\n\n# Title\n\nBody here"
        fm, body = formatter._extract_frontmatter_and_body(content)

        assert fm["sop_version"] == 1
        assert fm["sop_slug"] == "test"
        assert "Title" in body
        assert "Body here" in body

    def test_no_frontmatter(self):
        formatter = SOPFormatter()
        content = "# Just a markdown file\n\nNo frontmatter here."
        fm, body = formatter._extract_frontmatter_and_body(content)

        assert fm == {}
        assert "Just a markdown file" in body


class TestConfidenceSummary:
    """High/medium/low classification."""

    def test_high_confidence(self):
        formatter = SOPFormatter()
        assert formatter._confidence_label(0.90) == "high"
        assert formatter._confidence_label(0.85) == "high"

    def test_medium_confidence(self):
        formatter = SOPFormatter()
        assert formatter._confidence_label(0.70) == "medium"
        assert formatter._confidence_label(0.60) == "medium"

    def test_low_confidence(self):
        formatter = SOPFormatter()
        assert formatter._confidence_label(0.50) == "low"
        assert formatter._confidence_label(0.0) == "low"


class TestInputVariablesInFrontmatter:
    """Variables listed correctly in frontmatter."""

    def test_variables_appear_in_frontmatter(self):
        formatter = SOPFormatter()
        template = _sample_sop_template(
            variables=[
                {"name": "customer_name", "type": "string", "example": "Alice"},
                {"name": "order_id", "type": "number", "example": "12345"},
            ]
        )
        result = formatter.format_sop(template)
        fm, _ = formatter._extract_frontmatter_and_body(result)

        assert len(fm["input_variables"]) == 2
        var_names = [v["name"] for v in fm["input_variables"]]
        assert "customer_name" in var_names
        assert "order_id" in var_names

    def test_variable_types_preserved(self):
        formatter = SOPFormatter()
        template = _sample_sop_template(
            variables=[
                {"name": "count", "type": "number", "example": "42"},
            ]
        )
        result = formatter.format_sop(template)
        fm, _ = formatter._extract_frontmatter_and_body(result)

        var = fm["input_variables"][0]
        assert var["type"] == "number"
        assert var["example"] == "42"


class TestMissingFileNotEdited:
    """New file -> not edited."""

    def test_missing_file_returns_false(self, tmp_path: Path):
        formatter = SOPFormatter()
        was_edited, reason = formatter.detect_manual_edit(
            str(tmp_path / "nonexistent.md")
        )
        assert was_edited is False
        assert reason == "file_not_found"

    def test_file_without_hash_not_edited(self, tmp_path: Path):
        formatter = SOPFormatter()
        filepath = tmp_path / "no_hash.md"
        filepath.write_text("---\nsop_version: 1\n---\n\n# Content\n", encoding="utf-8")

        was_edited, reason = formatter.detect_manual_edit(str(filepath))
        assert was_edited is False
        assert reason == "no_hash_in_frontmatter"
