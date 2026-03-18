# Conjectures

Status tracking for the five open conjectures. Each requires a
measurement note: confirmed, refuted, or indeterminate with data.

Detailed research in `docs/conjectures/c-NNN-research.md`.

| ID | Claim | Status | Evidence |
|----|-------|--------|----------|
| C-001 | Claude Code uses on-demand tool indexing | Confirmed | Prior session (2026-02-04); re-verified 2026-03-17: 4324-tool server loads without crashing Claude Code. .mcp.json configured for both modes |
| C-002 | Arglist heuristic yields > 80% precision | Indeterminate | 4324/~30000 obarray symbols pass heuristic. Manual audit of 50 random functions pending |
| C-003 | emacsclient round-trip < 50ms for string fns | Confirmed | 2026-03-18: median=2.3ms, P95=~3ms, worst=24ms (GC jitter). 200 samples, 0% above 50ms. Prior 10.9ms was inflated by Python startup overhead |
| C-004 | Non-ASCII survives full round trip | Confirmed | 2026-03-18: 14 character classes tested (CJK, emoji, ZWJ families, Arabic, Thai, Korean, combining, supplementary plane, flags). All byte-identical round trips via hex comparison |
| C-005 | Maximalist manifest causes measurable init latency vs core | Confirmed | 2026-03-18: core=0.1ms (60 tools), 780 tools=1.7ms, 3.6k extrapolated=~10ms. Token cost is the real impact: core ~5.7k tokens vs maximalist ~341k tokens |

## Measurement Details

### C-001: On-demand tool indexing (Confirmed)

Claude Code connects to the 4324-tool maximalist server without
context window exhaustion. Tools are indexed lazily. Prior session
(2026-02-04) first observed this; re-verified 2026-03-17 with `.mcp.json`.

### C-003: emacsclient latency (Confirmed)

**2026-03-18 update** (supersedes prior measurement):
- Median: 2.3ms, P95: ~3ms, worst outlier: 24ms (GC/TCP jitter)
- dispatch.py wrapper adds ~0.2ms overhead (negligible)
- 200 samples across 10 expressions, 0% above 50ms threshold
- Prior data showing "10.9ms" was inflated by Python interpreter startup
  overhead in measurement script
- Daemon connected via TCP (0.0.0.0); Unix socket would be faster

Prior measurement (2026-03-17): `(+ 1 1)` = 10.9ms, `(string-trim " hello ")` < 15ms.

### C-004: Non-ASCII round trip (Confirmed)

**2026-03-18 update** (expanded from 6 to 14 character classes):
- 14 character classes tested: CJK, emoji, ZWJ families
  (e.g. family emoji), Arabic, Thai, Korean, combining characters,
  supplementary plane (musical symbols), flag emoji
- All byte-identical round trips confirmed via hex comparison
- Transformation tests pass: upcase/downcase preserve diacritics,
  string-trim works on CJK, reverse works on Japanese
- `escape_for_elisp()` only escapes 4 ASCII chars (`\`, `"`, `\n`, `\r`)
  plus rejects null bytes; all non-ASCII passes through as raw UTF-8

Prior measurement (2026-03-17): 6/6 live tests pass (CJK, emoji, combining).

### C-005: Init latency differential (Confirmed)

**2026-03-18 update** (refined measurements):
- Init latency: 0.1ms (core/60 tools) vs 1.7ms (780 tools) vs ~10ms
  (3.6k tools, extrapolated)
- Ratio: 16.8x (780 vs 60), ~92x (3600 vs 60)
- Token cost is the real impact: core ~5.7k tokens, maximalist 3.6k
  tools ~341k tokens (~1.3MB JSON)
- Wall-clock init difference is not user-perceptible; token budget
  impact validates the reductio ad absurdum thesis

Prior measurement (2026-03-17): core=0.7ms (69 tools), maximalist=15.9ms (4324 tools), ~23x ratio.

### C-002: Arglist heuristic precision (Indeterminate)

4324 functions matched from obarray. Manual audit of 50 random
functions needed to measure precision. Instrumentation: manifest
contains arglist signatures for each function.

## Instrumentation Hooks

- **C-001, C-005**: `EMCP_TRACE=1` environment variable in `server.py`
- **C-003**: `EMCP_TRACE=1` in `dispatch.py` logs per-call latency
- **C-004**: `tests/test_dispatch_live.py::TestNonAsciiRoundTrip`
- **C-002**: Random sampling from `functions-compact.jsonl` (manual)
