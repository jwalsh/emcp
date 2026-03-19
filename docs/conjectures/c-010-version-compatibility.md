# C-010: Emacs Version Compatibility

## Conjecture

emcp-stdio.el works correctly on Emacs 28.1+, 29.x, 30.x, and 31.x
without modification.

## Status: CONFIRMED (with caveats)

emcp-stdio.el is compatible with Emacs 27.1 through 31.x (development
master) without modification. The effective minimum version is **27.1**
(set by `json-serialize` / `json-parse-string`), not 28.1 as initially
hypothesized. All version-sensitive functions are either preloaded or
available through transitive `(require 'json)` dependencies across
every tested version.

## Function Version Audit

Every built-in, macro, and special form used by emcp-stdio.el,
categorized by introduction version:

### C Primitives (always available, pre-Emacs 20)

| Function | Source | Notes |
|----------|--------|-------|
| `condition-case` | special form | Ancient |
| `read-from-minibuffer` | C primitive | Ancient |
| `princ` | C primitive | Ancient |
| `terpri` | C primitive | Ancient |
| `make-hash-table` | C primitive | Ancient |
| `prin1-to-string` | C primitive | Ancient |
| `call-process` | C primitive | Ancient |
| `mapatoms` | C primitive | Ancient |
| `fboundp` | C primitive | Ancient |
| `symbol-name` | C primitive | Ancient |
| `intern-soft` | C primitive | Ancient |
| `funcall` | C primitive | Ancient |
| `eval` | C primitive | Ancient |
| `read` | C primitive | Ancient |
| `format` | C primitive | Ancient |
| `length` | C primitive | Ancient |
| `substring` | C primitive | Ancient |
| `concat` | C primitive | Ancient |
| `nreverse` | C primitive | Ancient |
| `apply` | C primitive | Ancient |
| `append` | C primitive | Ancient |
| `zerop` | C primitive | Ancient |
| `string=` | C primitive | Ancient |
| `error-message-string` | C primitive | Ancient |
| `decode-coding-string` | C primitive | Emacs 20+ |
| `message` | C primitive | Ancient |

### Preloaded Lisp (subr.el, always available)

| Function | Introduced | Source |
|----------|-----------|--------|
| `string-match-p` | 23.1 | C primitive |
| `string-prefix-p` | 24.1 | subr.el |
| `string-suffix-p` | 24.4 | subr.el (used in tests only) |
| `split-string` | ancient | subr.el |
| `mapconcat` | ancient | subr.el |
| `alist-get` | 25.1 | subr.el |
| `string-trim` | 26.1 | subr.el (moved from subr-x) |
| `string-trim-left` | 26.1 | subr.el |
| `string-trim-right` | 26.1 | subr.el |
| `assoc` (3-arg) | 26.1 | C primitive (TESTFN argument) |
| `set-language-environment` | 20.x | mule.el (preloaded) |

### Native JSON API (Emacs 27.1+)

| Function | Introduced | Notes |
|----------|-----------|-------|
| `json-serialize` | 27.1 | C primitive, requires jansson |
| `json-parse-string` | 27.1 | C primitive, requires jansson |
| `json-parse-error` | 27.1 | Error condition, C-defined |

The `:object-type 'alist` keyword argument to `json-parse-string`
was part of the initial API in 27.1.

### Preloaded from 27.1+

| Function | Introduced | Source |
|----------|-----------|--------|
| `set-binary-mode` | 26.1 | C primitive (guarded with `fboundp`) |
| `seq-remove` | 25.1 | seq.el (preloaded from 27.1) |

### Version-sensitive: subr-x functions

| Function | In subr-x | Moved to | Always available from |
|----------|-----------|----------|-----------------------|
| `string-empty-p` | 24.4 | simple.el | 29.1 |
| `string-blank-p` | 24.4 | subr-x | not used |

### Other requires

| Function | Source | Loaded via |
|----------|--------|-----------|
| `help-function-arglist` | help.el | Preloaded (loadup.el) |
| `pcase` | pcase.el | Preloaded |
| `documentation` | C primitive | Always available |
| `ignore-errors` | subr.el | Preloaded |

### Macros and special forms

| Form | Introduced | Notes |
|------|-----------|-------|
| `defconst` | ancient | special form |
| `defvar` | ancient | special form |
| `defun` | ancient | special form |
| `let` / `let*` | ancient | special form |
| `when` / `unless` | ancient | subr.el macros |
| `push` | ancient | subr.el macro |
| `pcase` | 24.1 | pcase.el (preloaded) |
| `condition-case` | ancient | special form |
| `with-temp-buffer` | ancient | subr.el macro |

## Transitive Dependency Chain

The `(require 'json)` in emcp-stdio.el creates a critical transitive
dependency chain that resolves all version-sensitive functions:

```
(require 'json)                    ; emcp-stdio.el line 17
  json.el (require 'subr-x)       ; json.el line 69 -- all versions 27.1-31.x
    subr-x.el: string-empty-p     ; available in 28.x via subr-x
  json.el (require 'map)          ; json.el line 68 -- all versions 27.1-31.x
    map.el (require 'seq)          ; map.el line 45 -- all versions
      seq.el: seq-remove           ; available in all versions
```

This chain is **stable across all tested versions** (27.1, 28.1, 29.1,
30.1, master/31.x). The `(require 'json)` line, while technically
unnecessary for the native `json-serialize`/`json-parse-string` C
primitives, serves the essential role of pulling in these transitive
dependencies.

