"""Retro (2008-2013 catalog style) Moth race meshes: very few polygons, detail painted into small flat textures.

Same output layout / rig script as build_moth_mesh.py (no collar).
"""
import math, pickle, os, sys
import numpy as np
from PIL import Image, ImageDraw
import build_moth_mesh as mm
from build_moth_mesh import (catmull, signed_area, slab_from_polygon, ngon, textured, flat, MIRROR, tube,
                             FORE, HIND, ANT_BASE, antenna_curve, write_luau, GLOW)

OUT = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/moth/retro_out'
os.makedirs(OUT, exist_ok=True)
TEX = 256          # final texture size (old-catalog resolution)
SS = 4             # paint supersampling
WING_T = 0.07

BASE = (22, 66, 72)
INNER = (12, 36, 41)
VEIN = (8, 22, 26)
FUR = (132, 198, 196)
FUR_DARK = (92, 156, 156)
SPOT = (30, 118, 126)


def outline(spec):
    P = catmull(spec.ctrl, 2)
    if signed_area(P) < 0:
        P = P[::-1]
    n = len(P)
    seg = np.linalg.norm(np.roll(P, -1, 0) - P, axis=1)
    s = np.concatenate([[0], np.cumsum(seg)[:-1]]) / seg.sum()
    a, b = spec.fringe
    out = []
    for i in range(n):
        p, q = P[i], P[(i + 1) % n]
        out.append(p)
        if a <= s[i] <= b:   # one chunky fluff lobe per edge
            e = q - p
            nrm = np.array([e[1], -e[0]]) / np.linalg.norm(e)
            out.append((p + q) / 2 + nrm * 0.11)
    return np.array(out)


def paint(spec, P, span, origin):
    S = TEX * SS
    to_px = lambda xy: [((x - origin[0]) / span * S, (1 - (y - origin[1]) / span) * S) for x, y in np.atleast_2d(xy)]
    img = Image.new('RGB', (S, S), FUR)
    d = ImageDraw.Draw(img)
    d.polygon(to_px(P), fill=FUR_DARK)                       # fur edge, darker underside of the fluff
    c = P.mean(0)
    inner1 = c + (P - c) * 0.9
    d.polygon(to_px(inner1), fill=FUR)                        # pale fluffy border
    inner2 = c + (P - c) * 0.8 + np.array([-0.05, 0])
    d.polygon(to_px(inner2), fill=BASE)                       # wing
    inner3 = c + (P - c) * 0.55 + (np.array([0.0, 0.0]) - c) * 0.15
    d.polygon(to_px(inner3), fill=INNER)                      # darker middle
    # a few veins from the root
    for f in (0.15, 0.4, 0.62, 0.85):
        e = inner2[int(f * len(inner2)) % len(inner2)]
        d.line(to_px([[0.05, 0.0], e]), fill=VEIN, width=3 * SS)
    # root fluff
    r = 0.42 / span * S
    x0, y0 = to_px([0, 0])[0]
    d.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=FUR)
    # eyespot backing + a few dim spots
    for (ex, ey, er) in spec.eyes:
        (cx, cy), = to_px([ex, ey])
        for k, col in ((1.45, VEIN), (1.15, INNER)):
            rr = er * k / span * S
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col)
    for (sx, sy, sr) in spec.specks:
        (cx, cy), = to_px([sx, sy])
        rr = sr * 1.4 / span * S
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=SPOT)
    return img.resize((TEX, TEX), Image.LANCZOS)


def glow_mesh(spec, zc):
    parts = []
    for (ex, ey, er) in spec.eyes:
        m, _ = slab_from_polygon(ngon((ex, ey), er, 8, math.pi / 8), zc, WING_T + 0.04, max_area=None,
                                 holes=[ngon((ex, ey), er * 0.6, 8, math.pi / 8)[::-1]])
        parts.append(m)
        m, _ = slab_from_polygon(ngon((ex, ey), er * 0.22, 6), zc, WING_T + 0.05, max_area=None)
        parts.append(m)
    import trimesh
    return trimesh.util.concatenate(parts)


def antenna_tex():
    S = 64 * SS
    img = Image.new('RGB', (S, S), (16, 48, 54))
    d = ImageDraw.Draw(img)
    # painted feather barbs: diagonal strokes from the middle out, pale at the tips
    for i in range(-2, 14):
        y = i * S / 12
        for sgn in (1, -1):
            x0 = S / 2
            x1 = S / 2 + sgn * S / 2
            d.line([(x0, y + S / 10), (x1, y - S / 14)], fill=(40, 118, 124), width=3 * SS)
            d.line([(S / 2 + sgn * S * 0.38, y - S / 30), (x1, y - S / 14)], fill=FUR, width=3 * SS)
    d.rectangle([S / 2 - 3 * SS, 0, S / 2 + 3 * SS, S], fill=(10, 26, 31))   # shaft
    return img.resize((64, 64), Image.LANCZOS)


