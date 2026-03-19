# emcp-data-buffer-list Test Results

**Date:** 2026-03-18
**Tool:** `emcp-data-buffer-list`
**Source:** `src/emcp-stdio.el` lines 152-154 (definition), 216-221 (sexp builder)
**Sexp builder:** hardcoded `mapconcat` over `(buffer-list)` -- ignores args

## Overview

`emcp-data-buffer-list` is a daemon data-layer tool that lists all open
buffers in the running Emacs daemon with their file associations. It takes
zero arguments and dispatches via `emacsclient --eval`.

The generated sexp (identical regardless of arguments passed):

```elisp
(mapconcat (lambda (b)
             (format "%s\t%s"
                     (buffer-name b)
                     (or (buffer-file-name b) "")))
           (buffer-list) "\n")
```

The sexp builder uses `prin1-to-string` to inject literal tab and newline
characters into the sexp string, avoiding embedded escaped quotes.

## Test Method

All tests run via MCP JSON-RPC over stdio:

```
emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start
```

Daemon was running (PID 5220). Server reported: 788 tools (779 local + 9 daemon).

**Note:** The daemon check (`emcp-stdio--check-daemon`) was non-deterministic
during testing -- the 3-second timeout in `call-process` sometimes expired
when a TCP-based `emacsclient` connection interfered with socket discovery.
This caused some test runs to report "no daemon" and return the error
`"error: No daemon available for emcp-data-buffer-list"`. Successful tests
occurred when the daemon was reached within the timeout.

## Test Results

### 1. Does it return a list of buffers?

**YES.** The tool returns a string containing one buffer per line, covering
all buffers in the daemon's `(buffer-list)`. A successful call returned 14
buffer lines.

Raw JSON-RPC response (id:10):

```json
{"jsonrpc":"2.0","id":10,"result":{"content":[{"type":"text","text":"\"*scratch*\t\\n ...\""}]}}
```

The `text` field contains an Emacs-quoted string (outer `"` quotes, `\\n`
for literal newlines, `\\t` for literal tabs).

### 2. What format? (tab-separated name\tfilename per line?)

**YES.** Each line is `name<TAB>filename`. When a buffer has no associated
file, the filename field is empty (empty string after the tab).

Parsed output from the successful test:

```
*scratch*
 *Minibuf-0*
*Messages*
 *code-conversion-work*
 *server*
emcp-test-table.org	/tmp/emcp-test-table.org
README.org	/Users/jwalsh/ghq/github.com/jwalsh/emacs-mcp-maximalist/README.org
spec.org	/Users/jwalsh/ghq/github.com/jwalsh/emacs-mcp-maximalist/spec.org
 *Org parse*
emcp-test-capture.org	/tmp/emcp-test-capture.org
emcp-stdio.el	/Users/jwalsh/ghq/github.com/jwalsh/emacs-mcp-maximalist/src/emcp-stdio.el
CLAUDE.md	/Users/jwalsh/ghq/github.com/jwalsh/emacs-mcp-maximalist/CLAUDE.md
file.txt	/nonexistent/path/file.txt
emcp-test-todo.org	/tmp/emcp-test-todo.org
```

### 3. Are system buffers (starting with space) included?

**YES.** System buffers (names starting with a space) are included in the
output. The test returned 4 system buffers:

| Buffer name | File |
|---|---|
| ` *Minibuf-0*` | (none) |
| ` *code-conversion-work*` | (none) |
| ` *server*` | (none) |
| ` *Org parse*` | (none) |

The sexp uses `(buffer-list)` without any filtering, so all buffers are
returned including internal/system buffers. Callers who want to exclude
system buffers should filter lines where the name starts with a space.

### 4. Are file-visiting buffers showing their file paths?

**YES.** File-visiting buffers show their full absolute paths in the second
tab-separated field. The test returned 8 file-visiting buffers:

| Buffer name | File path |
|---|---|
| emcp-test-table.org | /tmp/emcp-test-table.org |
| README.org | /Users/jwalsh/.../README.org |
| spec.org | /Users/jwalsh/.../spec.org |
| emcp-test-capture.org | /tmp/emcp-test-capture.org |
| emcp-stdio.el | /Users/jwalsh/.../src/emcp-stdio.el |
| CLAUDE.md | /Users/jwalsh/.../CLAUDE.md |
| file.txt | /nonexistent/path/file.txt |
| emcp-test-todo.org | /tmp/emcp-test-todo.org |

Note that `file.txt` shows `/nonexistent/path/file.txt` -- a buffer can
be "visiting" a file that does not exist on disk (new-file state from a
prior `find-file-noselect` call).

### 5. What happens with zero args (correct usage)?

**Works correctly.** The sexp builder for `emcp-data-buffer-list` does not
reference the `args` parameter at all. Calling with `"args":[]` (empty
array) produces the expected buffer list.

The tool definition declares arglist as `"()"` and the MCP inputSchema
reflects this:

```json
{
  "type": "object",
  "properties": {
    "args": {
      "type": "array",
      "items": {"type": "string"},
      "description": "()"
    }
  },
  "required": ["args"]
}
```

Note: the `args` array is still **required** by the schema even though
the tool takes no arguments. Callers must send `"args":[]`.

### 6. What happens with unexpected args?

**Silently ignored.** Calling with `"args":["unexpected","extra","args"]`
produces identical output to `"args":[]`.

Verified by directly testing the sexp builder:

```elisp
(string= (emcp-stdio--daemon-build-sexp "emcp-data-buffer-list" nil)
         (emcp-stdio--daemon-build-sexp "emcp-data-buffer-list"
                                         '("unexpected" "extra")))
;; => t
```

Both calls produce the same sexp string. The `"emcp-data-buffer-list"`
branch in the `pcase` does not destructure or reference `args`.

## Tool Registration

When a daemon is available, `emcp-data-buffer-list` appears in the
`tools/list` response as one of 9 daemon tools. When no daemon is
available, the tool is **not registered** -- it does not appear in
`tools/list` at all (779 tools vs 788 tools).

If a client somehow calls `emcp-data-buffer-list` when the daemon is
unavailable (e.g., daemon went down after registration), the response is:

```json
{"jsonrpc":"2.0","id":10,"result":{
  "content":[{"type":"text","text":"error: No daemon available for emcp-data-buffer-list"}],
  "isError":true}}
```

## Output Encoding

The daemon's `emacsclient` returns an Emacs string literal (outer double
quotes). The MCP server passes this through as the `text` field. The
actual tab and newline characters are represented as `\t` and `\n` in the
Emacs string encoding. Clients parsing the output need to:

1. Strip the outer `"` quotes (Emacs string literal framing)
2. Unescape `\n` to newlines and `\t` to tabs
3. Split on newlines to get individual buffer entries
4. Split each entry on tab to get `(name, filename)` pairs

## Summary

| Test | Status |
|------|--------|
| Returns list of buffers | PASS |
| Format is name\tfilename per line | PASS |
| System buffers (space-prefixed) included | PASS (no filtering) |
| File-visiting buffers show full paths | PASS |
| Zero args (correct usage) | PASS |
| Unexpected args silently ignored | PASS |
| No daemon: tool excluded from tools/list | PASS |
| No daemon: call returns isError | PASS |

All 8 test scenarios passed. The tool works correctly for its intended
purpose of enumerating daemon buffers with file associations.
