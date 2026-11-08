"""Renders the Build menu pictures (assets/icons/<item>.png) in Blender.

Each picture is a little diorama of one plot, built from the same building
models the game uses (tools/make_buildings.py) and the same colours, laid out
like the game lays them out, with the same stone, slate, grass and tarmac photos.

    python tools/make_menu_pictures.py assets/icons assets/textures [only_this_item]
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_buildings as mb  # noqa: E402

# Colours from scripts/world3d.gd (linear, as the game uses them).
RED_SANDSTONE = (0.60, 0.34, 0.27)
BLONDE_SANDSTONE = (0.80, 0.69, 0.52)
WHITE_RENDER = (0.90, 0.89, 0.85)
CREAM_RENDER = (0.86, 0.80, 0.67)
GREY_RENDER = (0.66, 0.66, 0.64)
SLATE = (0.25, 0.27, 0.31)
SHED_METAL = (0.55, 0.58, 0.62)
SHED_GREEN = (0.36, 0.45, 0.40)
CONCRETE = (0.64, 0.64, 0.62)
PAVEMENT = (0.66, 0.65, 0.62)
DRIVEWAY = (0.58, 0.56, 0.53)
COURT = (0.55, 0.54, 0.50)
CAR_PARK = (0.20, 0.20, 0.21)
YARD = (0.50, 0.50, 0.48)
LAWN = (0.33, 0.52, 0.24)
HONEY_STONE = (0.84, 0.71, 0.50)
CREAM_STONE = (0.88, 0.84, 0.74)
MODERN_WHITE = (0.92, 0.92, 0.90)
GLASS_FRAME = (0.30, 0.33, 0.36)
TRIM = (0.93, 0.91, 0.86)
POLICE_BLUE = (0.10, 0.20, 0.50)
FIRE_RED = (0.72, 0.08, 0.06)
CROSS_RED = (0.82, 0.06, 0.06)
AMBULANCE_YELLOW = (0.92, 0.84, 0.16)
CRANE_YELLOW = (0.95, 0.74, 0.10)
SOIL = (0.32, 0.23, 0.16)
TURBINE_WHITE = (0.92, 0.93, 0.93)
PANEL_BLUE = (0.10, 0.15, 0.28)
TANK_GREY = (0.64, 0.70, 0.74)
GREEN_SPEC = (0.42, 0.68, 0.30)
BUNKER_SAND = (0.86, 0.80, 0.62)
BUS_RED = (0.70, 0.12, 0.12)
TRAIN_RED = (0.62, 0.12, 0.18)
TEAM_BLUE = (0.12, 0.28, 0.62)
HULL_WHITE = (0.94, 0.94, 0.92)
SHIP_HULL = (0.20, 0.22, 0.26)
CHARCOAL = (0.22, 0.23, 0.25)
HEDGE = (0.16, 0.30, 0.12)
CONTAINERS = [(0.62, 0.18, 0.12), (0.12, 0.30, 0.55), (0.75, 0.55, 0.10), (0.20, 0.45, 0.30)]
CAR_PAINT = [(0.55, 0.05, 0.05), (0.05, 0.12, 0.35), (0.85, 0.85, 0.85), (0.08, 0.08, 0.08), (0.45, 0.45, 0.47)]

TEXTURES = {}
AVERAGES = {}
_materials = {}


# ------------------------------------------------------------------ materials

def _load_textures(folder):
    for name in ("sandstone", "slate", "grass", "tarmac"):
        path = os.path.join(folder, name + ".jpg")
        if os.path.exists(path):
            img = bpy.data.images.load(path)
            TEXTURES[name] = img
            px = list(img.pixels[:])   # linear floats, RGBA
            n = len(px) // 4
            step = max(1, n // 4000)
            sums = [0.0, 0.0, 0.0]
            count = 0
            for k in range(0, n, step):
                for c in range(3):
                    sums[c] += px[k * 4 + c]
                count += 1
            AVERAGES[name] = [s / count for s in sums]


def _textured(nodes, links, tex, tint, metres):
    """A colour = tint x (photo / its average colour), projected from the box sides."""
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / metres, 1 / metres, 1 / metres)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    img = nodes.new("ShaderNodeTexImage")
    img.image = TEXTURES[tex]
    img.projection = "BOX"
    img.projection_blend = 0.3
    links.new(mapping.outputs["Vector"], img.inputs["Vector"])
    avg = AVERAGES[tex]
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    links.new(img.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (tint[0] / avg[0], tint[1] / avg[1], tint[2] / avg[2], 1.0)
    return mix.outputs["Result"]


def material(kind, tint=(0.8, 0.8, 0.8), rough=0.85, metal=0.0, emit=None):
    """kind: 'plain', 'stone' (sandstone photo), 'slate', 'grass', 'tarmac' or 'glass'."""
    key = (kind, tuple(round(c, 3) for c in tint), rough, metal)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new("%s_%d" % (kind, len(_materials)))
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    photo = {"stone": ("sandstone", 3.0), "slate": ("slate", 2.5), "grass": ("grass", 6.0),
             "tarmac": ("tarmac", 4.0)}.get(kind)
    if photo and photo[0] in TEXTURES:
        links.new(_textured(nodes, links, photo[0], tint, photo[1]), bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (tint[0], tint[1], tint[2], 1.0)
    _materials[key] = m
    return m


def model_materials(wall, roof, r):
    """One material per model part, as the game's model shader colours them."""
    def pick(x, options):
        return options[int(x * 6) % 6]
    doors = [(0.08, 0.16, 0.32), (0.10, 0.24, 0.16), (0.45, 0.08, 0.08), (0.05, 0.05, 0.06),
             (0.32, 0.10, 0.16), (0.06, 0.28, 0.30)]
    fascias = [(0.06, 0.20, 0.15), (0.06, 0.10, 0.22), (0.04, 0.04, 0.05), (0.35, 0.06, 0.08),
               (0.75, 0.70, 0.58), (0.20, 0.28, 0.30)]
    awnings = [(0.55, 0.10, 0.10), (0.10, 0.32, 0.20), (0.10, 0.16, 0.38), (0.50, 0.40, 0.10),
               (0.15, 0.15, 0.15), (0.45, 0.18, 0.30)]
    parts = {
        "stone": material("stone", wall), "roof": material("slate", roof, 0.65),
        "glass": material("plain", (0.05, 0.07, 0.09), 0.08, 0.35), "frame": material("plain", (0.88, 0.87, 0.82), 0.55),
        "door": material("plain", pick((r * 3.7) % 1, doors), 0.4), "metal": material("plain", (0.09, 0.09, 0.10), 0.45, 0.4),
        "pot": material("plain", (0.55, 0.30, 0.20)), "fascia": material("plain", pick((r * 5.3) % 1, fascias), 0.35),
        "render": material("plain", wall), "awning": material("plain", pick((r * 2.9) % 1, awnings)),
        "lead": material("plain", (0.30, 0.32, 0.34), 0.6), "cladding": material("plain", wall, 0.5, 0.35),
        "sheet": material("plain", roof, 0.5, 0.35), "accent": material("plain", roof, 0.4),
    }
    return [parts[name] for name in mb.MATERIALS]


