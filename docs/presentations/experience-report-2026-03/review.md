# Slide Deck Review: "Emacs All The Way Down"

Reviewer: Claude Opus 4.6 (automated review)
Date: 2026-03-19
Artifact: `docs/presentations/experience-report-2026-03/slides.org`

---

## Conference Suitability Scores

### EmacsConf: 5/5

**Justification**: This is a near-perfect EmacsConf talk. It is deeply
technical, rooted entirely in Emacs internals (obarray, mapatoms,
funcall, batch mode I/O), and demonstrates something genuinely new: a
pure Elisp MCP server that exposes Emacs as an agent-facing tool
registry with zero external dependencies. The discovery around
`send-string-to-terminal` vs `princ` buffering (C-011) alone is worth
the talk -- it documents a real batch-mode pitfall that affects anyone
building Emacs-based servers. The progression from a five-layer Python
shim to ~280 lines of Elisp is a compelling narrative arc. EmacsConf
audiences value exactly this kind of "I went deep and here is what I
found" experience report.

### EuroLisp: 3/5

**Justification**: The Lisp angle is present but secondary. The talk
uses `mapatoms`, `funcall`, `obarray` reflection, and `prin1-to-string`
as serialization -- all Lisp-specific mechanisms. The CPRR methodology
and the empirical measurement of heuristic precision (C-002) would
interest a research-oriented audience. However, the talk is firmly
embedded in Emacs-specific concerns (daemon mode, batch stdout buffering,
emacsclient IPC) that would not transfer to Common Lisp, Scheme, or
Clojure contexts. For EuroLisp, the talk would need to foreground the
language-level observations: runtime reflection via symbol tables,
`funcall` as a universal dispatch mechanism, the tension between
autoloaded vs. resident definitions, and comparison with CL's
`do-symbols` / CLOS MOP. As currently written, the Emacs operational
details dominate the Lisp theoretical content.

---

## Suggested Title Variants

The current title "Emacs All The Way Down" is memorable but slightly
informal and does not convey the technical contribution. Suggestions:

1. **"Emacs as MCP Server: From Python Shim to Pure Elisp in One Session"**
   -- Descriptive, signals the before/after arc. Best for EmacsConf.

2. **"The obarray Is the API: Exposing 779 Emacs Functions via MCP"**
   -- Emphasizes the key insight. Strong for either conference.

3. **"Runtime Reflection as Protocol: Building an MCP Server with mapatoms and funcall"**
   -- Foregrounds the Lisp angle. Best for EuroLisp.

4. **"Emacs All The Way Down: A Pure Elisp MCP Server in 280 Lines"**
   -- Keeps the current title but adds a concrete hook. Good compromise.

5. **"No Shim Left Behind: Replacing 2381 Lines of Python with 280 Lines of Elisp"**
   -- Punchiest option. Risks being read as language partisanship.

---

## Abstract Draft (150 words, CFP-ready)

> We describe the design and implementation of a pure Emacs Lisp server
> for the Model Context Protocol (MCP), enabling AI agents to invoke
> Emacs functions as tools. The server is 280 lines of Elisp with no
> external dependencies. It uses `mapatoms` to introspect the obarray
> at startup, filtering for text-consumer functions via arglist
> heuristics, and exposes them as MCP tools dispatched through
> `funcall`. The system began as a five-layer Python-mediated stack
> (introspector, escaper, dispatcher, manifest, server) but was
> collapsed to a single Elisp file after discovering that Emacs batch
> mode can serve JSON-RPC directly -- provided stdout buffering is
> bypassed via `send-string-to-terminal`. We report measurements on
> eleven conjectures including emacsclient latency (2.3ms median),
> Unicode fidelity across 14 character classes, arglist heuristic
> precision (40%, refuting our 80% prediction), and the autoload
> barrier hiding 222 functions. The system exposes 779 tools from a
> vanilla Emacs.

---

## Strengths

1. **Clear narrative arc**: The progression from five-layer Python stack
   to single-file Elisp is a strong story. The "pivot moment" (slide 4)
   where Unicode round-trip testing reveals Python is unnecessary is
   well-placed dramatically.

2. **Empirical rigor**: 11 conjectures with explicit confirmation/refutation
   status is unusual for a conference talk and adds credibility. The
   willingness to report C-002's refutation (40% vs 80% predicted)
   strengthens the methodology.

3. **Actionable discoveries**: The C-011 stdout buffering finding is
   independently valuable. Anyone building an Emacs batch-mode server
   will hit this. The comparison table of 6 approaches (slide 6) is
   a useful reference.

4. **Quantitative throughout**: Every claim is backed by a number
   (779 tools, 2.3ms latency, 14 char classes, 191 tests, 33 categories).
   This is the right level of evidence for a technical audience.

5. **Architecture diagrams**: The Mermaid sequence diagram (slide 15)
   cleanly shows the dual-path dispatch (in-process funcall vs daemon
   emacsclient). The Gantt chart (slide 16) is an unusual but effective
   way to show project timeline density.

