# spatial-index-d

Reusable spatial indexing data structures for D.

**Status:** repository bootstrap / pre-implementation. No spatial index API or
release is available yet. This repository is not ready for DUB publication.

## Purpose

`spatial-index-d` hosts independent, reusable spatial storage and search
structures. Its first planned implementation is **RTreeX**, a dynamic R-tree
designed for interactive editing, range queries and bulk loading. Dunia
(OpenStreetMap editing) is the first intended consumer, not a dependency.

Other indexes (for example, packed static trees or quadtrees) may be added only
when there is a concrete consumer need.

## RTreeX: intended scope

- Bounding-box intersection/range queries with deterministic boundary rules.
- Incremental insert, remove and geometry update.
- Fast bulk loading for pre-existing data.
- Compact storage with predictable allocation and lifetime.
- Caller-owned payloads referenced by stable identifiers or lightweight handles.
- No GIS, coordinate reference system, OSM or rendering assumptions.
- Practical performance with DMD and LDC; focus on real workloads.

**Algorithm selection is not frozen.** R*-tree subtree selection/splitting,
RBush-inspired OMT bulk loading and compact node pools are candidates, not
claims about implemented behaviour. See [the roadmap](ROADMAP.md) and
[ADR-0001](docs/adr/ADR-0001-scope-and-boundaries.md).

## Repository layout

```text
source/spatial_index/package.d  public package entry point (no API yet)
docs/adr/                       architectural decisions
tests/consumer/                 external DUB consumer smoke test
.github/workflows/              compiler / release qualification
```

## Development

The supported minimum D frontend is **2.111.0**; the controlled fast CI
baseline uses DMD 2.111.0 and LDC 1.41.0.

```sh
dub test --compiler=dmd --force
dub test --compiler=ldc2 --force
dub build --build=release --compiler=ldc2 --force
(cd tests/consumer && dub run --compiler=ldc2 --force)
```

Normal integration targets `develop`; `main` is reserved for qualified
states. This repository follows the `d-geospatial-workspace` practices.
The local `.workspace/` directory is not tracked.

## License

MIT. See [LICENSE](LICENSE).
