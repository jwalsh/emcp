---
name: bootstrap
description: Initialize a new project repo with git, GitHub remote, and verify spec.org exists. Use when starting a fresh project from a spec.org file.
user-invocable: true
allowed-tools: Bash, Read, Write, Edit
argument-hint: [org/repo-name]
---

# Bootstrap a New Project

You are initializing a new project repository.

## Sentinel

Before doing anything, check what already exists:

```bash
SENTINEL_GIT=$(git rev-parse --is-inside-work-tree 2>/dev/null && echo true || echo false)
SENTINEL_REMOTE=$(git remote get-url origin 2>/dev/null && echo true || echo false)
SENTINEL_SPEC=$(test -f spec.org && echo true || echo false)
```

- If all three are `true`: report "bootstrap already complete" and stop.
  Suggest `/generate-claude-md` if CLAUDE.md doesn't exist, or
  `/review-prompt` if it does.
- If `SENTINEL_GIT=true` and `SENTINEL_REMOTE=true` but `SENTINEL_SPEC=false`:
  tell user to write spec.org and stop.
- Otherwise: proceed with the steps below, skipping any that are already done.

## Steps

1. Verify toolchain is available:
   ```
   git --version
   gh --version
   ```

2. If `$ARGUMENTS` is provided (org/repo format), create GitHub repo:
   ```
   gh repo create $ARGUMENTS --private --source=. --push
   ```

3. Verify `spec.org` exists in the current directory.
   If it doesn't, tell the user to write one first and stop.

4. Set repo description from spec.org's `#+title` and `#+subtitle` lines.

5. Add topics extracted from spec.org's domain:
   ```
   gh repo edit --add-topic emacs --add-topic mcp --add-topic elisp
   ```

6. Report what was initialized and suggest running `/generate-claude-md`.
