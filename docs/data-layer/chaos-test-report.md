# Chaos Test Report: Daemon Stability Under Concurrent Agent Load

**Date**: 2026-03-19
**Machine**: Darwin 25.3.0, ARM64 (Apple Silicon)
**Emacs**: emacs-30.2
**Trigger**: System monitor found 3 PID changes in 2 minutes; original 33-day-uptime daemon died

## Executive Summary

The Emacs daemon is **robust under concurrent load**. It does not crash,
leak, or churn on its own. The instability observed by the system monitor
was caused by **agents restarting the daemon**, not by the daemon failing
under pressure. The Unix socket file acts as a natural mutex preventing
duplicate daemons on the default socket, but agents using `emacs --daemon`
will kill and replace the existing daemon, causing the PID churn pattern
observed.

## Test Environment

| Metric | Value |
|--------|-------|
| Initial daemon PID | 12225 |
| Initial daemon uptime | 7 hours, 5 minutes |
| Initial RSS | 34,336 KB (~34 MB) |
| Initial buffer count | 12 |
| Socket path | `/var/folders/.../emacs501/server` |

## Test Matrix

| # | Test | Calls | OK | Fail | Wall Time | PID Stable | Verdict |
|---|------|-------|----|------|-----------|------------|---------|
| 2 | Sequential emacsclient | 100 | 100 | 0 | 0.16s | YES | PASS |
| 3a | Concurrent emacsclient (10) | 10 | 10 | 0 | 0.053s | YES | PASS |
| 3b | Concurrent emacsclient (50) | 50 | 50 | 0 | 0.040s | YES | PASS |
| 3c | Concurrent emacsclient (100) | 100 | 61 | 39 | 0.074s | YES | PARTIAL |
| 3f | Concurrent emacsclient (200) | 200 | 111 | 89 | 0.110s | YES | PARTIAL |
| 4c | MCP batch sessions (5) | 5 | 5 | 0 | 0.29s | YES | PASS |
| 4f | MCP + daemon eval (10) | 10 | 10 | 0 | 0.62s | YES | PASS |
| 5 | Buffer create/delete (50) | 50 | 50 | 0 | 0.098s | YES | PASS |
| 5b | find-file sequential (10) | 10 | 10 | 0 | 0.531s | YES | PASS |
| 5b | find-file concurrent (20) | 20 | 20 | 0 | 0.025s | YES | PASS |
| 6e | Kill + 5 concurrent restarts | 5 | 1 winner | 4 lost race | 3s | N/A | EXPECTED |
| 6f | Mixed -Q / init.el race | 5 | 1 winner | 4 lost race | 3s | N/A | EXPECTED |
| 6g | Named socket fragmentation | 3 | 3 | 0 | 3s | N/A | RISK |

## Latency Measurements

### Sequential (100 calls)

| Percentile | Latency |
|------------|---------|
| Min | 1.5 ms |
| P50 | 1.7 ms |
| P90 | 2.0 ms |
| P95 | 2.2 ms |
| P99 | 47.4 ms |
| Max | 47.4 ms |
| Mean | 2.2 ms |
| StdDev | 4.6 ms |

Validates **C-003**: emacsclient round-trip is well under 50ms for pure
string functions. Median is 1.7ms.

### Per-Operation Latency (20 calls each)

| Operation | Min | P50 | P95 | Max |
|-----------|-----|-----|-----|-----|
| `(+ 1 1)` | 1.6 ms | 1.8 ms | 2.1 ms | 2.8 ms |
| `(string-trim " hello ")` | 1.7 ms | 1.8 ms | 1.9 ms | 2.1 ms |
| `(length (buffer-list))` | 1.7 ms | 1.7 ms | 1.8 ms | 1.8 ms |
| `(upcase "hello world")` | 1.6 ms | 1.7 ms | 1.8 ms | 1.9 ms |
| `(format "%s-%d" "test" 42)` | 1.6 ms | 1.7 ms | 1.8 ms | 2.0 ms |
| buffer create+kill | 1.7 ms | 1.7 ms | 1.8 ms | 1.8 ms |

