"""Builds the Troon building models (.glb) for the game, in Blender.

Run with Blender's Python (pip package "bpy"):
    python tools/make_buildings.py assets/models [preview_folder]
(set ONLY=name,name to rebuild just those models)

Each model is one mesh with named materials that the game swaps for its own
shaders: stone, roof, glass, frame, door, metal, pot, fascia, render, awning, lead,
cladding (ribbed metal walls), sheet (metal roofs) and accent (painted in the
building's second colour: fire station doors, the hospital's red cross).
Axes in Blender: x along the street, +y towards the street (the front), z up.
The origin is the middle of the footprint at ground level, so the game can place
and stretch a model exactly like the old boxes.
"""
import math
import os
import sys

import bpy
import bmesh

MATERIALS = {
    # name: preview colour (the game uses its own shaders and colours)
    "stone": (0.62, 0.46, 0.30), "roof": (0.20, 0.23, 0.27), "glass": (0.06, 0.08, 0.10),
    "frame": (0.88, 0.87, 0.82), "door": (0.10, 0.20, 0.35), "metal": (0.12, 0.12, 0.13),
    "pot": (0.55, 0.30, 0.20), "fascia": (0.10, 0.25, 0.20), "render": (0.85, 0.83, 0.78),
    "awning": (0.55, 0.12, 0.12), "lead": (0.32, 0.34, 0.36),
    "cladding": (0.55, 0.60, 0.62), "sheet": (0.40, 0.42, 0.44),
    "accent": (0.72, 0.08, 0.06),
    # glass in the wall colour (curtain walling), shop windows (lit all evening),
    # red aviation lights, floodlit trim on tower crowns, office glazing
    "curtain": (0.20, 0.32, 0.42), "display": (0.12, 0.10, 0.08), "beacon": (0.8, 0.05, 0.03),
    "lamp": (0.85, 0.85, 0.80), "office": (0.05, 0.06, 0.08),
    "green": (0.20, 0.30, 0.10),   # a roof terrace: sedum or gravel
    "cool": (0.75, 0.75, 0.72),    # a pale flat roof (California's "cool roofs")
}
MAT_INDEX = {name: n for n, name in enumerate(MATERIALS)}


class Builder:
    """Collects solids (as corner lists) with a material each, then makes one mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []

    def _add(self, pts, faces, mat):
        base = len(self.verts)
        self.verts.extend(pts)
        for f in faces:
            self.faces.append([base + k for k in f])
            self.mats.append(MAT_INDEX[mat])

    def hexa(self, c, mat):
        # 8 corners: bottom 0-3 then top 4-7, each going round the same way.
        self._add(c, [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]], mat)

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        self.hexa([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                   (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], mat)

    def prism(self, plan, z0, z1, mat):
        # A vertical prism from a plan polygon [(x, y), ...].
        n = len(plan)
        pts = [(x, y, z0) for x, y in plan] + [(x, y, z1) for x, y in plan]
        faces = [list(range(n))[::-1], list(range(n, 2 * n))]
        for k in range(n):
            j = (k + 1) % n
            faces.append([k, j, n + j, n + k])
        self._add(pts, faces, mat)

    def extrude_x(self, section, x0, x1, mat):
        # A prism along x from a cross-section [(y, z), ...] (roofs, skews).
        n = len(section)
        pts = [(x0, y, z) for y, z in section] + [(x1, y, z) for y, z in section]
        faces = [list(range(n))[::-1], list(range(n, 2 * n))]
        for k in range(n):
            j = (k + 1) % n
            faces.append([k, j, n + j, n + k])
        self._add(pts, faces, mat)

    def extrude_y(self, section, y0, y1, mat):
        # A prism along y from a cross-section [(x, z), ...] (gables facing the street).
        n = len(section)
        pts = [(x, y0, z) for x, z in section] + [(x, y1, z) for x, z in section]
        faces = [list(range(n)), list(range(n, 2 * n))[::-1]]
        for k in range(n):
            j = (k + 1) % n
            faces.append([k, n + k, n + j, j])
        self._add(pts, faces, mat)

    def cylinder(self, x, y, r, z0, z1, mat, sides=8):
        plan = [(x + r * math.cos(2 * math.pi * k / sides), y + r * math.sin(2 * math.pi * k / sides))
                for k in range(sides)]
        self.prism(plan, z0, z1, mat)


class Face:
    """A wall face: a point on it, the direction along it (u) and outwards (out)."""

    def __init__(self, origin, u, out):
        self.o, self.u, self.out = origin, u, out

    def point(self, a, b, z):
        return (self.o[0] + self.u[0] * a + self.out[0] * b,
                self.o[1] + self.u[1] * a + self.out[1] * b, z)

    def slab(self, mb, a0, a1, z0, z1, b0, b1, mat):
        # A box on the face: a0..a1 along it, z0..z1 up, b0..b1 out from it.
        c = [self.point(a0, b0, z0), self.point(a1, b0, z0), self.point(a1, b1, z0), self.point(a0, b1, z0),
             self.point(a0, b0, z1), self.point(a1, b0, z1), self.point(a1, b1, z1), self.point(a0, b1, z1)]
        mb.hexa(c, mat)


def front(w, d): return Face((0, d / 2, 0), (1, 0, 0), (0, 1, 0))
def back(w, d): return Face((0, -d / 2, 0), (-1, 0, 0), (0, -1, 0))
def left(w, d): return Face((-w / 2, 0, 0), (0, 1, 0), (-1, 0, 0))
def right(w, d): return Face((w / 2, 0, 0), (0, -1, 0), (1, 0, 0))


def window(mb, f, a, z, w, h, surround=True, bars=True, sill=True, lintel=True):
    """A sash window: glass, white painted frame, glazing bars, stone sill and lintel."""
    f.slab(mb, a - w / 2, a + w / 2, z, z + h, -0.02, 0.02, "glass")
    ft = 0.07
    for a0, a1, z0, z1 in ((a - w / 2, a - w / 2 + ft, z, z + h), (a + w / 2 - ft, a + w / 2, z, z + h),
                           (a - w / 2, a + w / 2, z, z + ft), (a - w / 2, a + w / 2, z + h - ft, z + h)):
        f.slab(mb, a0, a1, z0, z1, 0.0, 0.06, "frame")
    if bars:
        f.slab(mb, a - 0.025, a + 0.025, z, z + h, 0.0, 0.04, "frame")             # upright
        f.slab(mb, a - w / 2, a + w / 2, z + h * 0.5 - 0.04, z + h * 0.5 + 0.04, 0.0, 0.07, "frame")   # meeting rail
    if surround:
        s = 0.14
        f.slab(mb, a - w / 2 - s, a - w / 2, z, z + h, 0.0, 0.07, "stone")
        f.slab(mb, a + w / 2, a + w / 2 + s, z, z + h, 0.0, 0.07, "stone")
    if sill:
        f.slab(mb, a - w / 2 - 0.18, a + w / 2 + 0.18, z - 0.14, z, -0.02, 0.17, "stone")
    if lintel:
        f.slab(mb, a - w / 2 - 0.16, a + w / 2 + 0.16, z + h, z + h + 0.26, 0.0, 0.08, "stone")


def door(mb, f, a, w=1.0, h=2.2, steps=2, fanlight=True, z0=0.0):
    """A panelled front door in a stone surround, with a fanlight and stone steps."""
    zt = z0 + 0.17 * steps
    f.slab(mb, a - w / 2, a + w / 2, zt, zt + h, -0.02, 0.03, "door")
    f.slab(mb, a - w / 2 - 0.16, a - w / 2, zt, zt + h + 0.5, 0.0, 0.08, "stone")
    f.slab(mb, a + w / 2, a + w / 2 + 0.16, zt, zt + h + 0.5, 0.0, 0.08, "stone")
    if fanlight:
        f.slab(mb, a - w / 2, a + w / 2, zt + h + 0.04, zt + h + 0.45, -0.02, 0.02, "glass")
    f.slab(mb, a - w / 2 - 0.2, a + w / 2 + 0.2, zt + h + 0.45, zt + h + 0.7, 0.0, 0.12, "stone")
    for k in range(steps):
        f.slab(mb, a - w / 2 - 0.25, a + w / 2 + 0.25, z0 + 0.17 * k, z0 + 0.17 * (k + 1),
               0.0, 0.32 * (steps - k), "stone")


def bay(mb, f, a, width, proj, z0, z1, floors, storey, cap="lead"):
    """A canted bay window: a three-sided stone bay with windows on each side."""
    p = proj
    plan = [f.point(a - width / 2, 0.0, 0)[:2], f.point(a - width / 2 + p, p, 0)[:2],
            f.point(a + width / 2 - p, p, 0)[:2], f.point(a + width / 2, 0.0, 0)[:2]]
    mb.prism(plan, z0, z1, "stone")
    # The three faces of the bay, as their own little walls.
    cx = math.sqrt(0.5)
    faces = []
    ux, uy = f.u[0], f.u[1]
    ox, oy = f.out[0], f.out[1]
    for (pa, pb) in ((plan[0], plan[1]), (plan[1], plan[2]), (plan[2], plan[3])):
        mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
        dx, dy = pb[0] - pa[0], pb[1] - pa[1]
        ln = math.hypot(dx, dy)
        u = (dx / ln, dy / ln, 0)
        out = (u[1], -u[0], 0)
        if out[0] * ox + out[1] * oy < 0:
            out = (-out[0], -out[1], 0)
        faces.append((Face((mid[0], mid[1], 0), u, out), ln))
    for fl in range(floors):
        zb = z0 + fl * storey + 0.9
        for (bf, ln) in faces:
            window(mb, bf, 0.0, zb, ln * 0.62, storey * 0.58, surround=False, bars=True, lintel=False)
    # A cap over the bay.
    capplan = [f.point(a - width / 2 - 0.15, 0.0, 0)[:2], f.point(a - width / 2 + p - 0.05, p + 0.18, 0)[:2],
               f.point(a + width / 2 - p + 0.05, p + 0.18, 0)[:2], f.point(a + width / 2 + 0.15, 0.0, 0)[:2]]
    mb.prism(capplan, z1, z1 + 0.28, cap)


def gable_roof(mb, w, d, h_wall, rise, over=0.35, gable_over=0.12, skews=True, mat="roof"):
    """A slate roof, ridge along the street, with stone gables and skew copes."""
    hw, hd = w / 2, d / 2
    section = [(-hd - over, h_wall - 0.18), (hd + over, h_wall - 0.18), (hd + over, h_wall + 0.02),
               (0.0, h_wall + rise + 0.18), (-hd - over, h_wall + 0.02)]
    mb.extrude_x(section, -hw - gable_over, hw + gable_over, mat)
    # Stone gable triangles under the roof at each end.
    tri = [(-hd, h_wall - 0.01), (hd, h_wall - 0.01), (0.0, h_wall + rise - 0.05)]
    mb.extrude_x(tri, -hw, -hw + 0.3, "stone")
    mb.extrude_x(tri, hw - 0.3, hw, "stone")
    if skews:
        skew = [(-hd - 0.05, h_wall + 0.05), (hd + 0.05, h_wall + 0.05), (0.0, h_wall + rise + 0.32)]
        mb.extrude_x(skew, -hw - 0.04, -hw + 0.38, "stone")
        mb.extrude_x(skew, hw - 0.38, hw + 0.04, "stone")
    # Gutters along both eaves, and a ridge line.
    mb.box(-hw - gable_over, hw + gable_over, hd + over - 0.05, hd + over + 0.1, h_wall - 0.3, h_wall - 0.12, "metal")
    mb.box(-hw - gable_over, hw + gable_over, -hd - over - 0.1, -hd - over + 0.05, h_wall - 0.3, h_wall - 0.12, "metal")
    mb.box(-hw - gable_over, hw + gable_over, -0.09, 0.09, h_wall + rise + 0.12, h_wall + rise + 0.26, "lead")


def hip_roof(mb, w, d, h_wall, rise, over=0.35, mat="roof"):
    """A hipped slate roof: sloping on all four sides up to a short ridge."""
    hw, hd = w / 2 + over, d / 2 + over
    inset = min(hd, hw * 0.8)
    z0 = h_wall - 0.15
    pts = [(-hw, -hd, z0), (hw, -hd, z0), (hw, hd, z0), (-hw, hd, z0),
           (-hw + inset, 0.0, h_wall + rise + 0.15), (hw - inset, 0.0, h_wall + rise + 0.15)]
    mb._add(pts, [[0, 3, 2, 1], [3, 4, 5, 2], [0, 1, 5, 4], [0, 4, 3], [1, 2, 5]], mat)
    mb.box(-hw, hw, hd - 0.12, hd + 0.05, h_wall - 0.32, h_wall - 0.14, "metal")
    mb.box(-hw, hw, -hd - 0.05, -hd + 0.12, h_wall - 0.32, h_wall - 0.14, "metal")


def porch(mb, f, a, w=2.0, proj=1.4, h=2.9):
    """A little stone porch with a glazed door and a slate roof, in front of the door."""
    f.slab(mb, a - w / 2, a + w / 2, 0.0, h, 0.0, proj, "stone")
    f.slab(mb, a - 0.45, a + 0.45, 0.35, 2.4, proj, proj + 0.03, "door")
    f.slab(mb, a - 0.45, a + 0.45, 2.45, 2.75, proj, proj + 0.02, "glass")
    p = [f.point(a - w / 2 - 0.15, -0.05, h), f.point(a + w / 2 + 0.15, -0.05, h),
         f.point(a + w / 2 + 0.15, proj + 0.2, h), f.point(a - w / 2 - 0.15, proj + 0.2, h),
         f.point(a, -0.05, h + 0.9), f.point(a, proj + 0.2, h + 0.9)]
    mb._add(p, [[0, 3, 2, 1], [0, 1, 4], [3, 5, 2], [1, 2, 5, 4], [0, 4, 5, 3]], "roof")


def door_hood(mb, f, a, w=1.3, z=2.75):
    f.slab(mb, a - w / 2, a + w / 2, z, z + 0.16, 0.0, 0.55, "lead")


def front_gable(mb, w_g, d, h_wall, rise, a=0.0):
    """A gable rising through the front eaves (a wallhead), with its own roof."""
    hd = d / 2
    mb.box(a - w_g / 2, a + w_g / 2, hd - 2.0, hd, h_wall - 0.2, h_wall + 1.6, "stone")
    sec = [(a - w_g / 2 - 0.25, h_wall + 1.45), (a + w_g / 2 + 0.25, h_wall + 1.45), (a, h_wall + 1.45 + w_g * 0.45)]
    pts = [(x, hd + 0.2, z) for x, z in sec] + [(x, hd - 3.2, z) for x, z in sec]
    mb._add(pts, [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], "roof")
    tri = [(a - w_g / 2, h_wall + 1.4), (a + w_g / 2, h_wall + 1.4), (a, h_wall + 1.4 + w_g * 0.42)]
    pts = [(x, hd, z) for x, z in tri] + [(x, hd - 0.3, z) for x, z in tri]
    mb._add(pts, [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], "stone")


def roof_height_at(y, d, h_wall, rise):
    return h_wall + rise * (1.0 - abs(y) / (d / 2))


def chimney(mb, x, y, w, d, z0, z1, pots=2):
    """A stone stack with a cope and clay pots."""
    mb.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z0, z1, "stone")
    mb.box(x - w / 2 - 0.08, x + w / 2 + 0.08, y - d / 2 - 0.08, y + d / 2 + 0.08, z1, z1 + 0.14, "stone")
    for k in range(pots):
        px = x - w / 2 + (k + 0.5) * w / pots
        mb.cylinder(px, y, 0.13, z1 + 0.14, z1 + 0.62, "pot", 8)


def dormer(mb, x, y_face, w, h, z_base, depth=1.4):
    """A dormer window on the front roof slope (its face at y = y_face)."""
    mb.box(x - w / 2, x + w / 2, y_face - depth, y_face, z_base, z_base + h, "stone")
    f = Face((x, y_face, 0), (1, 0, 0), (0, 1, 0))
    window(mb, f, 0.0, z_base + 0.2, w - 0.6, h - 0.45, surround=False, lintel=False, sill=False)
    sec = [(y_face - depth, z_base + h - 0.05), (y_face + 0.15, z_base + h - 0.05), (y_face + 0.15, z_base + h + 0.05),
           (y_face - depth, z_base + h + 0.05)]
    # A little pitched roof over it (ridge front to back).
    hw = w / 2 + 0.15
    pts = [(x - hw, y_face + 0.15, z_base + h - 0.05), (x + hw, y_face + 0.15, z_base + h - 0.05),
           (x + hw, y_face - depth, z_base + h - 0.05), (x - hw, y_face - depth, z_base + h - 0.05),
           (x, y_face + 0.15, z_base + h + 0.75), (x, y_face - depth, z_base + h + 0.75)]
    mb._add(pts, [[0, 3, 2, 1], [0, 1, 4], [3, 5, 2], [1, 2, 5, 4], [0, 4, 5, 3]], "roof")


def plinth(mb, w, d, h=0.45):
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.3, h, "stone")


def string_course(mb, w, d, z, t=0.16, out=0.06):
    mb.box(-w / 2 - out, w / 2 + out, -d / 2 - out, d / 2 + out, z, z + t, "stone")


# ---------------------------------------------------------------- the models

def villa(variant="a"):
    # a: bay and door, gabled; b: the other way round, hipped roof and a porch;
    # c: twin bays either side of a porch, with a gable over the middle.
    w, d, h, rise = 7.4, 8.0, 5.8, 3.4
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    if variant == "b":
        bay(mb, f, 1.55, 3.0, 0.85, 0.0, 3.1, 1, 3.1)
        porch(mb, f, -2.1, 1.9, 1.3)
        for a in (1.55, -2.1):
            window(mb, f, a, 3.55, 1.1, 1.6)
    elif variant == "c":
        for a in (-2.4, 2.4):
            bay(mb, f, a, 2.4, 0.7, 0.0, 3.1, 1, 3.1)
            window(mb, f, a, 3.55, 1.0, 1.55)
        porch(mb, f, 0.0, 1.8, 1.2)
        front_gable(mb, 2.6, d, h, rise, 0.0)
        window(mb, f, 0.0, 4.1, 0.8, 1.2, surround=True)
    else:
        bay(mb, f, -1.55, 3.0, 0.85, 0.0, 3.1, 1, 3.1)
        door(mb, f, 2.1)
        for a in (-1.55, 2.1):
            window(mb, f, a, 3.55, 1.1, 1.6)
    for a in (-1.8, 1.8):
        window(mb, b, a, 0.9, 1.0, 1.4, surround=False)
        window(mb, b, a, 3.6, 0.9, 1.3, surround=False)
    for side in (l, r):
        window(mb, side, 1.2, 0.95, 0.9, 1.4, surround=False)
    if variant == "b":
        hip_roof(mb, w, d, h, rise)
        chimney(mb, 0.9, 0.0, 0.8, 1.1, h + rise - 0.9, h + rise + 1.0, 3)
    else:
        gable_roof(mb, w, d, h, rise)
        for x in (-w / 2 + 0.45, w / 2 - 0.45):
            chimney(mb, x, 0.0, 0.7, 1.1, h + rise - 0.6, h + rise + 1.1, 2)
    mb.cylinder(w / 2 - 0.12, d / 2 + 0.1, 0.05, 0.0, h - 0.2, "metal", 6)      # downpipe
    return mb, (w, d, h, rise)


def bungalow(variant="a"):
    # a: bay, dormers in a gabled roof; b: twin bays, a porch and a hipped roof.
    w, d, h, rise = 8.0, 8.0, 3.2, 3.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    f, b = front(w, d), back(w, d)
    for a in (-2.0, 2.0):
        window(mb, b, a, 0.9, 1.0, 1.4, surround=False)
    if variant == "b":
        for a in (-2.5, 2.5):
            bay(mb, f, a, 2.4, 0.7, 0.0, 2.9, 1, 3.0)
        porch(mb, f, 0.0, 1.7, 1.2, 2.7)
        hip_roof(mb, w, d, h, rise)
        chimney(mb, -1.2, 0.0, 0.7, 1.0, h + rise - 0.8, h + rise + 0.9, 2)
        return mb, (w, d, h, rise)
    bay(mb, f, -2.0, 2.8, 0.75, 0.0, 2.9, 1, 3.0)
    door(mb, f, 0.9, steps=1)
    window(mb, f, 2.8, 0.95, 1.0, 1.4)
    gable_roof(mb, w, d, h, rise)
    for x in (-1.9, 1.9):
        y = d / 2 - 1.6
        dormer(mb, x, y, 1.6, 1.4, roof_height_at(y, d, h, rise) - 0.25)
    chimney(mb, w / 2 - 0.45, 0.0, 0.7, 1.0, h + rise - 0.6, h + rise + 1.0, 2)
    return mb, (w, d, h, rise)


# ----------------------------------------------- Californian homes (Palo Alto)
# Variants of the bungalow and villa: the same declared sizes (so the game fits
# them to the same plots), with lower Californian roofs built inside that size.
# Walls are stucco ("render", the wall colour); roofs are clay tile or shingle
# ("roof", the roof colour).

def ca_window(mb, f, a, z, w, h):
    window(mb, f, a, z, w, h, surround=False, bars=False, sill=False, lintel=False)


def ranch():
    # A low ranch house: one long storey, a shallow hipped roof with deep eaves, a
    # big picture window, the front door and a garage door.
    w, d, h, rise = 8.0, 8.0, 3.2, 3.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, 2.9, "render")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.2, 0.15, "stone")
    f, b = front(w, d), back(w, d)
    ca_window(mb, f, -2.2, 0.8, 2.6, 1.4)                  # picture window
    f.slab(mb, -0.3, 0.6, 0.0, 2.1, 0.0, 0.05, "door")
    f.slab(mb, 1.3, 3.7, 0.0, 2.2, 0.0, 0.06, "frame")     # garage door
    for a in (-2.0, 2.0):
        ca_window(mb, b, a, 1.0, 1.4, 1.0)
    hip_roof(mb, w, d, 2.9, 1.3, over=0.8)
    return mb, (w, d, h, rise)


def mission():
    # A Spanish-style bungalow: stucco, a low clay-tile gable roof, an arcaded porch
    # with three openings, and deep-set windows.
    w, d, h, rise = 8.0, 8.0, 3.2, 3.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2 + 0.0, d / 2 - 1.6, 0.0, 3.1, "render")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.2, 0.15, "stone")
    # The porch: a stucco front wall with three openings, under its own low roof.
    y0, y1 = d / 2 - 1.6, d / 2
    for x0, x1 in ((-w / 2, -2.9), (-1.7, -1.1), (1.1, 1.7), (2.9, w / 2)):
        mb.box(x0, x1, y1 - 0.35, y1, 0.0, 2.7, "render")
    mb.box(-w / 2, w / 2, y1 - 0.35, y1, 2.2, 2.7, "render")
    mb.box(-0.4, 0.4, y0, y0 + 0.05, 0.0, 2.1, "door")
    f2 = Face((0, y0, 0), (1, 0, 0), (0, 1, 0))
    for a in (-2.4, 2.4):
        ca_window(mb, f2, a, 0.9, 1.0, 1.3)
    b = back(w, d)
    for a in (-2.0, 2.0):
        ca_window(mb, b, a, 1.0, 1.0, 1.2)
    gable_roof(mb, w, d, 3.1, 1.2, over=0.3, gable_over=0.2, skews=False)
    return mb, (w, d, h, rise)


def ca_villa():
    # A two-storey Spanish revival house: stucco, a low clay-tile hipped roof, tall
    # windows, a balcony over the door with an iron railing.
    w, d, h, rise = 7.4, 8.0, 5.8, 3.4
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, 5.8, "render")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.2, 0.15, "stone")
    f, b = front(w, d), back(w, d)
    f.slab(mb, -0.5, 0.5, 0.0, 2.3, 0.0, 0.05, "door")
    for a in (-2.3, 2.3):
        ca_window(mb, f, a, 0.8, 1.2, 1.7)
        ca_window(mb, f, a, 3.6, 1.1, 1.4)
    ca_window(mb, f, 0.0, 3.4, 1.4, 1.9)
    mb.box(-1.2, 1.2, d / 2, d / 2 + 0.8, 3.15, 3.35, "render")            # balcony
    for x in [-1.15 + k * 0.23 for k in range(11)]:
        mb.box(x - 0.025, x + 0.025, d / 2 + 0.72, d / 2 + 0.78, 3.35, 4.3, "metal")
    mb.box(-1.2, 1.2, d / 2 + 0.7, d / 2 + 0.8, 4.25, 4.35, "metal")
    for a in (-2.0, 2.0):
        ca_window(mb, b, a, 0.9, 1.1, 1.4)
        ca_window(mb, b, a, 3.6, 1.1, 1.4)
    hip_roof(mb, w, d, 5.8, 1.5, over=0.6)
    return mb, (w, d, h, rise)


def ca_modern():
    # A modern Californian house: two white stucco boxes, the upper one sliding over
    # the lower, big glass, a flat roof with a thin edge, timber (door colour) by the door.
    w, d, h, rise = 7.4, 8.0, 5.8, 3.4
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2 - 0.8, 0.0, 2.9, "render")
    mb.box(-w / 2, w / 2 - 1.2, -d / 2, d / 2, 2.9, 5.8, "render")
    mb.box(-w / 2 - 0.2, w / 2 - 1.0, -d / 2 - 0.2, d / 2 + 0.2, 5.8, 6.0, "frame")
    mb.box(-w / 2 - 0.1, w / 2 + 0.1, -d / 2 - 0.1, d / 2 - 0.7, 2.9, 3.05, "frame")
    f_low = Face((0, d / 2 - 0.8, 0), (1, 0, 0), (0, 1, 0))
    f_low.slab(mb, -3.2, 1.0, 0.2, 2.6, -0.02, 0.02, "glass")
    f_low.slab(mb, 1.6, 2.6, 0.0, 2.4, 0.0, 0.06, "door")
    f = front(w, d)
    f.slab(mb, -3.4, 0.6, 3.3, 5.4, -0.02, 0.02, "glass")
    b = back(w, d)
    b.slab(mb, -3.0, 3.0, 0.3, 2.6, -0.02, 0.02, "glass")
    return mb, (w, d, h, rise)


def strip_mall(variant="a"):
    # A Californian strip mall: a long single-storey stucco row of six shopfronts
    # behind a continuous canopy on posts, a sign band and parapet. a: a little
    # Spanish-style tower over the middle; b: a taller anchor store at one end.
    # (The building is set back behind its car park; the front is +y.)
    w, d, h = 46.0, 17.0, 8.0
    mb = Builder()
    yf = d / 2 - 3.0                                   # the shopfront line (the canopy is in front)
    mb.box(-w / 2, w / 2, -d / 2, yf, 0.0, 5.0, "render")
    mb.box(-w / 2 - 0.1, w / 2 + 0.1, -d / 2 - 0.1, yf + 0.1, 5.0, 5.6, "render")       # parapet
    f = Face((0, yf, 0), (1, 0, 0), (0, 1, 0))
    unit = w / 6
    for k in range(6):
        a0 = -w / 2 + k * unit
        f.slab(mb, a0 + 0.35, a0 + unit - 0.35, 0.3, 3.1, -0.02, 0.03, "display")
        f.slab(mb, a0 + unit * 0.5 - 0.6, a0 + unit * 0.5 + 0.6, 0.0, 2.4, 0.0, 0.05, "door")
        f.slab(mb, a0 + 0.3, a0 + unit - 0.3, 3.6, 4.7, 0.0, 0.12, "fascia")              # sign
    mb.box(-w / 2, w / 2, yf, d / 2, 3.25, 3.55, "frame")                                 # canopy
    for k in range(7):
        x = -w / 2 + 0.3 + k * (w - 0.6) / 6
        mb.box(x - 0.15, x + 0.15, d / 2 - 0.45, d / 2 - 0.15, 0.0, 3.25, "frame")
    if variant == "b":
        mb.box(-w / 2, -w / 2 + 14.0, -d / 2, yf + 0.3, 0.0, 7.4, "render")             # anchor store
        mb.box(-w / 2 - 0.1, -w / 2 + 14.1, -d / 2 - 0.1, yf + 0.4, 7.4, 8.0, "render")
        fa = Face((0, yf + 0.3, 0), (1, 0, 0), (0, 1, 0))
        fa.slab(mb, -w / 2 + 3.0, -w / 2 + 11.0, 0.0, 3.0, -0.02, 0.03, "display")
        fa.slab(mb, -w / 2 + 1.5, -w / 2 + 12.5, 4.6, 6.6, 0.0, 0.15, "fascia")
    else:
        mb.box(-3.0, 3.0, yf - 2.0, d / 2 + 0.2, 0.0, 7.2, "render")                      # tower
        pyramid(mb, 0.0, (yf - 2.0 + d / 2 + 0.2) / 2, 3.6, 7.2, 8.0, "roof")
    return mb, (w, d, h, 0.0)


def glass_office(storeys):
    # A business-park office: bands of dark glass between white floor strips, slim
    # vertical fins, a canopy over the door, plant on the roof behind a parapet.
    w, d, storey = 40.0, 18.0, 3.8
    top = storeys * storey
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, top, "office")
    for k in range(1, storeys):
        z = k * storey
        mb.box(-w / 2 - 0.15, w / 2 + 0.15, -d / 2 - 0.15, d / 2 + 0.15, z - 0.5, z + 0.4, "frame")
    for x in [-w / 2 + 0.6 + k * 2.6 for k in range(15)]:
        for y in (d / 2, -d / 2):
            mb.box(x - 0.08, x + 0.08, y - 0.25, y + 0.25, 0.0, top, "frame")
    mb.box(-w / 2 - 0.2, w / 2 + 0.2, -d / 2 - 0.2, d / 2 + 0.2, top, top + 0.7, "frame")    # parapet
    mb.box(-6.0, 6.0, -4.0, 4.0, top + 0.7, top + 2.4, "metal")                               # roof plant
    mb.box(-5.0, 5.0, d / 2, d / 2 + 3.5, 3.2, 3.5, "frame")                                   # canopy
    for x in (-4.7, 4.7):
        mb.box(x - 0.12, x + 0.12, d / 2 + 3.2, d / 2 + 3.45, 0.0, 3.2, "frame")
    return mb, (w, d, top + 2.4, 0.0)


# ------------------------------------- Californian medium and high density
# Stucco ("render", the wall colour) under clay tile ("roof", the roof colour), in
# the same declared sizes as the Scottish terraces, tenements, shops with flats and
# classical blocks, so the game fits them to the same plots.

def face_prism(mb, f, poly, b0, b1, mat):
    # A flat shape drawn on a wall face [(along, z), ...], b0..b1 out from it.
    n = len(poly)
    pts = [f.point(a, b0, z) for a, z in poly] + [f.point(a, b1, z) for a, z in poly]
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for k in range(n):
        j = (k + 1) % n
        faces.append([k, j, n + j, n + k])
    mb._add(pts, faces, mat)


def arch(mb, f, a, z0, w, h, mat="glass", fill="render"):
    """A round-headed opening: the opening, then stucco (or stone) filling its top corners."""
    r = w / 2
    hs = z0 + h - r
    f.slab(mb, a - r, a + r, z0, z0 + h, -0.03, 0.01, mat)
    for side in (-1, 1):
        poly = [(a + side * r, hs), (a + side * r, hs + r), (a, hs + r)]
        for k in range(1, 6):
            t = math.pi / 2 * k / 6
            poly.append((a + side * r * math.sin(t), hs + r * math.cos(t)))
        face_prism(mb, f, poly, 0.0, 0.04, fill)


def tile_hip(mb, x0, x1, y0, y1, z, rise, over=0.5, mat="roof"):
    """A low hipped roof over any rectangle: clay tile in the game's roof colour."""
    hx, hy = (x1 - x0) / 2 + over, (y1 - y0) / 2 + over
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    z0, top = z - 0.12, z + rise
    if hx >= hy:
        pts = [(cx - hx, cy - hy, z0), (cx + hx, cy - hy, z0), (cx + hx, cy + hy, z0), (cx - hx, cy + hy, z0),
               (cx - hx + hy, cy, top), (cx + hx - hy, cy, top)]
        mb._add(pts, [[0, 3, 2, 1], [3, 4, 5, 2], [0, 1, 5, 4], [0, 4, 3], [1, 2, 5]], mat)
    else:
        pts = [(cx - hx, cy - hy, z0), (cx + hx, cy - hy, z0), (cx + hx, cy + hy, z0), (cx - hx, cy + hy, z0),
               (cx, cy - hy + hx, top), (cx, cy + hy - hx, top)]
        mb._add(pts, [[0, 3, 2, 1], [0, 1, 4], [1, 2, 5, 4], [2, 3, 5], [3, 0, 4, 5]], mat)


