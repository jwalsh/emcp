# Naming and Positioning Analysis: emcp [originally emacs-mcp-maximalist]

Author: Marketing review (Emacs/open-source background)
Date: 2026-03-19

---

## 1. Name Analysis: `emacs-mcp-maximalist`

### Discoverability

**Score: 3/5**

Someone searching "Emacs MCP server" would find this repo only if they
also added "maximalist" or happened across it in a broader GitHub search.
The words "emacs" and "mcp" are in the name, which is good -- but the
qualifier "maximalist" pushes it away from the most natural search terms.
A developer looking for an Emacs MCP implementation would more likely
search for "emacs mcp", "emacs mcp server", or "elisp mcp". The name
does not contain "server", "elisp", or "tool" -- three high-intent
search terms for this space.

Contrast: `mcp.el` (the Emacs MCP client) is immediately findable
because it uses the `.el` convention. `gptel` is not descriptive but
has become memorable through usage. This project falls between the two:
partially descriptive, partially obscured by the qualifier.

### Accuracy

**Score: 2/5**

This is the core problem. The name describes what the project *was* --
an intentionally absurd exercise in exposing all 3600+ functions. It
does not describe what the project *is*:

- A **pure Elisp MCP server** (`emcp-stdio.el`, 500 lines, zero
  external dependencies)
- A **daemon data layer** (9 tools for org-mode, buffers, eval)
- A **retrieval system** design (JITIR via eval-as-query-language)
- A **trust/presence architecture** (5-tier eval barrier, mDNS
  discovery)
- A **research methodology** (56 falsifiable conjectures across 4
  series: C, C-D, C-E, C-F)

"Maximalist" signals "too many tools on purpose" -- which was the
reductio. But the project's actual contributions are the pure Elisp
server, the daemon-as-database insight, and the conjecture-driven
methodology. None of these are captured in the name.

The Python stack is gone. The manifest file is gone. The project is
not about enumeration anymore -- it is about the daemon as a queryable
knowledge surface. The name is 6 months behind the artifact.

### Memorability

**Score: 3/5**

