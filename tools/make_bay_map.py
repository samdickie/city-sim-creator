#!/usr/bin/env python3
"""
Make the game's map from real US heights: Menlo Park and the Bay, on the San
Francisco Peninsula (the real Silicon Valley), by default.

Where the heights come from
    AWS's free "Terrain Tiles" (https://registry.opendata.aws/terrain-tiles/),
    built from USGS 3DEP and NOAA data: no sign-up. The tiles it downloads are
    kept in map/.terrain_cache (git-ignored), so running it again is quick.

How to run (from the project folder)
    python3 tools/make_bay_map.py

What it makes
    map/menlo_park_map.json  the map the game loads (height + sea for every tile)
    map/preview.png          a picture of the map, to check it

Needs Pillow (pip install pillow) to read the tiles. Run with --help to make a
different place (--centre LAT LON, --size WIDTH HEIGHT in metres).
"""

import argparse
import io
import json
import math
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_common import find_sea, save   # (the sea rule and the map file format)

try:
    from PIL import Image
except ImportError:
    sys.exit("This needs Pillow to read the height tiles: pip install pillow")

# The game's map since Nov 2026: Menlo Park, East Palo Alto and the Bay, with
# the Dumbarton crossing (about 1.1 km of water) to the far shore at the top
# right, for bridges. 9 km x 8 km. Framed so the dev tools' town (tiles 34-95,
# 31-108) is all on land.
MENLO_PARK_CENTRE = (37.4785, -122.1409)
MENLO_PARK_SIZE = (9000.0, 8000.0)
# The map before that (map/palo_alto_map.json): downtown Palo Alto and the edge
# of Stanford, the Baylands and the open Bay. 7 km x 6.5 km.
PALO_ALTO_CENTRE = (37.44924, -122.1305)
PALO_ALTO_SIZE = (7000.0, 6500.0)
ZOOM = 13                                    # about 15 m a pixel here
TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
CREDITS = ("Heights: USGS 3DEP and NOAA, via the AWS Terrain Tiles open data set "
           "(registry.opendata.aws/terrain-tiles)")


def to_pixel(lat, lon):
    # Web Mercator pixel (at ZOOM) for a latitude and longitude.
    n = 2 ** ZOOM * 256
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.log(math.tan(math.radians(lat)) + 1.0 / math.cos(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


class Heights:
    """Heights in metres from the terrain tiles, fetched (and cached) as needed."""

    def __init__(self, cache):
        self.cache = cache
        self.tiles = {}
        os.makedirs(cache, exist_ok=True)

    def tile(self, tx, ty):
        key = (tx, ty)
        if key not in self.tiles:
            path = os.path.join(self.cache, f"{ZOOM}_{tx}_{ty}.png")
            if not os.path.exists(path):
                url = TILE_URL.format(z=ZOOM, x=tx, y=ty)
                print(f"  fetching {url}")
                with urllib.request.urlopen(url, timeout=60) as r:
                    data = r.read()
                with open(path, "wb") as fh:
                    fh.write(data)
            img = Image.open(path).convert("RGB")
            self.tiles[key] = img.load()
        return self.tiles[key]

    def at_pixel(self, px, py):
        # "Terrarium" encoding: (R x 256 + G + B / 256) - 32768 metres.
        tx, ty = int(px // 256), int(py // 256)
        r, g, b = self.tile(tx, ty)[int(px % 256), int(py % 256)]
        return r * 256.0 + g + b / 256.0 - 32768.0

    def at(self, lat, lon):
        # Bilinear between the four nearest pixels.
        px, py = to_pixel(lat, lon)
        px -= 0.5
        py -= 0.5
        x0, y0 = math.floor(px), math.floor(py)
        fx, fy = px - x0, py - y0
        h00 = self.at_pixel(x0, y0)
        h10 = self.at_pixel(x0 + 1, y0)
        h01 = self.at_pixel(x0, y0 + 1)
        h11 = self.at_pixel(x0 + 1, y0 + 1)
        return (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy


def sample_grid(source, centre, size, cell):
    # Each tile's height is the average of 3 x 3 points across it (row 0 = north).
    lat0, lon0 = centre
    m_per_lat = 110540.0
    m_per_lon = 111320.0 * math.cos(math.radians(lat0))
    width = round(size[0] / cell)
    height = round(size[1] / cell)
    heights = []
    for r in range(height):
        for c in range(width):
            total = 0.0
            for sy in (-1, 0, 1):
                for sx in (-1, 0, 1):
                    north = size[1] / 2.0 - (r + 0.5 + sy / 3.0) * cell
                    east = -size[0] / 2.0 + (c + 0.5 + sx / 3.0) * cell
                    total += source.at(lat0 + north / m_per_lat, lon0 + east / m_per_lon)
            heights.append(total / 9.0)
    return width, height, heights


def smooth_sea(w, h, sea, passes=2):
    # The salt marshes come out as speckles of sea: let each tile follow most of
    # the 3 x 3 round it (twice), then keep only sea joined to the map edge.
    for _ in range(passes):
        out = list(sea)
        for r in range(h):
            for c in range(w):
                n = 0
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        rr, cc = min(max(r + dr, 0), h - 1), min(max(c + dc, 0), w - 1)
                        n += sea[rr * w + cc]
                out[r * w + c] = 1 if n >= 5 else 0
        sea = out
    fake = [0.0 if s else 1.0 for s in sea]       # (find_sea keeps what's joined to the edge)
    return find_sea(w, h, fake, 0.5)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.join(here, "..")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--centre", nargs=2, type=float, metavar=("LAT", "LON"), default=MENLO_PARK_CENTRE)
    p.add_argument("--size", nargs=2, type=float, metavar=("WIDTH", "HEIGHT"), default=MENLO_PARK_SIZE,
                   help="metres east-west and north-south (default 7000 6500)")
    p.add_argument("--cell", type=float, default=50.0, help="metres per game tile (default 50)")
    p.add_argument("--sea-level", type=float, default=0.5,
                   help="ground at or below this height, joined to the map edge, is sea (default 0.5 m)")
    p.add_argument("--name", default="Menlo Park")
    p.add_argument("--out", default=os.path.join(root, "map", "menlo_park_map.json"))
    args = p.parse_args()

    source = Heights(os.path.join(root, "map", ".terrain_cache"))
    w, h, heights = sample_grid(source, tuple(args.centre), tuple(args.size), args.cell)
    sea = smooth_sea(w, h, find_sea(w, h, heights, args.sea_level))
    # Below the sea, the heights are the sea bed: the game treats sea tiles as water, so keep them.
    preview = save(args.out, args.name, w, h, args.cell, heights, sea, credits=CREDITS)
    with open(args.out) as fh:
        data = json.load(fh)
    data["latlon_centre"] = list(args.centre)
    data["size_m"] = list(args.size)
    with open(args.out, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    land = [v for v, s in zip(heights, sea) if not s]
    print(f"Wrote {args.out}: {w} x {h} tiles of {args.cell:.0f} m. Preview: {preview}")
    print(f"Sea: {sum(sea) * 100 // len(sea)}% of tiles   Highest land: {max(land) if land else 0:.0f} m")


if __name__ == "__main__":
    main()
