# MCP Protocol Compliance Report

**Date**: 2026-03-18
**Server**: `emacs-mcp-elisp` v0.1.0 (`src/emcp-stdio.el`)
**Emacs**: GNU Emacs 30.2
**MCP Protocol Version**: 2024-11-05
**Inspector**: `@modelcontextprotocol/inspector` v0.21.1 (CLI mode)
**Tool Count (vanilla -Q)**: 779

## Test Method

Two independent verification methods were used:

1. **Official MCP Inspector** (`npx @modelcontextprotocol/inspector --cli`)
   - Ran `tools/list` successfully; inspector parsed and displayed all 779 tools
   - Ran `resources/list` and `prompts/list`; correctly received `-32601` errors
   - Inspector confirmed JSON-RPC framing is correct

2. **Manual JSON-RPC over stdio** via `printf | emacs --batch -Q`
   - Full handshake: initialize, notifications/initialized, tools/list, tools/call, ping
   - Error handling: unknown tools, wrong arity, unknown methods, malformed JSON
   - Non-ASCII: Latin accented, CJK, emoji
   - Timing measurements

## Results Summary

| Check | Status | Notes |
|-------|--------|-------|
| JSON-RPC 2.0 framing | PASS | Every response has `jsonrpc`, `id`, `result` XOR `error` |
| `initialize` | PASS | Returns `protocolVersion`, `capabilities`, `serverInfo` |
| `notifications/initialized` | PASS | Silently swallowed (no response, correct for notification) |
| `tools/list` | PASS | Returns `{tools: [...]}` with 779 valid tool definitions |
| `tools/call` (success) | PASS | Returns `{content: [{type: "text", text: "..."}]}` |
| `tools/call` (error) | PARTIAL | Returns content with error text, but missing `isError: true` |
| `ping` | PASS | Returns empty object `{}` |
| `resources/list` | PASS | Returns `-32601` Method not found |
| `prompts/list` | PASS | Returns `-32601` Method not found |
| `resources/templates/list` | PASS | Returns `-32601` |
| `completion/complete` | PASS | Returns `-32601` |
| `logging/setLevel` | PASS | Returns `-32601` |
| `sampling/createMessage` | PASS | Returns `-32601` |
| Notifications (cancelled) | PASS | Silently swallowed |
| Malformed JSON recovery | PASS | Logs to stderr, continues processing |
| Non-ASCII (Latin/CJK) | PASS | `upcase("cafe")` -> `"CAFE"`, `string-trim` on Japanese works |
| Non-ASCII (Emoji) | FAIL | Dispatch error: `invalid utf-8 encoding` |
| Version negotiation | INFO | Server always responds with `2024-11-05` regardless of client version |

## Detailed Findings

### 1. initialize (PASS)

