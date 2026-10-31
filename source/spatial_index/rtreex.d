/**
 * RTreeX: a dynamic two-dimensional R-tree for copied bounding boxes and
 * caller-owned identifiers.
 *
 * The index is independent of OSM and of any geometry package. An intersection
 * query returns bounding-box candidates, not exact geometry intersections.
 *
 * Internally, RTreeX uses a compact array-backed node pool and R*-inspired
 * split and subtree-selection heuristics. Packed construction uses an
 * OMT-inspired balanced two-axis group builder. Forced reinsertion is not
 * part of this implementation.
 *
 * See_Also:
 *   docs/adr/ADR-0002-rtreex-m1-contract.md
 */
module spatial_index.rtreex;

import std.math : isFinite;
import std.traits : isFloatingPoint;

/**
 * Closed, axis-aligned rectangle in two dimensions.
 *
 * Touching edges and zero-area rectangles are valid and intersect inclusively.
 * All coordinates must be finite for floating-point scalar types.
 * The default `Bounds2!T.init` is an invalid (empty) sentinel; construct
 * `Bounds2!T(0, 0, 0, 0)` explicitly to represent the origin as a point.
 *
 * Params:
 *   T = `int`, `long`, `float` or `double`.
 */
struct Bounds2(T)
if (is(T == int) || is(T == long) ||
    is(T == float) || is(T == double))
{
    /// Lower x coordinate.
    T minX = T.max;
    /// Lower y coordinate.
    T minY = T.max;
    /// Upper x coordinate.
    T maxX = -T.max;
    /// Upper y coordinate.
    T maxY = -T.max;

    /**
     * Whether this rectangle is ordered and finite.
     *
     * Returns: `true` for ordered, finite bounds (including points).
     */
    bool isValid() const
    {
        if (!(minX <= maxX && minY <= maxY))
            return false;

        static if (isFloatingPoint!T)
            return isFinite(minX) && isFinite(minY) &&
                isFinite(maxX) && isFinite(maxY);
        else
            return true;
    }

    /**
     * Test closed-rectangle overlap, including edges and corners.
     *
     * Params:
     *   other = Second rectangle.
     *
     * Returns: `true` only when both rectangles are valid and overlap.
     */
    bool intersects(Bounds2 other) const
    {
        return isValid() && other.isValid() &&
            minX <= other.maxX && maxX >= other.minX &&
            minY <= other.maxY && maxY >= other.minY;
    }
}

/**
 * Dynamically balanced R-tree with unique caller-assigned identifiers.
 *
 * The tree owns copied rectangles, IDs, and its internal storage only. It does
 * not own application geometry. Its value type is deliberately noncopyable;
 * do not mutate the tree while a search visitor is executing. No concurrency
 * or out-of-memory rollback guarantee is implied.
 *
 * The query traversal itself does not allocate result storage. A visitor
 * returns `true` to continue or `false` to stop, and the search result counts
 * invocations, including the invocation that requests termination. Query order
 * is unspecified. Operations returning `false` because of invalid bounds,
 * duplicate IDs or missing IDs leave the logical index unchanged.
 *
 * Params:
 *   T = `int`, `long`, `float` or `double` coordinate type.
 *   Id = Unsigned `uint` or `ulong` caller identity type.
 *   MaxEntries = Maximum entries per node (4..64, default 16).
 *
 * Examples:
 * ---
 * import spatial_index.rtreex : RTreeX, Bounds2;
 *
 * RTreeX!(double, ulong) tree;
 * alias Box = Bounds2!double;
 * assert(tree.insert(42, Box(0, 0, 2, 2)));
 *
 * ulong found;
 * auto visits = tree.search(Box(1, 1, 3, 3), (ulong id) {
 *     found = id;
 *     return true;
 * });
 * assert(visits == 1 && found == 42);
 * assert(tree.update(42, Box(5, 5, 6, 6)));
 * assert(tree.remove(42));
 * ---
 */
