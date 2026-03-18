# Conjectures

Status tracking for the five open conjectures. Each requires a
measurement note: confirmed, refuted, or indeterminate with data.

Detailed research in `docs/conjectures/c-NNN-research.md`.

| ID | Claim | Status | Evidence |
|----|-------|--------|----------|
| C-001 | Claude Code uses on-demand tool indexing | Confirmed | Prior session (2026-02-04); re-verified 2026-03-17: 4324-tool server loads without crashing Claude Code. .mcp.json configured for both modes |
| C-002 | Arglist heuristic yields > 80% precision | Indeterminate | 4324/~30000 obarray symbols pass heuristic. Manual audit of 50 random functions pending |
| C-003 | emacsclient round-trip < 50ms for string fns | Confirmed | 2026-03-17: `(+ 1 1)` = 10.9ms, `(string-trim " hello ")` < 15ms. EMCP_TRACE=1 instrumented |
| C-004 | Non-ASCII survives full round trip | Confirmed | 2026-03-17: CJK, emoji, combining characters all survive escape -> emacsclient -> Emacs -> stdout. 6/6 live tests pass |
| C-005 | Maximalist manifest causes measurable init latency vs core | Confirmed | 2026-03-17: core=0.7ms (69 tools), maximalist=15.9ms (4324 tools). ~23x slower but both sub-second — not user-visible |

## Measurement Details

### C-001: On-demand tool indexing (Confirmed)

Claude Code connects to the 4324-tool maximalist server without
context window exhaustion. Tools are indexed lazily. Prior session
(2026-02-04) first observed this; re-verified 2026-03-17 with `.mcp.json`.

### C-003: emacsclient latency (Confirmed)

Measured with `EMCP_TRACE=1` on macOS, Emacs 30.1 daemon:
- `(+ 1 1)`: 10.9ms
- `(string-trim " hello ")`: ~15ms
- All pure string functions: < 50ms threshold

### C-004: Non-ASCII round trip (Confirmed)

Live integration tests (`tests/test_dispatch_live.py`):
- CJK characters survive
- Emoji (multi-byte UTF-8) survives
- Combining characters (e + combining acute) survive

### C-005: Init latency differential (Confirmed)

Measured with `EMCP_TRACE=1`:
- Core (69 tools): parse=0.3ms, build=0.4ms, total=0.7ms
- Maximalist (4324 tools): parse=6.2ms, build=9.7ms, total=15.9ms
- Ratio: ~23x, but both sub-second — not user-perceptible

### C-002: Arglist heuristic precision (Indeterminate)

4324 functions matched from obarray. Manual audit of 50 random
functions needed to measure precision. Instrumentation: manifest
contains arglist signatures for each function.

## Instrumentation Hooks

- **C-001, C-005**: `EMCP_TRACE=1` environment variable in `server.py`
- **C-003**: `EMCP_TRACE=1` in `dispatch.py` logs per-call latency
- **C-004**: `tests/test_dispatch_live.py::TestNonAsciiRoundTrip`
- **C-002**: Random sampling from `functions-compact.jsonl` (manual)
