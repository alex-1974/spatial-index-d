# ADR-0003 — RTreeX M3 bulk construction and performance policy

- **Status:** Accepted for M3 integration; release pending M5.
- **Date:** 2026-10-31
- **Scope:** `spatial_index.rtreex` bulk construction.

## Problem

RTreeX already supports dynamic mutation with R*-inspired split heuristics.
Dunia and other consumers also need to load large, preexisting data sets
without incurring a split per overflow and excessive bounding-box overlap.

## Decision

Add a **single** `bulkLoad(scope const(Item)[])` API that *replaces* the
current index. Its elements are copied; the index never retains the
consumer-provided slice or underlying geometry.

- Validate every item for finite, ordered bounds and unique IDs **before**
  adoption. Invalid input / duplicate IDs -> `false`, previous index intact.
- Build a separate candidate index, then commit the new pool and lookup map
  only after the build succeeds. Allocation failures may still throw, without
  promising a no-throw API.
- At each level, group boxes using an **OMT-inspired, two-axis spatial sort**:
  balanced groups, x columns sized by group count, then y ordering in each
  column. Parent bounding boxes become the next level. This retains R-tree
  invariants without changing dynamic updates or query semantics.
- The construction produces a uniform-depth tree. All non-root nodes obey
  occupancy `ceil(n / MaxEntries)` grouping and minimum occupancy.
- Existing incremental `insert`, `remove` and `update` remain unchanged.
- Keep the original R*-inspired dynamic split. No new public strategy flags.

The implementation is **OMT-inspired**, not a verbatim port of RBush's
multi-select OMT construction or a full R*-tree with forced reinsertion.
Do not advertise either algorithm as fully implemented.

## Alternatives

**Repeated insertion**: remains supported and is the baseline, but is not
the chosen construction path for initially empty large data sets.

**STR (sort-tile-recursive)**: shares a two-axis sorting principle. An
independent STR variant is not introduced unless it beats the current
grouping on realistic workloads; another API knob would add maintenance cost.

**Hilbert bulk order / Flatbush**: most attractive for a separate immutable
packed index. RTreeX must support ongoing updates, so no fixed packed
representation is introduced in M3.

**R* forced reinsertion and alternate splits**: not added until repeated
insertion and edit-time profiles demonstrate a material benefit.

**SIMD**: deferred until query profiling establishes bounding-box checks
as a bottleneck. Avoid optimizing unmeasured branches.

**Two-tier static/dynamic hybrid**: rejected for M3 due to extra invalidation,
deduplication and update complexity; a single tree comes first.

## Measurement and reliability

Two independent workloads are required:
1. Deterministic synthetic distributions (`urban`, `sparse`, `long`)
   at 10k, 100k and 1M entries. These are **not actual OSM extracts**.
2. An authentic OSM XML extract (Liechtenstein, 2013) from the
   `osm2pgsql` test corpus at a pinned upstream commit, converted to
   point/node and Way bounding boxes by a reproducible Python script.

The benchmark uses DMD and LDC release builds and compares incremental
insertion against packed loading on the same dataset and runner. It records
build time, 200 query time, up to 1000 update times, GC allocation-used delta
and result IDs (count plus commutative checksum). The `storageStats`
snapshot additionally provides node slots and a lower bound from occupied
node pool and raw lookup values, so memory comparison need not rely on
the GC alone. This is practical performance evidence, not microbenchmark
science.

**Caveats:** Structural lower bounds exclude associative-array overhead,
runtime allocation capacities and garbage-collector metadata. GC deltas are
rough process-level memory indicators, not exact per-index resident memory. OSM data are WGS84 lon/lat (not projected);
distance/metric nearest-neighbor performance is not tested. CI hardware is
shared and samples are not repeated confidence intervals.

A successful benchmark must execute operations in release mode. Never put
necessary side effects inside `assert`: release configurations may compile
assert calls away. See the benchmark's explicit `enforce` calls.

## Consequences

Dunia may bulk-load large known data sets and then edit them dynamically.
There is no new dependency in the published library. Current Node and
payload storage remain candidates for later independent optimization if
measured memory cost warrants it.

Before M5 release, repeat the representative measurements on the target
XPS and assess consumer archive, complete public Ddoc and the controlled
release compiler matrix. No release tag is created by M3.