struct RTreeX(T, Id = ulong, size_t MaxEntries = 16)
if (is(T == int) || is(T == long) ||
    is(T == float) || is(T == double))
{
    static assert(is(Id == uint) || is(Id == ulong),
        "RTreeX M2 supports uint/ulong IDs");
    static assert(MaxEntries >= 4 && MaxEntries <= 64,
        "RTreeX node capacity must be in 4..64");

    alias Box = Bounds2!T;
    private enum size_t none = size_t.max;
    private enum size_t minimum = MaxEntries / 2;

    private struct Entry
    {
        Box box;
        Id id;
        size_t child;
    }

    private struct Node
    {
        bool leaf;
        size_t count;
        Entry[MaxEntries + 1] entries;
    }

    /**
     * One copied rectangle and its stable, caller-owned identifier.
     *
     * This is a value-only transfer record; the tree never retains the
     * caller's Item array. It does not take ownership of application geometry.
     */
    struct Item
    {
        /// Caller-supplied unique ID.
        Id id;
        /// Finite, ordered rectangle to index.
        Box bounds;
    }

    private Node[] _nodes;
    private size_t[] _free;
    private size_t _root = none;
    private size_t _size;
    private Box[Id] _boxes;

    // A bitwise/postblit copy would alias mutable backing arrays and the
    // associative lookup table. Disable copying until a deep-clone contract
    // is explicitly designed.
    @disable this(this);

    /// Number of indexed IDs.
    @property size_t length() const
    {
        return _size;
    }

    /// Whether this index contains no entries.
    @property bool empty() const
    {
        return _size == 0;
    }

    /**
     * Read the copied rectangle for an ID.
     *
     * Params:
     *   id = Caller-assigned ID.
     *   bounds = Receives the stored rectangle if present.
     *
     * Returns: `true` for a present ID, otherwise `false` (out unchanged).
     */
    bool tryGetBounds(Id id, ref Box bounds) const
    {
        auto found = id in _boxes;
        if (found is null)
            return false;
        bounds = *found;
        return true;
    }

    /**
     * Insert a uniquely identified rectangle.
     *
     * Params:
     *   id = Unique caller-supplied identity.
     *   bounds = Valid, finite rectangle (zero-area permitted).
     *
     * Returns: `false` if `id` exists or `bounds` is invalid; otherwise
     *   `true`. Rejected calls leave existing data unchanged.
     */
    bool insert(Id id, Box bounds)
    {
        if (!bounds.isValid() || (id in _boxes) !is null)
            return false;

        _insertEntry(Entry(bounds, id, none));
        _boxes[id] = bounds;
        ++_size;
        return true;
    }


    /**
     * Replace all indexed entries with a packed, spatially organized tree.
     *
     * The caller's Item array remains unchanged and can be discarded after
     * the call. This method accepts any number of entries, including zero,
     * and rebuilds the tree in O(n log n) expected sorting time rather than
     * repeatedly calling insert. A two-axis, overlap-minimizing top-down
     * (OMT-inspired) grouping heuristic is applied at every tree level.
     *
     * All input is validated before the current tree is changed. The method
     * returns false for invalid boxes or duplicate IDs and leaves the prior
     * tree untouched in that case. Memory allocation failures can still
     * throw; no out-of-memory rollback is promised by the public API.
     *
     * Params:
     *   items = Caller-owned items with unique IDs and valid rectangles.
     *
     * Returns: true on success, false for duplicate IDs or invalid bounds.
     *
     * Examples:
     * ---
     * RTreeX!(double, uint) tree;
     * alias B = Bounds2!double;
     * RTreeX!(double, uint).Item[] items = [
     *     { 11, B(0, 0, 5, 5) },
     *     { 12, B(8, 8, 9, 9) }
     * ];
     * assert(tree.bulkLoad(items));
     * assert(tree.length == 2);
     * assert(tree.search(B(1, 1, 2, 2), (uint id) {
     *     return true;
     * }) == 1);
     * ---
     */
    bool bulkLoad(scope const(Item)[] items)
    {
        // Build in detached storage, so rejected input cannot destroy the
        // previous tree. The new pool/map are adopted only on success.
        RTreeX!(T, Id, MaxEntries) candidate;
        Entry[] level;
        level.length = items.length;

        foreach (i, item; items)
        {
            if (!item.bounds.isValid() ||
                (item.id in candidate._boxes) !is null)
                return false;

            candidate._boxes[item.id] = item.bounds;
            level[i] = Entry(item.bounds, item.id, none);
        }

        candidate._size = items.length;
        if (level.length != 0)
        {
            bool leaves = true;
            while (level.length > MaxEntries)
            {
                level = candidate._buildLevel(level, leaves);
                leaves = false;
            }

            // The final root is exempt from the minimum occupancy rule.
            const size_t root = candidate._allocateNode(leaves);
            foreach (i, item; level)
                candidate._nodes[root].entries[i] = item;
            candidate._nodes[root].count = level.length;
            candidate._root = root;
        }

        _nodes = candidate._nodes;
        _free = candidate._free;
        _boxes = candidate._boxes;
        _root = candidate._root;
        _size = candidate._size;
        return true;
    }

    // OMT-inspired grouping of one tree level: sort by minX into spatial
    // columns sized by the number of target groups, then sort each column by
    // minY and pack balanced groups. Every non-root group is >= minimum.
    private Entry[] _buildLevel(Entry[] level, bool leaves)
    {
        import std.algorithm.sorting : sort;

        const size_t groups = (level.length - 1) / MaxEntries + 1;
        assert(groups >= 2);
        const size_t smallGroup = level.length / groups;
        const size_t largerGroups = level.length % groups;
        assert(smallGroup >= minimum);

        size_t columns = 1;
        while (columns < groups / columns ||
               (columns * columns < groups))
            ++columns;

        // Equal-size columns by *number of groups*. This prevents tiny
        // underfull leaf groups at slice boundaries.
        sort!((a, b) => _bulkLess(a, b, 0))(level);

        Entry[] parents;
        parents.length = groups;
        size_t first = 0;
        size_t nextGroup = 0;
        foreach (column; 0 .. columns)
        {
            const size_t columnGroups = groups / columns +
                (column < groups % columns ? 1 : 0);
            size_t columnLength = columnGroups * smallGroup;
            if (nextGroup < largerGroups)
            {
                const size_t countLarger = largerGroups - nextGroup;
                columnLength += countLarger < columnGroups ?
                    countLarger : columnGroups;
            }

            sort!((a, b) => _bulkLess(a, b, 1))(
                level[first .. first + columnLength]);

            size_t offset = first;
            foreach (g; 0 .. columnGroups)
            {
                const size_t groupLength = smallGroup +
                    (nextGroup < largerGroups ? 1 : 0);
                const size_t nodeIndex = _allocateNode(leaves);
                foreach (k; 0 .. groupLength)
                    _nodes[nodeIndex].entries[k] = level[offset + k];
                _nodes[nodeIndex].count = groupLength;
                parents[nextGroup] = Entry(_nodeBounds(nodeIndex),
                                           Id.init, nodeIndex);
                offset += groupLength;
                ++nextGroup;
            }
            first += columnLength;
            assert(offset == first);
        }
        assert(first == level.length && nextGroup == groups);
        return parents;
    }

    // Deterministic ordering even for equal minimum coordinates; internal
    // entries with Id.init are distinguished by their child pool index.
    private static bool _bulkLess(Entry a, Entry b, size_t axis)
    {
        const T ak = axis == 0 ? a.box.minX : a.box.minY;
        const T bk = axis == 0 ? b.box.minX : b.box.minY;
        if (ak < bk) return true;
        if (ak > bk) return false;
        const T as = axis == 0 ? a.box.minY : a.box.minX;
        const T bs = axis == 0 ? b.box.minY : b.box.minX;
        if (as < bs) return true;
        if (as > bs) return false;
        if (a.id != b.id) return a.id < b.id;
        return a.child < b.child;
    }

    /**
     * Delete an entry by its ID.
     *
     * Returns: `true` if deleted, otherwise `false` without changing data.
     */
    bool remove(Id id)
    {
        auto found = id in _boxes;
        if (found is null)
            return false;

        const Box oldBounds = *found;
        if (!_eraseTree(id, oldBounds))
            return false;

        _boxes.remove(id);
        --_size;
        return true;
    }

    /**
     * Replace the rectangle associated with an existing ID.
     *
     * Params:
     *   id = Existing ID.
     *   bounds = New valid, finite bounds.
     *
     * Returns: `true` on success, including an identical update; otherwise
     *   `false` and no logical change.
     */
    bool update(Id id, Box bounds)
    {
        if (!bounds.isValid())
            return false;
        auto found = id in _boxes;
        if (found is null)
            return false;

        const Box previous = *found;
        if (previous == bounds)
            return true;
        if (!_eraseTree(id, previous))
            return false;

        _insertEntry(Entry(bounds, id, none));
        _boxes[id] = bounds;
        return true;
    }

    /**
     * Visit all indexed rectangles intersecting `query` until stopped.
     *
     * `visitor` receives the caller ID, returns `true` to continue, or
     * returns `false` to terminate early. Neither the visitor nor another
     * thread may mutate the tree during a search.
     *
     * Params:
     *   F = Callable visitor type (deduced).
     *   query = Closed query rectangle.
     *   visitor = Callable `bool(Id)`; may capture external state.
     *
     * Returns: Number of visitor calls; zero for empty/invalid queries.
     */
    size_t search(F)(Box query, F visitor) const
    {
        if (_root == none || !query.isValid())
            return 0;

        size_t count = 0;
        _searchNode(_root, query, visitor, count);
        return count;
    }

    /// Discard all entries, including internal node storage.
    void clear()
    {
        _nodes = null;
        _free = null;
        _boxes = null;
        _root = none;
        _size = 0;
    }

    private bool _searchNode(F)(size_t index, Box query,
                                ref F visitor, ref size_t count) const
    {
        // Search is read-only: no node-array reallocation while traversing.
        const(Node)* node = &_nodes[index];
        foreach (i; 0 .. node.count)
        {
            const Entry e = node.entries[i];
            if (!e.box.intersects(query))
                continue;
            if (node.leaf)
            {
                ++count;
                if (!visitor(e.id))
                    return false;
            }
            else if (!_searchNode(e.child, query, visitor, count))
                return false;
        }
        return true;
    }

    private size_t _allocateNode(bool leaf)
    {
        size_t index;
        if (_free.length != 0)
        {
            index = _free[$ - 1];
            _free.length = _free.length - 1;
            _nodes[index] = Node.init;
        }
        else
        {
            index = _nodes.length;
            _nodes ~= Node.init;
        }
        _nodes[index].leaf = leaf;
        return index;
    }

    private void _releaseNode(size_t index)
    {
        _nodes[index] = Node.init;
        _free ~= index;
    }

    private static Box _unite(Box a, Box b)
    {
        if (b.minX < a.minX) a.minX = b.minX;
        if (b.minY < a.minY) a.minY = b.minY;
        if (b.maxX > a.maxX) a.maxX = b.maxX;
        if (b.maxY > a.maxY) a.maxY = b.maxY;
        return a;
    }

    private static real _area(Box b)
    {
        return (cast(real) b.maxX - cast(real) b.minX) *
            (cast(real) b.maxY - cast(real) b.minY);
    }

    private static real _margin(Box b)
    {
        return 2 * ((cast(real) b.maxX - cast(real) b.minX) +
            (cast(real) b.maxY - cast(real) b.minY));
    }

    private static real _overlap(Box a, Box b)
    {
        const T loX = a.minX > b.minX ? a.minX : b.minX;
        const T hiX = a.maxX < b.maxX ? a.maxX : b.maxX;
        const T loY = a.minY > b.minY ? a.minY : b.minY;
        const T hiY = a.maxY < b.maxY ? a.maxY : b.maxY;
        if (loX >= hiX || loY >= hiY)
            return 0;
        return (cast(real) hiX - cast(real) loX) *
            (cast(real) hiY - cast(real) loY);
    }

    private static Box _rangeBounds(const(Entry)[] entries,
                                     size_t start, size_t finish)
    {
        Box result = entries[start].box;
        foreach (i; start + 1 .. finish)
            result = _unite(result, entries[i].box);
        return result;
    }

    private Box _nodeBounds(size_t index) const
    {
        return _rangeBounds(_nodes[index].entries[],
                            0, _nodes[index].count);
    }

    private size_t _chooseChild(size_t index, Box incoming) const
    {
        const(Node)* node = &_nodes[index];
        const bool leafChildren = _nodes[node.entries[0].child].leaf;
        size_t best = 0;
        real bestOverlap = 0;
        real bestEnlargement = 0;
        real bestArea = 0;

        foreach (i; 0 .. node.count)
        {
            const Box old = node.entries[i].box;
            const Box grown = _unite(old, incoming);
            const real enlargement = _area(grown) - _area(old);
            const real area = _area(old);
            real overlapChange = 0;
            if (leafChildren)
            {
                foreach (j; 0 .. node.count)
                {
                    if (i == j) continue;
                    const Box peer = node.entries[j].box;
                    overlapChange += _overlap(grown, peer) -
                        _overlap(old, peer);
                }
            }

            if (i == 0 ||
                (leafChildren &&
                 (overlapChange < bestOverlap ||
                  (overlapChange == bestOverlap &&
                   (enlargement < bestEnlargement ||
                    (enlargement == bestEnlargement && area < bestArea))))) ||
                (!leafChildren &&
                 (enlargement < bestEnlargement ||
                  (enlargement == bestEnlargement && area < bestArea))))
            {
                best = i;
                bestOverlap = overlapChange;
                bestEnlargement = enlargement;
                bestArea = area;
            }
        }
        return best;
    }

    private static T _sortKey(Entry e, size_t axis, bool byUpper)
    {
        if (axis == 0)
            return byUpper ? e.box.maxX : e.box.minX;
        return byUpper ? e.box.maxY : e.box.minY;
    }

    private static bool _sortLess(Entry a, Entry b, size_t axis, bool byUpper)
    {
        const T ak = _sortKey(a, axis, byUpper);
        const T bk = _sortKey(b, axis, byUpper);
        if (ak < bk) return true;
        if (bk < ak) return false;
        // Deterministic tie-breaking for this in-memory node ordering.
        const T aSecondary = _sortKey(a, 1 - axis, byUpper);
        const T bSecondary = _sortKey(b, 1 - axis, byUpper);
        if (aSecondary < bSecondary) return true;
        if (bSecondary < aSecondary) return false;
        if (a.id != b.id) return a.id < b.id;
        return a.child < b.child;
    }

    // Insertion sort is cheap and allocation-free for <= 65 entries.
    private static void _sortEntries(Entry[] arr, size_t axis, bool byUpper)
    {
        foreach (i; 1 .. arr.length)
        {
            Entry value = arr[i];
            size_t j = i;
            while (j > 0 && _sortLess(value, arr[j - 1], axis, byUpper))
            {
                arr[j] = arr[j - 1];
                --j;
            }
            arr[j] = value;
        }
    }

    /**
     * Split one full node by minimizing summed margins over each axis and
     * then overlap/area over legal distributions on the selected axis.
     *
     * A successful allocation is performed before altering the original
     * node. The temporary ordered candidates live on the call stack.
     */
    private size_t _split(size_t index, Entry added)
    {
        enum size_t n = MaxEntries + 1;
        Entry[n] candidates = _nodes[index].entries;
        candidates[MaxEntries] = added;

        size_t chosenAxis = 0;
        real bestMargin = real.infinity;
        foreach (axis; 0 .. 2)
        {
            real totalMargin = 0;
            foreach (order; 0 .. 2)
            {
                Entry[n] sorted = candidates;
                _sortEntries(sorted[], axis, order == 1);
                foreach (cut; minimum .. n - minimum + 1)
                {
                    totalMargin += _margin(_rangeBounds(sorted[], 0, cut));
                    totalMargin += _margin(_rangeBounds(sorted[], cut, n));
                }
            }
            if (axis == 0 || totalMargin < bestMargin)
            {
                chosenAxis = axis;
                bestMargin = totalMargin;
            }
        }

        size_t chosenCut = minimum;
        Entry[n] chosenOrder;
        real bestOverlap = 0;
        real bestArea = 0;
        bool first = true;
        foreach (order; 0 .. 2)
        {
            Entry[n] sorted = candidates;
            _sortEntries(sorted[], chosenAxis, order == 1);
            foreach (cut; minimum .. n - minimum + 1)
            {
                const Box left = _rangeBounds(sorted[], 0, cut);
                const Box right = _rangeBounds(sorted[], cut, n);
                const real overlap = _overlap(left, right);
                const real totalArea = _area(left) + _area(right);
                if (first || overlap < bestOverlap ||
                    (overlap == bestOverlap && totalArea < bestArea))
                {
                    first = false;
                    bestOverlap = overlap;
                    bestArea = totalArea;
                    chosenCut = cut;
                    chosenOrder = sorted;
                }
            }
        }

        const bool leaf = _nodes[index].leaf;
        const size_t sibling = _allocateNode(leaf);
        _nodes[index] = Node.init;
        _nodes[index].leaf = leaf;
        foreach (i; 0 .. chosenCut)
            _nodes[index].entries[i] = chosenOrder[i];
        _nodes[index].count = chosenCut;
        foreach (i; chosenCut .. n)
            _nodes[sibling].entries[i - chosenCut] = chosenOrder[i];
        _nodes[sibling].count = n - chosenCut;
        return sibling;
    }

    // Returns a sibling on overflow; 'none' otherwise.
    private size_t _insertAt(size_t index, Entry added)
    {
        if (_nodes[index].leaf)
        {
            if (_nodes[index].count < MaxEntries)
            {
                _nodes[index].entries[_nodes[index].count++] = added;
                return none;
            }
            return _split(index, added);
        }

        const size_t chosen = _chooseChild(index, added.box);
        const size_t child = _nodes[index].entries[chosen].child;
        const size_t sibling = _insertAt(child, added);
        _nodes[index].entries[chosen].box = _nodeBounds(child);
        if (sibling == none)
            return none;

        const Entry right = Entry(_nodeBounds(sibling), Id.init, sibling);
        if (_nodes[index].count < MaxEntries)
        {
            _nodes[index].entries[_nodes[index].count++] = right;
            return none;
        }
        return _split(index, right);
    }

    private void _insertEntry(Entry entry)
    {
        if (_root == none)
        {
            _root = _allocateNode(true);
            _nodes[_root].entries[0] = entry;
            _nodes[_root].count = 1;
            return;
        }

        const size_t sibling = _insertAt(_root, entry);
        if (sibling != none)
        {
            const size_t oldRoot = _root;
            const size_t newRoot = _allocateNode(false);
            _nodes[newRoot].entries[0] =
                Entry(_nodeBounds(oldRoot), Id.init, oldRoot);
            _nodes[newRoot].entries[1] =
                Entry(_nodeBounds(sibling), Id.init, sibling);
            _nodes[newRoot].count = 2;
            _root = newRoot;
        }
    }

    private void _removeEntry(size_t index, size_t position)
    {
        for (size_t i = position + 1; i < _nodes[index].count; ++i)
            _nodes[index].entries[i - 1] = _nodes[index].entries[i];
        --_nodes[index].count;
        _nodes[index].entries[_nodes[index].count] = Entry.init;
    }

    private bool _removeAt(size_t index, Id id, Box box,
                            ref Entry[] reinsert)
    {
        if (_nodes[index].leaf)
        {
            foreach (i; 0 .. _nodes[index].count)
            {
                if (_nodes[index].entries[i].id == id)
                {
                    _removeEntry(index, i);
                    return true;
                }
            }
            return false;
        }

        size_t i = 0;
        while (i < _nodes[index].count)
        {
            if (!_nodes[index].entries[i].box.intersects(box))
            {
                ++i;
                continue;
            }
            const size_t child = _nodes[index].entries[i].child;
            if (_removeAt(child, id, box, reinsert))
            {
                if (_nodes[child].count < minimum)
                {
                    _collectAndRelease(child, reinsert);
                    _removeEntry(index, i);
                }
                else
                    _nodes[index].entries[i].box = _nodeBounds(child);
                return true;
            }
            ++i;
        }
        return false;
    }

    private void _collectAndRelease(size_t index, ref Entry[] reinsert)
    {
        const bool leaf = _nodes[index].leaf;
        const size_t count = _nodes[index].count;
        foreach (i; 0 .. count)
        {
            const Entry e = _nodes[index].entries[i];
            if (leaf)
                reinsert ~= e;
            else
                _collectAndRelease(e.child, reinsert);
        }
        _releaseNode(index);
    }

    private bool _eraseTree(Id id, Box bounds)
    {
        if (_root == none)
            return false;

        Entry[] orphaned;
        if (!_removeAt(_root, id, bounds, orphaned))
            return false;

        // The root is exempt from the normal minimum occupancy rule.
        if (_nodes[_root].count == 0)
        {
            _releaseNode(_root);
            _root = none;
        }
        else
        {
            while (!_nodes[_root].leaf && _nodes[_root].count == 1)
            {
                const size_t oldRoot = _root;
                _root = _nodes[oldRoot].entries[0].child;
                _releaseNode(oldRoot);
            }
        }

        foreach (e; orphaned)
            _insertEntry(e);
        return true;
    }

    // Debug / regression oracle for the node structure. Not an exported API.
    private bool _checkNode(size_t index, bool isRoot, ref size_t seen) const
    {
        if (index >= _nodes.length)
            return false;
        const(Node)* node = &_nodes[index];
        if (node.count == 0 || node.count > MaxEntries)
            return false;
        if (!isRoot && node.count < minimum)
            return false;
        if (isRoot && !node.leaf && node.count < 2)
            return false;
        foreach (i; 0 .. node.count)
        {
            const Entry e = node.entries[i];
            if (!e.box.isValid())
                return false;
            if (node.leaf)
            {
                auto found = e.id in _boxes;
                if (found is null || *found != e.box)
                    return false;
                ++seen;
            }
            else
            {
                if (e.child >= _nodes.length ||
                    e.box != _nodeBounds(e.child) ||
                    !_checkNode(e.child, false, seen))
                    return false;
            }
        }
        return true;
    }

    private bool _checkInvariants() const
    {
        if (_root == none)
            return _size == 0 && _boxes.length == 0;
        size_t seen = 0;
        return _checkNode(_root, true, seen) &&
            seen == _size && _boxes.length == _size;
    }
}

