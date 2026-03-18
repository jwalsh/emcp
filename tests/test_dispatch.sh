#!/usr/bin/env bash
# tests/test_dispatch.sh — validate emcp-stdio.el dispatch contracts
#
# Sends JSON-RPC 2.0 messages to the pure-Elisp MCP server and validates
# responses against the contract in docs/contracts/dispatch.md.
#
# Usage:
#   bash tests/test_dispatch.sh
#
# Requirements:
#   - emacs on PATH
#   - jq on PATH
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

# --- Config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_EL="$PROJECT_DIR/src/emcp-stdio.el"

PASS=0
FAIL=0
TOTAL=0

# --- Helpers ---

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN=''
    RED=''
    BOLD=''
    RESET=''
fi

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "${GREEN}PASS${RESET} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "${RED}FAIL${RESET} %s\n" "$1"
    if [ -n "${2:-}" ]; then
        printf "     %s\n" "$2"
    fi
}

# send_messages INPUT_STRING
#   Feeds INPUT_STRING (newline-delimited JSON) to the emcp-stdio server.
#   Returns stdout lines (JSON responses). Stderr is captured separately.
#   Uses -Q (vanilla Emacs, no init) to keep tool count small and fast.
send_messages() {
    local input="$1"
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    # shellcheck disable=SC2086
    printf '%s\n' "$input" | emacs --batch -Q \
        -l "$SERVER_EL" \
        -f emcp-stdio-start \
        >"$stdout_file" 2>"$stderr_file" || true

    cat "$stdout_file"
    rm -f "$stdout_file" "$stderr_file"
}

# send_single MESSAGE
#   Send a single JSON-RPC message. Returns the single response line.
send_single() {
    send_messages "$1"
}

# Check prerequisites
check_prereqs() {
    if ! command -v emacs &>/dev/null; then
        echo "ERROR: emacs not found on PATH"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq not found on PATH"
        exit 1
    fi
    if [ ! -f "$SERVER_EL" ]; then
        echo "ERROR: $SERVER_EL not found"
        exit 1
    fi
}

# --- Tests ---

test_initialize() {
    local desc="initialize returns protocolVersion, capabilities.tools, serverInfo"
    local msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Check jsonrpc field
    local jsonrpc
    jsonrpc=$(echo "$resp" | jq -r '.jsonrpc' 2>/dev/null)
    if [ "$jsonrpc" != "2.0" ]; then
        fail "$desc" "jsonrpc=$jsonrpc, expected 2.0"
        return
    fi

    # Check id matches
    local resp_id
    resp_id=$(echo "$resp" | jq -r '.id' 2>/dev/null)
    if [ "$resp_id" != "1" ]; then
        fail "$desc" "id=$resp_id, expected 1"
        return
    fi

    # Check protocolVersion
    local proto
    proto=$(echo "$resp" | jq -r '.result.protocolVersion' 2>/dev/null)
    if [ "$proto" != "2024-11-05" ]; then
        fail "$desc" "protocolVersion=$proto"
        return
    fi

    # Check capabilities.tools exists (should be an object, possibly empty)
    local tools_type
    tools_type=$(echo "$resp" | jq -r '.result.capabilities.tools | type' 2>/dev/null)
    if [ "$tools_type" != "object" ]; then
        fail "$desc" "capabilities.tools type=$tools_type, expected object"
        return
    fi

    # Check serverInfo
    local server_name server_version
    server_name=$(echo "$resp" | jq -r '.result.serverInfo.name' 2>/dev/null)
    server_version=$(echo "$resp" | jq -r '.result.serverInfo.version' 2>/dev/null)
    if [ "$server_name" = "null" ] || [ -z "$server_name" ]; then
        fail "$desc" "serverInfo.name missing"
        return
    fi
    if [ "$server_version" = "null" ] || [ -z "$server_version" ]; then
        fail "$desc" "serverInfo.version missing"
        return
    fi

    pass "$desc"
}

