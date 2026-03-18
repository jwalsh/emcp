# I/O Layer Contract: `src/emcp-stdio.el`

This document specifies the contracts for the four I/O functions in
`emcp-stdio.el` that form the JSON-RPC 2.0 transport boundary.

## Protocol Context

The MCP protocol uses **newline-delimited JSON-RPC 2.0** over stdio:
- Each message is a single line of valid JSON followed by exactly one `\n`
- No embedded newlines within a message
- Encoding is UTF-8 throughout
- stdout carries protocol messages; stderr carries diagnostics

## Function Contracts

### `emcp-stdio--read-line`

**Purpose**: Read one line of input from stdin.

| Aspect | Specification |
|--------|---------------|
| **Inputs** | None (reads from `standard-input`, which is stdin in batch mode) |
| **Output** | A string (one line, newline stripped) or `nil` at EOF |
| **Mechanism** | `read-from-minibuffer ""` — reads one line from stdin in batch mode |
| **EOF handling** | Catches `end-of-file` signal, returns `nil` to terminate the read loop |
| **Encoding** | Governed by `coding-system-for-read`, set to `utf-8` at startup |
| **Blocking** | Blocks until a complete line (terminated by newline) is available |

**Invariants**:
- Never raises an error — EOF is handled via `condition-case`
- Returns the raw line content without trailing newline
- Empty lines return `""` (empty string), not `nil`
- `nil` means only EOF, never an empty input

**Edge cases**:
- Partial line without trailing newline at EOF: behavior depends on Emacs's `read-from-minibuffer` — may return the partial content or signal EOF
- Binary/non-UTF-8 input: decoded per `coding-system-for-read` (`utf-8`); invalid byte sequences may produce replacement characters

---

### `emcp-stdio--send`

**Purpose**: Serialize an alist as JSON and write it to stdout, newline-terminated.

| Aspect | Specification |
|--------|---------------|
| **Input** | `ALIST` — an Emacs Lisp alist representing a JSON object |
| **Output** | Side effect: writes one line to stdout (JSON + `\n`) |
| **Serializer** | `json-serialize` (built-in, returns unibyte UTF-8 string) |
| **Critical step** | `decode-coding-string ... 'utf-8` converts unibyte to multibyte before `princ` |
| **Newline** | `terpri` writes exactly one `\n` after the JSON payload |
| **Flushing** | `terpri` flushes stdout in batch mode |

**Invariants**:
1. Output is always exactly one line: valid JSON followed by exactly one `\n`
2. No embedded newlines within the JSON (guaranteed by `json-serialize` — JSON strings escape `\n` as `\\n`)
3. Output encoding is UTF-8 (governed by `coding-system-for-write`)
4. The `decode-coding-string` step is mandatory: without it, `princ` in batch mode may emit raw bytes instead of properly encoded multibyte characters, corrupting non-ASCII output

**Type mapping** (Elisp to JSON via `json-serialize`):
| Elisp | JSON |
|-------|------|
| string | string |
| integer/float | number |
| `t` | `true` |
| `:json-false` / `nil` (in some contexts) | `false` |
| `:json-null` | `null` |
| vector `[...]` | array `[...]` |
| alist `((k . v) ...)` | object `{"k": v, ...}` |
| hash-table | object `{...}` |

**Error cases**:
- If `ALIST` contains values that `json-serialize` cannot encode (e.g., markers, buffers), it signals `wrong-type-argument` — this is NOT caught by `emcp-stdio--send` and will propagate to the caller
- Circular structures: `json-serialize` will error

---

### `emcp-stdio--respond`

**Purpose**: Send a JSON-RPC 2.0 success response.

| Aspect | Specification |
|--------|---------------|
| **Inputs** | `ID` — request identifier (integer or string per JSON-RPC 2.0); `RESULT` — the response payload (any JSON-serializable value) |
| **Output** | Calls `emcp-stdio--send` with a well-formed response alist |
| **Delegates to** | `emcp-stdio--send` |

**Produced JSON structure**:
```json
{
  "jsonrpc": "2.0",
  "id": <ID>,
  "result": <RESULT>
}
```

