"""Accessory-quality Moth race meshes: textured wings, feathery antennae, fluffy collar.

Outputs (in OUT):
  MothRace.glb        one scene, one node per piece (import with Studio's 3D Importer)
  MothParts.luau      rigs the imported model onto an R6 character (auto-detects importer axes/scale)
  tex_*.png           the painted textures (also embedded in the .glb)
  pieces.pkl          geometry for the preview renderer

Coordinates: Roblox studs, Torso-local (Torso centre = origin, Y up, character faces -Z, back is +Z).
"""
import math, pickle, os, sys
import numpy as np
import trimesh, triangle
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

OUT = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/moth/mesh_out'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(5)

GLOW = (41, 223, 235)
HEAD_Y = 1.5  # R6 head centre above torso centre


def roty(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rotx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def catmull(ctrl, n):
    P = np.array(ctrl, float)
    m = len(P)
    out = []
    for i in range(m):
        p0, p1, p2, p3 = P[(i - 1) % m], P[i], P[(i + 1) % m], P[(i + 2) % m]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return np.array(out)


def signed_area(P):
    x, y = P[:, 0], P[:, 1]
    return 0.5 * np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y)


# ---------------------------------------------------------------- wings
class WingSpec:
    def __init__(self, name, ctrl, fringe, hinge, sweep, raise_, camber, eyes, specks):
        self.name, self.ctrl, self.fringe = name, ctrl, fringe
        self.hinge, self.sweep, self.raise_ = np.array(hinge, float), sweep, raise_
        self.camber, self.eyes, self.specks = camber, eyes, specks
        self.R = roty(-math.radians(sweep)) @ rotz(math.radians(raise_))


FORE = WingSpec('Forewing',
                [(0.0, 0.15), (0.8, 0.72), (1.9, 1.42), (3.0, 2.02), (3.78, 2.28), (4.1, 1.9), (4.15, 1.15),
                 (3.82, 0.42), (3.2, -0.18), (2.2, -0.52), (1.1, -0.5), (0.3, -0.25)],
                fringe=(0.36, 0.97),   # fraction of the outline (from ctrl 0) that gets the furry scallops
                hinge=[0.25, 0.45, 0.62], sweep=22, raise_=4, camber=0.16,
                eyes=[(3.05, 1.08, 0.36)], specks=[(1.75, 0.2, 0.07), (2.35, 0.55, 0.05), (2.6, -0.1, 0.06), (3.55, 1.7, 0.05)])
HIND = WingSpec('Hindwing',
                [(0.0, 0.1), (1.0, 0.16), (2.1, -0.08), (2.88, -0.7), (3.08, -1.45), (2.72, -2.12), (1.92, -2.48),
                 (1.1, -2.12), (0.5, -1.4), (0.15, -0.6)],
                fringe=(0.2, 0.9), hinge=[0.25, -0.2, 0.66], sweep=30, raise_=-6, camber=0.12,
                eyes=[(1.95, -1.32, 0.4)], specks=[(1.05, -0.6, 0.06), (2.55, -0.55, 0.05), (1.4, -1.9, 0.05)])

WING_T = 0.06


def wing_outline(spec):
    P = catmull(spec.ctrl, 40)
    if signed_area(P) < 0:
        P = P[::-1]
    n = len(P)
    seg = np.linalg.norm(np.roll(P, -1, 0) - P, axis=1)
    s = np.concatenate([[0], np.cumsum(seg)[:-1]]) / seg.sum()
    tang = np.roll(P, -1, 0) - np.roll(P, 1, 0)
    nrm = np.stack([tang[:, 1], -tang[:, 0]], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)  # outward for CCW
    a, b = spec.fringe
    w = np.clip(np.minimum((s - a) / 0.06, (b - s) / 0.06), 0, 1)
    arc = np.concatenate([[0], np.cumsum(seg)[:-1]])
    period = 0.2
    phase = arc / period
    bump = np.abs(np.sin(np.pi * phase)) ** 0.55          # rounded clumps with sharp valleys
    jitter = 0.6 + 0.4 * np.sin(phase * 1.7 + 1.3) * np.sin(phase * 0.63)
    disp = w * 0.11 * bump * jitter + 0.012 * (1 - w) * np.sin(arc * 40)
    return P + nrm * disp[:, None]