test_notification_no_response() {
    local desc="notification (no id) produces no output"
    # Send a notification (no id field) followed by a request (with id).
    # We should get exactly one response line (for the request), not two.
    local input
    input=$(printf '%s\n%s' \
        '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
        '{"jsonrpc":"2.0","id":99,"method":"ping"}')

    local resp
    resp=$(send_messages "$input")

    # Count non-empty lines
    local line_count
    line_count=$(echo "$resp" | grep -c '^{' || true)

    if [ "$line_count" -ne 1 ]; then
        fail "$desc" "expected 1 response line, got $line_count"
        return
    fi

    # The one response should have id=99 (from the ping)
    local resp_id
    resp_id=$(echo "$resp" | grep '^{' | jq -r '.id' 2>/dev/null)
    if [ "$resp_id" != "99" ]; then
        fail "$desc" "response id=$resp_id, expected 99"
        return
    fi

    pass "$desc"
}

test_unknown_method() {
    local desc="unknown method returns -32601 error"
    local msg='{"jsonrpc":"2.0","id":2,"method":"bogus/nonexistent","params":{}}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Should have error field, not result
    local has_error
    has_error=$(echo "$resp" | jq 'has("error")' 2>/dev/null)
    if [ "$has_error" != "true" ]; then
        fail "$desc" "response has no error field"
        return
    fi

    # Error code should be -32601
    local code
    code=$(echo "$resp" | jq -r '.error.code' 2>/dev/null)
    if [ "$code" != "-32601" ]; then
        fail "$desc" "error code=$code, expected -32601"
        return
    fi

    # Error message should mention the method
    local error_msg
    error_msg=$(echo "$resp" | jq -r '.error.message' 2>/dev/null)
    if ! echo "$error_msg" | grep -q "bogus/nonexistent"; then
        fail "$desc" "error message doesn't mention method: $error_msg"
        return
    fi

    pass "$desc"
}

test_tools_call_valid() {
    local desc="tools/call with valid function returns content array"
    # upcase is a built-in Elisp function that takes a string, should be
    # available in vanilla -Q mode and pass the text-consumer filter.
    local msg='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"upcase","arguments":{"args":["hello"]}}}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Should have result, not error
    local has_result
    has_result=$(echo "$resp" | jq 'has("result")' 2>/dev/null)
    if [ "$has_result" != "true" ]; then
        fail "$desc" "response has no result field"
        return
    fi

    # result.content should be an array
    local content_type
    content_type=$(echo "$resp" | jq -r '.result.content | type' 2>/dev/null)
    if [ "$content_type" != "array" ]; then
        fail "$desc" "content type=$content_type, expected array"
        return
    fi

    # First element should have type="text"
    local elem_type
    elem_type=$(echo "$resp" | jq -r '.result.content[0].type' 2>/dev/null)
    if [ "$elem_type" != "text" ]; then
        fail "$desc" "content[0].type=$elem_type, expected text"
        return
    fi

    # The text should contain "HELLO" (upcase of "hello")
    local text
    text=$(echo "$resp" | jq -r '.result.content[0].text' 2>/dev/null)
    if ! echo "$text" | grep -q "HELLO"; then
        fail "$desc" "expected HELLO in text, got: $text"
        return
    fi

    pass "$desc"
}

test_tools_call_nonexistent() {
    local desc="tools/call with nonexistent function returns error in content"
    local msg='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"this-function-does-not-exist-xyz","arguments":{"args":[]}}}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Should be a result (not a JSON-RPC error) — the error is in content
    local has_result
    has_result=$(echo "$resp" | jq 'has("result")' 2>/dev/null)
    if [ "$has_result" != "true" ]; then
        fail "$desc" "expected result (error in content), got JSON-RPC error"
        return
    fi

    # content[0].text should contain "error"
    local text
    text=$(echo "$resp" | jq -r '.result.content[0].text' 2>/dev/null)
    if ! echo "$text" | grep -qi "error"; then
        fail "$desc" "expected error in content text, got: $text"
        return
    fi

    pass "$desc"
}

