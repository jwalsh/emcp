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
1. emcp-stdio.el -- `emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start`
   responds to `tools/list` with >= 700 tools
2. ert tests -- `emacs --batch -Q -l tests/test-emcp-stdio.el -f ert-run-tests-batch`
   passes all cases
3. health-check.sh -- exits 0 on configured machine

## Step 2: Create Conjecture Issues

For each conjecture (C-001 through C-006, C-008), create a tracking issue:

```bash
gh issue create --title "C-NNN: <claim summary>" \
  --body "<falsification criterion and measurement plan>" \
  --label "conjecture"
```

## Step 3: Wire Dependencies

Add dependency notes in issue bodies -- each step references its predecessor:
"Blocked by #N (Step N-1: component)"

## Step 4: Verify

Run `gh issue list` -- should show all build steps and conjectures.

## Anti-Goals

- This skill must not create duplicate issues — every candidate title MUST be checked against `$EXISTING_ISSUES` before `gh issue create` is invoked.
- This skill must never create a conjecture issue without a falsification criterion in the body; "C-NNN: make it work" is forbidden.
- This skill must not create build-step issues whose body lacks an acceptance test extracted from `spec.org` — the `--body` MUST contain a mechanical check.
- This skill must never create issues before verifying `gh auth status` succeeds and the repo has a GitHub remote; partial-wire states leave orphaned local references.
- This skill must not wire dependencies by editing issue bodies out of order — predecessor issues MUST exist before "Blocked by #N" references are added.
- This skill must never label a step issue with `conjecture` or a conjecture issue with `feature`; label taxonomy is load-bearing for downstream filters.