unittest
{
    alias Box = Bounds2!double;
    assert(Box(0, 0, 1, 1).intersects(Box(1, 1, 2, 2)));
    assert(Box(1, 1, 1, 1).isValid());
    assert(!Box.init.isValid());
    assert(Box(0, 0, 0, 0).isValid());
    assert(!Box(1, 1, 0, 0).isValid());
    assert(!Box(double.nan, 0, 1, 1).isValid());
    assert(!Box(double.infinity, 0, 1, 1).isValid());

    RTreeX!(double, ulong, 4) tree;
    assert(tree.empty);
    assert(!tree.insert(1, Box(10, 0, 1, 2)));
    assert(!tree.insert(1, Box(double.infinity, 0, 1, 2)));
    assert(tree.insert(1, Box(0, 0, 1, 1)));
    assert(!tree.update(1, Box(double.nan, 0, 1, 2)));
    assert(!tree.insert(1, Box(2, 2, 3, 3)));
    assert(tree.insert(0, Box(1, 1, 1, 1)));
    assert(tree._checkInvariants());

    size_t found;
    assert(tree.search(Box(1, 1, 1, 1), (ulong id) {
        ++found;
        return true;
    }) == 2);
    assert(found == 2);

    assert(tree.search(Box(-1, -1, 4, 4), (ulong id) {
        return false;
    }) == 1);
    assert(tree.update(1, Box(10, 10, 11, 11)));
    assert(tree.search(Box(0, 0, 0, 0), (ulong id) {
        return true;
    }) == 0);
    assert(tree._checkInvariants());

    Box value;
    assert(tree.tryGetBounds(1, value));
    assert(value == Box(10, 10, 11, 11));
    assert(!tree.update(987, Box(0, 0, 1, 1)));
    Box unchanged = Box(7, 7, 9, 9);
    assert(!tree.tryGetBounds(987, unchanged));
    assert(unchanged == Box(7, 7, 9, 9));
    assert(!tree.remove(987));
    assert(tree.remove(1));
    assert(tree.remove(0));
    assert(tree.empty && tree._checkInvariants());
    tree.clear();
    assert(tree._checkInvariants());
}

