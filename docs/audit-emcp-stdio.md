# Audit Report: docs/emcp-stdio.org and docs/emcp-stdio-api.org

**Date**: 2026-03-18
**Auditor**: Claude Code (automated)
**Source file**: `src/emcp-stdio.el` (415 lines, 24 definitions)
**Doc files**: `docs/emcp-stdio.org` (752 lines), `docs/emcp-stdio-api.org` (68 lines)

## Summary

| Category | Pass | Fail | Notes |
|----------|------|------|-------|
| Source links (emcp-stdio.org) | 82 | 0 | All 82 links resolve to existing definitions |
| Source links (emcp-stdio-api.org) | 26 | 0 | All 26 links resolve to existing definitions |
| Cross-reference links | 9 | 0 | All external file targets exist |
| Completeness (source -> docs) | 24/24 | 0 | Every definition is documented |
| Completeness (docs -> source) | 24/24 | 0 | Every doc entry exists in source |
| Daemon tool coverage | 9/9 | 0 | All 9 daemon tools documented |
| Pcase branch coverage | 8/8 | 0 | All :build tools have pcase branches |
| Invariants documented | 10 | 0 | All enforced in code |
| Invariants undocumented | 0 | 4 | See below |
| Org-mode format | Pass | 0 | No syntax errors |

**Overall**: PASS with 4 minor recommendations.

## A. Source Links

### emcp-stdio.org

All 82 `[[file:../src/emcp-stdio.el::...]]` links were verified against the source.
Every link target matches a `defun`, `defvar`, or `defconst` in `src/emcp-stdio.el`.

**Broken links**: None.

### emcp-stdio-api.org

All 26 `[[file:../src/emcp-stdio.el::...]]` links were verified.

**Broken links**: None.

## B. Cross-Reference Links

| Link target | Exists? |
|-------------|---------|
| `../CLAUDE.md` | Yes |
| `../CONJECTURES.md` | Yes |
| `../README.org` | Yes |
| `conjectures/c-008-research.md` | Yes |
| `reference/batch-mode.md` | Yes |
| `reference/parsing-json.md` | Yes |
| `reference/coding-system-basics.md` | Yes |
| `reference/symbol-components.md` | Yes |
| `reference/synchronous-processes.md` | Yes |

Internal cross-references between emcp-stdio.org and emcp-stdio-api.org are also valid (both files reference each other).

**Broken cross-references**: None.

## C. Completeness Audit

### Source definitions (24 total)

| Type | Name | In emcp-stdio.org? | In emcp-stdio-api.org? |
|------|------|---------------------|------------------------|
| defconst | emcp-stdio--protocol-version | Yes | Yes |
| defconst | emcp-stdio--server-name | Yes | Yes |
| defconst | emcp-stdio--server-version | Yes | Yes |
| defvar | emcp-stdio--tools-cache | Yes | Yes |
| defvar | emcp-stdio-filter-fn | Yes | Yes |
| defvar | emcp-stdio--daemon-available | Yes | Yes |
| defvar | emcp-stdio--daemon-tool-defs | Yes | Yes |
| defun | emcp-stdio--read-line | Yes | Yes |
| defun | emcp-stdio--send | Yes | Yes |
| defun | emcp-stdio--respond | Yes | Yes |
| defun | emcp-stdio--respond-error | Yes | Yes |
| defun | emcp-stdio--text-consumer-p | Yes | Yes |
| defun | emcp-stdio--build-tool | Yes | Yes |
| defun | emcp-stdio--collect-tools | Yes | Yes |
| defun | emcp-stdio--check-daemon | Yes | Yes |
| defun | emcp-stdio--daemon-eval | Yes | Yes |
| defun | emcp-stdio--build-daemon-tools | Yes | Yes |
| defun | emcp-stdio--daemon-build-sexp | Yes | Yes |
| defun | emcp-stdio--daemon-call | Yes | Yes |
| defun | emcp-stdio--handle-initialize | Yes | Yes |
| defun | emcp-stdio--handle-tools-list | Yes | Yes |
| defun | emcp-stdio--handle-tools-call | Yes | Yes |
| defun | emcp-stdio--dispatch | Yes | Yes |
| defun | emcp-stdio-start | Yes | Yes |

**Undocumented functions**: None.
**Phantom doc entries (not in source)**: None.

### Daemon tool definitions (9 tools)

All 9 tools in `emcp-stdio--daemon-tool-defs` are documented in the "Daemon Tools Reference" section:

| Tool | In defvar? | In pcase? | In doc table? | In doc detail? |
|------|-----------|-----------|---------------|----------------|
| emcp-data-eval | Yes | N/A (:raw) | Yes | Yes |
| emcp-data-buffer-list | Yes | Yes | Yes | Yes |
| emcp-data-buffer-read | Yes | Yes | Yes | Yes |
| emcp-data-buffer-insert | Yes | Yes | Yes | Yes |
| emcp-data-find-file | Yes | Yes | Yes | Yes |
| emcp-data-org-headings | Yes | Yes | Yes | Yes |
| emcp-data-org-set-todo | Yes | Yes | Yes | Yes |
| emcp-data-org-table | Yes | Yes | Yes | Yes |
| emcp-data-org-capture | Yes | Yes | Yes | Yes |

