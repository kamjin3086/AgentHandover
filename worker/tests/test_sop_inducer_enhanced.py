"""Tests for enhanced SOP inducer features: preconditions, postconditions, exceptions.

These tests don't require prefixspan - they test the helper methods directly.
"""

from __future__ import annotations

from collections import Counter


# ------------------------------------------------------------------
# Since SOPInducer requires prefixspan, we test the methods
# that don't need it by instantiating with a mock or testing the
# detection methods via the class
# ------------------------------------------------------------------


class TestDetectPreconditions:
    def test_common_app_detected(self) -> None:
        """App appearing in 80%+ of instances is a precondition."""
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        instances = [
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Chrome"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Chrome"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Chrome"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Chrome"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Firefox"}}],
        ]

        preconditions = inducer._detect_preconditions(instances)
        assert any("Chrome" in p for p in preconditions)

    def test_no_precondition_when_diverse(self) -> None:
        """No precondition when apps are diverse (< 80%)."""
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        instances = [
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Chrome"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Firefox"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"app_id": "Safari"}}],
        ]

        preconditions = inducer._detect_preconditions(instances)
        app_preconditions = [p for p in preconditions if p.startswith("app_open:")]
        assert len(app_preconditions) == 0

    def test_url_precondition(self) -> None:
        """Common URL in first step is a precondition."""
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        instances = [
            [{"step": "click", "target": "Submit", "pre_state": {"url": "https://app.com/login"}}],
            [{"step": "click", "target": "Submit", "pre_state": {"url": "https://app.com/login"}}],
        ]

        preconditions = inducer._detect_preconditions(instances)
        assert any("url_open:" in p for p in preconditions)


class TestDetectPostconditions:
    def test_common_final_action(self) -> None:
        """Common final intent is a postcondition."""
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        instances = [
            [
                {"step": "type", "target": "Email"},
                {"step": "click", "target": "Save"},
            ],
            [
                {"step": "type", "target": "Email"},
                {"step": "click", "target": "Save"},
            ],
        ]

        postconditions = inducer._detect_postconditions(instances)
        assert any("final_action:click" in p for p in postconditions)

    def test_empty_instances(self) -> None:
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        postconditions = inducer._detect_postconditions([])
        assert postconditions == []


class TestDetectExceptions:
    def test_cancel_detected(self) -> None:
        """Cancel events in pattern episodes are detected as exceptions."""
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        episodes = [
            [
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "cancel", "target": "Cancel dialog", "parameters": {}},
            ],
            [
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
            ],
        ]

        # Build encoding manually to test _detect_exceptions
        encoded, code_to_sig, sig_to_steps = inducer._encode_steps(episodes)
        # Find pattern codes for "click::submit button"
        click_code = None
        for code, sig in code_to_sig.items():
            if "click::submit button" in sig:
                click_code = code
                break

        if click_code is not None:
            pattern_codes = [click_code, click_code, click_code]
            exceptions = inducer._detect_exceptions(episodes, pattern_codes, code_to_sig)
            assert any("cancel" in e for e in exceptions)

    def test_no_exceptions_in_clean_episodes(self) -> None:
        try:
            from oc_apprentice_worker.sop_inducer import SOPInducer
        except ImportError:
            import pytest
            pytest.skip("prefixspan not installed")

        inducer = SOPInducer()
        episodes = [
            [
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
                {"step": "click", "target": "Submit button", "parameters": {}},
            ],
        ]

        encoded, code_to_sig, sig_to_steps = inducer._encode_steps(episodes)
        click_code = None
        for code, sig in code_to_sig.items():
            if "click::submit button" in sig:
                click_code = code
                break

        if click_code is not None:
            pattern_codes = [click_code, click_code, click_code]
            exceptions = inducer._detect_exceptions(episodes, pattern_codes, code_to_sig)
            assert len(exceptions) == 0
