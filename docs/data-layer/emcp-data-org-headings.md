# emcp-data-org-headings

Daemon data-layer tool that extracts org-mode headings from a file.

## Interface

- **Tool name**: `emcp-data-org-headings`
- **Arguments**: `[filename]` (single string, absolute path)
- **Requires**: running Emacs daemon (tool is unavailable without one)
- **Handler type**: `:build` (sexp constructed in `emcp-stdio--daemon-build-sexp`)

## Sexp Builder

Located in `src/emcp-stdio.el`, the `"emcp-data-org-headings"` branch of
`emcp-stdio--daemon-build-sexp`. Takes one arg (filename) and builds:

```elisp
(progn (require 'org)
  (with-current-buffer (find-file-noselect FILENAME)
    (mapconcat
     (lambda (c) (mapconcat #'identity c "\t"))
     (org-map-entries
      (lambda ()
        (let ((h (org-heading-components)))
          (list
           (make-string (nth 0 h) ?*)   ; level as stars
           (or (nth 2 h) "-")           ; TODO state or "-"
           (nth 4 h)                    ; title text
           (or (nth 5 h) "")))))        ; tags or ""
     "\n")))
```

## Output Format

Tab-separated, one heading per line:

```
level<TAB>state<TAB>title<TAB>tags
```

- **level**: stars matching depth (`*`, `**`, `***`, ...)
- **state**: TODO keyword or `-` if none
- **title**: heading text (without stars, state, or tags)
- **tags**: org tag string (e.g., `:tag1:tag2:`) or empty string

The entire result is returned as a single string within the MCP `text`
field, with `\n` separating lines. The string is Elisp-quoted (wrapped
in `"..."` with escaped newlines as `\n`).

## Test Results (2026-03-18)

Tested against Emacs 30.2, vanilla daemon (`emacs -Q --daemon`).

### Test 1: README.org -- basic headings with nesting

**Input**: `/Users/jwalsh/.../README.org`

**Result**: SUCCESS -- 25 headings returned.

Sample output (decoded):

```
*	-	What
*	-	Axiom
*	-	Elisp Server
**	-	Daemon Data-Layer Tools
*	-	Usage
**	-	Claude Code (=.mcp.json=)
```

**Observations**:
- Levels correctly distinguished (`*` vs `**`)
- No TODO states present in this file -- all show `-`
- No tags present in this file -- all show empty string
- Org markup in titles preserved as-is (e.g., `=.mcp.json=`)

### Test 2: spec.org -- headings without TODO states

**Input**: `/Users/jwalsh/.../spec.org`

**Result**: SUCCESS -- 20 headings returned.

Sample output (decoded):

```
*	-	Purpose and Scope
*	-	Architecture
**	-	Data Flow
**	-	Security Boundary
*	-	Components
**	-	L1: Introspector (=src/introspect.el=)
```

**Observations**:
- All headings show `-` for state (no TODO keywords in this file)
- Nested headings correctly leveled

### Test 3: CLAUDE.md -- non-org file

**Input**: `/Users/jwalsh/.../CLAUDE.md`

**Result**: ERROR

```json
{"isError": true, "content": [{"type": "text", "text": "error: daemon-eval failed: *ERROR*: Cache must be active"}]}
```

**Observations**:
- `find-file-noselect` opens the .md file but it enters `markdown-mode` (or `fundamental-mode`), not `org-mode`
- `org-map-entries` requires an active org cache, which only exists in org-mode buffers
- The error message ("Cache must be active") comes from org-mode's internal cache validation
- This is correct behavior: the tool is org-specific and should fail on non-org files
- A more descriptive error message would improve the user experience

### Test 4: Crafted file with TODO states, tags, and nesting

**Input**: `/tmp/emcp-test-headings.org`

```org
* TODO First heading                                                  :tag1:
** DONE Nested heading                                           :tag2:tag3:
*** Third level no state
* IN-PROGRESS Second top heading
** Nested without state
* DONE Third with empty tags
```

**Result**: SUCCESS

Decoded output:

```
*	TODO	First heading	:tag1:
**	DONE	Nested heading	:tag2:tag3:
***	-	Third level no state
*	-	IN-PROGRESS Second top heading
**	-	Nested without state
*	DONE	Third with empty tags
```

**Observations**:
- TODO and DONE states correctly extracted (these are default org keywords)
- Tags correctly extracted including multi-tag (`:tag2:tag3:`)
- Three-level nesting (`*`, `**`, `***`) correctly represented
- **Important**: `IN-PROGRESS` is NOT a standard org TODO keyword (only `TODO` and `DONE` are defaults in vanilla Emacs). Org treats it as part of the title text, not the state. The state column shows `-` and the title is `IN-PROGRESS Second top heading`. This is correct org-mode behavior. Custom TODO keywords require `#+TODO:` or `#+SEQ_TODO:` in the file header.
- Headings without tags show an empty string in the tags column

Verified with direct `org-heading-components` call:
```
(1 1 nil nil "IN-PROGRESS Second top heading" nil)
```
-- `nth 2` (TODO state) is `nil`, confirming the keyword is not recognized.

### Test 5: Non-existent file

**Input**: `/tmp/nonexistent-file-12345.org`

**Result**: Returns empty string `""`

**Observations**:
- `find-file-noselect` creates a new empty buffer for non-existent files (standard Emacs behavior)
- `org-map-entries` finds no headings, returns empty
- No error is raised -- this is arguably correct but could be surprising
- The daemon does not distinguish between "file not found" and "file has no headings"

### Test 6: Empty org file

**Input**: `/tmp/emcp-empty.org`

**Result**: Returns empty string `""`

**Observations**:
- Correct behavior: no headings means empty result

## Summary

| Test | Input | Result | Headings |
|------|-------|--------|----------|
| 1 | README.org | SUCCESS | 25 |
| 2 | spec.org | SUCCESS | 20 |
| 3 | CLAUDE.md | ERROR (Cache must be active) | n/a |
| 4 | crafted.org | SUCCESS | 6 |
| 5 | nonexistent.org | SUCCESS (empty) | 0 |
| 6 | empty.org | SUCCESS (empty) | 0 |

## Requirements

1. **Running Emacs daemon**: mandatory. Without one, returns `"No daemon available for emcp-data-org-headings"`.
2. **org-mode**: loaded via `(require 'org)` in the sexp. Built into Emacs, no external dependency.
3. **File must be org-mode compatible**: `.org` extension or org-mode association. Non-org files produce an error from org's cache system.

## Known Behaviors / Edge Cases

- Non-standard TODO keywords (e.g., `IN-PROGRESS`, `WAITING`) are treated as title text unless declared with `#+TODO:` in the file header or configured in the daemon's org settings
- Non-existent files return empty string (no error), because `find-file-noselect` silently creates a buffer
- The result string is Elisp-quoted: wrapped in double quotes with `\n` for newlines -- MCP clients must parse this
- The daemon may become unresponsive under load or after init.el errors; the batch MCP process uses `emacsclient --timeout 3` to detect this
- Vanilla daemon (`emacs -Q --daemon`) is sufficient; no user init required
