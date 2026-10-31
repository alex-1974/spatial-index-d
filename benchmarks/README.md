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
Do not interpret this as a precise bytes-per-entry measurement.

Timing uses a monotonic clock, includes allocator effects and depends on
hardware/load; compare methods within each run, repeat on the intended XPS.
No performance threshold is used to pass or fail CI.

For actual OSM measurements, an extracted bounding-box corpus with explicit
provenance must be provided; these results must never be described as
benchmarks performed on downloaded OSM data.
