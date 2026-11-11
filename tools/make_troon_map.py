#!/usr/bin/env python3
"""
Turn Ordnance Survey "OS Terrain 50" height data into the game's map file.

What you need
    The free OS Terrain 50 download in "ASCII Grid" format, from
    https://osdatahub.os.uk/data/downloads/open/Terrain50
    (no sign-up). You can point this script at the downloaded zip as-is.

How to run (from the troon-city folder)
    python3 tools/make_troon_map.py ~/Downloads/terr50_gagg_gb.zip

What it makes
    map/troon_map.json   the map the game loads (height + sea for every tile)
    map/preview.png      a picture of the map, to check it looks like Troon

Only uses Python's built-in libraries, so there is nothing extra to install.
Run with --help for options (a different box, tile size, sea level).
"""

import argparse
import io
import json
import math
import os
import struct
import sys
import zipfile
import zlib
from collections import deque

# British National Grid box around Troon, in metres (7 km x 6.5 km).
# Covers the harbour, the town centre, Barassie, Royal Troon and the hills to the east.
TROON_BOX = (230300, 628200, 237300, 634700)

CREDITS = ("Contains OS data © Crown copyright and database right "
           "(OS Terrain 50, Open Government Licence)")


# ---------------------------------------------------------------- reading tiles

