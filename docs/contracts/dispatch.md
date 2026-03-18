# Dispatch Layer Contract: `src/emcp-stdio.el`

## Scope

This document specifies the contracts for the JSON-RPC method routing,
local eval, daemon dispatch, and main loop in `src/emcp-stdio.el`.

The dispatch layer is the pure-Elisp MCP server: Emacs itself reads
JSON-RPC 2.0 from stdin, routes to handlers, and writes responses to
stdout. No Python, no manifest file, no emacsclient for local tools.

## Functions Under Contract

### `emcp-stdio--dispatch (msg)`

**Inputs**: An alist parsed from a JSON-RPC 2.0 message with keys
`id`, `method`, and optionally `params`.

**Outputs**: Zero or one JSON-RPC 2.0 response written to stdout via
`emcp-stdio--send`.

**Routing table**:

| `id`   | `method`        | Handler                              |
|--------|-----------------|--------------------------------------|
| nil    | (any)           | Swallow silently (notification)      |
| non-nil| `"initialize"`  | `emcp-stdio--handle-initialize`      |
| non-nil| `"ping"`        | Respond with empty hash-table `{}`   |
| non-nil| `"tools/list"`  | `emcp-stdio--handle-tools-list`      |
| non-nil| `"tools/call"`  | `emcp-stdio--handle-tools-call`      |
| non-nil| (anything else) | Error response, code -32601          |

**Invariants**:
1. Notifications (no `id`) MUST never produce a response on stdout.
2. Every request (has `id`) MUST produce exactly one response on stdout.
3. The response `id` MUST match the request `id`.
4. Unknown methods MUST return JSON-RPC error code -32601 ("Method not found").
5. `params` defaults to `()` if absent from the message.

### `emcp-stdio--handle-initialize (id params)`

**Inputs**: Request id (integer or string) and params (ignored).

**Outputs**: JSON-RPC success response containing:
```json
{
  "protocolVersion": "2024-11-05",
  "capabilities": { "tools": {} },
  "serverInfo": {
    "name": "emacs-mcp-elisp",
    "version": "0.1.0"
  }
}
```

**Invariants**:
1. `protocolVersion` MUST equal `emcp-stdio--protocol-version`.
2. `capabilities.tools` MUST be present (as an empty object).
3. `serverInfo.name` and `serverInfo.version` MUST be present.

### `emcp-stdio--handle-tools-list (id params)`

**Inputs**: Request id and params (ignored).

**Outputs**: JSON-RPC success response containing:
```json
{
  "tools": [ ...tool definitions... ]
}
```

**Invariants**:
1. Returns the pre-built `emcp-stdio--tools-cache` vector.
2. Every tool in the array has keys: `name`, `description`, `inputSchema`.
3. `inputSchema.properties.args` defines an array of strings.
4. `inputSchema.required` contains `["args"]`.

### `emcp-stdio--handle-tools-call (id params)`

**Inputs**: Request id and params alist containing:
- `name`: string, the tool name
- `arguments.args`: JSON array of string arguments

**Outputs**: JSON-RPC success response in all cases (both success and
application-level errors). The result contains:
```json
{
  "content": [
    { "type": "text", "text": "<result or error message>" }
  ]
}
```

**Routing decision** (the key invariant):
- If `name` starts with `"emcp-data-"`: dispatch to daemon via
  `emcp-stdio--daemon-call`. Requires `emcp-stdio--daemon-available`
  to be non-nil.
- Otherwise: dispatch to local `read` + `eval` in the batch process.

**Invariants**:
1. Application errors (unknown tool, eval failure, daemon unavailable)
   are returned as `content` text prefixed with `"error: "`, NOT as
   JSON-RPC error responses. The JSON-RPC layer always succeeds.
2. `condition-case` wraps the entire dispatch, catching all `error`
   signals. The server MUST NOT crash on any tool call.
3. For local tools, `intern-soft` MUST find the symbol and `fboundp`
   MUST confirm it is callable. Otherwise: error in content.
4. For daemon tools, if `emcp-stdio--daemon-available` is nil, the
   error message MUST indicate "No daemon available".

### `emcp-stdio-start ()`

**Inputs**: None. Reads from stdin (newline-delimited JSON).

**Outputs**: JSON-RPC responses on stdout. Diagnostics on stderr.

**Startup sequence**:
1. Set UTF-8 encoding on stdin/stdout.
2. Probe daemon availability via `emcp-stdio--check-daemon`.
3. Build tool cache: local obarray tools + daemon tools (if available).
4. Log tool count to stderr.
5. Enter read loop.

