#!/usr/bin/env bash
# tests/test_daemon_layer.sh -- Integration tests for daemon data layer
#
# Validates the daemon tool contracts defined in
# docs/contracts/daemon-data-layer.md
#
# Usage:
#   bash tests/test_daemon_layer.sh
#
# Prerequisites:
#   - Emacs daemon running (emacsclient --eval "(emacs-pid)" succeeds)
#   - src/emcp-stdio.el loadable by emacs --batch
#
# Exit codes:
#   0 = all tests passed (or skipped due to no daemon)
#   1 = one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EMCP_STDIO="$PROJECT_DIR/src/emcp-stdio.el"

PASS=0
FAIL=0
SKIP=0

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

pass() {
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo "  detail: $2"
    fi
}

skip() {
    SKIP=$((SKIP + 1))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

# ---------- Precondition checks ----------

if [ ! -f "$EMCP_STDIO" ]; then
    echo "ERROR: src/emcp-stdio.el not found at $EMCP_STDIO"
    exit 1
fi

# Check for daemon availability
DAEMON_AVAILABLE=false
if emacsclient --eval "(emacs-pid)" >/dev/null 2>&1; then
    DAEMON_AVAILABLE=true
    echo "Daemon detected. Running full test suite."
else
    echo "No daemon detected. Running daemon-absent tests only."
fi

# Helper: send a JSON-RPC request to the MCP server and capture the response.
# Uses emacs --batch to run the server, piping a single request via stdin.
mcp_call() {
    local json_request="$1"
    # Send initialize + the actual request + let stdin close
    local init='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}'
    echo -e "${init}\n${json_request}" | \
        emacs --batch -Q -l "$EMCP_STDIO" -f emcp-stdio-start 2>/dev/null
}

# Helper: extract the "text" field from an MCP tools/call response.
# Expects the second JSON line (first is initialize response).
extract_text() {
    local output="$1"
    # Get the second line (response to our actual request)
    local response_line
    response_line=$(echo "$output" | sed -n '2p')
    # Extract the text field -- simple pattern for well-formed output
    echo "$response_line" | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line:
    sys.exit(1)
resp = json.loads(line)
content = resp.get('result', {}).get('content', [])
if content:
    print(content[0].get('text', ''))
"
}

# ---------- Test 1: emcp-data-eval with (emacs-version) ----------

if $DAEMON_AVAILABLE; then
    echo ""
    echo "=== Daemon-present tests ==="

    # We need to test via the MCP protocol, so we run the batch server
    # with a daemon available.

    # Test 1: Direct emacsclient eval works (baseline)
    result=$(emacsclient --eval "(emacs-version)" 2>/dev/null) || true
    if echo "$result" | grep -q "GNU Emacs"; then
        pass "emacsclient eval (emacs-version) returns version string"
    else
        fail "emacsclient eval (emacs-version) did not return version" "$result"
    fi

    # Test 2: emcp-data-eval via MCP protocol returns version
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-eval","arguments":{"args":["(emacs-version)"]}}}') || true
    text=$(extract_text "$output") || true
    if echo "$text" | grep -q "GNU Emacs"; then
        pass "emcp-data-eval (emacs-version) via MCP returns version string"
    else
        fail "emcp-data-eval (emacs-version) via MCP" "got: $text"
    fi

    # Test 3: emcp-data-buffer-list returns tab-separated output
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-buffer-list","arguments":{"args":[]}}}') || true
    text=$(extract_text "$output") || true
    if echo "$text" | grep -q "	"; then
        pass "emcp-data-buffer-list returns tab-separated output"
    elif [ -n "$text" ] && [ "$text" != "error:"* ]; then
        # Buffer list might have buffers without files, so tabs may be present
        # but the output should at least contain *scratch* or *Messages*
        if echo "$text" | grep -qE '\*scratch\*|\*Messages\*'; then
            pass "emcp-data-buffer-list returns buffer names"
        else
            fail "emcp-data-buffer-list output unexpected" "got: $text"
        fi
    else
        fail "emcp-data-buffer-list returned error or empty" "got: $text"
    fi

    # Test 4: emcp-data-eval with special chars doesn't crash
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-eval","arguments":{"args":["(concat \"hello\" \" \" \"world\")"]}}}') || true
    text=$(extract_text "$output") || true
    if echo "$text" | grep -q "hello world"; then
        pass "emcp-data-eval with embedded quotes succeeds"
    else
        fail "emcp-data-eval with embedded quotes" "got: $text"
    fi

    # Test 5: emcp-data-find-file with /tmp/test-file.txt creates buffer
    TEST_FILE="/tmp/emcp-test-daemon-layer-$$"
    output=$(mcp_call "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"emcp-data-find-file\",\"arguments\":{\"args\":[\"$TEST_FILE\"]}}}") || true
    text=$(extract_text "$output") || true
    expected_bufname=$(basename "$TEST_FILE")
    if echo "$text" | grep -q "$expected_bufname"; then
        pass "emcp-data-find-file returns buffer name for new file"
    else
        fail "emcp-data-find-file" "expected buffer name containing '$expected_bufname', got: $text"
    fi
    # Clean up: kill the buffer in daemon
    emacsclient --eval "(when (get-buffer \"$expected_bufname\") (kill-buffer \"$expected_bufname\"))" >/dev/null 2>&1 || true
    rm -f "$TEST_FILE"

    # Test 6: Wrong arg count returns error, not crash
    # emcp-data-buffer-read expects 1 arg, send 0
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-buffer-read","arguments":{"args":[]}}}') || true
    text=$(extract_text "$output") || true
    # The response should exist (server didn't crash) -- it might be an error or nil buffer
    if [ -n "$text" ]; then
        pass "emcp-data-buffer-read with 0 args returns response (no crash)"
    else
        fail "emcp-data-buffer-read with 0 args: no response (possible crash)"
    fi

    # Test 7: emcp-data-eval with parentheses in sexp
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-eval","arguments":{"args":["(format \"%s(%s)\" \"a\" \"b\")"]}}}') || true
    text=$(extract_text "$output") || true
    if echo "$text" | grep -q "a(b)"; then
        pass "emcp-data-eval with parentheses in format string"
    else
        fail "emcp-data-eval with parentheses" "got: $text"
    fi

    # Test 8: Diagnostic line filtering
    # This is hard to trigger reliably, but we can verify the eval
    # path works end-to-end with a simple expression
    output=$(mcp_call '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-eval","arguments":{"args":["(+ 2 3)"]}}}') || true
    text=$(extract_text "$output") || true
    if [ "$text" = "5" ]; then
        pass "emcp-data-eval arithmetic returns clean result (no diagnostics)"
    else
        fail "emcp-data-eval arithmetic" "expected '5', got: '$text'"
    fi

