#!/usr/bin/env bash
# test_io_layer.sh --- Smoke tests for emcp-stdio.el I/O layer
#
# Pipes JSON-RPC messages through the MCP server and validates output.
# Self-contained: starts its own Emacs batch process per test.
# No external dependencies beyond: emacs, jq, bash.
#
# Usage:
#   bash tests/test_io_layer.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -euo pipefail

# --- Setup ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EMCP_STDIO="$PROJECT_ROOT/src/emcp-stdio.el"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check prerequisites
if ! command -v emacs &>/dev/null; then
    echo "SKIP: emacs not found in PATH"
    exit 0
fi

if [[ ! -f "$EMCP_STDIO" ]]; then
    echo "FAIL: $EMCP_STDIO not found"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "SKIP: jq not found in PATH (required for JSON validation)"
    exit 0
fi

# --- Helpers ---

run_server() {
    # Run emcp-stdio with given single-line stdin, capture stdout and stderr.
    # The server exits naturally when stdin reaches EOF (pipe closes).
    # Args: stdin_content (single line)
    # Sets: STDOUT, STDERR, EXIT_CODE
    local input="$1"
    local tmpout tmpout_err
    tmpout="$(mktemp)"
    tmpout_err="$(mktemp)"

    set +e
    printf '%s\n' "$input" | emacs --batch -Q \
        -l "$EMCP_STDIO" \
        -f emcp-stdio-start \
        >"$tmpout" 2>"$tmpout_err"
    EXIT_CODE=$?
    set -e

    STDOUT="$(cat "$tmpout")"
    STDERR="$(cat "$tmpout_err")"
    rm -f "$tmpout" "$tmpout_err"
}

run_server_multiline() {
    # Run emcp-stdio with multi-line stdin (one JSON-RPC message per line).
    # Args: stdin_content (newline-separated messages)
    # Sets: STDOUT, STDERR, EXIT_CODE
    local input="$1"
    local tmpout tmpout_err tmpin
    tmpout="$(mktemp)"
    tmpout_err="$(mktemp)"
    tmpin="$(mktemp)"

    # Write input to a file to preserve exact newlines
    printf '%s\n' "$input" > "$tmpin"

    set +e
    emacs --batch -Q \
        -l "$EMCP_STDIO" \
        -f emcp-stdio-start \
        <"$tmpin" >"$tmpout" 2>"$tmpout_err"
    EXIT_CODE=$?
    set -e

    STDOUT="$(cat "$tmpout")"
    STDERR="$(cat "$tmpout_err")"
    rm -f "$tmpout" "$tmpout_err" "$tmpin"
}

# Find the response line matching a given id from STDOUT
find_response_by_id() {
    local target_id="$1"
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]] && echo "$line" | jq -e ".id == $target_id" &>/dev/null 2>&1; then
            echo "$line"
            return 0
        fi
    done <<< "$STDOUT"
    return 1
}

assert_json_valid() {
    local label="$1"
    local json_str="$2"
    if [[ -z "$json_str" ]]; then
        echo "  ASSERTION FAILED [$label]: empty string is not valid JSON"
        return 1
    fi
    if echo "$json_str" | jq . &>/dev/null; then
        return 0
    else
        echo "  ASSERTION FAILED [$label]: not valid JSON: $json_str"
        return 1
    fi
}

assert_json_field() {
    local label="$1"
    local json_str="$2"
    local field="$3"
    local expected="$4"

    local actual
    actual="$(echo "$json_str" | jq -r ".$field")"
    if [[ "$actual" == "$expected" ]]; then
        return 0
    else
        echo "  ASSERTION FAILED [$label]: .$field = '$actual', expected '$expected'"
        return 1
    fi
}

assert_json_has_key() {
    local label="$1"
    local json_str="$2"
    local key="$3"

    if echo "$json_str" | jq -e "has(\"$key\")" &>/dev/null; then
        return 0
    else
        echo "  ASSERTION FAILED [$label]: missing key '$key'"
        return 1
    fi
}

