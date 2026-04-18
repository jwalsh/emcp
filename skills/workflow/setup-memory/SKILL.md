---
name: setup-memory
description: Create structured memory files for project persistence so fresh Claude sessions can resume context. Use after bootstrap is complete.
user-invocable: true
allowed-tools: Read, Write, Bash
---

# Setup Memory Files

## Sentinel

Check which memory files already exist:

```bash
MEMORY_DIR="$HOME/.claude/projects/-Users-jasonwalsh-ghq-github-com-jwalsh-emacs-mcp-maximalist/memory"
for f in project_state.md user_role.md feedback_style.md; do
  test -f "$MEMORY_DIR/$f" && echo "EXISTS: $f" || echo "MISSING: $f"
done
test -f "$MEMORY_DIR/../MEMORY.md" && echo "EXISTS: MEMORY.md" || echo "MISSING: MEMORY.md"
```

- If all four files exist: report "memory already configured" with a
  summary of each file's content. Stop unless `$ARGUMENTS` contains
  `--force`.
- If some exist: only create the missing ones. Do not overwrite existing
  files (they may contain user corrections from prior sessions).
- If MEMORY.md exists but is missing pointers to files that exist:
  update the index only.

Create structured memory files so a fresh Claude session can resume work
on this project without cold-start amnesia.

## Memory Files to Create

Write to the project memory directory (it already exists):

### 1. project_state.md

```markdown
---
name: emacs-mcp-maximalist state
description: Current project state — what exists, what's been done, what's next
type: project
---

emacs-mcp-maximalist exposes Emacs obarray as MCP tools via runtime introspection.

**Why:** Demonstrate that naive "enumerate all tools" MCP design saturates
agent context windows — the system must work to make the critique work.

**How to apply:** All build decisions favor completeness over curation.
The maximalist mode is the point, not a stretch goal.
```

### 2. user_role.md

Ask the user about their role and expertise, then write accordingly.
If not available, note that it needs to be filled in.

### 3. feedback_style.md

Record any communication preferences or corrections from the current
session. Start with project defaults from CLAUDE.md global instructions.

### 4. MEMORY.md

Create/update the MEMORY.md index with pointers to each memory file.

## Important

- Use selective writes, not append-all (prevents memory self-degradation)
- Keep MEMORY.md under 200 lines
- Include absolute dates, not relative ("2026-03-17" not "today")

## Anti-Goals

- This skill must not overwrite existing `project_state.md`, `user_role.md`, or `feedback_style.md` files — they may contain user corrections from prior sessions that would be lost.
- This skill must never write relative dates ("today", "yesterday", "last week") into any memory file; absolute ISO dates only.
- This skill must not let `MEMORY.md` grow past 200 lines; append-all behavior that causes memory self-degradation is forbidden.
- This skill must never index memory files that do not exist on disk — the MEMORY.md pointers MUST all resolve.
- This skill must not write secrets, API tokens, or host-specific credentials into memory files; memory persists across sessions and is read by future agents.
- This skill must never invent a `user_role.md` answer when the user has not provided one — mark it as "needs fill-in" instead.