# ------------------------------------------------------------------ the plot
# Plot frame, as in the game: "along" runs along the street (x), "back" is the
# distance in from the street edge, which is at y = +25 (the street is in front).

def _y(back, d):
    return 25.0 - back - d / 2


def _mesh_object(name, builder, materials):
    me = bpy.data.meshes.new(name)
    me.from_pydata(builder.verts, [], builder.faces)
    me.update()
    for m in materials:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", builder.mats)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def model(name, along, back, w, d, total_h=None, wall=BLONDE_SANDSTONE, roof=SLATE, r=0.3, z0=0.0):
    builder, dims = mb.MODELS[name]()
    if total_h is None:
        total_h = dims[2] + dims[3]          # as built, unstretched
    obj = _mesh_object(name, builder, model_materials(wall, roof, r))
    obj.location = (along, _y(back, d), z0)
    obj.scale = (w / dims[0], d / dims[1], total_h / (dims[2] + dims[3]))
    return obj


def box(along, back, w, d, h, colour, z0=0.0, kind="plain", rough=0.85):
    b = mb.Builder()
    y = _y(back, d)
    b.box(along - w / 2, along + w / 2, y - d / 2, y + d / 2, z0, z0 + h, "stone")
    return _mesh_object("box", b, [material(kind, colour, rough)] * len(mb.MATERIALS))


def slab(along, back, w, d, colour, lift=0.0, kind="plain"):
    return box(along, back, w, d, 0.12 + lift, colour, 0.0, kind)


def gabled(along, back, w, d, h, rise, colour, roof=SLATE, windows=True):
    """A simple block with a slate roof and rows of windows (like the game's plain blocks)."""
    box(along, back, w, d, h, colour, kind="stone")
    b = mb.Builder()
    y = _y(back, d)
    if rise > 0:
        sec = [(y - d / 2 - 0.4, h - 0.1), (y + d / 2 + 0.4, h - 0.1), (y, h + rise)]
        b.extrude_x(sec, along - w / 2 - 0.2, along + w / 2 + 0.2, "stone")
        _mesh_object("roof", b, [material("slate", roof, 0.65)] * len(mb.MATERIALS))
    if windows:
        g = mb.Builder()
        floors = max(1, int(h / 3.0))
        for f in range(floors):
            z = 1.0 + f * 3.0
            x = along - w / 2 + 1.6
            while x < along + w / 2 - 1.2:
                g.box(x - 0.55, x + 0.55, y + d / 2, y + d / 2 + 0.05, z, z + 1.5, "stone")
                x += 2.8
        _mesh_object("windows", g, [material("plain", (0.05, 0.07, 0.09), 0.1, 0.3)] * len(mb.MATERIALS))


