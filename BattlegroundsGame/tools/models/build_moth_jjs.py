"""JJS-style Moth race meshes: chunky flat shapes, soft bevels, flat colours, very few polygons.

Colours come from a tiny palette texture (one flat colour per face), glow pieces are separate meshes set to Neon.
Same rig script / output layout as build_moth_mesh.py.
"""
import math, pickle, os, sys
import numpy as np
import trimesh, triangle
from PIL import Image
from shapely.geometry import Polygon
import build_moth_mesh as mm
from build_moth_mesh import ngon, textured, flat, MIRROR, FORE, HIND, ANT_BASE, write_luau, GLOW, tube

OUT = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/moth/jjs_out'
LEVEL = sys.argv[2] if len(sys.argv) > 2 else 'full'   # 'full' | '500' | '350'
BEVEL_BODY = LEVEL == 'full'
BEVEL_REST = LEVEL == 'full'
RING = 8 if LEVEL == 'full' else 6
os.makedirs(OUT, exist_ok=True)

PALETTE = {  # flat colours, JJS-like: few, clean
    'body': (24, 66, 72),
    'trim': (136, 200, 196),
    'pupil': (10, 24, 28),
    'rod': (16, 38, 44),
    'feather': (38, 110, 116),
}
KEYS = list(PALETTE)


def palette_img():
    img = Image.new('RGB', (64, 64), (0, 0, 0))
    for i, k in enumerate(KEYS):
        r, c = divmod(i, 4)
        img.paste(PALETTE[k], (c * 16, r * 16, c * 16 + 16, r * 16 + 16))
    return img


def uv_of(key):
    r, c = divmod(KEYS.index(key), 4)
    return np.array([(c + 0.5) / 4, 1 - (r + 0.5) / 4])   # GL-style v (trimesh flips on export)


def ccw(P):
    P = np.asarray(P, float)
    x, y = P[:, 0], P[:, 1]
    return P if np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y) > 0 else P[::-1]


def inset(P, d):
    """Mitred inward offset of a CCW polygon (same vertex count)."""
    n = len(P)
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        e1, e2 = (b - a) / np.linalg.norm(b - a), (c - b) / np.linalg.norm(c - b)
        n1, n2 = np.array([-e1[1], e1[0]]), np.array([-e2[1], e2[0]])   # inward (left) normals
        m = n1 + n2
        k = 1 + n1 @ n2
        off = m / max(k, 0.35)
        out.append(b + off * d)
    return np.array(out)


def cap(P):
    T = triangle.triangulate({'vertices': P, 'segments': np.stack([np.arange(len(P)), (np.arange(len(P)) + 1) % len(P)], 1)}, 'p')
    return T['vertices'], T['triangles']


def beveled_slab(P, thick, bevel, key, z0=0.0):
    """Flat-shaded slab with a soft chamfer on both faces. Returns V, F, UV (all faces one palette colour)."""
    P = ccw(P)
    n = len(P)
    I = inset(P, bevel)
    h = thick / 2
    rings = [(I, z0 + h), (P, z0 + h - bevel), (P, z0 - h + bevel), (I, z0 - h)] if bevel > 0 else [(P, z0 + h), (P, z0 - h)]
    if bevel <= 0:
        I = P
    V, F = [], []
    for R, z in rings:
        V.append(np.column_stack([R, np.full(n, z)]))
    V = np.vstack(V)
    for r in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            a, b = r * n + i, r * n + j
            c, d = (r + 1) * n + j, (r + 1) * n + i
            F += [[a, d, c], [a, c, b]]
    for R, z, flip in ((I, z0 + h, False), (I, z0 - h, True)):
        V2, T = cap(R)
        base = len(V)
        V = np.vstack([V, np.column_stack([V2, np.full(len(V2), z)])])
        F += ((T + base)[:, ::-1] if flip else (T + base)).tolist()
    V, F = np.array(V), np.array(F)
    m = trimesh.Trimesh(V, F, process=False)
    m.fix_normals()
    return m.vertices, m.faces, np.tile(uv_of(key), (len(m.vertices), 1))


