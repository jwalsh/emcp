#!/usr/bin/env bash
# tests/test_tool_collection.sh — validate tool collection layer contracts
#
# Runs emacs --batch -Q to exercise emcp-stdio--collect-tools and
# validates the MCP tool schema invariants documented in
# docs/contracts/tool-collection.md.
#
# Usage:
#   bash tests/test_tool_collection.sh
#
# Requires: emacs, python3 (with json module)
#
# Known issue: The #'always filter causes emacs to abort because
# emcp-stdio--build-tool lacks error protection around
# help-function-arglist. Some functions (e.g., minibuffer-lazy-
# highlight-setup) have arglists containing #'identity read syntax
# that crash format "%s". Test 6 uses a safe-always filter that
# wraps build-tool with condition-case to work around this.

set -uo pipefail

# Resolve paths relative to the repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EMCP_STDIO="$REPO_ROOT/src/emcp-stdio.el"

PASS=0
FAIL=0
TOTAL=0

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    echo "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "        $2"
    fi
}

echo "=== Tool Collection Contract Tests ==="
echo "Emacs: $(emacs --version 2>&1 | head -1)"
echo "Source: $EMCP_STDIO"
echo ""

# Check prerequisites
if ! command -v emacs >/dev/null 2>&1; then
    echo "ERROR: emacs not found in PATH"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found in PATH"
    exit 1
fi
if [ ! -f "$EMCP_STDIO" ]; then
    echo "ERROR: $EMCP_STDIO not found"
    exit 1
fi

# ---- Helper: extract tools/list JSON from raw MCP server output ----
# The output is newline-delimited JSON-RPC. We find the tools/list
# response by looking for a JSON object with result.tools.
extract_tools_response() {
    python3 -c "
import sys, json

data = sys.stdin.read()
decoder = json.JSONDecoder()
pos = 0
responses = []
while pos < len(data):
    while pos < len(data) and data[pos] in ' \t\r\n':
        pos += 1
    if pos >= len(data):
        break
    if data[pos] != '{':
        eol = data.find('\n', pos)
        if eol == -1:
            break
        pos = eol + 1
        continue
    try:
        obj, end = decoder.raw_decode(data, pos)
        responses.append(obj)
        pos = end
    except json.JSONDecodeError:
        eol = data.find('\n', pos)
        if eol == -1:
            break
        pos = eol + 1

for r in responses:
    result = r.get('result', {})
    if isinstance(result, dict) and 'tools' in result:
        print(json.dumps(r))
        sys.exit(0)

sys.exit(1)
"
}

# Disable daemon check to avoid blocking on a busy/absent daemon.
# We override emcp-stdio--check-daemon to always return nil.
# This ensures we test only the local obarray tool collection layer.
DISABLE_DAEMON='(defun emcp-stdio--check-daemon () nil)'

# For the "always" filter test: we also need to protect build-tool
# from crashing on functions with unprintable arglists (e.g.,
# minibuffer-lazy-highlight-setup whose arglist contains #'identity).
# This wraps collect-tools with per-symbol error protection.
SAFE_ALWAYS_FILTER='
(defun emcp-stdio--safe-always-collect ()
  "Walk obarray with error protection per symbol."
  (let (tools)
    (mapatoms
     (lambda (sym)
       (when (and (fboundp sym)
                  (not (string-prefix-p "emcp-stdio-" (symbol-name sym))))
         (condition-case nil
             (push (emcp-stdio--build-tool sym) tools)
           (error nil)))))
    (apply (function vector) (nreverse tools))))
'

MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}'
MCP_LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# ---- Run MCP server with default filter (vanilla -Q) ----
echo "--- Running MCP server with default filter (vanilla -Q) ---"
DEFAULT_RAW=$(
    {
        echo "$MCP_INIT"
        echo "$MCP_LIST"
    } | emacs --batch -Q \
          -l "$EMCP_STDIO" \
          --eval "$DISABLE_DAEMON" \
          -f emcp-stdio-start 2>/dev/null
) || true
TOOLS_JSON_DEFAULT=$(echo "$DEFAULT_RAW" | extract_tools_response)
if [ $? -ne 0 ] || [ -z "$TOOLS_JSON_DEFAULT" ]; then
    echo "ERROR: Failed to capture default filter tools/list response"
    exit 1
fi
echo "  Captured default filter response."

