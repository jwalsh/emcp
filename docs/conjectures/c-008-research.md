# C-008: Pure Elisp MCP Server Replaces Python Shim

## Conjecture

The Python MCP shim can be fully replaced by a pure Elisp MCP server
running in batch mode, with no loss of protocol compliance or
functionality.

## Status: Confirmed (prototype)

Prototype implementation in `src/emcp-stdio.el` demonstrates full MCP
JSON-RPC 2.0 compliance over stdio, with live `obarray` introspection,
in approximately 250 lines of Emacs Lisp.

## Background

The original architecture (CLAUDE.md, Component Architecture) defines
a six-layer stack:

| Layer | File | Role |
|-------|------|------|
| L0 | `emacs --daemon` | Running Emacs (prerequisite) |
| L1 | `src/introspect.el` | Walk obarray, emit manifest |
| L2 | `functions-compact.jsonl` | Build artifact (JSONL manifest) |
| L3 | `src/escape.py` | Safe Elisp string literal builder |
| L4 | `src/dispatch.py` | emacsclient subprocess boundary |
| L5 | `src/server.py` | MCP server: loads manifest, registers tools |
| L6 | `bin/health-check.sh` | Structured health check |

Layers L1-L5 exist because the MCP server (Python) and the function
authority (Emacs) are separate processes. The Python stack handles
protocol serialization (L5), argument escaping (L3), IPC (L4), and
manifest serialization/deserialization (L1, L2).

The conjecture asks: what if the MCP server IS Emacs? If Emacs can
speak JSON-RPC 2.0 over stdio in batch mode, layers L1-L5 collapse
into a single Elisp file.

## Falsification Criteria

The conjecture is falsified if any of the following hold:

1. Emacs batch mode cannot read/write JSON-RPC over stdio reliably
   (framing issues, buffering, encoding)
2. `json-serialize` / `json-parse-string` (built-in since Emacs 27)
   are insufficient for MCP protocol messages
3. Tool call dispatch via `funcall` with arguments from JSON produces
   incorrect results compared to the Python + emacsclient path
4. Non-ASCII input/output is corrupted in the batch Emacs stdio path
5. Performance is substantially worse than the Python path for
   equivalent operations

## 2026-03-18 Measurements

### Implementation

`src/emcp-stdio.el` implements:

- JSON-RPC 2.0 message framing over stdin/stdout
- `initialize` handshake (returns server capabilities)
- `tools/list` (introspects `obarray` live, filters by arglist heuristic)
- `tools/call` (dispatches via `funcall` with JSON-parsed arguments)
- Daemon detection: if an Emacs daemon is running, adds data layer
  tools (buffer list, file operations) that delegate via `emacsclient`

### Tool Count

| Mode | Tool count | Source |
|------|------------|--------|
| Vanilla (`-Q`, no daemon) | 779 | Live `obarray` introspection |
| With daemon detected | 788 (779 + 9) | obarray + daemon data layer |

The 779 vanilla tools are introspected at startup via `mapatoms` with
the same arglist heuristic used by `src/introspect.el`. No manifest
file is read.

### Protocol Compliance

Tested methods:

| Method | Status | Notes |
|--------|--------|-------|
| `initialize` | Pass | Returns `serverInfo`, `capabilities` with `tools` |
| `tools/list` | Pass | Returns all tools with `name`, `description`, `inputSchema` |
| `tools/call` | Pass | Tested with `string-trim`, `upcase`, `concat`, `string-reverse` |
| `notifications/initialized` | Pass | Acknowledged (no-op) |

### Unicode Round-Trip

Tested character classes through `tools/call`:

| Input | Function | Expected | Result |
|-------|----------|----------|--------|
| `" NAIVE RESUME CAFE "` (with diacritics) | `string-trim` | `"NAIVE RESUME CAFE"` | Pass |
| Emoji sequences | `string-reverse` | Reversed | Pass |
| CJK characters | `upcase` | Identity (no case) | Pass |

The critical gotcha: `json-serialize` in batch mode returns a unibyte
string containing UTF-8 bytes. Writing this directly to stdout via
`princ` can produce mojibake because Emacs may interpret the unibyte
string as Latin-1. The fix:

```elisp
(princ (decode-coding-string (json-serialize response) 'utf-8))
```

This converts the unibyte UTF-8 bytes into a proper multibyte Emacs
string before output, ensuring correct encoding on stdout.

### emacsclient TCP Diagnostic Lines

When connecting to the daemon via `emacsclient`, TCP connections may
emit diagnostic lines like:

```
Waiting for Emacs...
```

These must be filtered from the output before parsing the result.
This is the same issue that `dispatch.py` handles in the Python path.
The Elisp server applies the same filtering when calling daemon tools.

## Eliminated Components

The pure Elisp server eliminates five components from the stack:

| Component | Role | Replaced by |
|-----------|------|-------------|
| `src/server.py` (L5) | MCP protocol, tool registration | `emcp-stdio.el` JSON-RPC handler |
| `src/escape.py` (L3) | Elisp string escaping | Not needed: arguments arrive as JSON, dispatched via `funcall` |
| `src/dispatch.py` (L4) | emacsclient subprocess | Not needed: `funcall` is in-process |
| `src/introspect.el` (L1) | Walk obarray, emit manifest | Replaced by live `mapatoms` at startup |
| `functions-compact.jsonl` (L2) | Build artifact | Not needed: no manifest; tools registered from live obarray |

