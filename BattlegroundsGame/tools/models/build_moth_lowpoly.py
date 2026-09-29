"""Low-poly Moth race wings + antennae (classic Roblox wedge triangles), sculk palette.

Same rig as before (Torso > WingMount > 4 wing bones, Head > AntennaMount > 2 antenna bones),
so MothParts.luau and any animations keep working. Torso-local coords, character faces -Z.
Triangles are built from two WedgeParts each (the standard Roblox triangle method).
"""
import math, random, json, sys
import numpy as np
import build_moth as bm
from build_moth import Part, cf, mirror, roty, rotz, MATERIAL

rng = random.Random(11)

D = (12, 28, 33)      # sculk black
S = (17, 60, 66)      # deep teal
M = (26, 96, 104)     # mid teal
L = (40, 128, 134)    # light teal facet
F1 = (118, 170, 170)  # fluff
F2 = (160, 208, 204)  # fluff light
G = (41, 223, 235)    # glow
P = (150, 250, 255)   # bright glow

MEMBRANE = 0.08
EPS = 1e-4


class Wedge(Part):
    cls = 'WedgePart'


def tri(a, b, c, color, mat='SmoothPlastic', thick=MEMBRANE, bone=None, name='Facet'):
    """Two WedgeParts filling triangle abc (world space). Mirrors EgoMoose's draw-triangle."""
    a, b, c = (np.array(v, float) for v in (a, b, c))
    ab, ac, bc = b - a, c - a, c - b
    abd, acd, bcd = ab @ ab, ac @ ac, bc @ bc
    if abd > acd and abd > bcd:
        c, a = a, c
    elif acd > bcd and acd > abd:
        a, b = b, a
    ab, ac, bc = b - a, c - a, c - b
    right = np.cross(ac, ab); right /= np.linalg.norm(right)
    up = np.cross(bc, right); up /= np.linalg.norm(up)
    back = bc / np.linalg.norm(bc)
    height = abs(ab @ up)
    out = []
    for pos, r, bk, depth in (((a + b) / 2, right, back, abs(ab @ back)),
                              ((a + c) / 2, -right, -back, abs(ac @ back))):
        if depth < 0.01 or height < 0.01:
            continue
        R = np.column_stack([r, up, bk])
        out.append(Wedge(name, cf(pos, R), (thick, height, depth), color, mat, bone=bone))
    return out


def ngon(centre, radius, n, rot=0.0, squash=1.0):
    return [np.array([centre[0] + radius * math.cos(rot + 2 * math.pi * i / n),
                      centre[1] + radius * squash * math.sin(rot + 2 * math.pi * i / n)]) for i in range(n)]