def cylinder(along, back, radius, h, colour, z0=0.0, taper=1.0):
    b = mb.Builder()
    y = _y(back, 0)
    sides = 24
    bottom = [(along + radius * math.cos(2 * math.pi * k / sides), y + radius * math.sin(2 * math.pi * k / sides))
              for k in range(sides)]
    top = [(along + radius * taper * math.cos(2 * math.pi * k / sides), y + radius * taper * math.sin(2 * math.pi * k / sides))
           for k in range(sides)]
    pts = [(x, yy, z0) for x, yy in bottom] + [(x, yy, z0 + h) for x, yy in top]
    faces = [list(range(sides))[::-1], list(range(sides, 2 * sides))]
    for k in range(sides):
        j = (k + 1) % sides
        faces.append([k, j, sides + j, sides + k])
    b._add(pts, faces, "stone")
    return _mesh_object("cyl", b, [material("plain", colour, 0.8)] * len(mb.MATERIALS))


def tree(along, back, h=9.0, colour=(0.20, 0.36, 0.13), kind="broad"):
    cylinder(along, back, 0.18 + h * 0.015, h * 0.5, (0.30, 0.22, 0.15))
    y = _y(back, 0)
    if kind == "conifer":
        for k in range(3):
            cylinder(along, back, h * (0.22 - k * 0.05), h * 0.3, colour, h * (0.2 + k * 0.22), 0.0)
        return
    for dx, dy, dz, s in ((0, 0, 0.62, 0.32), (0.18, 0.1, 0.55, 0.22), (-0.15, -0.12, 0.6, 0.24), (0.05, -0.15, 0.75, 0.2)):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=h * s,
                                              location=(along + dx * h, y + dy * h, h * dz))
        o = bpy.context.active_object
        o.scale = (1.0, 1.0, 0.85)
        o.data.materials.append(material("plain", (colour[0] * (1 + dx), colour[1] * (1 + dz * 0.2), colour[2]), 0.95))


def car(along, back, colour, across=False):
    w, d = (1.8, 4.2) if not across else (4.2, 1.8)
    box(along, back, w, d, 0.8, colour, 0.25, rough=0.3)
    box(along, back + (0.3 if not across else 0), w * 0.85, d * 0.5, 0.6, (0.12, 0.14, 0.16), 1.05, rough=0.2)


def hedge(along, back, w, d, h=1.1):
    box(along, back, w, d, h, HEDGE, rough=0.95)


def fence(depth=48.0):
    for (a, b, w, d) in ((0, 0.5, 48, 0.15), (0, depth - 1.5, 48, 0.15), (-24, 0.5, 0.15, depth - 2), (24, 0.5, 0.15, depth - 2)):
        box(a, b, w, d, 2.4, (0.35, 0.38, 0.36))


def ground(kind="grass", sea=False, road=True):
    """The plot as a thick tile, with the street in front (and the sea for marinas and harbours)."""
    b = mb.Builder()
    b.box(-25, 25, -25, 25, -3.0, -0.02, "stone")
    _mesh_object("ground", b, [material("grass" if kind == "grass" else "plain",
                                        (0.20, 0.30, 0.12) if kind == "grass" else kind, 0.95)] * len(mb.MATERIALS))
    s = mb.Builder()
    s.box(-25.05, 25.05, -25.05, 25.05, -6.0, -3.0, "stone")
    _mesh_object("soil", s, [material("plain", (0.22, 0.16, 0.11))] * len(mb.MATERIALS))
    if road:
        t = mb.Builder()
        t.box(-25, 25, 25, 37, -3.0, 0.0, "stone")
        _mesh_object("road", t, [material("tarmac", (0.16, 0.16, 0.17), 0.9)] * len(mb.MATERIALS))
        for k in range(5):
            m = mb.Builder()
            m.box(-22 + k * 10, -18 + k * 10, 30.9, 31.1, 0.0, 0.03, "stone")
            _mesh_object("line", m, [material("plain", (0.9, 0.9, 0.86))] * len(mb.MATERIALS))
    if sea:
        w = mb.Builder()
        w.box(-25, 25, -60, -25, -4.0, -0.6, "stone")
        _mesh_object("sea", w, [material("plain", (0.04, 0.12, 0.18), 0.05, 0.2)] * len(mb.MATERIALS))


# ------------------------------------------------------------------ the items

def homes_0():
    ground()
    names = ["villa", "villa_b", "villa_c", "villa_b"]
    for k, along in enumerate((-17.25, -5.75, 5.75, 17.25)):
        w = 7.4
        house = along - 5.3 + w / 2
        model(names[k], house, 6.0, w, 8.0, 9.0, [BLONDE_SANDSTONE, RED_SANDSTONE, CREAM_RENDER, BLONDE_SANDSTONE][k],
              r=0.17 * k + 0.1)
        slab(along - 5.3 + w + 1.5, 0.0, 2.6, 14.0, DRIVEWAY)
        if k % 2 == 0:
            car(along - 5.3 + w + 1.5, 1.0, CAR_PAINT[k])
        hedge(house, 0.3, w, 0.8)
        tree(along + 1.5, 24.0, 8.0)
    for edge in (-11.5, 0.0, 11.5):
        hedge(edge, 0.3, 0.7, 45.0, 1.4)


