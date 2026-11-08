# Builds small isometric SVG icons for the build menu, and line icons for its
# category rail, into scripts/icons.gd (as text, so Godot needs no import step).
import math, json, sys
S = 1.0
def P(x, y, z):
    return (32 + (x - y) * 0.866, 38 + (x + y) * 0.5 - z)
def hexc(c):
    return '#%02x%02x%02x' % tuple(max(0, min(255, int(v))) for v in c)
def rgb(h):
    h = h.lstrip('#'); return [int(h[i:i+2], 16) for i in (0, 2, 4)]
def shade(h, k):
    return hexc([v * k for v in rgb(h)])
def poly(pts, fill, extra=''):
    return '<polygon points="%s" fill="%s"%s/>' % (' '.join('%.1f,%.1f' % p for p in pts), fill, extra)

class Icon:
    def __init__(self): self.parts = []
    def add(self, s): self.parts.append(s)
    def ground(self, colour='#6f9a4a', half=17, edge=None):
        c = [P(-half, -half, 0), P(half, -half, 0), P(half, half, 0), P(-half, half, 0)]
        self.add(poly([P(-half, half, 0), P(half, half, 0), P(half, half, -3), P(-half, half, -3)], shade(colour, 0.72)))
        self.add(poly([P(half, -half, 0), P(half, half, 0), P(half, half, -3), P(half, -half, -3)], shade(colour, 0.55)))
        self.add(poly(c, colour))
    def slab(self, x0, y0, x1, y1, colour, z=0.3):
        self.add(poly([P(x0, y0, z), P(x1, y0, z), P(x1, y1, z), P(x0, y1, z)], colour))
    def box(self, x0, y0, x1, y1, z0, z1, colour, windows=None, top=None):
        self.add(poly([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], shade(colour, 0.92)))
        self.add(poly([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], shade(colour, 0.70)))
        self.add(poly([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], top or shade(colour, 1.12)))
        if windows:
            wc, sx, sz = windows
            z = z0 + sz * 0.6
            while z + sz * 0.5 < z1 - 0.8:
                x = x0 + sx * 0.6
                while x + 1.2 < x1:
                    self.add(poly([P(x, y1 + 0.05, z), P(x + 1.3, y1 + 0.05, z), P(x + 1.3, y1 + 0.05, z + sz * 0.45), P(x, y1 + 0.05, z + sz * 0.45)], wc))
                    x += sx
                yy = y0 + sx * 0.6
                while yy + 1.2 < y1:
                    self.add(poly([P(x1 + 0.05, yy, z), P(x1 + 0.05, yy + 1.3, z), P(x1 + 0.05, yy + 1.3, z + sz * 0.45), P(x1 + 0.05, yy, z + sz * 0.45)], shade(wc, 0.8)))
                    yy += sx
                z += sz
    def gable(self, x0, y0, x1, y1, z, h, colour, wall):
        ym = (y0 + y1) / 2
        self.add(poly([P(x0, y0, z), P(x1, y0, z), P(x1, ym, z + h), P(x0, ym, z + h)], shade(colour, 1.1)))
        self.add(poly([P(x0, y1, z), P(x1, y1, z), P(x1, ym, z + h), P(x0, ym, z + h)], colour))
        self.add(poly([P(x1, y0, z), P(x1, y1, z), P(x1, ym, z + h)], shade(wall, 0.7)))
    def cyl(self, x, y, r, z0, z1, colour):
        cx, cy0 = P(x, y, z0); _, cy1 = P(x, y, z1)
        rx, ry = r * 1.22, r * 0.71
        self.add('<path d="M%.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 0 %.1f %.1f L%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f Z" fill="%s"/>' % (
            cx - rx, cy1, cx - rx, cy0, rx, ry, cx + rx, cy0, cx + rx, cy1, rx, ry, cx - rx, cy1, shade(colour, 0.82)))
        self.add('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>' % (cx, cy1, rx, ry, shade(colour, 1.1)))
    def taper(self, x, y, r0, r1, z0, z1, colour):
        cx, cy0 = P(x, y, z0); _, cy1 = P(x, y, z1)
        self.add(poly([(cx - r0 * 1.22, cy0), (cx + r0 * 1.22, cy0), (cx + r1 * 1.22, cy1), (cx - r1 * 1.22, cy1)], shade(colour, 0.85)))
        self.add('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>' % (cx, cy0, r0 * 1.22, r0 * 0.71, shade(colour, 0.85)))
        self.add('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" fill="%s"/>' % (cx, cy1, r1 * 1.22, r1 * 0.71, shade(colour, 0.6)))
    def tree(self, x, y, h=10, r=4.2, colour='#3f7a35', trunk='#5a3d26'):
        bx, by = P(x, y, 0); _, ty = P(x, y, h * 0.45)
        self.add('<rect x="%.1f" y="%.1f" width="1.6" height="%.1f" fill="%s"/>' % (bx - 0.8, ty, by - ty, trunk))
        cx, cy = P(x, y, h * 0.7)
        self.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (cx, cy, r, colour))
        self.add('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (cx - r * 0.3, cy - r * 0.35, r * 0.55, shade(colour, 1.25)))
    def cone_tree(self, x, y, h=12, r=3.5, colour='#2f5a33'):
        bx, by = P(x, y, 0); _, ty = P(x, y, h)
        self.add(poly([(bx - r, by - 1.5), (bx + r, by - 1.5), (bx, ty)], colour))
        self.add(poly([(bx, by - 1.5), (bx + r, by - 1.5), (bx, ty)], shade(colour, 0.75)))
    def raw(self, s): self.add(s)
    def svg(self):
        return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'>" + ''.join(self.parts).replace('"', "'") + "</svg>"

GRASS = '#6f9a4a'; PAVE = '#a7a49b'; ROAD = '#55595e'
SAND = '#c9a46b'; RED = '#9a5a45'; SLATE = '#4d5862'; WHITE = '#e6e5df'
LIT = '#f3c46a'; DARK = '#2e3a46'; GLASS = '#6fa3c8'; CONC = '#a9aaa6'
icons = {}

def villa():
    i = Icon(); i.ground(); i.slab(-15, 4, 15, 15, PAVE)
    i.box(-12, -10, 2, 2, 0, 8, SAND, (LIT, 4, 4)); i.gable(-12, -10, 2, 2, 8, 6, SLATE, SAND)
    i.tree(8, -6, 12, 4.5); i.tree(10, 6, 9, 3.5); return i
def terrace():
    i = Icon(); i.ground(); i.slab(-17, 7, 17, 17, PAVE)
    i.box(-14, -8, 14, 4, 0, 10, RED, (LIT, 3.5, 4.5)); i.gable(-14, -8, 14, 4, 10, 5, SLATE, RED)
    i.tree(10, -13, 9, 3.2); return i
def flats():
    i = Icon(); i.ground(); i.slab(-17, 6, 17, 17, PAVE)
    i.box(-13, -12, -1, 3, 0, 26, '#d7d2c4', (DARK, 3, 4)); i.box(2, -8, 12, 4, 0, 16, '#b88f62', (LIT, 3, 4))
    i.tree(10, 11, 8, 3); return i
def shop_small():
    i = Icon(); i.ground(); i.slab(-17, 3, 17, 17, PAVE)
    i.box(-12, -10, 8, 2, 0, 9, WHITE, (LIT, 4, 4.5)); i.gable(-12, -10, 8, 2, 9, 4, SLATE, WHITE)
    i.add(poly([P(-12, 2.1, 3.2), P(8, 2.1, 3.2), P(8, 5, 2.4), P(-12, 5, 2.4)], '#b8423a'))
    return i
def shop_mid():
    i = Icon(); i.ground(); i.slab(-17, 3, 17, 17, PAVE)
    i.box(-14, -10, 12, 2, 0, 15, SAND, (LIT, 3.5, 4)); i.add(poly([P(-14, 2.1, 3.5), P(12, 2.1, 3.5), P(12, 5, 2.6), P(-14, 5, 2.6)], '#2f5f4f'))
    return i
def offices():
    i = Icon(); i.ground('#8d918c'); i.box(-12, -12, 4, 2, 0, 30, GLASS, ('#cfe6f5', 2.5, 3))
    i.box(5, -6, 13, 4, 0, 14, '#cfc9ba', (DARK, 2.6, 3.5)); return i
def factory():
    i = Icon(); i.ground('#8a8a80'); i.box(-14, -10, 10, 6, 0, 9, '#8a9aa6')
    for k in range(3):
        x0 = -14 + k * 8
        i.add(poly([P(x0, -10, 9), P(x0, 6, 9), P(x0 + 4, 6, 13), P(x0 + 4, -10, 13)], shade('#6d7a84', 1.1)))
        i.add(poly([P(x0 + 4, -10, 13), P(x0 + 4, 6, 13), P(x0 + 8, 6, 9), P(x0 + 8, -10, 9)], '#55606a'))
    i.cyl(10, -10, 1.8, 0, 22, '#9a5a45'); return i
def road():
    i = Icon(); i.ground(); i.slab(-17, -6, 17, 6, ROAD)
    for k in range(4):
        x = -14 + k * 8; i.slab(x, -0.4, x + 4, 0.4, '#f0f0e8', 0.4)
    i.tree(-10, -13, 8, 3); i.tree(8, 12, 8, 3); return i
def grid():
    i = Icon(); i.ground()
    i.slab(-17, -3, 17, 3, ROAD); i.slab(-3, -17, 3, 17, ROAD); i.slab(-3, -3, 3, 3, '#5e6267', 0.35)
    i.box(6, 6, 14, 14, 0, 7, SAND); i.box(-14, -14, -6, -6, 0, 9, RED); return i
def bulldoze():
    i = Icon(); i.ground('#8b7a5c')
    i.box(-8, -6, 6, 6, 1, 7, '#e2b23a'); i.box(-6, -4, 1, 4, 7, 12, '#d3a12e', None, '#8fb6cf')
    i.box(6, -9, 9, 9, 0, 6, '#5d6064'); i.slab(-12, -8, 6, -6, '#2b2b2b', 1); i.slab(-12, 6, 6, 8, '#2b2b2b', 1); return i
def park():
    i = Icon(); i.ground('#78a854'); i.slab(-17, -1, 17, 1.5, '#d9c9a1')
    i.tree(-9, -9, 13, 5); i.tree(8, -8, 10, 4); i.tree(-8, 9, 10, 4, '#4f8a3c'); i.cone_tree(9, 9, 13); return i
def coal():
    i = Icon(); i.ground('#8b8b84'); i.box(-12, -8, 6, 8, 0, 12, '#9a5a45', (DARK, 3.5, 4))
    i.cyl(9, -9, 2.2, 0, 30, '#b0aca2'); i.raw('<circle cx="%.1f" cy="%.1f" r="4" fill="#c9c9c9" opacity="0.7"/>' % P(9, -9, 33)); return i
def gas():
    i = Icon(); i.ground('#8b8b84'); i.box(-14, -8, 4, 8, 0, 11, '#8aa0b4')
    i.cyl(9, -10, 1.6, 0, 30, '#c8c8c4'); i.cyl(12, -4, 1.6, 0, 30, '#c8c8c4'); i.cyl(9, 9, 4, 0, 6, '#e0e0dc'); return i
def nuclear():
    i = Icon(); i.ground('#8b8b84'); i.taper(-6, -6, 8, 5.5, 0, 22, '#d6d6d0'); i.taper(8, 6, 7, 5, 0, 18, '#d0d0ca')
    i.box(4, -12, 14, -3, 0, 8, '#9aa6b0'); return i
def wind():
    i = Icon(); i.ground('#7ba653')
    bx, by = P(0, 0, 0); hx, hy = P(0, 0, 36)
    i.raw('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="#e9eaea"/>' % (bx - 1.4, by, bx + 1.4, by, hx + 0.6, hy, hx - 0.6, hy))
    for a in (90, 210, 330):
        r = math.radians(a)
        i.raw('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="#f4f4f2"/>' % (hx, hy, hx + 17 * math.cos(r) - 1.3 * math.sin(r), hy - 17 * math.sin(r) - 1.3 * math.cos(r), hx + 17 * math.cos(r) + 1.3 * math.sin(r), hy - 17 * math.sin(r) + 1.3 * math.cos(r)))
    i.raw('<circle cx="%.1f" cy="%.1f" r="1.8" fill="#cfd0d0"/>' % (hx, hy)); return i
def solar():
    i = Icon(); i.ground('#7ba653')
    for k in range(4):
        y = -13 + k * 7.5
        i.add(poly([P(-14, y, 1), P(14, y, 1), P(14, y + 4, 4), P(-14, y + 4, 4)], '#22345a'))
        i.add(poly([P(-14, y + 4, 4), P(14, y + 4, 4), P(14, y + 4.2, 3.6), P(-14, y + 4.2, 3.6)], '#9fb3c8'))
    return i
def power_line():
    i = Icon(); i.ground('#7ba653')
    for (x, y) in ((-10, -10), (10, 10)):
        bx, by = P(x, y, 0); tx, ty = P(x, y, 26)
        i.raw('<polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="none" stroke="#c8ccd0" stroke-width="1.4"/>' % (bx - 3, by, bx + 3, by, tx, ty))
        i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#c8ccd0" stroke-width="1.4"/>' % (tx - 5, ty + 4, tx + 5, ty + 4))
    a = P(-10, -10, 22); b = P(10, 10, 22)
    i.raw('<path d="M%.1f %.1f Q%.1f %.1f %.1f %.1f" stroke="#2b2b2b" stroke-width="0.8" fill="none"/>' % (a[0] - 5, a[1], (a[0] + b[0]) / 2 - 5, (a[1] + b[1]) / 2 + 5, b[0] - 5, b[1]))
    i.raw('<path d="M%.1f %.1f Q%.1f %.1f %.1f %.1f" stroke="#2b2b2b" stroke-width="0.8" fill="none"/>' % (a[0] + 5, a[1], (a[0] + b[0]) / 2 + 5, (a[1] + b[1]) / 2 + 5, b[0] + 5, b[1]))
    return i
def water_pump():
    i = Icon(); i.ground('#8b8b84'); i.box(-13, -6, -3, 4, 0, 7, RED); i.gable(-13, -6, -3, 4, 7, 4, SLATE, RED)
    i.cyl(5, -6, 5, 0, 8, '#a8b7c2'); i.cyl(8, 8, 4, 0, 7, '#a8b7c2'); return i
def water_tower():
    i = Icon(); i.ground(); i.cyl(0, 0, 2.2, 0, 22, '#bdbdb6'); i.cyl(0, 0, 8, 22, 31, '#cdd6dc')
    i.tree(-11, 9, 9, 3); return i
def landfill():
    i = Icon(); i.ground('#7a6b52')
    i.add(poly([P(-14, -12, 0), P(12, -12, 0), P(12, 12, 0), P(-14, 12, 0)], '#6a5c45'))
    i.add(poly([P(-10, -8, 4), P(8, -8, 4), P(8, 8, 4), P(-10, 8, 4)], '#857458')); i.box(-10, -8, 8, 8, 0, 4, '#6a5c45', None, '#8a7a5d')
    i.box(-5, -4, 3, 4, 4, 8, '#5b6a3f', None, '#6d7e48'); i.box(9, 8, 14, 12, 0, 3.5, '#e2b23a'); return i
def recycling():
    i = Icon(); i.ground('#8b8b84'); i.box(-13, -11, 7, 3, 0, 10, '#4d7a4f')
    for k, c in enumerate(('#3d7f47', '#3c66a8', '#8a6a3e')):
        i.box(-12 + k * 7, 6, -7 + k * 7, 12, 0, 4, c)
    return i
def police():
    i = Icon(); i.ground(); i.slab(-17, 4, 17, 17, PAVE)
    i.box(-13, -10, 9, 3, 0, 12, '#d8c39a', (LIT, 3.5, 4)); i.add(poly([P(-6, 3.1, 8), P(2, 3.1, 8), P(2, 3.1, 10), P(-6, 3.1, 10)], '#1f3d8c'))
    i.box(10, 6, 14, 14, 0, 3.5, WHITE, None, '#3b5fc0'); return i
def fire():
    i = Icon(); i.ground(); i.slab(-17, 4, 17, 17, '#bdbab2')
    i.box(-14, -10, 6, 3, 0, 11, RED)
    for k in range(3):
        x = -12 + k * 6; i.add(poly([P(x, 3.1, 0), P(x + 4.5, 3.1, 0), P(x + 4.5, 3.1, 6), P(x, 3.1, 6)], '#c4281f'))
    i.box(8, -10, 13, -5, 0, 24, RED, (DARK, 3, 4)); return i
def school():
    i = Icon(); i.ground('#78a854'); i.box(-15, -12, 9, -2, 0, 10, RED, (LIT, 3.5, 4.5)); i.gable(-15, -12, 9, -2, 10, 5, SLATE, RED)
    i.slab(-12, 3, 14, 15, '#8fbf63', 0.35)
    i.raw('<rect x="%.1f" y="%.1f" width="0" height="0"/>' % P(0, 0, 0)); i.slab(-12, 8.8, 14, 9.2, '#f2f2ea', 0.45); return i
def hospital():
    i = Icon(); i.ground('#8d918c'); i.box(-13, -12, 9, 3, 0, 22, '#eceae4', ('#8fb1c9', 3, 3.5))
    cx, cy = P(-2, 3.2, 17); i.raw('<rect x="%.1f" y="%.1f" width="5" height="1.6" fill="#d22"/><rect x="%.1f" y="%.1f" width="1.6" height="5" fill="#d22"/>' % (cx - 2.5, cy - 0.8, cx - 0.8, cy - 2.5))
    i.box(10, 5, 15, 13, 0, 4, WHITE, None, '#e8c53a'); return i
def golf():
    i = Icon(); i.ground('#7cb257')
    cx, cy = P(2, 2, 0.3); i.raw('<ellipse cx="%.1f" cy="%.1f" rx="12" ry="6" fill="#9fd06f"/>' % (cx, cy))
    bx, by = P(-8, 8, 0.3); i.raw('<ellipse cx="%.1f" cy="%.1f" rx="5" ry="2.4" fill="#eadcae"/>' % (bx, by))
    fx, fy = P(4, 0, 0); i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#fff" stroke-width="1"/><polygon points="%.1f,%.1f %.1f,%.1f %.1f,%.1f" fill="#d63a2f"/>' % (fx, fy, fx, fy - 14, fx, fy - 14, fx + 6, fy - 12, fx, fy - 10))
    i.cone_tree(-12, -10, 12); i.tree(12, -12, 10, 3.5); return i
def library():
    i = Icon(); i.ground(); i.slab(-17, 4, 17, 17, PAVE)
    i.box(-13, -10, 11, 2, 0, 11, '#e2d6b6', (LIT, 3.5, 5))
    for k in range(4):
        x = -6 + k * 4; i.box(x, 3, x + 1.2, 4.2, 0, 9, '#f0e8d2')
    i.add(poly([P(-8, 4.5, 9), P(8, 4.5, 9), P(0, 4.5, 13)], '#d8ccb0')); return i
def museum():
    i = Icon(); i.ground(); i.slab(-17, 4, 17, 17, PAVE)
    i.box(-14, -11, 4, 2, 0, 13, '#d3b780', (LIT, 3.5, 5))
    for k in range(5):
        x = -12 + k * 3.6; i.box(x, 3, x + 1.2, 4.2, 0, 10, '#efe2c4')
    i.box(6, -6, 14, 4, 0, 9, GLASS, ('#d6ecf7', 2.5, 3)); return i
def stadium():
    i = Icon(); i.ground('#8d918c'); i.slab(-10, -7, 10, 7, '#6fb24d', 0.4)
    i.slab(-0.2, -7, 0.2, 7, '#f4f4f0', 0.5)
    i.box(-14, -13, 14, -9, 0, 7, '#c7c7c2', None, '#2d5aa8'); i.box(-14, 9, 14, 13, 0, 7, '#c7c7c2', None, '#2d5aa8')
    for (x, y) in ((-15, -14), (15, 14)):
        bx, by = P(x, y, 0); tx, ty = P(x, y, 22)
        i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#3b3b3b" stroke-width="1.2"/><rect x="%.1f" y="%.1f" width="5" height="2" fill="#fff8d0"/>' % (bx, by, tx, ty, tx - 2.5, ty - 2))
    return i
def marina():
    i = Icon()
    c = [P(-17, -17, 0), P(17, -17, 0), P(17, 17, 0), P(-17, 17, 0)]
    i.add(poly(c, '#3d7fa8'))
    i.add(poly([P(-17, -17, 0), P(17, -17, 0), P(17, -6, 0), P(-17, -6, 0)], '#d9c99d'))
    i.box(-12, -16, 2, -9, 0, 7, WHITE, (DARK, 3, 3.5))
    i.slab(-1, -6, 1, 16, '#9b8a6b', 0.5)
    for y in (0, 8):
        i.slab(1, y, 9, y + 1, '#9b8a6b', 0.5); i.box(-9, y - 1.5, -2, y + 1.5, 0, 1.5, '#ffffff')
        mx, my = P(-5.5, y, 1.5); i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#ddd" stroke-width="0.8"/>' % (mx, my, mx, my - 13))
    return i
def town_hall():
    i = Icon(); i.ground(); i.slab(-17, 4, 17, 17, PAVE)
    i.box(-14, -10, 12, 2, 0, 13, '#d9c393', (LIT, 3.5, 5)); i.box(-4, -6, 2, 0, 13, 25, '#d9c393')
    i.add(poly([P(-4, 0, 25), P(2, 0, 25), P(-1, -3, 31)], SLATE)); i.add(poly([P(2, -6, 25), P(2, 0, 25), P(-1, -3, 31)], shade(SLATE, 0.7)))
    cx, cy = P(-1, 0.1, 21); i.raw('<circle cx="%.1f" cy="%.1f" r="1.8" fill="#fbf6e6"/>' % (cx, cy)); return i
def bus_depot():
    i = Icon(); i.ground('#8d918c'); i.box(-14, -13, 10, -2, 0, 9, '#b9bcbe', None, '#7c8388')
    for k in range(3):
        y = 1 + k * 5; i.box(-12, y, 4, y + 3, 0, 4, '#c0352d', ('#cfe6f5', 2.4, 3))
    return i
def station():
    i = Icon(); i.ground('#8d918c'); i.slab(-17, 2, 17, 10, '#4a4642')
    i.slab(-17, 4.5, 17, 5, '#b9b9bb', 0.5); i.slab(-17, 7.5, 17, 8, '#b9b9bb', 0.5)
    i.box(-12, -12, 8, -3, 0, 9, RED, (LIT, 3.5, 4)); i.gable(-12, -12, 8, -3, 9, 4, SLATE, RED)
    i.box(-15, 4.6, 14, 7.6, 0.6, 4.5, '#a8233a', ('#d8ecf6', 3, 3)); return i
def harbour():
    i = Icon()
    i.add(poly([P(-17, -17, 0), P(17, -17, 0), P(17, 17, 0), P(-17, 17, 0)], '#3d7fa8'))
    i.add(poly([P(-17, -17, 0), P(17, -17, 0), P(17, -2, 0), P(-17, -2, 0)], '#a9aaa6'))
    for k, c in enumerate(('#c0392b', '#2e6fb5', '#e0a526')):
        i.box(-14 + k * 6, -14, -9 + k * 6, -9, 0, 3.5, c)
    bx, by = P(6, -5, 0); tx, ty = P(6, -5, 22)
    i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2b23a" stroke-width="2"/>' % (bx, by, tx, ty))
    ex, ey = P(6, 8, 22); i.raw('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2b23a" stroke-width="1.6"/>' % (tx, ty, ex, ey))
    i.box(-12, 4, 12, 11, -2, 3, '#2d3238'); i.box(-10, 5, -4, 10, 3, 8, WHITE); return i
def district(colour, low):
    i = Icon(); i.ground('#8a8f88')
    i.add(poly([P(-17, -17, 0.4), P(17, -17, 0.4), P(17, 17, 0.4), P(-17, 17, 0.4)], colour, " opacity='0.45'"))
    if low:
        i.box(-12, -10, 0, 0, 0, 9, SAND, (LIT, 3.5, 4)); i.gable(-12, -10, 0, 0, 9, 4, SLATE, SAND)
        i.box(3, 2, 13, 11, 0, 9, RED, (LIT, 3.5, 4)); i.gable(3, 2, 13, 11, 9, 4, SLATE, RED)
    else:
        i.box(-11, -11, -1, -1, 0, 34, GLASS, ('#d6ecf7', 2.5, 3)); i.box(3, -2, 12, 8, 0, 22, '#cfd3d6', (DARK, 2.5, 3))
    return i
def district_normal():
    i = Icon(); i.ground('#8a8f88')
    i.box(-12, -10, 0, 0, 0, 14, SAND, (LIT, 3.5, 4)); i.box(3, 2, 13, 11, 0, 9, RED, (LIT, 3.5, 4)); return i

builders = {
    'homes_0': villa, 'homes_1': terrace, 'homes_2': flats,
    'shops_0': shop_small, 'shops_1': shop_mid, 'shops_2': offices, 'industry': factory,
    'road': road, 'grid': grid, 'bulldoze': bulldoze, 'park': park,
    'coal': coal, 'gas': gas, 'nuclear': nuclear, 'wind': wind, 'solar': solar, 'power_line': power_line,
    'water_pump': water_pump, 'water_tower': water_tower, 'landfill': landfill, 'recycling': recycling,
    'police': police, 'fire': fire, 'school': school, 'hospital': hospital,
    'golf': golf, 'library': library, 'museum': museum, 'stadium': stadium, 'marina': marina, 'town_hall': town_hall,
    'bus_depot': bus_depot, 'station': station, 'harbour': harbour,
    'cbd': lambda: district('#9a62e8', False), 'conservation': lambda: district('#d08f45', True), 'normal': district_normal,
}
for k, f in builders.items():
    icons[k] = f().svg()

# Line icons for the category rail, the Build button and the price tag (white, 24 x 24).
def line(paths):
    return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' width='24' height='24' fill='none' stroke='white' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>" + paths + "</svg>"
rail = {
    'all': line("<rect x='4' y='4' width='6.5' height='6.5' rx='1.5'/><rect x='13.5' y='4' width='6.5' height='6.5' rx='1.5'/><rect x='4' y='13.5' width='6.5' height='6.5' rx='1.5'/><rect x='13.5' y='13.5' width='6.5' height='6.5' rx='1.5'/>"),
    'zones': line("<path d='M4 11 L12 4 L20 11'/><path d='M6 10 V20 H18 V10'/><path d='M10 20 V15 H14 V20'/>"),
    'roads': line("<path d='M8 3 L5 21'/><path d='M16 3 L19 21'/><path d='M12 4 V7'/><path d='M12 10.5 V13.5'/><path d='M12 17 V20'/>"),
    'power': line("<path d='M13 3 L6 13 H11.5 L10.5 21 L18 10 H12.5 Z'/>"),
    'utilities': line("<path d='M12 3.5 C9 8 6 11 6 14.5 A6 6 0 0 0 18 14.5 C18 11 15 8 12 3.5 Z'/>"),
    'services': line("<path d='M12 3 L19 6 V11.5 C19 16 16 19.5 12 21 C8 19.5 5 16 5 11.5 V6 Z'/><path d='M12 8.5 V15.5'/><path d='M8.5 12 H15.5'/>"),
    'leisure': line("<path d='M12 21 V13'/><circle cx='12' cy='9' r='5'/><path d='M8 21 H16'/>"),
    'transport': line("<rect x='5' y='3.5' width='14' height='14' rx='3'/><path d='M5 11 H19'/><circle cx='9' cy='14.5' r='0.6'/><circle cx='15' cy='14.5' r='0.6'/><path d='M8 17.5 L6.5 20.5'/><path d='M16 17.5 L17.5 20.5'/>"),
    'districts': line("<path d='M12 3.5 L20.5 8 L12 12.5 L3.5 8 Z'/><path d='M3.5 12 L12 16.5 L20.5 12'/><path d='M3.5 16 L12 20.5 L20.5 16'/>"),
    'build': line("<path d='M14.5 4 L20 9.5 L17.5 12 L12 6.5 Z'/><path d='M13.5 9.5 L5 18 A1.8 1.8 0 0 0 7.5 20.5 L16 12'/>"),
    'bulldoze': line("<path d='M4 18 H15'/><rect x='5' y='11' width='9' height='5' rx='1'/><path d='M7 11 V7.5 H11.5 L13 11'/><path d='M15 15 L20 12 V19 H15'/>"),
    'price': line("<path d='M12 3.5 L19.5 7.5 V16.5 L12 20.5 L4.5 16.5 V7.5 Z'/><path d='M4.5 7.5 L12 11.5 L19.5 7.5'/><path d='M12 11.5 V20.5'/>"),
    'lock': line("<rect x='5.5' y='10.5' width='13' height='9.5' rx='2'/><path d='M8.5 10.5 V7.5 A3.5 3.5 0 0 1 15.5 7.5 V10.5'/>"),
}
out = ['## Icons for the build menu, made by tools/make_icons.py (edit that, not this).',
       '## ITEMS: small isometric pictures (64 x 64); LINES: white line icons (24 x 24).',
       '', 'const ITEMS := {']
for k, v in icons.items():
    out.append('\t%s: "%s",' % (json.dumps(k), v))
out.append('}'); out.append(''); out.append('const LINES := {')
for k, v in rail.items():
    out.append('\t%s: "%s",' % (json.dumps(k), v))
out.append('}'); out.append('')
open(sys.argv[1], 'w').write('\n'.join(out))
# Also a preview sheet.
if len(sys.argv) > 2:
    cells = list(icons.items()) + [(k, v.replace("stroke='white'", "stroke='#222'")) for k, v in rail.items()]
    cols = 8; rows = (len(cells) + cols - 1) // cols
    sheet = ["<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'><rect width='100%%' height='100%%' fill='#30352f'/>" % (cols * 140, rows * 150)]
    for n, (k, v) in enumerate(cells):
        x = (n % cols) * 140 + 6; y = (n // cols) * 150 + 6
        bg = '#ffffff' if k in rail else '#23281f'
        sheet.append("<rect x='%d' y='%d' width='128' height='128' rx='18' fill='%s'/>" % (x, y, bg))
        sheet.append("<svg x='%d' y='%d' width='128' height='128' viewBox='%s'>%s</svg>" % (x, y, '0 0 24 24' if k in rail else '0 0 64 64', v.split('>', 1)[1].rsplit('</svg>', 1)[0]))
        sheet.append("<text x='%d' y='%d' fill='#ddd' font-size='12' font-family='sans-serif'>%s</text>" % (x + 4, y + 142, k))
    sheet.append('</svg>')
    open(sys.argv[2], 'w').write(''.join(sheet))
print(len(icons), 'items', len(rail), 'lines')