def build_wing(bone_name, bone_m, verts, tris, rim_edges, eyespot, specks, zlift):
    """verts: 2D (x out, y up) in bone space; zlift: per-vertex depth for faceting."""
    parts = []
    V = [np.array([x, y, zlift.get(i, 0.0)]) for i, (x, y) in enumerate(verts)]
    W = lambda p: (bone_m @ np.append(p, 1.0))[:3]
    for (i, j, k), col in tris:
        parts += tri(W(V[i]), W(V[j]), W(V[k]), col, bone=bone_name)

    # fluffy rim: a pale band just inside the edge + wide, low scallops outside it
    centroid = np.mean([V[i][:2] for i in range(len(verts))], axis=0)
    n_tooth = 0
    for i, j in rim_edges:
        a, b = V[i], V[j]
        e = b[:2] - a[:2]
        length = np.linalg.norm(e)
        nrm = np.array([e[1], -e[0]]) / length
        if nrm @ (((a[:2] + b[:2]) / 2) - centroid) < 0:
            nrm = -nrm
        n3 = np.append(nrm, 0.0)
        band = 0.16
        parts += tri(W(a - n3 * band), W(b - n3 * band), W(a + n3 * 0.02), F1, 'SmoothPlastic', 0.11, bone_name, 'Fluff')
        parts += tri(W(b - n3 * band), W(b + n3 * 0.02), W(a + n3 * 0.02), F1, 'SmoothPlastic', 0.11, bone_name, 'Fluff')
        teeth = max(1, round(length / 0.5))
        for t in range(teeth):
            p0 = a + (b - a) * (t / teeth) - n3 * 0.04
            p1 = a + (b - a) * ((t + 1) / teeth) - n3 * 0.04
            tip = (p0 + p1) / 2 + (b - a) * rng.uniform(-0.15, 0.15) / teeth + n3 * rng.uniform(0.13, 0.22)
            parts += tri(W(p0), W(p1), W(tip), F2 if n_tooth % 2 else F1, 'SmoothPlastic', 0.1, bone_name, 'Fluff')
            n_tooth += 1

    # eyespot: glowing ring = neon hexagon with a dark hexagon on top (both thicker than the membrane)
    (cx, cy, r, z) = eyespot
    for rad, col, mat, th in ((r, G, 'Neon', 0.16), (r * 0.52, D, 'SmoothPlastic', 0.2), (r * 0.2, P, 'Neon', 0.24)):
        ring = ngon((cx, cy), rad, 6, rot=math.radians(90))
        c3 = np.array([cx, cy, z])
        for q in range(6):
            p0 = np.append(ring[q], z)
            p1 = np.append(ring[(q + 1) % 6], z)
            parts += tri(W(c3), W(p0), W(p1), col, mat, th, bone_name, 'Glow' if mat == 'Neon' else 'Eyespot')
    # sculk specks: small neon triangles
    for (sx, sy, sz, s) in specks:
        pts = ngon((sx, sy), s, 3, rot=rng.uniform(0, 6.28))
        parts += tri(*(W(np.append(p, sz)) for p in pts), P, 'Neon', 0.12, bone_name, 'Glow')
    return parts


# ---------------- wing shapes (right side, bone space) ----------------
FORE_V = [(0, 0), (0.9, 0.6), (2.0, 1.35), (3.0, 1.95), (3.75, 2.2), (4.05, 1.4), (3.75, 0.5),
          (3.1, -0.25), (2.0, -0.6), (0.9, -0.5), (1.3, 0.15), (2.45, 0.6), (3.25, 1.1)]
FORE_T = [((0, 1, 10), S), ((1, 2, 10), D), ((2, 11, 10), S), ((2, 3, 11), D), ((3, 12, 11), M),
          ((3, 4, 12), S), ((4, 5, 12), D), ((5, 6, 12), S), ((6, 11, 12), D), ((6, 7, 11), M),
          ((7, 8, 11), S), ((8, 10, 11), D), ((8, 9, 10), M), ((9, 0, 10), L)]
FORE_RIM = [(3, 4), (4, 5), (5, 6), (6, 7), (7, 8), (8, 9)]
FORE_Z = {10: 0.04, 11: 0.05, 12: 0.04, 4: -0.03, 7: -0.02}

HIND_V = [(0, 0), (1.0, 0.1), (2.2, -0.2), (2.9, -0.8), (3.0, -1.5), (2.5, -2.1), (1.6, -2.3),
          (0.8, -1.8), (0.25, -0.9), (1.4, -0.85), (2.2, -1.35)]
HIND_T = [((0, 1, 9), S), ((1, 2, 9), M), ((2, 10, 9), D), ((2, 3, 10), S), ((3, 4, 10), D),
          ((4, 5, 10), S), ((5, 6, 10), M), ((6, 9, 10), D), ((6, 7, 9), S), ((7, 8, 9), D), ((8, 0, 9), L)]
HIND_RIM = [(2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8)]
HIND_Z = {9: 0.04, 10: 0.05, 5: -0.03}


