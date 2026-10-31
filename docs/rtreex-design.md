# RTreeX — M1/M2 Implementation Notes

**Status:** M1–M3 implemented and CI-qualified; no DUB release prepared.

## API and semantics

The accepted public contract is
[ADR-0002](adr/ADR-0002-rtreex-m1-contract.md).

- `RTreeX!(T, Id = ulong, MaxEntries = 16)`
- `Bounds2!T(minX, minY, maxX, maxY)`; default `.init` is invalid/empty.
- `insert(id, bounds)`, `remove(id)`, `update(id, bounds)`
- `bulkLoad(scope const(Item)[])` replaces the entire index after validation
- `tryGetBounds(id, ref bounds)`, `search(bounds, visitor)`
- `length`, `empty` and `clear`

Only 2D bounding boxes are included. Search returns broad-phase
candidates; exact geometry is an independent consumer responsibility.

## Storage and ownership

Nodes live in a dense dynamic array. Free node slots are recycled through
a free-list rather than independently allocating each tree node. Each node
has up to `MaxEntries` live entries plus one temporary overflow slot.

Each live leaf entry stores copied bounds and one caller ID; internal entries
store a bounding rectangle and a child pool index. The implementation uses
one uniform entry representation for simplicity; a later memory study may
justify specialized leaf and internal layouts.

A secondary `ID -> bounds` associative array lets callers erase/update
by ID without retaining the previous rectangle. The map is an intentional
memory/correctness trade-off: it increases per-entry memory but keeps the
initial API simple and removals spatially restricted. Revisit if M3 shows
significant memory pressure in Dunia.

The index does **not** own the referenced geometries and has no pointers
into caller memory. The index aggregate is noncopyable; no external node
slot or iterator handles are exposed.

## Search / insertion

Traversal is recursive with depth bounded by the R-tree height; the query
path uses no intermediate result array. The visitor can stop early.

- Parents immediately above leaves are selected by minimal additional
  overlap, then area enlargement and area.
- Higher parents are selected by minimal area enlargement, then area.
- Full nodes are split using an R*-inspired axis choice: summed margins
  of legal distributions along lower and upper coordinate orders.
- The chosen axis is split at minimal bounding-box overlap, then
  minimal combined area. Deterministic tie-breaking favors the first
  candidate order.

Forced reinsertion is **not** implemented: it increases mutation cost and
should only be added if measured editor workloads demonstrate a benefit.

## Deletion / updates

A removal finds the existing bounds through the ID map and descends only
through intersecting child rectangles. An underfull non-root child is
removed, its surviving entries are collected and reinserted. Root
contraction removes single-child roots after deletions.

An update removes the old spatial entry and inserts the new bounds while
preserving the caller ID. Precondition failures are non-destructive;
there is no promised transactional rollback for allocator failures.

No concurrent mutation or reentrant mutation from search visitors is
supported; callers must synchronize access.

## Correctness qualification

The M2 suite includes:

- degenerate and touching rectangles;
- invalid/inverted/nonfinite input and repeated IDs;
- root split, root shrink, node recycling and complete deletion;
- a 400-entry mixed edit scenario;
- a seeded, deterministic 6,000-operation differential test against a
  simple ID-to-box map and linear-scan query oracle;
- internal node and parent-bounds invariant checks;
- an independent external DUB consumer exercise.

Compiler qualification: fast DMD 2.111.0 and LDC 1.41.0 CI, additional
controlled six-compiler matrix at release gate. CI is authoritative, not a
claim about local XPS builds.

## M3: packed construction and performance

M3 introduces a single OMT-inspired, balanced two-axis packed builder.
It sorts x-oriented slices, sorts y within each slice, and packs each level
into uniform-height nodes. The new builder reuses all existing dynamic
operations. It deliberately does not add original RBush quickselect,
independent STR/Hilbert index variants or forced reinsertion.

- Validation rejects duplicate IDs and invalid boxes before adoption.
- Construction uses temporary state; callers' input arrays are not retained.
- Query and update correctness is verified after each rebuilt tree.
- On GitHub Actions LDC 1.41, the build speedup was 7.3x on a 1M-entry
  synthetic urban corpus and 5.8x on the 72,854-entry actual OSM fixture.
- Query timings were not uniformly better: for 1M urban entries, 200
  queries took 1.946 ms after packed loading versus 1.270 ms after
  incremental insertion. No blanket search-speed advantage is claimed.
- DMD 2.111 and LDC 1.41 performed the comparisons; see
  `docs/m3-performance-2026-10-31.md`, CSV artifacts and
  `benchmarks/README.md`.
- `storageStats` exposes node slots and a clear structural byte lower bound.
- GC allocation deltas are indicative, not reliable exact index footprint.

See [ADR-0003](adr/ADR-0003-m3-bulk-loading.md).

## Explicitly deferred beyond M3

- Additional STR/Hilbert algorithms; M3 includes only OMT-inspired bulk load.
- Runtime nearest-neighbor/radius contracts and metrics.
- Specialized compact leaf layouts and SIMD.
- Packed static tree or two-tier static/dynamic index.
- Data persistence, concurrency and snapshots.
- 3D / general N-dimensional API.
- Dunia entity-vs-segment indexing policy; see Issue #5 (M4).

## Performance policy

Benchmark actual viewer/cursor workloads at ~10k, 100k and 1M entries.
Compare build time, candidate query latency, editor updates and bytes per
object under DMD/LDC release builds. Prefer a small reproducible harness
to elaborate synthetic benchmark frameworks.
