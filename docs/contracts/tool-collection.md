# Tool Collection Layer Contracts

Contracts for the obarray-walking and MCP tool schema construction
functions in `src/emcp-stdio.el` (lines 62-100).

## Functions

### `emcp-stdio--text-consumer-p` (SYM)

**Purpose**: Predicate that decides whether a symbol should be exposed
as an MCP tool based on its argument list.

**Input**: `SYM` -- an Emacs Lisp symbol (must be `fboundp`; caller
is responsible for checking this).

**Output**: Non-nil if SYM's arglist suggests it consumes text; `nil`
otherwise. Returns `nil` on any error (condition-case catches all).

**Algorithm**:
1. Obtain the arglist via `(help-function-arglist SYM t)`.
2. Coerce to string via `format "%s"`.
3. Match against the regex:
   ```
   string\|text\|str[^iua]\|buffer\|sequence\|object
   ```
4. Return `t` on match, `nil` otherwise.

**Regex pattern breakdown**:

| Branch | Matches | Rationale | Known false positive classes |
|--------|---------|-----------|----------------------------|
| `string` | Any arg containing "string" | Core text functions (string-trim, etc.) | Rare; "string" is precise |
| `text` | Any arg containing "text" | text-properties, text insertion | Low FP |
| `str[^iua]` | "str" not followed by i/u/a | Catches `strN`, `strp` style params | Excludes "stria", "strua" |
| `buffer` | Any arg containing "buffer" | Buffer manipulation functions | **High FP**: many functions take a buffer arg but are not text transformers (e.g., `buffer-live-p`, `buffer-size`) |
| `sequence` | Any arg containing "sequence" | Sequence operations (seq-*, cl-*) | **High FP**: `seq-length`, `seq-every-p` etc. are predicates, not text transformers |
| `object` | Any arg containing "object" | Generic dispatch functions | **Highest FP**: `object` is the default arg name for hundreds of predicates (`stringp`, `numberp`, `consp`, etc.) |

**Precision (C-002, refuted)**: A 50-function manual audit yielded 40%
precision (20 true positives, 30 false positives). The `object` and
`buffer` patterns dominate false positives. The original conjecture
that the heuristic would achieve >80% precision was refuted.

**Edge cases**:

| Case | Behavior |
|------|----------|
| Symbol with no arglist (e.g., alias to C primitive) | `help-function-arglist` may return `t` or a list; `format "%s"` handles both |
| Autoloaded function (not yet loaded) | `help-function-arglist` reads the autoload cookie; works without loading |
| Macro | `help-function-arglist` works for macros; they will be included if arglist matches |
| Special form | `help-function-arglist` works; special forms can match |
| Function signals error on arglist retrieval | `condition-case` catches and returns `nil` (excluded from tools) |

### `emcp-stdio--build-tool` (SYM)

**Purpose**: Construct a single MCP tool definition alist from a symbol.

**Input**: `SYM` -- an Emacs Lisp symbol that is `fboundp`.

**Output**: An alist with the following exact structure:

```elisp
((name . "symbol-name")
 (description . "docstring, truncated to 500 chars")
 (inputSchema
  . ((type . "object")
     (properties
      . ((args . ((type . "array")
                  (items . ((type . "string")))
                  (description . "(ARG1 ARG2 ...)")))))
     (required . ["args"]))))
```

**Invariants**:

1. `name` is always a string, the result of `(symbol-name SYM)`.
   It is a valid Elisp symbol name by construction.

2. `description` is a string. If the function has documentation,
   it is truncated to at most 500 characters. If `(documentation SYM t)`
   signals an error, the description is `""` (empty string).

3. `inputSchema` always has `type` = `"object"`.

4. `inputSchema.properties.args` always has `type` = `"array"` with
   `items.type` = `"string"`.

5. `inputSchema.properties.args.description` contains the formatted
   arglist signature string (e.g., `"(STRING &optional CHAR)"`)

6. `inputSchema.required` is always the vector `["args"]`.

**Edge cases**:

| Case | Behavior |
|------|----------|
| No docstring | `description` = `""` |
| Docstring exactly 500 chars | Returned verbatim (not truncated) |
| Docstring > 500 chars | Hard truncation at char 500, no ellipsis |
| Docstring contains newlines | Preserved as-is |
| No arglist (help-function-arglist returns t) | `description` in `args` field = `"t"` |
| Multibyte characters in docstring | Truncation is by `length` (character count), not byte count |

### `emcp-stdio--collect-tools` ()

