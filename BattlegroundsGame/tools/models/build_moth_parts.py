"""Moth wings + antennae built from Roblox parts (WedgeParts / Parts), same flat design as the chosen
500-triangle version. Writes:
  MothPartsData.luau   data module the game builds the wings from (per character, server side)
  moth_parts.json      the same data for the animation rig builder / preview renderer

Every visual part is placed relative to a BONE (invisible part) that hangs off a Motor6D:
  Torso > RightForewing / LeftForewing / RightHindwing / LeftHindwing
  Head  > RightAntenna / LeftAntenna
Bone frames: wings use the wing's own frame (X out along the wing, Y up it, Z = backward normal),
so Transform Ry(+) swings the wing tip forward, Ry(-) folds it back, Rz(+) raises the tip.
"""
import json, math, sys
import numpy as np
import triangle

sys.argv = [sys.argv[0], '/tmp/jj_unused', '500']
import build_moth_mesh as mm
import build_moth_jjs as jj
from build_moth_lowpoly import tri, Wedge
from build_moth import Part, cf, mirror

BODY = (24, 66, 72)
TRIM = (136, 200, 196)
PUPIL = (10, 24, 28)
ROD = (16, 38, 44)
FEATHER = (38, 110, 116)
GLOW = (41, 223, 235)
HEAD_Y = 1.5


def triangles(P):
    P = np.array(P, float)
    n = len(P)
    T = triangle.triangulate({'vertices': P, 'segments': np.stack([np.arange(n), (np.arange(n) + 1) % n], 1)}, 'p')
    return T['vertices'], T['triangles']


def slab_parts(P2, thick, color, bone_m, bone, z=0.0, name='Plate'):
    V, T = triangles(P2)
    W = lambda p: (bone_m @ np.array([p[0], p[1], z, 1.0]))[:3]
    out = []
    for a, b, c in T:
        out += tri(W(V[a]), W(V[b]), W(V[c]), color, 'SmoothPlastic', thick, bone, name)
    return out


def disc(bone_m, bone, x, y, dia, thick, color, mat, name):
    R = np.column_stack([[0, 0, 1.0], [1.0, 0, 0], [0, 1.0, 0]])  # cylinder axis (X) -> wing normal
    p = Part(name, bone_m @ cf([x, y, 0], R), (thick, dia, dia), color, mat, bone=bone)
    p.shape = 'Cylinder'
    return p


def block(bone_m, bone, a, b, th, color, name):
    a, b = np.array(a, float), np.array(b, float)
    v = b - a
    y = v / np.linalg.norm(v)
    x = np.cross(y, [0, 0, 1.0]); x /= np.linalg.norm(x)
    R = np.column_stack([x, y, np.cross(x, y)])
    return Part(name, bone_m @ cf((a + b) / 2, R), (th, np.linalg.norm(v) + th * 0.5, th), color, 'SmoothPlastic', bone=bone)