def merge(parts):
    V, F, U, o = [], [], [], 0
    for v, f, u in parts:
        V.append(v); F.append(f + o); U.append(u); o += len(v)
    return np.vstack(V), np.vstack(F), np.vstack(U)


# ---------------- shapes (right side, wing space: x out along the wing, y up) ----------------
FORE_BODY = [(0, 0), (1.2, 0.95), (3.5, 2.0), (3.95, 1.55), (3.6, 0.45), (2.2, -0.35), (0.6, -0.35)]
FORE_TRIM = [(-0.1, 0.05), (1.15, 1.12), (3.55, 2.22), (4.22, 1.7), (4.0, 1.25), (4.12, 0.9), (3.78, 0.55), (3.72, 0.18),
             (3.2, 0.08), (2.85, -0.32), (2.3, -0.3), (1.9, -0.64), (1.3, -0.47), (0.8, -0.64), (0.35, -0.47)]
FORE_EYE = (2.9, 1.05, 0.4)
HIND_BODY = [(0, 0), (1.6, 0.05), (2.6, -0.5), (2.7, -1.5), (2.0, -2.2), (1.0, -1.9), (0.3, -0.8)]
HIND_TRIM = [(-0.05, 0.12), (1.65, 0.22), (2.8, -0.45), (2.95, -0.95), (2.8, -1.2), (2.97, -1.6), (2.55, -1.92), (2.45, -2.32),
             (1.95, -2.42), (1.6, -2.22), (1.15, -2.37), (0.85, -2.02), (0.45, -1.92), (0.35, -1.42), (0.05, -1.0), (0.1, -0.6)]
HIND_EYE = (1.7, -1.25, 0.42)
FORE_TRIM_LO = [(-0.1, 0.05), (1.15, 1.12), (3.55, 2.22), (4.22, 1.7), (4.05, 1.05), (3.72, 0.2), (2.9, -0.3),
                (1.9, -0.64), (0.8, -0.64), (0.3, -0.45)]
HIND_TRIM_LO = [(-0.05, 0.12), (1.65, 0.22), (2.8, -0.45), (2.97, -1.3), (2.55, -2.32), (1.6, -2.4), (0.8, -2.12),
                (0.35, -1.42), (0.05, -1.0), (0.1, -0.6)]
if LEVEL != 'full':
    FORE_TRIM, HIND_TRIM = FORE_TRIM_LO, HIND_TRIM_LO


def build_wing(body, trim, eye):
    assert Polygon(trim).buffer(0.001).contains(Polygon(body)), 'trim must enclose body'
    ex, ey, er = eye
    parts = [beveled_slab(np.array(trim, float), 0.14, 0.03 if BEVEL_REST else 0, 'trim'),
             beveled_slab(np.array(body, float), 0.2, 0.04 if BEVEL_BODY else 0, 'body'),
             ] + ([beveled_slab(ngon((ex, ey), er * 0.5, RING, math.pi / RING), 0.26, 0.03 if BEVEL_REST else 0, 'pupil')]
                  if LEVEL != '350' else [])
    V, F, U = merge(parts)
    # glow ring (Neon): 8-sided ring, thicker than the body so it shows on both faces
    if LEVEL != 'full':   # solid glowing hexagon; the dark pupil (500 only) sits on top of it
        hv, hf, _ = beveled_slab(ngon((ex, ey), er * (0.8 if LEVEL == '350' else 1.0), 6, math.pi / 6), 0.24, 0, 'body')
        glow = trimesh.Trimesh(hv, hf, process=False)
        return V, F, U, glow
    N = RING
    outer, inner = ngon((ex, ey), er, N, math.pi / N), ngon((ex, ey), er * 0.62, N, math.pi / N)
    gv, gf = [], []
    for z in (0.12, -0.12):
        gv += [np.column_stack([outer, np.full(N, z)]), np.column_stack([inner, np.full(N, z)])]
    GV = np.vstack(gv)   # 0-7 outer top, 8-15 inner top, 16-23 outer bottom, 24-31 inner bottom
    for i in range(N):
        j = (i + 1) % N
        a, b, c = N, 2 * N, 3 * N   # inner top, outer bottom, inner bottom offsets
        gf += [[i, j, a + j], [i, a + j, a + i],
               [b + i, c + j, b + j], [b + i, c + i, c + j],
               [i, b + j, j], [i, b + i, b + j],
               [a + i, a + j, c + j], [a + i, c + j, c + i]]
    glow = trimesh.Trimesh(GV, np.array(gf), process=False)
    glow.fix_normals()
    return V, F, U, glow