class Tile:
    """One OS Terrain 50 tile: a grid of heights with its position."""

    def __init__(self, name, text):
        self.name = name
        lines = text.splitlines()
        header = {}
        body_start = 0
        for n, line in enumerate(lines):
            parts = line.split()
            if len(parts) == 2 and parts[0][0].isalpha():
                header[parts[0].lower()] = float(parts[1])
            else:
                body_start = n
                break
        self.ncols = int(header["ncols"])
        self.nrows = int(header["nrows"])
        self.cell = header["cellsize"]
        if "xllcorner" in header:
            self.xll, self.yll = header["xllcorner"], header["yllcorner"]
        else:  # some files give the centre of the corner cell instead
            self.xll = header["xllcenter"] - self.cell / 2
            self.yll = header["yllcenter"] - self.cell / 2
        self.nodata = header.get("nodata_value", -9999.0)
        self._lines = lines[body_start:]
        self._rows = None

    @property
    def extent(self):
        return (self.xll, self.yll,
                self.xll + self.ncols * self.cell, self.yll + self.nrows * self.cell)

    def overlaps(self, box):
        x0, y0, x1, y1 = self.extent
        return x0 < box[2] and x1 > box[0] and y0 < box[3] and y1 > box[1]

    def height_at(self, x, y):
        """Height at a BNG point, or None if outside this tile / no data."""
        if self._rows is None:  # parse the numbers only when first needed
            values = " ".join(self._lines).split()
            self._rows = [[float(v) for v in values[r * self.ncols:(r + 1) * self.ncols]]
                          for r in range(self.nrows)]
            self._lines = None
        col = int((x - self.xll) // self.cell)
        row_from_bottom = int((y - self.yll) // self.cell)
        if not (0 <= col < self.ncols and 0 <= row_from_bottom < self.nrows):
            return None
        v = self._rows[self.nrows - 1 - row_from_bottom][col]
        return None if v == self.nodata else v


def find_tiles(sources, box):
    """Collect every .asc tile that overlaps the box, from files, folders or zips."""
    found = []

    def consider(name, data):
        try:
            text = data.decode("ascii", errors="ignore")
            tile = Tile(name, text)
        except (KeyError, ValueError, IndexError):
            return
        if tile.overlaps(box):
            found.append(tile)

    def from_zip(zf):
        for info in zf.infolist():
            lower = info.filename.lower()
            if lower.endswith(".asc"):
                consider(info.filename, zf.read(info))
            elif lower.endswith(".zip"):  # OS packs each tile in its own zip
                with zipfile.ZipFile(io.BytesIO(zf.read(info))) as inner:
                    from_zip(inner)

    for src in sources:
        src = os.path.expanduser(src)
        if os.path.isdir(src):
            for root, _, files in os.walk(src):
                for f in files:
                    path = os.path.join(root, f)
                    if f.lower().endswith(".asc"):
                        with open(path, "rb") as fh:
                            consider(path, fh.read())
                    elif f.lower().endswith(".zip"):
                        with zipfile.ZipFile(path) as zf:
                            from_zip(zf)
        elif src.lower().endswith(".zip"):
            with zipfile.ZipFile(src) as zf:
                from_zip(zf)
        elif src.lower().endswith(".asc"):
            with open(src, "rb") as fh:
                consider(src, fh.read())
        else:
            sys.exit(f"Don't know how to read {src} (expected a .zip, .asc or folder)")
    return found


# ------------------------------------------------------------- building the map

def sample_grid(tiles, box, cell):
    width = round((box[2] - box[0]) / cell)
    height = round((box[3] - box[1]) / cell)
    heights, missing = [], 0
    for r in range(height):                     # row 0 = north edge
        y = box[3] - (r + 0.5) * cell
        for c in range(width):
            x = box[0] + (c + 0.5) * cell
            h = None
            for t in tiles:
                h = t.height_at(x, y)
                if h is not None:
                    break
            if h is None:
                missing += 1
                h = 0.0                         # no data: treat as sea level
            heights.append(h)
    return width, height, heights, missing


def find_sea(width, height, heights, sea_level):
    """Low ground connected to the edge of the map counts as sea.
    (Low ground inland, cut off from the edge, stays as land.)"""
    sea = [0] * (width * height)
    queue = deque()
    for r in range(height):
        for c in range(width):
            if (r in (0, height - 1) or c in (0, width - 1)) and heights[r * width + c] <= sea_level:
                sea[r * width + c] = 1
                queue.append((r, c))
    while queue:
        r, c = queue.popleft()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < height and 0 <= nc < width:
                i = nr * width + nc
                if not sea[i] and heights[i] <= sea_level:
                    sea[i] = 1
                    queue.append((nr, nc))
    return sea


def placeholder_map(size=120):
    """A made-up coast so the game runs before the real data is added."""
    heights = []
    for r in range(size):
        # Coastline wanders down the west side with a headland part-way down.
        coast = 0.30 * size + 4 * math.sin(r / 9.0) - 14 * math.exp(-((r - 0.45 * size) / 7.0) ** 2)
        for c in range(size):
            d = c - coast
            heights.append(-2.0 if d < 0 else round(min(2 + d * 0.45, 40) + 3 * math.sin(c / 7.0) * math.cos(r / 11.0), 1))
    sea = find_sea(size, size, heights, 0.5)
    return size, size, heights, sea


# ------------------------------------------------------------------- outputs

def write_png(path, width, height, pixels, scale=4):
    """Write an RGB PNG using only the standard library."""
    raw = bytearray()
    for r in range(height):
        row = bytearray([0])  # filter type: none
        for c in range(width):
            row += bytes(pixels[r * width + c]) * scale
        raw += bytes(row) * scale
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width * scale, height * scale, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def preview_pixels(width, height, heights, sea):
    land = [h for h, s in zip(heights, sea) if not s]
    top = max(land) if land else 1.0
    pixels = []
    for h, s in zip(heights, sea):
        if s:
            pixels.append((46, 107, 168))
        else:
            t = max(0.0, min(1.0, h / max(top, 1.0)))
            pixels.append((int(158 - 66 * t), int(189 - 61 * t), int(117 - 46 * t)))
    return pixels


def save(out_json, name, width, height, cell, heights, sea, box=None, credits=""):
    os.makedirs(os.path.dirname(out_json) or ".", exist_ok=True)
    data = {
        "name": name,
        "width": width,
        "height": height,
        "cell_size_m": cell,
        "heights": [round(h, 1) for h in heights],
        "water": sea,
        "credits": credits,
    }
    if box:
        data["bng_box"] = list(box)
    with open(out_json, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))
    preview = os.path.join(os.path.dirname(out_json), "preview.png")
    write_png(preview, width, height, preview_pixels(width, height, heights, sea))
    return preview


# ---------------------------------------------------------------------- main

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(here, "..", "map", "troon_map.json")

    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("sources", nargs="*", help="OS Terrain 50 zip(s), folder(s) or .asc file(s)")
    p.add_argument("--box", nargs=4, type=float, metavar=("WEST", "SOUTH", "EAST", "NORTH"),
                   default=TROON_BOX, help="area in British National Grid metres (default: Troon)")
    p.add_argument("--cell", type=float, default=50.0, help="metres per game tile (default 50)")
    p.add_argument("--sea-level", type=float, default=0.5,
                   help="ground at or below this height, joined to the map edge, is sea (default 0.5 m)")
    p.add_argument("--name", default="Troon", help="map name shown in the game")
    p.add_argument("--out", default=default_out, help="where to write the map file")
    p.add_argument("--placeholder", action="store_true", help="write a made-up test coast instead")
    args = p.parse_args()
    out = os.path.normpath(args.out)

    if args.placeholder:
        w, h, heights, sea = placeholder_map()
        preview = save(out, "Placeholder coast (not real Troon yet)", w, h, 50.0, heights, sea,
                       credits="Placeholder terrain. Run tools/make_troon_map.py with OS Terrain 50 for real Troon.")
        print(f"Wrote placeholder map {w} x {h} -> {out}\nPreview: {preview}")
        return

    if not args.sources:
        p.error("give the OS Terrain 50 download (zip or folder), or use --placeholder")

    box = tuple(args.box)
    print("Looking for height tiles that cover the map area...")
    tiles = find_tiles(args.sources, box)
    if not tiles:
        sys.exit("No OS Terrain 50 tiles cover this area. Is it the 'ASCII Grid' download?")
    print(f"Found {len(tiles)} tile(s): " + ", ".join(sorted(os.path.basename(t.name) for t in tiles)))

    w, h, heights, missing = sample_grid(tiles, box, args.cell)
    sea = find_sea(w, h, heights, args.sea_level)
    preview = save(out, args.name, w, h, args.cell, heights, sea, box=box, credits=CREDITS)

    land = [v for v, s in zip(heights, sea) if not s]
    print(f"Map: {w} x {h} tiles at {args.cell:g} m  ({w * args.cell / 1000:g} km x {h * args.cell / 1000:g} km)")
    print(f"Sea: {sum(sea) * 100 // len(sea)}% of tiles   Highest land: {max(land) if land else 0:.0f} m")
    if missing:
        print(f"Warning: {missing} tiles had no height data and were set to sea level.")
    print(f"Saved {out}\nPreview: {preview}")


if __name__ == "__main__":
    main()