6. **Honest about limitations**: C-002 refutation, daemon instability
   under concurrent agents, text property leaks -- these are presented
   without hedging.

---

## Weaknesses

1. **No demo slot**: There is no slide dedicated to a live demonstration
   or screen recording. For EmacsConf, a 2-minute demo showing
   `emacs --batch -Q -l emcp-stdio.el` responding to MCP requests would
   be more convincing than any number of tables.

2. **Too many slides for 20 minutes**: 18 content slides averaging
   ~67 seconds each leaves no time for demos, audience questions, or
   breathing room. Several slides are data-dense (C-006 Deep Dive,
   Agent Coordination) and would each need 2-3 minutes to present
   properly. Realistic capacity is 12-14 slides for a 20-minute talk.

3. **Mermaid diagrams may not render**: The org file uses `#+begin_src mermaid`
   blocks. These will not render in Beamer/PDF export (they appear as
   code blocks). For the actual talk, these need to be pre-rendered as
   images or the export pipeline needs mermaid-cli integration.

4. **Missing "why should I care" framing**: The talk jumps straight to
   the axiom without establishing why MCP matters, what agents need from
   editors, or what problem this solves for the audience. Slide 1 states
   facts; it does not motivate.

5. **CPRR methodology introduced late**: The conjecture framework is
   central to the project's methodology but is not explained until
   slide 11. Audience members seeing "C-004" and "C-011" on earlier
   slides will not have context.

6. **Daemon data layer undersold**: The 9 daemon tools (slide 7) are
   arguably the most practically useful part of the system (org capture,
   buffer access, eval in daemon) but get only one slide. The "Emacs as
   database" concept deserves expansion.

7. **Agent coordination slide is tangential**: Slide 9 (daemon churn
   under 27 agents) is interesting operational data but is about the
   development process, not the artifact. It may confuse audiences who
   think the MCP server requires 27 agents.

---

## Slide-by-Slide Feedback

### Slide 1: "Emacs All The Way Down: An Experience Report"
- **Keep.** Good opening summary. Add one sentence of motivation: "AI
  agents need tool registries. Emacs already has one: the obarray."

### Slide 2: "The Axiom"
- **Keep.** This is the thesis statement. Consider adding a one-line
  contrast: "Most MCP servers hardcode their tool list. This one asks
  Emacs what it can do."

### Slide 3: "Starting Point: The Python Shim"
- **Keep, but simplify.** The layer table is useful for showing what was
  eliminated. Consider cutting the bullet points below the table -- they
  are details that belong in later slides.

### Slide 4: "The Pivot"
- **Keep.** This is the dramatic turning point. The rhetorical question
  "What if Emacs IS the server?" is effective. Consider making the
  Unicode observation more concrete: one example (`(string-trim " hello ")`
  round-tripping through JSON-RPC).

### Slide 5: "emcp-stdio.el"
- **Keep.** Core technical slide. The 5 bullet points map exactly to
  the architecture. The command-line invocation example is good.

### Slide 6: "The Deletion"
- **Keep.** High emotional impact. The before/after ASCII diagram is
  effective. Consider showing the diff stats (`-2381 +1309`) more
  prominently -- perhaps as the slide subtitle.

### Slide 7: "C-011: Stdout Buffering"
- **Keep, but move earlier or flag the conjecture framework.** This is
  one of the best slides -- a real engineering discovery with a clean
  comparison table. However, "C-011" is meaningless to the audience at
  this point. Either introduce the numbering scheme first, or just call
  it "The Real Bug: stdout buffering in batch mode."

### Slide 8: "Daemon Data Layer"
- **Expand.** This is the most practically useful feature for Emacs
  users. The tool table is good. Add a concrete example: "An AI agent
  can read your org-mode TODO list, set TODO states, and capture new
  entries -- all through MCP, without touching the filesystem."

### Slide 9: "Testing at Scale"
- **Keep, but tighten.** The tier table is useful. The "Top categories"
  bullet can be cut -- it is detail that does not help the narrative.

### Slide 10: "Agent Coordination"
- **CUT or move to appendix.** This is about the development process
  (many Claude agents sharing a daemon), not the artifact. It is
  interesting but will confuse the audience about what the talk is about.
  If kept, relabel: "Aside: What Happens When 27 Agents Share a Daemon."

### Slide 11: "Conjectures: CPRR Lifecycle"
- **Keep, but move to slide 3 or 4.** The conjecture framework is the
  methodological backbone. The audience needs it before they see C-004,
  C-011, etc. The Mermaid state diagram is good but will not render in
  Beamer -- pre-render it as an image.