**Purpose**: Walk the entire `obarray`, apply the filter predicate and
exclusion rules, and return a vector of MCP tool definitions.

**Input**: None (reads from global `obarray` and `emcp-stdio-filter-fn`).

**Output**: A vector of alists, each produced by `emcp-stdio--build-tool`.
The vector is suitable for JSON serialization as a JSON array.

**Algorithm**:
1. `mapatoms` over the default obarray.
2. For each symbol, include it if ALL of:
   - `(fboundp sym)` is non-nil
   - `(funcall emcp-stdio-filter-fn sym)` is non-nil
   - `(not (string-prefix-p "emcp-stdio-" (symbol-name sym)))` -- the
     server's own functions are excluded
3. Build the tool definition via `emcp-stdio--build-tool`.
4. Collect into a list, reverse (to approximate obarray insertion order),
   and convert to vector via `(apply #'vector ...)`.

**Invariants**:

1. The result is always a vector (never a list), because MCP `tools/list`
   requires a JSON array, and `json-serialize` maps vectors to arrays.

2. No tool in the result has a name starting with `"emcp-stdio-"`.

3. Every element in the vector satisfies the MCP tool schema structure
   defined in `emcp-stdio--build-tool`.

4. The tool count depends solely on:
   - The contents of `obarray` (which depends on `-Q` vs. init.el)
   - The value of `emcp-stdio-filter-fn`

5. With `emcp-stdio-filter-fn` set to `#'always`, the tool count equals
   the number of `fboundp` symbols in obarray minus the `emcp-stdio-*`
   symbols. This is the "true maximalist" mode.

6. With the default `#'emcp-stdio--text-consumer-p`, the tool count is
   a strict subset of the `always` count.

**Edge cases**:

| Case | Behavior |
|------|----------|
| Empty obarray (impossible in practice) | Returns empty vector `[]` |
| Filter returns non-nil for zero symbols | Returns empty vector `[]` |
| `emcp-stdio-filter-fn` is `#'always` | All `fboundp` symbols except `emcp-stdio-*` are included |
| Symbol is both fboundp and has a variable binding | Included (only fboundp matters) |
| Symbol is an autoload | Included if filter passes (arglist from autoload cookie) |

### `emcp-stdio-filter-fn` (variable)

**Purpose**: Configurable predicate that controls which functions are
exposed as MCP tools.

**Type**: Function -- `(SYM) -> non-nil | nil`

**Default value**: `#'emcp-stdio--text-consumer-p`

**Contract**:
- Must accept a single argument (a symbol).
- Must return non-nil to include the symbol, nil to exclude it.
- Must not signal errors (the collect loop does not protect against
  filter errors; a signaling filter will abort tool collection).
- The symbol passed is guaranteed to be `fboundp` (the caller checks
  this before calling the filter).

**Known configurations**:

| Value | Mode | Expected tool count (vanilla -Q) |
|-------|------|----------------------------------|
| `#'emcp-stdio--text-consumer-p` | Default/core | ~700-800 |
| `#'always` | True maximalist | ~8000+ |

## MCP Tool Schema Invariants (cross-cutting)

These invariants hold for every tool returned by `tools/list`:

1. **name**: string, non-empty, a valid Elisp symbol name
2. **description**: string (may be empty), at most 500 characters
3. **inputSchema.type**: always `"object"`
4. **inputSchema.properties.args.type**: always `"array"`
5. **inputSchema.properties.args.items.type**: always `"string"`
6. **inputSchema.required**: always `["args"]`
7. **No emcp-stdio- prefix**: no tool name starts with `"emcp-stdio-"`
8. **Deterministic structure**: all tools have identical schema shape;
   only `name`, `description`, and `args.description` vary

## Relationship to C-002

The `emcp-stdio--text-consumer-p` function is the implementation of the
heuristic tested by conjecture C-002. The conjecture hypothesized >80%
precision; the audit yielded 40%. The dominant false-positive sources:

- **`object` pattern**: matches every type predicate (`stringp`,
  `integerp`, `consp`, etc.) because they all take `(OBJECT)`.
  These are predicates, not text transformers.
- **`buffer` pattern**: matches buffer predicates and metadata readers
  (`buffer-live-p`, `buffer-size`, `buffer-modified-p`) that do not
  transform text.
- **`sequence` pattern**: matches seq library predicates and accessors.

A more precise heuristic would need to examine docstrings or function
behavior, not just argument names. However, improving precision is an
anti-goal of the maximalist project: the point is to expose everything
and observe the consequences.
