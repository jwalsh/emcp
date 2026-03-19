# emcp-data-buffer-insert

**Tool type:** Daemon data-layer (WRITE operation)
**Date tested:** 2026-03-18
**Server:** emcp-stdio.el (pure Elisp MCP server)

## Signature

```
(buffer-name text)
```

Two string arguments passed via `args` array:
- `buffer-name`: Name of an existing buffer in the daemon (e.g., `"*scratch*"`)
- `text`: Text to insert

## Generated Sexp

The sexp builder at `emcp-stdio--daemon-build-sexp` (line 228) produces:

```elisp
(with-current-buffer BUFFER-NAME
  (goto-char (point-max))
  (insert TEXT)
  (format "inserted %d chars" (length TEXT)))
```

Key observations:
- **Appends at point-max** (end of buffer) -- confirmed
- **Does NOT call `save-buffer`** -- confirmed (Agent 4's observation is correct)
- Uses `prin1-to-string` for safe quoting of both buffer-name and text
- Returns a confirmation string: `"inserted N chars"`

## MCP Tool Definition

```json
{
  "name": "emcp-data-buffer-insert",
  "description": "Insert TEXT at end of BUFFER-NAME in the running Emacs daemon.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "args": {
        "type": "array",
        "items": { "type": "string" },
        "description": "(buffer-name text)"
      }
    },
    "required": ["args"]
  }
}
```

## Test Results

### Test 1: Basic insert and char count

```
tools/call: emcp-data-buffer-insert ["*scratch*", "hello from MCP"]
```

**Result:** `"inserted 14 chars"` -- PASS

The return value confirms 14 characters were inserted (length of "hello from MCP").

### Test 2: Read-back verification

After inserting "hello from MCP" into `*scratch*`:

```
tools/call: emcp-data-buffer-read ["*scratch*"]
```

**Result:** Buffer contents end with `hello from MCP` -- PASS

The text appears at the end of the buffer, after the default *scratch* comment.

### Test 3: Nonexistent buffer

```
tools/call: emcp-data-buffer-insert ["nonexistent-buffer-xyz", "test"]
```

**Result:** Error with `isError: true`:
```
error: daemon-eval failed: *ERROR*: No buffer named nonexistent-buffer-xyz
```

PASS -- the error originates from `with-current-buffer` in the daemon, which
signals when the buffer does not exist. The MCP layer wraps it as an error response.

### Test 4: Multiple inserts append in order

```
1. emcp-data-eval: create *mcp-test*, erase it
2. emcp-data-buffer-insert ["*mcp-test*", "FIRST"]   -> "inserted 5 chars"
3. emcp-data-buffer-insert ["*mcp-test*", "SECOND"]  -> "inserted 6 chars"
4. emcp-data-buffer-read ["*mcp-test*"]               -> "FIRSTSECOND"
```

**Result:** Contents are `"FIRSTSECOND"` -- PASS

Confirms `goto-char (point-max)` causes each insert to append. No separator
is added between inserts; the caller must include newlines if desired.

### Test 5: Special characters

| Input | Chars | Status |
|-------|-------|--------|
| Newlines: `"\nline two\nline three"` | 20 | PASS |
| Quotes: `"quotes: \"hello\" and 'world'"` | 27 | PASS |
| Unicode: `"Unicode: eaue 世界 🚀"` | 17 | PASS |
| Parens: `"parens: (foo (bar)) end"` | 23 | PASS |
| Backslash + tab: `"backslash: \\ and tab:\t done"` | 27 | PASS |
| Empty string: `""` | 0 | PASS |

All special characters survive the JSON -> Elisp `prin1-to-string` -> `emacsclient` ->
daemon `insert` round-trip without corruption.

### Test 6: No save-buffer call

Inspecting the generated sexp confirms there is no `save-buffer` call.
This is the correct behavior for buffer-insert: the daemon buffer is modified
in memory but not persisted to disk. This differs from `emcp-data-org-set-todo`
and `emcp-data-org-capture`, which do call `save-buffer`.

**Agent 4's observation: CONFIRMED** -- `emcp-data-buffer-insert` does NOT save.

### Test 7: Argument validation (edge cases)

| Args | Generated sexp | Behavior |
|------|---------------|----------|
| 1 arg (missing text) | `(insert nil)` | Inserts literal `nil` -- no validation |
| 0 args | `(with-current-buffer nil ...)` | Daemon error -- `nil` is not a buffer |

**Note:** The sexp builder does not validate argument count. With 1 arg,
`(nth 1 args)` returns `nil`, which `prin1-to-string` converts to the
symbol `nil`. Emacs then `(insert nil)` which inserts the literal string
"nil" into the buffer. This is a silent data corruption risk -- no error
is raised.

## Contract Summary

| Property | Value |
|----------|-------|
| Operation type | WRITE (buffer modification) |
| Insert position | `point-max` (append) |
| Calls `save-buffer`? | NO |
| Requires daemon? | YES |
| Error on missing buffer? | YES (`with-current-buffer` signals) |
| Validates arg count? | NO (silent nil insertion) |
| Handles Unicode? | YES |
| Handles newlines? | YES |
| Handles embedded quotes? | YES (via `prin1-to-string`) |
| Return value | `"inserted N chars"` |

## Recommendations

1. **Argument validation**: The sexp builder should check that both args
   are non-nil before building the sexp, to avoid silent `nil` insertion.
2. **Consider `get-buffer-create` variant**: A separate tool or flag
   could create the buffer if it does not exist, rather than erroring.
3. **Insert position variant**: Some use cases may want insert at point
   rather than point-max. The current append-only behavior is documented
   and correct for the common case.
