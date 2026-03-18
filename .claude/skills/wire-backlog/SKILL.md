---
name: wire-backlog
description: Create GitHub issues with dependency chain for the build order extracted from spec.org and CLAUDE.md. Use after CLAUDE.md is finalized.
user-invocable: true
allowed-tools: Read, Bash, Grep
---

# Wire Backlog from Spec

## Sentinel

Before creating issues, check what already exists:

```bash
EXISTING_ISSUES=$(gh issue list --limit 100 --json title --jq '.[].title' 2>/dev/null)
```

- If `gh` is not authenticated or no remote exists: stop with error
  "no GitHub remote configured. Run `/bootstrap` first."
- If `CLAUDE.md` does not exist: stop with error "run `/generate-claude-md` first."
- For each build step and conjecture below, check if an issue with a
  matching title prefix already exists in `$EXISTING_ISSUES`.
- Skip any issue that already exists. Report which were skipped.
- If all issues already exist: report "backlog already wired" and
  show `gh issue list`. Stop.

Read spec.org and CLAUDE.md to extract build steps and conjectures.

## Step 1: Create Build Order Issues

For each build step, create a GitHub issue:

```bash
gh issue create --title "Step N: <component>" \
  --body "<acceptance test from spec>" \
  --label "feature"
```

Build steps for this project:
1. escape.py — pytest tests/test_escape.py passes
2. introspect.el — emcp-write-manifest returns integer > 0
3. dispatch.py — eval_in_emacs('(+ 1 1)') returns "2"
4. server.py (core) — tools/list returns >= 20 tools
5. server.py (maximalist) — tools/list returns > 1000 tools
6. health-check.sh — exits 0 on configured machine

## Step 2: Create Conjecture Issues

For each conjecture (C-001 through C-005), create a tracking issue:

```bash
gh issue create --title "C-NNN: <claim summary>" \
  --body "<falsification criterion and measurement plan>" \
  --label "conjecture"
```

## Step 3: Wire Dependencies

Add dependency notes in issue bodies — each step references its predecessor:
"Blocked by #N (Step N-1: component)"

## Step 4: Verify

Run `gh issue list` — should show all build steps and conjectures.