def pent(mb, f, a0, a1, z, out, drop=0.4, mat="roof"):
    """A short sloping strip of tiles along a wall (over shopfronts, on parapets)."""
    t = 0.12
    p = [f.point(a0, 0.0, z), f.point(a1, 0.0, z), f.point(a1, out, z - drop), f.point(a0, out, z - drop)]
    mb.hexa(p + [(q[0], q[1], q[2] + t) for q in p], mat)


def rail(mb, f, a0, a1, z, out, h=1.0, mat="metal"):
    """An iron railing: a top rail and thin uprights."""
    f.slab(mb, a0, a1, z + h - 0.05, z + h, out - 0.06, out, mat)
    n = max(2, int((a1 - a0) / 0.3))
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        f.slab(mb, a - 0.025, a + 0.025, z, z + h, out - 0.05, out - 0.01, mat)


def balcony(mb, f, a, z, w, out=1.2, glass_rail=False):
    f.slab(mb, a - w / 2, a + w / 2, z - 0.22, z, 0.0, out, "render")
    if glass_rail:
        f.slab(mb, a - w / 2, a + w / 2, z, z + 1.05, out - 0.06, out, "glass")
        f.slab(mb, a - w / 2, a + w / 2, z + 1.0, z + 1.08, out - 0.08, out + 0.02, "metal")
    else:
        rail(mb, f, a - w / 2, a + w / 2, z, out)


def slider(mb, f, a, z, w, h=2.25):
    """A sliding glass door in a dark frame."""
    f.slab(mb, a - w / 2, a + w / 2, z, z + h, -0.02, 0.02, "glass")
    for a0, a1, z0, z1 in ((a - w / 2, a - w / 2 + 0.07, z, z + h), (a + w / 2 - 0.07, a + w / 2, z, z + h),
                           (a - w / 2, a + w / 2, z + h - 0.07, z + h), (a - 0.04, a + 0.04, z, z + h)):
        f.slab(mb, a0, a1, z0, z1, 0.0, 0.05, "metal")


def dark_window(mb, f, a, z, w, h):
    """A modern window: glass in a thin dark frame."""
    f.slab(mb, a - w / 2, a + w / 2, z, z + h, -0.02, 0.02, "glass")
    for a0, a1, z0, z1 in ((a - w / 2, a - w / 2 + 0.06, z, z + h), (a + w / 2 - 0.06, a + w / 2, z, z + h),
                           (a - w / 2, a + w / 2, z, z + 0.06), (a - w / 2, a + w / 2, z + h - 0.06, z + h)):
        f.slab(mb, a0, a1, z0, z1, 0.0, 0.05, "metal")


def flat_top(mb, x0, x1, y0, y1, z, edge=0.25, up=0.35, over=0.0, mat="frame"):
    """A flat roof: dark membrane inside a thin edge (white trim, or the wall colour)."""
    x0, x1, y0, y1 = x0 - over, x1 + over, y0 - over, y1 + over
    mb.box(x0, x1, y0, y1, z - 0.2, z, mat)
    for bx0, bx1, by0, by1 in ((x0, x1, y1 - edge, y1), (x0, x1, y0, y0 + edge),
                               (x0, x0 + edge, y0, y1), (x1 - edge, x1, y0, y1)):
        mb.box(bx0, bx1, by0, by1, z, z + up, mat)
    mb.box(x0 + edge, x1 - edge, y0 + edge, y1 - edge, z, z + 0.05, "cool")


def awning_on(mb, f, a0, a1, z, out=1.3):
    p0, p1 = f.point(a0, 0.15, z), f.point(a1, 0.15, z)
    p2, p3 = f.point(a1, out, z - 0.6), f.point(a0, out, z - 0.6)
    t = 0.06
    mb.hexa([p0, p1, p2, p3] + [(q[0], q[1], q[2] + t) for q in (p0, p1, p2, p3)], "awning")


def tile_chimney(mb, x, y, z0, z1):
    """A stucco chimney with a little tiled cap."""
    mb.box(x - 0.45, x + 0.45, y - 0.45, y + 0.45, z0, z1, "render")
    pyramid(mb, x, y, 0.6, z1, z1 + 0.45, "roof")


def ca_townhouse(variant="a"):
    # Three joined two-storey townhouses, 5 m each. a: Spanish, under one low
    # clay-tile roof with deep eaves, arched doorways, tiled hoods and iron
    # balconettes, the middle house stepped forward. b: modern, three flat-roofed
    # boxes (the middle one taller), big windows in dark frames, a coloured
    # panel by each door.
    w, d, h, rise = 15.0, 8.5, 6.2, 3.2
    mb = Builder()
    b = back(w, d)
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.2, 0.12, "stone")
    for k in range(3):
        cx = -5.0 + k * 5.0
        x0, x1 = cx - 2.5, cx + 2.5
        if variant == "b":
            top = 7.0 if k == 1 else 6.2
            mb.box(x0, x1, -d / 2, d / 2, 0.0, top, "render")
            flat_top(mb, x0, x1, -d / 2, d / 2, top, edge=0.2, up=0.25, over=0.12)
            f = front(w, d)
            f.slab(mb, cx + 0.6, cx + 2.3, 0.0, top - 0.6, 0.0, 0.06, "door")        # coloured panel
            f.slab(mb, cx + 1.0, cx + 1.95, 0.0, 2.3, 0.06, 0.09, "metal")           # the door
            f.slab(mb, cx + 0.5, cx + 2.4, 2.6, 2.75, 0.0, 1.0, "frame")             # canopy
            dark_window(mb, f, cx - 0.9, 0.5, 2.6, 2.0)
            dark_window(mb, f, cx - 0.4, 3.4, 3.6, top - 4.2)
            dark_window(mb, b, -cx, 0.3, 3.6, 2.2)
            dark_window(mb, b, -cx, 3.6, 3.0, 1.6)
        else:
            y1 = d / 2 + (0.45 if k == 1 else 0.0)
            mb.box(x0, x1, -d / 2, y1, 0.0, h, "render")
            f = Face((0, y1, 0), (1, 0, 0), (0, 1, 0))
            arch(mb, f, cx + 1.4, 0.0, 1.2, 2.7, "door")
            ca_window(mb, f, cx - 1.0, 0.8, 1.6, 1.4)
            pent(mb, f, cx - 2.0, cx, 2.6, 0.5, 0.25)
            ca_window(mb, f, cx - 1.0, 3.6, 1.2, 1.5)
            f.slab(mb, cx - 1.7, cx - 0.3, 3.45, 3.6, 0.0, 0.4, "render")
            rail(mb, f, cx - 1.7, cx - 0.3, 3.6, 0.4, h=0.8)
            ca_window(mb, f, cx + 1.4, 3.8, 0.8, 1.2)
            ca_window(mb, b, -cx + 1.0, 0.9, 1.4, 1.3)
            ca_window(mb, b, -cx - 1.2, 3.7, 1.0, 1.2)
    if variant != "b":
        tile_hip(mb, -w / 2, w / 2, -d / 2, d / 2, h, 1.7, over=0.6)
        tile_chimney(mb, w / 2 - 1.0, -0.8, h, h + 2.5)
    return mb, (w, d, h, rise)


def ca_apartments(storeys, variant="a"):
    # Garden apartments round a courtyard. a: Spanish, stucco under a low tile
    # roof, a stair tower with an arched entry and its own tiled top, balconies
    # with iron railings. b: mid-century, flat roof with a deep white edge, an
    # open walkway along each upper floor, coloured panels (the roof colour)
    # and parking tucked under the ground floor.
    w, d, rise = 22.0, 13.0, 4.8
    ground, storey = 3.4, 3.0
    h = ground + (storeys - 1) * storey + 0.5
    mb = Builder()
    f, b = front(w, d), back(w, d)
    units = (-8.25, -2.75, 2.75, 8.25)
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.2, 0.25, "stone")
    if variant == "b":
        y1 = d / 2 - 1.6                                    # the face behind the walkways
        mb.box(-w / 2, w / 2, -d / 2, y1, 0.0, h, "render")
        mb.box(-w / 2, w / 2, y1, d / 2, ground - 0.3, h, "render")    # upper floors over the car port
        fb = Face((0, y1, 0), (1, 0, 0), (0, 1, 0))
        fb.slab(mb, -w / 2 + 0.3, w / 2 - 0.3, 0.0, ground - 0.3, -0.05, 0.0, "metal")    # car port
        for k in range(6):
            x = -w / 2 + 0.3 + k * (w - 0.6) / 5
            mb.box(x - 0.2, x + 0.2, d / 2 - 0.4, d / 2, 0.0, ground - 0.3, "render")    # posts
        mb.box(-w / 2, w / 2, y1, d / 2, ground - 0.3, ground + 0.05, "render")
        # Each upper floor: doors, windows and coloured panels behind an open walkway.
        for fl in range(1, storeys):
            z = ground + (fl - 1) * storey
            ff = Face((0, d / 2, 0), (1, 0, 0), (0, 1, 0))
            for cx in units:
                ff.slab(mb, cx - 2.6, cx - 0.9, z + 0.2, z + 2.6, 0.0, 0.05, "accent")
                ff.slab(mb, cx - 0.7, cx + 0.2, z + 0.05, z + 2.25, 0.0, 0.05, "door")
                dark_window(mb, ff, cx + 1.5, z + 0.9, 2.0, 1.3)
            ff.slab(mb, -w / 2, w / 2, z - 0.2, z + 0.05, 0.0, 1.3, "frame")         # walkway
            rail(mb, ff, -w / 2, w / 2, z + 0.05, 1.3, h=1.0)
        beam(mb, (w / 2 + 0.7, d / 2 - 3.5, 0.0), (w / 2 + 0.7, d / 2 + 0.3, ground), 0.9, "frame")   # stair
        flat_top(mb, -w / 2, w / 2, -d / 2, d / 2, h, edge=0.9, up=0.3, over=0.6)
        for fl in range(storeys):
            z = 0.9 if fl == 0 else ground + (fl - 1) * storey + 0.8
            for a in (-9.0, -5.0, -1.5, 1.5, 5.0, 9.0):
                dark_window(mb, b, a, z, 1.4, 1.3)
        return mb, (w, d, h, rise)
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h, "render")
    # The stair tower: forward of the front, rising above the eaves.
    tw = 3.6
    ty0, ty1 = d / 2 - 1.0, d / 2 + 0.8
    mb.box(-tw / 2, tw / 2, ty0, ty1, 0.0, h + 1.8, "render")
    ft = Face((0, ty1, 0), (1, 0, 0), (0, 1, 0))
    arch(mb, ft, 0.0, 0.0, 2.0, 3.0, "glass")
    for fl in range(1, storeys):
        arch(mb, ft, 0.0, ground + (fl - 1) * storey + 0.9, 0.8, 1.4, "glass")
    tile_hip(mb, -tw / 2, tw / 2, ty0, ty1, h + 1.8, 1.4, over=0.35)
    for cx in units:
        ca_window(mb, f, cx - 0.9, 0.9, 1.6, 1.5)
        ca_window(mb, f, cx + 1.4, 0.9, 0.9, 1.5)
        pent(mb, f, cx - 1.9, cx + 0.1, 2.75, 0.5, 0.25)
        for fl in range(1, storeys):
            z = ground + (fl - 1) * storey
            slider(mb, f, cx - 0.7, z + 0.1, 2.0)
            balcony(mb, f, cx - 0.7, z + 0.1, 2.8, out=1.1)
            ca_window(mb, f, cx + 1.6, z + 0.8, 0.9, 1.4)
    for fl in range(storeys):
        z = 0.9 if fl == 0 else ground + (fl - 1) * storey + 0.8
        for a in (-9.0, -5.0, -1.5, 1.5, 5.0, 9.0):
            ca_window(mb, b, a, z, 1.0, 1.4)
    tile_hip(mb, -w / 2, w / 2, -d / 2, d / 2, h, 2.2, over=0.7)
    tile_chimney(mb, -w / 2 + 2.0, -2.0, h, h + 2.8)
    return mb, (w, d, h, rise)


def ca_mainstreet(storeys, variant="a"):
    # Shops with flats above on a Californian main street. a: Spanish revival,
    # arched shopfronts under a tiled hood, deep windows with iron balconettes, a
    # tiled cap on the parapet and (from three storeys) a little corner tower.
    # b: modern mixed use, an all-glass ground floor under a steel canopy, floors
    # of big windows with glass balconies and coloured panels (the roof colour).
    w, d = 23.0, 18.0
    ground, storey = 3.8, 3.1
    h = ground + (storeys - 1) * storey + 0.4
    mb = Builder()
    f, b = front(w, d), back(w, d)
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "render")
    unit = w / 3
    if variant == "b":
        f.slab(mb, -w / 2 + 0.2, w / 2 - 0.2, 0.0, ground - 0.4, -0.03, 0.02, "display")
        for k in range(4):
            a = -w / 2 + 0.2 + k * (w - 0.4) / 3
            f.slab(mb, a - 0.2, a + 0.2, 0.0, ground, 0.0, 0.15, "render")
        for k in range(3):
            f.slab(mb, -w / 2 + k * unit + unit / 2 - 0.6, -w / 2 + k * unit + unit / 2 + 0.6, 0.0, 2.4,
                   0.02, 0.05, "door")
        f.slab(mb, -w / 2 - 0.1, w / 2 + 0.1, ground - 0.4, ground - 0.15, 0.0, 1.6, "metal")      # canopy
        f.slab(mb, -w / 2, w / 2, ground - 0.15, ground + 0.5, 0.0, 0.1, "fascia")                 # sign band
        for fl in range(1, storeys):
            z = ground + (fl - 1) * storey + 0.6
            f.slab(mb, -w / 2 - 0.05, w / 2 + 0.05, z - 0.35, z - 0.1, 0.0, 0.12, "frame")
            for k in range(4):
                a = -w / 2 + (k + 0.5) * w / 4
                if k % 2 == fl % 2:
                    f.slab(mb, a - 2.6, a - 1.4, z - 0.1, z + 2.4, 0.0, 0.05, "accent")
                    dark_window(mb, f, a + 0.6, z + 0.1, 3.4, 2.2)
                    balcony(mb, f, a + 0.6, z - 0.1, 3.6, out=1.0, glass_rail=True)
                else:
                    dark_window(mb, f, a, z + 0.4, 4.0, 1.7)
            for k in range(5):
                dark_window(mb, b, -w / 2 + (k + 0.5) * w / 5, z + 0.3, 2.0, 1.6)
        flat_top(mb, -w / 2, w / 2, -d / 2, d / 2, h, edge=0.3, up=0.7, over=0.1)
        roof_clutter(mb, w, d, h + 0.05)
        return mb, (w, d, h + 0.7, 0.0)
    for k in range(3):
        c = -w / 2 + (k + 0.5) * unit
        arch(mb, f, c, 0.0, unit - 1.6, ground - 0.2, "display")
        f.slab(mb, c - 0.6, c + 0.6, 0.0, 2.4, 0.01, 0.05, "door")
        if k != 1:
            awning_on(mb, f, c - unit / 2 + 1.0, c + unit / 2 - 1.0, ground - 1.0)
    pent(mb, f, -w / 2, w / 2, ground + 0.35, 0.8, 0.35)
    for fl in range(1, storeys):
        z = ground + (fl - 1) * storey + 0.7
        for k in range(6):
            a = -w / 2 + (k + 0.5) * w / 6
            ca_window(mb, f, a, z, 1.2, 1.7)
            if fl == 1 and k in (1, 4):
                f.slab(mb, a - 0.8, a + 0.8, z - 0.15, z, 0.0, 0.45, "render")
                rail(mb, f, a - 0.8, a + 0.8, z, 0.45, h=0.9)
        for k in range(5):
            ca_window(mb, b, -w / 2 + (k + 0.5) * w / 5, z, 1.0, 1.5)
    # Parapet with a tiled cap along the front, a flat roof behind.
    flat_top(mb, -w / 2, w / 2, -d / 2, d / 2, h, edge=0.3, up=0.7, mat="render")
    pent(mb, f, -w / 2 - 0.1, w / 2 + 0.1, h + 0.85, 0.55, 0.3)
    roof_clutter(mb, w, d, h + 0.05)
    if storeys >= 3:
        x0, x1 = w / 2 - 4.2, w / 2
        mb.box(x0, x1, d / 2 - 4.2, d / 2, h, h + 3.2, "render")
        ft = Face((0, d / 2, 0), (1, 0, 0), (0, 1, 0))
        arch(mb, ft, (x0 + x1) / 2, h + 0.8, 1.6, 2.0, "glass")
        tile_hip(mb, x0, x1, d / 2 - 4.2, d / 2, h + 3.2, 1.6, over=0.35)
    return mb, (w, d, h + 0.7, 0.0)


def ca_classical(storeys, kind):
    # The grand block in Mediterranean revival (offices, mansion flats, big shops,
    # civic buildings): stucco, an arcade of round arches on the ground floor (or
    # arched shopfronts), deep-set windows, iron balconies on flats ("bays"), a
    # band under deep eaves and a low clay-tile hipped roof; a belvedere on the
    # taller ones.
    w, d = 21.0, 13.0
    ground, storey = 4.2, 3.4
    h = ground + (storeys - 1) * storey + 0.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "render")
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.2, 0.5, "stone")
    f, b = front(w, d), back(w, d)
    cols = max(4, int(w / 2.7))
    xs = [-w / 2 + (k + 0.5) * w / cols for k in range(cols)]
    if kind == "shops":
        unit = w / 3
        for k in range(3):
            c = -w / 2 + (k + 0.5) * unit
            arch(mb, f, c, 0.0, unit - 1.4, ground - 0.3, "display")
            f.slab(mb, c - 0.6, c + 0.6, 0.0, 2.5, 0.01, 0.05, "door")
            if k == 1:
                awning_on(mb, f, c - unit / 2 + 1.0, c + unit / 2 - 1.0, ground - 1.2)
    else:
        for x in xs:
            if abs(x) < 1.6:
                arch(mb, f, x, 0.0, 1.8, 3.4, "door")
            else:
                arch(mb, f, x, 0.7, 1.4, 2.8, "glass")
    f.slab(mb, -w / 2, w / 2, ground - 0.2, ground, 0.0, 0.12, "render")     # a band over the ground floor
    bays = kind == "bays"
    for fl in range(1, storeys):
        z = ground + (fl - 1) * storey + 0.6
        for k, x in enumerate(xs):
            if bays and k in (1, cols - 2):
                slider(mb, f, x, z - 0.4, 1.8, 2.3)
                balcony(mb, f, x, z - 0.4, 2.6, out=1.0)
            else:
                ca_window(mb, f, x, z, 1.1, 1.8)
                if fl == 1 and not bays:
                    f.slab(mb, x - 0.7, x + 0.7, z - 0.18, z, 0.0, 0.35, "render")
                    rail(mb, f, x - 0.7, x + 0.7, z, 0.35, h=0.8)
        for x in xs[::2]:
            ca_window(mb, b, x, z, 1.0, 1.7)
    # A band under the eaves with little corbels, then the low tile roof.
    f.slab(mb, -w / 2, w / 2, h - 0.45, h, 0.0, 0.15, "render")
    for x in [-w / 2 + 0.4 + k * 0.9 for k in range(int((w - 0.8) / 0.9) + 1)]:
        f.slab(mb, x - 0.12, x + 0.12, h - 0.25, h + 0.75, 0.0, 0.55, "metal")   # timber corbels
    mb.box(-w / 2, w / 2, -d / 2, d / 2, h, h + 0.9, "render")
    tile_hip(mb, -w / 2, w / 2, -d / 2, d / 2, h + 0.9, 2.4, over=0.8)
    tile_chimney(mb, w / 2 - 2.0, -2.2, h + 0.9, h + 4.2)
    if storeys >= 4:
        x0, x1 = -w / 2 + 1.5, -w / 2 + 5.5
        y0, y1 = -2.0, 2.0
        mb.box(x0, x1, y0, y1, h + 0.9, h + 4.3, "render")
        for fc in (Face(((x0 + x1) / 2, y1, 0), (1, 0, 0), (0, 1, 0)), Face(((x0 + x1) / 2, y0, 0), (-1, 0, 0), (0, -1, 0)),
                   Face((x0, (y0 + y1) / 2, 0), (0, 1, 0), (-1, 0, 0)), Face((x1, (y0 + y1) / 2, 0), (0, -1, 0), (1, 0, 0))):
            for a in (-0.9, 0.9):
                arch(mb, fc, a, h + 2.0, 1.1, 1.9, "glass")
        tile_hip(mb, x0, x1, y0, y1, h + 4.3, 1.5, over=0.45)
    return mb, (w, d, h + 0.9, 4.0)


# ------------------------------------------- Californian campus (college, university, research park)

def arcade(mb, f, a0, a1, top, bays, deep=3.0, spring=2.6, mat="stone"):
    """An open arcade along a wall face: round arches on square piers, a deep
    walkway behind them (its ceiling and floor), and a lean-to tile roof on top.
    f is the face of the arcade's front; the wall it shelters stands deep behind."""
    s = (a1 - a0) / bays
    pier = min(0.9, s * 0.25)
    t = 0.7                                                   # the arcade wall's thickness
    for k in range(bays + 1):
        a = a0 + k * s
        f.slab(mb, max(a0, a - pier / 2), min(a1, a + pier / 2), 0.0, top, -t, 0.0, mat)
    r = (s - pier) / 2
    for k in range(bays):
        c = a0 + (k + 0.5) * s
        f.slab(mb, c - r, c + r, spring + r, top, -t, 0.0, mat)
        for side in (-1, 1):
            poly = [(c + side * r, spring), (c + side * r, spring + r), (c, spring + r)]
            for n in range(1, 6):
                q = math.pi / 2 * n / 6
                poly.append((c + side * r * math.sin(q), spring + r * math.cos(q)))
            face_prism(mb, f, poly, -t, 0.0, mat)
    f.slab(mb, a0, a1, top - 0.35, top, -deep, 0.0, mat)       # ceiling
    f.slab(mb, a0, a1, -0.2, 0.08, -deep, 0.15, "stone")      # floor
    pent(mb, f, a0 - 0.2, a1 + 0.2, top + 0.9 + deep * 0.15, 0.5, 0.9 + deep * 0.15 - 0.1)
    p = [f.point(a0 - 0.2, -deep, top + 0.9), f.point(a1 + 0.2, -deep, top + 0.9),
         f.point(a1 + 0.2, 0.3, top), f.point(a0 - 0.2, 0.3, top)]
    mb.hexa(p + [(q[0], q[1], q[2] + 0.12) for q in p], "roof")