Response structure matches MCP spec exactly:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "emacs-mcp-elisp", "version": "0.1.0" }
  }
}
```

**Capabilities advertised**: `tools` only (empty object, meaning no `listChanged` support).
**Capabilities NOT advertised**: `resources`, `prompts`, `logging`, `sampling`.
This is correct -- the server should not advertise capabilities it does not implement.

### 2. tools/list (PASS)

- 779 tools returned in vanilla (`-Q`) mode
- All 779 tools have `name`, `description`, and `inputSchema` fields
- All `inputSchema` objects have `type: "object"`, `properties`, and `required` fields
- `required` is a JSON array `["args"]` (correct per JSON Schema)
- 188 tools have descriptions truncated at exactly 500 characters
- 5 tools have special characters in names (`<`, `>`, `--`):
  - `length<`, `length>`, `string<`, `string>`, `completion-pcm--string->pattern`

**Note**: No pagination support (`nextCursor` not present). The full list is
returned in a single response. At 779 tools this is fine; at 3600+ (maximalist
with init.el) this will produce a very large single response.

### 3. tools/call (PARTIAL)

Successful calls return correct `CallToolResult`:

```json
{
  "content": [{ "type": "text", "text": "hello" }]
}
```

Verified functions:
- `string-trim(" hello ")` -> `"hello"`
- `concat("hello", " ", "world")` -> `"hello world"`
- `upcase("hello")` -> `"HELLO"`
- `downcase("HELLO")` -> `"hello"`
- `string-replace("world", "universe", "hello world")` -> `"hello universe"`
- `length("hello")` -> `"5"`
- `string-to-number("42")` -> `"42"`
- `string-reverse("hello")` -> `"olleh"`

**Issue: Missing `isError` flag on tool execution errors.**

Per MCP spec, when a tool call results in an error, the response should include
`isError: true` in the `CallToolResult`. Currently, errors are returned as
success responses with error text in `content[0].text`:

```json
{
  "content": [{ "type": "text", "text": "error: Unknown tool: xyz" }]
}
```

Should be:

```json
{
  "content": [{ "type": "text", "text": "error: Unknown tool: xyz" }],
  "isError": true
}
```

This affects: unknown tools, wrong argument count, runtime eval errors.

### 4. ping (PASS)

Returns `{}` (empty object). Correct per MCP spec.

### 5. Error Responses (PASS)

Unimplemented methods correctly return JSON-RPC error `-32601`:

```json
{
  "error": { "code": -32601, "message": "Method not found: resources/list" }
}
```

This is the correct JSON-RPC 2.0 error code for method not found.

### 6. Non-ASCII Handling (PARTIAL)

| Input | Status | Result |
|-------|--------|--------|
| `upcase("cafe")` | PASS | `"CAFE"` |
| `string-trim("  konnichiha  ")` | PASS | `"konnichiha"` (Japanese) |
| `concat(emoji, " smile")` | FAIL | `invalid utf-8 encoding` error |

The emoji failure occurs in the dispatch layer when building the eval sexp.
The server recovers and continues processing subsequent requests.

### 7. Daemon Check Blocking

**Critical operational issue**: `emcp-stdio--check-daemon` calls
`(call-process "emacsclient" nil nil nil "--eval" "(emacs-pid)")` which blocks
indefinitely if no Emacs daemon is running or if `emacsclient` cannot find a
socket. This prevents the server from starting at all in environments without
a running daemon.

All tests in this report were run with the daemon check bypassed via
`--eval '(defun emcp-stdio--check-daemon () nil)'`.

## MCP Methods Implementation Matrix

| Method | Implemented | Notes |
|--------|------------|-------|
| `initialize` | Yes | Fully compliant |
| `notifications/initialized` | Yes | Silently accepted |
| `ping` | Yes | Returns `{}` |
| `tools/list` | Yes | Full list, no pagination |
| `tools/call` | Yes | Missing `isError` on errors |
| `resources/list` | No | Returns -32601 |
| `resources/read` | No | Returns -32601 |
| `resources/templates/list` | No | Returns -32601 |
| `resources/subscribe` | No | Returns -32601 |
| `prompts/list` | No | Returns -32601 |
| `prompts/get` | No | Returns -32601 |
| `completion/complete` | No | Returns -32601 |
| `logging/setLevel` | No | Returns -32601 |
| `sampling/createMessage` | No | N/A (server-to-client) |
| `notifications/cancelled` | Yes | Silently swallowed |
| `notifications/progress` | No | Not emitted |
| `notifications/resources/list_changed` | No | Not applicable |
| `notifications/tools/list_changed` | No | Not emitted |

## Performance

| Metric | Value |
|--------|-------|
| Startup + tool collection | ~138ms |
| First response (initialize) | ~138ms from process start |
| tools/list (779 tools) | <1ms after initialize |
| tools/call (string-trim) | <1ms after tools/list |
| Total handshake (init + list + call) | ~140ms |

## Recommendations

### Must Fix (Protocol Non-Compliance)

1. **Add `isError: true` to tool call error responses.** When `tools/call`
   catches an error, the `CallToolResult` should include `isError: true`
   alongside the error content. Without this, clients cannot programmatically
   distinguish tool success from tool failure.

2. **Fix emoji/4-byte UTF-8 handling.** Characters outside the Basic
   Multilingual Plane cause `invalid utf-8 encoding` errors. This likely
   requires ensuring `format "%S"` properly handles supplementary Unicode
   characters in the sexp builder.

### Should Fix (Operational)

3. **Fix `emcp-stdio--check-daemon` blocking.** Use `emacsclient` with
   `--socket-name` and a timeout, or check for the socket file existence
   before calling `call-process`. The current implementation hangs
   indefinitely if no daemon is available.

### Nice to Have (Optional MCP Features)

4. **Add `isError` field support.** Already covered above.

5. **Consider pagination for tools/list.** At 779 tools the single response
   is ~700KB of JSON. In maximalist mode (3600+ tools) this will be
   multiple megabytes. Pagination via `cursor`/`nextCursor` would help
   clients that cannot handle large responses.

6. **Consider `listChanged` in tools capability.** If the tool set could
   change during a session (e.g., daemon connects/disconnects), advertising
   `listChanged: true` and emitting `notifications/tools/list_changed`
   would allow clients to refresh.

7. **Version negotiation.** The server currently ignores the client's
   requested `protocolVersion` and always responds with `2024-11-05`.
   Per MCP spec, the server should respond with the highest version it
   supports that is <= the client's requested version.