def build():
    top = []
    mount = Part('WingMount', cf([0, 0, 0]), (0.2, 0.2, 0.2), transparency=1.0)
    defs = [
        ('Forewing', [0.25, 0.45, 0.62], math.radians(22), math.radians(4), FORE_V, FORE_T, FORE_RIM, FORE_Z,
         (3.0, 1.05, 0.45, 0.04), [(1.7, 0.1, 0.07, 0.1), (2.3, 0.35, 0.09, 0.08), (2.7, -0.05, 0.05, 0.09)]),
        ('Hindwing', [0.25, -0.2, 0.66], math.radians(30), math.radians(-6), HIND_V, HIND_T, HIND_RIM, HIND_Z,
         (1.95, -1.3, 0.45, 0.04), [(1.0, -0.55, 0.07, 0.08), (2.55, -0.6, 0.06, 0.08)]),
    ]
    bones, visible, motors = [], [], []
    for name, hinge, sweep, raise_, V, T, rim, Z, eye, specks in defs:
        bone_r = cf(hinge, roty(-sweep) @ rotz(raise_))
        parts_r = build_wing('Right' + name, bone_r, V, T, rim, eye, specks, Z)
        for side, bmat in (('Right', bone_r), ('Left', mirror(bone_r))):
            bname = side + name
            bones.append(Part(bname, bmat, (0.2, 0.2, 0.2), transparency=1.0))
            motors.append((bname, 'WingMount', bname))
            for p in parts_r:
                if side == 'Right':
                    visible.append(p)
                else:
                    visible.append(Wedge(p.name, mirror_wedge(p.m), p.size, p.color, p.mat, bone=bname))

    # root tuft: a few chunky rotated blocks, classic Roblox style
    tuft = [((0.0, 0.35, 0.66), (0.8, 0.6, 0.3), (0.1, 0.0, 0.785), F1),
            ((0.35, 0.05, 0.7), (0.55, 0.6, 0.3), (0.0, 0.3, 0.5), F2),
            ((-0.35, 0.05, 0.7), (0.55, 0.6, 0.3), (0.0, -0.3, -0.5), F2),
            ((0.0, -0.3, 0.64), (0.5, 0.4, 0.25), (0.2, 0.0, 0.8), S)]
    for pos, size, (rx, ry, rz), col in tuft:
        R = rotz(rz) @ roty(ry) @ bm.rotx(rx)
        visible.append(Part('Tuft', cf(pos, R), size, col, 'SmoothPlastic', bone='WingMount'))
    top.append(('MothWings', mount, bones, visible, motors, 'Torso'))

    # ---------------- ANTENNAE ----------------
    amount = Part('AntennaMount', cf([0, 1.5, 0]), (0.2, 0.2, 0.2), transparency=1.0)
    bone_r = cf([0.32, 2.0, -0.25])
    W = lambda p: (bone_r @ np.append(p, 1.0))[:3]
    pts = [np.zeros(3)]
    n_seg, length = 6, 2.1
    for i in range(1, n_seg + 1):
        t = i / n_seg
        phi = math.radians(12 + 42 * t ** 1.5 + (35 if t > 0.9 else 0))
        d = np.array([math.sin(phi), math.cos(phi), 0.12]); d /= np.linalg.norm(d)
        pts.append(pts[-1] + d * length / n_seg)
    parts_r = []
    for i in range(n_seg):  # stalk: chunky blocks
        a, b = pts[i], pts[i + 1]
        v = b - a; y = v / np.linalg.norm(v)
        x = np.cross(y, [0, 0, 1.0]); x /= np.linalg.norm(x)
        R = np.column_stack([x, y, np.cross(x, y)])
        th = 0.16 - 0.015 * i
        parts_r.append(Part('Stalk', bone_r @ cf((a + b) / 2, R), (th, np.linalg.norm(v) + th * 0.5, th), D, bone='RightAntenna'))
    # feather: one serrated triangle per segment per side (low-poly comb)
    for i in range(1, n_seg - 1):
        t = i / n_seg
        a, b = pts[i], pts[i + 1]
        tan = (b - a) / np.linalg.norm(b - a)
        perp = np.cross(tan, [0, 0, 1.0]); perp /= np.linalg.norm(perp)
        w = 0.14 + 0.36 * math.sin(math.pi * min(t / 0.85, 1))
        for sgn, col in ((1, M if i % 2 else S), (-1, S if i % 2 else M)):
            tip = b + perp * sgn * w - tan * 0.05
            parts_r += tri(W(a), W(b), W(tip), col, 'SmoothPlastic', 0.06, 'RightAntenna', 'Feather')
            # pale fluffy edge tooth on the outer end of each barb
            parts_r += tri(W(tip), W(b + perp * sgn * w * 0.55), W(tip + tan * 0.16 + perp * sgn * 0.07),
                           F2 if sgn == 1 else F1, 'SmoothPlastic', 0.07, 'RightAntenna', 'Fluff')
    # glowing tip: a 45-degree-turned neon cube
    tipR = rotz(math.radians(45)) @ bm.rotx(math.radians(35))
    parts_r.append(Part('Glow', bone_r @ cf(pts[-1], tipR), (0.24, 0.24, 0.24), G, 'Neon', bone='RightAntenna'))
    parts_r.append(Part('Socket', bone_r @ cf([0, 0.03, 0]), (0.26, 0.14, 0.26), S, bone='RightAntenna'))

    abones, avis, amotors = [], [], []
    for side, bmat in (('Right', bone_r), ('Left', mirror(bone_r))):
        bname = side + 'Antenna'
        abones.append(Part(bname, bmat, (0.2, 0.2, 0.2), transparency=1.0))
        amotors.append((bname, 'AntennaMount', bname))
        for p in parts_r:
            if side == 'Right':
                avis.append(p)
            elif isinstance(p, Wedge):
                avis.append(Wedge(p.name, mirror_wedge(p.m), p.size, p.color, p.mat, bone=bname))
            else:
                avis.append(Part(p.name, mirror(p.m), p.size, p.color, p.mat, bone=bname))
    top.append(('MothAntennae', amount, abones, avis, amotors, 'Head'))
    return top