test_tools_call_bad_args() {
    local desc="tools/call with bad args returns error in content (not crash)"
    # Call concat with no args — should work actually, but let's test
    # something that will error: call a function that requires args with
    # wrong types. We use string-to-number with no args by calling a
    # function that expects exactly one arg with zero args.
    # Actually, let's use a simpler approach: call substring with bad indices.
    local msg='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"substring","arguments":{"args":["hello","not-a-number"]}}}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Should be a result (error caught in content), not a crash
    local has_result
    has_result=$(echo "$resp" | jq 'has("result")' 2>/dev/null)
    if [ "$has_result" != "true" ]; then
        fail "$desc" "expected result with error in content, got JSON-RPC error or crash"
        return
    fi

    # content[0].text should indicate an error
    local text
    text=$(echo "$resp" | jq -r '.result.content[0].text' 2>/dev/null)
    if ! echo "$text" | grep -qi "error"; then
        fail "$desc" "expected error in content, got: $text"
        return
    fi

    pass "$desc"
}

test_ping() {
    local desc="ping returns empty object"
    local msg='{"jsonrpc":"2.0","id":6,"method":"ping"}'
    local resp
    resp=$(send_single "$msg")

    if [ -z "$resp" ]; then
        fail "$desc" "no response received"
        return
    fi

    # Check id
    local resp_id
    resp_id=$(echo "$resp" | jq -r '.id' 2>/dev/null)
    if [ "$resp_id" != "6" ]; then
        fail "$desc" "id=$resp_id, expected 6"
        return
    fi

    # result should be an empty object {}
    local result_type result_len
    result_type=$(echo "$resp" | jq -r '.result | type' 2>/dev/null)
    result_len=$(echo "$resp" | jq -r '.result | length' 2>/dev/null)
    if [ "$result_type" != "object" ]; then
        fail "$desc" "result type=$result_type, expected object"
        return
    fi
    if [ "$result_len" != "0" ]; then
        fail "$desc" "result has $result_len keys, expected 0"
        return
    fi

    pass "$desc"
}

test_sequential_ids() {
    local desc="multiple sequential requests each get the correct id back"
    # Send three requests with different ids in one session
    local input
    input=$(printf '%s\n%s\n%s' \
        '{"jsonrpc":"2.0","id":10,"method":"ping"}' \
        '{"jsonrpc":"2.0","id":20,"method":"ping"}' \
        '{"jsonrpc":"2.0","id":30,"method":"ping"}')

    local resp
    resp=$(send_messages "$input")

    # Should get 3 response lines
    local line_count
    line_count=$(echo "$resp" | grep -c '^{' || true)
    if [ "$line_count" -ne 3 ]; then
        fail "$desc" "expected 3 responses, got $line_count"
        return
    fi

    # Extract ids in order
    local ids
    ids=$(echo "$resp" | grep '^{' | jq -r '.id' 2>/dev/null | tr '\n' ' ')

    # All three ids should be present (order should match input order)
    if ! echo "$ids" | grep -q "10"; then
        fail "$desc" "id 10 missing from responses: $ids"
        return
    fi
    if ! echo "$ids" | grep -q "20"; then
        fail "$desc" "id 20 missing from responses: $ids"
        return
    fi
    if ! echo "$ids" | grep -q "30"; then
        fail "$desc" "id 30 missing from responses: $ids"
        return
    fi

    pass "$desc"
}

# --- Main ---

main() {
    check_prereqs

    printf "${BOLD}=== emcp-stdio.el dispatch contract tests ===${RESET}\n\n"

    test_initialize
    test_notification_no_response
    test_unknown_method
    test_tools_call_valid
    test_tools_call_nonexistent
    test_tools_call_bad_args
    test_ping
    test_sequential_ids

    printf "\n${BOLD}--- Results ---${RESET}\n"
    printf "Total: %d  Passed: %d  Failed: %d\n" "$TOTAL" "$PASS" "$FAIL"

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
