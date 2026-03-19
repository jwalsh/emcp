# emcp-data-eval Test Results

**Date:** 2026-03-18
**Tool:** `emcp-data-eval`
**Source:** `src/emcp-stdio.el` line 147
**Handler type:** `:raw` -- `args[0]` is sent directly to `emacsclient --eval` without quoting

## Overview

`emcp-data-eval` is the raw eval escape hatch in the daemon data layer.
Unlike the other `emcp-data-*` tools which use `emcp-stdio--daemon-build-sexp`
to construct sanitized sexps, `emcp-data-eval` passes `(car args)` directly
to `emcp-stdio--daemon-eval`, which calls `emacsclient --eval` with the
string verbatim.

The dispatch path:

```
tools/call → emcp-stdio--handle-tools-call
  → (string-prefix-p "emcp-data-" name) → emcp-stdio--daemon-call
    → (eq (nth 3 def) :raw) → (emcp-stdio--daemon-eval (car args))
      → (call-process "emacsclient" nil t nil "--eval" sexp-string)
```

No escaping, no sexp building. The caller controls the entire expression.

## Test Method

All tests run via MCP JSON-RPC over stdio:

```
emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start
```

Daemon was running (PID 6694, Emacs 30.2, `-Q` vanilla mode).
Server reported: 788 tools (779 local + 9 daemon).

## Primary Test Results

### 1. emacs-version (id:10)

| Input | Result | Pass |
|-------|--------|------|
| `(emacs-version)` | `"GNU Emacs 30.2 (build 1, aarch64-apple-darwin24.6.0)\n of 2026-02-09"` | YES |

Returns the full version string, including build details. The `\n` in the
response is an escaped literal newline in the JSON output -- the version
string contains a real newline which `emacsclient` prints as part of the
result.

### 2. Arithmetic (id:11)

| Input | Result | Pass |
|-------|--------|------|
| `(+ 1 2 3)` | `6` | YES |

Integer result, no quoting. Demonstrates that non-string results are
returned as their Elisp printed representation.

### 3. Daemon state access (id:12)

| Input | Result | Pass |
|-------|--------|------|
| `(format "%s items" (length (buffer-list)))` | `"13 items"` | YES |

Accesses live daemon state (`buffer-list`). The count (13) reflects the
daemon's actual buffer list, not the batch process's. Confirms the eval
runs in the daemon, not in the batch MCP server.

### 4. String manipulation (id:13)

| Input | Result | Pass |
|-------|--------|------|
| `(mapconcat #'symbol-name (list 'a 'b 'c) ", ")` | `"a, b, c"` | YES |

Complex expression with `#'` reader syntax and quoted symbols. The JSON
transport correctly delivers the sexp to `emacsclient`.

### 5. Stateful evaluation (id:14, id:30)

| id | Input | Result | Pass |
|----|-------|--------|------|
| 14 | `(progn (setq emcp-test-var 42) emcp-test-var)` | `42` | YES |
| 30 | `emcp-test-var` | `42` | YES |

The variable set in id:14 persists in the daemon and is readable in id:30.
This confirms:
- `setq` in the daemon has lasting side effects
- Simple symbol evaluation works (not just function calls)
- The daemon maintains state across `emacsclient` invocations

### 6. Division by zero (id:15)

| Input | Result | isError | Pass |
|-------|--------|---------|------|
| `(/ 1 0)` | `error: daemon-eval failed: *ERROR*: Arithmetic error` | `true` | YES |

The error is caught by `emcp-stdio--daemon-eval` (non-zero exit from
`emacsclient`), wrapped in the MCP error format with `isError: true`.
The daemon survives the error.

## Edge Case Results

### 7. Empty sexp (id:20)

| Input | Result | isError | Pass |
|-------|--------|---------|------|
| `""` | `error: daemon-eval failed: *ERROR*: Wrong type argument: stringp, nil` | `true` | YES |

Empty string argument. The `:raw` handler calls `(car args)` which
returns the empty string. `emacsclient --eval ""` causes an error in
the Elisp reader (it expects a readable sexp). The error is properly
wrapped in `isError: true`.

### 8. Multiline sexp (id:21)

| Input | Result | Pass |
|-------|--------|------|
| `(progn\n  (setq x 1)\n  (setq y 2)\n  (+ x y))` | `3` | YES |

