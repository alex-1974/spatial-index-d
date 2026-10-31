# RTreeX — Engineering design notes

**Status:** design candidate, not implemented or public API.

## Required editor operations

| Operation | Intended use | Main concern |
| --- | --- | --- |
| Insert | add a node, way or indexed segment | stable identity |
| Remove | delete from working graph | correct removal |
| Update | move a node, change Way bounds | consistent index |
| Search | viewport intersection | candidate false positives |
| Point/radius candidate query | hit-testing and snapping | exact test belongs to caller |
| Bulk load | load downloaded OSM region | build speed / memory |

## Algorithm candidates

1. R*-inspired choose-subtree and split optimization for dynamic updates.
2. RBush-inspired overlap-minimizing top-down bulk loader (OMT).
3. Compact node pool and iterative traversal for cache locality.
4. Packed/Hilbert static structures may be separate indexes later.
5. SIMD comparison only after representative measurements.

Avoid a combined design with complex incremental and static tiers before the
single dynamic implementation is measured.

## Required contracts before implementation

- Empty, inverted, degenerate, touching and non-finite bounding boxes.
- Payload identity, duplicate insertion, removal by ID/handle, and updates.
- No geometry ownership; explicit memory and lifetime model.
- Iterator and callback invalidation on mutation; concurrent access policy.
- Query order versus deterministic membership.
- Reporting failure without corrupting the tree.
- Unbounded geographic extents and antimeridian handling belong to caller's
  coordinate representation, not hidden index normalization.
- No automatic full-geometry predicate: bounds are only a prefilter.

## Minimal practical qualification

- Differential tests against a linear scan and independent box-overlap oracle.
- Mixed insert/remove/update workloads, empty and degenerate cases.
- Consumer smoke test importing the package from another DUB project.
- Three realistic object sizes: around 10k, 100k, 1M.
- Compare bytes per object, build time, viewport query time and update cost.
- At least one dense city extract and one sparse/long-way distribution.
- Both DMD and LDC; release builds before performance comparisons.

No publication until an initial consumer-facing API is frozen.
