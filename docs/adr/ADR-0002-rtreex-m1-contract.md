# ADR-0002 — RTreeX v0.1 dynamic index contract

- **Status:** Accepted for M1/M2 implementation; review before first release.
- **Date:** 2026-10-31
- **Scope:** `spatial_index.rtreex`

## Coordinates and bounds

- Initial implementation: axis-aligned **2D** rectangles (`Bounds2!T`).
- Coordinate scalars: `int`, `long`, `float`, `double`.
- Input is valid iff each lower coordinate is <= upper and each floating
  coordinate is finite. Negative/empty/inverted bounds or NaN/infinities are
  rejected by mutators and yield zero search results.
- Zero-width and zero-height bounds are **valid**, including point rectangles.
- Intersections are **closed/inclusive**: touching edges count as intersections.
- Index does not define CRS, map projection, global epsilon or topology.
- Extremely large finite rectangles remain valid; split heuristics may
  saturate numerically but must not affect correctness of search results.

## Identity and storage

- `RTreeX!(T, Id, MaxEntries)`; `Id` is `uint` or `ulong` in M2;
  default `ulong`. `MaxEntries` is compile-time 4..64, default 16.
- Unique, caller-provided IDs. No sentinel ID is reserved.
- Index owns **only** copied bounds, IDs, tree nodes and lookup structures.
  It never owns or retains a geometry object pointer.
- Duplicate insertion, nonexistent deletion, invalid insertion/update: return
  `false` with no logical change.
- `update(id, bounds)` returns `true` for an existing unchanged box.
- `tryGetBounds(id, out bounds)` allows inspection of the stored box.
- Struct copying is disabled: accidental copies must not alias mutable
  ownership. `clear()` restores empty state; the GC can reclaim backing
  storage after the index is discarded.
- Public indices and handles refer to caller IDs, **not node slot offsets**.

## Mutations and failure behaviour

- `insert`, `remove`, `update`, `clear` are the supported mutations.
- Operations are synchronous. On successful return, queries see the new tree.
- Deletion condenses underfull branches and reinserts orphaned entries;
  the root contracts when it has a single remaining child.
- No concurrent readers/writers without external synchronization.
- **Mutation during a search callback is forbidden**. Calls and callbacks
  have no reentrant mutation contract.
- No persistence, stable node handles, snapshot or iterator API in M2.
- Out-of-memory exceptions are not promised to provide transactional rollback
  during tree reconstruction; precondition failures are non-destructive.

## Queries

- `search(bounds, visitor)` visits all matching ID candidates or stops when
  a visitor returns `false`. Return value is the number of callbacks invoked.
- No guaranteed result iteration order (insertion history affects shape).
- The query path itself performs no explicit heap allocation; the caller is
  responsible for any allocation in its visitor.
- Searches return **bounding-box candidates**, not exact geometry hits.
- Empty tree and invalid search bounds produce zero callbacks.
- No nearest-neighbor or radius-specific API in M2: these need an explicit
  distance/metric contract and are not silently approximated.

## Algorithm and implementation

- Dynamically balanced R-tree with **compact pool of value nodes** and a
  reusable free list; no per-node `new`/individual GC allocation.
- Subtree selection uses R*-inspired overlap enlargement at the leaf-parent
  level and area enlargement higher up.
- Split evaluates ordering of entry lower/upper coordinates along both axes,
  selects the axis using total margins and then the distribution using
  overlap followed by total area. This is a practical R*-style baseline;
  **forced reinsertion is deliberately not implemented in M2**.
- Median/OMT mass loading is separately scheduled for M3; repeated `insert`
  is the only initial construction path.

## Verification

- Linear-scan oracle for search and mixed insert/remove/update workloads.
- Targeted tests for touching boundaries, degenerate boxes, duplicate IDs,
  node/root underflow, free-list reuse, early-stop and tree invariants.
- DMD 2.111.0, LDC 1.41.0 and controlled six-compiler release gate.
- An external DUB consumer compiles through `spatial_index.rtreex`.
- Avoid unrealistically strict benchmark thresholds in M2.