unittest
{
    // Exercise overflow, splits, underflow, root shrink and slot recycling.
    alias Box = Bounds2!int;
    RTreeX!(int, uint, 8) tree;
    Box[uint] reference;

    foreach (i; 0u .. 400u)
    {
        const int x = cast(int) (i % 25u) * 3;
        const int y = cast(int) (i / 25u) * 5;
        const Box box = Box(x, y, x + 9, y + 3);
        assert(tree.insert(i, box));
        reference[i] = box;
    }
    assert(tree.length == reference.length);
    assert(tree._checkInvariants());

    foreach (i; 0u .. 400u)
    {
        if (i % 3u == 0)
        {
            const Box box = Box(1000 + cast(int) i, -5,
                                1001 + cast(int) i, 6);
            assert(tree.update(i, box));
            reference[i] = box;
        }
        else if (i % 3u == 1)
        {
            assert(tree.remove(i));
            reference.remove(i);
        }
        if (i % 20u == 0)
            assert(tree._checkInvariants());
    }
    assert(tree._checkInvariants());

    foreach (q; 0 .. 140)
    {
        const Box query = Box(q * 7 - 3, -7, q * 7 + 14, 100);
        size_t expected = 0;
        foreach (id, box; reference)
            if (box.intersects(query)) ++expected;

        bool[uint] hits;
        const size_t actual = tree.search(query, (uint id) {
            assert((id in hits) is null);
            hits[id] = true;
            auto box = id in reference;
            assert(box !is null && (*box).intersects(query));
            return true;
        });
        assert(actual == expected);
    }

    foreach (id; 0u .. 400u)
        if ((id in reference) !is null)
            assert(tree.remove(id));
    assert(tree.empty && tree._checkInvariants());
}


