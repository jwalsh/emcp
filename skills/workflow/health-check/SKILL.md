---
name: health-check
description: Generate or run bin/health-check.sh that validates project prerequisites (emacs daemon, emcp-stdio.el) with JSON output and exit codes. Use to verify environment.
user-invocable: true
allowed-tools: Read, Write, Bash, Edit
---

# Health Check

This skill is inherently idempotent -- it checks current state and reports.
Running it multiple times is expected and safe.

## If bin/health-check.sh does not exist

Generate it from the current project architecture. The script must:

- Check hard requirements (exit 2 if any fail):
  - `emacsclient --eval '(emacs-pid)'` succeeds (daemon running)
  - `emacs --batch -Q -l src/emcp-stdio.el` loads without error

- Check soft requirements (exit 1 if any fail):
  - `.mcp.json` exists (MCP client config present)
  - `CLAUDE.md` exists
  - `src/emcp-stdio.el` exists

- Output structured JSON with boolean values for each check
- Exit codes: 0 (ok), 1 (degraded), 2 (broken)

## If bin/health-check.sh exists

Run it and report results:

```bash
chmod +x bin/health-check.sh
bin/health-check.sh
echo "Exit code: $?"
```

Interpret the JSON output and summarize what's working and what needs
attention.

## Anti-Goals

- This skill must not modify system state (starting daemons, installing packages, chmod-ing unrelated files) — health-check is read-only by contract.
- This skill must never exit 0 when a hard requirement check failed; exit codes MUST be 0 (ok), 1 (degraded), 2 (broken) and an emacsclient-daemon failure MUST produce 2.
- This skill must not emit non-JSON text on stdout; structured JSON output is the contract and monitors will break on stray log lines.
- This skill must never swallow subprocess errors silently — every check MUST record the command, exit status, and stderr in the JSON payload.
- This skill must not conflate soft and hard requirements; `.mcp.json` missing is degraded (exit 1), not broken (exit 2), and vice versa.