def build_antenna():
    pts = antenna_curve(n=6)
    n = len(pts)
    V1, F1, U1 = tube(pts, np.linspace(0.07, 0.04, n), 4, np.full(n, 0.5))
    U1 = np.column_stack([np.full(len(V1), 0.5), np.full(len(V1), 0.5)])   # shaft colour (texture middle)
    # one flat leaf-shaped feather along the stalk; the barbs are painted on
    cp = antenna_curve(n=6)
    left, right = [], []
    for i, p in enumerate(cp):
        t = i / (len(cp) - 1)
        tan = cp[min(i + 1, len(cp) - 1)] - cp[max(i - 1, 0)]
        tan /= np.linalg.norm(tan)
        side = np.cross(tan, [0, 0, 1.0]); side /= np.linalg.norm(side)
        w = 0.04 + 0.28 * math.sin(math.pi * min(max((t - 0.1) / 0.8, 0), 1))
        left.append(p + side * w); right.append(p - side * w)
    # leaf outline in the antenna's own 2D plane (x/y; the curve's small z tilt is re-applied after)
    ring = np.vstack([left, right[::-1]])
    z_of = lambda xy: np.interp(xy[:, 1], cp[:, 1], cp[:, 2])
    leaf, V2 = slab_from_polygon(ring[:, :2], z_of, 0.03, max_area=None)
    # uv: u across the leaf (0..1 left->right of the stalk), v along it
    Uu = []
    for x, y in V2:
        k = np.argmin(np.linalg.norm(cp[:, :2] - [x, y], axis=1))
        tan = cp[min(k + 1, len(cp) - 1)] - cp[max(k - 1, 0)]
        side = np.cross(tan / np.linalg.norm(tan), [0, 0, 1.0])[:2]
        off = np.dot([x, y] - cp[k, :2], side / np.linalg.norm(side))
        Uu.append((0.5 + off / 0.64, y / cp[-1, 1]))
    Uu = np.array(Uu)
    U2 = np.vstack([Uu, Uu])
    V = np.vstack([V1, leaf.vertices])
    F = np.vstack([F1, leaf.faces + len(V1)])
    U = np.vstack([U1, U2])
    import trimesh
    tip = trimesh.creation.icosphere(subdivisions=0, radius=0.13)
    tip.apply_translation(pts[-1])
    return V + ANT_BASE, F, U, tip.apply_translation(ANT_BASE)


def main():
    import trimesh
    pieces = {}
    for spec in (FORE, HIND):
        P = outline(spec)
        xmin, ymin = P.min(0) - 0.03
        span = max(P.max(0) - P.min(0)) + 0.06
        zc = lambda xy, spec=spec: mm.camber_z(spec, xy)
        mesh, V2 = slab_from_polygon(P, zc, WING_T, max_area=None)
        uv = np.vstack([(V2 - [xmin, ymin]) / span] * 2)
        tex = paint(spec, P, span, (xmin, ymin))
        tex.save(f'{OUT}/tex_{spec.name.lower()}.png')
        glow = glow_mesh(spec, zc)
        Vw = mesh.vertices @ spec.R.T + spec.hinge
        Gw = glow.vertices @ spec.R.T + spec.hinge
        for side in ('Right', 'Left'):
            flip = side == 'Left'
            nm = side + spec.name
            pieces[nm] = dict(mesh=textured(nm, Vw @ MIRROR if flip else Vw, mesh.faces, uv, tex, flip), tex=tex, uv=uv,
                              attach='Torso', joint='Motor6D', hinge=spec.hinge @ MIRROR if flip else spec.hinge,
                              R=MIRROR @ spec.R @ MIRROR if flip else spec.R)
            gm = trimesh.Trimesh(Gw @ MIRROR if flip else Gw, glow.faces[:, ::-1] if flip else glow.faces, process=False)
            pieces[nm + 'Glow'] = dict(mesh=flat(nm + 'Glow', gm, GLOW), attach=nm, joint='Weld', glow=True)
    atex = antenna_tex()
    atex.save(f'{OUT}/tex_antenna.png')
    V, F, U, tip = build_antenna()
    for side in ('Right', 'Left'):
        flip = side == 'Left'
        nm = side + 'Antenna'
        pieces[nm] = dict(mesh=textured(nm, V @ MIRROR if flip else V, F, U, atex, flip), tex=atex, uv=U,
                          attach='Head', joint='Motor6D', hinge=ANT_BASE @ MIRROR if flip else ANT_BASE, R=np.eye(3))
        gv = tip.vertices @ MIRROR if flip else tip.vertices
        gm = trimesh.Trimesh(gv, tip.faces[:, ::-1] if flip else tip.faces, process=False)
        pieces[nm + 'Glow'] = dict(mesh=flat(nm + 'Glow', gm, GLOW), attach=nm, joint='Weld', glow=True)

    scene = trimesh.Scene()
    for nm, p in pieces.items():
        scene.add_geometry(p['mesh'], node_name=nm, geom_name=nm)
        lo, hi = p['mesh'].bounds
        p['center'], p['size'] = (lo + hi) / 2, hi - lo
    scene.export(f'{OUT}/MothRace.glb')
    mm.OUT = OUT
    write_luau(pieces)
    pickle.dump({nm: dict(V=p['mesh'].vertices, F=p['mesh'].faces, uv=p.get('uv'),
                          tex=np.array(p['tex']) if 'tex' in p else None, glow=p.get('glow', False))
                 for nm, p in pieces.items()}, open(f'{OUT}/pieces.pkl', 'wb'))
    print('triangles total', sum(len(p['mesh'].faces) for p in pieces.values()))
    for nm, p in pieces.items():
        print(f"  {nm:18s} {len(p['mesh'].faces):4d}")


if __name__ == '__main__':
    main()