unittest
{
    // Deterministic mixed-operation differential test. The reference map
    // deliberately does not reuse the tree's traversal or split algorithms.
    alias Box = Bounds2!int;
    RTreeX!(int, ulong, 4) tree;
    Box[ulong] reference;
    uint state = 0xC001D00Du;

    uint nextRandom()
    {
        state = state * 1664525u + 1013904223u;
        return state;
    }

    foreach (step; 0 .. 6_000)
    {
        const ulong id = cast(ulong) (nextRandom() % 170u);
        const uint operation = nextRandom() % 5u;
        const int x = cast(int) (nextRandom() % 350u) - 175;
        const int y = cast(int) (nextRandom() % 350u) - 175;
        // Mix points, long thin rectangles, and ordinary boxes.
        const int dx = id % 11 == 0 ? 450 : cast(int) (nextRandom() % 15u);
        const int dy = id % 7 == 0 ? 0 : cast(int) (nextRandom() % 15u);
        const Box bounds = Box(x, y, x + dx, y + dy);

        if (operation == 0)
        {
            const bool present = (id in reference) !is null;
            assert(tree.insert(id, bounds) == !present);
            if (!present) reference[id] = bounds;
        }
        else if (operation == 1)
        {
            const bool present = (id in reference) !is null;
            assert(tree.remove(id) == present);
            if (present) reference.remove(id);
        }
        else if (operation == 2)
        {
            const bool present = (id in reference) !is null;
            assert(tree.update(id, bounds) == present);
            if (present) reference[id] = bounds;
        }
        else
        {
            const Box query = Box(x, y, x + 30, y + 30);
            size_t expected = 0;
            foreach (candidateId, candidateBounds; reference)
                if (candidateBounds.intersects(query)) ++expected;

            bool[ulong] seen;
            const size_t actual = tree.search(query, (ulong candidateId) {
                assert((candidateId in seen) is null);
                seen[candidateId] = true;
                auto known = candidateId in reference;
                assert(known !is null && (*known).intersects(query));
                return true;
            });
            assert(actual == expected);

            if (expected != 0)
                assert(tree.search(query, (ulong candidateId) {
                    return false;
                }) == 1);
        }

        if (step % 17 == 0)
        {
            assert(tree._checkInvariants());
            assert(tree.length == reference.length);
        }
    }
    assert(tree._checkInvariants());
    assert(tree.length == reference.length);
}