"emacs-mcp-maximalist" is 23 characters. It is sayable ("the
maximalist project") but long to type. In conversation, people will
shorten it to "emcp" or "the maximalist thing." The latter is
memorable but for the wrong reason -- it marks the project as the
excessive one, the joke, the one that is deliberately too much. That
was appropriate for a proof-of-concept. It is less appropriate for
conference submissions.

For comparison: magit (5 chars), org-roam (8), gptel (5), mcp.el (6).
Emacs projects trend short. 23 characters is an outlier.

### Tone

**Score: 2/5**

"Maximalist" is a loaded word. It communicates:

- **To Emacs users**: "This is the over-the-top one." Some will find
  this appealing (Emacs users appreciate excess); others will dismiss
  it as a toy. The tone is correct for a reductio ad absurdum but
  wrong for a serious research artifact.
- **To Lisp researchers (EuroLisp)**: "This is not serious work."
  Academic reviewers scan titles for credibility signals. "Maximalist"
  reads as self-aware humor, which is fine for a blog post but risky
  for a paper submission.
- **To AI/MCP developers**: "This probably exposes too many tools and
  breaks things." Which was the point -- but the project now also
  demonstrates that Emacs can be a practical, zero-dependency MCP
  server. The name undersells that.

The tone problem in a sentence: the project has outgrown its irony.

### Convention

Emacs projects follow several naming patterns:

| Pattern | Examples | This project |
|---------|----------|-------------|
| Verb/noun + `.el` | `mcp.el`, `magit`, `gptel` | Does not follow |
| `org-*` for org-mode extensions | `org-roam`, `org-capture` | Partially fits (daemon tools are org-centric) |
| `emacs-*` for external tooling | `emacs-lsp`, `emacs-slack` | Follows this pattern |
| Abbreviation | `eglot`, `gptel`, `ellama` | `emcp` would fit |
| Descriptive compound | `copilot.el`, `emacs-mcp-curated` | Current name follows this |

The `emacs-*-*` triple-compound pattern is relatively uncommon.
`emacs-lsp-bridge` exists but is the exception. The community
gravitates toward short names. The internal prefix is already `emcp-`
(used in `emcp-stdio.el`, `emcp-data-eval`, `emcp-presence`,
`emcp-q/*`). The code has already chosen its name; the repo has not
caught up.

---

## 2. Alternative Names

### 2a. `emcp`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 4/5 | Covers "Emacs MCP" without implying maximalism |
| Tone | 5/5 | Neutral, professional, matches the internal prefix |
| Discoverability | 3/5 | Short and searchable but not self-describing |
| Brevity | 5/5 | 4 characters. Sayable, typable, memorable |

The Elisp files already use this prefix. The shortest path to
coherence. Risk: could be confused with a generic "Emacs MCP client"
(which is `mcp.el`). Mitigation: the tagline and README disambiguate.

### 2b. `emcp-server`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 4/5 | Names the artifact (it is a server) |
| Tone | 4/5 | Functional, clear |
| Discoverability | 5/5 | "emacs mcp server" search would match |
| Brevity | 4/5 | 11 characters, reasonable |

The most discoverable option. Slightly generic -- does not signal
what makes this server different from other MCP servers.

### 2c. `emcp-stdio`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 5/5 | Names the file and the transport |
| Tone | 4/5 | Technical, precise |
| Discoverability | 3/5 | Only findable by people who know MCP uses stdio |
| Brevity | 4/5 | 10 characters |

Matches the actual artifact name (`emcp-stdio.el`). Too
transport-specific for a project that now includes daemon data layer,
presence, and retrieval architecture.

### 2d. `emacs-mcp`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 3/5 | Generic -- does not say server vs client vs library |
| Tone | 4/5 | Clean, standard Emacs naming |
| Discoverability | 5/5 | Exactly what you would search for |
| Brevity | 4/5 | 9 characters |

The most obvious name. Risk: name collision with the concept itself.
Could imply "the" Emacs MCP implementation, which overpromises given
that `mcp.el` exists as the client-side project.

### 2e. `obarray-mcp`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 5/5 | Names the core insight (the obarray IS the manifest) |
| Tone | 4/5 | Technical, insider, intriguing |
| Discoverability | 2/5 | Only Emacs/Lisp developers know what an obarray is |
| Brevity | 4/5 | 10 characters |

The most technically precise name. Captures the foundational axiom.
Would be excellent for a paper title but limits the audience to people
who already know Emacs internals.

### 2f. `elisp-mcp`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 4/5 | Signals pure-Elisp implementation |
| Tone | 5/5 | Clean, technical, the right register |
| Discoverability | 4/5 | "elisp mcp" is a plausible search query |
| Brevity | 4/5 | 9 characters |

Good for the EuroLisp audience. Emphasizes the language angle. Does
not capture the daemon-as-database or presence layers, but neither
does any short name.

### 2g. `emcp-maximalist`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 3/5 | Keeps the reductio framing, drops the redundant "emacs" |
| Tone | 3/5 | Retains the joke but shortens it |
| Discoverability | 3/5 | Still requires knowing "maximalist" is relevant |
| Brevity | 4/5 | 15 characters, better than 23 |

A compromise that preserves history. The "maximalist" qualifier still
has the tone problems described above.

### 2h. `emcp-data`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 3/5 | Captures the daemon data layer angle but not the tool server |
| Tone | 4/5 | Neutral, practical |
| Discoverability | 3/5 | "emacs data mcp" is not a common search |
| Brevity | 4/5 | 9 characters |

Appropriate if the project pivots toward the data layer as the primary
contribution. Currently the server and the data layer are co-equal.

### 2i. `emacs-recall`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 2/5 | Captures the JITIR/retrieval angle only |
| Tone | 4/5 | Evocative, references Remembrance Agent lineage |
| Discoverability | 2/5 | Would attract memory/retrieval researchers, not MCP developers |
| Brevity | 5/5 | 12 characters |

A name for the future, not the present. The retrieval architecture
exists as specs but has not been implemented. Naming the repo after
unbuilt features would be premature.

### 2j. `mcp-absurdum`

| Criterion | Score | Notes |
|-----------|-------|-------|
| Accuracy | 2/5 | Captures only the reductio angle |
| Tone | 2/5 | Clever but risks alienating serious audiences |
| Discoverability | 1/5 | No one would search for this |
| Brevity | 4/5 | 12 characters |

Entertaining. Not appropriate for a project with 56 conjectures and
four spec documents. The joke that outgrew itself should not be
replaced with a different joke.

---

## 3. Positioning Statements

### 3a. For EmacsConf

emcp is a pure Emacs Lisp MCP server -- 500 lines, zero external
dependencies -- that exposes the running Emacs process as a tool
registry for AI agents. At startup it walks the obarray, identifies
text-consuming functions via arglist heuristics, and registers each as
an MCP tool callable over JSON-RPC stdio. When a daemon is running, nine
additional data-layer tools provide live access to buffers, org headings,
TODO states, and arbitrary eval. The server began as a five-layer
Python-mediated stack and collapsed to a single Elisp file after
discovering that Emacs batch mode can serve JSON-RPC directly -- provided
you know about `send-string-to-terminal`. The project is a research
artifact driven by 56 falsifiable conjectures with measurements on
emacsclient latency, Unicode fidelity, arglist precision, and the
autoload barrier. It proves two things: Emacs does not need a shim to
speak agent protocols, and the daemon is already the most capable
personal retrieval layer most of us have -- we just never gave it a
protocol.

### 3b. For EuroLisp

emcp is a protocol server built entirely in Emacs Lisp that uses
`mapatoms` to enumerate a Lisp image's function namespace at runtime and
expose each function as a callable tool over JSON-RPC. The core
mechanism -- walking the symbol table, extracting arglists via
`help-function-arglist`, filtering by parameter name heuristics, and
dispatching via `funcall` -- is a case study in runtime reflection as
protocol surface. The system's serialization boundary is
`prin1-to-string`, which serves simultaneously as the security layer
(argument escaping) and the wire format (sexp-to-JSON bridge). Eleven
falsifiable conjectures drive the empirical evaluation, including a
refuted precision hypothesis (40% vs predicted 80% for the arglist
heuristic) and an independently discovered buffering bug in Emacs batch
stdout that required `send-string-to-terminal` as a workaround. The
project raises a generalizable question for dynamically-typed Lisps: if
`funcall` is a universal dispatch and the symbol table is a queryable
registry, what prevents any Lisp image from self-describing as an RPC
server at the language level?

### 3c. For GitHub/Hacker News

emcp turns a running Emacs into an MCP server that AI agents can call.
It is 500 lines of Elisp with no dependencies. At startup it
introspects the obarray (Emacs's symbol table) and registers every
text-consuming function as an MCP tool -- 779 of them from a vanilla
Emacs. When an Emacs daemon is running, the server also provides tools
for reading buffers, querying org-mode headings, setting TODO states, and
evaluating arbitrary Elisp. There is no manifest file, no Python, no
Node, no subprocess shim. Emacs batch mode speaks JSON-RPC directly over
stdin/stdout. The project started as a deliberate reductio ad absurdum
("what if you exposed all 3600 functions to prove MCP context saturation?")
and evolved into a practical demonstration that Emacs is already a
queryable data layer -- it holds your buffers, your org files, your
clock history, your unsaved edits -- and MCP is just the protocol that
lets an agent ask it questions.

---

## 4. Recommendation

**Rename to `emcp`.** Here is the case:

### Why rename

1. **The code already chose the name.** The Elisp prefix is `emcp-`
   everywhere: `emcp-stdio.el`, `emcp-data-eval`, `emcp-presence`,
   `emcp-q/*`, `emcp-barrier/*`. The internal identifier and the
   external identifier should match.

2. **The project outgrew the irony.** "Maximalist" was the thesis:
   expose everything, watch it break, prove a point about context
   windows. That thesis is still in the repo -- it is conjecture C-001
   and C-005. But the project now has four spec documents, 56
   conjectures, a pure Elisp server, a daemon data layer, a trust tier
   model, and mDNS presence. Calling it "maximalist" buries the
   substance under the punchline.

3. **Conference submissions need clean names.** "emacs-mcp-maximalist"
   in a CFP title or abstract makes reviewers wonder if it is a joke
   project. "emcp" or "emcp: a pure Elisp MCP server" is immediately
   legible.

4. **Discoverability.** The most natural search terms are "emacs mcp
   server" and "elisp mcp." The word "maximalist" adds noise.

### Why `emcp` specifically

- 4 characters, easy to type, say, and remember.
- Matches the internal prefix used across all Elisp files.
- Does not over-specify: it covers the server, the data layer, the
  presence tools, and the research framework.
- Does not conflict with `mcp.el` (the Emacs MCP *client*) --
  the `em-` prefix signals "Emacs" while the `mcp` suffix signals
  the protocol. Together they read as "Emacs MCP [server]".

### The cost of renaming

- **41 commits**: history is preserved via `git log --follow` after
  rename. GitHub redirects old URLs to the new repo name automatically.
- **External links**: the gist (cc7f50fe) references
  `emacs-mcp-maximalist` by name. The gist content does not break; the
  description can be updated. GitHub handles repo renames with automatic
  redirects for an extended period.
- **Presentation materials**: `slides.org` and `review.md` reference
  the project by its current name. These are historical documents --
  they should note the rename, not be rewritten.
- **`.mcp.json` examples**: need updating in README. Minor.
- **Mental model**: anyone who knows the project as "the maximalist
  thing" will need to learn "emcp." This is a one-time cost with long-
  term benefit.

### What to keep

The word "maximalist" should remain in the project's vocabulary -- in
the README, in the CLAUDE.md anti-goals, in the conjecture
descriptions. The reductio framing is still valuable context. It just
should not be the name. A sentence like "emcp began as
emacs-mcp-maximalist, a deliberate reductio ad absurdum" preserves
the origin without letting it define the present.

### Alternative: do not rename

The case for keeping the name: it is distinctive, it has history, and
renaming has friction. If the project's primary audience remains
"people already in the conversation" (i.e., the author and
collaborating agents), the name does not matter much. But the EmacsConf
and EuroLisp submission plans change the audience. Once external
reviewers and attendees are in the picture, the name is load-bearing.

**Verdict: rename to `emcp` before submitting to conferences.**

---

## 5. Tagline Proposals

1. **"Emacs as MCP server. Pure Elisp. Zero dependencies."**
   Clean, factual, hits the three most remarkable properties. Best for
   GitHub description and README header.

2. **"The obarray is the manifest."**
   The most technically precise tagline. Captures the foundational
   axiom in five words. Best for the Emacs/Lisp audience who will
   immediately understand the implication.

3. **"Your Emacs daemon is already a queryable data layer. This gives it a protocol."**
   Captures the daemon-as-database insight. Best for the AI/agent
   audience who care about what MCP unlocks, not how it is built.

4. **"779 functions, one `mapatoms`, zero shims."**
   Punchy, specific, technical. Good for social media or a talk
   subtitle. The number anchors it in reality.

5. **"Every function in Emacs, as an MCP tool."**
   The current tagline. Still accurate, still effective for the reductio
   framing. If the project keeps its maximalist identity even after
   rename, this remains the best single-sentence summary of the thesis.
   Consider pairing it: "Every function in Emacs, as an MCP tool --
   and it only took 500 lines of Elisp."