def stone_arch_window(mb, f, a, z, w, h):
    """A deep-set round-headed window in a sandstone wall."""
    arch(mb, f, a, z, w, h, "glass", fill="stone")
    f.slab(mb, a - w / 2 - 0.15, a + w / 2 + 0.15, z - 0.18, z, 0.0, 0.12, "stone")


def ca_quad():
    # A Stanford-style quad: three ranges of buff sandstone round a courtyard open
    # at the back, under low red clay-tile roofs. The front range (two storeys)
    # has an arcade of round arches along the street and a gabled gateway in the
    # middle; the two wings have arcades facing the courtyard, and so does the
    # front range's inner side. Walls in "stone" (the game's sandstone colour),
    # roofs in the roof colour.
    w, d = 40.0, 34.0
    hf, hw = 9.0, 7.6                                        # front range, wings
    mb = Builder()
    yf0, yf1 = 7.0, d / 2 - 3.0                              # the front range behind its arcade
    mb.box(-w / 2, w / 2, yf0, yf1, -0.3, hf, "stone")
    for x0, x1 in ((-w / 2, -w / 2 + 10.0), (w / 2 - 10.0, w / 2)):
        mb.box(x0, x1, -d / 2, yf0, -0.3, hw, "stone")
    # The street arcade, either side of the gateway.
    fa = Face((0, d / 2, 0), (1, 0, 0), (0, 1, 0))
    arcade(mb, fa, -w / 2, -4.0, 4.6, 6)
    arcade(mb, fa, 4.0, w / 2, 4.6, 6)
    fw = Face((0, yf1, 0), (1, 0, 0), (0, 1, 0))
    for k in range(12):
        a = -w / 2 + 1.5 + k * ((w - 3.0) / 11)
        if abs(a) < 5.0:
            continue
        fw.slab(mb, a - 0.5, a + 0.5, 0.0, 2.5, -0.02, 0.02, "door" if k % 4 == 1 else "glass")
        stone_arch_window(mb, fw, a, 5.6, 1.2, 2.2)
    # The gateway: a gable over a big arch, standing proud of the arcades.
    gx = 4.0
    mb.box(-gx, gx, yf1 - 0.5, d / 2 + 0.4, -0.3, hf + 1.0, "stone")
    fg = Face((0, d / 2 + 0.4, 0), (1, 0, 0), (0, 1, 0))
    arch(mb, fg, 0.0, 0.0, 4.6, 6.4, "metal", fill="stone")
    for a in (-2.6, 2.6):
        fg.slab(mb, a - 0.35, a + 0.35, 6.9, 8.6, -0.02, 0.02, "glass")
    fg.slab(mb, -gx - 0.1, gx + 0.1, hf + 0.7, hf + 1.0, 0.0, 0.15, "stone")       # band under the gable
    mb.extrude_y([(-gx - 0.2, hf + 1.0), (gx + 0.2, hf + 1.0), (0.0, hf + 4.4)], yf0 + 2.0, d / 2 + 0.6, "roof")
    mb.extrude_y([(-gx, hf + 1.0), (gx, hf + 1.0), (0.0, hf + 4.0)], yf0 + 2.0, d / 2 + 0.4, "stone")
    # Roofs: the front range and the wings, low hips with deep eaves.
    tile_hip(mb, -w / 2, w / 2, yf0, yf1, hf, 2.8, over=0.7)
    for x0, x1 in ((-w / 2, -w / 2 + 10.0), (w / 2 - 10.0, w / 2)):
        tile_hip(mb, x0, x1, -d / 2, yf0 - 0.3, hw, 2.5, over=0.6)
    # Courtyard arcades: the front range's inner side and the wings' inner sides.
    fi = Face((0, yf0 - 3.0, 0), (-1, 0, 0), (0, -1, 0))
    arcade(mb, fi, -10.0, 10.0, 4.2, 6)
    yc = yf0 - 3.0                                           # where the wings' arcades stop
    arcade(mb, Face((-w / 2 + 13.0, 0, 0), (0, -1, 0), (1, 0, 0)), -yc, d / 2, 4.2, 7)
    arcade(mb, Face((w / 2 - 13.0, 0, 0), (0, 1, 0), (-1, 0, 0)), -d / 2, yc, 4.2, 7)
    # Windows on the outer walls.
    for side in (-1, 1):
        fo = Face((side * w / 2, 0, 0), (0, -side, 0), (side, 0, 0))
        for k in range(9):
            y = -d / 2 + 2.0 + k * 3.4
            stone_arch_window(mb, fo, -side * y, 1.0, 1.1, 2.0)
            stone_arch_window(mb, fo, -side * y, 4.6 if y < yf0 else 5.6, 1.0, 1.8)
    fb = Face((0, -d / 2, 0), (-1, 0, 0), (0, -1, 0))
    for x in (-w / 2 + 2.5, -w / 2 + 5.0, -w / 2 + 7.5, w / 2 - 2.5, w / 2 - 5.0, w / 2 - 7.5):
        stone_arch_window(mb, fb, -x, 1.0, 1.1, 2.0)
        stone_arch_window(mb, fb, -x, 4.6, 1.0, 1.8)
    tile_chimney(mb, -w / 2 + 5.0, -d / 2 + 6.0, hw, hw + 3.2)
    return mb, (w, d, hf + 1.0, 3.4)


def ca_bell_tower():
    # A tall sandstone tower on the campus lawn (after Stanford's Hoover Tower):
    # a plain square shaft with recessed strips of narrow windows, a belfry of
    # tall round arches, a band, and a low dome of red clay tile on a drum.
    w = d = 10.0
    s = 4.0                                                   # half the shaft's width
    mb = Builder()
    mb.box(-s - 0.6, s + 0.6, -s - 0.6, s + 0.6, -0.5, 4.0, "stone")   # the base
    mb.box(-s, s, -s, s, 4.0, 40.0, "stone")
    faces = [Face((0, s, 0), (1, 0, 0), (0, 1, 0)), Face((0, -s, 0), (-1, 0, 0), (0, -1, 0)),
             Face((s, 0, 0), (0, -1, 0), (1, 0, 0)), Face((-s, 0, 0), (0, 1, 0), (-1, 0, 0))]
    for f in faces:
        f.slab(mb, -1.0, 1.0, 6.0, 37.0, -0.15, 0.0, "metal")             # the recessed strip
        for z in range(8, 36, 3):
            f.slab(mb, -0.5, 0.5, z, z + 1.8, -0.1, 0.01, "glass")
        f.slab(mb, -s - 0.3, s + 0.3, 40.0, 40.6, 0.0, 0.35, "stone")      # band under the belfry
    mb.box(-s + 0.3, s - 0.3, -s + 0.3, s - 0.3, 40.6, 47.0, "stone")
    for f in faces:
        fb = Face(f.point(0, -0.3, 0), f.u, f.out)
        for a in (-1.8, 0.0, 1.8):
            arch(mb, fb, a, 41.4, 1.2, 4.6, "metal", fill="stone")
        fb.slab(mb, -s, s, 47.0, 47.7, 0.0, 0.5, "stone")                   # the cornice
    revolve(mb, 0.0, 0.0, [(3.4, 47.7, "stone"), (3.4, 49.2, "stone")], 16)
    revolve(mb, 0.0, 0.0, [(3.7, 49.2, "roof"), (3.5, 50.6, "roof"), (2.9, 51.9, "roof"),
                           (1.9, 52.9, "roof"), (0.7, 53.5, "roof"), (0.15, 53.7, "roof")], 16)
    revolve(mb, 0.0, 0.0, [(0.3, 53.7, "stone"), (0.3, 54.4, "stone"), (0.05, 55.4, "stone")], 8)
    return mb, (w, d, 55.4, 0.0)


def ca_college():
    # A Mission revival college: a two-storey stucco hall behind an arcade, a
    # curved Mission gable with a bell in its opening over the door, arched windows
    # and a low clay-tile roof; a square tower at one end.
    w, d, h = 26.0, 14.0, 8.0
    mb = Builder()
    y1 = d / 2 - 3.0
    mb.box(-w / 2, w / 2, -d / 2, y1, -0.3, h, "render")
    mb.box(-w / 2, w / 2, -d / 2 - 0.05, d / 2, -0.3, 0.25, "stone")
    fa = Face((0, d / 2, 0), (1, 0, 0), (0, 1, 0))
    arcade(mb, fa, -w / 2, -3.2, 4.0, 4, mat="render")
    arcade(mb, fa, 3.2, w / 2 - 4.5, 4.0, 3, mat="render")
    fw = Face((0, y1, 0), (1, 0, 0), (0, 1, 0))
    for a in (-11.0, -8.0, -5.0, 6.0, 9.0):
        ca_window(mb, fw, a, 0.9, 1.0, 1.6)
        arch(mb, fw, a, 4.9, 1.0, 2.0, "glass")
    # The middle: a gabled front with the door, and the curved Mission parapet.
    mb.box(-3.2, 3.2, y1, d / 2 + 0.2, -0.3, h + 0.6, "render")
    fg = Face((0, d / 2 + 0.2, 0), (1, 0, 0), (0, 1, 0))
    arch(mb, fg, 0.0, 0.0, 2.2, 3.6, "door")
    arch(mb, fg, 0.0, 4.8, 1.4, 2.2, "glass")
    prof = [(-3.2, h + 0.6), (-3.2, h + 1.4)]
    for n in range(7):                                        # the curved shoulders and top
        q = math.pi * n / 6
        prof.append((-3.2 + 1.2 * (1 - math.cos(q / 2)) + n * 0.12, h + 1.4 + 1.4 * math.sin(q / 2)))
    prof += [(-1.4, h + 3.4), (-1.4, h + 4.6), (1.4, h + 4.6), (1.4, h + 3.4)]
    right = [(-x, z) for x, z in prof[2:9]][::-1]
    poly = prof + right + [(3.2, h + 1.4), (3.2, h + 0.6)]
    face_prism(mb, fg, poly, -0.6, 0.0, "render")
    fg2 = Face((0, d / 2 + 0.25, 0), (1, 0, 0), (0, 1, 0))
    arch(mb, fg2, 0.0, h + 2.4, 1.2, 1.9, "metal")             # the bell's opening
    revolve(mb, 0.0, d / 2 - 0.1, [(0.45, h + 2.6, "pot"), (0.35, h + 3.1, "pot"), (0.12, h + 3.5, "pot")], 8)
    fg.slab(mb, -1.6, 1.6, h + 4.6, h + 4.8, -0.7, 0.1, "render")
    # The tower at the east end.
    tx0, tx1 = w / 2 - 4.5, w / 2
    mb.box(tx0, tx1, y1 - 2.0, d / 2, -0.3, h + 5.0, "render")
    ft = Face(((tx0 + tx1) / 2, d / 2, 0), (1, 0, 0), (0, 1, 0))
    arch(mb, ft, 0.0, 1.0, 1.2, 2.4, "glass")
    arch(mb, ft, 0.0, h + 1.6, 1.6, 2.6, "metal")
    fs = Face((tx1, y1 - 1.0 + 1.5, 0), (0, -1, 0), (1, 0, 0))
    arch(mb, fs, 0.0, h + 1.6, 1.6, 2.6, "metal")
    tile_hip(mb, tx0, tx1, y1 - 2.0, d / 2, h + 5.0, 2.0, over=0.4)
    fb = back(w, d)
    for a in (-10.0, -6.0, -2.0, 2.0, 6.0, 10.0):
        ca_window(mb, fb, a, 0.9, 1.1, 1.6)
        ca_window(mb, fb, a, 4.8, 1.0, 1.6)
    tile_hip(mb, -w / 2, w / 2, -d / 2, y1, h, 2.6, over=0.7)
    return mb, (w, d, h + 5.0, 2.0)


def ca_lab():
    # A research park lab: two long low storeys, a recessed glass ground floor,
    # the upper floor wrapped in white sun fins over ribbon glazing, a timber
    # screen by the entrance (the roof colour), a pale roof with rows of solar
    # panels and plant behind a screen.
    w, d, storey = 30.0, 22.0, 4.2
    h = 2 * storey
    mb = Builder()
    mb.box(-w / 2 + 1.5, w / 2 - 1.5, -d / 2 + 1.5, d / 2 - 1.5, 0.0, storey, "curtain")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, storey, h, "render")
    for k in range(8):
        x = -w / 2 + 1.0 + k * (w - 2.0) / 7
        for y in (-d / 2 + 1.0, d / 2 - 1.0):
            mb.box(x - 0.2, x + 0.2, y - 0.2, y + 0.2, 0.0, storey, "frame")
    faces = [(front(w, d), w), (back(w, d), w), (left(w, d), d), (right(w, d), d)]
    for f, span in faces:
        f.slab(mb, -span / 2 + 0.6, span / 2 - 0.6, storey + 0.9, h - 0.8, -0.02, 0.03, "glass")
        n = int((span - 1.2) / 1.2)
        for k in range(n + 1):
            a = -span / 2 + 0.6 + k * (span - 1.2) / n
            f.slab(mb, a - 0.06, a + 0.06, storey + 0.5, h - 0.3, 0.0, 0.7, "frame")   # sun fins
        f.slab(mb, -span / 2, span / 2, h - 0.35, h, 0.0, 0.8, "frame")
    f = front(w, d)
    f.slab(mb, -9.0, -3.0, 0.0, storey + 0.2, 1.4, 1.6, "accent")          # the timber screen
    for k in range(13):
        f.slab(mb, -9.0 + k * 0.5, -8.85 + k * 0.5, 0.0, storey, 1.6, 1.7, "accent")
    f.slab(mb, -2.5, 2.5, 3.2, 3.5, 0.0, 3.0, "frame")                     # canopy
    f.slab(mb, -1.2, 1.2, 0.0, 2.6, 1.5, 1.55, "door")
    flat_top(mb, -w / 2, w / 2, -d / 2, d / 2, h, edge=0.3, up=0.45)
    for row in range(4):                                                   # solar panels
        y = -d / 2 + 3.0 + row * 3.4
        p = [(-w / 2 + 2.0, y, h + 0.3), (w / 2 - 9.0, y, h + 0.3), (w / 2 - 9.0, y + 2.2, h + 1.1),
             (-w / 2 + 2.0, y + 2.2, h + 1.1)]
        mb.hexa(p + [(q[0], q[1], q[2] + 0.08) for q in p], "metal")
    mb.box(w / 2 - 7.5, w / 2 - 1.5, -d / 2 + 2.5, d / 2 - 2.5, h, h + 2.0, "cladding")   # plant screen
    return mb, (w, d, h + 2.0, 0.0)


def terrace(variant="a"):
    # Three joined two-storey houses, each 5 m wide: door, a ground-floor window
    # (a bay on alternate houses), two windows upstairs; party-wall chimneys.
    # Variant b: flat fronts with door hoods, and a dormer on each house.
    w, d, h, rise = 15.0, 8.5, 6.2, 3.2
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    string_course(mb, w, d, 3.1, 0.14, 0.04)
    f, b = front(w, d), back(w, d)
    for k in range(3):
        cx = -5.0 + k * 5.0
        door(mb, f, cx + 1.6, w=0.95, steps=1)
        if variant == "b":
            door_hood(mb, f, cx + 1.6)
            window(mb, f, cx - 0.9, 0.95, 1.4, 1.5)
            y = d / 2 - 1.4
            dormer(mb, cx - 0.4, y, 1.5, 1.3, roof_height_at(y, d, h, rise) - 0.3)
        elif k % 2 == 0:
            bay(mb, f, cx - 0.9, 2.4, 0.6, 0.0, 2.95, 1, 3.0)
        else:
            window(mb, f, cx - 0.9, 0.95, 1.2, 1.5)
        window(mb, f, cx - 0.9, 3.75, 1.0, 1.45)
        window(mb, f, cx + 1.6, 3.75, 0.8, 1.45)
        window(mb, b, -cx + 0.9, 0.9, 1.0, 1.3, surround=False)
        window(mb, b, -cx - 1.4, 3.7, 0.9, 1.2, surround=False)
    gable_roof(mb, w, d, h, rise)
    for x in (-w / 2 + 0.45, -2.5, 2.5, w / 2 - 0.45):
        chimney(mb, x, 0.0, 0.8 if abs(x) < 3 else 0.7, 1.0, h + rise - 0.6, h + rise + 1.0, 4 if abs(x) < 3 else 2)
    return mb, (w, d, h, rise)


def tenement(storeys, variant="a"):
    # A Victorian sandstone tenement: rusticated ground floor with a central close
    # door, full-height canted bays, string courses, a cornice, a steep slate
    # roof with chimney stacks, and plainer windows at the back.
    # Variant b: flat-fronted with paired windows and wallhead dormers.
    w, d, rise = 22.0, 13.0, 4.8
    storey = 3.0
    ground = 3.4
    h = ground + (storeys - 1) * storey + 0.5
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d, 0.5)
    for k in range(5):                     # rustication grooves on the ground floor
        mb.box(-w / 2 - 0.03, w / 2 + 0.03, d / 2 - 0.01, d / 2 + 0.03, 0.55 + k * 0.6, 0.6 + k * 0.6, "stone")
    string_course(mb, w, d, ground - 0.1, 0.22, 0.08)
    for fl in range(2, storeys):
        string_course(mb, w, d, ground + (fl - 1) * storey - 0.05, 0.12, 0.04)
    mb.box(-w / 2 - 0.35, w / 2 + 0.35, -d / 2 - 0.35, d / 2 + 0.35, h - 0.35, h, "stone")    # cornice
    f, b = front(w, d), back(w, d)
    door(mb, f, 0.0, w=1.3, h=2.5, steps=2)
    for a in (-6.5, 6.5):
        if variant == "b":
            for pair in (-0.75, 0.75):
                window(mb, f, a + pair, 1.05, 1.0, 1.7)
                for fl in range(1, storeys):
                    window(mb, f, a + pair, ground + (fl - 1) * storey + 0.75, 1.0, 1.75)
        else:
            bay(mb, f, a, 3.6, 0.9, 0.5, h - 0.35, storeys, storey, cap="stone")
    for a in (-2.4, 2.4, -10.2, 10.2):
        if abs(a) > 10:
            window(mb, f, a, 1.05, 0.9, 1.7)
        for fl in range(1, storeys):
            window(mb, f, a, ground + (fl - 1) * storey + 0.75, 1.15, 1.75)
    for a in (-2.4, 2.4):
        window(mb, f, a, 1.05, 1.15, 1.7)
    for fl in range(storeys):
        z = (0.9 if fl == 0 else ground + (fl - 1) * storey + 0.7)
        for a in (-9.0, -5.0, -1.5, 1.5, 5.0, 9.0):
            window(mb, b, a, z, 1.0, 1.6, surround=False, lintel=False)
    gable_roof(mb, w, d, h, rise, over=0.15, skews=True)
    if variant == "b":
        for a in (-6.5, 6.5):
            front_gable(mb, 3.4, d, h, rise, a)
            window(mb, f, a, h + 0.05, 1.1, 1.25, surround=False)
    for x in (-w / 2 + 0.5, 0.0, w / 2 - 0.5):
        chimney(mb, x, 0.0, 1.0 if x == 0 else 0.8, 2.2, h + rise - 1.2, h + rise + 1.3, 6 if x == 0 else 4)
    for x in (-6.5, 6.5):                  # roof lights at the back
        y = -d / 2 + 2.2
        z = roof_height_at(y, d, h, rise)
        mb.box(x - 0.5, x + 0.5, y - 0.6, y + 0.6, z - 0.1, z + 0.12, "glass")
    return mb, (w, d, h, rise)


def roof_clutter(mb, w, d, z):
    """Things on a flat roof: a stair and lift housing, vents and roof lights."""
    mb.box(-w * 0.18, w * 0.02, -d * 0.1, d * 0.12, z, z + 2.4, "render")
    mb.box(-w * 0.18 - 0.1, w * 0.02 + 0.1, -d * 0.1 - 0.1, d * 0.12 + 0.1, z + 2.4, z + 2.55, "lead")
    for k in range(3):
        x = w * 0.15 + k * 1.6
        mb.box(x - 0.45, x + 0.45, -d * 0.25 - 0.45, -d * 0.25 + 0.45, z, z + 0.9, "metal")
    for k in range(2):
        x = -w * 0.32 + k * 3.2
        mb.box(x - 0.9, x + 0.9, d * 0.22 - 0.6, d * 0.22 + 0.6, z, z + 0.25, "glass")


def shopfront(mb, f, a0, a1, h_shop=3.6, awning=False):
    """A traditional shopfront: stall riser, big glass, painted pilasters, fascia and cornice."""
    w = a1 - a0
    f.slab(mb, a0 + 0.3, a1 - 0.3, 0.0, 0.6, 0.0, 0.12, "fascia")              # stall riser
    f.slab(mb, a0 + 0.3, a1 - 0.3, 0.6, 2.85, -0.03, 0.03, "display")
    f.slab(mb, a0 + w * 0.68, a0 + w * 0.68 + 1.0, 0.0, 2.85, -0.01, 0.04, "door")
    for a in (a0 + 0.3 + (w - 0.6) * k / 3 for k in (1, 2)):
        f.slab(mb, a - 0.04, a + 0.04, 0.6, 2.85, 0.0, 0.08, "fascia")          # mullions
    for a in (a0, a1 - 0.3):
        f.slab(mb, a, a + 0.3, 0.0, h_shop, 0.0, 0.18, "fascia")                # pilasters
    f.slab(mb, a0, a1, 2.85, h_shop - 0.25, 0.0, 0.2, "fascia")                 # fascia board
    f.slab(mb, a0 - 0.05, a1 + 0.05, h_shop - 0.25, h_shop, 0.0, 0.3, "frame")  # cornice
    if awning:
        p0 = f.point(a0 + 0.35, 0.2, 2.85)
        p1 = f.point(a1 - 0.35, 0.2, 2.85)
        p2 = f.point(a1 - 0.35, 1.5, 2.25)
        p3 = f.point(a0 + 0.35, 1.5, 2.25)
        t = 0.06
        mb.hexa([p0, p1, p2, p3, (p0[0], p0[1], p0[2] + t), (p1[0], p1[1], p1[2] + t),
                 (p2[0], p2[1], p2[2] + t), (p3[0], p3[1], p3[2] + t)], "awning")


def shop_parade(two_storey, variant="a"):
    # Shops along the street: one storey with a parapet, or two with flats above
    # and a slate roof. Variant b: three narrower shops, a raised centre on the
    # parapet, or dormers in the roof.
    w, d = 15.5, 13.0
    h = 7.0 if two_storey else 4.4
    rise = 3.0 if two_storey else 0.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "render")
    f, b = front(w, d), back(w, d)
    if variant == "b":
        for k in range(3):
            shopfront(mb, f, -w / 2 + 0.1 + k * (w - 0.2) / 3, -w / 2 + 0.1 + (k + 1) * (w - 0.2) / 3 - 0.1,
                      awning=(k != 1))
    else:
        shopfront(mb, f, -w / 2 + 0.1, -0.05, awning=True)
        shopfront(mb, f, 0.05, w / 2 - 0.1, awning=False)
    if two_storey:
        for a in (-5.6, -2.0, 2.0, 5.6):
            window(mb, f, a, 4.4, 1.0, 1.5)
        gable_roof(mb, w, d, h, rise, skews=False)
        if variant == "b":
            for x in (-3.8, 3.8):
                y = d / 2 - 1.5
                dormer(mb, x, y, 1.7, 1.3, roof_height_at(y, d, h, rise) - 0.3)
        for x in (-w / 2 + 0.45, w / 2 - 0.45):
            chimney(mb, x, 0.0, 0.7, 1.4, h + rise - 0.6, h + rise + 0.9, 3)
    else:
        mb.box(-w / 2, w / 2, -d / 2, d / 2, h, h + 0.6, "render")              # parapet
        mb.box(-w / 2 + 0.25, w / 2 - 0.25, -d / 2 + 0.25, d / 2 - 0.25, h + 0.1, h + 0.62, "lead")
        roof_clutter(mb, w, d, h + 0.62)
        if variant == "b":
            f.slab(mb, -2.5, 2.5, h + 0.6, h + 1.3, -0.2, 0.0, "render")        # raised centre
            f.slab(mb, -2.7, 2.7, h + 1.3, h + 1.45, -0.25, 0.05, "frame")
    for a in (-4.0, 4.0):
        window(mb, b, a, 1.0, 1.0, 1.3, surround=False)
    return mb, (w, d, h + (0.6 if not two_storey else 0.0), rise)


def shops_with_flats(storeys):
    # A sandstone block: three shopfronts on the ground floor, flats above with
    # tall windows, a cornice and a parapet over a flat roof.
    w, d = 23.0, 18.0
    ground = 3.8
    storey = 3.1
    h = ground + (storeys - 1) * storey + 0.4
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    f, b = front(w, d), back(w, d)
    unit = w / 3
    for k in range(3):
        shopfront(mb, f, -w / 2 + k * unit + 0.1, -w / 2 + (k + 1) * unit - 0.1, h_shop=ground, awning=(k == 1))
    for fl in range(1, storeys):
        z = ground + (fl - 1) * storey + 0.7
        string_course(mb, w, d, ground + (fl - 1) * storey - 0.1, 0.12, 0.04)
        for k in range(6):
            window(mb, f, -w / 2 + (k + 0.5) * w / 6, z, 1.15, 1.75)
        for k in range(5):
            window(mb, b, -w / 2 + (k + 0.5) * w / 5, z, 1.0, 1.5, surround=False, lintel=False)
    mb.box(-w / 2 - 0.3, w / 2 + 0.3, -d / 2 - 0.3, d / 2 + 0.3, h - 0.3, h, "stone")       # cornice
    mb.box(-w / 2, w / 2, -d / 2, d / 2, h, h + 0.7, "stone")                                # parapet
    mb.box(-w / 2 + 0.3, w / 2 - 0.3, -d / 2 + 0.3, d / 2 - 0.3, h + 0.1, h + 0.72, "lead")
    for x in (-7.0, 7.0):
        chimney(mb, x, -d / 2 + 3.0, 0.9, 1.6, h, h + 1.8, 4)
    roof_clutter(mb, w, d, h + 0.72)
    return mb, (w, d, h + 0.7, 0.0)


