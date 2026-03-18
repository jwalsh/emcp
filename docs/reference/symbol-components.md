# Elisp Manual: Symbol Components & Creating Symbols (obarray, mapatoms)

**Source**: https://www.gnu.org/software/emacs/manual/html_node/elisp/Symbol-Components.html
**Source**: https://www.gnu.org/software/emacs/manual/html_node/elisp/Creating-Symbols.html
**Sections**: 9.1 Symbol Components, 9.3 Creating and Interning Symbols
**Fetched**: 2026-03-18

## Symbol Components (9.1)

Each symbol has four components (or "cells"), each of which references
another object:

| Component | Description | Accessor |
|-----------|-------------|----------|
| Print name | The symbol's name (always a string, immutable) | `symbol-name` |
| Value | Current value as a variable | `symbol-value` |
| Function | Function definition (function, symbol, keymap, macro, autoload) | `symbol-function` |
| Property list | The symbol's property list | `symbol-plist` |

The print name cell always holds a string and cannot be changed.

The value cell may be *void* (not the same as holding `nil` or `void`).
Examining a void value cell signals: "Symbol's value as variable is void".

Because each symbol has separate value and function cells, variable names
and function names do not conflict (Lisp-2):

```elisp
buffer-file-name
     => "/gnu/elisp/symbols.texi"
(symbol-function 'buffer-file-name)
     => #<subr buffer-file-name>
```

## Creating and Interning Symbols (9.3)

### Obarrays

When the Lisp reader encounters a name that references a symbol in source
code, it looks up that name in a table called an **obarray** -- an
unordered container of symbols, indexed by name.

Finding or adding a symbol with a certain name is called **interning** it.
Interning ensures that each obarray has just one symbol with any
particular name.

**Uninterned symbols** are not in any obarray. They have the same four
cells but can only be accessed via references in other objects.

### Function: `obarray-make` &optional size

Creates and returns a new obarray.

### Function: `obarrayp` object

Returns `t` if *object* is an obarray.

### Function: `symbol-name` symbol

Returns the string that is *symbol*'s name.

```elisp
(symbol-name 'foo)
     => "foo"
```

**Warning**: Never alter the string returned by `symbol-name`. Doing so
might make Emacs dysfunctional or crash.

### Function: `make-symbol` name

Returns a newly-allocated, uninterned symbol whose name is *name*.

```elisp
(setq sym (make-symbol "foo"))
     => foo
(eq sym 'foo)
     => nil
```

### Function: `gensym` &optional prefix

Returns an uninterned symbol using `make-symbol`, with a unique name
formed by appending `gensym-counter` to *prefix* (default `"g"`).

### Function: `intern` name &optional obarray

Returns the interned symbol whose name is *name*. If no such symbol
exists, creates one, adds it to the obarray, and returns it. If
*obarray* is omitted, uses the global `obarray`.

```elisp
(setq sym (intern "foo"))
     => foo
(eq sym 'foo)
     => t
```

### Function: `intern-soft` name &optional obarray

Returns the symbol in *obarray* whose name is *name*, or `nil` if no
such symbol exists. Useful for testing whether a symbol is interned.

```elisp
(intern-soft "frazzle")
     => nil
(setq sym (intern "frazzle"))
     => frazzle
(intern-soft "frazzle")
     => frazzle
(eq sym 'frazzle)
     => t
```

### Variable: `obarray`

The standard obarray for use by `intern` and `read`.

### Function: `mapatoms` function &optional obarray

Calls *function* once with each symbol in the obarray *obarray*. Returns
`nil`. If *obarray* is omitted, defaults to the standard `obarray`.

```elisp
(setq count 0)
     => 0
(defun count-syms (s)
  (setq count (1+ count)))
     => count-syms
(mapatoms 'count-syms)
     => nil
count
     => 1871
```

### Function: `unintern` symbol obarray

Deletes *symbol* from *obarray*. Returns `t` if deleted, `nil` otherwise.

### Function: `obarray-clear` obarray

Removes all symbols from *obarray*.

---

## Relevance to emacs-mcp-maximalist

### The foundational mechanism: `mapatoms` over `obarray`

This is the core of `introspect.el` (Layer L1). The introspector walks
every symbol in the global `obarray` using `mapatoms`, checks each
symbol's function cell via `symbol-function`, and emits those that are
callable functions.

### Key design patterns

1. **`mapatoms` + `functionp` filter**:
   ```elisp
   (let (fns)
     (mapatoms
      (lambda (sym)
        (when (and (fboundp sym) (functionp (symbol-function sym)))
          (push sym fns))))
     fns)
   ```
   This is the fundamental pattern for discovering all functions.

2. **`symbol-name` for manifest keys**: Each function's name in the
   manifest (`n` field) comes from `(symbol-name sym)`.

3. **`symbol-function` for type detection**: Used to distinguish between
   subrs (C primitives), byte-compiled functions, interpreted functions,
   autoloads, macros, etc. The function cell can hold:
   - A compiled function (`byte-code-function-p`)
   - A subr (`subrp`)
   - A cons/closure (`closurep`)
   - An autoload object (`autoloadp`)
   - A keymap, symbol (function indirection), or keyboard macro

4. **`fboundp` guard**: Must check `fboundp` before `symbol-function` to
   avoid "Symbol's function definition is void" errors.

5. **`obarray` is the sole authority**: Per the foundational axiom, no
   component outside Emacs may define the function list. `mapatoms` on
   `obarray` is the only legitimate source.

### Gotchas

- `mapatoms` visits ALL symbols, including variables-only, faces, etc.
  The introspector must filter for `fboundp` symbols.
- The count from `mapatoms` varies by Emacs version and loaded packages.
  Vanilla `-Q` Emacs has fewer symbols than a configured one (C-006).
- `symbol-name` returns a shared string -- never mutate it.
- `intern-soft` is useful for checking if a specific function exists
  without creating it (e.g., when validating tool names from MCP clients).