**Invariants**:
1. Always includes exactly three keys: `jsonrpc`, `id`, `result`
2. `jsonrpc` is always the string `"2.0"`
3. `id` matches the request's `id` field exactly (integer or string)
4. `result` is present even if the logical result is empty (e.g., empty hash-table `{}`)
5. The `error` key is never present in a success response
6. Output is one newline-delimited JSON line (inherited from `emcp-stdio--send`)

**JSON-RPC 2.0 compliance**:
- Per spec section 5: "result" MUST be present on success, MUST NOT be present on error
- Per spec section 5: "error" MUST NOT be present on success
- Both conditions are met by construction

---

### `emcp-stdio--respond-error`

**Purpose**: Send a JSON-RPC 2.0 error response.

| Aspect | Specification |
|--------|---------------|
| **Inputs** | `ID` — request identifier; `CODE` — integer error code; `MSG` — human-readable error message string |
| **Output** | Calls `emcp-stdio--send` with a well-formed error response alist |
| **Delegates to** | `emcp-stdio--send` |

**Produced JSON structure**:
```json
{
  "jsonrpc": "2.0",
  "id": <ID>,
  "error": {
    "code": <CODE>,
    "message": <MSG>
  }
}
```

**Invariants**:
1. Always includes exactly three keys: `jsonrpc`, `id`, `error`
2. `jsonrpc` is always the string `"2.0"`
3. `id` matches the request's `id` field exactly
4. `error` is an object with exactly two keys: `code` (integer) and `message` (string)
5. The `result` key is never present in an error response
6. Output is one newline-delimited JSON line (inherited from `emcp-stdio--send`)

**Standard JSON-RPC 2.0 error codes used in this server**:
| Code | Meaning | Used when |
|------|---------|-----------|
| -32601 | Method not found | Unknown method in dispatch |
| -32700 | Parse error | Malformed JSON (handled in read loop, logged to stderr) |

**JSON-RPC 2.0 compliance**:
- Per spec section 5.1: error object MUST contain `code` (integer) and `message` (string)
- Optional `data` field is not used
- Per spec section 5: "result" MUST NOT be present on error

---

## Cross-Cutting Invariants

### Encoding Pipeline

```
json-serialize(alist)           → unibyte UTF-8 string
  ↓
decode-coding-string(..., utf-8) → multibyte Emacs string
  ↓
princ(...)                       → writes to stdout
  ↓
coding-system-for-write = utf-8  → UTF-8 bytes on the wire
```

This pipeline is necessary because `json-serialize` returns a unibyte
string (raw UTF-8 bytes), but `princ` in batch mode needs a multibyte
string to emit correct output. Without the `decode-coding-string` step,
non-ASCII characters (accented letters, CJK, emoji) would be corrupted.

### Newline Discipline

- Every message on stdout is exactly one line: `<json>\n`
- No message contains embedded literal newlines (JSON `\n` is escaped as `\\n`)
- `terpri` produces exactly one newline character
- Stderr messages (via `message`) may contain newlines but are on a separate channel

### Error Routing

| Error type | Destination | Mechanism |
|------------|-------------|-----------|
| JSON parse error (malformed input) | stderr | `message` in read loop's `condition-case` |
| Dispatch error (handler crash) | stderr | `message` in read loop's `condition-case` |
| Method not found | stdout (JSON-RPC error response) | `emcp-stdio--respond-error` with code -32601 |
| Tool execution error | stdout (success response with error text in content) | `emcp-stdio--respond` with error string in `content[0].text` |

Note: tool execution errors are returned as **success responses** with
the error message embedded in the content text, prefixed with `"error: "`.
This is a design choice — the JSON-RPC call itself succeeded; the tool
execution failed. The MCP client sees the error in the tool's text output.

### Notification Handling

JSON-RPC 2.0 notifications (messages without `id`) are silently swallowed
by the dispatch function. No response is sent, per spec.

### Startup Encoding Configuration

`emcp-stdio-start` sets these before the read loop:
```elisp
(set-language-environment "UTF-8")
(setq coding-system-for-read 'utf-8)
(setq coding-system-for-write 'utf-8)
```

This ensures consistent encoding regardless of the user's locale settings.