def shed():
    # A portal-frame industrial shed: ribbed metal walls over a brick base, a
    # shallow metal roof with roof lights, roller doors, a two-storey office at
    # the front corner and a gantry walkway.
    w, d, h, rise = 34.0, 28.0, 8.0, 2.2
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "cladding")
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.3, 1.4, "pot")       # brick base
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    for a in (-10.0, -2.0):
        f.slab(mb, a - 2.4, a + 2.4, 0.0, 5.2, 0.0, 0.08, "door")                 # roller doors
        f.slab(mb, a - 2.6, a + 2.6, 5.2, 5.5, 0.0, 0.18, "metal")
    for a in range(-14, 16, 4):
        f.slab(mb, a - 1.2, a + 1.2, 6.2, 7.2, -0.02, 0.03, "glass")           # high windows
        b.slab(mb, a - 1.2, a + 1.2, 6.2, 7.2, -0.02, 0.03, "glass")
    office = Face((9.0, d / 2, 0), (1, 0, 0), (0, 1, 0))
    office.slab(mb, -6.0, 6.0, 0.0, 7.2, 0.0, 3.5, "stone")
    for a in (-4.0, -1.3, 1.3, 4.0):
        for z in (1.0, 4.4):
            Face((9.0, d / 2 + 3.5, 0), (1, 0, 0), (0, 1, 0)).slab(mb, a - 1.0, a + 1.0, z, z + 1.5, -0.02, 0.03, "glass")
    Face((9.0, d / 2 + 3.5, 0), (1, 0, 0), (0, 1, 0)).slab(mb, -6.2, 6.2, 7.2, 7.5, -0.1, 0.1, "metal")
    sec = [(-d / 2 - 0.4, h - 0.1), (d / 2 + 0.4, h - 0.1), (d / 2 + 0.4, h + 0.1), (0.0, h + rise), (-d / 2 - 0.4, h + 0.1)]
    mb.extrude_x(sec, -w / 2 - 0.3, w / 2 + 0.3, "sheet")
    for x in range(-12, 14, 6):                                                # roof lights
        for side in (-1, 1):
            y = side * d * 0.22
            z = h + rise * (1 - abs(y) / (d / 2))
            mb.box(x - 1.2, x + 1.2, y - 2.5, y + 2.5, z - 0.05, z + 0.12, "glass")
    for x in (-w / 2 - 0.1, w / 2 + 0.1):
        mb.box(x - 0.12, x + 0.12, -d / 2, d / 2, h - 0.3, h, "metal")
    r.slab(mb, -6.0, 6.0, 3.0, 3.3, 0.0, 1.2, "metal")                          # gantry
    for k in range(4):
        r.slab(mb, -5.5 + k * 3.6, -5.3 + k * 3.6, 0.0, 3.0, 0.9, 1.1, "metal")
    return mb, (w, d, h, rise)


def works():
    # An old works: walls of brick or stone (the wall colour), a north-light
    # sawtooth roof of metal sheet (the roof colour) with glazing on the steep
    # faces, tall windows between piers, a big loading door, a brick office.
    w, d, h, rise = 34.0, 28.0, 6.0, 3.2
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    mb.box(-w / 2 - 0.15, w / 2 + 0.15, -d / 2 - 0.15, d / 2 + 0.15, h - 0.35, h, "stone")      # eaves course
    n = 5
    tooth = d / n
    for k in range(n):
        y0 = -d / 2 + k * tooth
        y1 = y0 + tooth
        mb.extrude_x([(y0, h), (y1, h), (y0 + 0.5, h + rise)], -w / 2 - 0.2, w / 2 + 0.2, "sheet")
        mb.extrude_x([(y0 - 0.06, h + 0.25), (y0 + 0.02, h + 0.25), (y0 + 0.5, h + rise - 0.25),
                      (y0 + 0.42, h + rise - 0.25)], -w / 2 + 0.4, w / 2 - 0.4, "glass")
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    for face, length in ((f, w), (b, w), (l, d), (r, d)):
        k = 0
        a = -length / 2 + 2.0
        while a < length / 2 - 1.5:
            if not (face is f and -9.0 < a < -3.0):
                face.slab(mb, a - 0.6, a + 0.6, 1.2, 4.6, -0.03, 0.02, "glass")
                face.slab(mb, a - 0.75, a + 0.75, 1.0, 1.2, 0.0, 0.12, "frame")
            face.slab(mb, a + 1.15, a + 1.85, 0.0, h - 0.35, 0.0, 0.2, "stone")             # pier
            a += 3.0
            k += 1
    f.slab(mb, -8.5, -3.5, 0.0, 4.6, 0.0, 0.1, "door")                                         # loading door
    f.slab(mb, -8.8, -3.2, 4.6, 5.0, 0.0, 0.25, "frame")
    office = Face((9.5, d / 2, 0), (1, 0, 0), (0, 1, 0))
    office.slab(mb, -5.5, 5.5, 0.0, 6.8, 0.0, 3.0, "pot")
    of = Face((9.5, d / 2 + 3.0, 0), (1, 0, 0), (0, 1, 0))
    for a in (-3.6, -1.2, 1.2, 3.6):
        for z in (0.9, 4.0):
            of.slab(mb, a - 0.6, a + 0.6, z, z + 1.6, -0.02, 0.03, "glass")
    of.slab(mb, -0.6, 0.6, 0.0, 2.4, -0.01, 0.04, "door")
    mb.box(9.5 - 5.7, 9.5 + 5.7, d / 2 - 0.2, d / 2 + 3.2, 6.8, 7.1, "stone")
    return mb, (w, d, h, rise)


def warehouse():
    # A modern distribution shed: tall clad walls (the wall colour) with dark corner
    # trims, a shallow metal roof (the roof colour) with roof lights, a row of
    # loading docks with coloured doors and black shelters, a glazed office pod.
    w, d, h = 40.0, 30.0, 11.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "cladding")
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, 0, 1.2, "render")        # plinth
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            mb.box(x - 0.25, x + 0.25, y - 0.25, y + 0.25, 0, h + 0.4, "metal")
    mb.box(-w / 2 - 0.1, w / 2 + 0.1, -d / 2 - 0.1, d / 2 + 0.1, h, h + 0.4, "metal")         # coping
    mb.box(-w / 2 + 0.1, w / 2 - 0.1, -d / 2 + 0.1, d / 2 - 0.1, h, h + 0.6, "sheet")         # roof
    for x in range(-15, 16, 6):
        for y in (-7.0, 0.0, 7.0):
            mb.box(x - 1.0, x + 1.0, y - 1.6, y + 1.6, h + 0.6, h + 0.75, "glass")
    f = front(w, d)
    for k in range(6):
        a = -17.0 + k * 3.8
        f.slab(mb, a - 1.5, a + 1.5, 1.2, 4.4, 0.0, 0.06, "door")
        f.slab(mb, a - 1.8, a + 1.8, 0.9, 4.8, 0.0, 0.5, "metal")                              # shelter
        f.slab(mb, a - 1.4, a + 1.4, 1.2, 4.3, 0.0, 0.52, "door")
    f.slab(mb, -19.5, 3.0, 5.3, 5.6, 0.0, 2.0, "metal")                                        # canopy
    pod = Face((13.5, d / 2, 0), (1, 0, 0), (0, 1, 0))
    pod.slab(mb, -5.5, 5.5, 0.0, 7.4, 0.0, 3.5, "render")
    pf = Face((13.5, d / 2 + 3.5, 0), (1, 0, 0), (0, 1, 0))
    ribbon(mb, pf, -5.2, 5.2, 1.0, 2.8, step=1.3)
    ribbon(mb, pf, -5.2, 5.2, 4.3, 6.1, step=1.3)
    mb.box(13.5 - 5.7, 13.5 + 5.7, d / 2 - 0.2, d / 2 + 3.7, 7.4, 7.7, "metal")
    return mb, (w, d, h + 0.75, 0.0)


def classical(storeys, kind):
    # The grand sandstone block (offices, mansion flats, civic buildings): a tall
    # rusticated ground floor (arched windows, or shopfronts), sash windows with
    # stone surrounds and pediments, string courses, full-height bays on flats,
    # a heavy cornice and a slate mansard roof with dormers and stacks.
    w, d = 21.0, 13.0
    ground, storey = 4.2, 3.4
    h = ground + (storeys - 1) * storey + 0.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d, 0.6)
    f, b = front(w, d), back(w, d)
    cols = max(4, int(w / 2.7))
    xs = [-w / 2 + (k + 0.5) * w / cols for k in range(cols)]
    if kind == "shops":
        unit = w / 3
        for k in range(3):
            shopfront(mb, f, -w / 2 + k * unit + 0.1, -w / 2 + (k + 1) * unit - 0.1, h_shop=ground - 0.2,
                      awning=(k == 1))
    else:
        for k in range(7):                       # rustication
            f.slab(mb, -w / 2, w / 2, 0.65 + k * 0.5, 0.71 + k * 0.5, 0.0, 0.03, "stone")
        door(mb, f, 0.0, w=1.6, h=2.8, steps=3)
        for x in xs:
            if abs(x) > 1.6:
                window(mb, f, x, 1.2, 1.2, 2.2, surround=True)
                f.slab(mb, x - 0.25, x + 0.25, 3.45, 3.85, 0.0, 0.12, "stone")    # keystone
    string_course(mb, w, d, ground - 0.15, 0.3, 0.1)
    bays = kind == "bays"
    for fl in range(1, storeys):
        z = ground + (fl - 1) * storey + 0.6
        if fl > 1:
            string_course(mb, w, d, z - 0.62, 0.12, 0.05)
        for k, x in enumerate(xs):
            if bays and (k in (1, 2, cols - 3, cols - 2)):
                continue
            window(mb, f, x, z, 1.1, 2.0)
            if fl == 1:
                # Pediments over the first-floor windows.
                p = [f.point(x - 0.85, 0.0, z + 2.3), f.point(x + 0.85, 0.0, z + 2.3), f.point(x, 0.0, z + 2.75),
                     f.point(x - 0.85, 0.2, z + 2.3), f.point(x + 0.85, 0.2, z + 2.3), f.point(x, 0.2, z + 2.75)]
                mb._add(p, [[0, 2, 1], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]], "stone")
        for x in xs[::2]:
            window(mb, b, x, z, 1.0, 1.8, surround=False, lintel=False)
    if bays:
        for a in (xs[1] + (xs[2] - xs[1]) / 2, xs[cols - 3] + (xs[cols - 2] - xs[cols - 3]) / 2):
            bay(mb, f, a, 3.6, 0.95, ground, h - 0.1, storeys - 1, storey, cap="stone")
    mb.box(-w / 2 - 0.5, w / 2 + 0.5, -d / 2 - 0.5, d / 2 + 0.5, h, h + 0.5, "stone")      # cornice
    mb.box(-w / 2 - 0.3, w / 2 + 0.3, -d / 2 - 0.3, d / 2 + 0.3, h + 0.5, h + 0.9, "stone")
    # Mansard: steep lower slopes and a flat top.
    m = 1.4
    z0, z1 = h + 0.9, h + 0.9 + 4.0
    pts = [(-w / 2, -d / 2, z0), (w / 2, -d / 2, z0), (w / 2, d / 2, z0), (-w / 2, d / 2, z0),
           (-w / 2 + m, -d / 2 + m, z1), (w / 2 - m, -d / 2 + m, z1), (w / 2 - m, d / 2 - m, z1), (-w / 2 + m, d / 2 - m, z1)]
    mb.hexa(pts, "roof")
    for x in xs[1::2]:
        y = d / 2 - 0.7
        dormer(mb, x, y + 0.5, 1.5, 1.8, z0 + 0.5, depth=1.6)
    for x in (-w / 2 + 1.0, w / 2 - 1.0):
        chimney(mb, x, 0.0, 1.0, 2.6, z1 - 0.2, z1 + 1.3, 6)
    return mb, (w, d, h + 0.9, 4.0)


def parapet(mb, w, d, z0, z1, t=0.3, mat="stone"):
    """A low wall round a flat roof (four thin walls, so the roof shows inside)."""
    mb.box(-w / 2, w / 2, d / 2 - t, d / 2, z0, z1, mat)
    mb.box(-w / 2, w / 2, -d / 2, -d / 2 + t, z0, z1, mat)
    mb.box(-w / 2, -w / 2 + t, -d / 2, d / 2, z0, z1, mat)
    mb.box(w / 2 - t, w / 2, -d / 2, d / 2, z0, z1, mat)


def gable_y(mb, x0, x1, y0, y1, z, rise, over=0.3, mat="roof"):
    """A roof whose gable faces the street: ridge running front to back."""
    cx, hw = (x0 + x1) / 2, (x1 - x0) / 2 + over
    mb.extrude_y([(cx - hw, z - 0.15), (cx + hw, z - 0.15), (cx + hw, z + 0.05), (cx, z + rise + 0.15),
                  (cx - hw, z + 0.05)], y0, y1 + over, mat)
    tri = [(x0, z - 0.01), (x1, z - 0.01), (cx, z + rise - 0.05)]
    mb.extrude_y(tri, y1 - 0.3, y1, "stone")                                   # the gable wall
    skew = [(x0 - 0.05, z + 0.05), (x1 + 0.05, z + 0.05), (cx, z + rise + 0.32)]
    mb.extrude_y(skew, y1 - 0.4, y1 + 0.05, "stone")                           # skew cope


def pyramid(mb, x, y, half, z0, z1, mat):
    pts = [(x - half, y - half, z0), (x + half, y - half, z0), (x + half, y + half, z0), (x - half, y + half, z0),
           (x, y, z1)]
    mb._add(pts, [[0, 3, 2, 1], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]], mat)


def mullions(mb, f, a0, a1, z0, z1, step, mat="metal", t=0.06, out=0.07):
    """Thin uprights across a stretch of glazing."""
    n = max(1, round((a1 - a0) / step))
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        f.slab(mb, a - t / 2, a + t / 2, z0, z1, 0.0, out, mat)


def fire_station():
    # A red sandstone station: three engine bays with red doors (drive-through,
    # so doors at the back too), stone piers, sign boards over the doors, the
    # crew rooms upstairs, a parapet with a raised centre and a flagpole.
    w, d, h = 34.0, 18.0, 9.5
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    for face, signs in ((f, True), (b, False)):
        for a in (-11.0, 0.0, 11.0):
            face.slab(mb, a - 3.8, a + 3.8, 0.0, 4.9, 0.0, 0.05, "accent")            # sectional door
            face.slab(mb, a - 3.6, a + 3.6, 3.3, 3.9, 0.05, 0.07, "glass")
            for z in (0.8, 1.6, 2.4, 4.4):
                face.slab(mb, a - 3.8, a + 3.8, z, z + 0.04, 0.05, 0.08, "metal")
            for side in (-1, 1):
                face.slab(mb, a + side * 3.9 - 0.06, a + side * 3.9 + 0.06, 0.0, 5.0, 0.0, 0.12, "metal")
            face.slab(mb, a - 3.95, a + 3.95, 4.9, 5.05, 0.0, 0.12, "metal")
            if signs:
                face.slab(mb, a - 3.0, a + 3.0, 5.2, 5.75, 0.3, 0.36, "frame")       # sign board
                face.slab(mb, a - 3.0, a + 3.0, 5.2, 5.28, 0.36, 0.38, "accent")
            for k in (-2.6, 0.0, 2.6):
                window(mb, face, a + k, 6.4, 1.3, 1.9)
        for a0, a1 in ((-17.0, -15.1), (-6.9, -4.1), (4.1, 6.9), (15.1, 17.0)):
            face.slab(mb, a0, a1, 0.0, 5.1, 0.0, 0.25, "stone")                      # piers
        face.slab(mb, -17.0, 17.0, 5.1, 5.85, 0.0, 0.3, "stone")                       # lintel band
    for side in (l, r):
        door(mb, side, 5.0, w=1.0, steps=1, fanlight=False)
        for a in (-5.0, -1.0):
            window(mb, side, a, 1.2, 1.2, 1.8)
        for a in (-5.0, -1.0, 3.0, 6.0):
            window(mb, side, a, 6.4, 1.2, 1.9)
    mb.box(-w / 2 - 0.3, w / 2 + 0.3, -d / 2 - 0.3, d / 2 + 0.3, h - 0.35, h, "stone")    # cornice
    parapet(mb, w, d, h, h + 0.8)
    mb.box(-w / 2 + 0.3, w / 2 - 0.3, -d / 2 + 0.3, d / 2 - 0.3, h - 0.05, h + 0.05, "lead")
    f.slab(mb, -4.5, 4.5, h, h + 1.8, -0.3, 0.0, "stone")                                # raised centre
    f.slab(mb, -4.7, 4.7, h + 1.8, h + 2.0, -0.4, 0.1, "stone")
    f.slab(mb, -1.4, 1.4, h + 0.3, h + 1.5, 0.0, 0.04, "frame")                          # name panel
    mb.cylinder(0.0, d / 2 - 0.6, 0.06, h + 2.0, h + 7.0, "metal", 6)                   # flagpole
    mb.box(0.05, 1.6, d / 2 - 0.62, d / 2 - 0.58, h + 6.0, h + 6.9, "accent")
    mb.box(-8.0, -4.0, -4.0, 0.0, h, h + 2.4, "render")                                  # stair housing
    mb.box(-8.1, -3.9, -4.1, 0.1, h + 2.4, h + 2.55, "lead")
    for x in (6.0, 8.0, 10.0):
        mb.box(x - 0.45, x + 0.45, -5.0, -4.1, h, h + 0.9, "metal")
    return mb, (w, d, h + 2.0, 0.0)


def fire_tower():
    # The hose drying and drill tower: a slim sandstone tower with slit windows
    # and an open louvred top where the hoses hang.
    w, d, h = 6.0, 6.0, 19.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    faces = (front(w, d), back(w, d), left(w, d), right(w, d))
    door(mb, faces[0], 0.0, w=1.1, steps=1, fanlight=False)
    for n, face in enumerate(faces):
        for z in (4.0, 8.0, 12.0, 16.0):
            if n == 0 or z > 4.0:
                window(mb, face, 0.0, z, 0.7, 2.0, bars=False)
        face.slab(mb, -w / 2 - 0.1, w / 2 + 0.1, h - 0.4, h, 0.0, 0.15, "stone")        # band
    mb.box(-w / 2 + 0.9, w / 2 - 0.9, -d / 2 + 0.9, d / 2 - 0.9, h, h + 2.6, "lead")   # dark inside
    for x in (-w / 2, w / 2 - 0.9):
        for y in (-d / 2, d / 2 - 0.9):
            mb.box(x, x + 0.9, y, y + 0.9, h, h + 2.6, "stone")                          # corner piers
    for face in faces:
        for k in range(6):
            z = h + 0.2 + k * 0.38
            face.slab(mb, -w / 2 + 0.9, w / 2 - 0.9, z, z + 0.16, -0.5, -0.4, "metal")  # louvres
    mb.box(-w / 2 - 0.35, w / 2 + 0.35, -d / 2 - 0.35, d / 2 + 0.35, h + 2.6, h + 3.0, "stone")
    pyramid(mb, 0.0, 0.0, w / 2 + 0.2, h + 3.0, h + 4.0, "lead")
    return mb, (w, d, h + 4.0, 0.0)


def school():
    # A Victorian board school in red sandstone: tall many-paned windows on two
    # floors, gabled wings at each end, a gabled entrance porch in the middle,
    # a steep slate roof with ridge ventilators, tall stacks and a bellcote.
    w, d, h, rise = 38.0, 13.0, 9.0, 4.5
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "stone")
    plinth(mb, w, d)
    string_course(mb, w, d, 4.3, 0.2, 0.06)
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)

    def tall_window(face, a, z, ww, hh):
        window(mb, face, a, z, ww, hh)
        face.slab(mb, a - ww / 2, a + ww / 2, z + hh * 0.72 - 0.04, z + hh * 0.72 + 0.04, 0.0, 0.07, "frame")
        for k in (-1, 1):
            face.slab(mb, a + k * ww / 4 - 0.025, a + k * ww / 4 + 0.025, z, z + hh, 0.0, 0.04, "frame")

    for a in (-10.5, -7.5, 7.5, 10.5):
        tall_window(f, a, 1.0, 1.9, 2.6)
        tall_window(f, a, 5.0, 1.9, 2.8)
    for a in range(-16, 17, 3):
        window(mb, b, a + 0.5, 1.0, 1.6, 2.4, surround=False)
        window(mb, b, a + 0.5, 5.0, 1.6, 2.5, surround=False)
    for side in (l, r):
        for a in (-3.0, 3.0):
            tall_window(side, a, 1.0, 1.7, 2.6)
            tall_window(side, a, 5.0, 1.7, 2.8)
    # Gabled wings at each end, standing forward of the main front.
    for cx in (-15.75, 15.75):
        x0, x1 = cx - 3.25, cx + 3.25
        mb.box(x0, x1, d / 2, d / 2 + 1.5, -0.3, h, "stone")
        wf = Face((cx, d / 2 + 1.5, 0), (1, 0, 0), (0, 1, 0))
        wf.slab(mb, -3.3, 3.3, 4.3, 4.5, 0.0, 0.06, "stone")
        for a in (-1.8, 0.0, 1.8):
            tall_window(wf, a, 1.0, 1.3, 2.6)
        for a in (-1.15, 1.15):
            tall_window(wf, a, 5.0, 1.6, 2.8)
        window(mb, wf, 0.0, h + 0.6, 1.0, 1.2, bars=False, sill=False)
        gable_y(mb, x0, x1, 0.0, d / 2 + 1.5, h, 3.3)
    # The entrance porch, with its own gable.
    mb.box(-4.0, 4.0, d / 2, d / 2 + 2.2, -0.3, h + 0.5, "stone")
    pf = Face((0.0, d / 2 + 2.2, 0), (1, 0, 0), (0, 1, 0))
    door(mb, pf, 0.0, w=1.8, h=2.8, steps=2)
    for a in (-0.9, 0.9):
        tall_window(pf, a, 5.0, 1.2, 2.6)
    pf.slab(mb, -1.0, 1.0, h - 0.6, h + 0.2, 0.0, 0.08, "frame")                         # date stone
    gable_y(mb, -4.0, 4.0, 0.0, d / 2 + 2.2, h + 0.5, 3.0)
    gable_roof(mb, w, d, h, rise)
    # Ridge ventilators, the bellcote and the stacks.
    top = h + rise
    for x in (-7.0, 7.0):
        mb.box(x - 0.5, x + 0.5, -0.5, 0.5, top - 0.2, top + 0.9, "metal")
        pyramid(mb, x, 0.0, 0.75, top + 0.9, top + 1.6, "lead")
    mb.box(-0.8, 0.8, -0.6, 0.6, top - 0.5, top + 0.4, "stone")
    for x in (-0.75, 0.45):
        mb.box(x, x + 0.3, -0.5, 0.5, top + 0.4, top + 1.9, "stone")
    mb.cylinder(0.0, 0.0, 0.28, top + 0.9, top + 1.45, "metal", 8)                       # the bell
    pyramid(mb, 0.0, 0.0, 0.95, top + 1.9, top + 3.0, "lead")
    for x in (-11.0, 11.0):
        chimney(mb, x, -1.5, 1.0, 1.8, roof_height_at(-1.5, d, h, rise) - 0.5, top + 1.8, 4)
    return mb, (w, d, h, rise)


def hospital():
    # A modern hospital: white panels with long bands of windows on six floors,
    # a glazed stair tower, a tall white pier carrying the red cross, a parapet,
    # roof plant at the back and the middle of the roof clear for the helipad.
    w, d = 34.0, 22.0
    floors, storey = 6, 3.2
    h = floors * storey + 0.6
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0, h, "render")
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.3, 0.6, "lead")
    faces = ((front(w, d), w), (back(w, d), w), (left(w, d), d), (right(w, d), d))
    for n, (face, length) in enumerate(faces):
        spans = [(-length / 2 + 1.2, length / 2 - 1.2)]
        if n == 0:
            spans = [(-length / 2 + 4.6, 8.6), (13.4, length / 2 - 1.2)]   # round the stair tower and the cross
        for fl in range(floors):
            z = 0.6 + fl * storey
            face.slab(mb, -length / 2 - 0.08, length / 2 + 0.08, z - 0.12, z + 0.18, 0.0, 0.08, "render")
            for a0, a1 in spans:
                face.slab(mb, a0, a1, z + 0.95, z + 2.65, -0.02, 0.02, "glass")
                face.slab(mb, a0 - 0.05, a1 + 0.05, z + 0.85, z + 0.95, 0.0, 0.14, "frame")
                mullions(mb, face, a0, a1, z + 0.95, z + 2.65, 1.5)
    f = faces[0][0]
    # Glazed stair tower at the left of the front.
    f.slab(mb, -16.6, -13.0, 0.0, h + 2.4, 0.0, 1.0, "render")
    f.slab(mb, -16.2, -13.4, 0.6, h + 1.8, 1.0, 1.03, "glass")
    for fl in range(floors + 1):
        f.slab(mb, -16.2, -13.4, 0.6 + fl * storey, 0.8 + fl * storey, 1.0, 1.08, "metal")
    mullions(mb, f, -16.2, -13.4, 0.6, h + 1.8, 1.4, out=1.08)
    # The pier and the red cross.
    f.slab(mb, 8.8, 13.2, 0.0, h + 1.0, 0.0, 0.5, "frame")
    f.slab(mb, 10.35, 11.65, h - 6.0, h - 1.8, 0.5, 0.6, "accent")
    for a0, a1 in ((8.9, 10.35), (11.65, 13.1)):
        f.slab(mb, a0, a1, h - 4.55, h - 3.25, 0.5, 0.6, "accent")
    # Roof: parapet, plant at the back, the helipad space left clear.
    parapet(mb, w, d, h, h + 1.0, 0.3, "render")
    mb.box(-w / 2 + 0.3, w / 2 - 0.3, -d / 2 + 0.3, d / 2 - 0.3, h - 0.05, h + 0.05, "lead")
    mb.box(8.5, 15.5, -10.0, -4.0, h, h + 3.0, "render")
    for k in range(5):
        x = 9.0 + k * 1.3
        mb.box(x, x + 0.9, -4.0, -3.9, h + 0.4, h + 2.6, "metal")                       # louvres
    for x in (10.0, 12.0, 14.0):
        mb.cylinder(x, -7.0, 0.35, h + 3.0, h + 5.0, "metal", 10)                       # flues
    return mb, (w, d, h + 1.0, 0.0)


# Modern blocks are stacked from storeys, so one set of models fits any height:
# a glazed ground floor, upper floors (two designs, and an all-glass one for
# offices and the best land), and a roof with a set-back penthouse.
MOD_W, MOD_D = 21.0, 13.0


def modern_base():
    w, d, h = MOD_W, MOD_D, 4.6
    mb = Builder()
    mb.box(-w / 2 + 0.3, w / 2 - 0.3, -d / 2 + 0.3, d / 2 - 0.3, -0.3, h - 0.35, "glass")
    for face, length in ((front(w, d), w), (back(w, d), w), (left(w, d), d), (right(w, d), d)):
        inner = Face(face.point(0, -0.3, 0), face.u, face.out)
        mullions(mb, inner, -length / 2 + 0.3, length / 2 - 0.3, 0.0, h - 0.35, 1.3)
        inner.slab(mb, -length / 2 + 0.3, length / 2 - 0.3, 3.0, 3.08, 0.0, 0.07, "metal")
        piers = 4 if length > 15 else 2
        for k in range(piers + 1):
            a = -length / 2 + length * k / piers
            a = max(-length / 2 + 0.3, min(length / 2 - 0.3, a))
            face.slab(mb, a - 0.3, a + 0.3, -0.3, h - 0.35, -0.6, 0.0, "cladding")
    mb.box(-w / 2 - 0.1, w / 2 + 0.1, -d / 2 - 0.1, d / 2 + 0.1, h - 0.35, h, "frame")
    f = front(w, d)
    f.slab(mb, -1.6, 1.6, 0.0, 2.6, -0.32, -0.25, "metal")                               # doors
    f.slab(mb, -1.5, 1.5, 0.05, 2.5, -0.25, -0.22, "glass")
    f.slab(mb, -3.2, 3.2, 3.0, 3.25, -0.3, 1.8, "frame")                                 # canopy
    return mb, (w, d, h, 0.0)


