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

    alias Item = RTreeX!(double, ulong).Item;
    Item[] newData = [
        Item(100, Box(0, 0, 1, 1)),
        Item(101, Box(5, 5, 6, 6)),
    ];
    assert(tree.replaceAll(newData));
    assert(tree.length == 2);
    assert(tree.search(Box(1, 1, 1, 1), (ulong id) {
        return true;
    }) == 1);
    newData[0].bounds = Box(100, 100, 100, 100);
    assert(tree.tryGetBounds(100, stored));
    assert(stored == Box(0, 0, 1, 1));
    assert(tree.update(101, Box(6, 6, 7, 7)));
    assert(tree.remove(100));
    assert(tree.remove(101));
    safeConsumer();
}


/** Compile-check that normal indexing is available to @safe D consumers. */
@safe void safeConsumer()
{
    alias B = Bounds2!int;
    RTreeX!(int, uint) index;
    assert(index.insert(3, B(0, 0, 5, 5)));
    RTreeX!(int, uint).Item[] items = [
        { 3, B(0, 0, 5, 5) },
        { 4, B(10, 10, 11, 11) },
    ];
    assert(index.replaceAll(items));
    size_t seen;
    auto count = index.search(B(1, 1, 2, 2), (uint id) @safe {
        ++seen;
        return true;
    });
    assert(count == 1 && seen == 1);
    assert(index.update(3, B(4, 4, 6, 6)));
    assert(index.remove(3));
    assert(index.remove(4));
}