def resample(P, step=0.03):
    Q = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(Q, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    t = np.arange(0, cum[-1], step)
    return np.stack([np.interp(t, cum, Q[:, 0]), np.interp(t, cum, Q[:, 1])], 1)


def camber_z(spec, xy):
    L = max(p[0] for p in spec.ctrl)
    u = np.clip(xy[:, 0] / L, 0, 1)
    return spec.camber * np.sin(np.pi * u * 0.9) + 0.03 * xy[:, 1]


def slab_from_polygon(P2, z_fn, thick, max_area='0.004', holes=None, segs_extra=None):
    """Triangulate a 2D polygon (with interior points) and build a closed slab: front, back, side walls."""
    n = len(P2)
    verts = [P2]
    segs = [np.stack([np.arange(n), (np.arange(n) + 1) % n], 1)]
    hole_pts = []
    off = n
    for h in holes or []:
        verts.append(h)
        m = len(h)
        segs.append(np.stack([np.arange(m), (np.arange(m) + 1) % m], 1) + off)
        hole_pts.append(h.mean(0))
        off += m
    A = {'vertices': np.vstack(verts), 'segments': np.vstack(segs)}
    if hole_pts:
        A['holes'] = np.array(hole_pts)
    T = triangle.triangulate(A, 'pq30a' + max_area if max_area else 'p')
    V2, F = T['vertices'], T['triangles']
    z = z_fn(V2)
    front = np.column_stack([V2, z - thick / 2])   # -Z side (toward the body)
    back = np.column_stack([V2, z + thick / 2])
    nv = len(V2)
    V = np.vstack([front, back])
    faces = [F[:, ::-1], F + nv]                  # front faces point -Z, back faces +Z
    # side walls along every boundary segment (outer + holes); triangle keeps the input vertices first
    for (i, j) in T['segments']:
        faces.append(np.array([[i, j, j + nv], [i, j + nv, i + nv]]))
    faces = np.vstack(faces)
    mesh = trimesh.Trimesh(V, faces, process=False)
    mesh.fix_normals()
    return mesh, V2


def paint_wing(spec, P, span, origin, eye_list, size=1024, ss=2):
    S = size * ss
    to_px = lambda xy: np.stack([(xy[:, 0] - origin[0]) / span * S, (1 - (xy[:, 1] - origin[1]) / span) * S], 1)
    Pp = to_px(P)
    mask_img = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask_img).polygon([tuple(p) for p in Pp], fill=255)
    mask = np.array(mask_img) > 0
    dist = ndimage.distance_transform_edt(mask) / S * span   # studs to the edge
    yy, xx = np.mgrid[0:S, 0:S]
    wx = xx / S * span + origin[0]
    wy = (1 - yy / S) * span + origin[1]
    hinge_d = np.hypot(wx, wy)

    # base: teal near the body -> deep sculk black toward the tips, with soft mottling
    Lx = max(p[0] for p in spec.ctrl)
    t = np.clip(hinge_d / Lx, 0, 1)[..., None]
    near, far = np.array([28, 88, 94.]), np.array([9, 24, 29.])
    img = near * (1 - t) ** 1.4 + far * (1 - (1 - t) ** 1.4)
    noise = ndimage.gaussian_filter(rng.standard_normal((S // 8, S // 8)), 2.5)
    noise = np.kron(noise, np.ones((8, 8)))[:S, :S]
    img *= (1 + 0.35 * noise[..., None] / (np.abs(noise).max() + 1e-6))
    # subtle lighter band across the wing (moth "postmedian line")
    band = np.exp(-((hinge_d - Lx * 0.55) / 0.1) ** 2)[..., None]
    img = img * (1 - 0.35 * band) + np.array([40, 120, 124.]) * 0.35 * band

    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    px = S / span
    # veins fanning from the hinge
    ends = P[:: max(1, len(P) // 9)]
    for e in ends:
        mid = e * 0.55 + rng.normal(0, 0.05, 2)
        pts = to_px(np.array([[0.05, 0.0], mid, e]))
        d.line([tuple(p) for p in pts], fill=(6, 15, 18), width=int(0.035 * px), joint='curve')
        d.line([tuple(p + np.array([2 * ss, -2 * ss])) for p in pts], fill=(30, 80, 86), width=max(1, int(0.008 * px)))
    # dim sculk specks (the bright ones are the glow mesh)
    for _ in range(90):
        x, y = rng.uniform(0.3, Lx), rng.uniform(P[:, 1].min(), P[:, 1].max())
        r = rng.uniform(0.012, 0.03) * px
        c = to_px(np.array([[x, y]]))[0]
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(24, 110, 118))
    # dark halo under each eyespot so the glow ring pops
    for (ex, ey, er) in eye_list:
        c = to_px(np.array([[ex, ey]]))[0]
        for k, col in ((1.55, (6, 14, 17)), (1.2, (14, 44, 50))):
            r = er * k * px
            d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=col)
    arr = np.array(im).astype(float)

    # fur trim: pale near the edge, fading in, with outward strokes
    fur = np.clip(1 - dist / 0.24, 0, 1)[..., None] ** 1.3
    arr = arr * (1 - fur) + np.array([118, 176, 174.]) * fur
    root = np.clip(1 - hinge_d / 0.8, 0, 1)[..., None] ** 1.5       # fuzzy wing root
    arr = arr * (1 - root) + np.array([100, 160, 160.]) * root
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    gy, gx = np.gradient(ndimage.gaussian_filter(dist, 6))
    edge_px = np.argwhere(mask & (dist < 0.24))
    for (r_, c_) in edge_px[rng.choice(len(edge_px), 6000)]:
        g = np.array([gx[r_, c_], gy[r_, c_]])
        if np.linalg.norm(g) < 1e-9:
            continue
        g = -g / np.linalg.norm(g)                   # outward
        g = g + rng.normal(0, 0.25, 2)
        ln = rng.uniform(0.05, 0.12) * px
        shade = rng.uniform(0.75, 1.15)
        col = tuple(int(min(255, v * shade)) for v in (140, 196, 194))
        d.line([(c_, r_), (c_ + g[0] * ln, r_ + g[1] * ln)], fill=col, width=max(1, int(0.012 * px)))
    root_px = np.argwhere(mask & (hinge_d < 0.7))
    for (r_, c_) in root_px[rng.choice(len(root_px), 1500)]:
        g = np.array([c_ - to_px(np.zeros((1, 2)))[0][0], r_ - to_px(np.zeros((1, 2)))[0][1]])
        g = g / (np.linalg.norm(g) + 1e-6) + rng.normal(0, 0.35, 2)
        ln = rng.uniform(0.04, 0.1) * px
        d.line([(c_, r_), (c_ + g[0] * ln, r_ + g[1] * ln)], fill=(126, 184, 182), width=max(1, int(0.01 * px)))
    arr = np.array(im)
    arr[~mask] = (118, 176, 174)   # bleed colour for the side walls / mip-maps
    return Image.fromarray(arr).resize((size, size), Image.LANCZOS)


def ngon(c, r, n, rot=0.0):
    a = rot + 2 * np.pi * np.arange(n) / n
    return np.stack([c[0] + r * np.cos(a), c[1] + r * np.sin(a)], 1)


def build_wing(spec):
    P = resample(wing_outline(spec), 0.045)
    xmin, ymin = P.min(0) - 0.02
    span = max(P.max(0) - P.min(0)) + 0.04
    mesh, V2 = slab_from_polygon(P, lambda xy: camber_z(spec, xy), WING_T, max_area='0.12')
    uv = np.vstack([(V2 - [xmin, ymin]) / span] * 2)
    tex = paint_wing(spec, P, span, (xmin, ymin), spec.eyes)
    # glow: eyespot rings with a dot, plus specks; thicker than the membrane so they show on both sides
    glow_parts = []
    zc = lambda xy: camber_z(spec, xy)
    for (ex, ey, er) in spec.eyes:
        ring_out = ngon((ex, ey), er, 40)
        ring_in = ngon((ex, ey), er * 0.62, 40)[::-1]
        m, _ = slab_from_polygon(ring_out, zc, WING_T + 0.035, max_area=None, holes=[ring_in])
        glow_parts.append(m)
        m, _ = slab_from_polygon(ngon((ex, ey), er * 0.22, 16), zc, WING_T + 0.045, max_area=None)
        glow_parts.append(m)
        # little crescent highlight, sculk-sensor style
        arc = np.array([[ex + er * 1.25 * math.cos(a), ey + er * 1.25 * math.sin(a)] for a in np.linspace(0.3, 1.5, 10)])
        arc2 = np.array([[ex + er * 1.12 * math.cos(a), ey + er * 1.12 * math.sin(a)] for a in np.linspace(1.5, 0.3, 10)])
        m, _ = slab_from_polygon(np.vstack([arc, arc2]), zc, WING_T + 0.03, max_area=None)
        glow_parts.append(m)
    for (sx, sy, sr) in spec.specks:
        m, _ = slab_from_polygon(ngon((sx, sy), sr, 4, rot=rng.uniform(0, 1.5)), zc, WING_T + 0.03, max_area=None)
        glow_parts.append(m)
    glow = trimesh.util.concatenate(glow_parts)
    return mesh, uv, tex, glow


# ---------------------------------------------------------------- antenna + collar texture
def gradient_tex():
    W, H = 256, 32
    x = np.linspace(0, 1, W)[:, None]
    stops = [(0, (10, 26, 31)), (0.45, (24, 90, 98)), (0.75, (60, 140, 144)), (1.0, (160, 212, 208))]
    arr = np.zeros((W, 3))
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        sel = (x[:, 0] >= a) & (x[:, 0] <= b)
        f = ((x[sel, 0] - a) / (b - a))[:, None]
        arr[sel] = np.array(ca) * (1 - f) + np.array(cb) * f
    img = np.repeat(arr[None], H, 0)
    img *= 1 + 0.08 * rng.standard_normal((H, W, 1))
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def tube(points, radii, sides=6, u_vals=None):
    """Tapered tube along points; returns vertices, faces, uv (u from u_vals)."""
    points = np.asarray(points, float)
    V, U, F = [], [], []
    for i, p in enumerate(points):
        t = points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        a = np.cross(t, [0, 0, 1.0])
        if np.linalg.norm(a) < 1e-6:
            a = np.cross(t, [1.0, 0, 0])
        a /= np.linalg.norm(a)
        b = np.cross(t, a)
        for k in range(sides):
            ang = 2 * np.pi * k / sides
            V.append(p + radii[i] * (np.cos(ang) * a + np.sin(ang) * b))
            U.append((u_vals[i] if u_vals is not None else 0.1, 0.5))
    n = len(points)
    for i in range(n - 1):
        for k in range(sides):
            a0, a1 = i * sides + k, i * sides + (k + 1) % sides
            b0, b1 = a0 + sides, a1 + sides
            F += [[a0, a1, b1], [a0, b1, b0]]
    # caps
    V.append(points[0]); U.append((u_vals[0] if u_vals is not None else 0.1, 0.5))
    V.append(points[-1]); U.append((u_vals[-1] if u_vals is not None else 0.1, 0.5))
    c0, c1 = len(V) - 2, len(V) - 1
    for k in range(sides):
        F.append([c0, (k + 1) % sides, k])
        F.append([c1, (n - 1) * sides + k, (n - 1) * sides + (k + 1) % sides])
    return np.array(V), np.array(F), np.array(U)


def combine(parts):
    V, F, U, off = [], [], [], 0
    for v, f, u in parts:
        V.append(v); F.append(f + off); U.append(u); off += len(v)
    return np.vstack(V), np.vstack(F), np.vstack(U)


ANT_BASE = np.array([0.3, 2.0, -0.2])   # right antenna root on top of the head (torso-local)


def antenna_curve(n=18, L=2.2):
    pts = [np.zeros(3)]
    for i in range(1, n + 1):
        t = i / n
        phi = math.radians(10 + 45 * t ** 1.5 + 30 * max(0, (t - 0.85) / 0.15))
        d = np.array([math.sin(phi), math.cos(phi), 0.14]); d /= np.linalg.norm(d)
        pts.append(pts[-1] + d * L / n)
    return np.array(pts)


def build_antenna():
    pts = antenna_curve()
    n = len(pts)
    parts = [tube(pts, np.linspace(0.075, 0.035, n), 6, np.linspace(0.02, 0.25, n))]
    # bipectinate comb: flattened curved barbs on both sides, longest in the middle
    for i in range(2, n - 2):
        t = i / (n - 1)
        a, b = pts[i - 1], pts[i + 1]
        tan = (b - a) / np.linalg.norm(b - a)
        side = np.cross(tan, [0, 0, 1.0]); side /= np.linalg.norm(side)
        length = 0.14 + 0.42 * math.sin(math.pi * min(t / 0.88, 1)) ** 0.8
        for sgn in (1, -1):
            bp = [pts[i]]
            for k in range(1, 5):
                f = k / 4
                bp.append(pts[i] + side * sgn * length * f + tan * (0.2 * length * f ** 1.6) + np.array([0, 0, 0.03 * f]))
            r = np.linspace(0.028, 0.008, 5)
            v, fcs, u = tube(bp, r, 4, np.linspace(0.3, 0.97, 5))
            v = v - pts[i]
            # flatten the barb into a blade (squash along the view axis z)
            v[:, 2] *= 0.5
            v = v + pts[i]
            parts.append((v, fcs, u))
    V, F, U = combine(parts)
    glowm = trimesh.creation.icosphere(subdivisions=1, radius=0.12)
    glowm.vertices[:, 1] *= 1.35
    glowm.apply_translation(pts[-1] + np.array([0.02, 0.05, 0]))
    return V + ANT_BASE, F, U, glowm.apply_translation(ANT_BASE)


def build_collar():
    """A mane of fur clumps around the neck and between the wing roots."""
    parts = []
    spots = []
    for k in range(16):  # ring around the neck
        a = 2 * np.pi * k / 16
        spots.append((np.array([0.72 * math.cos(a), 0.92, 0.46 * math.sin(a)]), np.array([math.cos(a), 0.35, math.sin(a) * 1.3]), 0.55))
    for k in range(7):   # back clump over the wing hinges
        spots.append((np.array([rng.uniform(-0.35, 0.35), rng.uniform(-0.3, 0.6), 0.55]), np.array([rng.uniform(-0.5, 0.5), rng.uniform(-0.8, 0.3), 1.0]), 0.34))
    for base, direc, L in spots:
        direc = direc / np.linalg.norm(direc)
        for j in range(3):   # 3 locks per clump
            d = direc + rng.normal(0, 0.25, 3)
            d /= np.linalg.norm(d)
            droop = np.array([0, -0.6, 0])
            ln = L * rng.uniform(0.75, 1.15)
            pts = [base + rng.normal(0, 0.05, 3)]
            for s in range(1, 5):
                f = s / 4
                pts.append(pts[0] + d * ln * f + droop * ln * f * f)
            parts.append(tube(pts, np.linspace(0.15, 0.012, 5), 5, np.linspace(0.35, 1.0, 5)))
    return combine(parts)


# ---------------------------------------------------------------- assemble + export
def textured(name, V, F, U, img, flip=False):
    if flip:
        F = F[:, ::-1]
    mat = trimesh.visual.material.PBRMaterial(name=name + 'Mat', baseColorTexture=img, metallicFactor=0.0, roughnessFactor=1.0)
    m = trimesh.Trimesh(V, F, visual=trimesh.visual.TextureVisuals(uv=U, material=mat), process=False)
    return m


def flat(name, mesh, color):
    m = mesh.copy()
    m.visual = trimesh.visual.ColorVisuals(m, face_colors=np.tile([*color, 255], (len(m.faces), 1)))
    return m


MIRROR = np.diag([-1.0, 1.0, 1.0])


def main():
    pieces = {}   # name -> dict(mesh, joint info)
    grad = gradient_tex()
    grad.save(f'{OUT}/tex_fur.png')
    for spec in (FORE, HIND):
        mesh, uv, tex, glow = build_wing(spec)
        tex.save(f'{OUT}/tex_{spec.name.lower()}.png')
        Vw = mesh.vertices @ spec.R.T + spec.hinge
        Gw = glow.vertices @ spec.R.T + spec.hinge
        for side in ('Right', 'Left'):
            flip = side == 'Left'
            V = Vw @ MIRROR if flip else Vw
            G = Gw @ MIRROR if flip else Gw
            hinge = spec.hinge @ MIRROR if flip else spec.hinge
            R = MIRROR @ spec.R @ MIRROR if flip else spec.R
            nm = side + spec.name
            pieces[nm] = dict(mesh=textured(nm, V, mesh.faces, uv, tex, flip), tex=tex, uv=uv,
                              attach='Torso', joint='Motor6D', hinge=hinge, R=R)
            gm = trimesh.Trimesh(G, glow.faces[:, ::-1] if flip else glow.faces, process=False)
            pieces[nm + 'Glow'] = dict(mesh=flat(nm + 'Glow', gm, GLOW), attach=nm, joint='Weld', glow=True)
    V, F, U, glowm = build_antenna()
    for side in ('Right', 'Left'):
        flip = side == 'Left'
        nm = side + 'Antenna'
        VV = V @ MIRROR if flip else V
        base = ANT_BASE @ MIRROR if flip else ANT_BASE
        pieces[nm] = dict(mesh=textured(nm, VV, F, U, grad, flip), tex=grad, uv=U, attach='Head', joint='Motor6D',
                          hinge=base, R=np.eye(3))
        gv = glowm.vertices @ MIRROR if flip else glowm.vertices
        gm = trimesh.Trimesh(gv, glowm.faces[:, ::-1] if flip else glowm.faces, process=False)
        pieces[nm + 'Glow'] = dict(mesh=flat(nm + 'Glow', gm, GLOW), attach=nm, joint='Weld', glow=True)
    V, F, U = build_collar()
    pieces['Collar'] = dict(mesh=textured('Collar', V, F, U, grad), tex=grad, uv=U, attach='Torso', joint='Motor6D',
                            hinge=np.array([0, 0.9, 0.0]), R=np.eye(3))

    scene = trimesh.Scene()
    for nm, p in pieces.items():
        p['mesh'].metadata['name'] = nm
        scene.add_geometry(p['mesh'], node_name=nm, geom_name=nm)
    scene.export(f'{OUT}/MothRace.glb')

    # data for the Luau rig script: bbox centres (the importer puts each MeshPart at its bbox centre) + sizes
    rows = []
    for nm, p in pieces.items():
        lo, hi = p['mesh'].bounds
        p['center'], p['size'] = (lo + hi) / 2, hi - lo
        rows.append(nm)
    write_luau(pieces)
    pickle.dump({nm: dict(V=p['mesh'].vertices, F=p['mesh'].faces, uv=p.get('uv'),
                          tex=np.array(p['tex']) if 'tex' in p else None, glow=p.get('glow', False))
                 for nm, p in pieces.items()}, open(f'{OUT}/pieces.pkl', 'wb'))
    tris = sum(len(p['mesh'].faces) for p in pieces.values())
    print('pieces', len(pieces), 'triangles', tris)
    for nm, p in pieces.items():
        print(f"  {nm:18s} tris {len(p['mesh'].faces):5d} size {np.round(p['size'], 2)}")


def v3(v):
    return f'Vector3.new({v[0]:.4f}, {v[1]:.4f}, {v[2]:.4f})'


def cfr(pos, R):
    vals = ', '.join(f'{x:.5f}' for x in [*pos, *R.flatten()])
    return f'CFrame.new({vals})'


def write_luau(pieces):
    lines = []
    for nm, p in pieces.items():
        entry = [f'Name = "{nm}"', f'Center = {v3(p["center"])}', f'Size = {v3(p["size"])}',
                 f'Attach = "{p["attach"]}"', f'Joint = "{p["joint"]}"']
        if p['joint'] == 'Motor6D':
            h = p['hinge']
            entry.append(f'Hinge = {cfr(h, p["R"])}')
        if p.get('glow'):
            entry.append('Glow = true')
        lines.append('\t{ ' + ', '.join(entry) + ' },')
    src = open('/home/claude/moth/MothParts_mesh_template.luau').read().replace('--@@PIECES@@', '\n'.join(lines))
    open(f'{OUT}/MothParts.luau', 'w').write(src)


if __name__ == '__main__':
    main()
