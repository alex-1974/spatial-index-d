/**
 * Minimal release-build comparison of incremental insertion and packed
 * bulkLoad. Not a research benchmark: results are workload/hardware specific.
 *
 * Usage (from benchmarks/):
 *   dub run --build=release --compiler=ldc2 -- 100000 urban
 *
 * Workload names: urban, sparse, long.
 * Input is deterministic and OSM-shaped, but SYNTHETIC; real OSM extracts
 * must be measured separately before claiming field performance.
 */
module app;

import spatial_index.rtreex : Bounds2, RTreeX;
import core.memory : GC;
import core.time : MonoTime;
import std.conv : to;
import std.stdio : writeln, writefln;

alias Index = RTreeX!(double, ulong, 16);
alias Box = Bounds2!double;
alias Item = Index.Item;

private double ms(MonoTime start)
{
    return cast(double) (MonoTime.currTime - start).total!"usecs" / 1000.0;
}

private Item[] workload(size_t n, string kind)
{
    Item[] items;
    items.length = n;
    size_t side = 1;
    while (side < n / side || side * side < n)
        ++side;

    foreach (i; 0 .. n)
    {
        double x, y, dx, dy;
        if (kind == "sparse")
        {
            x = cast(double) (i % side) * 75;
            y = cast(double) (i / side) * 75;
            dx = i % 9 == 0 ? 30 : 1;
            dy = i % 17 == 0 ? 30 : 1;
        }
        else if (kind == "long")
        {
            x = cast(double) ((i * 37) % 17000);
            y = cast(double) ((i * 127) % 17000);
            dx = i % 7 == 0 ? 3200 : 7;
            dy = i % 11 == 0 ? 700 : 2;
        }
        else
        {
            x = cast(double) ((i * 79) % 4000);
            y = cast(double) ((i * 113) % 4000);
            dx = i % 19 == 0 ? 80 : 3;
            dy = i % 31 == 0 ? 60 : 3;
        }
        items[i] = Item(cast(ulong) i, Box(x, y, x + dx, y + dy));
    }
    return items;
}

private struct Result
{
    double buildMs;
    double queryMs;
    double updateMs;
    size_t gcBytes;
    ulong checksum;
    size_t hitCount;
}

private Result run(const(Item)[] data, string kind, bool bulk)
{
    Index tree;
    GC.collect();
    auto before = GC.stats.usedSize;

    auto start = MonoTime.currTime;
    if (bulk)
    {
        assert(tree.bulkLoad(data));
    }
    else
    {
        foreach (item; data)
            assert(tree.insert(item.id, item.bounds));
    }
    const double buildMs = ms(start);
    auto after = GC.stats.usedSize;
    const size_t gcBytes = after > before ? after - before : 0;

    size_t hits = 0;
    ulong checksum = 0;
    const double domain = kind == "sparse" ? 60000 :
        kind == "long" ? 17000 : 4000;
    start = MonoTime.currTime;
    foreach (i; 0 .. 200)
    {
        const double x = cast(double) ((i * 983) % cast(size_t) domain);
        const double y = cast(double) ((i * 271) % cast(size_t) domain);
        const double span = kind == "sparse" ? 200 : 80;
        auto q = Box(x, y, x + span, y + span);
        hits += tree.search(q, (ulong id) {
            checksum += id * 1469598103934665603UL + 1;
            return true;
        });
    }
    const double queryMs = ms(start);

    start = MonoTime.currTime;
    const size_t modifications = data.length / 100 < 1 ? data.length :
        (data.length / 100 > 1000 ? 1000 : data.length / 100);
    foreach (i; 0 .. modifications)
    {
        const auto old = data[i].bounds;
        assert(tree.update(data[i].id, Box(old.minX + 1, old.minY + 1,
                                          old.maxX + 1, old.maxY + 1)));
    }
    const double updateMs = ms(start);

    return Result(buildMs, queryMs, updateMs, gcBytes, checksum, hits);
}

void main(string[] args)
{
    const size_t n = args.length > 1 ? to!size_t(args[1]) : 10_000;
    const string kind = args.length > 2 ? args[2] : "urban";
    assert(kind == "urban" || kind == "sparse" || kind == "long");
    assert(n > 0);
    auto data = workload(n, kind);

    const auto incremental = run(data, kind, false);
    const auto packed = run(data, kind, true);
    assert(incremental.hitCount == packed.hitCount);
    assert(incremental.checksum == packed.checksum);

    writeln("method,workload,entries,build_ms,query200_ms,update_ms,gc_used_delta_bytes,hits,checksum");
    writefln("incremental,%s,%s,%.3f,%.3f,%.3f,%s,%s,%s", kind, n,
             incremental.buildMs, incremental.queryMs, incremental.updateMs,
             incremental.gcBytes, incremental.hitCount, incremental.checksum);
    writefln("omt,%s,%s,%.3f,%.3f,%.3f,%s,%s,%s", kind, n,
             packed.buildMs, packed.queryMs, packed.updateMs,
             packed.gcBytes, packed.hitCount, packed.checksum);
}
