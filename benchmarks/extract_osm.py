#!/usr/bin/env python3
"""Extract independent 2D bounding boxes from a local OSM XML / .bz2 / .gz file.

Only benchmark fixtures: node and way bounding boxes; relations omitted.
Coordinates are WGS84 lon/lat as source-provided (no projection), and must
not be used as metric distances. The output records sequential benchmark IDs,
not authoritative OSM IDs. Preserve source/provenance separately.
"""
import argparse
import bz2
import csv
import gzip
import xml.etree.ElementTree as ET
from pathlib import Path


def open_xml(path: Path):
    if path.suffix == ".bz2":
        return bz2.open(path, "rb")
    if path.suffix == ".gz":
        return gzip.open(path, "rb")
    return path.open("rb")


def convert(source: Path, target: Path, limit: int | None = None) -> tuple[int, int]:
    nodes: dict[str, tuple[float, float]] = {}
    node_rows = 0
    way_rows = 0

    with open_xml(source) as source_file, target.open(
        "w", encoding="utf-8", newline=""
    ) as output:
        output.write("# RTreeX benchmark corpus: WGS84 lon/lat bounding boxes\n")
        output.write(f"# OSM source file: {source.name}\n")
        output.write("# format: sequential_id,minX,minY,maxX,maxY\n")
        writer = csv.writer(output)
        identifier = 0
        way_refs: list[str] = []
        for event, element in ET.iterparse(source_file, events=("start", "end")):
            if event == "start":
                if element.tag == "way":
                    way_refs = []
                continue
            if element.tag == "node":
                osm_id = element.attrib.get("id")
                if osm_id is not None and "lon" in element.attrib:
                    x, y = float(element.attrib["lon"]), float(element.attrib["lat"])
                    nodes[osm_id] = (x, y)
                    if limit is None or identifier < limit:
                        writer.writerow((identifier, x, y, x, y))
                        identifier += 1
                        node_rows += 1
            elif element.tag == "nd":
                ref = element.attrib.get("ref")
                if ref:
                    way_refs.append(ref)
            elif element.tag == "way":
                coords = [nodes[ref] for ref in way_refs if ref in nodes]
                if coords and (limit is None or identifier < limit):
                    xs, ys = zip(*coords)
                    writer.writerow((identifier, min(xs), min(ys), max(xs), max(ys)))
                    identifier += 1
                    way_rows += 1
                way_refs = []
            element.clear()

    return node_rows, way_rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="OSM XML, .osm.gz or .osm.bz2")
    parser.add_argument("output", type=Path, help="Output CSV of bounding boxes")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()
    if args.limit is not None and args.limit < 0:
        parser.error("--limit must not be negative")
    nodes, ways = convert(args.input, args.output, args.limit)
    print(f"extracted {nodes} node boxes and {ways} way boxes")