def build_antenna():
    rod = np.array([[0, 0, 0], [0.22, 0.95, 0.08], [0.78, 1.7, 0.18]])
    rv, rf, _ = tube(rod, [0.065, 0.055, 0.045], 5 if LEVEL == 'full' else 4)
    parts = [(rv, rf, np.tile(uv_of('rod'), (len(rv), 1)))]
    leaf = np.array([(0.05, 0.45), (0.42, 0.8), (0.72, 1.3), (0.98, 1.62), (0.6, 1.52), (0.2, 1.1), (-0.05, 0.75)])
    if LEVEL != 'full':
        leaf = np.array([(0.05, 0.45), (0.72, 1.3), (0.98, 1.62), (0.6, 1.52), (-0.05, 0.75)])
    if LEVEL == '350':
        leaf = None
    lv, lf, lu = (np.zeros((0, 3)), np.zeros((0, 3), int), np.zeros((0, 2))) if LEVEL == '350' else beveled_slab(leaf, 0.07, 0.02 if BEVEL_REST else 0, 'feather', z0=0.1)
    parts.append((lv, lf, lu))
    V, F, U = merge(parts)
    if LEVEL == 'full':
        tip = trimesh.creation.icosphere(subdivisions=0, radius=0.15)
    else:  # octahedron gem
        ov = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], float) * 0.15
        of = np.array([[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]])
        tip = trimesh.Trimesh(ov, of, process=False)
        tip.fix_normals()
    tip.vertices[:, 1] *= 1.2
    tip.apply_translation(rod[-1] + [0.03, 0.06, 0])
    return V + ANT_BASE, F, U, tip.apply_translation(ANT_BASE)


def main():
    pal = palette_img()
    pal.save(f'{OUT}/tex_palette.png')
    pieces = {}
    for spec, body, trim, eye in ((FORE, FORE_BODY, FORE_TRIM, FORE_EYE), (HIND, HIND_BODY, HIND_TRIM, HIND_EYE)):
        V, F, U, glow = build_wing(body, trim, eye)
        Vw = V @ spec.R.T + spec.hinge
        Gw = glow.vertices @ spec.R.T + spec.hinge
        for side in ('Right', 'Left'):
            flip = side == 'Left'
            nm = side + spec.name
            pieces[nm] = dict(mesh=textured(nm, Vw @ MIRROR if flip else Vw, F, U, pal, flip), tex=pal, uv=U,
                              attach='Torso', joint='Motor6D', hinge=spec.hinge @ MIRROR if flip else spec.hinge,
                              R=MIRROR @ spec.R @ MIRROR if flip else spec.R)
            gm = trimesh.Trimesh(Gw @ MIRROR if flip else Gw, glow.faces[:, ::-1] if flip else glow.faces, process=False)
            pieces[nm + 'Glow'] = dict(mesh=flat(nm + 'Glow', gm, GLOW), attach=nm, joint='Weld', glow=True)
    V, F, U, tip = build_antenna()
    for side in ('Right', 'Left'):
        flip = side == 'Left'
        nm = side + 'Antenna'
        pieces[nm] = dict(mesh=textured(nm, V @ MIRROR if flip else V, F, U, pal, flip), tex=pal, uv=U,
                          attach='Head', joint='Motor6D', hinge=ANT_BASE @ MIRROR if flip else ANT_BASE, R=np.eye(3))
        gm = trimesh.Trimesh(tip.vertices @ MIRROR if flip else tip.vertices, tip.faces[:, ::-1] if flip else tip.faces, process=False)
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