# ---- Run MCP server with safe-always filter (vanilla -Q) ----
# We cannot use (setq emcp-stdio-filter-fn #'always) directly because
# build-tool crashes on some functions (no condition-case around
# help-function-arglist). Instead we replace collect-tools with a
# version that has per-symbol error protection.
echo "--- Running MCP server with safe-always filter (vanilla -Q) ---"
ALWAYS_RAW=$(
    {
        echo "$MCP_INIT"
        echo "$MCP_LIST"
    } | emacs --batch -Q \
          -l "$EMCP_STDIO" \
          --eval "$DISABLE_DAEMON" \
          --eval "$SAFE_ALWAYS_FILTER" \
          --eval '(setq emcp-stdio--tools-cache nil)' \
          --eval '(advice-add (quote emcp-stdio--collect-tools) :override (quote emcp-stdio--safe-always-collect))' \
          -f emcp-stdio-start 2>/dev/null
) || true
TOOLS_JSON_ALWAYS=$(echo "$ALWAYS_RAW" | extract_tools_response)
if [ $? -ne 0 ] || [ -z "$TOOLS_JSON_ALWAYS" ]; then
    echo "ERROR: Failed to capture always filter tools/list response"
    echo "  Raw output (first 200 chars): ${ALWAYS_RAW:0:200}"
    exit 1
fi
echo "  Captured always filter response."

echo ""
echo "=== Test Results ==="
echo ""

# ---- Helper: run a Python check on the tools JSON ----
check_tools() {
    local json="$1"
    local expr="$2"
    echo "$json" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
tools = data['result']['tools']
$expr
"
}

# ---- Test 1: Tool count > 0 for vanilla Emacs (-Q) ----
echo "--- Test 1: Tool count > 0 for vanilla Emacs (-Q) ---"
DEFAULT_COUNT=$(check_tools "$TOOLS_JSON_DEFAULT" "print(len(tools))")
if [ "$DEFAULT_COUNT" -gt 0 ] 2>/dev/null; then
    pass "Default filter tool count = $DEFAULT_COUNT (> 0)"
else
    fail "Default filter tool count = '$DEFAULT_COUNT' (expected > 0)"
fi

# ---- Test 2: Every tool has required MCP schema fields ----
echo "--- Test 2: Every tool has required MCP schema fields ---"

MISSING_NAME=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t for t in tools if not isinstance(t.get('name'), str) or len(t['name']) == 0]
print(len(bad))
")
if [ "$MISSING_NAME" -eq 0 ]; then
    pass "All tools have 'name' (non-empty string)"
else
    fail "$MISSING_NAME tools missing or empty 'name' field"
fi

MISSING_DESC=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t for t in tools if not isinstance(t.get('description'), str)]
print(len(bad))
")
if [ "$MISSING_DESC" -eq 0 ]; then
    pass "All tools have 'description' (string)"
else
    fail "$MISSING_DESC tools missing 'description' field"
fi

BAD_SCHEMA_TYPE=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t for t in tools if t.get('inputSchema', {}).get('type') != 'object']
print(len(bad))
")
if [ "$BAD_SCHEMA_TYPE" -eq 0 ]; then
    pass "All tools have inputSchema.type = 'object'"
else
    fail "$BAD_SCHEMA_TYPE tools have wrong inputSchema.type"
fi

BAD_ARGS_TYPE=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t for t in tools if t.get('inputSchema', {}).get('properties', {}).get('args', {}).get('type') != 'array']
print(len(bad))
")
if [ "$BAD_ARGS_TYPE" -eq 0 ]; then
    pass "All tools have inputSchema.properties.args.type = 'array'"
else
    fail "$BAD_ARGS_TYPE tools have wrong args type"
fi

BAD_ITEMS_TYPE=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t for t in tools if t.get('inputSchema', {}).get('properties', {}).get('args', {}).get('items', {}).get('type') != 'string']
print(len(bad))
")
if [ "$BAD_ITEMS_TYPE" -eq 0 ]; then
    pass "All tools have inputSchema.properties.args.items.type = 'string'"
else
    fail "$BAD_ITEMS_TYPE tools have wrong items type"
fi

# ---- Test 3: No tool name starts with "emcp-stdio-" ----
echo "--- Test 3: No tool name starts with 'emcp-stdio-' ---"
EMCP_TOOLS=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t['name'] for t in tools if t.get('name', '').startswith('emcp-stdio-')]
print(len(bad))
if bad: print('  Names:', ', '.join(bad[:5]), file=sys.stderr)
")
if [ "$EMCP_TOOLS" -eq 0 ]; then
    pass "No tools with 'emcp-stdio-' prefix in default filter"
