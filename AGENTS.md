# Repository Engineering Context

This repository belongs to the `d-geospatial-workspace`.

Before changing architecture, public API, algorithms, ownership, storage layout,
allocation, safety, performance contracts, CI or releases, read the relevant
canonical workspace documents under `.workspace/`, when available:

- `.workspace/README.md`
- `.workspace/ROADMAP.md`
- `.workspace/DESIGN_PRINCIPLES.md`
- `.workspace/DLANG_PRACTICES.md`
- `.workspace/RESEARCH.md`
- `.workspace/QUALITY_GATES.md`
- `.workspace/GIT_GITHUB_WORKFLOW.md`
- `.workspace/REPOSITORY_STANDARD.md`
- `.workspace/TOOLCHAIN_ISSUES.md`

The workspace documents are authoritative. Do not duplicate their normative
rules in this repository. Record index-specific decisions under `docs/adr/`.
When `.workspace/` is unavailable, follow tracked repository documents and
explicitly note the missing workspace context when proposing substantial changes.

`spatial-index-d` is a general-purpose D library; Dunia is a consumer, not a
dependency. RTreeX is the first intended index. Do not silently publish a
speculative public API, change a numeric boundary rule, or introduce
OSM-specific assumptions into the core.

Prioritize realistic correctness, stable ownership, compact memory and
representative consumer performance over academic benchmark breadth.