### Slide 12: "C-006 Deep Dive"
- **CUT or abbreviate.** Five hypotheses is too much detail for a
  conference talk. The key finding ("text-consumer heuristic acts as a
  natural stabilizer") can be stated in one bullet on the conjectures
  summary slide.

### Slide 13: "C-009: The Autoload Barrier"
- **Keep, but shorten.** The 5-approach table is interesting but will
  take 2+ minutes to explain. Reduce to the problem statement and the
  key tension: "safe approaches are incomplete, complete approaches are
  unsafe." One bullet per approach, not a full table.

### Slide 14: "What We Proved"
- **Keep.** Strong summary. The parallel structure (X IS the Y) is
  effective rhetoric.

### Slide 15: "What We Discovered"
- **Keep.** Good complement to slide 14. The four discoveries are
  well-chosen. Consider merging with slide 14 into a single "Results"
  slide.

### Slide 16: "By the Numbers"
- **Keep.** Audiences love summary tables. Put this near the end, just
  before the closing.

### Slide 17: "Architecture"
- **Keep, but move to slide 5-6 area.** The sequence diagram should
  appear when the architecture is first discussed, not near the end.
  Will not render as Mermaid in Beamer -- pre-render.

### Slide 18: "Project Arc" (Gantt)
- **CUT.** The Gantt chart is interesting as project documentation but
  does not contribute to the conference talk. It implies "look how much
  we did in a short time," which is not the thesis.

### Slide 19: "Open Questions"
- **Keep.** Good closing slide. The four open questions invite follow-up
  conversation. The `aq` gossip layer mention is a nice forward hook.

### Slide 20: "Links"
- **Keep.** Standard closing slide with references. Consider adding a
  QR code for the repository URL.

---

## Suggested Reordering (for 20-minute talk, ~13 slides)

1. Title + motivation (current slide 1, expanded)
2. The Axiom (current slide 2)
3. CPRR Methodology (current slide 11, abbreviated -- just the framework)
4. Starting Point: Python Shim (current slide 3)
5. Architecture diagram (current slide 17, moved here)
6. The Pivot (current slide 4)
7. emcp-stdio.el (current slide 5)
8. The Deletion (current slide 6)
9. stdout Buffering discovery (current slide 7, renamed)
10. Daemon Data Layer (current slide 8, expanded)
11. Conjectures Summary + Key Results (slides 11, 14, 15 merged)
12. By the Numbers (current slide 16)
13. Open Questions + Links (slides 19, 20 merged)

Slides to cut: Agent Coordination (10), C-006 Deep Dive (12), Project Arc Gantt (18), Testing at Scale (9, merge key points into slide 12).

---

## Suggested Additions for EmacsConf

- **Live demo slide**: Add a slide that is just the command to run, with
  a note to switch to terminal. Show `tools/list` returning 779 tools,
  then `tools/call` executing `string-trim`. 2 minutes maximum.
- **"Try it yourself" slide**: Installation instructions. `git clone`,
  `emacs --batch -Q -l src/emcp-stdio.el -f emcp-stdio-start`. Emacs
  users want to try things.
- **Comparison with existing approaches**: Brief mention of emacs-lsp,
  gptel, ellama, and how this differs (inverted control flow: editor
  exposed to agent, not agent embedded in editor).

## Suggested Additions for EuroLisp

- **Language-level reflection comparison**: Add a slide comparing
  Emacs Lisp `mapatoms`/`obarray` with Common Lisp `do-symbols`/
  `find-all-symbols`, Clojure `ns-publics`, Scheme environments.
  The question "can your Lisp enumerate its own capabilities at runtime?"
  generalizes beyond Emacs.
- **`funcall` as universal dispatch**: Discuss how the lack of static
  typing makes `funcall` a natural RPC dispatch mechanism. Compare with
  CL's `funcall` and the implications for building protocol servers in
  dynamically typed Lisps.
- **Serialization via `prin1`**: The observation that `prin1-to-string`
  is both the security boundary (proper escaping) and the serialization
  layer is a Lisp-specific insight. Compare with CL's `prin1-to-string`
  and reader macros.
- **The autoload problem as a module system question**: C-009 (222
  hidden functions) is really about the tension between lazy loading and
  reflection. This generalizes to any Lisp with autoload or demand-loading.
  ASDF defsystem has analogous issues.

---

## PDF Export Notes

- Beamer PDF export succeeded via `org-beamer-export-to-pdf` using the
  system's LaTeX installation (`pdflatex`).
- Output: `docs/presentations/experience-report-2026-03/slides.pdf` (184 KB).
- Mermaid code blocks (slides 11, 17, 18) render as literal source code
  in the PDF. For a presentation-ready PDF, these need to be pre-rendered
  to images using `mmdc` (mermaid-cli) and included as `#+ATTR_LATEX` images.
- The `#+REVEAL_THEME` and `#+REVEAL_TRANS` headers suggest the slides
  were also intended for reveal.js export (`ox-reveal`). The Beamer
  export ignores these. Consider adding Beamer-specific options
  (`#+BEAMER_THEME`, `#+BEAMER_COLOR_THEME`) for dual-target export.
- LaTeX auxiliary files (`slides.tex`, `slides.aux`, `slides.log`, etc.)
  were generated alongside the PDF. Consider adding `*.aux *.log *.nav
  *.out *.snm *.toc *.vrb *.tex` to `.gitignore` for this directory.
