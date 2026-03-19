# emcp-data-org-set-todo

Daemon data-layer tool. Changes the TODO state of an org heading via
`emacsclient --eval` against a running Emacs daemon.

## Signature

```
(filename heading new-state)
```

- **filename** -- absolute path to the org file
- **heading** -- text to match against heading titles (substring match via `regexp-quote`)
- **new-state** -- target TODO keyword (e.g. `"DONE"`, `"TODO"`, or `""` to clear)

## Generated Sexp

The sexp builder in `emcp-stdio--daemon-build-sexp` produces:

```elisp
(progn (require 'org)
  (with-current-buffer (find-file-noselect "/tmp/file.org")
    (goto-char (point-min))
    (re-search-forward (concat "^\\*+ .*" (regexp-quote "Buy milk")))
    (org-todo "DONE")
    (save-buffer)
    (format "set %s to %s" "Buy milk" "DONE")))
```

Key points:
- Uses `find-file-noselect` to open the buffer without displaying it
- `re-search-forward` with `regexp-quote` prevents heading text from being
  interpreted as regex
- `org-todo` handles the actual state transition (respects org-todo-keywords)
- `save-buffer` persists changes to disk immediately
- Returns a confirmation string: `"set <heading> to <state>"`

## Test Results (2026-03-18)

### Test file

```org
* TODO Buy milk
* DONE Write tests
* TODO Fix bug
** TODO Subtask one
** DONE Subtask two
```

### 1. Basic TODO -> DONE transition

**Input:** `("emcp-data-org-set-todo", args: ["/tmp/emcp-test-todo.org", "Buy milk", "DONE"])`

**Result:** `"set Buy milk to DONE"` -- PASS

Headings after:
```
*   DONE   Buy milk
*   DONE   Write tests
*   TODO   Fix bug
**  TODO   Subtask one
**  DONE   Subtask two
```

File on disk confirmed changed: `* DONE Buy milk`

### 2. save-buffer verification

The file is saved to disk after each `org-todo` call. Confirmed by reading
`/tmp/emcp-test-todo.org` after the MCP call -- the `* TODO Buy milk` line
was rewritten to `* DONE Buy milk`.

### 3. Before/after verification via emcp-data-org-headings

- **id:10 (before):** `*  TODO  Buy milk` in heading list
- **id:12 (after):**  `*  DONE  Buy milk` in heading list

Round-trip confirmed: the heading state reported by `emcp-data-org-headings`
reflects the change made by `emcp-data-org-set-todo`.

### 4. Nonexistent heading

**Input:** `args: ["/tmp/emcp-test-todo.org", "Nonexistent heading", "TODO"]`

**Result:** Error returned correctly:

```
error: daemon-eval failed: *ERROR*: Search failed: "^\\*+ .*Nonexistent heading"
```

The `re-search-forward` throws a search-failed error, which propagates as
an MCP error response with `isError: true`. No file modification occurs.

### 5. Partial heading matches

**Input:** `args: ["/tmp/emcp-test-todo.org", "Buy", "DONE"]`

**Result:** `"set Buy to DONE"` -- matches **first** occurrence only.

With two headings "Buy milk" and "Buy eggs", the partial match "Buy" changes
only "Buy milk" (the first match from `point-min`). "Buy eggs" is unaffected.

This is a substring match via `regexp-quote`, so:
- `"milk"` matches `* TODO Buy milk` (substring in title)
- `"Buy"` matches the first `Buy *` heading only
- Exact heading text is not required

**Caveat:** There is no way to target the second of two headings that share
a substring. The regex always matches the first from buffer start.

### 6. Subtask handling

**Input:** `args: ["/tmp/emcp-test-todo.org", "Subtask one", "DONE"]`

**Result:** `"set Subtask one to DONE"` -- PASS

The regex `^\\*+ .*Subtask one` matches headings at any depth. The `\\*+`
prefix matches one or more stars, so both `* TODO ...` and `** TODO ...`
headings are searchable.

### 7. DONE -> TODO reversal

**Input:** `args: ["/tmp/emcp-test-todo.org", "Write tests", "TODO"]`

**Result:** `"set Write tests to TODO"` -- PASS

Headings confirm the state changed from DONE back to TODO. Bidirectional
state transitions work correctly.

### 8. Clearing TODO state (empty string)

**Input:** `args: ["/tmp/emcp-test-todo.org", "Fix bug", ""]`

**Result:** `"set Fix bug to "` -- the TODO keyword is removed.

Headings show: `*  -  Fix bug` (the `-` indicates no TODO state).
The heading becomes a plain heading with no keyword. On disk: `* Fix bug`.

## Edge Cases and Limitations

| Case | Behavior |
|------|----------|
| Nonexistent heading | Error: `Search failed` -- clean MCP error, no file change |
| Partial match | Matches first heading containing the substring |
| Multiple matches | Only first match is affected (re-search-forward from point-min) |
| Subtasks (any level) | Matched -- `\\*+` covers all heading depths |
| DONE -> TODO | Works -- bidirectional transitions |
| Empty new-state `""` | Clears TODO keyword entirely -- heading becomes plain |
| No daemon running | Error: `No daemon available for emcp-data-org-set-todo` |
| File not found | Emacs creates a new buffer (standard find-file-noselect behavior) |

## Source

Sexp builder: `src/emcp-stdio.el`, function `emcp-stdio--daemon-build-sexp`,
`"emcp-data-org-set-todo"` branch (lines 252-266).
