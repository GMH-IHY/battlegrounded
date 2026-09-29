"""Textured z-buffer preview of pieces.pkl on a grey R6 dummy."""
import pickle, math, sys
import numpy as np
from PIL import Image, ImageDraw

pieces = pickle.load(open(sys.argv[1], 'rb'))
out_path = sys.argv[2]
LIGHT = np.array([0.35, 0.8, 0.5]); LIGHT /= np.linalg.norm(LIGHT)

C = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
BOX_T = np.array([(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)])
dummy = []
for pos, size, col in [([0, 0, 0], [2, 2, 1], (40, 127, 71)), ([0, 1.5, 0], [1.2, 1.2, 1.2], (245, 205, 48)),
                       ([1.5, 0, 0], [1, 2, 1], (245, 205, 48)), ([-1.5, 0, 0], [1, 2, 1], (245, 205, 48)),
                       ([0.5, -2, 0], [1, 2, 1], (13, 105, 172)), ([-0.5, -2, 0], [1, 2, 1], (13, 105, 172))]:
    dummy.append(dict(V=C * size + pos, F=BOX_T, col=col))


def draw(yaw, pitch, W=800, H=800, scale=70, centre=np.array([0, 0.6, 0.3])):
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    fwd = np.array([-sy * cp, -sp, -cy * cp]); right = np.array([cy, 0, -sy]); up = np.cross(right, fwd)
    zb = np.full((H, W), np.inf)
    img = np.zeros((H, W, 3)); img[:] = (122, 122, 122)

    def raster(V, F, uv=None, tex=None, col=None, glow=False):
        P = np.stack([W / 2 + (V - centre) @ right * scale, H / 2 - (V - centre) @ up * scale, (V - centre) @ fwd], 1)
        for f in F:
            a, b, c = V[f]
            n = np.cross(b - a, c - a)
            ln = np.linalg.norm(n)
            if ln < 1e-12:
                continue
            n /= ln
            if n @ fwd > 0:           # back-face cull (meshes are closed)
                continue
            shade = 1.0 if glow else 0.45 + 0.55 * max(0.0, n @ LIGHT) + 0.1
            p = P[f]
            x0, x1 = int(max(0, p[:, 0].min())), int(min(W - 1, p[:, 0].max() + 1))
            y0, y1 = int(max(0, p[:, 1].min())), int(min(H - 1, p[:, 1].max() + 1))
            if x0 > x1 or y0 > y1:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (xa, ya, za), (xb, yb, zb_), (xc, yc, zc) = p
            den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
            if abs(den) < 1e-9:
                continue
            l1 = ((yb - yc) * (xs - xc) + (xc - xb) * (ys - yc)) / den
            l2 = ((yc - ya) * (xs - xc) + (xa - xc) * (ys - yc)) / den
            l3 = 1 - l1 - l2
            ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            z = l1 * za + l2 * zb_ + l3 * zc
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            win = ins & (z < sub)
            if not win.any():
                continue
            sub[win] = z[win]
            if tex is not None:
                u = l1 * uv[f[0], 0] + l2 * uv[f[1], 0] + l3 * uv[f[2], 0]
                v = l1 * uv[f[0], 1] + l2 * uv[f[1], 1] + l3 * uv[f[2], 1]
                th, tw = tex.shape[:2]
                tx = np.clip((u * tw).astype(int), 0, tw - 1)
                ty = np.clip(((1 - v) * th).astype(int), 0, th - 1)   # GL-style uv (v up)
                c = tex[ty, tx][win] * shade
            else:
                c = np.array(col, float) * shade
            img[y0:y1 + 1, x0:x1 + 1][win] = np.clip(c, 0, 255)

    for d in dummy:
        raster(d['V'], d['F'], col=d['col'])
    for nm, p in pieces.items():
        if p['glow']:
            raster(p['V'], p['F'], col=(60, 235, 245), glow=True)
        else:
            raster(p['V'], p['F'], uv=p['uv'], tex=p['tex'].astype(float))
    return Image.fromarray(img.astype(np.uint8))


views = [('Back', 0, 0.12), ('Back 3/4', 0.75, 0.25), ('Front 3/4', math.pi - 0.6, 0.15), ('Side', math.pi / 2, 0.05)]
out = Image.new('RGB', (1600, 1600))
for i, (nm, yaw, pitch) in enumerate(views):
    im = draw(yaw, pitch)
    ImageDraw.Draw(im).text((12, 10), nm, fill=(255, 255, 255))
    out.paste(im, ((i % 2) * 800, (i // 2) * 800))
out.save(out_path)
