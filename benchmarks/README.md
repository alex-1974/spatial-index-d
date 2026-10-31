# RTreeX M3 benchmark

Small, deterministic comparison of **incremental insert** versus
**OMT-inspired packed bulkLoad**.

## Run

```sh
cd benchmarks
dub run --build=release --compiler=ldc2 -- 10000 urban
dub run --build=release --compiler=ldc2 -- 100000 sparse
dub run --build=release --compiler=ldc2 -- 100000 long
dub run --build=release --compiler=ldc2 -- 1000000 urban
```

Repeat using `--compiler=dmd`. DUB `--` passes size and workload to the
executable; it emits one compact CSV-like table per invocation.

The three patterns are **synthetic** (not actual OSM extracts):
- `urban`: dense points, small buildings and occasional larger bounds;
- `sparse`: widely separated areas, small objects;
- `long`: narrow ways and a subset of very long overlapping bounds.

Each run uses 200 viewport queries and up to 1,000 geometry updates.
Results and checksum are compared between construction methods. The benchmark
does not invoke the full independent correctness suite; CI does that.

`gc_used_delta_bytes` is the rough change in D GC allocated-used memory over
construction, *not* an exact footprint. It excludes memory in unmanaged native
allocators and depends on GC collection/implementation and temporary buffers.
`minimum_structural_bytes` is a different, explicit lower-bound quantity:
node pool slot bytes + free-list contents + raw ID/bounds lookup values.
Divide it by `entries` for the structural **minimum bytes per item**, but
remember that runtime map buckets and unused allocator capacity are excluded.
`node_slots` exposes the high-water slot count (including recycled nodes).
Neither measure equals process RSS.

Timing uses a monotonic clock, includes allocator effects and depends on
hardware/load; compare methods within each run, repeat on the intended XPS.
No performance threshold is used to pass or fail CI.

## Authentic OSM sample

The optional `osm` workload reads an extracted CSV corpus. A
reproducible source used in GitHub Actions is `Liechtenstein 2013-08-03`,
provided by the `osm2pgsql` project's test suite, pinned to
`7e44c916d17c20a6eea3882f946fd74f4773b738`:

```sh
mkdir -p build/m3
curl -fL \
  https://raw.githubusercontent.com/osm2pgsql-dev/osm2pgsql/7e44c916d17c20a6eea3882f946fd74f4773b738/tests/data/liechtenstein-2013-08-03.osm.bz2 \
  -o build/m3/liechtenstein.osm.bz2
python3 benchmarks/extract_osm.py \
  build/m3/liechtenstein.osm.bz2 build/m3/liechtenstein.csv
(cd benchmarks && dub run --build=release --compiler=ldc2 -- \
  1000000 osm ../build/m3/liechtenstein.csv)
```

This archived extract yields **65,733 node rectangles + 7,121 Way
rectangles** (72,854 total). It is an authentic historical OSM geometry
sample, not a modern complete-map benchmark. Relations are not indexed
in the extractor. IDs in the CSV are sequential benchmark IDs. WGS84
longitude and latitude are used as raw axis coordinates; no distance
or projection claim is implied.

Data credit: © OpenStreetMap contributors. OpenStreetMap data are available
under the Open Database License (ODbL). The CI workflow downloads the
original data from the pinned upstream source; its artifacts contain
**measurement CSVs only**, not an extracted OSM database.

## Validated initial CI comparison

GitHub Actions Ubuntu 24.04 shared runner, release builds (one sample per
workload/compile configuration). Results are contextual, not XPS benchmarks:

| Compiler | Corpus | Insert build (ms) | Packed build (ms) | Query 200 insert/packed (ms) |
| --- | --- | ---: | ---: | --- |
| LDC 1.41 | 10k urban | 21.716 | 2.009 | 0.063 / 0.064 |
| LDC 1.41 | 100k sparse | 120.425 | 25.846 | 0.374 / 0.157 |
| LDC 1.41 | 100k long | 218.475 | 26.741 | 0.798 / 1.204 |
| LDC 1.41 | 1M urban | 2709.496 | 372.809 | 1.270 / 1.946 |
| LDC 1.41 | 72,854 OSM | 119.125 | 20.411 | 0.158 / 0.153 |
| DMD 2.111 | 1M urban | 14152.417 | 1749.387 | 2.806 / 4.408 |
| DMD 2.111 | 72,854 OSM | 897.479 | 106.112 | 0.548 / 0.707 |

The first attempts were invalid because `assert(insert(...))` was
optimized out in release mode; **those results were discarded**. The
validated run performs all operations independently of assertions
and checks a commutative ID checksum and hit count after each build.
GC memory deltas are not precise per-object footprint measurements.

For actual OSM measurements, an extracted bounding-box corpus with explicit
provenance must be provided; these results must never be described as
benchmarks performed on downloaded OSM data.