def _floor_slab(mb, w, d):
    mb.box(-w / 2 - 0.08, w / 2 + 0.08, -d / 2 - 0.08, d / 2 + 0.08, 0.0, 0.35, "frame")


def modern_floor(variant="a"):
    # a: wide glazed bays between clad bays with slot windows;
    # b: cladding with punched windows in deep light frames.
    w, d, h = MOD_W, MOD_D, 3.2
    mb = Builder()
    _floor_slab(mb, w, d)
    mb.box(-w / 2 + 0.05, w / 2 - 0.05, -d / 2 + 0.05, d / 2 - 0.05, 0.35, h, "cladding")
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)

    def glazed(face, a0, a1):
        face.slab(mb, a0 + 0.12, a1 - 0.12, 0.35, h, -0.06, -0.01, "glass")
        mullions(mb, face, a0 + 0.12, a1 - 0.12, 0.35, h, 1.2, out=0.02)
        face.slab(mb, a0 + 0.12, a1 - 0.12, 1.05, 1.11, -0.05, 0.02, "metal")

    def punched(face, a, ww):
        face.slab(mb, a - ww / 2, a + ww / 2, 0.75, h - 0.3, -0.06, -0.02, "glass")
        for a0, a1, z0, z1 in ((a - ww / 2 - 0.15, a - ww / 2, 0.6, h - 0.15), (a + ww / 2, a + ww / 2 + 0.15, 0.6, h - 0.15),
                               (a - ww / 2 - 0.15, a + ww / 2 + 0.15, 0.6, 0.75),
                               (a - ww / 2 - 0.15, a + ww / 2 + 0.15, h - 0.3, h - 0.15)):
            face.slab(mb, a0, a1, z0, z1, -0.05, 0.28, "frame")

    if variant == "b":
        for face, length, n in ((f, w, 7), (b, w, 6), (l, d, 3), (r, d, 3)):
            for k in range(n):
                punched(face, -length / 2 + (k + 0.5) * length / n, length / n * 0.62)
    else:
        bay = w / 6
        for k, kind in enumerate("GCGGCG"):
            a0 = -w / 2 + k * bay
            if kind == "G":
                glazed(f, a0, a0 + bay)
            else:
                f.slab(mb, a0 + 1.4, a0 + 2.0, 0.6, h - 0.2, -0.06, -0.02, "glass")    # slot window
        for k in range(6):
            if k % 2:
                glazed(b, -w / 2 + k * bay, -w / 2 + (k + 1) * bay)
        for side in (l, r):
            glazed(side, -2.2, 2.2)
    return mb, (w, d, h, 0.0)


def faces4(w, d):
    return ((front(w, d), w), (back(w, d), w), (left(w, d), d), (right(w, d), d))


def glass_floor():
    # Curtain walling: glass in the building's own tint (blue, green, bronze, silver)
    # in a grid of slim mullions, with a spandrel band at each floor in its second colour.
    w, d, h = MOD_W, MOD_D, 3.2
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, 0.8, "accent")
    mb.box(-w / 2 + 0.02, w / 2 - 0.02, -d / 2 + 0.02, d / 2 - 0.02, 0.8, h, "curtain")
    for face, length in faces4(w, d):
        mullions(mb, face, -length / 2, length / 2, 0.0, h, 1.5, t=0.08, out=0.1)
        face.slab(mb, -length / 2, length / 2, 0.76, 0.84, 0.0, 0.06, "metal")
    return mb, (w, d, h, 0.0)


def tower_stone():
    # A stone-clad office storey (art deco): stone piers running up between tall
    # windows set well back, a dark spandrel panel (second colour) under each.
    w, d, h = MOD_W, MOD_D, 3.2
    mb = Builder()
    mb.box(-w / 2 + 0.3, w / 2 - 0.3, -d / 2 + 0.3, d / 2 - 0.3, 0.0, h, "office")
    for face, length in faces4(w, d):
        n = max(3, round(length / 2.1))
        step = length / n
        for k in range(n + 1):
            a = -length / 2 + k * step
            half = 0.5 if k in (0, n) else 0.3
            face.slab(mb, max(-length / 2, a - half), min(length / 2, a + half), 0.0, h, -0.3, 0.14, "stone")
        for k in range(n):
            a0 = -length / 2 + k * step
            face.slab(mb, a0, a0 + step, 0.0, 0.3, -0.3, 0.02, "stone")
            face.slab(mb, a0 + 0.2, a0 + step - 0.2, 0.3, 1.0, -0.3, -0.16, "accent")
    return mb, (w, d, h, 0.0)


def tower_grid():
    # Precast concrete grid (the wall colour): deep frames round every bay, the
    # glass set well back, so the face reads as a strong square grid.
    w, d, h = MOD_W, MOD_D, 3.2
    mb = Builder()
    mb.box(-w / 2 + 0.55, w / 2 - 0.55, -d / 2 + 0.55, d / 2 - 0.55, 0.0, h, "office")
    for face, length in faces4(w, d):
        n = max(3, round(length / 1.9))
        step = length / n
        for k in range(n + 1):
            a = -length / 2 + k * step
            face.slab(mb, max(-length / 2, a - 0.22), min(length / 2, a + 0.22), 0.0, h, -0.55, 0.12, "render")
        face.slab(mb, -length / 2, length / 2, 0.0, 0.6, -0.55, 0.12, "render")
    return mb, (w, d, h, 0.0)


def tower_band():
    # A storey of flats: a band of render (the wall colour) under a strip of windows
    # in white frames, every third bay a coloured panel (the second colour).
    w, d, h = MOD_W, MOD_D, 3.2
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, 0.95, "render")
    mb.box(-w / 2 + 0.15, w / 2 - 0.15, -d / 2 + 0.15, d / 2 - 0.15, 0.95, h - 0.2, "glass")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, h - 0.2, h, "render")
    for face, length in faces4(w, d):
        n = max(3, round(length / 1.5))
        step = length / n
        for k in range(n + 1):
            a = -length / 2 + k * step
            face.slab(mb, max(-length / 2, a - 0.07), min(length / 2, a + 0.07), 0.95, h - 0.2, -0.15, -0.02, "frame")
        for k in range(n):
            if k % 3 == 1:
                a0 = -length / 2 + k * step
                face.slab(mb, a0 + 0.07, a0 + step - 0.07, 0.95, h - 0.2, -0.15, -0.03, "accent")
    return mb, (w, d, h, 0.0)


def beacon(mb, x, y, z, mast=0.0):
    """A red aviation light, on a short mast if mast > 0."""
    if mast > 0:
        mb.box(x - 0.08, x + 0.08, y - 0.08, y + 0.08, z, z + mast, "metal")
    mb.box(x - 0.45, x + 0.45, y - 0.45, y + 0.45, z + mast, z + mast + 0.7, "beacon")


def crown_plant():
    # A tower's roof: a parapet (second colour), a set-back screen of ribbed metal
    # louvres round the plant, a lift overrun, air handling units, aviation lights.
    w, d = MOD_W, MOD_D
    mb = Builder()
    mb.box(-w / 2 + 0.2, w / 2 - 0.2, -d / 2 + 0.2, d / 2 - 0.2, 0.0, 0.15, "lead")
    parapet(mb, w, d, 0.0, 1.2, 0.25, "accent")
    sw, sd = w * 0.56, d * 0.6
    mb.box(-sw / 2 - 1.0, sw / 2 - 1.0, -sd / 2 - 0.5, sd / 2 - 0.5, 0.0, 4.2, "cladding")
    mb.box(-sw / 2 - 1.2, sw / 2 - 0.8, -sd / 2 - 0.7, sd / 2 - 0.3, 4.2, 4.4, "metal")
    mb.box(w * 0.22, w * 0.36, -d * 0.2, d * 0.15, 0.0, 5.6, "frame")       # lift overrun
    for k in range(3):
        x = -w * 0.4 + k * 2.2
        mb.box(x, x + 1.6, d * 0.2, d * 0.38, 0.0, 1.4, "metal")
    beacon(mb, w / 2 - 0.6, d / 2 - 0.6, 1.2, 1.0)
    beacon(mb, -w / 2 + 0.6, -d / 2 + 0.6, 1.2, 1.0)
    return mb, (w, d, 5.6, 0.0)


def crown_deco():
    # An art deco top: the tower steps in three times in stone, each step edged with
    # floodlit trim, fins up the middle step, and a flagpole with a red light.
    w, d = MOD_W, MOD_D
    mb = Builder()
    steps = ((1.0, 1.0, 1.6), (0.78, 0.78, 4.2), (0.56, 0.58, 3.6), (0.34, 0.4, 3.0))
    z = 0.0
    for k, (fw, fd, sh) in enumerate(steps):
        sw, sd = w * fw, d * fd
        mb.box(-sw / 2, sw / 2, -sd / 2, sd / 2, z, z + sh, "stone")
        if k in (1, 2):
            for face, length in faces4(sw, sd):
                n = max(2, round(length / 2.2))
                for j in range(n):
                    a = -length / 2 + (j + 0.5) * length / n
                    face.slab(mb, a - 0.35, a + 0.35, z + 0.6, z + sh - 0.5, -0.02, 0.03, "office")
                    face.slab(mb, a - 0.75, a - 0.55, z, z + sh, 0.0, 0.25, "stone")
        parapet(mb, sw + 0.2, sd + 0.2, z + sh - 0.2, z + sh + 0.35, 0.2, "lamp")
        z += sh
    pyramid(mb, 0.0, 0.0, min(w * 0.34, d * 0.4) / 2, z, z + 2.4, "lead")
    mb.box(-0.1, 0.1, -0.1, 0.1, z + 2.0, z + 8.0, "metal")
    beacon(mb, 0.0, 0.0, z + 8.0)
    return mb, (w, d, z + 8.5, 0.0)


def crown_spire():
    # A landmark's top: a tapering glass crown with metal ribs and floodlit edge,
    # then a needle spire with a red light.
    w, d = MOD_W, MOD_D
    mb = Builder()
    mb.box(-w / 2 + 0.2, w / 2 - 0.2, -d / 2 + 0.2, d / 2 - 0.2, 0.0, 0.15, "lead")
    b, t, hh = (w * 0.42, d * 0.42), (w * 0.12, d * 0.16), 11.0
    mb.box(-b[0] - 0.15, b[0] + 0.15, -b[1] - 0.15, b[1] + 0.15, 0.0, 0.6, "lamp")
    mb.hexa([(-b[0], -b[1], 0.6), (b[0], -b[1], 0.6), (b[0], b[1], 0.6), (-b[0], b[1], 0.6),
             (-t[0], -t[1], hh), (t[0], -t[1], hh), (t[0], t[1], hh), (-t[0], t[1], hh)], "curtain")
    for sx in (-1, 1):
        for sy in (-1, 1):
            beam(mb, (sx * b[0], sy * b[1], 0.6), (sx * t[0], sy * t[1], hh), 0.3, "metal")
    mb.box(-t[0] - 0.1, t[0] + 0.1, -t[1] - 0.1, t[1] + 0.1, hh, hh + 0.4, "lamp")
    mb.box(-0.45, 0.45, -0.45, 0.45, hh, hh + 9.0, "frame")
    mb.box(-0.18, 0.18, -0.18, 0.18, hh + 9.0, hh + 22.0, "frame")
    beacon(mb, 0.0, 0.0, hh + 22.0)
    return mb, (w, d, hh + 22.5, 0.0)


def crown_slope():
    # A sloping glass top, low at the front and high at the back, with metal ribs,
    # a floodlit ridge and a red light at each end.
    w, d = MOD_W, MOD_D
    lo, hi = 1.5, 9.0
    mb = Builder()
    mb.extrude_x([(-d / 2, 0.0), (d / 2, 0.0), (d / 2, lo), (-d / 2, hi)], -w / 2, w / 2, "curtain")
    for k in range(7):
        x = -w / 2 + k * w / 6
        x = max(-w / 2 + 0.15, min(w / 2 - 0.15, x))
        beam(mb, (x, d / 2 + 0.05, lo + 0.05), (x, -d / 2 + 0.05, hi + 0.05), 0.2, "metal")
    mb.box(-w / 2, w / 2, -d / 2, -d / 2 + 0.3, hi - 0.1, hi + 0.25, "lamp")
    for x in (-w / 2 + 0.5, w / 2 - 0.5):
        beacon(mb, x, -d / 2 + 0.3, hi + 0.25, 0.8)
    return mb, (w, d, hi + 1.6, 0.0)


def modern_top():
    # The roof: a terrace edged in glass and a two-storey penthouse set back,
    # all glass with clad ends, under a thin projecting canopy.
    w, d = MOD_W, MOD_D
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.05, 0.15, "green")
    for x0, x1, y0, y1 in ((-w / 2, w / 2, d / 2 - 0.06, d / 2), (-w / 2, -w / 2 + 0.06, -d / 2, d / 2),
                           (w / 2 - 0.06, w / 2, -d / 2, d / 2), (-w / 2, w / 2, -d / 2, -d / 2 + 0.06)):
        mb.box(x0, x1, y0, y1, 0.15, 1.15, "glass")
        mb.box(x0 - 0.02, x1 + 0.02, y0 - 0.02, y1 + 0.02, 1.15, 1.2, "metal")
    pw, pd, py = w - 5.0, d - 4.0, -1.0
    mb.box(-pw / 2 + 0.4, pw / 2 - 0.4, py - pd / 2, py + pd / 2, 0.15, 6.4, "glass")
    for x in (-pw / 2, pw / 2 - 0.4):
        mb.box(x, x + 0.4, py - pd / 2, py + pd / 2, 0.15, 6.4, "cladding")
    mb.box(-pw / 2, pw / 2, py - pd / 2 - 0.05, py + pd / 2 + 0.05, 3.2, 3.45, "frame")
    pf = Face((0.0, py + pd / 2, 0), (1, 0, 0), (0, 1, 0))
    pb = Face((0.0, py - pd / 2, 0), (-1, 0, 0), (0, -1, 0))
    for face in (pf, pb):
        mullions(mb, face, -pw / 2 + 0.4, pw / 2 - 0.4, 0.15, 6.4, 1.6)
    mb.box(-(pw + 3.0) / 2, (pw + 3.0) / 2, py - (pd + 2.5) / 2, py + (pd + 2.5) / 2, 6.4, 6.62, "frame")
    mb.box(-(pw + 2.8) / 2, (pw + 2.8) / 2, py - (pd + 2.3) / 2, py + (pd + 2.3) / 2, 6.62, 6.85, "lead")
    return mb, (w, d, 6.85, 0.0)


# ------------------------------------------------- power stations and the rest

def revolve(mb, x, y, profile, sides=16, top=None):
    """A round solid (chimney, tank, cooling tower, dome) from a profile going up:
    [(radius, z, material), ...]; each band takes the material of the ring at its top,
    the bottom cap the first ring's. top: the top cap's material (default: the last band's)."""
    base = len(mb.verts)
    for r, z, _m in profile:
        mb.verts.extend((x + r * math.cos(2 * math.pi * k / sides), y + r * math.sin(2 * math.pi * k / sides), z)
                        for k in range(sides))

    def idx(i, k):
        return base + i * sides + k % sides

    mb.faces.append([idx(0, k) for k in range(sides)][::-1])
    mb.mats.append(MAT_INDEX[profile[0][2]])
    for i in range(1, len(profile)):
        for k in range(sides):
            mb.faces.append([idx(i - 1, k), idx(i - 1, k + 1), idx(i, k + 1), idx(i, k)])
            mb.mats.append(MAT_INDEX[profile[i][2]])
    mb.faces.append([idx(len(profile) - 1, k) for k in range(sides)])
    mb.mats.append(MAT_INDEX[top or profile[-1][2]])


def beam(mb, p0, p1, t, mat, t2=None):
    """A square-section member from p0 to p1 (girders, braces, sloping galleries)."""
    t2 = t if t2 is None else t2
    d = [p1[k] - p0[k] for k in range(3)]
    ln = math.sqrt(sum(c * c for c in d))
    d = [c / ln for c in d]
    up = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    a = (d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0])
    al = math.sqrt(sum(c * c for c in a))
    a = [c / al for c in a]
    b = (a[1] * d[2] - a[2] * d[1], a[2] * d[0] - a[0] * d[2], a[0] * d[1] - a[1] * d[0])

    def corner(p, sa, sb):
        return tuple(p[k] + a[k] * sa * t / 2 + b[k] * sb * t2 / 2 for k in range(3))

    ring = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    mb.hexa([corner(p0, sa, sb) for sa, sb in ring] + [corner(p1, sa, sb) for sa, sb in ring], mat)


def ribbon(mb, f, a0, a1, z0, z1, step=1.6, mat="glass"):
    """A band of glazing on a face with mullions and a sill."""
    f.slab(mb, a0, a1, z0, z1, -0.02, 0.03, mat)
    mullions(mb, f, a0, a1, z0, z1, step, t=0.08, out=0.08)
    f.slab(mb, a0 - 0.05, a1 + 0.05, z0 - 0.12, z0, 0.0, 0.12, "metal")


def flat_roof(mb, x0, x1, y0, y1, z, up=0.9, mat="cladding", t=0.3):
    """A flat roof with a coping round the edge (the walls' colour)."""
    mb.box(x0 + t, x1 - t, y0 + t, y1 - t, z - 0.05, z + 0.05, "lead")
    for bx0, bx1, by0, by1 in ((x0, x1, y1 - t, y1), (x0, x1, y0, y0 + t), (x0, x0 + t, y0 + t, y1 - t),
                               (x1 - t, x1, y0 + t, y1 - t)):
        mb.box(bx0, bx1, by0, by1, z, z + up, mat)


def transformer(mb, x, y):
    """A grid transformer: dark tank, radiator fins, bushings on top."""
    mb.box(x - 1.6, x + 1.6, y - 1.2, y + 1.2, 0.0, 3.2, "metal")
    for k in range(4):
        fx = x - 1.3 + k * 0.85
        mb.box(fx - 0.2, fx + 0.2, y + 1.2, y + 2.2, 0.4, 2.8, "lead")
    for k in range(3):
        mb.cylinder(x - 0.9 + k * 0.9, y, 0.14, 3.2, 4.6, "frame", 6)


def portal(mb, x0, x1, y, h):
    """A switchyard gantry: two lattice posts and a beam."""
    for x in (x0, x1):
        mb.box(x - 0.25, x + 0.25, y - 0.25, y + 0.25, 0.0, h, "frame")
    mb.box(x0 - 0.3, x1 + 0.3, y - 0.3, y + 0.3, h - 0.8, h, "frame")
    for k in range(3):
        xx = x0 + (x1 - x0) * (k + 1) / 4
        mb.cylinder(xx, y, 0.12, h - 2.2, h - 0.8, "frame", 6)


def coal_plant():
    # A big Scottish coal station (Cockenzie, Longannet): a long clad turbine hall
    # facing the road, the tall boiler house behind in the darker cladding,
    # the precipitator on stilts, twin concrete chimneys with dark tops, the coal
    # stockpile at the back fed up a sloping conveyor, and a switchyard in front.
    w, d = 44.0, 44.0
    mb = Builder()
    # Turbine hall.
    mb.box(-21.1, 6.1, 8.9, 21.1, -0.3, 2.0, "stone")
    mb.box(-21.0, 6.0, 9.0, 21.0, 2.0, 17.0, "cladding")
    hall = Face((0.0, 21.0, 0), (1, 0, 0), (0, 1, 0))
    ribbon(mb, hall, -20.0, 5.0, 12.4, 15.6, 2.5)
    ribbon(mb, hall, -20.0, -4.0, 3.2, 5.0, 2.0)
    hall.slab(mb, 0.0, 4.6, 0.0, 6.5, 0.0, 0.1, "sheet")                         # loading door
    hall.slab(mb, -0.2, 4.8, 6.5, 6.8, 0.0, 0.25, "metal")
    hall.slab(mb, -3.1, -1.9, 0.0, 2.3, 0.0, 0.06, "door")
    end = Face((-21.0, 15.0, 0), (0, -1, 0), (-1, 0, 0))
    ribbon(mb, end, -5.0, 5.0, 4.0, 15.5, 2.0)                                  # glazed gable end
    sec = [(8.6, 16.9), (21.4, 16.9), (21.4, 17.15), (15.0, 18.7), (8.6, 17.15)]
    mb.extrude_x(sec, -21.3, 6.3, "sheet")
    # Boiler house, with a band of louvres near the top and a stair tower.
    mb.box(-21.1, 3.1, -9.1, 8.9, -0.3, 2.0, "stone")
    mb.box(-21.0, 3.0, -9.0, 9.0, 2.0, 36.0, "sheet")
    for face, a0, a1 in ((Face((0.0, 9.0, 0), (1, 0, 0), (0, 1, 0)), -20.0, 2.0),
                         (Face((0.0, -9.0, 0), (-1, 0, 0), (0, -1, 0)), -2.0, 20.0),
                         (Face((-21.0, 0.0, 0), (0, -1, 0), (-1, 0, 0)), -8.0, 8.0),
                         (Face((3.0, 0.0, 0), (0, 1, 0), (1, 0, 0)), -8.0, 2.0)):
        ribbon(mb, face, a0, a1, 31.0, 34.0, 1.2)
        face.slab(mb, a0 - 1.0, a1 + 1.0, 21.0, 21.4, 0.0, 0.1, "cladding")      # string of light cladding
    flat_roof(mb, -21.0, 3.0, -9.0, 9.0, 36.0, 0.8)
    for x in (-15.0, -9.0):
        mb.box(x - 1.5, x + 1.5, -3.0, 3.0, 36.0, 38.5, "cladding")             # roof vents
        mb.box(x - 1.7, x + 1.7, -3.2, 3.2, 38.5, 38.8, "metal")
    mb.box(3.0, 6.5, 3.0, 8.5, 0.0, 39.0, "cladding")                           # stair tower
    stair = Face((6.5, 5.75, 0), (0, -1, 0), (1, 0, 0))
    for z in range(4, 37, 4):
        stair.slab(mb, -0.4, 0.4, z, z + 2.0, -0.02, 0.03, "glass")
    mb.box(2.9, 6.6, 2.9, 8.6, 39.0, 39.3, "metal")
    # Precipitator on legs, ducts from the boiler and to the chimneys.
    mb.box(5.0, 14.0, -9.0, 1.0, 6.0, 18.0, "cladding")
    mb.box(4.8, 14.2, -9.2, 1.2, 18.0, 18.4, "metal")
    for x in (7.25, 11.75):
        for y in (-6.5, -1.5):
            mb._add([(x - 2.2, y - 2.4, 6.0), (x + 2.2, y - 2.4, 6.0), (x + 2.2, y + 2.4, 6.0), (x - 2.2, y + 2.4, 6.0),
                     (x, y, 3.2)], [[0, 1, 2, 3], [1, 0, 4], [2, 1, 4], [3, 2, 4], [0, 3, 4]], "sheet")
    for x in (5.3, 9.5, 13.7):
        for y in (-8.7, 0.7):
            mb.box(x - 0.3, x + 0.3, y - 0.3, y + 0.3, 0.0, 6.0, "metal")
    mb.box(3.0, 5.0, -7.0, -1.0, 21.0, 25.0, "cladding")
    mb.box(14.0, 16.2, -5.0, -1.5, 9.0, 12.0, "cladding")
    mb.box(14.0, 16.2, -9.0, -6.5, 9.0, 12.0, "cladding")
    mb.box(16.2, 18.5, -12.0, -6.5, 9.0, 12.0, "cladding")
    # Twin chimneys: tapering concrete with dark tops and a cap.
    for y in (-3.2, -13.5):
        revolve(mb, 18.5, y, [(2.6, -0.3, "render"), (1.95, 61.5, "render"), (1.95, 65.0, "lead"),
                              (2.2, 65.0, "metal"), (2.2, 66.0, "metal")], 14)
    # Coal stockpile, the sloping conveyor and its transfer tower.
    mb.hexa([(-20.5, -21.6, -0.2), (12.5, -21.6, -0.2), (12.5, -12.6, -0.2), (-20.5, -12.6, -0.2),
             (-16.0, -18.8, 5.0), (8.5, -18.8, 5.0), (8.5, -15.4, 5.0), (-16.0, -15.4, 5.0)], "metal")
    mb.box(-21.0, -16.0, -13.5, -9.0, 0.0, 21.0, "cladding")
    mb.box(-21.2, -15.8, -13.7, -8.8, 21.0, 21.3, "metal")
    beam(mb, (4.0, -11.2, 1.6), (-16.0, -11.2, 15.0), 2.4, "cladding", 2.6)
    for x, z in ((-1.0, 4.9), (-8.0, 9.6)):
        for y in (-12.2, -10.2):
            mb.box(x - 0.2, x + 0.2, y - 0.2, y + 0.2, 0.0, z, "metal")
    mb.box(2.0, 6.0, -13.0, -9.4, 0.0, 2.8, "cladding")                         # reclaim hopper
    # Switchyard in front.
    for y in (11.5, 18.5):
        portal(mb, 9.5, 20.5, y, 11.0)
    for x in (11.5, 15.0, 18.5):
        transformer(mb, x, 14.6)
    return mb, (w, d, 66.0, 0.0)


