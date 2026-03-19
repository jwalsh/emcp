# emcp-data-find-file Test Results

**Date:** 2026-03-18
**Tool:** `emcp-data-find-file`
**Source:** `src/emcp-stdio.el` line 237
**Sexp builder:** `(format "(buffer-name (find-file-noselect %S))" (nth 0 args))`

## Overview

`emcp-data-find-file` is a daemon data-layer tool that opens a file in the
running Emacs daemon using `find-file-noselect` and returns the buffer name.
It takes one argument (filename) and dispatches via `emacsclient --eval`.

The generated sexp for a call with `"/path/to/file.el"`:

```elisp
(buffer-name (find-file-noselect "/path/to/file.el"))
```

## Test Method

All tests run via MCP JSON-RPC over stdio:

```
emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start
```

Daemon was running (PID 5220). Server reported: 788 tools (779 local + 9 daemon).

## Test Results

### 1. Existing file returns buffer name

| id | Input | Result | Pass |
|----|-------|--------|------|
| 10 | `/Users/jwalsh/.../src/emcp-stdio.el` | `"emcp-stdio.el"` | YES |
| 11 | `/Users/jwalsh/.../CLAUDE.md` | `"CLAUDE.md"` | YES |

Both return the filename portion (buffer name), not the full path. This is
standard `find-file-noselect` behavior: the buffer name is the file's
base name unless there is a conflict.

### 2. Buffer appears in subsequent buffer-list

After opening `emcp-stdio.el` and `CLAUDE.md`, the `emcp-data-buffer-list`
call (id:13) output included:

```
emcp-stdio.el	/Users/jwalsh/.../src/emcp-stdio.el
CLAUDE.md	/Users/jwalsh/.../CLAUDE.md
```

Both buffers are visible in the daemon's buffer list with correct file
associations. **Pass.**

### 3. Nonexistent file

| id | Input | Result | Pass |
|----|-------|--------|------|
| 12 | `/nonexistent/path/file.txt` | `"file.txt"` | YES |

`find-file-noselect` creates a buffer for the nonexistent file without
error. The buffer exists (confirmed in buffer-list: `file.txt	/nonexistent/path/file.txt`)
but the underlying file does not exist on disk. This is standard Emacs
behavior -- the buffer is in a "new file" state.

**Note:** This is not an error condition. Emacs treats this as "visiting
a file that does not yet exist," which is the normal workflow for creating
new files.

### 4. Relative paths

| id | Input | Result | Pass |
|----|-------|--------|------|
| 20 | `README.org` | `"README.org"` | YES |

Relative paths are resolved by the daemon's `default-directory`. The file
was found because `README.org` exists in the daemon's working directory.
The buffer was created/reused successfully.

### 5. Paths with spaces and special characters

| id | Input | Result | Pass |
|----|-------|--------|------|
| 21 | `/tmp/test file with spaces.txt` | `"test file with spaces.txt"` | YES |
| 22 | `/tmp/test-special-chars-uber.txt` (umlaut) | `"test-special-chars-uber.txt"` (umlaut) | YES |

Both spaces and non-ASCII characters (German umlaut) are handled correctly.
The `%S` format specifier in the sexp builder properly escapes the filename
string for the Elisp reader.

### 6. Edge cases

| id | Input | Result | Notes |
|----|-------|--------|-------|
| 23 | `""` (empty string) | `"emcp"` | Opened `default-directory` as dired buffer |
| 24 | `~/nonexistent.txt` | `"nonexistent.txt"` | Tilde expanded, buffer created for new file |

- **Empty string:** `find-file-noselect` receives `""`, which Emacs
  interprets as `default-directory`. Returns the directory name as a dired
  buffer. Not an error, but callers should validate input.
- **Tilde expansion:** `find-file-noselect` expands `~` to the user's home
  directory. Works as expected.

## Security Considerations

The sexp builder uses `%S` (Elisp `prin1` format) which properly quotes
and escapes the filename argument. This prevents injection via:
- Embedded quotes in filenames
- Parentheses in filenames
- Shell metacharacters

The security boundary is the escaping done by `format "%S"` in the sexp
builder, which produces a properly quoted Elisp string literal.

## Summary

| Test | Status |
|------|--------|
| Returns buffer name for existing files | PASS |
| Buffer visible in daemon buffer-list | PASS |
| Nonexistent files create new-file buffers | PASS (expected behavior) |
| Relative paths resolved by daemon cwd | PASS |
| Paths with spaces | PASS |
| Non-ASCII characters (umlaut) | PASS |
| Empty string input | PASS (degrades to dired) |
| Tilde expansion | PASS |

All 8 test scenarios passed. The tool works correctly across all tested
input variations.
