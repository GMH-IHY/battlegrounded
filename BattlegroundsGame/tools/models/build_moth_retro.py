"""Retro / simplified Moth race wings + antennae (classic Roblox look, very few parts).

Same rig as before: Torso > WingMount > Right/Left Forewing/Hindwing, Head > AntennaMount > Right/Left Antenna.
Each wing = a flat dark plate (3 triangles) on a slightly bigger pale plate (the fluffy trim),
plus a glowing disc eyespot. Antennae = 2 block segments, 2 barbs a side, glowing ball tip.
"""
import math, json
import numpy as np
import build_moth as bm
import build_moth_lowpoly as lp
from build_moth import Part, cf, mirror, roty, rotz, rotx
from build_moth_lowpoly import Wedge, tri, mirror_wedge

DARK = (17, 52, 58)      # wing plate
DARK2 = (12, 38, 44)     # hindwing plate
TRIM = (122, 196, 196)   # fluffy trim
STALK = (12, 30, 35)
BARB = (26, 96, 104)
GLOW = (41, 223, 235)
PUPIL = (8, 20, 24)

PLATE = 0.14
TRIM_T = 0.1
SHAPE = {'Ball': 0, 'Block': 1, 'Cylinder': 2}

FORE = [(0, 0), (1.6, 1.3), (3.8, 2.1), (3.95, 0.6), (2.2, -0.5)]
HIND = [(0, 0), (2.4, -0.2), (2.9, -1.3), (2.0, -2.3), (0.6, -1.5)]
DISC_R = np.column_stack([[0, 0, 1.0], [1.0, 0, 0], [0, 1.0, 0]])  # cylinder axis (X) -> wing normal


def flat_poly(bone, bone_m, verts, color, thick, scale=1.0, name='Plate'):
    V = np.array([[x, y, 0.0] for x, y in verts])
    if scale != 1.0:
        c = V.mean(0)
        V = c + (V - c) * scale
    W = lambda p: (bone_m @ np.append(p, 1.0))[:3]
    out = []
    for k in range(1, len(V) - 1):  # fan
        out += tri(W(V[0]), W(V[k]), W(V[k + 1]), color, 'SmoothPlastic', thick, bone, name)
    return out


def disc(bone, bone_m, x, y, dia, thick, color, mat, name):
    p = Part(name, bone_m @ cf([x, y, 0], DISC_R), (thick, dia, dia), color, mat, bone=bone)
    p.shape = 'Cylinder'
    return p


def mirror_part(p, bone):
    if isinstance(p, Wedge):
        q = Wedge(p.name, mirror_wedge(p.m), p.size, p.color, p.mat, bone=bone)
    else:
        q = Part(p.name, mirror(p.m), p.size, p.color, p.mat, bone=bone)
        q.shape = getattr(p, 'shape', 'Block')
    return q


def build():
    top = []
    mount = Part('WingMount', cf([0, 0, 0]), (0.2, 0.2, 0.2), transparency=1.0)
    defs = [('Forewing', [0.25, 0.45, 0.62], 22, 4, FORE, DARK, (2.75, 0.9, 0.95)),
            ('Hindwing', [0.25, -0.2, 0.66], 30, -6, HIND, DARK2, (1.75, -1.15, 0.85))]
    bones, visible, motors = [], [], []
    for name, hinge, sweep, raise_, poly, col, (ex, ey, edia) in defs:
        bname = 'Right' + name
        bone_r = cf(hinge, roty(-math.radians(sweep)) @ rotz(math.radians(raise_)))
        parts = flat_poly(bname, bone_r, poly, TRIM, TRIM_T, scale=1.15, name='Trim')
        parts += flat_poly(bname, bone_r, poly, col, PLATE)
        parts.append(disc(bname, bone_r, ex, ey, edia, 0.2, GLOW, 'Neon', 'Glow'))
        parts.append(disc(bname, bone_r, ex, ey, edia * 0.45, 0.24, PUPIL, 'SmoothPlastic', 'Eyespot'))
        for side, bmat in (('Right', bone_r), ('Left', mirror(bone_r))):
            sb = side + name
            bones.append(Part(sb, bmat, (0.2, 0.2, 0.2), transparency=1.0))
            motors.append((sb, 'WingMount', sb))
            visible += parts if side == 'Right' else [mirror_part(p, sb) for p in parts]
    # fluffy collar: one pale block turned 45 degrees, classic hat style
    visible.append(Part('Tuft', cf([0, 0.2, 0.68], rotz(math.radians(45))), (0.85, 0.85, 0.3), TRIM, 'SmoothPlastic', bone='WingMount'))
    top.append(('MothWings', mount, bones, visible, motors, 'Torso'))

    # antennae
    amount = Part('AntennaMount', cf([0, 1.5, 0]), (0.2, 0.2, 0.2), transparency=1.0)
    bone_r = cf([0.3, 2.0, -0.2])
    parts = []

    def block(a, b, th, color, name):
        a, b = np.array(a, float), np.array(b, float)
        v = b - a; y = v / np.linalg.norm(v)
        x = np.cross(y, [0, 0, 1.0]); x /= np.linalg.norm(x)
        R = np.column_stack([x, y, np.cross(x, y)])
        return Part(name, bone_r @ cf((a + b) / 2, R), (th, np.linalg.norm(v) + th, th), color, bone='RightAntenna')

    p0, p1, p2 = [0, 0, 0], [0.35, 1.0, 0.1], [0.95, 1.75, 0.2]
    parts.append(block(p0, p1, 0.18, STALK, 'Stalk'))
    parts.append(block(p1, p2, 0.16, STALK, 'Stalk'))
    for base, d in (([0.2, 0.55, 0.05], 0.42), ([0.62, 1.35, 0.15], 0.4)):
        tan = np.array(p1 if base[1] < 1 else p2, float) - np.array(p0 if base[1] < 1 else p1, float)
        tan /= np.linalg.norm(tan)
        perp = np.cross(tan, [0, 0, 1.0]); perp /= np.linalg.norm(perp)
        for s in (1, -1):
            tip = np.array(base) + (perp * s * 0.77 + tan * 0.64) * d
            parts.append(block(base, tip, 0.1, BARB, 'Barb'))
    tipball = Part('Glow', bone_r @ cf(p2), (0.38, 0.38, 0.38), GLOW, 'Neon', bone='RightAntenna')
    tipball.shape = 'Ball'
    parts.append(tipball)
    abones, avis, amotors = [], [], []
    for side, bmat in (('Right', bone_r), ('Left', mirror(bone_r))):
        sb = side + 'Antenna'
        abones.append(Part(sb, bmat, (0.2, 0.2, 0.2), transparency=1.0))
        amotors.append((sb, 'AntennaMount', sb))
        avis += parts if side == 'Right' else [mirror_part(p, sb) for p in parts]
    top.append(('MothAntennae', amount, abones, avis, amotors, 'Head'))
    return top


_prev = bm.part_xml


def part_xml(p, rid, inner=''):
    x = _prev(p, rid, inner)
    shp = getattr(p, 'shape', 'Block')
    if shp != 'Block' and not isinstance(p, Wedge):
        x = x.replace('<token name="shape">1</token>', f'<token name="shape">{SHAPE[shp]}</token>')
    return x


bm.part_xml = part_xml

if __name__ == '__main__':
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
                         'wedge': isinstance(p, Wedge), 'shape': getattr(p, 'shape', 'Block')})
        print(name, 'parts:', len(visible))
    json.dump(dump, open('/home/claude/moth/boxes.json', 'w'))
