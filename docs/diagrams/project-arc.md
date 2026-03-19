# Project Arc

```mermaid
gantt
    title From Spec to Pure Elisp — Two Sessions
    dateFormat YYYY-MM-DD
    axisFormat %m-%d

    section Phase 1: Python Shim (2026-03-17)
    spec.org + CLAUDE.md generation        :done, p1, 2026-03-17, 3h
    escape.py + introspect.el + dispatch.py :done, p2, after p1, 3h
    server.py (MCP over stdio)             :done, p3, after p2, 2h
    health-check.sh + CI                   :done, p4, after p3, 1h
    Conjectures C-001 thru C-006 registered :done, p5, after p3, 2h
    11 GitHub issues wired (bd)            :done, p6, after p4, 1h

    section Phase 2: Measurement (2026-03-18 AM)
    C-001 protocol-level (two-tier confirmed) :done, m1, 2026-03-18, 2h
    C-002 arglist audit (refuted at 40%)      :done, m2, after m1, 1h
    C-003 latency (2.3ms median confirmed)    :done, m3, after m1, 1h
    C-004 non-ASCII (14 char classes)         :done, m4, after m1, 1h
    C-005 init latency (confirmed)            :done, m5, after m1, 1h
    C-006 vanilla vs configured (confirmed)   :done, m6, after m1, 1h

    section Phase 3: Paradigm Shift (2026-03-18 PM)
    Unicode round-trip via MCP tools       :done, s1, after m6, 1h
    Conjecture: Emacs all the way down     :milestone, s2, after s1, 0d
    emcp-stdio.el (pure Elisp MCP server)  :done, s3, after s2, 2h
    Daemon data layer (9 tools)            :done, s4, after s3, 1h
    json-serialize unibyte fix (C-004)     :done, s5, after s3, 30min
    C-008 confirmed (Python replaceable)   :done, s6, after s4, 30min

    section Phase 4: Python Elimination
    Delete entire Python stack             :crit, done, d1, after s6, 30min
    Purge all references (27 files)        :done, d2, after d1, 1h
    .mcp.json rewritten for Elisp          :done, d3, after d1, 30min

    section Phase 5: Hardening (19 agents)
    5 contract specs (I/O, collection, dispatch, daemon, integration) :done, h1, after d2, 2h
    ert test suite (86 tests)              :done, h2, after d2, 2h
    CI workflows (ert + org-lint)          :done, h3, after d2, 1h
    docs/emcp-stdio.org (751 lines, 80 links) :done, h4, after d2, 2h
    Audit (108 links verified)             :done, h5, after h4, 1h
    build-tool crash fix (maximalist 9217) :done, h6, after h2, 30min
    org-lint fix (spec.org orphan)         :done, h7, after h3, 30min

    section Phase 6: Investigation
    C-006 re-examination (5 hypotheses)    :done, i1, after h6, 2h
    batch implies -q (H1 confirmed)        :done, i2, after i1, 30min
    Filter masks 93% of delta (H2)         :done, i3, after i1, 30min
    222 hidden autoloads (H3)              :done, i4, after i1, 30min
    Category error in test (H5)            :done, i5, after i1, 30min
    C-009 autoload barrier (5 conjectures) :active, i6, after i4, 1d
    C-010 version compat (27.1+ confirmed) :done, i7, after i5, 1h
    C-011 stdout buffering discovered      :active, i8, after h6, 1d
```
