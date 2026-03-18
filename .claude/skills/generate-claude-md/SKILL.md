---
name: generate-claude-md
description: Read spec.org and generate CLAUDE.md following the fixed-point kernel constraints (axiom before line 10, confirmation gate, failure handler, instrumentation). Use after spec.org exists.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Generate CLAUDE.md from spec.org

## Sentinel

Before generating, check current state:

1. If `spec.org` does not exist: stop with error "no spec.org found."
2. If `CLAUDE.md` already exists:
   - Run the four kernel checks (axiom before line 10, confirmation gate,
     failure handler, instrumentation section).
   - If all four pass: report "CLAUDE.md already exists and passes kernel
     checks. Run `/review-prompt` for full review or pass `--force` to
     regenerate." Stop unless `$ARGUMENTS` contains `--force`.
   - If any fail: warn which kernel constraints are violated and offer
     to regenerate. Proceed only with user confirmation.
3. If `docs/meta-prompt-v0.md` exists but `CLAUDE.md` does not: something
   went wrong mid-generation. Restore from v0 and run `/review-prompt`.

Read `spec.org` completely. Extract and produce CLAUDE.md.

## Fixed-Point Kernel (mandatory in every CLAUDE.md)

These four elements MUST appear. They survive all levels of abstraction:

1. **Axiom placement**: The foundational axiom MUST appear before line 10.
   - Inversion test: What do failing tools optimize for? Negate it.
   - Degradation test: What breaks if AI improves 10x? Axiom must survive.
   - Compression test: If context shrinks to 500 tokens, this sentence remains.

2. **Confirmation gate**: "Before writing any code, output a one-paragraph
   summary of what you understand [PROJECT] to be, who its primary user
   is, and what its primary output is."

3. **Failure handler**: "If an acceptance test fails, stop. Document what
   failed, what you tried, and what the blocker is. Do not proceed to
   the next step. Surface the failure as a CPRR refutation candidate."

4. **Instrumentation requirement**: "Each conjecture requires a corresponding
   measurement hook in the implementation."

## Extraction Targets

From spec.org, extract:
- Project name and subtitle
- Foundational axiom (apply the three tests above)
- Anti-goals with named products and mechanical failure modes
- Build order with acceptance tests per step
- Open conjectures with falsification criteria
- Architectural constraints (promote to named sections if they affect >2 components)
- Success criteria as testable assertions
- Primary user and primary output artifact
- Stack preferences
- Research context (drop anything low-relevance)

## CLAUDE.md Structure

```
## Your Role                     <- always "coding agent"
## Foundational Axiom            <- BEFORE LINE 10
## Confirmation Gate             <- always same text
## What You Are Building         <- 2-3 bullets from spec
## Explicit Anti-Goals           <- named products + mechanical failures
## Key Design Decisions          <- from spec
## [Named Constraint Section]    <- promoted architectural constraint
## Build Order                   <- with failure handler
## [Core Domain Model]           <- table/enum from spec
## Open Conjectures              <- C-001 through C-NNN
## Instrumentation Requirement   <- always same text
## Research Context              <- links, no low-relevance
## Stack Preferences             <- from spec
## Acceptance: End-to-End Test   <- synthetic + testable assertions
```

After generating, save as `docs/meta-prompt-v0.md` and run `/review-prompt`.
