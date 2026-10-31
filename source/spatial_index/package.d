/**
 * Reusable spatial indexes for D.
 *
 * The first implementation is $(D RTreeX), a dynamic index of copied
 * two-dimensional bounding boxes and caller-owned IDs. The package carries
 * no OSM or coordinate reference system assumptions.
 *
 * Examples:
 * ---
 * import spatial_index;
 * RTreeX!(double, ulong) tree;
 * assert(tree.insert(7, Bounds2!double(0, 0, 1, 1)));
 * ---
 */
module spatial_index;

public import spatial_index.rtreex : Bounds2, RTreeX;