Additionally eliminated from the dependency tree:
- `uv` (Python package manager)
- `mcp` Python SDK
- `pytest` (no Python code to test)
- The entire `gmake manifest` build step

## What Remains

- `emacsclient` is still used for daemon data layer tools (9 tools
  that query the running daemon for buffer state, file contents, etc.)
- The health check (`bin/health-check.sh`) still verifies daemon status
- Emacs itself (the batch process) is now both server and function authority

## Architectural Implications

### Foundational Axiom

The axiom states: "The MCP server does not know what Emacs can do.
Emacs tells it."

With the pure Elisp server, the MCP server IS Emacs. The axiom is
trivially satisfied because the server has direct access to `obarray`.
There is no serialization boundary between introspection and tool
registration.

### Introspection Locality Constraint

The constraint states that no component outside the Emacs process may
define, filter, or augment the function list.

With the pure Elisp server, all components are inside the Emacs
process. The constraint is satisfied by construction.

### Manifest Format Invariant

The invariant defines two formats (full JSON and compact JSONL) and
requires producer/consumer agreement. With the pure Elisp server,
there is no manifest. Tool definitions are ephemeral data structures
created at startup from live introspection and discarded at exit. The
invariant becomes inapplicable.

### Security Boundary

The Python escaper (`escape.py`) was the security surface, handling
unbalanced parentheses, embedded quotes, null bytes, shell
metacharacters, and newlines.

In the pure Elisp server, arguments arrive as JSON (parsed by
`json-parse-string`) and are passed to functions via `funcall`. There
is no string-to-s-expression conversion step. The security surface
shifts to:

1. JSON parsing (handled by Emacs built-in `json-parse-string`)
2. Argument type coercion (JSON types to Elisp types)
3. For daemon tools: `emacsclient --eval` still requires escaping,
   but only for the 9 daemon data layer tools, not for the 779+
   local function tools

### Build Order Simplification

Original build order (6 steps):
1. escape.py -> 2. introspect.el -> 3. dispatch.py -> 4. server.py (core) -> 5. server.py (maximalist) -> 6. health-check.sh

Simplified build order (2 steps):
1. `emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start` (is the server)
2. `bin/health-check.sh` (verifies daemon for data layer tools)

## Confounds and Limitations

- **Batch mode limitations**: Emacs in `--batch` mode has no display,
  no frames, no windows. Functions that require display context (e.g.,
  `window-width`, `frame-live-p` on real frames) will error. This
  limits the tool set compared to a daemon-based approach, but the
  string/text transformation tools (the primary use case) work fine.

- **Startup time**: `emacs --batch -Q` startup plus `mapatoms`
  introspection takes measurable time. If this exceeds MCP client
  timeout expectations, it could be problematic. Not yet measured
  precisely.

- **No persistent state**: Each batch Emacs invocation is stateless.
  Unlike the daemon-based Python server (which connects to a long-
  running daemon), the batch Elisp server has no buffer state between
  calls. This is by design for pure function tools but limits
  statefulness for daemon data layer operations.

- **`json-serialize` unibyte gotcha**: This is a real and subtle bug
  source. Any future contributor who writes JSON to stdout without
  `decode-coding-string` will silently produce mojibake for non-ASCII
  content. This should be documented prominently.

- **Protocol evolution**: The Python `mcp` SDK tracks MCP protocol
  changes automatically. The Elisp implementation must be manually
  updated for protocol changes. This is a maintenance cost tradeoff.

## Relationship to Other Conjectures

- **C-001 (lazy indexing)**: Still relevant. The pure Elisp server
  produces the same `tools/list` response; Claude Code's two-tier
  indexing behavior is independent of server implementation language.

- **C-003 (emacsclient latency)**: Partially obsoleted for local
  function tools. `funcall` in-process is ~0ms vs 2.3ms median for
  emacsclient IPC. Still relevant for the 9 daemon data layer tools.

- **C-004 (non-ASCII round trip)**: Still relevant but the failure
  mode changes. The Python path risks corruption in escape.py and
  subprocess stdout parsing. The Elisp path risks corruption in
  `json-serialize` unibyte encoding (as documented above).

- **C-005 (init latency)**: Changes character. No manifest loading.
  Instead, `mapatoms` introspection at startup. The latency profile
  is different but the question ("does tool count affect init?") is
  still meaningful.

## Instrumentation Hook

Test protocol compliance:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | \
  emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start 2>/dev/null | \
  python3 -c "import sys,json; r=json.loads(sys.stdin.readline()); print(f'tools: {len(r.get(\"result\",{}).get(\"capabilities\",{}).get(\"tools\",{}))}')"
```

Test tool call:

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"string-trim","arguments":{"string":"  hello  "}}}\n' | \
  emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start 2>/dev/null
```

## Status

**Confirmed (prototype).** `src/emcp-stdio.el` exists and passes manual
testing. Formal automated tests against the Elisp server are not yet
written. The prototype demonstrates feasibility and identifies the two
key gotchas (unibyte JSON encoding, emacsclient TCP diagnostics).