def homes_1():
    ground()
    for row_back, kinds in ((4.0, ("terrace", "terrace_b", "terrace")), (37.0, ("terrace_b", "terrace", "terrace_b"))):
        for along, name in zip((-15.5, 0.0, 15.5), kinds):
            model(name, along, row_back, 15.0, 8.5, 9.4, BLONDE_SANDSTONE if row_back < 10 else RED_SANDSTONE)
        hedge(0.0, row_back - 3.6, 47.0, 0.7, 1.0)
    slab(0.0, 0.0, 48.0, 3.0, PAVEMENT)
    slab(0.0, 23.0, 48.0, 3.0, DRIVEWAY)
    for along in (-14.0, 9.0, 20.0):
        tree(along, 17.0, 8.0)


def modern_block(along, back, w, d, storeys, cladding, glassy=False, variant="modern_floor"):
    """A modern block stacked from storeys, as the game builds it, with balconies."""
    floor = "glass_floor" if glassy else variant
    model("modern_base", along, back, w, d, 4.6, cladding)
    body = max(storeys - 3, 1)
    for f in range(body):
        model(floor, along, back, w, d, 3.2, cladding, z0=4.6 + f * 3.2)
        side = 0.22 if f % 2 == 0 else -0.22
        box(along + w * side, back - 1.6, w * 0.44, 1.6, 0.22, TRIM, 4.6 + f * 3.2)
        box(along + w * side, back - 1.6, w * 0.44, 0.08, 1.05, (0.55, 0.66, 0.72), 4.82 + f * 3.2, rough=0.1)
    model("modern_top", along, back, w, d, None, cladding, z0=4.6 + body * 3.2)


TIMBER = (0.56, 0.38, 0.23)


def homes_2():
    ground("grass")
    model("classical6_bays", -12.5, 3.0, 21.0, 13.0, 27.6, HONEY_STONE)
    modern_block(12.5, 3.0, 21.0, 13.0, 8, TIMBER)
    slab(0.0, 17.5, 46.0, 15.0, LAWN)
    for along in (-15, 0, 15):
        tree(along, 25.0, 9.0)
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)


def shops_0():
    ground()
    for k, along in enumerate((-16.5, 0.0, 16.5)):
        model(("shop1", "shop1_b", "shop1")[k], along, 3.0, 15.5, 13.0, 4.6,
              (WHITE_RENDER, CREAM_RENDER, BLONDE_SANDSTONE)[k], r=0.2 + k * 0.3)
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    slab(0.0, 17.0, 47.0, 31.0, CAR_PARK)
    for k in range(8):
        car(-18 + k * 5.5, 20.0, CAR_PAINT[k % 5])


def shops_1():
    ground()
    for k, along in enumerate((-16.5, 0.0, 16.5)):
        model(("shop2", "shop2_b", "shop2")[k], along, 3.0, 15.5, 13.0, 10.2,
              (CREAM_RENDER, WHITE_RENDER, GREY_RENDER)[k], r=0.15 + k * 0.33)
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    slab(0.0, 17.0, 47.0, 31.0, CAR_PARK)
    for k in range(7):
        car(-17 + k * 6, 22.0, CAR_PAINT[(k + 2) % 5])


def shops_2():
    ground()
    model("classical5_shops", -12.5, 3.0, 23.0, 18.0, 24.2, HONEY_STONE, r=0.4)
    model("classical6_shops", 12.5, 3.0, 23.0, 18.0, 27.6, BLONDE_SANDSTONE, r=0.7)
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    box(0.0, 28.0, 40.0, 19.0, 9.0, CONCRETE)


def industry():
    ground(YARD)
    model("shed", 0.0, 6.0, 34.0, 28.0, 10.2, SHED_METAL, (0.44, 0.46, 0.50))
    for k in range(4):
        box(-14.0 + k * 3.0, 40.0, 2.5, 6.1, 2.6 * (1 + k % 2), CONTAINERS[k])
    for k in range(3):
        car(12.0 + k * 3.0, 0.8, CAR_PAINT[k])


def road():
    ground()
    slab(0.0, 19.0, 50.0, 12.0, (0.16, 0.16, 0.17), kind="tarmac")
    slab(0.0, 16.0, 50.0, 3.0, PAVEMENT)
    slab(0.0, 31.0, 50.0, 3.0, PAVEMENT)
    for k in range(5):
        slab(-20 + k * 10, 24.8, 4.0, 0.25, (0.9, 0.9, 0.86), 0.02)
    for along in (-16, 4, 18):
        tree(along, 6.0, 8.0)
    car(-6.0, 22.0, CAR_PAINT[0], across=True)


def grid():
    ground()
    slab(0.0, 19.0, 50.0, 12.0, (0.16, 0.16, 0.17), kind="tarmac")
    slab(0.0, 0.0, 12.0, 50.0, (0.16, 0.16, 0.17), lift=0.02, kind="tarmac")
    for (a, b) in ((-15, 4), (15, 36)):
        model("villa", a, b, 7.4, 8.0, 9.0, RED_SANDSTONE)