### On Emacs 29.1+

`string-empty-p` moved from `subr-x.el` to `simple.el` (preloaded),
so it no longer depends on the transitive chain. `seq` is also
preloaded. The transitive dependencies become redundant but harmless.

## Version-Specific Risks

### Low risk: `(require 'json)` removal of subr-x dependency

If a future Emacs version removes the `(require 'subr-x)` from
`json.el`, Emacs 28.x would lose access to `string-empty-p`.
However:
- Emacs 28.x is already EOL
- On 29.1+, `string-empty-p` is preloaded
- Mitigation: add `(require 'subr-x)` to emcp-stdio.el (harmless on all versions)

### No risk: json-serialize availability

`json-serialize` and `json-parse-string` are C primitives compiled
into Emacs when the jansson library is available. All major Emacs
distributions (Homebrew, Debian, Fedora, MSYS2, emacs-plus) compile
with jansson support. An Emacs built without jansson would fail at
the `json-serialize` call, but this is a build configuration issue,
not a version issue.

### No risk: `set-binary-mode` guarded

The call to `set-binary-mode` is correctly guarded with `(when (fboundp 'set-binary-mode) ...)`, so it is safe on all versions including
hypothetical builds where it might not exist.

### No risk: Emacs 31 deprecations

No functions used by emcp-stdio.el appear in the Emacs 31 (master)
deprecation or obsolescence lists as of 2026-03-18.

## Minimum Version Determination

**Effective minimum: Emacs 27.1**

| Version | Compatible | Limiting factor |
|---------|-----------|-----------------|
| 26.x | No | `json-serialize` not available (added 27.1) |
| 27.1 | Yes | All functions available (string-empty-p via json -> subr-x) |
| 28.x | Yes | All functions available (string-empty-p via json -> subr-x) |
| 29.x | Yes | string-empty-p now preloaded in simple.el |
| 30.x | Yes | Tested directly on 30.2 |
| 31.x | Yes | No deprecations found in master NEWS |

The stated floor of "Emacs 28.1+" in the conjecture is conservative.
The actual floor is **Emacs 27.1**, set by the native JSON API
(`json-serialize`, `json-parse-string`).

## Test Results (Emacs 30.2)

### Version

```
GNU Emacs 30.2
```

### All functions available without explicit require

```
json-serialize: ok
json-parse-string: ok
seq-remove: ok
string-empty-p: ok
alist-get: ok
pcase: ok
string-prefix-p: ok
help-function-arglist: ok
string-match-p: ok
string-trim: ok
decode-coding-string: ok
set-language-environment: ok
split-string: ok
mapconcat: ok
error-message-string: ok
set-binary-mode: ok
make-hash-table: ok
intern-soft: ok
json-parse-error condition: ok
```

### ERT test suite

```
Ran 20 tests, 20 results as expected, 0 unexpected
```

## Test Commands

Verify on any target Emacs version:

```bash
# Check version
emacs --version

# Test all version-sensitive functions
emacs --batch -Q --eval '(progn
  (require (quote json))
  (require (quote help-fns))
  (message "json-serialize: %s" (condition-case nil (progn (json-serialize (list (cons (quote a) "b"))) "ok") (error "MISSING")))
  (message "json-parse-string: %s" (condition-case nil (progn (json-parse-string "{}" :object-type (quote alist)) "ok") (error "MISSING")))
  (message "seq-remove: %s" (condition-case nil (progn (seq-remove (quote identity) (list)) "ok") (error "MISSING")))
  (message "string-empty-p: %s" (condition-case nil (progn (string-empty-p "") "ok") (error "MISSING")))
  (message "string-trim: %s" (condition-case nil (progn (string-trim " a ") "ok") (error "MISSING")))
  (message "alist-get: %s" (condition-case nil (progn (alist-get (quote a) (list (cons (quote a) 1))) "ok") (error "MISSING")))
  (message "pcase: %s" (condition-case nil (progn (pcase "x" ("x" t)) "ok") (error "MISSING")))
  (message "string-prefix-p: %s" (condition-case nil (progn (string-prefix-p "a" "ab") "ok") (error "MISSING")))
  (message "help-function-arglist: %s" (condition-case nil (progn (help-function-arglist (quote car) t) "ok") (error "MISSING")))
  (message "assoc 3-arg: %s" (condition-case nil (progn (assoc "a" (list (list "a" 1)) (function string=)) "ok") (error "MISSING"))))' 2>&1

# Run ERT tests
emacs --batch -Q -l src/emcp-stdio.el -l tests/test-emcp-stdio.el \
  -f ert-run-tests-batch-and-exit 2>&1 | tail -5
```

## Recommendation

No code changes required. The current emcp-stdio.el is compatible with
Emacs 27.1 through 31.x. However, for robustness against future changes
to json.el's transitive dependencies, consider adding explicit requires:

```elisp
;; Optional: make dependencies explicit rather than relying on
;; (require 'json) -> subr-x/map/seq transitive chain
(require 'seq)      ; seq-remove
;; (require 'subr-x) ; string-empty-p -- only needed for Emacs 28.x
```

This is a "belt and suspenders" change, not a bug fix.

## Measurement

- Audit date: 2026-03-18
- Tested on: GNU Emacs 30.2 (macOS, Homebrew)
- Source verification: emacs-mirror/emacs tags emacs-27.1, emacs-28.1, emacs-29.1, emacs-30.1, master
- Method: source file inspection via GitHub raw URLs + local ERT test suite
