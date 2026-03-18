# Elisp Manual: Parsing and Generating JSON

**Source**: https://www.gnu.org/software/emacs/manual/html_node/elisp/Parsing-JSON.html
**Section**: 33.31 Parsing and generating JSON values
**Fetched**: 2026-03-18

## Full Text

The Emacs JSON (JavaScript Object Notation) support provides several
functions to convert between Lisp objects and JSON values. Any JSON value
can be converted to a Lisp object, but not vice versa. Specifically:

### Type Mapping (JSON -> Elisp)

| JSON type | Elisp representation |
|-----------|---------------------|
| `true` | symbol `t` |
| `null` | symbol `:null` (default) |
| `false` | symbol `:false` (default) |
| number (float) | Lisp integer or float |
| string | Lisp string (Unicode/UTF-8) |
| array | Lisp vector (default) or list |
| object | Lisp hash-table (default), alist, or plist |

**Important**: JSON strings are always Unicode strings encoded in UTF-8.
Lisp strings can contain non-Unicode characters.

**Important**: `nil`, being both a valid alist and a valid plist,
represents `{}` (the empty JSON object) -- **not** `null`, `false`, or
an empty array, all of which are different JSON values.

When an alist or plist contains several elements with the same key, Emacs
uses only the first element for serialization, in accordance with `assq`.

### Error Types

| Error | When |
|-------|------|
| `json-unavailable` | Parsing library isn't available |
| `json-end-of-file` | Premature end of input |
| `json-trailing-content` | Unexpected input after first JSON object |
| `json-parse-error` | Invalid JSON syntax |

### Function: `json-serialize` object &rest args

Returns a new Lisp **unibyte** string containing the JSON representation
of *object*.

Keyword arguments:

- **`:null-object`** -- Lisp object to represent JSON `null`. Default: `:null`.
- **`:false-object`** -- Lisp object to represent JSON `false`. Default: `:false`.

### Function: `json-insert` object &rest args

Inserts the JSON representation of *object* into the current buffer
before point. Arguments interpreted as in `json-serialize`.

### Function: `json-parse-string` string &rest args

Parses the JSON value in *string* (must be a Lisp string). Signals
`json-parse-error` if *string* doesn't contain valid JSON.

Keyword arguments:

- **`:object-type`** -- How to represent JSON objects:
  - `hash-table` (default): hash tables with string keys
  - `alist`: alists with symbol keys
  - `plist`: plists with keyword symbol keys
- **`:array-type`** -- How to represent JSON arrays:
  - `array` (default): Lisp vectors
  - `list`: Lisp lists
- **`:null-object`** -- Lisp object for JSON `null`. Default: `:null`.
- **`:false-object`** -- Lisp object for JSON `false`. Default: `:false`.

### Function: `json-parse-buffer` &rest args

Reads the next JSON value from the current buffer, starting at point.
Moves point past the value on success. Arguments as in `json-parse-string`.

---

## Relevance to emacs-mcp-maximalist

### Critical path: JSON-RPC protocol

The MCP server uses `json-serialize` and `json-parse-string` as the
primary JSON codec for the JSON-RPC 2.0 protocol over stdin/stdout.

### Key design decisions

1. **`json-serialize` returns unibyte**: The result is a unibyte string.
   When writing to stdout in batch mode, this interacts with
   `coding-system-for-write`. For clean UTF-8 output, ensure the coding
   system is set to `utf-8`.

2. **`json-parse-string` with `:object-type 'alist`**: Using alists
   instead of hash-tables makes it easier to work with parsed JSON-RPC
   messages in Elisp, since `assoc`/`alist-get` are convenient. However,
   hash-tables are the default.

3. **nil = empty object, not null**: This is a critical gotcha. If a tool
   returns `nil`, `json-serialize` will produce `{}`, not `null`. To
   produce JSON `null`, use `:null`. To produce an empty array, use `[]`
   (an empty vector).

4. **`:false` vs `nil`**: JSON `false` is `:false` by default, not `nil`.
   This is important for boolean tool results.

### Gotchas

- `json-serialize` signals `wrong-type-argument` for non-serializable
  objects. Tool dispatch must catch this when function return values
  contain buffers, markers, or other non-serializable types.

- JSON strings must be Unicode/UTF-8. If Emacs strings contain
  non-Unicode characters (e.g., raw bytes from file I/O), serialization
  may fail or produce unexpected results.

- `json-parse-string` with `:object-type 'plist` uses keyword symbols
  (`:key`), while `'alist` uses plain symbols (`key`). The choice
  affects how you access parsed JSON-RPC fields like `"jsonrpc"`,
  `"method"`, `"params"`, `"id"`.

- `json-available-p` can be used to check at startup whether JSON
  support is compiled in (it is in all modern Emacs builds, but worth
  a guard for portability).
