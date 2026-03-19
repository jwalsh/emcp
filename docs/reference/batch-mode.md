# Elisp Manual: Batch Mode

**Source**: https://www.gnu.org/software/emacs/manual/html_node/elisp/Batch-Mode.html
**Section**: 43.17 Batch Mode
**Fetched**: 2026-03-18

## Full Text

The command-line option `-batch` causes Emacs to run noninteractively. In
this mode, Emacs does not read commands from the terminal, it does not
alter the terminal modes, and it does not expect to be outputting to an
erasable screen. The idea is that you specify Lisp programs to run; when
they are finished, Emacs should exit. The way to specify the programs to
run is with `-l file`, which loads the library named file, or `-f
function`, which calls function with no arguments, or `--eval=form`.

### Variable: `noninteractive`

This variable is non-`nil` when Emacs is running in batch mode.

### Error Handling

If the specified Lisp program signals an unhandled error in batch mode,
Emacs exits with a non-zero exit status after invoking the Lisp debugger
which shows the Lisp backtrace on the standard error stream:

```sh
$ emacs -Q --batch --eval '(error "foo")'; echo $?
```

```
Error: error ("foo")
mapbacktrace(#f(compiled-function ...))
debug-early-backtrace()
debug-early(error (error "foo"))
signal(error ("foo"))
error("foo")
eval((error "foo") t)
command-line-1(("--eval" "(error \"foo\")"))
command-line()
normal-top-level()
```

```
foo
255
```

### I/O in Batch Mode

Any Lisp program output that would normally go to the echo area, either
using `message`, or using `prin1`, etc., with `t` as the stream (see
Output Streams), goes instead to Emacs's standard descriptors when in
batch mode: **`message` writes to stderr**, while **`prin1` and other print
functions write to stdout**. Similarly, input that would normally come
from the minibuffer is read from the standard input descriptor. Thus,
Emacs behaves much like a noninteractive application program. (The echo
area output that Emacs itself normally generates, such as command
echoing, is suppressed entirely.)

### Encoding

Non-ASCII text written to the standard output or error descriptors is by
default encoded using `locale-coding-system` if it is non-`nil`; this
can be overridden by binding `coding-system-for-write` to a coding
system of your choice.

### GC Behavior

In batch mode, Emacs will enlarge the value of the `gc-cons-percentage`
variable from the default of 0.1 up to 1.0. Batch jobs that are supposed
to run for a long time should adjust the limit back down again, because
this means that less garbage collection will be performed by default (and
more memory consumed).

---

## Relevance to emcp

### Critical for JSON-RPC stdin loop

The project runs `emacs --batch` reading JSON-RPC from stdin. Key points:

1. **stdin reads via minibuffer**: Input from the minibuffer is read from
   stdin in batch mode. The server uses `read-from-minibuffer` or
   similar to read JSON-RPC messages from stdin.

2. **stdout vs stderr routing**: `prin1`/`princ` write to stdout (for
   JSON-RPC responses), while `message` writes to stderr (for logging).
   This separation is essential -- mixing them would corrupt the JSON-RPC
   protocol stream.

3. **Error exit behavior**: Unhandled errors cause exit with code 255.
   The server must wrap all processing in `condition-case` to avoid
   crashing on malformed input or tool execution errors.

4. **Encoding caveat**: Output encoding defaults to `locale-coding-system`.
   For reliable UTF-8 JSON output, the server should bind
   `coding-system-for-write` to `'utf-8` explicitly.

5. **GC tuning**: Long-running batch sessions (like a persistent MCP
   server) should reset `gc-cons-percentage` back to 0.1 to avoid
   unbounded memory growth.

### Gotchas

- There is no `read-from-stdin` function. In batch mode, functions like
  `read-from-minibuffer` and `read-string` read from stdin instead.
- The `noninteractive` variable can be checked to confirm batch mode.
- `-Q` flag (used for vanilla Emacs) suppresses loading user init files,
  which is important for reproducible manifest generation (C-006).
