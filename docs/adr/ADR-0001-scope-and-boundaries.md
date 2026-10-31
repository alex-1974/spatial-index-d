# ADR-0001 — Package scope and first index

- **Status:** Accepted (repository bootstrap)
- **Date:** 2026-10-31

## Context

Dunia needs frequent 2D spatial viewport queries and incremental geometry
updates. The indexing implementation should also serve unrelated D consumers.
The existing D ecosystem already has an independently published package named
`rtree`, so this repository uses the unambiguous package identity
`spatial-index-d` and reserves the type name `RTreeX`.

## Decision

- Repository / DUB identity: `spatial-index-d`.
- Module family: `spatial_index`.
- First planned concrete implementation: `spatial_index.rtreex`,
  user-facing type `RTreeX`.
- Build a coordinate-reference-system-agnostic, application-independent
  spatial index library. Do not embed OSM objects, map projection rules,
  viewports, GUI components or renderer logic.
- Start with dynamic bounding-box indexing for 2D workloads.
- Treat geometry ownership as external; the index owns its own compact
  bookkeeping, not the consumer's geometry objects.
- Use explicit tests and representative workloads before selecting detailed
  split, reinsert, packing or search heuristics.
- Keep the public implementation unexposed until behaviour, lifetime and
  scalar contracts have been reviewed.

## Not decided by this ADR

- Exact D type template signature and supported scalar categories.
- Whether entry identity is a caller-supplied ID or an index-generated handle.
- Limits of search callback/iterator lifetimes.
- Exact touching/invalid box semantics.
- Subtree selection, split and forced reinsertion algorithms.
- Packed/static index details; 3D/general N-dimensional API.

These are follow-up M1/M2 decisions. Do not mistake the intended name for a
claimed feature-complete implementation.

## Consequences

Consumers can depend on the future package without adopting Dunia.
The project can add other well-qualified index structures without renaming its
repository. No release or consumer contract is implied by this bootstrap.