Newlines within the sexp are preserved through JSON parsing and
`emacsclient --eval` handles them correctly. The Elisp reader treats
newlines as whitespace.

### 9. Special characters: quotes and backslashes (id:22)

| Input | Result | Pass |
|-------|--------|------|
| `(format "quotes: %s backslash: %s" "\"hello\"" "a\\b")` | `"quotes: \"hello\" backslash: a\\b"` | YES |

Escaped quotes and backslashes survive the JSON -> emacsclient -> Elisp
round trip. The JSON layer handles the first level of escaping; `emacsclient`
receives the properly escaped Elisp string literals.

### 10. nil evaluation (id:23)

| Input | Result | Pass |
|-------|--------|------|
| `nil` | `nil` | YES |

The symbol `nil` evaluates to itself. Returned as the string `"nil"` in
the MCP text content.

### 11. List return value (id:24)

| Input | Result | Pass |
|-------|--------|------|
| `(list 1 2 3 (list 4 5))` | `(1 2 3 (4 5))` | YES |

Lists are serialized using Elisp printed representation (`prin1` format).
Nested lists are preserved. The result is not JSON -- it is the raw Elisp
printed form.

### 12. String with embedded newlines (id:25)

| Input | Result | Pass |
|-------|--------|------|
| `(format "line1\nline2\nline3")` | `"line1\nline2\nline3"` | YES |

The newlines in the result string are escaped in the `emacsclient` output
(Elisp `prin1` format). They arrive in the MCP response as `\\n` in the
JSON text field.

### 13. Hash table return (id:26)

| Input | Result | Pass |
|-------|--------|------|
| `(let ((ht (make-hash-table))) (puthash 'key "value" ht) ht)` | `#s(hash-table data (key "value"))` | YES |

Hash tables are serialized using Elisp `#s(...)` syntax. The result is
readable by the Elisp reader (`read`), making it round-trippable.

### 14. Daemon current-buffer (id:27)

| Input | Result | Pass |
|-------|--------|------|
| `(buffer-name (current-buffer))` | `" *server*"` | YES |

The daemon's current buffer is `*server*` (with leading space). This
confirms the eval runs in the daemon's server context, not in any
user-facing buffer.

### 15. Large integer / bignum (id:28)

| Input | Result | Pass |
|-------|--------|------|
| `(format "%s" (+ most-positive-fixnum 1))` | `"2305843009213693952"` | YES |

Emacs 30.2 supports bignums. The value `most-positive-fixnum + 1`
(2^61 on this 64-bit platform) is correctly computed and formatted.

### 16. obarray length (id:29)

| Input | Result | isError | Notes |
|-------|--------|---------|-------|
| `(length obarray)` | `error: daemon-eval failed: *ERROR*: Wrong type argument: sequencep, #<obarray n=37289>` | `true` | Expected |

`obarray` is not a sequence in Emacs 30.x -- it is a specialized object
type. `length` requires a sequence. The error is correctly caught and
wrapped. Note: `n=37289` reveals the daemon has ~37k interned symbols.

### 17. Boolean t (id:31)

| Input | Result | Pass |
|-------|--------|------|
| `t` | `t` | YES |

The symbol `t` self-evaluates. Minimal confirmation of symbol evaluation.

### 18. Quoted list (id:32)

| Input | Result | Pass |
|-------|--------|------|
| `'(1 2 3)` | `(1 2 3)` | YES |

Quoted list passes through `emacsclient --eval` and the reader correctly
interprets the quote. Result is the unquoted printed form.

### 19. string-trim (id:33)

| Input | Result | Pass |
|-------|--------|------|
| `(string-trim "  hello world  ")` | `"hello world"` | YES |

Standard string function works as expected. Leading and trailing
whitespace removed.

### 20. with-temp-buffer (id:34)

| Input | Result | Pass |
|-------|--------|------|
| `(with-temp-buffer (insert "test content") (buffer-string))` | `"test content"` | YES |

Temporary buffers created in the daemon are cleaned up after the eval
completes. The result captures the buffer content before cleanup.

### 21. type-of (id:35)

| Input | Result | Pass |
|-------|--------|------|
| `(type-of '(1 2 3))` | `cons` | YES |

Introspection works. Lists are of type `cons`. Result is an unquoted
symbol name.

### 22. Void function (id:36)

