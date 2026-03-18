# Elisp Manual: Synchronous Processes

**Source**: https://www.gnu.org/software/emacs/manual/html_node/elisp/Synchronous-Processes.html
**Section**: 41.3 Creating a Synchronous Process
**Fetched**: 2026-03-18

## Full Text

After a synchronous process is created, Emacs waits for the process to
terminate before continuing. Starting Dired on GNU or Unix is an
example: it runs `ls` in a synchronous process, then modifies the output
slightly.

While Emacs waits for the synchronous subprocess to terminate, the user
can quit by typing `C-g`. The first `C-g` tries to kill the subprocess
with a `SIGINT` signal; but it waits until the subprocess actually
terminates before quitting. If during that time the user types another
`C-g`, that kills the subprocess instantly with `SIGKILL` and quits
immediately.

The output from a synchronous subprocess is generally decoded using a
coding system, much like text read from a file. The input sent to a
subprocess by `call-process-region` is encoded using a coding system,
much like text written into a file.

### Function: `call-process` program &optional infile destination display &rest args

Calls *program* and waits for it to finish.

The current working directory of the subprocess is set to the current
buffer's value of `default-directory` if that is local, or `~` otherwise.
To run in a remote directory, use `process-file`.

**Standard input**: comes from *infile* if non-`nil`, otherwise from the
null device.

**Destination** (where output goes):

| Value | Behavior |
|-------|----------|
| a buffer | Insert output in that buffer, before point |
| a string | Insert output in buffer with that name |
| `t` | Insert output in the current buffer |
| `nil` | Discard the output |
| `0` | Discard output, return `nil` immediately (async) |
| `(:file FILE)` | Send output to FILE, overwriting |
| `(REAL-DEST ERROR-DEST)` | Separate stdout and stderr |

For the `(REAL-DEST ERROR-DEST)` form:
- *error-destination* `nil` = discard stderr
- *error-destination* `t` = mix stderr with stdout
- *error-destination* string = redirect stderr to that file

**Return value**: A number (exit status; 0 = success) or a string
(describing a signal). Returns `nil` if destination was `0`.

```elisp
(call-process "pwd" nil t)
     => 0
;; Buffer now contains: /home/lewis/manual

(call-process "grep" nil "bar" nil "lewis" "/etc/passwd")
     => 0
;; Buffer "bar" now contains: lewis:x:1001:1001:...
```

### Function: `process-file` program &optional infile buffer display &rest args

Like `call-process`, but may invoke a file name handler based on
`default-directory`. This enables running commands on remote hosts (via
TRAMP, etc.).

Some file name handlers may not support all combinations of arguments.

### Variable: `process-file-side-effects`

Indicates whether `process-file` changes remote files. Default `t`. Set
to `nil` (via let-binding only) to optimize file attribute caching.

### Function: `call-process-region` start end program &optional delete destination display &rest args

Sends the text from *start* to *end* as standard input to *program*.
Deletes the sent text if *delete* is non-`nil`.

```elisp
(call-process-region 1 6 "cat" nil t)
     => 0
;; "input" text is duplicated in buffer
```

### Function: `call-process-shell-command` command &optional infile destination display

Executes *command* as a shell command synchronously.

### Function: `process-file-shell-command` command &optional infile destination display

Like `call-process-shell-command` but uses `process-file` internally.

### Function: `call-shell-region` start end command &optional delete destination

Sends text from *start* to *end* as stdin to an inferior shell running
*command*.

**Warning**: Behavior of various shells when commands are piped to their
stdin is shell- and system-dependent, especially with multi-line input.

### Function: `shell-command-to-string` command

Executes *command* as a shell command and returns its output as a string.

### Function: `process-lines` program &rest args

Runs *program*, waits for it to finish, returns output as a list of
strings (one per line, with end-of-line stripped). Signals an error if
*program* exits with non-zero status.

### Function: `process-lines-ignore-status` program &rest args

Like `process-lines` but does not signal an error on non-zero exit.

---

## Relevance to emacs-mcp-maximalist

### Primary IPC mechanism: `call-process` with `emacsclient`

The project uses `call-process` with `emacsclient --eval` as the IPC
boundary between the batch-mode MCP server and the Emacs daemon. This
is Layer L4 (dispatch).

### Key design considerations

1. **`call-process` vs `shell-command-to-string`**: `call-process` is
   preferred because it avoids shell interpretation of arguments, which
   is critical for security (no shell injection via tool arguments).

2. **Separate stderr**: Using `(REAL-DEST ERROR-DEST)` destination form,
   the project can capture `emacsclient` errors separately from output.
   This matters when `emacsclient --eval` returns an error.

3. **Return value checking**: Exit status 0 means success. Non-zero
   means `emacsclient` failed (daemon not running, eval error, etc.).
   The dispatch layer must check this.

4. **Coding system for output**: Output from `call-process` is decoded
   using a coding system. For UTF-8 safety, bind `coding-system-for-read`
   to `'utf-8` before calling `emacsclient`.

5. **Working directory**: `call-process` uses `default-directory`. If
   the batch-mode server's `default-directory` is unusual, this could
   affect `emacsclient` behavior.

### Gotchas

- `call-process` with destination `0` returns immediately without
  waiting -- do NOT use this for synchronous `emacsclient` calls.
- `process-lines` signals an error on non-zero exit. For `emacsclient`
  calls that might fail, use `call-process` directly or
  `process-lines-ignore-status`.
- The `C-g` quit behavior is irrelevant in batch mode (no terminal), but
  long-running `emacsclient` calls could block the server's event loop.

### Latency (C-003)

Conjecture C-003 claims `emacsclient` round-trip latency < 50ms for pure
string functions. The `call-process` overhead is: fork + exec + socket
connect to daemon + eval + result serialization + pipe read. Measurement
hooks should wrap `call-process` calls with timing.
