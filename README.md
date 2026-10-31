# spatial-index-d

Reusable spatial indexing data structures for D.

**Status:** M1/M2 and M3 implemented and CI-qualified on `develop`;
**not yet released** or published to DUB. The API may evolve before its
first public release.

## Purpose

`spatial-index-d` hosts independent, reusable spatial storage and search
structures. Its first planned implementation is **RTreeX**, a dynamic R-tree
designed for interactive editing, range queries and bulk loading. Dunia
(OpenStreetMap editing) is the first intended consumer, not a dependency.

Other indexes (for example, packed static trees or quadtrees) may be added only
when there is a concrete consumer need.

## RTreeX: first dynamic index

The M1–M3 implementation in `spatial_index.rtreex` provides:

- 2D, closed/inclusive `Bounds2` with `int`, `long`, `float` or `double`.
- Unique caller-supplied `uint`/`ulong` entry IDs and non-owning payload identity.
- Insert, remove, update, lookup, clear and visitor-based intersection search.
- Validated, replacement-style `bulkLoad(Item[])` using balanced
  OMT-inspired spatial grouping, with no retained caller buffers.
- Compact array-backed node pool with slot reuse and root contraction.
- `storageStats` for node slots and a clearly labeled structural memory
  lower bound (not total RAM usage).
- R*-inspired subtree selection and split (without forced reinsertion).
- No result-array allocation in the search implementation; results are
  bounding-box candidates, not exact geometry matches.

**Not yet included:** nearest-neighbor, radial search, snapshots, persistence,
thread-safe mutation or a separate static packed index.

The initial contract is documented in
[ADR-0002](docs/adr/ADR-0002-rtreex-m1-contract.md), the bulk-loading choice
in [ADR-0003](docs/adr/ADR-0003-m3-bulk-loading.md).
See [M3 benchmark instructions](benchmarks/README.md) and
[the measured M3 report](docs/m3-performance-2026-10-31.md) for repeatable
build, query, memory and update comparisons. Performance evidence does not
imply a release.

### Basic use

```d
import spatial_index.rtreex : Bounds2, RTreeX;

alias Box = Bounds2!double;
RTreeX!(double, ulong) index;

assert(index.insert(101, Box(0, 0, 10, 10)));
size_t visited = index.search(Box(9, 9, 20, 20), (ulong id) {
    // Process candidate ID. Return false to stop early.
    return true;
});
assert(visited == 1);

assert(index.update(101, Box(20, 20, 30, 30)));
assert(index.remove(101));

// Rebuild from a complete batch of copied entries:
alias Item = RTreeX!(double, ulong).Item;
Item[] batch = [
    Item(101, Box(10, 10, 20, 20)),
    Item(102, Box(100, 100, 101, 101)),
];
assert(index.bulkLoad(batch));
assert(index.length == 2);
```

The index does not depend on Dunia, `geo-d` or an OSM schema. Use a thin
adapter from existing consumer rectangles where necessary.

## Repository layout

```text
source/spatial_index/package.d  package entry point for RTreeX
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