// M1 compile-negative ownership and template-domain contracts.
static assert(!__traits(compiles, {
    RTreeX!(double, ulong) original;
    RTreeX!(double, ulong) accidentalCopy = original;
}));
static assert(!__traits(compiles, RTreeX!(double, long).init));
static assert(!__traits(compiles, Bounds2!string.init));


unittest
{
    // M3: empty replacement, validity and uniqueness are transactional.
    alias Index = RTreeX!(double, uint, 4);
    alias Box = Bounds2!double;
    Index tree;
    assert(tree.insert(99, Box(1, 1, 2, 2)));

    Index.Item[] duplicates = [
        Index.Item(3, Box(0, 0, 1, 1)),
        Index.Item(3, Box(3, 3, 4, 4))
    ];
    assert(!tree.bulkLoad(duplicates));
    assert(tree.length == 1);
    Box stored;
    assert(tree.tryGetBounds(99, stored) && stored == Box(1, 1, 2, 2));

    Index.Item[] invalid = [
        Index.Item(7, Box(1, 1, 1, 1)),
        Index.Item(8, Box(double.nan, 0, 1, 2))
    ];
    assert(!tree.bulkLoad(invalid));
    assert(tree.length == 1 && tree._checkInvariants());

    Index.Item[] entries = [
        Index.Item(2, Box(0, 0, 10, 10)),
        Index.Item(0, Box(10, 10, 12, 12)),
        Index.Item(8, Box(-2, -2, -2, -2)),
        Index.Item(7, Box(4, 4, 5, 5)),
        Index.Item(9, Box(100, 100, 200, 200))
    ];
    assert(tree.bulkLoad(entries));
    assert(tree.length == entries.length && tree._checkInvariants());
    assert(!tree.tryGetBounds(99, stored));
    assert(tree.search(Box(10, 10, 10, 10), (uint id) {
        return true;
    }) == 2);
    assert(tree.update(7, Box(11, 11, 11, 11)));
    assert(tree.remove(0));
    assert(tree._checkInvariants());

    // Bulk loading must copy values and never retain caller memory.
    entries[0] = Index.Item(999, Box(9, 9, 9, 9));
    assert(tree.tryGetBounds(2, stored) && stored == Box(0, 0, 10, 10));

    assert(tree.bulkLoad(cast(const(Index.Item)[]) null));
    assert(tree.empty && tree._checkInvariants());
}