**Read loop invariants**:
1. Reads one line at a time via `emcp-stdio--read-line`.
2. Empty lines are silently skipped.
3. JSON parse errors are logged to stderr, no response sent.
4. Other dispatch errors are logged to stderr, no response sent.
5. Loop exits on EOF (stdin closes).

## Routing Key: Local vs. Daemon

The routing decision is a string prefix check:

```
tool name starts with "emcp-data-" --> daemon dispatch
otherwise                          --> local eval
```

**Local eval path**:
```
(intern-soft name) -> fboundp check -> format sexp -> read -> eval
```

**Daemon eval path**:
```
emcp-stdio--daemon-call -> handler-type check:
  :raw  -> pass first arg directly to emacsclient --eval
  :build -> emcp-stdio--daemon-build-sexp constructs sexp, then emacsclient --eval
```

## Security Analysis

### Local eval: `format "%S"` prevents injection

The local eval path constructs a sexp string:
```elisp
(format "(%s %s)" name (mapconcat (lambda (a) (format "%S" a)) args " "))
```

- `name` comes from `intern-soft` lookup, so it must be a symbol that
  exists and is `fboundp`. An attacker cannot inject arbitrary code
  through the tool name without it already being a bound function.
- Each argument is formatted with `%S` (Elisp `prin1` quoting), which
  produces a properly escaped string literal: double-quotes, backslashes,
  and special characters are all escaped. This prevents injection via
  argument values.
- The resulting string is passed to `read` then `eval`. Because `%S`
  guarantees each arg is a single string token, the sexp structure is
  fixed: `(function-name "arg1" "arg2" ...)`.

**Residual risk**: The tool `name` is interpolated with `%s` (not `%S`),
so it enters the sexp unquoted. However, `intern-soft` + `fboundp`
gates this: only names that resolve to existing functions are accepted.
A crafted name like `progn` would pass `fboundp` but would require args
to be valid sexp forms (they are strings, so `(progn "hello")` just
returns `"hello"`). Functions with side effects (e.g., `delete-file`)
are callable if `fboundp` and the filter predicate allow them. This is
intentional: the server exposes Emacs's full capability surface.

### Daemon eval: `emcp-data-eval` takes raw sexp

The `:raw` handler type passes the first argument directly to
`emacsclient --eval`. This is equivalent in trust model to running
`emacsclient --eval` from a shell. No additional sandboxing.

For `:build` tools, `prin1-to-string` is used to quote arguments into
the constructed sexp, providing the same injection protection as `%S`.

### Can a tool name be crafted to exploit `read` + `eval`?

The tool name is used as the function-call position in the sexp:
`(name arg1 arg2 ...)`. For this to be exploitable:

1. The name must pass `intern-soft` (symbol exists in obarray).
2. The name must pass `fboundp` (symbol has a function binding).
3. The name must pass the filter predicate (`emcp-stdio-filter-fn`).

Condition 3 is the practical gate. In core mode, only functions whose
arglists match text-consumer patterns are exposed. An attacker would
need to find a destructive function whose arglist happens to contain
"string", "buffer", "text", etc. Examples: `kill-buffer` (has "buffer"
in arglist) would pass the filter. This is a known trade-off: the
filter is a heuristic, not a security boundary.

In maximalist mode with `emcp-stdio-filter-fn` set to `always`, every
`fboundp` symbol is exposed. This is the stated design intent.

**Bottom line**: The security boundary is the MCP transport layer
(who can connect), not the dispatch layer. The dispatch layer trusts
its caller, same as `emacsclient` trusts shell access.

## Wire Format Examples

### Request: initialize
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
```

### Response: initialize
```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"emacs-mcp-elisp","version":"0.1.0"}}}
```

### Request: tools/call (success)
```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"upcase","arguments":{"args":["hello"]}}}
```

### Response: tools/call (success)
```json
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"HELLO"}]}}
```

### Request: tools/call (unknown tool)
```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"nonexistent-fn","arguments":{"args":[]}}}
```

### Response: tools/call (error in content)
```json
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"error: Unknown tool: nonexistent-fn"}]}}
```

### Request: unknown method
```json
{"jsonrpc":"2.0","id":4,"method":"bogus/method","params":{}}
```

### Response: unknown method (JSON-RPC error)
```json
{"jsonrpc":"2.0","id":4,"error":{"code":-32601,"message":"Method not found: bogus/method"}}
```

### Notification (no id, no response expected)
```json
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
```