else
    echo ""
    echo "=== Daemon-absent tests ==="
    skip "emacsclient eval -- no daemon"
    skip "emcp-data-eval via MCP -- no daemon"
    skip "emcp-data-buffer-list -- no daemon"
    skip "emcp-data-eval with special chars -- no daemon"
    skip "emcp-data-find-file -- no daemon"
    skip "emcp-data-buffer-read wrong args -- no daemon"
    skip "emcp-data-eval with parentheses -- no daemon"
    skip "emcp-data-eval arithmetic -- no daemon"
fi

# ---------- Daemon-absent tests (always run) ----------

echo ""
echo "=== Daemon-independent tests ==="

# Test: When daemon is not running, tools/list should NOT include daemon tools
# We force -Q (no init) and set a non-existent socket to ensure no daemon
output=$(echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | \
    EMACS_SOCKET_NAME="/tmp/nonexistent-emcp-test-socket-$$" \
    emacs --batch -Q -l "$EMCP_STDIO" -f emcp-stdio-start 2>/dev/null) || true

tools_line=$(echo "$output" | sed -n '2p')
if echo "$tools_line" | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
resp = json.loads(line)
tools = resp.get('result', {}).get('tools', [])
daemon_tools = [t for t in tools if t.get('name', '').startswith('emcp-data-')]
if daemon_tools:
    print('FOUND_DAEMON_TOOLS')
    sys.exit(1)
else:
    print('NO_DAEMON_TOOLS')
    sys.exit(0)
" 2>/dev/null; then
    pass "tools/list excludes daemon tools when no daemon"
else
    fail "tools/list should exclude daemon tools when no daemon" \
         "daemon tools found in tools/list"
fi

# Test: Calling daemon tool when no daemon returns error message
output=$(echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"emcp-data-eval","arguments":{"args":["(emacs-version)"]}}}' | \
    EMACS_SOCKET_NAME="/tmp/nonexistent-emcp-test-socket-$$" \
    emacs --batch -Q -l "$EMCP_STDIO" -f emcp-stdio-start 2>/dev/null) || true

text=$(echo "$output" | sed -n '2p' | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line:
    sys.exit(1)
resp = json.loads(line)
content = resp.get('result', {}).get('content', [])
if content:
    print(content[0].get('text', ''))
" 2>/dev/null) || true

if echo "$text" | grep -qi "no daemon\|daemon.*available\|not.*available"; then
    pass "daemon tool call without daemon returns 'no daemon' error"
elif echo "$text" | grep -qi "error"; then
    pass "daemon tool call without daemon returns error"
else
    fail "daemon tool call without daemon should return error" "got: $text"
fi

# Test: The server starts and responds to initialize even without daemon
output=$(echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}' | \
    EMACS_SOCKET_NAME="/tmp/nonexistent-emcp-test-socket-$$" \
    emacs --batch -Q -l "$EMCP_STDIO" -f emcp-stdio-start 2>/dev/null) || true

if echo "$output" | python3 -c "
import sys, json
line = sys.stdin.readline().strip()
resp = json.loads(line)
if resp.get('result', {}).get('protocolVersion'):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "server starts and responds to initialize without daemon"
else
    fail "server should start without daemon" "got: $output"
fi

# ---------- Summary ----------

echo ""
TOTAL=$((PASS + FAIL + SKIP))
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL)"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