def bulldoze():
    ground((0.32, 0.25, 0.18))
    for k, (a, b, s) in enumerate(((-8, 18, 3.0), (-3, 22, 2.2), (4, 16, 2.6), (8, 26, 1.8))):
        box(a, b, s * 3, s * 2.5, s, (0.45 + k * 0.03, 0.40, 0.34))
    box(10.0, 8.0, 3.0, 6.0, 2.2, CRANE_YELLOW, 0.6)
    box(10.0, 9.0, 2.4, 2.4, 2.0, CRANE_YELLOW, 2.8)
    box(10.0, 4.0, 3.4, 1.0, 1.4, (0.25, 0.25, 0.25), 0.3)


def park():
    ground()
    slab(0.0, 0.0, 3.0, 50.0, (0.72, 0.66, 0.52))
    slab(0.0, 23.0, 50.0, 3.0, (0.72, 0.66, 0.52), 0.02)
    for (a, b, h) in ((-14, 8, 12), (-16, 36, 10), (13, 10, 9), (16, 34, 13), (-6, 40, 8), (7, 4, 8)):
        tree(a, b, h)
    tree(14, 22, 11, (0.10, 0.22, 0.13), "conifer")
    box(-6.0, 26.5, 2.0, 0.6, 0.9, (0.40, 0.28, 0.18))


def coal():
    ground(YARD)
    gabled(-6.0, 6.0, 30.0, 26.0, 18.0, 0.0, CONCRETE)
    for along in (12.0, 19.0):
        cylinder(along, 30.0, 3.0, 65.0, (0.75, 0.74, 0.72), taper=0.8)
    fence()


def gas():
    ground(YARD)
    model("shed", -6.0, 6.0, 30.0, 18.0, 16.0, (0.52, 0.60, 0.68), (0.44, 0.46, 0.50))
    box(-6.0, 27.0, 20.0, 12.0, 24.0, CONCRETE)
    for along in (10.0, 17.0):
        cylinder(along, 31.5, 1.6, 46.0, (0.78, 0.78, 0.76))
    cylinder(16.0, 15.0, 4.5, 8.0, (0.86, 0.86, 0.84))
    fence()


def nuclear():
    ground(YARD)
    for along in (-12.0, 12.0):
        cylinder(along, 42.0, 10.5, 44.0, (0.82, 0.82, 0.80), taper=0.8)
    box(-14.0, 5.0, 16.0, 14.0, 16.0, CONCRETE)
    cylinder(-14.0, 12.0, 6.5, 5.0, (0.74, 0.74, 0.72), 16.0, 0.8)
    box(10.0, 5.0, 24.0, 12.0, 12.0, (0.55, 0.62, 0.70))
    fence()


def wind():
    ground()
    slab(0.0, 22.0, 8.0, 8.0, YARD)
    cylinder(0.0, 25.0, 1.5, 62.0, TURBINE_WHITE, taper=0.6)
    y = _y(25.0, 0)
    b = mb.Builder()
    b.box(-1.5, 1.5, y - 4.5, y + 4.5, 60.5, 63.5, "stone")
    for k in range(3):
        a = math.radians(20 + k * 120)
        cx, cz = 0.0, 62.0
        tip = (cx + 34 * math.cos(a), cz + 34 * math.sin(a))
        nx, nz = -math.sin(a) * 0.7, math.cos(a) * 0.7
        pts = [(cx + nx, y + 4.6, cz + nz), (cx - nx, y + 4.6, cz - nz), (tip[0], y + 4.6, tip[1]),
               (cx + nx, y + 4.9, cz + nz), (cx - nx, y + 4.9, cz - nz), (tip[0], y + 4.9, tip[1])]
        b._add(pts, [[0, 2, 1], [3, 4, 5], [0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5]], "stone")
    _mesh_object("turbine", b, [material("plain", TURBINE_WHITE, 0.4)] * len(mb.MATERIALS))


def solar():
    ground()
    for k in range(6):
        y = _y(0, 0) - 7.0 - k * 7.2
        b = mb.Builder()
        t = math.radians(25)
        pts = [(-22, y - 1.8 * math.cos(t), 0.6), (22, y - 1.8 * math.cos(t), 0.6),
               (22, y + 1.8 * math.cos(t), 0.6 + 3.6 * math.sin(t)), (-22, y + 1.8 * math.cos(t), 0.6 + 3.6 * math.sin(t))]
        pts += [(x, yy, z + 0.12) for x, yy, z in pts]
        b.hexa(pts, "stone")
        _mesh_object("panel", b, [material("plain", PANEL_BLUE, 0.15, 0.4)] * len(mb.MATERIALS))


def power_line():
    ground()
    for along, back in ((-12.0, 12.0), (12.0, 38.0)):
        for dx in (-2.0, 2.0):
            box(along + dx, back, 0.4, 0.4, 26.0, (0.55, 0.57, 0.6))
        box(along, back, 10.0, 0.5, 0.5, (0.55, 0.57, 0.6), 22.0)
        box(along, back, 7.0, 0.5, 0.5, (0.55, 0.57, 0.6), 25.0)


