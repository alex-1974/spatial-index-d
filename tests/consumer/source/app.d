/**
 * External DUB consumer tests of the public package/module surface.
 * No workspace-relative application dependency is required.
 */
module app;

import spatial_index;
import spatial_index.rtreex;

void main()
{
    alias Box = Bounds2!double;
    RTreeX!(double, ulong) tree;

    assert(tree.insert(15, Box(0, 0, 10, 10)));
    assert(tree.insert(16, Box(50, 50, 60, 60)));
    assert(!tree.insert(16, Box(70, 70, 80, 80)));

    ulong[] selected;
    auto visited = tree.search(Box(5, 5, 12, 12), (ulong id) {
        selected ~= id; // consumer can choose to allocate results
        return true;
    });
    assert(visited == 1 && selected.length == 1 && selected[0] == 15);

    assert(tree.update(15, Box(100, 100, 110, 110)));
    assert(tree.search(Box(5, 5, 12, 12), (ulong id) {
        assert(0, "old bounds were not removed");
        return true;
    }) == 0);

    Box stored;
    assert(tree.tryGetBounds(15, stored) && stored == Box(100, 100, 110, 110));
    assert(tree.remove(15));
    assert(tree.remove(16));
    assert(tree.empty);
    safeConsumer();
}


/** Compile-check that normal indexing is available to @safe D consumers. */
@safe void safeConsumer()
{
    alias B = Bounds2!int;
    RTreeX!(int, uint) index;
    assert(index.insert(3, B(0, 0, 5, 5)));
    size_t seen;
    auto count = index.search(B(1, 1, 2, 2), (uint id) @safe {
        ++seen;
        return true;
    });
    assert(count == 1 && seen == 1);
    assert(index.update(3, B(4, 4, 6, 6)));
    assert(index.remove(3));
}
