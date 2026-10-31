# M3 Performance Qualification — 31 October 2026

## Status and provenance

This is a reproducible **single-sample** engineering comparison of RTreeX
incremental insertion and packed OMT-inspired `bulkLoad`. It is not a
scientific benchmark and does not establish a universal speed ranking.

- Code: `feature/m3-bulk-performance`.
- GitHub Actions: [measured workflow run #41238242359](https://github.com/alex-1974/spatial-index-d/actions/runs/41238242359).
- Platform: Ubuntu 24.04 GitHub-hosted x86-64 shared runner.
- Compilers: DMD 2.111.0 / LDC 1.41.0, DUB 1.40.0; release configuration.
- Every test compares identical input items and 200 query results by hit
  count and commutative checksum; 1% of entries (capped at 1,000) are updated.
- Synthetic sizes: 10k urban, 100k sparse and long, 1M urban.
- Real OSM sample: 65,733 Nodes and 7,121 Ways from Liechtenstein
  2013-08-03, as stored in the pinned `osm2pgsql` test fixture
  (`7e44c916d17c20a6eea3882f946fd74f4773b738`).
  Coordinates are original WGS84 lon/lat rectangles, not projected meters.
  Credit: © OpenStreetMap contributors (ODbL).
- The benchmark's `enforce` operations execute under release builds.
  Earlier traces with side effects hidden within `assert` were invalid and
  are **excluded** from this report.

## Build and query times

Times are milliseconds. Query values are **the total for 200** viewport
candidate searches, not per query. Update values cover up to 1,000 edits.
All timings are a single runner measurement, not a confidence interval.

| Compiler | Corpus | Insert build | OMT build | OMT speedup | Query insert / OMT | Update insert / OMT |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| LDC 1.41 | 10k urban | 19.110 | 1.720 | 11.1× | 0.055 / 0.056 | 0.397 / 0.392 |
| LDC 1.41 | 100k sparse | 100.420 | 21.482 | 4.7× | 0.283 / 0.114 | 41.578 / 2.986 |
| LDC 1.41 | 100k long | 190.192 | 23.121 | 8.2× | 0.678 / 1.012 | 7.192 / 4.799 |
| LDC 1.41 | 1M urban | 2208.974 | 298.708 | 7.4× | 1.370 / 1.902 | 13.767 / 13.736 |
| LDC 1.41 | 72,854 OSM | 103.155 | 17.760 | 5.8× | 0.106 / 0.121 | 5.988 / 1.457 |
| DMD 2.111 | 10k urban | 111.314 | 10.832 | 10.3× | 0.304 / 0.338 | 2.751 / 2.189 |
| DMD 2.111 | 100k sparse | 1011.092 | 133.627 | 7.6× | 0.777 / 0.525 | 460.281 / 33.662 |
| DMD 2.111 | 100k long | 1208.736 | 129.868 | 9.3× | 2.817 / 4.865 | 48.984 / 29.233 |
| DMD 2.111 | 1M urban | 12360.605 | 1567.230 | 7.9× | 2.301 / 3.990 | 100.611 / 91.113 |
| DMD 2.111 | 72,854 OSM | 789.824 | 104.088 | 7.6× | 0.475 / 0.659 | 47.459 / 11.806 |

**Interpretation:** The packed build is consistently faster in all tested
construction workloads. Queries are not consistently faster: long ways and
dense million-entry workloads show increased query times after packed
construction. The query latency is nevertheless small in absolute terms on
these cases. No universal query-speed advantage is claimed.

## Structural storage

`storageStats.minimumBytes` adds occupied node-array values, free-list
values, and raw ID/rectangle pairs from the lookup table. It excludes AA
bucket/allocator overhead, runtime capacity, temporary buffers and stack.
It is a **lower bound on structural storage**, not resident bytes or full
GC memory. The same value results from DMD and LDC under this layout.

| Corpus | Insert nodes | OMT nodes | Insert minimum B/entry | OMT minimum B/entry |
| --- | ---: | ---: | ---: | ---: |
| 10k urban | 970 | 669 | 120.7 | 95.7 |
| 100k sparse | 12,994 | 6,669 | 148.1 | 95.5 |
| 100k long | 9,768 | 6,669 | 121.3 | 95.5 |
| 1M urban | 115,735 | 66,669 | 136.3 | 95.5 |
| 72,854 OSM | 7,486 | 4,860 | 125.5 | 95.5 |

The GC-used allocation delta is separately recorded in generated CSV artifacts
but includes runtime/transient heap effects, so it is **not** used as an exact
bytes-per-entry comparison.

## Decision and follow-up

1. **Keep** one default OMT-inspired packed constructor in RTreeX.
2. **Keep** existing dynamic R*-inspired insertion for interactive editing.
3. **Do not** add STR/Hilbert/forced-reinsertion/SIMD variants without an
   identified Dunia consumer bottleneck or repeatable improvement.
4. **Do not** add a hybrid static/dynamic indexing subsystem in M3.
5. Before a release, rerun representative workloads on the intended XPS and
   validate complete external consumer archive and release compiler matrix.
6. Dunia M4 must compare entity-level and segment-level indexing with actual
   editor operations; the large long-way query effect is a useful target.

## Reproduction

```sh
cd benchmarks
dub run --build=release --compiler=ldc2 -- 10000 urban
dub run --build=release --compiler=ldc2 -- 100000 sparse
dub run --build=release --compiler=ldc2 -- 100000 long
dub run --build=release --compiler=ldc2 -- 1000000 urban
```

For the authentic OSM sample and its pinned source, see
[`benchmarks/README.md`](../benchmarks/README.md).