assert_json_not_has_key() {
    local label="$1"
    local json_str="$2"
    local key="$3"

    if echo "$json_str" | jq -e "has(\"$key\") | not" &>/dev/null; then
        return 0
    else
        echo "  ASSERTION FAILED [$label]: unexpected key '$key' present"
        return 1
    fi
}

test_begin() {
    TOTAL=$((TOTAL + 1))
    printf "${YELLOW}TEST %d${NC}: %s ... " "$TOTAL" "$1"
}

test_pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}PASS${NC}\n"
}

test_fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}FAIL${NC}\n"
    if [[ -n "${1:-}" ]]; then
        echo "  $1"
    fi
}

# --- Tests ---

# Test 1: Initialize handshake produces valid JSON-RPC
test_begin "initialize handshake produces valid JSON-RPC"
run_server '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
first_line="$(echo "$STDOUT" | head -n1)"
if assert_json_valid "valid json" "$first_line" && \
   assert_json_field "jsonrpc" "$first_line" "jsonrpc" "2.0" && \
   assert_json_field "id" "$first_line" "id" "1" && \
   assert_json_has_key "result" "$first_line" "result"; then
    test_pass
else
    test_fail
fi

# Test 2: Response contains jsonrpc, id, result — no error key
test_begin "response contains jsonrpc, id, result keys (no error)"
run_server '{"jsonrpc":"2.0","id":42,"method":"initialize","params":{}}'
first_line="$(echo "$STDOUT" | head -n1)"
if assert_json_has_key "has jsonrpc" "$first_line" "jsonrpc" && \
   assert_json_has_key "has id" "$first_line" "id" && \
   assert_json_has_key "has result" "$first_line" "result" && \
   assert_json_not_has_key "no error" "$first_line" "error"; then
    test_pass
else
    test_fail
fi

# Test 3: Non-ASCII round-trip (accented Latin characters via upcase)
test_begin "non-ASCII round-trip (accented Latin characters)"
INPUT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"upcase","arguments":{"args":["caf\u00e9"]}}}'
run_server_multiline "$INPUT"
response_line="$(find_response_by_id 2 || true)"
if [[ -n "$response_line" ]]; then
    if assert_json_valid "valid json" "$response_line" && \
       assert_json_has_key "has result" "$response_line" "result"; then
        result_text="$(echo "$response_line" | jq -r '.result.content[0].text')"
        if [[ "$result_text" == *"CAF"* ]]; then
            test_pass
        else
            test_fail "upcase result='$result_text', expected to contain 'CAF'"
        fi
    else
        test_fail "response not valid JSON-RPC"
    fi
else
    test_fail "no response found for id=2. STDOUT: $STDOUT"
fi

# Test 4: Emoji round-trip (concat two emoji)
test_begin "emoji round-trip"
# Use direct UTF-8 emoji bytes rather than JSON surrogate pairs
INPUT=$(printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"concat","arguments":{"args":["\xf0\x9f\x98\x80","\xf0\x9f\x9a\x80"]}}}')
run_server_multiline "$INPUT"
response_line="$(find_response_by_id 2 || true)"
if [[ -n "$response_line" ]]; then
    if assert_json_valid "valid json" "$response_line"; then
        result_text="$(echo "$response_line" | jq -r '.result.content[0].text')"
        if [[ -n "$result_text" && "$result_text" != "null" ]]; then
            test_pass
        else
            test_fail "empty or null result for emoji concat"
        fi
    else
        test_fail "response not valid JSON"
    fi
else
    test_fail "no response found for id=2. STDOUT: $STDOUT"
fi

# Test 5: Empty args handled
test_begin "empty args handled"
INPUT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"concat","arguments":{"args":[]}}}'
run_server_multiline "$INPUT"
response_line="$(find_response_by_id 2 || true)"
if [[ -n "$response_line" ]]; then
    if assert_json_valid "valid json" "$response_line" && \
       assert_json_has_key "has result" "$response_line" "result"; then
        test_pass
    else
        test_fail "response for empty args not valid JSON-RPC"
    fi
else
    test_fail "no response found for id=2. STDOUT: $STDOUT"
fi