def gas_plant():
    # A combined-cycle gas station: a modern clad turbine hall with a glazed
    # office end, two heat-recovery boilers behind with slim steel stacks, a
    # Victorian-style gasholder in its guide frame, a fuel tank, pipe racks and
    # transformers.
    w, d = 44.0, 44.0
    mb = Builder()
    # Turbine hall: light cladding, a coloured band, a curved roof.
    mb.box(-21.0, 5.0, 7.0, 20.0, -0.3, 1.0, "lead")
    mb.box(-21.0, 5.0, 7.0, 20.0, 1.0, 15.0, "cladding")
    for face, length, c in ((Face((-8.0, 20.0, 0), (1, 0, 0), (0, 1, 0)), 26.0, 0.0),
                            (Face((-8.0, 7.0, 0), (-1, 0, 0), (0, -1, 0)), 26.0, 0.0),
                            (Face((5.0, 13.5, 0), (0, -1, 0), (1, 0, 0)), 13.0, 0.0)):
        face.slab(mb, -length / 2 - 0.05, length / 2 + 0.05, 11.6, 12.8, 0.0, 0.06, "accent")
        ribbon(mb, face, -length / 2 + 1.0, length / 2 - 1.0, 13.2, 14.4, 1.8)
    hall = Face((0.0, 20.0, 0), (1, 0, 0), (0, 1, 0))
    hall.slab(mb, -3.0, 2.0, 0.0, 7.0, 0.0, 0.1, "sheet")
    hall.slab(mb, -3.2, 2.2, 7.0, 7.3, 0.0, 0.3, "metal")
    arc = [(7.0 + 13.0 * k / 8, 15.0 + 2.6 * math.sin(math.pi * k / 8)) for k in range(9)]
    sec = [(6.6, 14.85)] + [(y, z + 0.2) for y, z in arc[1:-1]] + [(20.4, 14.85), (20.4, 15.1)] + \
        [(y, z + 0.45) for y, z in arc[-2:0:-1]] + [(6.6, 15.1)]
    mb.extrude_x(sec, -21.3, 5.3, "sheet")
    # The glazed office at the left end of the front.
    mb.box(-21.0, -11.0, 20.0, 23.0, 0.0, 8.0, "glass")
    of = Face((-16.0, 23.0, 0), (1, 0, 0), (0, 1, 0))
    mullions(mb, of, -5.0, 5.0, 0.0, 8.0, 1.25, t=0.1, out=0.1)
    of.slab(mb, -5.0, 5.0, 3.85, 4.15, 0.0, 0.12, "metal")
    mb.box(-21.4, -10.6, 19.8, 23.6, 8.0, 8.5, "frame")
    of.slab(mb, -1.0, 1.0, 0.0, 2.4, 0.0, 0.05, "door")
    # Two heat-recovery boilers, ducts from the hall, and their stacks.
    for cx in (-15.5, -2.5):
        mb.box(cx - 4.5, cx + 4.5, -15.0, 5.0, 0.0, 24.0, "cladding")
        mb.box(cx - 4.7, cx + 4.7, -15.2, 5.2, 24.0, 24.4, "metal")
        for z in (8.0, 16.0):
            mb.box(cx - 4.6, cx + 4.6, -15.1, 5.1, z, z + 0.5, "sheet")
        mb.box(cx - 3.0, cx + 3.0, 5.0, 7.0, 4.0, 12.0, "cladding")
        for y in (-12.0, -5.0, 2.0):
            mb.box(cx + 4.5, cx + 5.3, y - 0.5, y + 0.5, 0.0, 24.0, "metal")        # stair columns
        revolve(mb, cx, -17.5, [(1.7, 0.0, "render"), (1.5, 44.0, "render"), (1.5, 45.5, "metal"),
                                (1.65, 46.0, "metal")], 12)
        revolve(mb, cx, -17.5, [(2.3, 32.0, "metal"), (2.3, 32.3, "metal")], 12)   # platform
        mb.box(cx - 1.0, cx + 1.0, -16.6, -15.0, 18.0, 21.0, "cladding")
    # Gasholder: the bell inside a ring of columns with girders and bracing.
    gx, gy, gr = 12.5, -9.5, 8.0
    revolve(mb, gx, gy, [(gr, -0.2, "cladding"), (gr, 11.0, "cladding"), (gr - 1.2, 12.3, "lead"),
                         (gr - 4.0, 12.9, "lead")], 24)
    cols = 10
    pts = [(gx + (gr + 0.8) * math.cos(2 * math.pi * k / cols), gy + (gr + 0.8) * math.sin(2 * math.pi * k / cols))
           for k in range(cols)]
    for px, py in pts:
        mb.box(px - 0.3, px + 0.3, py - 0.3, py + 0.3, 0.0, 17.0, "metal")
    for k in range(cols):
        (ax, ay), (bx, by) = pts[k], pts[(k + 1) % cols]
        for z in (9.0, 16.6):
            beam(mb, (ax, ay, z), (bx, by, z), 0.35, "metal", 0.6)
        beam(mb, (ax, ay, 9.0), (bx, by, 16.6), 0.2, "metal")
    # Fuel oil tank, pipe rack and transformers.
    revolve(mb, 14.5, 10.5, [(4.0, 0.0, "frame"), (4.0, 7.0, "frame"), (0.6, 8.2, "frame")], 16)
    mb.box(9.8, 19.2, 5.8, 15.2, 0.0, 0.8, "render")                            # bund wall
    mb.box(10.2, 18.8, 6.2, 14.8, 0.6, 0.7, "lead")
    for x in (6.0, 9.0):
        mb.box(x - 0.2, x + 0.2, 1.8, 2.2, 0.0, 4.5, "metal")
    pipe = [(2.0 + 0.35 * math.cos(2 * math.pi * k / 6), 5.0 + 0.35 * math.sin(2 * math.pi * k / 6)) for k in range(6)]
    mb.extrude_x(pipe, 5.0, 12.0, "frame")
    pipe = [(2.0 + 0.25 * math.cos(2 * math.pi * k / 6), 4.6 + 0.25 * math.sin(2 * math.pi * k / 6)) for k in range(6)]
    mb.extrude_x(pipe, 5.0, 12.0, "accent")
    mb.box(5.0, 10.0, 1.5, 2.5, 4.35, 4.5, "metal")
    for x in (8.5, 12.5):
        transformer(mb, x, 18.0)
    portal(mb, 15.5, 21.0, 18.0, 10.0)
    return mb, (w, d, 46.0, 0.0)


def nuclear_plant():
    # A nuclear station: the domed concrete containment, an auxiliary block, a
    # turbine hall in two-tone cladding, a slim vent stack, a gatehouse, and two
    # hyperbolic cooling towers at the back.
    w, d = 46.0, 46.0
    mb = Builder()
    for cx in (-12.0, 12.0):
        prof = [(10.4, -0.3, "lead"), (10.4, 2.2, "lead"), (10.2, 2.2, "render")]
        for k in range(1, 9):
            z = 2.2 + 41.8 * k / 8
            t = z / 44.0
            r = 6.6 + 3.6 * ((0.78 - t) / 0.73) ** 1.6 if t < 0.78 else 6.6 + 1.1 * ((t - 0.78) / 0.22) ** 2
            prof.append((r, z, "render"))
        revolve(mb, cx, -11.8, prof, 22, top="lead")
    # Containment: cylinder and dome.
    rx, ry, rr = -12.0, 9.5, 8.0
    prof = [(rr, -0.3, "render"), (rr, 18.0, "render")]
    for k in range(1, 6):
        a = math.pi / 2 * k / 6
        prof.append((rr * math.cos(a), 18.0 + rr * 0.85 * math.sin(a), "render"))
    revolve(mb, rx, ry, prof, 20)
    revolve(mb, rx, ry, [(rr + 0.15, 0.0, "lead"), (rr + 0.15, 1.2, "lead")], 20)
    mb.box(rx + 6.0, rx + 9.2, ry - 2.0, ry + 2.0, 0.0, 7.0, "cladding")          # equipment hatch
    # Auxiliary block between the containment and the cooling towers.
    mb.box(-22.0, -2.0, 0.0, 5.0, -0.3, 13.0, "render")
    aux = Face((-12.0, 0.0, 0), (-1, 0, 0), (0, -1, 0))
    for z in (4.0, 9.0):
        ribbon(mb, aux, -9.0, 9.0, z, z + 1.4, 1.8)
    flat_roof(mb, -22.0, -2.0, 0.0, 5.0, 13.0, 0.6, "render")
    # Turbine hall.
    mb.box(0.0, 22.0, 5.0, 21.0, -0.3, 7.0, "cladding")
    mb.box(0.0, 22.0, 5.0, 21.0, 7.0, 16.0, "sheet")
    th = Face((11.0, 21.0, 0), (1, 0, 0), (0, 1, 0))
    ribbon(mb, th, -10.0, 10.0, 5.0, 6.6, 2.0)
    th.slab(mb, -2.5, 2.5, 0.0, 4.6, 0.0, 0.1, "metal")
    side = Face((22.0, 13.0, 0), (0, -1, 0), (1, 0, 0))
    ribbon(mb, side, -7.0, 7.0, 10.0, 14.5, 1.75)
    flat_roof(mb, 0.0, 22.0, 5.0, 21.0, 16.0, 0.7, "cladding")
    for x in (5.0, 11.0, 17.0):
        mb.box(x - 1.2, x + 1.2, 10.0, 16.0, 16.0, 17.6, "metal")
    mb.box(-4.5, 0.0, 7.5, 12.5, 0.0, 10.0, "cladding")                          # link to the reactor
    # Vent stack and the gatehouse.
    revolve(mb, -1.0, 1.5, [(1.1, 0.0, "render"), (0.85, 46.0, "render"), (0.85, 47.5, "metal")], 10)
    mb.box(-22.0, -15.0, 19.0, 22.5, 0.0, 3.8, "render")
    gate = Face((-18.5, 22.5, 0), (1, 0, 0), (0, 1, 0))
    ribbon(mb, gate, -3.0, 3.0, 1.0, 3.0, 1.5)
    mb.box(-22.4, -14.6, 18.6, 23.4, 3.8, 4.2, "frame")
    return mb, (w, d, 47.5, 0.0)


def clubhouse():
    # A modern clubhouse (golf club, sailing club): white render, long glazing,
    # a set-back first-floor lounge in glass with timber-clad ends (accent), flat
    # roofs with thin projecting edges, a terrace with a glass balustrade.
    w, d = 18.0, 11.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, -0.3, 3.6, "render")
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    ribbon(mb, f, -8.0, -2.5, 0.8, 2.9, 1.4)
    ribbon(mb, f, 3.0, 8.0, 0.8, 2.9, 1.25)
    f.slab(mb, -1.4, 1.4, 0.0, 2.9, -0.02, 0.03, "glass")                         # entrance
    f.slab(mb, -0.6, 0.6, 0.0, 2.4, 0.03, 0.06, "door")
    f.slab(mb, -2.6, 2.6, 2.95, 3.15, 0.0, 2.0, "frame")                          # canopy
    for a0, a1 in ((-2.5, -1.4), (1.4, 3.0)):
        f.slab(mb, a0, a1, 0.0, 3.6, 0.0, 0.06, "accent")                         # timber panels
    ribbon(mb, b, -8.4, 8.4, 0.3, 3.0, 1.4)                                       # to the course
    for side in (l, r):
        ribbon(mb, side, -3.5, 3.5, 0.8, 2.9, 1.4)
    mb.box(-w / 2 - 0.4, w / 2 + 0.4, -d / 2 - 0.6, d / 2 + 0.4, 3.6, 3.9, "frame")
    # The lounge upstairs, over the left part, with the terrace beside it.
    lx0, lx1, ly0, ly1 = -8.5, 1.5, -5.5, 3.5
    mb.box(lx0 + 0.6, lx1 - 0.6, ly0 + 0.3, ly1, 3.9, 7.0, "glass")
    for x0, x1 in ((lx0, lx0 + 0.6), (lx1 - 0.6, lx1)):
        mb.box(x0, x1, ly0, ly1, 3.9, 7.0, "accent")
    for face in (Face((-3.5, ly1, 0), (1, 0, 0), (0, 1, 0)), Face((-3.5, ly0 + 0.3, 0), (-1, 0, 0), (0, -1, 0))):
        mullions(mb, face, -4.4, 4.4, 3.9, 7.0, 1.5)
    mb.box(lx0 - 0.8, lx1 + 1.2, ly0 - 1.2, ly1 + 0.6, 7.0, 7.3, "frame")
    for x0, x1, y0, y1 in ((lx1, w / 2 - 0.1, -d / 2 + 0.1, -d / 2 + 0.16), (w / 2 - 0.16, w / 2 - 0.1, -d / 2 + 0.1, d / 2 - 0.1),
                           (lx1, w / 2 - 0.1, d / 2 - 0.16, d / 2 - 0.1)):
        mb.box(x0, x1, y0, y1, 3.9, 4.95, "glass")                               # balustrade
        mb.box(x0 - 0.03, x1 + 0.03, y0 - 0.03, y1 + 0.03, 4.95, 5.02, "metal")
    mb.box(5.0, 7.0, -1.0, 1.0, 3.9, 4.6, "metal")                                # plant
    return mb, (w, d, 7.3, 0.0)


def museum_wing():
    # The museum's modern glass wing: a two-storey glass box on a stone plinth,
    # a solid stone back, slim mullions, the floor showing through, and a thin
    # white roof slab oversailing on slim columns.
    w, d = 12.0, 16.0
    mb = Builder()
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.3, 0.5, "stone")
    mb.box(-w / 2, w / 2, -d / 2, -d / 2 + 3.0, 0.5, 8.6, "stone")                  # stone back
    mb.box(-w / 2 + 0.25, w / 2 - 0.25, -d / 2 + 3.0, d / 2 - 0.25, 0.5, 8.6, "glass")
    gl = [(Face((0.0, d / 2 - 0.25, 0), (1, 0, 0), (0, 1, 0)), -w / 2 + 0.25, w / 2 - 0.25),
          (Face((-w / 2 + 0.25, 1.5, 0), (0, -1, 0), (-1, 0, 0)), -6.25, 6.25),
          (Face((w / 2 - 0.25, 1.5, 0), (0, 1, 0), (1, 0, 0)), -6.25, 6.25)]
    for face, a0, a1 in gl:
        mullions(mb, face, a0, a1, 0.5, 8.6, 1.4, t=0.07, out=0.08)
        face.slab(mb, a0, a1, 4.45, 4.75, -0.02, 0.06, "frame")                    # first floor
    f = gl[0][0]
    f.slab(mb, -1.2, 1.2, 0.5, 2.9, 0.08, 0.1, "door")
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        mb.box(x - 0.1, x + 0.1, d / 2 + 0.6, d / 2 + 0.8, 0.0, 8.6, "metal")       # columns
    mb.box(-w / 2 - 0.9, w / 2 + 0.9, -d / 2 - 0.3, d / 2 + 1.3, 8.6, 9.0, "frame")
    mb.box(-2.0, 2.0, -d / 2 + 0.5, -d / 2 + 2.5, 9.0, 9.4, "lead")                  # roof light
    return mb, (w, d, 9.0, 0.0)


def stand():
    # A football stand: concrete terracing with seats in the team colour
    # (accent), a clad back wall and ends, and a cantilevered roof (sheet).
    # The front (+y) faces the pitch.
    w, d = 42.0, 6.0
    mb = Builder()
    steps = 9
    for k in range(steps):
        y1 = d / 2 - k * d / steps
        z = 1.0 + k * 0.85
        mb.box(-w / 2 + 0.4, w / 2 - 0.4, -d / 2, y1, -0.3, z, "render")
        mb.box(-w / 2 + 0.4, w / 2 - 0.4, y1 - 0.42, y1 - 0.1, z, z + 0.4, "accent")      # seats
    for x in range(-18, 19, 9):
        mb.box(x - 0.6, x + 0.6, d / 2 - 0.2, d / 2 + 0.02, -0.3, 0.95, "metal")          # vomitories
    mb.box(-w / 2, w / 2, -d / 2 - 0.4, -d / 2, -0.3, 11.0, "cladding")               # back wall
    for x in (-w / 2, w / 2 - 0.4):
        mb._add([(x, -d / 2, -0.3), (x + 0.4, -d / 2, -0.3), (x + 0.4, d / 2, -0.3), (x, d / 2, -0.3),
                 (x, -d / 2, 11.0), (x + 0.4, -d / 2, 11.0), (x + 0.4, d / 2 + 0.5, 11.0), (x, d / 2 + 0.5, 11.0)],
                [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]], "cladding")
    mb.box(-w / 2 - 0.6, w / 2 + 0.6, -d / 2 - 1.0, d / 2 + 2.5, 11.0, 11.5, "sheet")
    mb.box(-w / 2 - 0.6, w / 2 + 0.6, d / 2 + 2.2, d / 2 + 2.5, 10.4, 11.0, "frame")    # fascia
    for x in range(-18, 19, 12):
        beam(mb, (x, -d / 2 - 0.5, 11.5), (x, d / 2 + 2.4, 11.5), 0.3, "metal", 0.6)
        beam(mb, (x, -d / 2 - 0.5, 14.0), (x, d / 2 + 2.4, 11.6), 0.25, "metal")
        mb.box(x - 0.2, x + 0.2, -d / 2 - 0.7, -d / 2 - 0.3, 11.0, 14.2, "metal")
    return mb, (w, d, 11.5, 0.0)


def water_tower():
    # A concrete water tower: a tapering shaft with a door and slit windows,
    # the tank on a conical base with a walkway round it, and a shallow roof.
    w = d = 16.0
    mb = Builder()
    revolve(mb, 0.0, 0.0, [(2.9, -0.3, "render"), (2.4, 24.0, "render"), (7.6, 27.8, "render"),
                           (7.6, 34.0, "frame"), (7.9, 34.0, "frame"), (7.9, 34.5, "frame"),
                           (1.2, 35.8, "lead")], 20)
    revolve(mb, 0.0, 0.0, [(8.5, 27.5, "metal"), (8.5, 27.8, "metal")], 20)        # walkway
    for k in range(20):
        a = 2 * math.pi * k / 20
        mb.box(8.4 * math.cos(a) - 0.04, 8.4 * math.cos(a) + 0.04, 8.4 * math.sin(a) - 0.04,
               8.4 * math.sin(a) + 0.04, 27.8, 28.9, "metal")
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        f = Face((2.75 * math.cos(a), 2.75 * math.sin(a), 0), (-math.sin(a), math.cos(a), 0), (math.cos(a), math.sin(a), 0))
        for z in (6.0, 12.0, 18.0):
            f.slab(mb, -0.2, 0.2, z, z + 2.2, -0.15, 0.05, "glass")
    f = Face((0.0, 2.85, 0), (1, 0, 0), (0, 1, 0))
    f.slab(mb, -0.6, 0.6, 0.0, 2.3, -0.1, 0.1, "door")
    f.slab(mb, -0.9, 0.9, 2.3, 2.5, -0.1, 0.5, "frame")
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        f = Face((7.6 * math.cos(a), 7.6 * math.sin(a), 0), (-math.sin(a), math.cos(a), 0), (math.cos(a), math.sin(a), 0))
        f.slab(mb, -0.25, 0.25, 28.2, 33.8, -0.05, 0.18, "render")                # fluting
    return mb, (w, d, 35.8, 0.0)

# ------------------------------------------------------------- landmarks
# Famous buildings, scaled to fit one 50 m plot (the tall ones keep their look
# rather than their true height). Colours come from the game: "render" and
# "stone" take the first colour, "accent" and "roof" the second.

def frustum(mb, x, y, hx0, hy0, hx1, hy1, z0, z1, mat):
    """A box that tapers from half-size (hx0, hy0) at z0 to (hx1, hy1) at z1."""
    mb.hexa([(x - hx0, y - hy0, z0), (x + hx0, y - hy0, z0), (x + hx0, y + hy0, z0), (x - hx0, y + hy0, z0),
             (x - hx1, y - hy1, z1), (x + hx1, y - hy1, z1), (x + hx1, y + hy1, z1), (x - hx1, y + hy1, z1)], mat)


def eiffel():
    # Four splayed iron legs, arches between them, two platforms, a tapering
    # lattice shaft, the top cabin and its mast.
    w = d = 44.0
    mb = Builder()
    iron = "render"
    rings = [(0.0, 19.5, 5.0), (9.0, 16.2, 4.4), (18.0, 13.4, 3.8), (26.0, 11.4, 3.4),
             (38.0, 8.2, 2.8), (50.0, 5.8, 2.2)]
    for sx in (-1, 1):
        for sy in (-1, 1):
            for (z0, r0, t0), (z1, r1, t1) in zip(rings, rings[1:]):
                beam(mb, (sx * r0, sy * r0, z0), (sx * r1, sy * r1, z1), (t0 + t1) / 2, iron)
            mb.box(sx * 19.5 - 3.6, sx * 19.5 + 3.6, sy * 19.5 - 3.6, sy * 19.5 + 3.6, -0.3, 1.2, "stone")
    # Arches under the first platform, and cross-bracing on each side.
    for turn in range(4):
        c, s = (1, 0, -1, 0)[turn], (0, 1, 0, -1)[turn]

        def pt(a, out, z):
            return (a * -s + out * c, a * c + out * s, z)
        arch = [(-14.5, 12.0), (-10.0, 18.5), (-4.0, 22.5), (4.0, 22.5), (10.0, 18.5), (14.5, 12.0)]
        for (a0, z0), (a1, z1) in zip(arch, arch[1:]):
            out0 = 19.5 - (19.5 - 11.4) * z0 / 26.0
            out1 = 19.5 - (19.5 - 11.4) * z1 / 26.0
            beam(mb, pt(a0, out0, z0), pt(a1, out1, z1), 1.0, iron)
        for z0, r0, z1, r1 in ((28.5, 10.6, 38.0, 8.2), (38.0, 8.2, 48.0, 6.2)):
            beam(mb, pt(-r0, r0, z0), pt(r1, r1, z1), 0.6, iron)
            beam(mb, pt(r0, r0, z0), pt(-r1, r1, z1), 0.6, iron)
    mb.box(-13.6, 13.6, -13.6, 13.6, 24.6, 27.4, iron)                 # first platform
    mb.box(-14.2, 14.2, -14.2, 14.2, 27.4, 28.4, "lead")
    mb.box(-7.4, 7.4, -7.4, 7.4, 49.0, 51.4, iron)                     # second platform
    mb.box(-7.9, 7.9, -7.9, 7.9, 51.4, 52.2, "lead")
    # The shaft: four corner members, rings and diagonals.
    levels = [(52.2, 5.4), (64.0, 4.3), (76.0, 3.4), (88.0, 2.7), (100.0, 2.1), (112.0, 1.6), (122.0, 1.3)]
    for (z0, r0), (z1, r1) in zip(levels, levels[1:]):
        for sx in (-1, 1):
            for sy in (-1, 1):
                beam(mb, (sx * r0, sy * r0, z0), (sx * r1, sy * r1, z1), 0.9, iron)
        for turn in range(4):
            c, s = (1, 0, -1, 0)[turn], (0, 1, 0, -1)[turn]
            beam(mb, (-r0 * -s + r0 * c, -r0 * c + r0 * s, z0), (r1 * -s + r1 * c, r1 * c + r1 * s, z1), 0.4, iron)
            beam(mb, (r0 * -s + r0 * c, r0 * c + r0 * s, z0), (-r1 * -s + r1 * c, -r1 * c + r1 * s, z1), 0.4, iron)
        mb.box(-r1 - 0.2, r1 + 0.2, -r1 - 0.2, r1 + 0.2, z1 - 0.3, z1 + 0.3, iron)
    mb.box(-2.4, 2.4, -2.4, 2.4, 122.0, 126.0, iron)                   # the top cabin
    mb.box(-2.9, 2.9, -2.9, 2.9, 126.0, 126.6, "lead")
    revolve(mb, 0.0, 0.0, [(1.4, 126.6, "lamp"), (1.1, 130.0, "lamp"), (0.3, 131.5, "lamp")], 8)
    mb.box(-0.15, 0.15, -0.15, 0.15, 131.5, 139.0, "metal")
    beacon(mb, 0.0, 0.0, 139.0)
    return mb, (w, d, 139.7, 0.0)


def clock_face(mb, face_out, at, z, r, c=0.0):
    """A round white dial with dark hands on a wall facing (0, 1), (0, -1), (1, 0) or (-1, 0);
    c: where its centre is along the wall."""
    ring = [(r * math.cos(2 * math.pi * k / 16), r * math.sin(2 * math.pi * k / 16)) for k in range(16)]
    ox, oy = face_out
    if oy != 0:
        y0, y1 = sorted((at, at + oy * 0.25))
        mb.extrude_y([(c + a, z + b) for a, b in ring], y0, y1, "frame")
        y0, y1 = sorted((at + oy * 0.25, at + oy * 0.33))
        mb.box(c - 0.15, c + 0.15, y0, y1, z, z + r * 0.82, "metal")
        mb.box(c - 0.15, c + r * 0.55, y0, y1, z - 0.15, z + 0.15, "metal")
    else:
        x0, x1 = sorted((at, at + ox * 0.25))
        mb.extrude_x([(c + a, z + b) for a, b in ring], x0, x1, "frame")
        x0, x1 = sorted((at + ox * 0.25, at + ox * 0.33))
        mb.box(x0, x1, c - 0.15, c + 0.15, z, z + r * 0.82, "metal")
        mb.box(x0, x1, c - 0.15, c + r * 0.55, z - 0.15, z + 0.15, "metal")


def big_ben():
    # The clock tower: a ribbed stone shaft, four dials, the belfry, and a steep
    # slate roof with a lantern and spire. A stretch of the palace beside it.
    w, d = 36.0, 16.0
    mb = Builder()
    tx = -10.0                                 # the tower's centre
    h = 6.0                                    # half its width
    mb.box(tx - h - 0.5, tx + h + 0.5, -h - 0.5, h + 0.5, -0.3, 2.0, "stone")
    mb.box(tx - h, tx + h, -h, h, 2.0, 55.0, "stone")
    for k in range(5):                         # ribs and tall slit windows on each side
        a = -4.8 + k * 2.4
        for y in (-h, h):
            mb.box(tx + a - 0.35, tx + a + 0.35, y - 0.3, y + 0.3, 2.0, 55.0, "stone")
        for x in (tx - h, tx + h):
            mb.box(x - 0.3, x + 0.3, a - 0.35, a + 0.35, 2.0, 55.0, "stone")
    for k in range(4):
        a = -3.6 + k * 2.4
        for z in range(6, 52, 7):
            for y in (-h - 0.05, h + 0.05):
                mb.box(tx + a - 0.45, tx + a + 0.45, y - 0.05, y + 0.05, z, z + 4.6, "glass")
            for x in (tx - h - 0.05, tx + h + 0.05):
                mb.box(x - 0.05, x + 0.05, a - 0.45, a + 0.45, z, z + 4.6, "glass")
    mb.box(tx - h - 0.7, tx + h + 0.7, -h - 0.7, h + 0.7, 55.0, 56.2, "stone")   # the clock stage
    mb.box(tx - h - 0.4, tx + h + 0.4, -h - 0.4, h + 0.4, 56.2, 68.0, "stone")
    clock_face(mb, (0, 1), h + 0.4, 62.0, 4.4, tx)
    clock_face(mb, (0, -1), -h - 0.4, 62.0, 4.4, tx)
    clock_face(mb, (1, 0), tx + h + 0.4, 62.0, 4.4)
    clock_face(mb, (-1, 0), tx - h - 0.4, 62.0, 4.4)
    mb.box(tx - h - 0.9, tx + h + 0.9, -h - 0.9, h + 0.9, 68.0, 69.2, "stone")
    mb.box(tx - h + 0.4, tx + h - 0.4, -h + 0.4, h - 0.4, 69.2, 75.0, "stone")   # the belfry
    for k in range(4):
        a = -3.6 + k * 2.4
        for y in (-h + 0.35, h - 0.35):
            mb.box(tx + a - 0.5, tx + a + 0.5, y - 0.06, y + 0.06, 69.8, 74.2, "metal")
        for x in (tx - h + 0.35, tx + h - 0.35):
            mb.box(x - 0.06, x + 0.06, a - 0.5, a + 0.5, 69.8, 74.2, "metal")
    for sx in (-1, 1):
        for sy in (-1, 1):
            pyramid(mb, tx + sx * (h - 0.2), sy * (h - 0.2), 0.8, 68.0, 78.0, "stone")   # pinnacles
    frustum(mb, tx, 0.0, h - 0.2, h - 0.2, 3.2, 3.2, 75.0, 84.0, "roof")
    mb.box(tx - 3.0, tx + 3.0, -3.0, 3.0, 84.0, 87.0, "lamp")                      # the lantern
    pyramid(mb, tx, 0.0, 3.3, 87.0, 95.0, "roof")
    mb.box(tx - 0.12, tx + 0.12, -0.12, 0.12, 95.0, 98.0, "lamp")
    # The palace wing: stone, tall windows, a slate roof with pinnacles.
    x0, x1 = tx + h, w / 2
    mb.box(x0, x1, -6.5, 6.5, -0.3, 15.0, "stone")
    n = 9
    for k in range(n):
        a = x0 + 1.4 + k * (x1 - x0 - 2.8) / (n - 1)
        for y in (-6.5, 6.5):
            mb.box(a - 0.55, a + 0.55, y - 0.06, y + 0.06, 2.0, 6.5, "glass")
            mb.box(a - 0.55, a + 0.55, y - 0.06, y + 0.06, 8.5, 13.0, "glass")
        if k % 2 == 0:
            for y in (-6.5, 6.5):
                pyramid(mb, a + 1.1, y, 0.45, 15.0, 19.5, "stone")
    mb.box(x0, x1, -6.9, 6.9, 15.0, 15.8, "stone")
    mb.extrude_x([(-6.3, 15.8), (6.3, 15.8), (0.0, 21.0)], x0, x1 - 0.3, "roof")
    return mb, (w, d, 98.0, 0.0)