def water_pump():
    ground(YARD)
    gabled(-12.0, 5.0, 12.0, 9.0, 5.5, 3.0, RED_SANDSTONE, windows=False)
    for along in (6.0, 18.0):
        cylinder(along, 21.0, 5.0, 7.0, TANK_GREY)
    box(0.0, 12.0, 20.0, 0.8, 0.8, CHARCOAL)
    fence()


def water_tower():
    ground()
    slab(0.0, 10.0, 30.0, 30.0, YARD)
    cylinder(0.0, 25.0, 2.4, 26.0, CONCRETE)
    cylinder(0.0, 25.0, 7.5, 9.0, (0.80, 0.82, 0.84), 26.0)
    box(14.0, 4.0, 6.0, 5.0, 3.0, CONCRETE)


def landfill():
    ground(SOIL)
    slab(0.0, 6.0, 44.0, 40.0, SOIL, 1.5)
    slab(0.0, 10.0, 34.0, 32.0, (0.40, 0.36, 0.30), 3.5)
    slab(2.0, 15.0, 22.0, 22.0, (0.36, 0.34, 0.29), 5.5)
    slab(-20.0, 0.0, 4.0, 10.0, YARD)
    box(-20.0, 2.0, 2.6, 7.0, 3.2, CRANE_YELLOW)
    fence()


def recycling():
    ground(YARD)
    model("shed", -5.0, 8.0, 32.0, 20.0, 12.0, SHED_GREEN, (0.44, 0.46, 0.50))
    for k in range(6):
        box(-19.0 + k * 6.5, 40.0, 2.6, 6.0, 2.4, [(0.20, 0.45, 0.25), (0.15, 0.30, 0.60), (0.50, 0.35, 0.20), (0.55, 0.55, 0.55)][k % 4])