Note: `emcp-data-eval` has handler type `:raw`, so it correctly has no pcase branch in `emcp-stdio--daemon-build-sexp`. The `:raw` path in `emcp-stdio--daemon-call` (line 300) passes the first arg directly to `emcp-stdio--daemon-eval`, bypassing sexp construction entirely. This is correctly documented.

### Pcase branch coverage

All 8 `:build` daemon tools have corresponding pcase branches in `emcp-stdio--daemon-build-sexp`. The fallback `(_ (error ...))` branch (line 293) handles unknown names.

## D. Invariant Audit

### Documented invariants (10) -- all enforced

| # | Invariant | Enforced at | Lines |
|---|-----------|-------------|-------|
| 1 | JSON-RPC 2.0 framing | `emcp-stdio--read-line` / `emcp-stdio--send` | 41, 49 |
| 2 | UTF-8 encoding | `emcp-stdio-start` | 376-378 |
| 3 | One-line-per-message | `read-from-minibuffer` + `terpri` | 41, 49 |
| 4 | Tools cache immutability | Single `setq` in `emcp-stdio-start` | 391 |
| 5 | Symbol interning | `intern-soft` in `emcp-stdio--handle-tools-call` | 331 |
| 6 | Daemon stability | Runtime assumption (not code-enforced) | N/A |
| 7 | Argument type | `%S` formatting in local dispatch | 335 |
| 8 | No concurrent requests | Single `while` loop, no threading | 404 |
| 9 | Stderr for diagnostics | All `message` calls (not `princ`) | 385, 393, 410, 412 |
| 10 | Server internals excluded | `string-prefix-p "emcp-stdio-"` filter | 98 |

**Invariants claimed but not enforced**: None. Invariant 6 (daemon stability) is correctly described as a runtime assumption rather than an enforced constraint.

### Undocumented code-level invariants (4)

These are enforced in code but not listed in the Invariants section:

1. **Lexical binding**: The file header declares `lexical-binding: t` (line 1). This is a prerequisite for closures in `mapatoms` callbacks and lambda expressions throughout. Not mentioned in the invariants section.

2. **Required libraries**: `(require 'json)` and `(require 'help-fns)` (lines 17-18) are hard dependencies. If these are unavailable (which would be unusual), the server fails at load time. Not documented as an invariant.

3. **Empty line skipping**: The read loop skips empty lines via `(unless (string-empty-p line) ...)` (line 405). This prevents attempting to parse blank lines as JSON. Not mentioned as an invariant.

4. **JSON parse to alist**: `json-parse-string` is called with `:object-type 'alist` (line 408). The entire dispatch layer assumes alist representation. If this were changed to `plist` or `hash-table`, all `alist-get` calls would break. Not documented as an invariant.

## E. Format Audit

| Check | Result |
|-------|--------|
| Org link syntax `[[...][...]]` | 82 + 26 links, all balanced |
| `#+begin_src` / `#+end_src` balance | 13/13 matched |
| `#+begin_example` / `#+end_example` balance | 2/2 matched |
| Code blocks use `#+begin_src elisp` | Yes (12 elisp + 1 shell) |
| Table formatting (org pipe tables) | Correct in both files |
| `:PROPERTIES:` / `:END:` blocks | All matched |
| `CUSTOM_ID` properties | Present on all sections |
| No broken org-mode syntax | Pass |

## Recommendations

1. **Minor**: Consider documenting the 4 undocumented invariants (lexical binding, required libraries, empty line skipping, JSON-to-alist parse mode) in the Invariants section. These are all enforced in code but could surprise a contributor who changes them without understanding the downstream impact.

2. **Minor**: The doc states "9 data layer tools" in the Runtime Modes table (line 37) and in the daemon-tool-defs description (line 213). This count is correct today but is hardcoded. If a tool is added or removed from `emcp-stdio--daemon-tool-defs`, these references will become stale. Consider noting that the count is derived from `(length emcp-stdio--daemon-tool-defs)`.

3. **Cosmetic**: The Runtime Modes table (line 37) uses `+Daemon` and `+9` with strikethrough-style `+` markers. In org-mode export, `+text+` renders as strikethrough. If this is intentional (to show daemon is additive, not a separate mode), it may confuse readers who see it as struck-through text. Consider using a footnote or parenthetical instead.

4. **Informational**: The doc correctly notes that `emcp-data-eval` is "the most powerful and least safe daemon tool" (line 512). The security model for daemon tools relies entirely on `prin1-to-string` quoting in `:build` handlers and provides no quoting at all for `:raw` handlers. This is documented in the gotchas section but could be called out more prominently in the invariants section as a security boundary.