def empire_state():
    # The art deco skyscraper: a wide base, setbacks, a long shaft with window
    # strips, the stepped crown and its mast.
    w, d = 40.0, 28.0
    mb = Builder()
    tiers = [(20.0, 14.0, 0.0, 14.0), (15.5, 11.0, 14.0, 26.0), (13.0, 9.5, 26.0, 40.0),
             (11.0, 8.2, 40.0, 138.0), (9.0, 6.8, 138.0, 148.0), (7.0, 5.4, 148.0, 156.0)]
    for hx, hy, z0, z1 in tiers:
        mb.box(-hx, hx, -hy, hy, z0 - (0.3 if z0 == 0 else 0), z1, "stone")
        nx = int(hx * 2 / 2.6)
        ny = int(hy * 2 / 2.6)
        for k in range(nx):
            a = -hx + (k + 0.5) * hx * 2 / nx
            for y in (-hy - 0.06, hy + 0.06):
                mb.box(a - 0.5, a + 0.5, y - 0.06, y + 0.06, z0 + (4.5 if z0 == 0 else 0.8), z1 - 1.0, "office")
        for k in range(ny):
            a = -hy + (k + 0.5) * hy * 2 / ny
            for x in (-hx - 0.06, hx + 0.06):
                mb.box(x - 0.06, x + 0.06, a - 0.5, a + 0.5, z0 + (4.5 if z0 == 0 else 0.8), z1 - 1.0, "office")
    for y in (-14.06, 14.06):                              # entrances
        mb.box(-3.0, 3.0, y - 0.1, y + 0.1, 0.0, 4.2, "glass")
    # Wings up the long faces of the shaft, as the real one has.
    for x in (-11.0, 11.0):
        mb.box(x - 1.6, x + 1.6, -5.4, 5.4, 40.0, 128.0, "stone")
    mb.box(-5.0, 5.0, -4.2, 4.2, 156.0, 163.0, "lamp")     # the crown, floodlit
    mb.box(-3.6, 3.6, -3.2, 3.2, 163.0, 168.0, "lamp")
    revolve(mb, 0.0, 0.0, [(2.6, 168.0, "lead"), (2.2, 176.0, "lead"), (1.2, 180.0, "lead"), (0.5, 182.0, "lead")], 10)
    mb.box(-0.2, 0.2, -0.2, 0.2, 182.0, 196.0, "metal")
    beacon(mb, 0.0, 0.0, 196.0)
    return mb, (w, d, 196.7, 0.0)


def liberty():
    # The statue on its pedestal on a star-shaped fort: robed figure, crown,
    # tablet, and the torch held high (all in the second colour, weathered copper).
    w = d = 34.0
    mb = Builder()
    star = []
    for k in range(22):
        a = 2 * math.pi * k / 22
        r = 16.5 if k % 2 == 0 else 11.5
        star.append((r * math.cos(a), r * math.sin(a)))
    mb.prism(star, -0.3, 4.0, "stone")
    mb.box(-9.5, 9.5, -9.5, 9.5, 4.0, 8.5, "stone")
    frustum(mb, 0.0, 0.0, 6.6, 6.6, 5.4, 5.4, 8.5, 12.0, "stone")
    frustum(mb, 0.0, 0.0, 5.2, 5.2, 4.3, 4.3, 12.0, 34.0, "stone")
    for turn in range(4):                                     # the pedestal's loggia
        c, s = (1, 0, -1, 0)[turn], (0, 1, 0, -1)[turn]
        f = Face((4.75 * c, 4.75 * s, 0), (-s, c, 0), (c, s, 0))
        f.slab(mb, -2.6, 2.6, 22.0, 29.0, -0.3, 0.12, "metal")
        for a in (-1.7, 0.0, 1.7):
            f.slab(mb, a - 0.28, a + 0.28, 22.0, 29.0, 0.05, 0.4, "stone")
    mb.box(-5.2, 5.2, -5.2, 5.2, 34.0, 35.4, "stone")
    c = "accent"
    revolve(mb, 0.0, 0.0, [(3.3, 35.4, c), (3.0, 44.0, c), (2.5, 53.0, c), (2.3, 60.0, c), (2.6, 64.0, c),
                           (1.2, 66.0, c), (1.0, 67.0, c), (1.6, 68.6, c), (1.7, 70.4, c), (1.2, 72.0, c),
                           (0.3, 72.6, c)], 12)
    for k in range(7):                                        # the crown's rays
        a = math.pi * (0.1 + 0.8 * k / 6)
        beam(mb, (1.4 * math.cos(a), 0.5, 71.4), (3.4 * math.cos(a), 0.9, 71.4 + 2.6 * math.sin(a)), 0.35, c)
    beam(mb, (-2.2, 0.0, 63.5), (-4.0, 0.6, 72.0), 1.5, c)   # the raised arm...
    beam(mb, (-4.0, 0.6, 72.0), (-4.3, 0.8, 80.5), 1.2, c)
    revolve(mb, -4.3, 0.8, [(0.5, 80.5, c), (1.3, 81.6, c), (1.3, 82.0, c), (0.5, 82.2, c)], 8)
    revolve(mb, -4.3, 0.8, [(0.7, 82.2, "lamp"), (0.9, 83.4, "lamp"), (0.2, 85.6, "lamp")], 8)   # ...and its torch
    beam(mb, (2.3, 0.0, 62.5), (3.0, 1.6, 56.5), 1.4, c)     # the other arm, holding the tablet
    mb.hexa([(2.2, 1.2, 55.0), (4.0, 1.2, 55.0), (4.0, 2.0, 55.4), (2.2, 2.0, 55.4),
             (2.0, 0.6, 60.0), (3.8, 0.6, 60.0), (3.8, 1.4, 60.4), (2.0, 1.4, 60.4)], c)
    return mb, (w, d, 85.6, 0.0)


def sail(mb, x_back, y, length, height, half, facing=1, mat="frame", glass=True):
    """A shell roof: a ridge rising in a curve from the ground at its back to its
    mouth, with curved sides down to the podium, and glass across the mouth."""
    n = 7
    ridge, left, right = [], [], []
    for k in range(n + 1):
        t = k / n
        x = x_back + facing * length * t
        z = height * math.sin(t * math.pi / 2) ** 0.8
        hw = half * (t ** 0.75)
        ridge.append((x + facing * 0.12 * z, y, z))
        left.append((x, y - hw, 0.0))
        right.append((x, y + hw, 0.0))
    base = len(mb.verts)
    mb.verts.extend(ridge + left + right)
    for k in range(n):
        r0, r1 = base + k, base + k + 1
        l0, l1 = base + n + 1 + k, base + n + 2 + k
        g0, g1 = base + 2 * n + 2 + k, base + 2 * n + 3 + k
        for face in ([r0, r1, l1, l0], [r1, r0, g0, g1]):
            mb.faces.append(face)
            mb.mats.append(MAT_INDEX[mat])
    if glass:
        mb.faces.append([base + n, base + 3 * n + 2, base + 2 * n + 1])
        mb.mats.append(MAT_INDEX["glass"])


def opera_house():
    # White shells in two rows on a stone podium by the water, with broad steps.
    w, d = 46.0, 38.0
    mb = Builder()
    mb.box(-23.0, 23.0, -19.0, 19.0, -0.3, 3.4, "stone")
    for k in range(5):                                  # broad steps down to the front
        mb.box(-13.0, 13.0, 19.0 + k * 0.5, 19.5 + k * 0.5, 3.4 - (k + 1) * 0.68, 3.4 - k * 0.68, "stone")
    shells = Builder()
    for y, scale in ((-8.5, 1.0), (8.0, 0.86)):
        sail(shells, -4.0, y, 17.0 * scale, 21.0 * scale, 7.6 * scale)
        sail(shells, -11.0, y, 13.0 * scale, 16.0 * scale, 6.4 * scale)
        sail(shells, -16.5, y, 9.0 * scale, 11.0 * scale, 5.0 * scale)
        sail(shells, -8.0, y, 11.0 * scale, 12.5 * scale, 5.6 * scale, facing=-1)
    sail(shells, 14.0, 12.0, 7.0, 8.0, 3.8, facing=-1)   # the small restaurant shells
    sail(shells, 15.0, 12.0, 5.5, 6.0, 3.2)
    base = len(mb.verts)
    mb.verts.extend((x, y, z + 3.4) for x, y, z in shells.verts)
    for f, m in zip(shells.faces, shells.mats):
        mb.faces.append([base + k for k in f])
        mb.faces.append([base + k for k in f][::-1])     # (both sides, so the shells are solid from any angle)
        mb.mats.extend([m, m])
    return mb, (w, d, 24.4, 0.0)


def onion_dome(mb, x, y, r, z0, mat="render", finial=True):
    revolve(mb, x, y, [(r * 0.95, z0, mat), (r * 1.08, z0 + r * 0.45, mat), (r * 1.02, z0 + r * 0.95, mat),
                       (r * 0.78, z0 + r * 1.4, mat), (r * 0.4, z0 + r * 1.78, mat), (r * 0.06, z0 + r * 2.1, mat)], 16)
    if finial:
        mb.box(x - 0.1, x + 0.1, y - 0.1, y + 0.1, z0 + r * 2.1, z0 + r * 2.1 + r * 0.5, "lamp")


def pointed_arch(a, z0, w, h):
    """The outline of a pointed arch as [(across, z), ...]."""
    return [(a - w / 2, z0), (a + w / 2, z0), (a + w / 2, z0 + h * 0.6), (a + w * 0.3, z0 + h * 0.85),
            (a, z0 + h), (a - w * 0.3, z0 + h * 0.85), (a - w / 2, z0 + h * 0.6)]


def taj_mahal():
    # White marble on a wide plinth: a square tomb with cut corners and a great
    # arched portal on every side, the onion dome with four small ones round it,
    # and a minaret at each corner of the plinth.
    w = d = 46.0
    mb = Builder()
    mb.box(-23.0, 23.0, -23.0, 23.0, -0.3, 2.6, "render")
    h, cut = 11.5, 3.6
    plan = [(-h + cut, -h), (h - cut, -h), (h, -h + cut), (h, h - cut), (h - cut, h), (-h + cut, h),
            (-h, h - cut), (-h, -h + cut)]
    mb.prism(plan, 2.6, 17.0, "render")
    mb.prism([(x * 1.02, y * 1.02) for x, y in plan], 17.0, 17.8, "render")
    for turn in range(4):
        c, s = (1, 0, -1, 0)[turn], (0, 1, 0, -1)[turn]
        if s != 0:
            y0, y1 = sorted((s * h, s * (h + 0.9)))
            mb.box(-4.6, 4.6, y0, y1, 2.6, 19.6, "render")                       # the portal's frame
            y0, y1 = sorted((s * (h + 0.9), s * (h + 1.0)))
            mb.extrude_y(pointed_arch(0.0, 2.6, 6.4, 13.5), y0, y1, "metal")
            for a in (-7.4, 7.4):
                for z in (3.4, 10.4):
                    mb.extrude_y(pointed_arch(a, z, 2.6, 5.4), min(s * h, s * (h + 0.1)), max(s * h, s * (h + 0.1)), "metal")
        else:
            x0, x1 = sorted((c * h, c * (h + 0.9)))
            mb.box(x0, x1, -4.6, 4.6, 2.6, 19.6, "render")
            x0, x1 = sorted((c * (h + 0.9), c * (h + 1.0)))
            mb.extrude_x(pointed_arch(0.0, 2.6, 6.4, 13.5), x0, x1, "metal")
            for a in (-7.4, 7.4):
                for z in (3.4, 10.4):
                    mb.extrude_x(pointed_arch(a, z, 2.6, 5.4), min(c * h, c * (h + 0.1)), max(c * h, c * (h + 0.1)), "metal")
    revolve(mb, 0.0, 0.0, [(6.2, 17.8, "render"), (6.2, 22.5, "render")], 16)     # the drum
    onion_dome(mb, 0.0, 0.0, 6.4, 22.5)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 7.6, sy * 7.6
            for k in range(6):                                                    # a small domed kiosk
                a = 2 * math.pi * k / 6
                mb.box(cx + 1.7 * math.cos(a) - 0.18, cx + 1.7 * math.cos(a) + 0.18,
                       cy + 1.7 * math.sin(a) - 0.18, cy + 1.7 * math.sin(a) + 0.18, 17.8, 20.6, "render")
            revolve(mb, cx, cy, [(2.3, 20.6, "render"), (2.3, 21.0, "render")], 12)
            onion_dome(mb, cx, cy, 2.0, 21.0)
            mx, my = sx * 20.8, sy * 20.8                                         # a minaret
            revolve(mb, mx, my, [(1.5, 2.6, "render"), (1.15, 28.0, "render")], 12)
            for z in (11.0, 19.5, 28.0):
                revolve(mb, mx, my, [(1.9, z, "render"), (1.9, z + 0.5, "render")], 12)
            for k in range(6):
                a = 2 * math.pi * k / 6
                mb.box(mx + 1.2 * math.cos(a) - 0.14, mx + 1.2 * math.cos(a) + 0.14,
                       my + 1.2 * math.sin(a) - 0.14, my + 1.2 * math.sin(a) + 0.14, 28.5, 30.6, "render")
            revolve(mb, mx, my, [(1.6, 30.6, "render"), (1.6, 30.9, "render")], 12)
            onion_dome(mb, mx, my, 1.35, 30.9)
    return mb, (w, d, 39.2, 0.0)


def ellipse_ring(mb, a0, b0, a1, b1, z0, z1, mat, n, k0=0, k1=None):
    """Part of a ring between two ellipses (outer a0 x b0, inner a1 x b1), as n wedges."""
    k1 = n if k1 is None else k1
    for k in range(k0, k1):
        t0, t1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        mb.hexa([(a1 * math.cos(t0), b1 * math.sin(t0), z0), (a0 * math.cos(t0), b0 * math.sin(t0), z0),
                 (a0 * math.cos(t1), b0 * math.sin(t1), z0), (a1 * math.cos(t1), b1 * math.sin(t1), z0),
                 (a1 * math.cos(t0), b1 * math.sin(t0), z1), (a0 * math.cos(t0), b0 * math.sin(t0), z1),
                 (a0 * math.cos(t1), b0 * math.sin(t1), z1), (a1 * math.cos(t1), b1 * math.sin(t1), z1)], mat)


def colosseum():
    # The oval amphitheatre: three tiers of arches and an attic, the outer wall
    # fallen away round half of it, the seating stepping down to the arena.
    w, d = 46.0, 38.0
    mb = Builder()
    n = 48
    a, b = 22.6, 18.6
    ellipse_ring(mb, a, b, a - 2.4, b - 2.4, -0.3, 19.0, "stone", n, 0, 26)         # the full-height outer wall
    ellipse_ring(mb, a - 0.2, b - 0.2, a - 2.4, b - 2.4, 19.0, 19.6, "stone", n, 0, 26)
    ellipse_ring(mb, a - 2.4, b - 2.4, a - 5.0, b - 5.0, -0.3, 13.4, "stone", n)    # the inner wall, all the way round
    for k in range(n):
        t = 2 * math.pi * (k + 0.5) / n
        outer = k < 26
        ra, rb = (a, b) if outer else (a - 2.4, b - 2.4)
        px, py = ra * math.cos(t), rb * math.sin(t)
        nx, ny = math.cos(t) / ra, math.sin(t) / rb
        ln = math.hypot(nx, ny)
        f = Face((px, py, 0), (-ny / ln, nx / ln, 0), (nx / ln, ny / ln, 0))
        half = math.hypot(ra * math.sin(t), rb * math.cos(t)) * math.pi / n * 0.55
        for tier in range(3 if outer else 2):
            z = 0.8 + tier * 4.6 if outer else 0.6 + tier * 6.2
            arch_h = 3.4 if outer else 4.6
            f.slab(mb, -half, half, z, z + arch_h * 0.7, -0.4, 0.06, "metal")
            f.slab(mb, -half * 0.6, half * 0.6, z + arch_h * 0.7, z + arch_h, -0.4, 0.06, "metal")
        if outer and k % 2 == 0:
            f.slab(mb, -0.4, 0.4, 15.2, 17.2, -0.3, 0.06, "metal")                   # attic windows
    for tier in range(1, 4):                                                        # string courses
        z = 0.2 + tier * 4.6
        ellipse_ring(mb, a + 0.25, b + 0.25, a - 0.2, b - 0.2, z, z + 0.45, "stone", n, 0, 26)
    steps = 6                                                                       # the seating
    for k in range(steps):
        r0 = 5.0 + k * 1.5
        ellipse_ring(mb, a - r0, b - r0, a - r0 - 1.5, b - r0 - 1.5, -0.3, 11.5 - k * 1.8, "stone", n)
    mb.prism([((a - 14.0) * math.cos(2 * math.pi * k / n), (b - 14.0) * math.sin(2 * math.pi * k / n))
              for k in range(n)], -0.3, 0.7, "accent")                              # the arena's sand
    return mb, (w, d, 19.6, 0.0)


def great_pyramid():
    # The great pyramid with two small ones at its foot, in sandy stone, its
    # capstone catching the light.
    w = d = 46.0
    mb = Builder()
    x, y, half, top = -2.5, -2.5, 19.5, 29.0
    courses = 14
    for k in range(courses):
        t0, t1 = k / courses, (k + 1) / courses
        frustum(mb, x, y, half * (1 - t0), half * (1 - t0), half * (1 - t1) + 0.25, half * (1 - t1) + 0.25,
                top * t0 - (0.3 if k == 0 else 0), top * t1, "stone")
    pyramid(mb, x, y, 0.9, top * (courses - 0.6) / courses, top + 0.8, "lamp")
    for px, py, ph in ((18.5, 17.5, 4.2), (18.5, 7.5, 3.4)):
        pyramid(mb, px, py, ph, -0.3, ph * 1.35, "stone")
    mb.box(-23.0, -2.5, 17.0, 19.0, -0.3, 0.5, "stone")                             # the causeway
    return mb, (w, d, 29.8, 0.0)


# ------------------------------------------------ San Francisco's landmarks