| Input | Result | isError | Pass |
|-------|--------|---------|------|
| `(void-function-that-doesnt-exist)` | `error: daemon-eval failed: *ERROR*: Symbol's function definition is void: void-function-that-doesnt-exist` | `true` | YES |

Calling a nonexistent function produces a clear error message identifying
the missing symbol. Wrapped with `isError: true`.

### 23. Explicit error signal (id:37)

| Input | Result | isError | Pass |
|-------|--------|---------|------|
| `(error "custom error message")` | `error: daemon-eval failed: *ERROR*: custom error message` | `true` | YES |

User-signaled errors are caught by `emacsclient` (non-zero exit) and
propagated through the MCP error path. The daemon survives -- errors
in `emacsclient --eval` do not crash the daemon.

## Security Considerations

`emcp-data-eval` is the most dangerous tool in the data layer. Because it
uses the `:raw` handler type, the caller's string is passed directly to
`emacsclient --eval` with no escaping or sandboxing:

- **Arbitrary code execution:** Any valid Elisp can be evaluated, including
  `(shell-command "rm -rf /")`, `(delete-file ...)`, etc.
- **No read-only protection:** The daemon's state can be mutated freely
  (`setq`, `kill-buffer`, file writes, etc.)
- **No timeout:** Long-running or infinite expressions will block the
  MCP server until `emacsclient` returns.

This is by design -- the tool is documented as "the raw query interface"
and the MCP server is not exposed to untrusted clients. The security
boundary is the MCP transport layer (stdio), not the tool itself.

## Error Handling Summary

| Error type | Behavior | isError | Daemon survives |
|------------|----------|---------|-----------------|
| Arithmetic error | `*ERROR*: Arithmetic error` | true | YES |
| Void function | `*ERROR*: Symbol's function definition is void: NAME` | true | YES |
| Wrong type argument | `*ERROR*: Wrong type argument: ...` | true | YES |
| Explicit `(error ...)` | `*ERROR*: MESSAGE` | true | YES |
| Empty input | `*ERROR*: Wrong type argument: stringp, nil` | true | YES |

All daemon errors produce `isError: true` in the MCP response. The daemon
is never crashed by evaluation errors. The error messages include the
Emacs `*ERROR*:` prefix from `emacsclient` output.

## Return Type Serialization

| Elisp type | Example | Serialized form | Notes |
|------------|---------|-----------------|-------|
| integer | `6` | `6` | No quotes |
| string | `"hello"` | `"hello"` | Elisp-quoted with `\"` |
| nil | `nil` | `nil` | No quotes |
| t | `t` | `t` | No quotes |
| symbol | `cons` | `cons` | No quotes |
| cons/list | `(1 2 3)` | `(1 2 3)` | Elisp printed form |
| hash-table | `#s(hash-table ...)` | `#s(hash-table data (...))` | Readable syntax |

Results are always the Elisp `prin1` printed representation of the return
value. They are not JSON-encoded by the daemon -- the MCP server wraps them
in `{"type":"text","text":"..."}`.

## Summary

| Test | ID(s) | Status |
|------|-------|--------|
| Version string returned | 10 | PASS |
| Arithmetic works | 11 | PASS |
| Accesses daemon state (buffer-list) | 12 | PASS |
| String manipulation | 13 | PASS |
| State persists across calls (setq) | 14, 30 | PASS |
| Division by zero returns error | 15 | PASS |
| Error wrapped in isError: true | 15, 20, 29, 36, 37 | PASS |
| Empty sexp returns error | 20 | PASS |
| Multiline sexp works | 21 | PASS |
| Quotes and backslashes survive | 22 | PASS |
| nil evaluates to nil | 23 | PASS |
| List returned as printed form | 24 | PASS |
| Newlines in result escaped | 25 | PASS |
| Hash table returned as #s(...) | 26 | PASS |
| Daemon current-buffer is *server* | 27 | PASS |
| Bignums supported | 28 | PASS |
| Non-sequence error caught | 29 | PASS (error) |
| Boolean t self-evaluates | 31 | PASS |
| Quoted list works | 32 | PASS |
| string-trim works | 33 | PASS |
| with-temp-buffer works | 34 | PASS |
| type-of returns symbol | 35 | PASS |
| Void function returns error | 36 | PASS |
| Explicit (error ...) returns error | 37 | PASS |

All 23 test scenarios passed. The daemon survived all error conditions
without crashing. Error responses are correctly wrapped with `isError: true`.
