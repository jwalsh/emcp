# emcp-data-org-table: Test Results

Tested: 2026-03-18

## Overview

`emcp-data-org-table` is a daemon data-layer tool that extracts an org
table from a file, located by searching for a `table-name` string near
the table. It returns the table as tab-separated rows.

**Source**: `src/emcp-stdio.el`, lines 268-279 (sexp builder in
`emcp-stdio--daemon-build-sexp`).

**Arguments**: `(filename table-name)` — both strings, passed via the
MCP `args` array.

**Sexp built** (for `scores` in `/tmp/test.org`):
```elisp
(progn (require 'org)
 (with-current-buffer (find-file-noselect "/tmp/test.org")
 (goto-char (point-min))
 (search-forward "scores")
 (forward-line 1)
 (mapconcat (lambda (row)
  (if (eq row 'hline) "---"
   (mapconcat #'identity row "\t")))
  (org-table-to-lisp) "\n")))
```

## Test Setup

Test org file (`/tmp/emcp-test-table.org`):
```org
* Data

#+name: scores
| Name  | Score | Grade |
|-------+-------+-------|
| Alice |    95 | A     |
| Bob   |    82 | B     |
| Carol |    91 | A     |

#+name: config
| Key     | Value     |
|---------+-----------|
| timeout | 30        |
| retries | 3         |
```

Edge case file (`/tmp/emcp-test-table2.org`):
```org
#+name: sparse
| A | B | C |
|---+---+---|
| x |   | z |
|   | y |   |

#+name: wide-padding
|  Alpha   |  Beta  |
|----------+--------|
|  hello   |  world |
```

## Results

### 1. Tab-separated rows: YES

The tool returns rows delimited by `\n`, with columns delimited by
`\t`. From the `scores` table, the decoded content is:

```
Name	Score	Grade
---
Alice	95	A
Bob	82	B
Carol	91	A
```

### 2. Hline separators as "---": YES

Org table horizontal rules (`|---+---+---|`) are represented as the
literal string `---` on their own line. Confirmed in both the `scores`
and `config` table outputs.

### 3. Finds the right table by name: YES

- `table-name="scores"` returned the 3-row scores table (Name/Score/Grade).
- `table-name="config"` returned the 2-row config table (Key/Value).
- Each returned only the table immediately following the matched name.

The mechanism is `search-forward` for the table-name text, then
`forward-line 1` to land on the table itself. This means the
`table-name` argument matches any text, not just `#+name:` attributes.
It would also match a heading or paragraph containing the search term,
as long as a table follows on the next line.

### 4. Nonexistent table name: ERROR

Request with `table-name="nonexistent"` returned:

```json
{
  "content": [{"type": "text", "text": "error: daemon-eval failed: *ERROR*: Search failed: \"nonexistent\""}],
  "isError": true
}
```

The error is correctly propagated: `search-forward` signals a search
failure, caught by the MCP error handler, returned with `isError: true`.

### 5. Column values trimmed: YES

From the `wide-padding` table (org source has `|  Alpha   |  Beta  |`),
the output was:

```
Alpha	Beta
---
hello	world
```

`org-table-to-lisp` strips padding whitespace from cell values.
Confirmed: no leading or trailing spaces in any cell.

### 6. Empty cells: EMPTY STRINGS

From the `sparse` table:

```
A	B	C
---
x		z
	y
```

Empty cells produce empty strings between tab delimiters. The tab
separators are always present, so column structure is preserved.
Consumers can parse reliably by splitting on `\t`.

## Known Issue: Text Properties in Output

The daemon returns Emacs propertized strings in `#(...)` read syntax.
For the `scores` table, the raw output was:

```
#("Name\tScore\tGrade\n---\nAlice\t95\tA\nBob\t82\tB\nCarol\t91\tA"
  0 4 (fontified nil) 5 10 (fontified nil) ...)
```

This happens because `org-table-to-lisp` returns propertized strings
(with `fontified` properties from font-lock), and `emacsclient --eval`
prints the full Elisp read syntax including properties.

**Impact**: MCP clients receive the `#(...)` wrapper rather than a
plain string. The actual data is extractable (it is the first element
of the `#(...)` form), but clients must parse or ignore the property
annotations.

**Potential fix** (not applied per instructions): Wrap the
`mapconcat` result in `substring-no-properties` before returning:

```elisp
(substring-no-properties (mapconcat ...))
```

## Summary

| Question                         | Result            |
|----------------------------------|-------------------|
| Tab-separated rows?              | Yes               |
| Hlines as "---"?                 | Yes               |
| Finds table by name?             | Yes               |
| Nonexistent name handling?       | Error with isError |
| Column values trimmed?           | Yes               |
| Empty cell handling?             | Empty strings     |
| Text properties in output?       | Yes (known issue) |