def rounded_square(hw, hd, r, z, n=4):
    """A ring of points round a rounded rectangle (half sizes hw, hd, corner radius r) at height z."""
    pts = []
    for cx, cy, a0 in ((hw - r, hd - r, 0.0), (-hw + r, hd - r, 90.0), (-hw + r, -hd + r, 180.0), (hw - r, -hd + r, 270.0)):
        for k in range(n + 1):
            a = math.radians(a0 + 90.0 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    return pts


def loft(mb, rings, mat, caps=True):
    """Side faces joining rings of points (each the same length, going round the same way)."""
    n = len(rings[0])
    base = len(mb.verts)
    for ring in rings:
        mb.verts.extend(ring)
    for i in range(1, len(rings)):
        for k in range(n):
            j = (k + 1) % n
            mb.faces.append([base + (i - 1) * n + k, base + (i - 1) * n + j, base + i * n + j, base + i * n + k])
            mb.mats.append(MAT_INDEX[mat])
    if caps:
        mb.faces.append([base + k for k in range(n)][::-1])
        mb.mats.append(MAT_INDEX[mat])
        top = base + (len(rings) - 1) * n
        mb.faces.append([top + k for k in range(n)])
        mb.mats.append(MAT_INDEX[mat])


def painted_lady():
    # One of the Painted Ladies: a narrow Victorian house over a raised basement,
    # a two-storey bay window, a stoop up to the door, white trim, a steep front
    # gable with shingles in the trim colour. The game draws a row of them, each
    # painted its own colour (wall colour; second colour: trim and gable).
    w, d = 7.6, 14.0
    mb = Builder()
    hw, hd = w / 2, d / 2
    mb.box(-hw, hw, -hd, hd, -0.3, 1.8, "accent")                     # the raised basement
    mb.box(-hw, hw, -hd, hd, 1.8, 11.4, "render")
    f = front(w, d)
    # The bay: three faces, angled at the sides.
    bay = [(0.0, hd), (3.6, hd), (3.0, hd + 1.3), (0.6, hd + 1.3)]
    mb.prism(bay, 1.8, 8.8, "render")
    mb.prism([(x, y + (0.15 if y > hd else 0.0)) for x, y in [(-0.15, hd), (3.75, hd), (3.1, hd + 1.45), (0.5, hd + 1.45)]],
             8.8, 9.3, "frame")
    for z in (2.6, 6.0):
        mb.box(0.9, 2.7, hd + 1.3, hd + 1.36, z, z + 2.4, "glass")
        mb.box(0.85, 2.75, hd + 1.32, hd + 1.42, z - 0.2, z, "frame")
        mb.box(0.85, 2.75, hd + 1.32, hd + 1.42, z + 2.4, z + 2.6, "frame")
        mb.box(1.77, 1.83, hd + 1.32, hd + 1.42, z, z + 2.4, "frame")
        for a, b in (((0.12, hd + 0.45), (0.55, hd + 1.15)), ((3.48, hd + 0.45), (3.05, hd + 1.15))):
            beam(mb, (a[0], a[1], z + 1.2), (b[0], b[1], z + 1.2), 0.08, "glass", 2.4)
    # The door up a stoop, a window over it, white bands and a bracketed cornice.
    window(mb, f, -2.2, 5.9, 1.4, 2.4, surround=False, sill=False, lintel=False)
    f.slab(mb, -3.2, -1.3, 1.8, 4.6, -0.02, 0.05, "door")
    f.slab(mb, -3.45, -1.05, 4.6, 5.0, 0.0, 0.35, "frame")             # the door hood
    for k in range(6):                                                 # the stoop
        f.slab(mb, -3.4, -1.1, -0.3, 1.8 - k * 0.3, 0.0, 0.4 + k * 0.4, "frame")
    for z in (1.8, 5.4):
        f.slab(mb, -hw, hw, z - 0.15, z + 0.1, 0.0, 0.12, "frame")
    f.slab(mb, -hw - 0.1, hw + 0.1, 10.8, 11.5, 0.0, 0.55, "frame")
    for k in range(7):
        a = -hw + 0.4 + k * (w - 0.8) / 6
        f.slab(mb, a - 0.12, a + 0.12, 10.3, 10.8, 0.0, 0.4, "accent")
    # The steep gable, with its shingled face and an attic window.
    mb.extrude_y([(-hw - 0.2, 11.4), (hw + 0.2, 11.4), (0.0, 16.0)], -hd, hd + 0.25, "lead")   # (dark slate: the second colour is the trim)
    mb.extrude_y([(-hw + 0.3, 11.5), (hw - 0.3, 11.5), (0.0, 15.4)], hd + 0.25, hd + 0.35, "accent")
    mb.box(-0.7, 0.7, hd + 0.33, hd + 0.4, 12.0, 13.6, "glass")
    mb.box(-0.85, 0.85, hd + 0.33, hd + 0.45, 11.85, 12.0, "frame")
    return mb, (w, d, 16.0, 0.0)


def coit_tower():
    # The fluted concrete column on Telegraph Hill, its arched lookout at the top,
    # and the low hall at its foot (with the murals inside).
    w = d = 34.0
    mb = Builder()
    mb.box(-15.0, 15.0, 2.0, 15.0, -0.3, 7.0, "render")                # the hall
    mb.box(-15.4, 15.4, 1.6, 15.4, 7.0, 7.8, "render")
    for k in range(9):                                                 # its arched windows
        a = -12.0 + k * 3.0
        mb.box(a - 0.8, a + 0.8, 15.0, 15.06, 1.2, 5.0, "glass")
        revolve(mb, a, 15.0, [(0.8, 5.0, "glass"), (0.55, 5.55, "glass"), (0.05, 5.8, "glass")], 8)
    mb.box(-2.0, 2.0, 15.0, 15.1, 0.0, 4.4, "door")
    cx, cy = 0.0, -2.0
    sides = 48
    plan = [(cx + (5.6 if k % 2 == 0 else 5.25) * math.cos(2 * math.pi * k / sides),
             cy + (5.6 if k % 2 == 0 else 5.25) * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    mb.prism(plan, -0.3, 54.0, "render")                               # the fluted shaft
    for k in range(4):                                                 # slit windows up it
        a = math.pi / 2 * k + math.pi / 4
        for z in range(12, 50, 6):
            x, y = cx + 5.62 * math.cos(a), cy + 5.62 * math.sin(a)
            mb.box(x - 0.25, x + 0.25, y - 0.25, y + 0.25, z, z + 2.6, "glass")
    revolve(mb, cx, cy, [(5.9, 54.0, "render"), (5.9, 54.8, "render")], 24)
    revolve(mb, cx, cy, [(5.5, 54.8, "render"), (5.5, 60.0, "render")], 24)
    for k in range(12):                                                # the lookout's arches
        a = 2 * math.pi * k / 12
        x, y = cx + 5.52 * math.cos(a), cy + 5.52 * math.sin(a)
        beam(mb, (x, y, 55.4), (x, y, 59.0), 0.5, "glass", 1.6)
    revolve(mb, cx, cy, [(6.0, 60.0, "render"), (6.0, 61.0, "render"), (5.0, 61.4, "render"),
                         (4.6, 63.6, "render"), (4.9, 64.2, "render"), (2.0, 64.6, "lead")], 24)
    beacon(mb, cx, cy, 64.6)
    return mb, (w, d, 65.3, 0.0)


def ferry_building():
    # The Ferry Building: a long two-storey hall in pale stone, a ground-floor
    # arcade, arched windows over it, and the clock tower in the middle (after
    # Seville's Giralda): clock faces, a belfry, a lantern and a small cupola.
    w, d = 46.0, 20.0
    mb = Builder()
    hw, hd = w / 2, d / 2
    mb.box(-hw, hw, -hd, hd, -0.3, 13.0, "stone")
    mb.box(-hw - 0.3, hw + 0.3, -hd - 0.3, hd + 0.3, 13.0, 13.8, "stone")   # cornice
    mb.extrude_x([(-hd, 13.8), (hd, 13.8), (0.0, 17.5)], -hw, hw, "roof")
    for y, out in ((hd, 1), (-hd, -1)):
        for k in range(15):                                             # the arcade and upper windows
            a = -hw + 1.6 + k * (w - 3.2) / 14
            y0, y1 = sorted((y, y + out * 0.06))
            mb.box(a - 0.9, a + 0.9, y0, y1, 0.0, 4.4, "glass")
            revolve(mb, a, y, [(0.9, 4.4, "glass"), (0.6, 5.1, "glass"), (0.05, 5.35, "glass")], 8)
            mb.box(a - 0.7, a + 0.7, y0, y1, 7.0, 10.4, "glass")
            revolve(mb, a, y, [(0.7, 10.4, "glass"), (0.45, 10.95, "glass"), (0.05, 11.1, "glass")], 8)
        y0, y1 = sorted((y, y + out * 0.5))
        mb.box(-hw, hw, y0, y1, 6.0, 6.5, "stone")
    for x in (-hw, hw - 4.0):                                           # end pavilions
        mb.box(x - 0.2, x + 4.2, -hd - 0.4, hd + 0.4, -0.3, 15.5, "stone")
        mb.box(x - 0.4, x + 4.4, -hd - 0.6, hd + 0.6, 15.5, 16.2, "stone")
    # The tower.
    h = 3.6
    mb.box(-h, h, -h, h, 13.0, 44.0, "stone")
    for k in range(3):
        a = -2.0 + k * 2.0
        for z in range(18, 42, 6):
            for y in (-h - 0.05, h + 0.05):
                mb.box(a - 0.35, a + 0.35, y - 0.05, y + 0.05, z, z + 2.8, "glass")
            for x in (-h - 0.05, h + 0.05):
                mb.box(x - 0.05, x + 0.05, a - 0.35, a + 0.35, z, z + 2.8, "glass")
    mb.box(-h - 0.3, h + 0.3, -h - 0.3, h + 0.3, 44.0, 51.0, "stone")
    clock_face(mb, (0, 1), h + 0.3, 47.5, 2.6)
    clock_face(mb, (0, -1), -h - 0.3, 47.5, 2.6)
    clock_face(mb, (1, 0), h + 0.3, 47.5, 2.6)
    clock_face(mb, (-1, 0), -h - 0.3, 47.5, 2.6)
    mb.box(-h - 0.6, h + 0.6, -h - 0.6, h + 0.6, 51.0, 51.8, "stone")
    mb.box(-h + 0.2, h - 0.2, -h + 0.2, h - 0.2, 51.8, 58.0, "stone")  # the belfry
    for a in (-1.6, 1.6):
        for y in (-h + 0.15, h - 0.15):
            mb.box(a - 0.9, a + 0.9, y - 0.08, y + 0.08, 52.6, 57.0, "metal")
        for x in (-h + 0.15, h - 0.15):
            mb.box(x - 0.08, x + 0.08, a - 0.9, a + 0.9, 52.6, 57.0, "metal")
    mb.box(-h, h, -h, h, 58.0, 58.8, "stone")
    mb.box(-2.4, 2.4, -2.4, 2.4, 58.8, 64.0, "lamp")                    # the lantern, lit at night
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box(sx * 2.4 - 0.4, sx * 2.4 + 0.4, sy * 2.4 - 0.4, sy * 2.4 + 0.4, 58.8, 64.0, "stone")
    mb.box(-2.8, 2.8, -2.8, 2.8, 64.0, 64.6, "stone")
    revolve(mb, 0.0, 0.0, [(2.2, 64.6, "roof"), (2.1, 66.0, "roof"), (1.4, 67.6, "roof"), (0.3, 68.6, "roof")], 12)
    mb.box(-0.1, 0.1, -0.1, 0.1, 68.6, 71.0, "metal")
    return mb, (w, d, 71.0, 0.0)


def fine_arts():
    # The Palace of Fine Arts: an open rotunda of paired columns under a domed
    # drum (the dome in the second colour), a curved colonnade behind it with its
    # planter boxes on top, and the lagoon in front.
    w = d = 46.0
    mb = Builder()
    cx, cy = 0.0, 2.0
    lagoon = [(16.0 * math.cos(math.pi * k / 12), 23.0 - 9.0 * math.sin(math.pi * k / 12)) for k in range(13)]
    mb.prism([(x, y) for x, y in lagoon][::-1] + [(-16.0, 23.0)], -0.2, 0.05, "metal")   # the lagoon (dark water)
    mb.prism([(cx + 11.0 * math.cos(2 * math.pi * (k + 0.5) / 8), cy + 11.0 * math.sin(2 * math.pi * (k + 0.5) / 8))
              for k in range(8)], -0.3, 1.2, "stone")                   # the platform
    for k in range(8):                                                  # paired columns at the corners
        a = 2 * math.pi * (k + 0.5) / 8
        for off in (-0.09, 0.09):
            x, y = cx + 9.6 * math.cos(a + off), cy + 9.6 * math.sin(a + off)
            revolve(mb, x, y, [(0.55, 1.2, "stone"), (0.5, 17.0, "stone"), (0.7, 17.6, "stone")], 8)
    octagon = lambda r: [(cx + r * math.cos(2 * math.pi * (k + 0.5) / 8), cy + r * math.sin(2 * math.pi * (k + 0.5) / 8))
                         for k in range(8)]
    mb.prism(octagon(10.6), 17.6, 21.0, "stone")                       # the entablature
    for k in range(8):                                                  # arches between the columns
        a = 2 * math.pi * k / 8
        x, y = cx + 9.9 * math.cos(a), cy + 9.9 * math.sin(a)
        beam(mb, (x, y, 15.0), (x, y, 17.6), 0.6, "stone", 6.0)
    mb.prism(octagon(9.4), 21.0, 26.0, "stone")                        # the drum
    revolve(mb, cx, cy, [(8.6, 26.0, "accent"), (8.4, 28.5, "accent"), (7.4, 32.0, "accent"), (5.4, 35.2, "accent"),
                         (2.6, 37.4, "accent"), (0.8, 38.0, "accent")], 24)
    revolve(mb, cx, cy, [(1.0, 38.0, "stone"), (0.8, 40.0, "stone"), (0.2, 40.6, "stone")], 8)
    # The colonnade: an arc of columns behind, beams along the top, planter boxes.
    arc = [math.radians(190.0 + k * 160.0 / 18) for k in range(19)]
    tops = []
    for a in arc:
        x, y = cx + 19.0 * math.cos(a), cy + 19.0 * math.sin(a)
        revolve(mb, x, y, [(0.6, -0.3, "stone"), (0.5, 11.0, "stone"), (0.7, 11.5, "stone")], 8)
        x2, y2 = cx + 21.5 * math.cos(a), cy + 21.5 * math.sin(a)
        revolve(mb, x2, y2, [(0.6, -0.3, "stone"), (0.5, 11.0, "stone"), (0.7, 11.5, "stone")], 8)
        tops.append(((x, y), (x2, y2)))
    for (p0, q0), (p1, q1) in zip(tops, tops[1:]):
        mb.hexa([(p0[0], p0[1], 11.5), (q0[0], q0[1], 11.5), (q1[0], q1[1], 11.5), (p1[0], p1[1], 11.5),
                 (p0[0], p0[1], 13.2), (q0[0], q0[1], 13.2), (q1[0], q1[1], 13.2), (p1[0], p1[1], 13.2)], "stone")
    for k in (1, 5, 9, 13, 17):
        (p, q) = tops[k]
        x, y = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        mb.box(x - 1.4, x + 1.4, y - 1.4, y + 1.4, 13.2, 16.4, "stone")
        mb.box(x - 1.6, x + 1.6, y - 1.6, y + 1.6, 16.4, 16.9, "stone")
    return mb, (w, d, 40.6, 0.0)


def transamerica():
    # The Transamerica Pyramid: white storeys tapering to a spire, the two
    # "wings" (lift and stair towers) standing out from its upper sides, a lit
    # tip, and slanting columns round the open ground floor.
    w = d = 40.0
    mb = Builder()
    z_base, z_top, h0, h1 = 9.0, 196.0, 17.0, 4.0

    def hw(z):
        return h0 - (h0 - h1) * (z - z_base) / (z_top - z_base)
    mb.box(-13.5, 13.5, -13.5, 13.5, -0.3, z_base, "office")           # the lobby
    for side in range(4):
        c, s = (1, 0, -1, 0)[side], (0, 1, 0, -1)[side]
        for k in range(7):
            a = -15.0 + k * 5.0
            p0 = (c * 16.6 + -s * a, s * 16.6 + c * a, -0.3)
            p1 = (c * h0 + -s * a * h0 / 16.6, s * h0 + c * a * h0 / 16.6, z_base)
            beam(mb, p0, p1, 0.9, "render")
    z = z_base
    while z < z_top - 0.1:
        z1 = min(z + 3.8, z_top)
        frustum(mb, 0.0, 0.0, hw(z), hw(z), hw(z + 1.1), hw(z + 1.1), z, z + 1.1, "render")
        frustum(mb, 0.0, 0.0, hw(z + 1.1) - 0.25, hw(z + 1.1) - 0.25, hw(z1) - 0.25, hw(z1) - 0.25, z + 1.1, z1, "office")
        z = z1
    for sx in (-1, 1):                                                  # the wings
        x0, x1 = sorted((sx * 3.0, sx * (hw(100.0) + 0.6)))
        mb.box(x0, x1, -3.4, 3.4, 100.0, 202.0, "render")
        mb.extrude_y([(x0, 202.0), (x1, 202.0), (sx * 3.0, 208.0)] if sx < 0 else [(x0, 202.0), (x1, 202.0), (x0, 208.0)],
                     -3.4, 3.4, "render")
    frustum(mb, 0.0, 0.0, h1, h1, 0.8, 0.8, z_top, 232.0, "render")   # the spire
    frustum(mb, 0.0, 0.0, 0.8, 0.8, 0.3, 0.3, 232.0, 236.0, "lamp")
    mb.box(-0.12, 0.12, -0.12, 0.12, 236.0, 240.0, "metal")
    beacon(mb, 0.0, 0.0, 240.0)
    return mb, (w, d, 240.7, 0.0)


def salesforce_tower():
    # Salesforce Tower: a rounded square of pale glass striped by white sunshades,
    # curving in near the top to an open lattice crown with a lit screen inside.
    w = d = 40.0
    mb = Builder()
    top_body, crown_top = 268.0, 296.0

    def half(z):
        if z < 190.0:
            return 17.0
        t = (z - 190.0) / (crown_top - 190.0)
        return 17.0 - 5.0 * t * t

    def ring(z, grow=0.0):
        h = half(z) + grow
        return rounded_square(h, h, h * 0.36, z)
    zs = [0.0, 12.0] + [12.0 + k * 8.0 for k in range(1, 33) if 12.0 + k * 8.0 < top_body] + [top_body]
    loft(mb, [ring(-0.3, -1.0), ring(12.0, -1.0)], "office")             # the lobby, set back
    loft(mb, [ring(z) for z in zs[1:]], "curtain")
    z = 16.2
    while z < top_body:                                                 # the sunshades, a band each storey
        loft(mb, [ring(z, 0.25), ring(z + 0.5, 0.25)], "frame")
        z += 4.2
    loft(mb, [ring(top_body, 0.3), ring(top_body + 1.0, 0.3)], "frame")
    # The crown: an open lattice of white fins and rings round a glowing screen.
    loft(mb, [ring(top_body + 1.0, -2.2), ring(crown_top - 3.0, -2.2)], "lamp")
    pts0, pts1 = ring(top_body + 1.0), ring(crown_top)
    for k in range(0, len(pts0), 2):
        beam(mb, pts0[k], pts1[k], 0.45, "frame")
    for zz in (top_body + 7.0, top_body + 14.0, top_body + 21.0, crown_top):
        loft(mb, [ring(zz - 0.5), ring(zz)], "frame", caps=False)
    loft(mb, [ring(crown_top - 3.0, -2.2), ring(crown_top - 2.6, -2.2)], "metal")
    beacon(mb, 0.0, 0.0, crown_top - 2.6, 2.0)
    return mb, (w, d, crown_top + 0.1, 0.0)


# ------------------------------------------------- company projects (tech layer)

def launch_tower():
    # SpaceX's launch tower: a square steel lattice (four columns, a ring every
    # 10 m, cross-braced faces), two "chopstick" arms reaching out (+x) to the
    # rocket, and a crane and mast on top. Dark steel throughout.
    w = d = 12.0
    mb = Builder()
    half = 4.5
    mb.box(-6.0, 6.0, -6.0, 6.0, -0.3, 1.0, "sheet")                      # the concrete base
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box(sx * half - 0.6, sx * half + 0.6, sy * half - 0.6, sy * half + 0.6, 1.0, 140.0, "metal")
    for z in range(10, 141, 10):
        for (x0, y0, x1, y1) in ((-half, -half, half, -half), (half, -half, half, half),
                                 (half, half, -half, half), (-half, half, -half, -half)):
            beam(mb, (x0, y0, z), (x1, y1, z), 0.5, "metal")
    for z in range(1, 131, 10):
        z1 = z + 9
        for (x0, y0, x1, y1) in ((-half, -half, half, -half), (half, -half, half, half),
                                 (half, half, -half, half), (-half, half, -half, -half)):
            beam(mb, (x0, y0, z), (x1, y1, z1), 0.3, "metal")
            beam(mb, (x1, y1, z), (x0, y0, z1), 0.3, "metal")
    # The chopsticks: a carriage on the tower and two long arms towards the rocket.
    mb.box(half, half + 1.6, -half - 0.6, half + 0.6, 92.0, 100.0, "metal")
    for y in (-3.4, 3.4):
        beam(mb, (half + 1.0, y, 96.0), (half + 13.0, y, 96.0), 1.2, "metal", 2.4)
    mb.box(-6.5, 6.5, -6.5, 6.5, 140.0, 141.2, "metal")                    # the top deck
    beam(mb, (0.0, 0.0, 141.2), (-14.0, 0.0, 147.0), 0.8, "metal")           # its crane jib
    mb.box(-0.3, 0.3, -0.3, 0.3, 141.2, 152.0, "metal")                    # lightning mast
    beacon(mb, 0.0, 0.0, 152.0)
    return mb, (w, d, 152.7, 0.0)


def rocket():
    # A two-stage stainless rocket on its launch mount: the booster with grid fins
    # near its top, a dark ring between the stages, the ship with its flaps and
    # nose. The stainless takes the wall colour (render).
    w = d = 11.0
    mb = Builder()
    revolve(mb, 0.0, 0.0, [(4.2, 0.0, "metal"), (4.5, 2.0, "metal"), (4.5, 69.0, "render"), (4.5, 71.5, "metal"),
                           (4.5, 112.0, "render"), (4.2, 115.5, "render"), (3.4, 118.5, "render"),
                           (2.1, 121.0, "render"), (0.5, 122.8, "render")], 20)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        c, s = math.cos(a), math.sin(a)
        beam(mb, (c * 4.3, s * 4.3, 66.0), (c * 6.2, s * 6.2, 66.0), 0.4, "metal", 3.0)     # grid fins
    for z0, z1, out in ((74.0, 82.0, 6.4), (106.0, 111.0, 5.8)):
        for side in (-1, 1):
            beam(mb, (side * 4.3, 0.0, z0), (side * out, 0.0, z0 + 1.0), 0.3, "metal", 0.0 + (z1 - z0))   # flaps
    mb.box(-5.5, 5.5, -5.5, 5.5, -0.3, 0.0, "sheet")                       # the launch mount
    return mb, (w, d, 122.8, 0.0)


def dc_hall():
    # One bay of a data centre hall (bays are repeated side by side along a hall):
    # windowless cladding in the wall colour with panel joints, a dark band of
    # louvres high up, a roller door at the front, and a parapet in the second colour.
    w, d, h = 30.0, 40.0, 14.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h - 1.0, "cladding")
    mb.box(-w / 2 - 0.15, w / 2 + 0.15, -d / 2 - 0.15, d / 2 + 0.15, h - 1.0, h, "sheet")      # parapet
    for y in (d / 2, -d / 2):
        out = 1 if y > 0 else -1
        for k in range(11):                                                     # panel joints
            x = -w / 2 + 1.5 + k * 2.7
            mb.box(x - 0.07, x + 0.07, min(y, y + 0.08 * out), max(y, y + 0.08 * out), 0.0, h - 1.0, "metal")
        y0, y1 = (y, y + 0.12) if out > 0 else (y - 0.12, y)
        mb.box(-w / 2 + 1.0, w / 2 - 1.0, y0, y1, 9.0, 11.5, "metal")              # louvres
    mb.box(-3.0, 3.0, d / 2, d / 2 + 0.12, 0.0, 5.0, "sheet")                     # roller door
    return mb, (w, d, h, 0.0)


def ai_hall():
    # One bay of OpenAI's hall: taller and darker, ribbed all over with vertical
    # fins, two bands of louvres, and stair towers at the front corners.
    w, d, h = 30.0, 40.0, 18.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h - 1.2, "cladding")
    mb.box(-w / 2 - 0.2, w / 2 + 0.2, -d / 2 - 0.2, d / 2 + 0.2, h - 1.2, h, "sheet")        # pale band
    for y, s in ((d / 2, 1), (-d / 2, -1)):
        for k in range(15):                                                     # fins
            x = -w / 2 + 1.0 + k * 2.0
            mb.box(x - 0.12, x + 0.12, min(y, y + 0.45 * s), max(y, y + 0.45 * s), 0.0, h - 1.2, "metal")
        for z0 in (4.0, 11.5):                                                  # louvre bands
            mb.box(-w / 2 + 0.5, w / 2 - 0.5, min(y, y + 0.2 * s), max(y, y + 0.2 * s), z0, z0 + 2.2, "metal")
    for x in (-w / 2 + 2.5, w / 2 - 2.5):                                       # stair towers
        mb.box(x - 2.0, x + 2.0, d / 2, d / 2 + 3.5, 0.0, h + 1.5, "sheet")
    return mb, (w, d, h + 1.5, 0.0)


def gigafactory_bay():
    # One bay of Tesla's factory: a tall white wall (the wall colour), a deep black
    # band along the top (the second colour), tall strips of glazing, and loading
    # doors at the back.
    w, d, h = 40.0, 60.0, 22.0
    mb = Builder()
    mb.box(-w / 2, w / 2, -d / 2, d / 2, 0.0, h - 5.0, "render")
    mb.box(-w / 2 - 0.2, w / 2 + 0.2, -d / 2 - 0.2, d / 2 + 0.2, h - 5.0, h, "sheet")        # black band
    for k in range(5):                                                          # glazing strips, front
        x = -w / 2 + 4.0 + k * 8.0
        mb.box(x - 1.0, x + 1.0, d / 2, d / 2 + 0.1, 2.0, h - 6.0, "glass")
    for k in range(3):                                                          # loading doors, back
        x = -w / 2 + 8.0 + k * 12.0
        mb.box(x - 2.2, x + 2.2, -d / 2 - 0.12, -d / 2, 0.0, 5.0, "metal")
    return mb, (w, d, h, 0.0)


def google_pavilion(storeys):
    # A tech campus pavilion: glass all round in a light frame, white floor bands,
    # a recessed glass ground floor on slim columns, a canopy over the door, and a
    # planted roof under an overhanging white edge. The glass takes the wall colour.
    w, d, storey = 34.0, 22.0, 3.6
    top = storeys * storey
    mb = Builder()
    mb.box(-w / 2 + 1.6, w / 2 - 1.6, -d / 2 + 1.6, d / 2 - 1.6, 0.0, storey, "curtain")
    mb.box(-w / 2, w / 2, -d / 2, d / 2, storey, top, "curtain")
    for k in range(9):                                                      # ground floor columns
        x = -w / 2 + 0.4 + k * (w - 0.8) / 8
        for y in (-d / 2 + 0.4, d / 2 - 0.4):
            mb.box(x - 0.25, x + 0.25, y - 0.25, y + 0.25, 0.0, storey, "frame")
    for n in range(1, storeys + 1):                                         # floor bands
        z = n * storey
        mb.box(-w / 2 - 0.3, w / 2 + 0.3, -d / 2 - 0.3, d / 2 + 0.3, z - 0.3, z + 0.2, "frame")
    for x in [-w / 2 + 1.5 + k * 1.55 for k in range(21)]:                  # mullions, front and back
        for y in (d / 2, -d / 2):
            mb.box(x - 0.06, x + 0.06, y - 0.08, y + 0.08, storey, top, "frame")
    for y in [-d / 2 + 1.5 + k * 1.58 for k in range(13)]:                  # and the ends
        for x in (w / 2, -w / 2):
            mb.box(x - 0.08, x + 0.08, y - 0.06, y + 0.06, storey, top, "frame")
    mb.box(-4.5, 4.5, d / 2 - 1.6, d / 2 + 3.0, 3.1, 3.45, "frame")         # the door canopy
    mb.box(-w / 2 - 1.2, w / 2 + 1.2, -d / 2 - 1.2, d / 2 + 1.2, top + 0.2, top + 0.6, "frame")   # roof edge
    mb.box(-w / 2 + 0.6, w / 2 - 0.6, -d / 2 + 0.6, d / 2 - 0.6, top + 0.6, top + 0.8, "green")   # planted roof
    return mb, (w, d, top + 0.8, 0.0)


MODELS = {
    "villa": villa, "villa_b": lambda: villa("b"), "villa_c": lambda: villa("c"),
    "bungalow": bungalow, "bungalow_b": lambda: bungalow("b"),
    "terrace": terrace, "terrace_b": lambda: terrace("b"),
    "tenement3": lambda: tenement(3), "tenement3_b": lambda: tenement(3, "b"),
    "tenement4": lambda: tenement(4), "tenement4_b": lambda: tenement(4, "b"),
    "shop1": lambda: shop_parade(False), "shop1_b": lambda: shop_parade(False, "b"),
    "shop2": lambda: shop_parade(True), "shop2_b": lambda: shop_parade(True, "b"),
    "shopflats2": lambda: shops_with_flats(2), "shopflats3": lambda: shops_with_flats(3),
    "shopflats4": lambda: shops_with_flats(4),
    "shed": shed, "works": works, "warehouse": warehouse,
    "fire_station": fire_station, "fire_tower": fire_tower, "school": school, "hospital": hospital,
    "modern_base": modern_base, "modern_floor": modern_floor, "modern_floor_b": lambda: modern_floor("b"),
    "glass_floor": glass_floor, "modern_top": modern_top,
    "tower_stone": tower_stone, "tower_grid": tower_grid, "tower_band": tower_band,
    "crown_plant": crown_plant, "crown_deco": crown_deco, "crown_spire": crown_spire, "crown_slope": crown_slope,
    "coal_plant": coal_plant, "gas_plant": gas_plant, "nuclear_plant": nuclear_plant,
    "clubhouse": clubhouse, "museum_wing": museum_wing, "stand": stand, "water_tower": water_tower,
    "eiffel": eiffel, "big_ben": big_ben, "empire_state": empire_state, "liberty": liberty,
    "opera_house": opera_house, "taj_mahal": taj_mahal, "colosseum": colosseum, "great_pyramid": great_pyramid,
    "painted_lady": painted_lady, "coit_tower": coit_tower, "ferry_building": ferry_building,
    "fine_arts": fine_arts, "transamerica": transamerica, "salesforce_tower": salesforce_tower,
    "strip_mall": strip_mall, "strip_mall_b": lambda: strip_mall("b"),
    "glass_office2": lambda: glass_office(2), "glass_office3": lambda: glass_office(3),
    "ranch": ranch, "mission": mission, "ca_villa": ca_villa, "ca_modern": ca_modern,
    "ca_townhouse": ca_townhouse, "ca_townhouse_b": lambda: ca_townhouse("b"),
    "ca_apartments3": lambda: ca_apartments(3), "ca_apartments3_b": lambda: ca_apartments(3, "b"),
    "ca_apartments4": lambda: ca_apartments(4), "ca_apartments4_b": lambda: ca_apartments(4, "b"),
    "launch_tower": launch_tower, "rocket": rocket,
    "dc_hall": dc_hall, "ai_hall": ai_hall, "gigafactory_bay": gigafactory_bay,
    "google_pavilion3": lambda: google_pavilion(3), "google_pavilion4": lambda: google_pavilion(4),
    "ca_quad": ca_quad, "ca_bell_tower": ca_bell_tower, "ca_college": ca_college, "ca_lab": ca_lab,
}
for _n in range(2, 8):
    MODELS["classical%d" % _n] = (lambda n: lambda: classical(n, "plain"))(_n)
    MODELS["classical%d_shops" % _n] = (lambda n: lambda: classical(n, "shops"))(_n)
for _n in range(5, 8):
    MODELS["classical%d_bays" % _n] = (lambda n: lambda: classical(n, "bays"))(_n)
for _n in range(2, 5):
    MODELS["ca_mainstreet%d" % _n] = (lambda n: lambda: ca_mainstreet(n))(_n)
    MODELS["ca_mainstreet%d_b" % _n] = (lambda n: lambda: ca_mainstreet(n, "b"))(_n)
for _n in range(2, 8):
    MODELS["ca_classical%d" % _n] = (lambda n: lambda: ca_classical(n, "plain"))(_n)
    MODELS["ca_classical%d_shops" % _n] = (lambda n: lambda: ca_classical(n, "shops"))(_n)
for _n in range(5, 8):
    MODELS["ca_classical%d_bays" % _n] = (lambda n: lambda: ca_classical(n, "bays"))(_n)


# ------------------------------------------------------------- Blender side

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    mats = []
    for name, col in MATERIALS.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.15 if name == "glass" else 0.8
        mats.append(m)
    return mats


def to_object(name, mb, mats):
    me = bpy.data.meshes.new(name)
    me.from_pydata(mb.verts, [], mb.faces)
    me.update()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mb.mats)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)


def render_preview(objs, folder):
    """Renders each model on its own, from the front corner, into folder/<name>.png."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
    scene.render.resolution_x = 700
    scene.render.resolution_y = 520
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.78, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, -0.01))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.35, 0.18, 1)
    ground.data.materials.append(gm)
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.0
    sun_obj = bpy.data.objects.new("sun", sun)
    sun_obj.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun_obj)
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam_obj = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    for obj in objs:
        obj.hide_render = True
    for obj in objs:
        obj.hide_render = False
        size = max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z)
        cam.ortho_scale = size * 1.55
        target = (0.0, 0.0, obj.dimensions.z * 0.4)
        dist = 60.0
        yaw = math.radians(35)
        pitch = math.radians(28)
        cam_obj.location = (target[0] + dist * math.sin(yaw) * math.cos(pitch),
                            target[1] + dist * math.cos(yaw) * math.cos(pitch),
                            target[2] + dist * math.sin(pitch))
        direction = (target[0] - cam_obj.location[0], target[1] - cam_obj.location[1],
                     target[2] - cam_obj.location[2])
        import mathutils
        cam_obj.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(folder, obj.name + ".png")
        bpy.ops.render.render(write_still=True)
        obj.hide_render = True


def main():
    out_dir = sys.argv[1]
    preview = sys.argv[2] if len(sys.argv) > 2 else ""
    os.makedirs(out_dir, exist_ok=True)
    sizes = {}
    clear_scene()
    mats = make_materials()
    objs = []
    only = set(filter(None, os.environ.get("ONLY", "").split(",")))   # e.g. ONLY=school,hospital
    for name, make in MODELS.items():
        if only and name not in only:
            continue
        mb, dims = make()
        obj = to_object(name, mb, mats)
        export(obj, os.path.join(out_dir, name + ".glb"))
        sizes[name] = dims
        objs.append(obj)
        print("%-11s %6d triangles  %s" % (name, sum(len(f) - 2 for f in mb.faces), dims))
    if preview:
        render_preview(objs, preview)


if __name__ == "__main__":
    main()