# Test 6: Malformed JSON produces error on stderr, nothing on stdout
test_begin "malformed JSON returns parse error on stderr (not stdout)"
run_server 'this is not json at all{{'
stdout_trimmed="$(echo "$STDOUT" | tr -d '[:space:]')"
if [[ -z "$stdout_trimmed" ]]; then
    if echo "$STDERR" | grep -qi "parse\|json\|error" 2>/dev/null; then
        test_pass
    else
        test_fail "stderr doesn't mention parse/json error. STDERR: $STDERR"
    fi
else
    test_fail "stdout should be empty for malformed input but got: $STDOUT"
fi

# Test 7: Unknown method returns JSON-RPC error response with -32601
test_begin "unknown method returns JSON-RPC error with code -32601"
run_server '{"jsonrpc":"2.0","id":1,"method":"nonexistent/method","params":{}}'
first_line="$(echo "$STDOUT" | head -n1)"
if assert_json_valid "valid json" "$first_line" && \
   assert_json_has_key "has error" "$first_line" "error" && \
   assert_json_not_has_key "no result" "$first_line" "result"; then
    error_code="$(echo "$first_line" | jq '.error.code')"
    if [[ "$error_code" == "-32601" ]]; then
        test_pass
    else
        test_fail "error code = $error_code, expected -32601"
    fi
else
    test_fail "response not a valid JSON-RPC error"
fi

# Test 8: Notification (no id) produces no response on stdout
test_begin "notification (no id) produces no response on stdout"
run_server '{"jsonrpc":"2.0","method":"notifications/initialized"}'
stdout_trimmed="$(echo "$STDOUT" | tr -d '[:space:]')"
if [[ -z "$stdout_trimmed" ]]; then
    test_pass
else
    test_fail "expected no stdout for notification, got: $STDOUT"
fi

# Test 9: Multiple requests produce one JSON line each
test_begin "each stdout line is exactly one JSON object"
INPUT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"ping"}'
run_server_multiline "$INPUT"
all_valid=true
line_count=0
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        line_count=$((line_count + 1))
        if ! echo "$line" | jq . &>/dev/null; then
            all_valid=false
            echo "  invalid JSON on line $line_count: $line"
        fi
    fi
done <<< "$STDOUT"
if $all_valid && [[ $line_count -ge 2 ]]; then
    test_pass
else
    if [[ $line_count -lt 2 ]]; then
        test_fail "expected >= 2 response lines, got $line_count. STDOUT: $STDOUT"
    else
        test_fail "some lines were not valid JSON"
    fi
fi

# Test 10: Ping response is valid JSON-RPC with empty result
test_begin "ping response has empty result object"
run_server '{"jsonrpc":"2.0","id":1,"method":"ping"}'
first_line="$(echo "$STDOUT" | head -n1)"
if assert_json_valid "valid json" "$first_line" && \
   assert_json_field "jsonrpc" "$first_line" "jsonrpc" "2.0" && \
   assert_json_field "id" "$first_line" "id" "1" && \
   assert_json_has_key "has result" "$first_line" "result"; then
    result_keys="$(echo "$first_line" | jq '.result | keys | length')"
    if [[ "$result_keys" == "0" ]]; then
        test_pass
    else
        test_fail "ping result has $result_keys keys, expected 0"
    fi
else
    test_fail
fi

# Test 11: tools/list returns result with tools array
test_begin "tools/list returns result with tools array"
INPUT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
run_server_multiline "$INPUT"
response_line="$(find_response_by_id 2 || true)"
if [[ -n "$response_line" ]]; then
    tools_type="$(echo "$response_line" | jq -r '.result.tools | type')"
    if [[ "$tools_type" == "array" ]]; then
        tool_count="$(echo "$response_line" | jq '.result.tools | length')"
        printf "(%s tools) " "$tool_count"
        test_pass
    else
        test_fail "result.tools type = '$tools_type', expected 'array'"
    fi
else
    test_fail "no response for tools/list. STDOUT: $STDOUT"
fi

# --- Summary ---

echo ""
echo "======================================="
printf "Results: ${GREEN}%d passed${NC}" "$PASS"
if [[ $FAIL -gt 0 ]]; then
    printf ", ${RED}%d failed${NC}" "$FAIL"
fi
printf " / %d total\n" "$TOTAL"
echo "======================================="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
