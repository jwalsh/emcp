---
name: review-prompt
description: Review CLAUDE.md against the critical/substantive/minor checklist from the meta-meta prompt. Use after generating or modifying CLAUDE.md.
user-invocable: true
allowed-tools: Read, Write, Edit, Grep
---

# Review CLAUDE.md

## Sentinel

Before reviewing, check current state:

1. If `CLAUDE.md` does not exist: stop with error "no CLAUDE.md to review.
   Run `/generate-claude-md` first."
2. If `docs/meta-prompt-v0-review.md` already exists:
   - Compare `CLAUDE.md` mtime vs review mtime.
   - If CLAUDE.md is newer: proceed (it was modified after last review).
   - If review is newer or same: report "CLAUDE.md has not changed since
     last review. Pass `--force` to re-review." Stop unless forced.
3. If `docs/meta-prompt-v0.md` does not exist: save current CLAUDE.md
   as v0 before reviewing.

Read CLAUDE.md and check against this list.

## Critical (must fix before proceeding)

- [ ] Agent role stated explicitly ("You are a coding agent")
- [ ] Axiom appears before line 10
- [ ] Build order includes failure handler text
- [ ] Conjectures have instrumentation requirement section

## Substantive (fix now)

- [ ] Confirmation gate present
- [ ] Anti-goals state mechanical failure modes (not just "it's bad")
- [ ] Architectural constraints are named sections (not buried bullets)
- [ ] Success criteria are testable assertions (not prose)
- [ ] No "low relevance" links wasting tokens

## Minor (note but proceed)

- [ ] External URLs that may need vendoring into repo
- [ ] Permission/environment assumptions documented

## Process

1. Read CLAUDE.md
2. Check each item, report findings with pass/fail per item
3. If any Critical items fail -> fix CLAUDE.md and re-check
4. Save review as `docs/meta-prompt-v0-review.md`
5. Save corrected version as `docs/meta-prompt-v1.md`
6. Update CLAUDE.md with corrected version
