# spatial-index-d — Design Specialization

Canonical `d-geospatial-workspace` principles remain authoritative. This
document records only decisions specific to spatial indexing.

## Scope

This is a collection of reusable spatial storage/index structures for D,
not a geometry kernel or an OSM application package. Coordinates are interpreted
in the caller's coordinate system; no CRS/projection or unit is implicit.

RTreeX is the first intended implementation. Additional tree families need
a real consumer and their own well-defined contract.

## Index versus geometry

The index answers spatial candidate queries. Exact geometry predicates,
topological validation, pixel hit-testing and snapping are consumer or geometry
library responsibilities. Do not silently claim exact intersection when only
axis-aligned bounding boxes are tested.

## Memory, ownership and mutation

Avoid per-object heap allocations in hot query paths where practical. The
index stores compact bounds and caller-defined lightweight references/handles,
not ownership of application geometries.

Insertion, deletion and geometry updates must keep the index consistent.
Handle stability, re-insertion, duplicate identities and iterator invalidation
are API decisions that must be defined before implementation is public.

## Numerical boundaries

Define and test empty/inverted/nonfinite bounds, point rectangles, touching
edges, overflow, coordinate type policy and degenerate geometries. No global
epsilon is allowed to redefine spatial overlap.

## Algorithm selection

R*-style split/subtree heuristics and RBush/OMT loading are candidates; neither
name nor algorithmic combination is a substitute for measurements. Prefer the
simplest correct design that satisfies common editing workloads.

## Compatibility

Index ABI and DUB dependencies must not depend on local workspace directory
layout. A public API is a compatibility commitment.


## Public naming follows consumer intent

Public declarations should say **what the caller wants to do**, not **how the
tree happens to implement it**. Names such as `insert`, `remove`, `update`,
`search`, `replaceAll`, `clear`, `length`, `empty` and `tryGetBounds`
are intentional.

Implementation algorithms (R*-split, OMT grouping, balancing, free lists),
node occupancies, traversal mechanics and storage diagnostics belong in private
declarations and technical documentation, not as everyday API options.
`RTreeX` is the one deliberate technical name: it identifies the index
family without exposing its implementation strategy.

Prefer defaults that work for typical consumers. Do not add public template
knobs, policy enums, strategy flags, or diagnostic types merely because an
internal implementation supports them. Any eventual specialist extension
must have a demonstrated real consumer use case, clear semantics and tests.

Naming must not hide important behavior: `replaceAll(items)` means it replaces
the entire index; `insert(item)` does not. Range searches return candidate
IDs based on rectangular overlap, never an implicit exact geometry match.

The preferred one-argument `search(bounds)` returns matching IDs and
allocates its result array. The two-argument `search(bounds, visitor)` enables
high-throughput, allocation-free traversal for callers such as Dunia. Both
overloads are named by the consumer task rather than the traversal algorithm.