def police():
    ground()
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    model("classical3", -7.0, 4.0, 30.0, 15.0, 17.4, BLONDE_SANDSTONE, r=0.05)
    box(-7.0, 3.6, 9.0, 0.3, 0.8, POLICE_BLUE, 3.3)
    slab(16.0, 3.0, 16.0, 45.0, CAR_PARK)
    for k in range(4):
        car(12.5 + (k % 2) * 7.0, 6.0 + (k // 2) * 8.0, (0.95, 0.95, 0.95))
    hedge(-7.0, 21.0, 30.0, 0.8, 1.2)


def fire():
    ground()
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    slab(-5.0, 3.0, 34.0, 5.0, CONCRETE)
    model("fire_station", -5.0, 8.0, 34.0, 18.0, None, RED_SANDSTONE, FIRE_RED)
    model("fire_tower", 19.0, 12.0, 6.0, 6.0, None, RED_SANDSTONE)
    slab(0.0, 27.0, 49.0, 22.0, YARD)
    box(-12.0, 30.0, 2.6, 8.5, 3.2, FIRE_RED)
    box(-6.0, 30.0, 2.6, 8.5, 3.2, FIRE_RED)


def school():
    ground()
    slab(0.0, 0.0, 49.0, 3.0, PAVEMENT)
    model("school", -4.0, 4.0, 38.0, 13.0, None, RED_SANDSTONE)
    slab(20.0, 3.0, 8.0, 15.0, CAR_PARK)
    slab(0.0, 19.0, 46.0, 29.0, LAWN)
    for b in (21.0, 46.0):
        slab(0.0, b, 38.0, 0.15, (0.92, 0.92, 0.88), 0.03)
    slab(0.0, 21.0, 0.15, 25.0, (0.92, 0.92, 0.88), 0.03)
    for k in range(4):
        tree(-21.5 + k * 14.3, 47.0, 9.0)


def hospital():
    ground()
    slab(18.5, 3.0, 12.0, 45.0, CAR_PARK)
    model("hospital", -6.0, 13.0, 34.0, 22.0, None, MODERN_WHITE, CROSS_RED)
    box(-6.0, 4.0, 16.0, 9.0, 5.0, (0.10, 0.17, 0.24), rough=0.08)
    box(-6.0, 4.0 - 0.6, 18.0, 0.6, 0.5, TRIM, 5.0)
    box(-6.0, 17.0, 14.0, 14.0, 0.3, CHARCOAL, 19.9)
    for along, w, d in ((-8.5, 1.0, 6.0), (-3.5, 1.0, 6.0), (-6.0, 4.0, 1.0)):
        box(along, 24.0 - d / 2, w, d, 0.05, WHITE_RENDER, 20.2)
    for along in (15.5, 21.0):
        box(along, 5.0, 2.3, 6.0, 2.8, AMBULANCE_YELLOW)


def golf():
    ground((0.30, 0.48, 0.20))
    slab(4.0, 18.0, 13.0, 11.0, GREEN_SPEC)
    slab(-6.0, 15.0, 5.0, 3.5, BUNKER_SAND)
    slab(13.0, 27.0, 4.5, 3.0, BUNKER_SAND)
    slab(-2.0, 43.0, 6.0, 4.0, GREEN_SPEC)
    box(6.0, 22.0, 0.08, 0.08, 2.4, (0.95, 0.95, 0.95))
    box(6.45, 22.0, 0.9, 0.05, 0.6, (0.85, 0.12, 0.10), 1.8)
    tree(-20, 10, 10, (0.10, 0.22, 0.13), "conifer")
    tree(20, 38, 9)
    tree(-18, 36, 11, (0.10, 0.22, 0.13), "conifer")


def library():
    ground()
    slab(0.0, 0.0, 49.0, 9.0, PAVEMENT)
    model("classical2", 0.0, 9.0, 26.0, 16.0, 14.0, CREAM_STONE, r=0.6)
    for k in range(4):
        box(-5.0 + k * 3.33, 6.0, 0.9, 0.9, 7.5, CREAM_STONE)
    box(0.0, 5.5, 12.0, 4.0, 0.9, CREAM_STONE, 7.5)
    for (a, b) in ((-20, 12), (20, 12), (-20, 26), (20, 26)):
        tree(a, b, 9.0)


def museum():
    ground()
    slab(0.0, 0.0, 49.0, 10.0, PAVEMENT)
    model("classical3", -5.0, 10.0, 34.0, 20.0, 17.4, HONEY_STONE, r=0.2)
    for k in range(6):
        box(-13.0 + k * 3.2, 7.0, 0.9, 0.9, 10.5, (0.92, 0.82, 0.62))
    box(-5.0, 6.5, 18.0, 4.0, 0.9, (0.92, 0.82, 0.62), 10.5)
    box(18.0, 14.0, 12.0, 16.0, 9.0, (0.10, 0.17, 0.24), rough=0.08)


def stadium():
    ground((0.45, 0.45, 0.43))
    slab(0.0, 14.0, 32.0, 22.0, LAWN)
    slab(0.0, 24.9, 0.15, 22.0, (0.92, 0.92, 0.88), 0.03)
    for back in (7.0, 37.0):
        box(0.0, back, 42.0, 6.0, 9.0, CONCRETE)
        box(0.0, back - 1.0, 44.0, 8.0, 0.5, TEAM_BLUE, 11.0)
    for along in (-20.0, 20.0):
        box(along, 14.0, 4.0, 22.0, 6.0, CONCRETE)
    for (a, b) in ((-22, 5), (22, 5), (-22, 44), (22, 44)):
        cylinder(a, b, 0.5, 30.0, CHARCOAL)
        box(a, b, 3.5, 0.6, 1.6, (1.0, 0.98, 0.9), 29.0)


def marina():
    ground(sea=True)
    model("shop1", -8.0, 5.0, 18.0, 11.0, 7.0, MODERN_WHITE, r=0.5)
    slab(10.0, 3.0, 22.0, 14.0, CAR_PARK)
    slab(0.0, 49.0, 2.4, 30.0, (0.55, 0.50, 0.42), -0.3)
    for k in range(4):
        back = 52.0 + k * 7.0
        for s in (-1, 1):
            box(s * 5.0, back, 8.0, 1.2, 0.5, (0.55, 0.50, 0.42), -0.4)
            box(s * 5.5, back + 2.0, 2.6, 8.0, 1.3, HULL_WHITE, -0.5)
            box(s * 5.5, back + 2.0, 0.15, 0.15, 11.0, (0.95, 0.95, 0.95), 0.8)


def town_hall():
    ground()
    slab(0.0, 0.0, 49.0, 12.0, PAVEMENT)
    model("classical3", 0.0, 12.0, 36.0, 18.0, 17.4, BLONDE_SANDSTONE, r=0.9)
    for k in range(4):
        box(-5.0 + k * 3.33, 9.0, 0.9, 0.9, 11.0, (0.9, 0.82, 0.66))
    box(0.0, 8.5, 12.0, 4.0, 0.9, (0.9, 0.82, 0.66), 11.0)
    gabled(0.0, 16.0, 7.0, 7.0, 32.0, 5.0, BLONDE_SANDSTONE)
    box(0.0, 15.8, 2.6, 0.2, 2.6, (0.95, 0.94, 0.9), 26.0)
    for along in (-18.0, 18.0):
        tree(along, 5.0, 8.0)


def bus_depot():
    ground(CAR_PARK)
    model("shed", 0.0, 24.0, 44.0, 22.0, 9.6, GREY_RENDER, (0.44, 0.46, 0.50))
    for k in range(5):
        box(-17.5 + k * 7.0, 4.0, 2.6, 12.0, 3.4, BUS_RED if k % 3 else (0.15, 0.45, 0.30))


def station():
    ground()
    model("classical2", 0.0, 3.0, 26.0, 11.0, 14.0, RED_SANDSTONE, r=0.33)
    slab(0.0, 15.0, 49.0, 4.0, PAVEMENT, 0.6)
    box(0.0, 15.0, 42.0, 5.0, 0.3, TRIM, 4.2)
    slab(0.0, 20.0, 49.0, 10.0, (0.30, 0.29, 0.28))
    for back in (22.0, 23.5, 26.0, 27.5):
        slab(0.0, back, 49.0, 0.12, (0.55, 0.55, 0.56), 0.1)
    box(-2.0, 21.6, 44.0, 3.0, 3.8, TRAIN_RED, 0.3)


def harbour():
    ground(CONCRETE, sea=True)
    model("shed", -10.0, 4.0, 26.0, 16.0, 12.0, SHED_METAL, (0.44, 0.46, 0.50))
    for k in range(8):
        box(6.0 + (k % 4) * 4.0, 8.0 + (k // 4) * 7.0, 2.5, 6.1, 2.6 * (1 + k % 2), CONTAINERS[k % 4])
    for along in (-12.0, 12.0):
        box(along, 46.0, 1.6, 1.6, 30.0, CRANE_YELLOW)
        box(along, 46.0, 1.4, 28.0, 1.4, CRANE_YELLOW, 28.0)
    box(0.0, 57.0, 44.0, 10.0, 6.5, SHIP_HULL, -2.0)
    box(-16.0, 57.0, 8.0, 9.0, 8.0, HULL_WHITE, 4.5)


def _district(colour, tall):
    ground()
    slab(0.0, 0.0, 50.0, 50.0, colour, 0.0)
    if tall:
        for f in range(20):
            model("glass_floor", -10.0, 6.0, 16.0, 14.0, 3.5, z0=f * 3.5)
        box(-10.0, 9.0, 8.0, 6.0, 3.0, CONCRETE, 70.0)
        model("classical6_shops", 12.0, 4.0, 21.0, 13.0, 27.6, HONEY_STONE)
    else:
        model("tenement4", -12.0, 3.0, 22.0, 13.0, 17.3, RED_SANDSTONE)
        model("villa_c", 12.0, 6.0, 7.4, 8.0, 9.2, BLONDE_SANDSTONE)


def cbd():
    _district((0.45, 0.25, 0.70), True)


def conservation():
    _district((0.70, 0.45, 0.20), False)


def normal():
    ground()
    model("terrace", -12.0, 4.0, 15.0, 8.5, 9.4, BLONDE_SANDSTONE)
    model("shop2", 12.0, 3.0, 15.5, 13.0, 10.2, CREAM_RENDER)


ITEMS = {
    "homes_0": homes_0, "homes_1": homes_1, "homes_2": homes_2, "shops_0": shops_0, "shops_1": shops_1,
    "shops_2": shops_2, "industry": industry, "road": road, "grid": grid, "bulldoze": bulldoze, "park": park,
    "coal": coal, "gas": gas, "nuclear": nuclear, "wind": wind, "solar": solar, "power_line": power_line,
    "water_pump": water_pump, "water_tower": water_tower, "landfill": landfill, "recycling": recycling,
    "police": police, "fire": fire, "school": school, "hospital": hospital, "golf": golf, "library": library,
    "museum": museum, "stadium": stadium, "marina": marina, "town_hall": town_hall, "bus_depot": bus_depot,
    "station": station, "harbour": harbour, "cbd": cbd, "conservation": conservation, "normal": normal,
}
TALL = {"coal": 1.9, "gas": 1.5, "nuclear": 1.45, "wind": 1.9, "cbd": 1.9, "power_line": 1.2, "harbour": 1.35,
        "marina": 1.2, "water_tower": 1.35, "stadium": 1.15, "town_hall": 1.25, "homes_2": 1.15,
        "hospital": 1.1, "shops_2": 1.15}


# ------------------------------------------------------------------ render

def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.62, 0.72, 0.86, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.2
    sun.angle = math.radians(3)
    sun_obj = bpy.data.objects.new("sun", sun)
    sun_obj.rotation_euler = (math.radians(42), math.radians(8), math.radians(-30))
    scene.collection.objects.link(sun_obj)
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam_obj = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    return scene, cam, cam_obj


def clear_items(keep):
    for obj in list(bpy.context.scene.collection.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)


def main():
    out_dir, tex_dir = sys.argv[1], sys.argv[2]
    only = set(filter(None, (sys.argv[3] if len(sys.argv) > 3 else "").split(",")))   # e.g. fire,school
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _load_textures(tex_dir)
    scene, cam, cam_obj = setup_scene()
    keep = {"sun", "cam"}
    import mathutils
    for name, make in ITEMS.items():
        if only and name not in only:
            continue
        clear_items(keep)
        make()
        tall = TALL.get(name, 1.0)
        target = mathutils.Vector((0.0, 6.0, 3.0 + (tall - 1.0) * 22.0))
        yaw, pitch = math.radians(38), math.radians(32)
        direction = mathutils.Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        cam_obj.location = target + direction * 150.0
        cam_obj.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        cam.ortho_scale = 60.0 * tall
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", name)


if __name__ == "__main__":
    main()
