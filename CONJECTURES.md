# Conjectures

Status tracking for the open conjectures. Each requires a
measurement note: confirmed, refuted, or indeterminate with data.

Detailed research in `docs/conjectures/c-NNN-research.md`.

| ID | Claim | Status | Evidence |
|----|-------|--------|----------|
| C-001 | Claude Code uses on-demand tool indexing | Confirmed | Prior session (2026-02-04); re-verified 2026-03-17: 4324-tool server loads without crashing Claude Code. .mcp.json configured for both modes |
| C-002 | Arglist heuristic yields > 80% precision | Refuted | 2026-03-18: 50-function audit yields 40% precision (20 TP, 30 FP). `object`/`buffer` arg patterns dominate false positives. See `docs/c002-audit.md` |
| C-003 | emacsclient round-trip < 50ms for string fns | Confirmed | 2026-03-18: median=2.3ms, P95=~3ms, worst=24ms (GC jitter). 200 samples, 0% above 50ms. Prior 10.9ms was inflated by Python startup overhead |
| C-004 | Non-ASCII survives full round trip | Confirmed | 2026-03-18: 14 character classes tested (CJK, emoji, ZWJ families, Arabic, Thai, Korean, combining, supplementary plane, flags). All byte-identical round trips via hex comparison |
| C-005 | Maximalist manifest causes measurable init latency vs core | Confirmed | 2026-03-18: core=0.1ms (60 tools), 780 tools=1.7ms, 3.6k extrapolated=~10ms. Token cost is the real impact: core ~5.7k tokens vs maximalist ~341k tokens |
| C-006 | Vanilla Emacs exposes substantially fewer functions than configured | Confirmed | 2026-03-18: vanilla (-Q) = 8460, configured (init.el) = 10040. Delta = 1580 (18.7%). Same C primitives (1336); difference is Elisp-defined functions |

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

### C-002: Arglist heuristic precision (Refuted)

**2026-03-18 measurement**: 50-function random sample (seed=42) from
`functions-compact.jsonl`, manually classified.

| Metric | Value |
|--------|-------|
| True Positives | 20 |
| False Positives | 30 |
| Precision | 40% |
| Conjectured threshold | 80% |

The heuristic matches argument names against
`string|str|text|buffer|object|obj|seq|sequence`. The dominant false
positive sources:

- **`object`/`obj` args** (12 FPs): catches every type predicate
  (`bignump`, `compiled-function-p`, etc.) and EIEIO OOP methods
- **`buffer`/`buffers` args** (10 FPs): catches `display-buffer-*`
  window management, process functions, variable-scope predicates
- **`string` in compound arg names** (5 FPs): catches completion
  internals (`format-string`, etc.) and server IPC

Notable false negatives (useful text functions missed):
- Zero-arg functions: `buffer-string`, `point-min`, `point-max`
- Non-matching arg names: `char-to-string` (arg: `char`),
  `number-to-string` (arg: `number`), `file-name-extension` (arg:
  `filename`), `insert` (arg: `args`)

The `sequence`/`seq` pattern performs best (~80% TP rate in the sample).

Full audit: `docs/c002-audit.md`.

### C-006: Vanilla vs configured function count (Confirmed)

**2026-03-18 measurement** on GNU Emacs 30.2 (aarch64-apple-darwin24.6.0):

| Metric | Vanilla (`-Q`) | Configured (init.el) | Delta |
|--------|---------------|----------------------|-------|
| Total `fboundp` symbols | 8460 | 10040 | +1580 (+18.7%) |
| C primitives (`subrp`) | 1336 | 1336 | 0 |
| Elisp-defined (non-subr) | 7383 | 8704 | +1321 |
| Autoloaded | 2846 | 2518 | -328 |
| Interactive commands | 3011 | 3087 | +76 |
| Total obarray symbols | 17398 | 22449 | +5051 (+29%) |
| Loaded features | 107 | 152 | +45 |
| Loaded files | 127 | 172 | +45 |

Key findings:
- C primitives are identical: init.el does not change the compiled core
- The configured daemon adds ~1580 functions (18.7% increase), all Elisp
- Autoloads *decrease* in the configured daemon because some get resolved
  (loaded) during init, converting from autoload stubs to real definitions
- The delta of +1321 Elisp-defined functions comes from the 45 additional
  files/features loaded by init.el
- Interactive commands barely change (+76), suggesting init.el mainly
  adds library functions, not user commands
- Total obarray grows 29% (5051 additional symbols: variables, faces, etc.)
- A third measurement (--no-init-file, with site-lisp) showed identical
  counts to -Q, confirming that site-lisp adds nothing on this system

Implications for the project:
- The anti-goal "config-dependent wrapper" is validated: the function
  count difference (18.7%) is meaningful but not transformative
- A vanilla daemon exposes 8460 functions, of which the arglist heuristic
  would filter to the manifest subset. The core tool set is stable
  regardless of user configuration
- The 780-line manifest (current) represents ~9.2% of vanilla functions
  and ~7.8% of configured functions

## Instrumentation Hooks

- **C-001, C-005**: `EMCP_TRACE=1` environment variable in `server.py`
- **C-003**: `EMCP_TRACE=1` in `dispatch.py` logs per-call latency
- **C-004**: `tests/test_dispatch_live.py::TestNonAsciiRoundTrip`
- **C-002**: Random sampling from `functions-compact.jsonl` (manual)
- **C-006**: `emacsclient --eval` with `mapatoms`/`fboundp` counting against
  daemons started with `-Q` vs normal init
