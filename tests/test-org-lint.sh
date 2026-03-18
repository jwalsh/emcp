#!/usr/bin/env bash
# test-org-lint.sh --- Run org-mode linter and report results
#
# Usage:
#   bash tests/test-org-lint.sh
#
# Exit codes:
#   0 - all checks passed (warnings are ok)
#   1 - errors found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== org-lint: checking org files in $PROJECT_ROOT ==="

cd "$PROJECT_ROOT"
emacs --batch -Q -l lisp/org-lint-batch.el -f emcp-org-lint-batch
