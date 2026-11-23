"""What every map tool shares: the sea rule, and writing the map file and its preview.

Used by tools/make_bay_map.py. Only Python's built-in libraries.
"""
import json
import os
import struct
import zlib
from collections import deque


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
