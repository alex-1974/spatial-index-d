# spatial-index-d — Roadmap

## Status

M1/M2 dynamic RTreeX is integrated on `develop`; M3 packed bulk loading
and practical benchmark evidence are being qualified for integration.
No public release or DUB registry publication. The initial dimension is 2D.

## M0 — Repository baseline

- [x] Create independent GitHub repository and reserve `RTreeX` name.
- [x] Establish DUB package identity, MIT license and importable package stub.
- [x] Define ownership and architecture questions in ADRs.
- [x] Add fast DMD/LDC checks and controlled release matrix configuration.
- [x] Add external consumer smoke-test package.
- [x] Verify fast DMD/LDC compiler families and CI pass for M1/M2.
- [x] Switch GitHub default branch to `develop` after creating the branches.
- [ ] Remove obsolete `master` once `develop` is default and `main` exists.

## M1 — RTreeX public contract

- [x] Decide bounding-box scalar policy (initially 2D), invalid/empty bounds
      handling and edge-touching intersection rules.
- [x] Define payload identity, insertion/remove/update signatures, duplicate
      policy and stable-handle semantics.
- [x] Define callback/visitor query, early-stop and result ordering contracts.
- [x] Define explicit allocation, ownership, move and iterator invalidation
      behaviour; decide whether a thread-safe variant is warranted (not default).
- [x] Review consumer interoperability with `geo-d` without taking a mandatory
      geometry dependency.
- [x] Implement external consumer tests for the selected API.

## M2 — Dynamic index core

- [x] Implement compact node pool and free-list management.
- [x] Implement correct search and insertion.
- [x] Implement R*-inspired subtree selection/split; defer comparative
      performance measurement against simpler variants to M3.
- [x] Implement erase/update, root contraction and empty-tree handling.
- [x] Test adversarial overlap, degeneracy, repeated updates, delete/reinsert,
      zero and large populations and memory invariants.
- [x] Ensure deterministic structural invariants and useful diagnostics.

## M3 — Bulk loading and performance

- [x] Establish repeated insertion as the baseline and implement an
      OMT-inspired packed `bulkLoad` for complete replacement.
- [x] Assess STR and Hilbert alternatives; defer more implementations without
      a measured consumer requirement (ADR-0003).
- [x] Compare build/query/update and approximate GC allocations for 10k,
      100k, 1M synthetic OSM-shaped objects, plus 72,854 actual OSM
      node/way bounding boxes from pinned 2013 Liechtenstein test data.
- [x] Document uneven query effects and release-build benchmark limitations.
- [x] Defer SIMD without evidence of a query bottleneck.
- [x] Keep a single dynamic index; no speculative static/dynamic hybrid.

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
