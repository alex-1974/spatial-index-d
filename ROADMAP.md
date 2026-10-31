# spatial-index-d — Roadmap

## Status

Repository bootstrap. No published version and no implemented public RTreeX
contract. Start with 2D axis-aligned bounding-box indexing; do not promise a
3D or generic N-dimensional product before actual consumer qualification.

## M0 — Repository baseline

- [x] Create independent GitHub repository and reserve `RTreeX` name.
- [x] Establish DUB package identity, MIT license and importable package stub.
- [x] Define ownership and architecture questions in ADRs.
- [x] Add fast DMD/LDC checks and controlled release matrix configuration.
- [x] Add external consumer smoke-test package.
- [ ] Verify both compiler families and CI pass.
- [ ] Switch GitHub default branch to `develop` after creating the branches.
- [ ] Remove obsolete `master` once `develop` is default and `main` exists.

## M1 — RTreeX public contract

- [ ] Decide bounding-box scalar policy (initially 2D), invalid/empty bounds
      handling and edge-touching intersection rules.
- [ ] Define payload identity, insertion/remove/update signatures, duplicate
      policy and stable-handle semantics.
- [ ] Define callback/visitor query, early-stop and result ordering contracts.
- [ ] Define explicit allocation, ownership, move and iterator invalidation
      behaviour; decide whether a thread-safe variant is warranted (not default).
- [ ] Review consumer interoperability with `geo-d` without taking a mandatory
      geometry dependency.
- [ ] Implement external consumer tests for the selected API.

## M2 — Dynamic index core

- [ ] Implement compact node pool and free-list management.
- [ ] Implement correct search and insertion.
- [ ] Evaluate R*-style subtree selection/split against simpler variants.
- [ ] Implement erase/update, root contraction and empty-tree handling.
- [ ] Test adversarial overlap, degeneracy, repeated updates, delete/reinsert,
      zero and large populations and memory invariants.
- [ ] Ensure deterministic structural invariants and useful diagnostics.

## M3 — Bulk loading and performance

- [ ] Implement a simple, correct bulk-loader as baseline.
- [ ] Evaluate RBush-inspired OMT versus STR/Hilbert ordering where justified.
- [ ] Compare query/build/update latency and bytes/object for approximately
      10k, 100k and 1M objects on representative OSM extracts.
- [ ] Consider SIMD only if profiling shows bounding-box tests matter.
- [ ] Do not add a hybrid static/dynamic index before measured need.

## M4 — Dunia integration

- [ ] Validate viewport queries and efficient large-area exploration.
- [ ] Validate snapping/hit-testing candidate queries, including long Ways.
- [ ] Exercise geometry updates, dependency propagation, undo/redo and bulk
      insertions from representative editor actions.
- [ ] Decide whether Dunia should maintain separate entity and segment indices.

## M5 — First public release

- [ ] Finish Ddoc documentation for every exposed declaration, including
      commented runnable unittests for consumer-facing API.
- [ ] Pass controlled DMD/LDC tests, release builds and external consumers.
- [ ] Review dependency archive, license and reproducibility.
- [ ] Publish first release only after API, ownership and performance review.

Later candidates: packed static indexes, quadtrees and other structures only
when justified by an actual consumer.