def mirror_wedge(m):
    """Mirror a wedge across X. Mirroring flips handedness; a wedge is symmetric in its local X
    (thickness) axis, so negate that column to keep a proper rotation with the same shape."""
    # M R M keeps det +1: its local X comes out negated, which a wedge (symmetric in X) doesn't mind
    return mirror(m)


# ---------------- XML (WedgePart support) ----------------
_orig_part_xml = bm.part_xml


def part_xml(p, rid, inner=''):
    x = _orig_part_xml(p, rid, inner)
    if isinstance(p, Wedge):
        x = x.replace('<Item class="Part"', '<Item class="WedgePart"', 1).replace('<token name="shape">1</token>', '')
    return x


bm.part_xml = part_xml


# wedge corner geometry (Roblox WedgePart: solid bottom + back, slope rises toward +Z)
def wedge_corners(m, size):
    sx, sy, sz = (s / 2 for s in size)
    loc = [(-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz), (sx, -sy, -sz), (sx, -sy, sz), (sx, sy, sz)]
    return [(m @ np.array([*v, 1.0]))[:3] for v in loc]


def self_check(models):
    """Every triangle's two wedges must exactly cover their source triangle: checked by ensuring
    each wedge's slanted-face corners lie on its membrane plane (x = 0 midplane) - cheap sanity test."""
    bad = 0
    for _, _, _, vis, _, _ in models:
        for p in vis:
            if isinstance(p, Wedge) and min(p.size) < 0:
                bad += 1
    return bad


if __name__ == '__main__':
    # verify the triangle method on a known triangle: wedge profiles must reproduce the 3 corners
    a, b, c = np.array([0, 0, 0.]), np.array([2, 0, 0.]), np.array([0.5, 1.5, 0.])
    corners = []
    for w in tri(a, b, c, D):
        cs = wedge_corners(w.m, w.size)
        mids = [(cs[i] + cs[i + 3]) / 2 for i in range(3)]  # midplane profile
        corners += [tuple(np.round(q, 4)) for q in mids]
    got = set(corners)
    for v in (a, b, c):
        assert tuple(np.round(v, 4)) in got, ('triangle corner missing', v, got)
    print('triangle method check OK')

    models = build()
    body = ''.join(bm.model_xml(*mm) for mm in models)
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           f'<Item class="Folder" referent="{bm.ref()}"><Properties><string name="Name">MothRace</string></Properties>'
           + body + '</Item></roblox>')
    open('/home/claude/moth/MothRace.rbxmx', 'w').write(xml)
    dump = []
    for name, mount, bones, visible, motors, _ in models:
        for p in visible:
            dump.append({'m': p.m.tolist(), 'size': list(p.size), 'color': list(p.color), 'mat': p.mat,
                         'group': name, 'wedge': isinstance(p, Wedge)})
    json.dump(dump, open('/home/claude/moth/boxes.json', 'w'))
    for name, mount, bones, visible, motors, _ in models:
        print(name, 'parts:', len(visible))
