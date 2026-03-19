# emcp-data-org-capture Test Results

Date: 2026-03-18

## Tool Summary

`emcp-data-org-capture` is a daemon data-layer tool that appends a new
org entry under a heading in an org file. It is a WRITE operation.

**Arguments**: `(file heading body)` -- all strings.

**Sexp builder**: `src/emcp-stdio.el` lines 281-301
(`emcp-stdio--daemon-build-sexp`, `"emcp-data-org-capture"` branch).

**Behavior**:
- When HEADING exists: navigates to end of subtree, inserts `\n** BODY\n`.
  BODY becomes the sub-heading title at level 2.
- When HEADING does not exist: appends `\n* HEADING\nBODY\n` at end of file.
  HEADING becomes a top-level heading, BODY becomes body text below it.
- File is saved after each capture via `(save-buffer)`.
- Returns `"captured"` or `"captured at top level"` accordingly.

## Test Environment

- Emacs: `-Q --daemon` (vanilla, no init.el)
- MCP server: `emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start`
- Transport: JSON-RPC over stdio

## Test Results

### T1: Capture under existing heading (Inbox)

| Input | Result |
|-------|--------|
| file: `/tmp/emcp-test-capture.org` | |
| heading: `"Inbox"` | |
| body: `"New captured item"` | `"captured"` |

After capture:
```org
* Inbox
** Existing item
** New captured item
```

**PASS** -- entry added as `**` sub-heading under `* Inbox`, after existing children.

### T2: Capture under nonexistent heading

| Input | Result |
|-------|--------|
| heading: `"Nonexistent Section"` | `"captured at top level"` |
| body: `"Should create top-level"` | |

After capture:
```org
* Nonexistent Section
Should create top-level
```

**PASS** -- new `*` heading created at end of file, body appears as text
below heading (not a sub-heading).

### T3: Verify via org-headings after T1+T2

Response (tab-separated: level, state, title, tags):
```
*	-	Inbox
**	-	Existing item
**	-	New captured item
*	-	Projects
**	-	Project Alpha
*	-	Nonexistent Section
```

**PASS** -- `Nonexistent Section` appears as top-level heading with no
sub-headings (its body text is not promoted to a heading).

### T4: Verify via buffer-read after T1+T2

```org
* Inbox
** Existing item
** New captured item

* Projects
** Project Alpha

* Nonexistent Section
Should create top-level
```

**PASS** -- file content matches expected structure.

### T5: Multiple captures stack correctly

Three sequential captures under `* Inbox`:

```org
* Inbox
** Existing item
** First capture
** Second capture
** Third capture



* Projects
** Project Alpha
```

**PASS** -- entries stack in insertion order. Each new entry appears
after the last child of the subtree.

Note: blank lines accumulate between the last capture and the next
heading. Each `org-end-of-subtree` + `\n** ...\n` insert adds a trailing
newline that compounds. Cosmetic issue only; org-mode parses correctly.

### T6: Capture under auto-created heading

After creating `* New Section` at top level (T2), subsequent captures
under `"New Section"` correctly find the heading and add `**` sub-entries.

**PASS** -- verified via single-call emacsclient test combining create + capture.

## Validation Checklist

| # | Question | Answer |
|---|----------|--------|
| 1 | Does it add under "Inbox" as a sub-heading? | Yes. `** New captured item` inserted after `** Existing item`. |
| 2 | Does it save the file? | Yes. `(save-buffer)` called on both code paths. File on disk matches. |
| 3 | Can we verify by reading headings + buffer? | Yes. `emcp-data-org-headings` and `emcp-data-buffer-read` both confirm. |
| 4 | When heading doesn't exist, does it create at top level? | Yes. Returns `"captured at top level"`, creates `* HEADING` at EOF. |
| 5 | Does the body appear in the captured entry? | Yes, but asymmetrically: as heading title (`** BODY`) when parent exists; as body text below heading when creating top-level. |
| 6 | Multiple captures -- do they stack correctly? | Yes. Three sequential captures under Inbox produce three `**` entries in order. |

## Design Observations

### Body semantics are asymmetric

When the heading exists, the sexp inserts:
```elisp
(insert "\n** " body "\n")
```
So `body` becomes the **title** of a level-2 heading.

When the heading does not exist, the sexp inserts:
```elisp
(insert "\n* " heading "\n" body "\n")
```
So `body` becomes **body text** below the new heading, not a sub-heading.

This means the same `body` argument serves different structural roles
depending on whether the heading existed. A caller expecting to always
create a sub-heading would need to handle the top-level case differently.

### Trailing newline accumulation

Each capture inserts `\n** BODY\n`. After three stacked captures, the
file has three blank lines between the last capture and the next heading.
`org-end-of-subtree` navigates past existing blank lines, so the blank
lines are harmless for subsequent captures, but the file becomes visually
noisy.

### Daemon stability under MCP batch load

The Emacs daemon was observed to become unresponsive or lose its socket
during rapid sequential MCP batch sessions. The daemon tool calls
themselves succeed (capture logic is correct), but the daemon process
can die between MCP sessions. This appears to be an environment issue
(socket cleanup, process contention) rather than an org-capture bug.

Mitigation: the `emcp-stdio--check-daemon` function runs at MCP session
startup and disables daemon tools if the daemon is unreachable, returning
a clear error message rather than hanging.
