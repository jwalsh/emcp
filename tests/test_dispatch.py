"""Tests for src/dispatch.py — emacsclient subprocess boundary.

These tests mock subprocess.run since a live Emacs daemon is not
guaranteed in the test environment.
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from dispatch import eval_in_emacs, EmacsClientError


class TestEvalInEmacs:
    """eval_in_emacs wraps emacsclient --eval as a pure subprocess call."""

    @patch("dispatch.subprocess.run")
    def test_successful_eval(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout='"2"\n',
            stderr="",
        )
        result = eval_in_emacs("(+ 1 1)")
        assert result == '"2"'
        mock_run.assert_called_once_with(
            ["emacsclient", "--eval", "(+ 1 1)"],
            capture_output=True,
            text=True,
            timeout=10,
        )

    @patch("dispatch.subprocess.run")
    def test_nonzero_exit_raises(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1,
            stdout="",
            stderr="emacsclient: connect: Connection refused\n",
        )
        with pytest.raises(EmacsClientError, match="exit 1"):
            eval_in_emacs("(+ 1 1)")

    @patch("dispatch.subprocess.run")
    def test_emacsclient_not_found(self, mock_run):
        mock_run.side_effect = FileNotFoundError()
        with pytest.raises(EmacsClientError, match="not found on PATH"):
            eval_in_emacs("(+ 1 1)")

    @patch("dispatch.subprocess.run")
    def test_timeout_raises(self, mock_run):
        mock_run.side_effect = subprocess.TimeoutExpired(
            cmd=["emacsclient", "--eval", "(sleep-for 999)"],
            timeout=10,
        )
        with pytest.raises(EmacsClientError, match="timed out after 10s"):
            eval_in_emacs("(sleep-for 999)")

    @patch("dispatch.subprocess.run")
    def test_custom_timeout(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout='"done"\n',
            stderr="",
        )
        eval_in_emacs("(some-long-op)", timeout=30)
        mock_run.assert_called_once_with(
            ["emacsclient", "--eval", "(some-long-op)"],
            capture_output=True,
            text=True,
            timeout=30,
        )

    @patch("dispatch.subprocess.run")
    def test_strips_trailing_whitespace(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout='  "hello"  \n',
            stderr="",
        )
        result = eval_in_emacs('(identity "hello")')
        assert result == '"hello"'

    @patch("dispatch.subprocess.run")
    def test_stderr_in_error_message(self, mock_run):
        mock_run.return_value = MagicMock(
            returncode=1,
            stdout="",
            stderr="  Symbol's function definition is void: nonexistent  \n",
        )
        with pytest.raises(EmacsClientError, match="void: nonexistent"):
            eval_in_emacs("(nonexistent)")