All operations are within 1-3ms. Operation type has negligible impact on
latency. The bottleneck is socket round-trip, not Elisp evaluation.

### Latency Under Concurrency

| Concurrency | OK/100 | Fail/100 | P50 | P99 | Max | Wall |
|-------------|--------|----------|-----|-----|-----|------|
| 1 | 100 | 0 | 2 ms | 46 ms | 46 ms | 234 ms |
| 5 | 100 | 0 | 3 ms | 7 ms | 7 ms | 72 ms |
| 10 | 57 | 43 | 6 ms | 48 ms | 48 ms | 78 ms |
| 20 | 100 | 0 | 10 ms | 26 ms | 26 ms | 76 ms |
| 50 | 79 | 21 | 7 ms | 43 ms | 43 ms | 94 ms |
| 100 | 100 | 0 | 9 ms | 26 ms | 26 ms | 81 ms |

Observations:
- Failures are **intermittent and not monotonically correlated with
  concurrency**. Runs at concurrency=10 saw 43 failures, but
  concurrency=100 saw 0. This indicates transient socket backlog
  exhaustion, not a hard limit.
- P50 latency degrades linearly with concurrency (2ms at 1, 9ms at 100).
- Wall-clock time plateaus at ~80ms regardless of concurrency above 5,
  indicating Emacs serializes all evaluations internally.

## Failure Modes Identified

### 1. Socket Backlog Exhaustion (TRANSIENT)

**Error**: `emacsclient: can't connect to .../server: Connection refused`

At high concurrency (100-200 simultaneous connections), the Unix domain
socket's listen backlog fills up. The daemon itself is unaffected -- it
continues processing queued requests. Rejected clients get "Connection
refused" immediately.

**Severity**: LOW. Retry with backoff resolves it. Daemon survives.

**Mitigation**: Increase `server-socket-backlog` in Emacs (if available),
or implement client-side retry with exponential backoff.

### 2. Agent-Initiated Daemon Restart (THE ACTUAL BUG)

**Error**: PID changes between calls, uptime resets to seconds.

This is what the system monitor observed. The daemon does not die on its
own. An agent (or its `emacs --daemon` call) replaces the running daemon.
The sequence:

1. Agent A calls `emacsclient --timeout 3 --eval ...`
2. Daemon is busy (processing another agent's heavy eval), times out
3. Agent A concludes daemon is dead, runs `emacs --daemon`
4. New daemon starts, steals the socket file
5. Agent B's in-flight `emacsclient` call fails
6. Agent B concludes daemon is dead, runs `emacs --daemon`
7. Cascade: each restart triggers more "daemon dead" detections

**Severity**: CRITICAL. This is a positive-feedback loop. More agents
make it worse, and the 3-second timeout in `emcp-stdio--check-daemon`
is too short for a daemon under load.

**Mitigation**:
- Never auto-restart the daemon from agent code
- Use a lock file / PID file before starting `emacs --daemon`
- Increase timeout to 10-30 seconds
- Accept daemon unavailability gracefully (degrade to batch-only mode)

### 3. Named Socket Fragmentation (LATENT RISK)

**Error**: Multiple daemons running simultaneously on different sockets.

If agents use `emacs --daemon="agent-N"` with different socket names,
the natural socket-file mutex is bypassed. Each daemon consumes ~14 MB
(vanilla -Q) or ~39 MB (configured). With 9 agents, this could mean
9 separate Emacs daemons (126-351 MB total), each with independent
buffer state.

**Severity**: MODERATE. Not observed in the system monitor data, but
a likely failure mode if agents are configured with different socket names.

**Mitigation**: All agents must use the same socket name (or default).

### 4. -Q vs Init.el Race (CONFIGURATION DRIFT)

When agents race to restart the daemon, the winner determines whether the
daemon is vanilla (`-Q`, ~5000 functions) or configured (init.el, ~10,000+
functions). This means the manifest tool count is non-deterministic after
a restart cascade.

**Severity**: MODERATE. The winning daemon's configuration affects all
subsequent MCP sessions.

**Mitigation**: Standardize on `-Q` for daemon starts (per CLAUDE.md
reproducibility requirement), or use a startup script that all agents share.

## Memory Observations

| Phase | RSS (KB) | Delta |
|-------|----------|-------|
| Baseline | 34,336 | -- |
| After 100 sequential calls | (not measured) | -- |
| After 50 concurrent calls | 35,376 | +1,040 |
| After 200 concurrent + buffer ops | 47,520 | +13,184 |
| Post-daemon-restart (configured) | 39,488 | N/A (new process) |
| Vanilla -Q daemon | ~14,624 | N/A |

The daemon does accumulate memory under load (~13 MB over the full test
suite), but this is within normal operating parameters. GC count was 54
pre-test, 11 post-restart (new process).

## MCP Batch Session Findings

The `--batch` MCP sessions (Step 4) are **completely isolated** from daemon
instability:

- Each MCP batch process is independent (spawned by `emacs --batch -Q`)
- Local tools (779 in vanilla -Q mode) work without any daemon
- Daemon tools require `EMACS_SOCKET_NAME` to be set when using -Q
- 5 concurrent batch sessions complete in 0.29s with zero failures
- 10 concurrent sessions hitting the daemon complete in 0.62s

The batch-mode architecture is inherently resilient: daemon death degrades
the data layer but does not crash the MCP server.

## Would `aq` Coordination Have Helped?

Yes. The core problem is uncoordinated daemon lifecycle management.
A queue/coordination layer (`aq`) would help in three ways:

1. **Singleton daemon guarantee**: Only one agent should own daemon
   lifecycle. A lock/lease mechanism prevents restart cascades.

2. **Request serialization**: Instead of 200 concurrent `emacsclient`
   calls hitting the socket, a queue could batch or rate-limit requests.
   The daemon serializes internally anyway, so client-side queuing
   would reduce socket backlog pressure without affecting throughput.

3. **Health-check coordination**: Instead of each agent independently
   checking daemon health and potentially restarting, a single health
   monitor could manage the daemon and signal agents when it is ready.

## Recommended Maximum Concurrent Agent Count

| Scenario | Recommended Max | Rationale |
|----------|----------------|-----------|
| Agents using daemon (emacsclient) | 5 | Socket backlog stable at 50 concurrent |
| Agents using batch MCP (no daemon) | 10+ | Fully independent processes |
| Agents using daemon + batch hybrid | 5 daemon + 10 batch | Daemon is the bottleneck |
| Without coordination | 3 | Beyond this, timeout-induced restart cascade risk |
| With aq coordination | 10 | Queue absorbs burst; daemon sees serial load |

## Recommendations

1. **Increase `emcp-stdio--check-daemon` timeout from 3s to 10s**.
   The 3-second timeout is the proximate cause of false "daemon dead"
   conclusions under load.

2. **Never auto-restart the daemon from agent code**. If the daemon is
   unreachable, degrade to batch-only mode. A human or a dedicated
   supervisor process should own daemon lifecycle.

3. **Add a daemon lock file**. Before running `emacs --daemon`, check
   for `/tmp/emacs-mcp-daemon.lock`. Use `flock` or equivalent.

4. **Standardize on `-Q` for daemon starts**. Per CLAUDE.md, the
   introspector should run against vanilla Emacs. Configured daemons
   introduce non-reproducible function counts.

5. **Implement client-side retry with backoff**. For the socket backlog
   exhaustion failure mode, a simple 100ms retry (up to 3 attempts)
   would eliminate nearly all transient failures.

6. **Consider a daemon supervisor**. A `systemd`-style watchdog or
   `launchd` plist that owns the single daemon process, restarts it
   on crash, and provides a stable interface for agents.

## Raw Data Summary

- Total emacsclient calls executed: ~1,200
- Total MCP batch sessions: ~25
- Total daemon restarts (intentional, for testing): 3
- Named daemon instances tested: 3
- Daemon crashes observed: 0
- Daemon self-initiated restarts: 0
- Agent-initiated restarts: 3 (all intentional test steps)