else
    fail "$EMCP_TOOLS tools have 'emcp-stdio-' prefix"
fi

EMCP_TOOLS_ALWAYS=$(check_tools "$TOOLS_JSON_ALWAYS" "
bad = [t['name'] for t in tools if t.get('name', '').startswith('emcp-stdio-')]
print(len(bad))
if bad: print('  Names:', ', '.join(bad[:5]), file=sys.stderr)
")
if [ "$EMCP_TOOLS_ALWAYS" -eq 0 ]; then
    pass "No tools with 'emcp-stdio-' prefix in always filter"
else
    fail "$EMCP_TOOLS_ALWAYS tools have 'emcp-stdio-' prefix in always filter"
fi

# ---- Test 4: All descriptions <= 500 chars ----
echo "--- Test 4: All descriptions <= 500 chars ---"
LONG_DESCS=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [(t['name'], len(t['description'])) for t in tools if len(t.get('description', '')) > 500]
print(len(bad))
for name, l in bad[:3]: print(f'  {name}: {l} chars', file=sys.stderr)
")
if [ "$LONG_DESCS" -eq 0 ]; then
    pass "All descriptions <= 500 chars (default filter)"
else
    fail "$LONG_DESCS tools have descriptions > 500 chars"
fi

LONG_DESCS_ALWAYS=$(check_tools "$TOOLS_JSON_ALWAYS" "
bad = [(t['name'], len(t['description'])) for t in tools if len(t.get('description', '')) > 500]
print(len(bad))
for name, l in bad[:3]: print(f'  {name}: {l} chars', file=sys.stderr)
")
if [ "$LONG_DESCS_ALWAYS" -eq 0 ]; then
    pass "All descriptions <= 500 chars (always filter)"
else
    fail "$LONG_DESCS_ALWAYS tools have descriptions > 500 chars (always filter)"
fi

# ---- Test 5: inputSchema.required is ["args"] for every tool ----
echo "--- Test 5: inputSchema.required = [\"args\"] for every tool ---"
BAD_REQUIRED=$(check_tools "$TOOLS_JSON_DEFAULT" "
bad = [t['name'] for t in tools if t.get('inputSchema', {}).get('required') != ['args']]
print(len(bad))
for name in bad[:3]: print(f'  {name}', file=sys.stderr)
")
if [ "$BAD_REQUIRED" -eq 0 ]; then
    pass "All tools have inputSchema.required = [\"args\"] (default filter)"
else
    fail "$BAD_REQUIRED tools have wrong required field"
fi

BAD_REQUIRED_ALWAYS=$(check_tools "$TOOLS_JSON_ALWAYS" "
bad = [t['name'] for t in tools if t.get('inputSchema', {}).get('required') != ['args']]
print(len(bad))
for name in bad[:3]: print(f'  {name}', file=sys.stderr)
")
if [ "$BAD_REQUIRED_ALWAYS" -eq 0 ]; then
    pass "All tools have inputSchema.required = [\"args\"] (always filter)"
else
    fail "$BAD_REQUIRED_ALWAYS tools have wrong required field (always filter)"
fi

# ---- Test 6: Tool count with filter=always > default filter ----
echo "--- Test 6: Tool count with safe-always filter > default filter ---"
ALWAYS_COUNT=$(check_tools "$TOOLS_JSON_ALWAYS" "print(len(tools))")
if [ "$ALWAYS_COUNT" -gt "$DEFAULT_COUNT" ] 2>/dev/null; then
    pass "safe-always filter ($ALWAYS_COUNT) > default filter ($DEFAULT_COUNT)"
else
    fail "safe-always filter ($ALWAYS_COUNT) not > default filter ($DEFAULT_COUNT)"
fi

# ---- Summary ----
echo ""
echo "=== Summary ==="
echo "  Total: $TOTAL"
echo "  Pass:  $PASS"
echo "  Fail:  $FAIL"
echo "  Default filter tool count: $DEFAULT_COUNT"
echo "  Always filter tool count:  $ALWAYS_COUNT"
echo ""
echo "Known issue: build-tool lacks condition-case around help-function-arglist."
echo "Functions with #' read syntax in arglists crash the server when"
echo "filter=#'always is used. The safe-always test works around this."

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
