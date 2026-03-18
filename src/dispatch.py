"""dispatch.py — emacsclient subprocess boundary."""

import subprocess


class EmacsClientError(RuntimeError):
    pass


def eval_in_emacs(sexp: str, timeout: int = 10) -> str:
    """Evaluate SEXP via emacsclient and return result as string.

    Raises EmacsClientError on non-zero exit or timeout.
    """
    try:
        result = subprocess.run(
            ["emacsclient", "--eval", sexp],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        raise EmacsClientError("emacsclient not found on PATH")
    except subprocess.TimeoutExpired:
        raise EmacsClientError(f"emacsclient timed out after {timeout}s")

    if result.returncode != 0:
        raise EmacsClientError(
            f"emacsclient exit {result.returncode}: {result.stderr.strip()}"
        )
    return result.stdout.strip()