unittest
{
    // M3: packed hierarchy versus independent linear-scan oracle.
    // Covers all sizes across multiple full/partial levels and edit sequences.
    alias Index = RTreeX!(int, ulong, 16);
    alias Box = Bounds2!int;
    foreach (n; [1, 15, 16, 17, 31, 32, 33, 255, 256, 257, 1024, 4097])
    {
        Index tree;
        Index.Item[] items;
        items.length = n;
        foreach (i; 0 .. n)
        {
            const int x = cast(int)(i % 47) * 5 - 115;
            const int y = cast(int)(i / 47) * 3 - 115;
            // A mixture of points, horizontal lines, and overlapping areas.
            const int dx = i % 13 == 0 ? 300 : cast(int)(i % 11);
            const int dy = i % 7 == 0 ? 0 : cast(int)(i % 17);
            items[i] = Index.Item(cast(ulong)i, Box(x, y, x + dx, y + dy));
        }
        assert(tree.bulkLoad(items));
        assert(tree.length == n && tree._checkInvariants());

        foreach (q; 0 .. 50)
        {
            const Box query = Box(q * 11 - 170, q * 3 - 145,
                                  q * 11 - 150, q * 3 - 100);
            size_t expected = 0;
            foreach (item; items)
                if (item.bounds.intersects(query)) ++expected;

            bool[ulong] found;
            auto count = tree.search(query, (ulong id) {
                assert((id in found) is null);
                found[id] = true;
                assert(items[cast(size_t) id].bounds.intersects(query));
                return true;
            });
            assert(count == expected);
        }

        if (n > 16)
        {
            foreach (i; 0 .. n)
            {
                if (i % 3 == 0)
                    assert(tree.remove(cast(ulong) i));
                else if (i % 3 == 1)
                    assert(tree.update(cast(ulong) i,
                        Box(2000, cast(int) i, 2005, cast(int) i + 1)));
            }
            assert(tree._checkInvariants());
        }
        assert(tree.bulkLoad(items));
        assert(tree.length == n && tree._checkInvariants());
    }
}
