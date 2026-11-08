"""Builds the Troon building models (.glb) for the game, in Blender.

Run with Blender's Python (pip package "bpy"):
    python tools/make_buildings.py assets/models [preview_folder]

Each model is one mesh with named materials that the game swaps for its own
shaders: stone, roof, glass, frame, door, metal, pot, fascia, render, awning, lead,
cladding (ribbed metal walls) and sheet (metal roofs).
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
    f.slab(mb, a0 + 0.3, a1 - 0.3, 0.6, 2.85, -0.03, 0.03, "glass")
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
    mb.box(-w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, -0.3, 1.4, "stone")     # brick base
    f, b, l, r = front(w, d), back(w, d), left(w, d), right(w, d)
    for a in (-10.0, -2.0):
        f.slab(mb, a - 2.4, a + 2.4, 0.0, 5.2, 0.0, 0.08, "sheet")                # roller doors
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
    "shed": shed,
}
for _n in range(2, 8):
    MODELS["classical%d" % _n] = (lambda n: lambda: classical(n, "plain"))(_n)
    MODELS["classical%d_shops" % _n] = (lambda n: lambda: classical(n, "shops"))(_n)
for _n in range(5, 8):
    MODELS["classical%d_bays" % _n] = (lambda n: lambda: classical(n, "bays"))(_n)


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
    for name, make in MODELS.items():
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