def build():
    joints, parts = [], []
    for spec, body, trim, eye in ((mm.FORE, jj.FORE_BODY, jj.FORE_TRIM_LO, jj.FORE_EYE),
                                  (mm.HIND, jj.HIND_BODY, jj.HIND_TRIM_LO, jj.HIND_EYE)):
        bone_r = cf(spec.hinge, spec.R)
        name = 'Right' + spec.name
        ex, ey, er = eye
        right = slab_parts(trim, 0.14, TRIM, bone_r, name, name='Trim')
        right += slab_parts(body, 0.2, BODY, bone_r, name, name='Membrane')
        right.append(disc(bone_r, name, ex, ey, er * 2, 0.24, GLOW, 'Neon', 'Glow'))
        right.append(disc(bone_r, name, ex, ey, er * 1.05, 0.28, PUPIL, 'SmoothPlastic', 'Pupil'))
        for side, bm in (('Right', bone_r), ('Left', mirror(bone_r))):
            bname = side + spec.name
            joints.append(dict(name=bname, part0='Torso', c0=bm))
            for p in right:
                m = p.m if side == 'Right' else mirror(p.m)
                parts.append(dict(bone=bname, name=p.name, cls='WedgePart' if isinstance(p, Wedge) else 'Part',
                                  shape=getattr(p, 'shape', 'Block'), size=list(p.size), world=m,
                                  color=list(p.color), mat=p.mat))
    # antennae (bone at the root, axes = torso axes)
    base = mm.ANT_BASE
    bone_r = cf(base)
    rod = [np.zeros(3), np.array([0.22, 0.95, 0.08]), np.array([0.78, 1.7, 0.18])]
    W = lambda p: base + np.asarray(p, float)
    right = [block(np.eye(4), 'RightAntenna', W(rod[0]), W(rod[1]), 0.13, ROD, 'Stalk'),
             block(np.eye(4), 'RightAntenna', W(rod[1]), W(rod[2]), 0.11, ROD, 'Stalk')]
    leaf = [(0.05, 0.45), (0.72, 1.3), (0.98, 1.62), (0.6, 1.52), (-0.05, 0.75)]
    right += slab_parts(leaf, 0.07, FEATHER, bone_r, 'RightAntenna', z=0.1, name='Feather')
    tip = Part('Glow', cf(W(rod[2]) + np.array([0.03, 0.06, 0])), (0.26, 0.26, 0.26), GLOW, 'Neon', bone='RightAntenna')
    tip.shape = 'Ball'
    right.append(tip)
    for side, bm in (('Right', bone_r), ('Left', mirror(bone_r))):
        bname = side + 'Antenna'
        joints.append(dict(name=bname, part0='Head', c0=cf([0, -HEAD_Y, 0]) @ bm))
        for p in right:
            m = p.m if side == 'Right' else mirror(p.m)
            parts.append(dict(bone=bname, name=p.name, cls='WedgePart' if isinstance(p, Wedge) else 'Part',
                              shape=getattr(p, 'shape', 'Block'), size=list(p.size), world=m,
                              color=list(p.color), mat=p.mat))
    # bone world frames (torso-local): torso joints C0 is already torso-local; head joints add the head offset
    bone_world = {}
    for j in joints:
        bone_world[j['name']] = j['c0'] if j['part0'] == 'Torso' else cf([0, HEAD_Y, 0]) @ j['c0']
    for p in parts:
        p['rel'] = np.linalg.inv(bone_world[p['bone']]) @ p['world']
    return joints, parts, bone_world


def lua_cf(m):
    v = [m[0, 3], m[1, 3], m[2, 3]] + list(m[:3, :3].flatten())
    return 'CFrame.new(' + ', '.join(f'{x:.5f}' for x in v) + ')'


def main():
    joints, parts, bone_world = build()
    lines = ['--!strict', '-- MothPartsData (ModuleScript, ReplicatedStorage > Movement > MothPartsData)',
             '-- GENERATED by tools/models/build_moth_parts.py. Do not edit by hand: change the script and rerun.',
             '-- Joints: bone Motor6Ds (C0 relative to Part0). Parts: visual pieces, CFrame relative to their bone.', '',
             'export type Joint = { Name: string, Part0: string, C0: CFrame }',
             'export type PartSpec = { Bone: string, Name: string, Class: string, Shape: string, Size: Vector3, CFrame: CFrame, Color: Color3, Material: Enum.Material }',
             '', 'local Joints: { Joint } = {']
    for j in joints:
        lines.append(f'\t{{ Name = "{j["name"]}", Part0 = "{j["part0"]}", C0 = {lua_cf(j["c0"])} }},')
    lines += ['}', '', 'local Parts: { PartSpec } = {']
    for p in parts:
        s = p['size']
        c = p['color']
        lines.append(
            f'\t{{ Bone = "{p["bone"]}", Name = "{p["name"]}", Class = "{p["cls"]}", Shape = "{p["shape"]}", '
            f'Size = Vector3.new({s[0]:.4f}, {s[1]:.4f}, {s[2]:.4f}), CFrame = {lua_cf(p["rel"])}, '
            f'Color = Color3.fromRGB({c[0]}, {c[1]}, {c[2]}), Material = Enum.Material.{p["mat"]} }},')
    lines += ['}', '', 'return { Joints = Joints, Parts = Parts }', '']
    open('/home/claude/moth/MothPartsData.luau', 'w').write('\n'.join(lines))
    json.dump({'joints': [dict(name=j['name'], part0=j['part0'], c0=j['c0'].tolist()) for j in joints],
               'parts': [dict(bone=p['bone'], name=p['name'], cls=p['cls'], shape=p['shape'], size=p['size'],
                              rel=p['rel'].tolist(), color=p['color'], mat=p['mat']) for p in parts]},
              open('/home/claude/moth/moth_parts.json', 'w'))
    print('joints', len(joints), 'parts', len(parts))


if __name__ == '__main__':
    main()
