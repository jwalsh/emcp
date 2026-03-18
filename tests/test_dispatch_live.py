"""Live integration tests for dispatch.py — requires running Emacs daemon.

Skip with: pytest -m "not live"
Run with:  PYTHONPATH=src pytest tests/test_dispatch_live.py -v
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from dispatch import eval_in_emacs, EmacsClientError
from escape import build_call


def emacs_available():
    try:
        eval_in_emacs("(emacs-pid)")
        return True
    except EmacsClientError:
        return False


pytestmark = pytest.mark.skipif(
    not emacs_available(), reason="Emacs daemon not running"
)


class TestLiveDispatch:
    """Integration tests against a live Emacs daemon."""

    def test_basic_arithmetic(self):
        assert eval_in_emacs("(+ 1 1)") == "2"

    def test_string_trim(self):
        sexp = build_call("string-trim", " hello ")
        result = eval_in_emacs(sexp)
        assert result == '"hello"'

    def test_identity_roundtrip(self):
        sexp = build_call("identity", "test string")
        result = eval_in_emacs(sexp)
        assert result == '"test string"'


class TestNonAsciiRoundTrip:
    """C-004: non-ASCII survives escape -> emacsclient -> Emacs -> stdout."""

    def test_cjk(self):
        sexp = build_call("identity", "\u4f60\u597d")
        result = eval_in_emacs(sexp)
        assert "\u4f60\u597d" in result

    def test_emoji(self):
        sexp = build_call("identity", "\U0001f680")
        result = eval_in_emacs(sexp)
        assert "\U0001f680" in result

    def test_combining_characters(self):
        sexp = build_call("identity", "e\u0301")
        result = eval_in_emacs(sexp)
        assert "e\u0301" in result or "\u00e9" in result
