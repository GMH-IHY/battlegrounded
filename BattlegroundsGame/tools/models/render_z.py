"""Z-buffer preview renderer for boxes/wedges in boxes.json (plus a grey R6 dummy)."""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw

boxes = json.load(open('/home/claude/moth/boxes.json'))
for pos, size, col in [([0, 0, 0], [2, 2, 1], (40, 127, 71)), ([0, 1.5, 0], [1.2, 1.2, 1.2], (245, 205, 48)),
                       ([1.5, 0, 0], [1, 2, 1], (245, 205, 48)), ([-1.5, 0, 0], [1, 2, 1], (245, 205, 48)),
                       ([0.5, -2, 0], [1, 2, 1], (13, 105, 172)), ([-0.5, -2, 0], [1, 2, 1], (13, 105, 172))]:
    m = np.eye(4); m[:3, 3] = pos
    boxes.append({'m': m.tolist(), 'size': size, 'color': list(col), 'mat': 'Plastic'})

C = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
BOX_T = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
WC = np.array([(-.5, -.5, -.5), (-.5, -.5, .5), (-.5, .5, .5), (.5, -.5, -.5), (.5, -.5, .5), (.5, .5, .5)])
WED_T = [(0, 2, 1), (3, 4, 5), (0, 1, 4), (0, 4, 3), (1, 2, 5), (1, 5, 4), (0, 3, 5), (0, 5, 2)]
def _cyl(n=16):
    v = [(x, 0.5 * math.cos(2 * math.pi * i / n), 0.5 * math.sin(2 * math.pi * i / n)) for x in (-.5, .5) for i in range(n)]
    v += [(-.5, 0, 0), (.5, 0, 0)]
    t = []
    for i in range(n):
        j = (i + 1) % n
        t += [(i, j, n + j), (i, n + j, n + i), (2 * n, j, i), (2 * n + 1, n + i, n + j)]
    return np.array(v), t
def _ball(nu=12, nv=8):
    v = []
    for a in range(nv + 1):
        th = math.pi * a / nv
        for b in range(nu):
            ph = 2 * math.pi * b / nu
            v.append((0.5 * math.sin(th) * math.cos(ph), 0.5 * math.cos(th), 0.5 * math.sin(th) * math.sin(ph)))
    t = []
    for a in range(nv):
        for b in range(nu):
            i, j = a * nu + b, a * nu + (b + 1) % nu
            t += [(i, j, j + nu), (i, j + nu, i + nu)]
    return np.array(v), t
CYL = _cyl(); BALL = _ball()
LIGHT = np.array([0.4, 0.8, 0.5]); LIGHT /= np.linalg.norm(LIGHT)

tris = []
for b in boxes:
    m = np.array(b['m']); R = m[:3, :3]; p = m[:3, 3]
    shp = b.get('shape', 'Block')
    if b.get('wedge'):
        local, idx = WC, WED_T
    elif shp == 'Cylinder':
        local, idx = CYL
    elif shp == 'Ball':
        local, idx = BALL
    else:
        local, idx = C, BOX_T
    V = (local * np.array(b['size'])) @ R.T + p
    ctr = V.mean(0)
    for i, j, k in idx:
        a, bb, c = V[i], V[j], V[k]
        n = np.cross(bb - a, c - a)
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n /= ln
        if n @ ((a + bb + c) / 3 - ctr) < 0:
            n = -n
        col = np.array(b['color'], float)
        if b['mat'] == 'Neon':
            col = np.minimum(255, col * 1.15)
        else:
            col = col * (0.5 + 0.5 * max(0.0, n @ LIGHT))
        tris.append((a, bb, c, n, col))


def view(yaw, pitch, W=700, H=700, scale=64, centre=np.array([0, 0.6, 0])):
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    fwd = np.array([-sy * cp, -sp, -cy * cp]); right = np.array([cy, 0, -sy]); up = np.cross(right, fwd)
    zb = np.full((H, W), np.inf); img = np.zeros((H, W, 3)); img[:] = (122, 122, 122)
    for a, b, c, n, col in tris:
        if n @ fwd > 0.02:
            continue
        P = np.array([[W / 2 + (q - centre) @ right * scale, H / 2 - (q - centre) @ up * scale, (q - centre) @ fwd] for q in (a, b, c)])
        x0, x1 = int(max(0, P[:, 0].min())), int(min(W - 1, P[:, 0].max() + 1))
        y0, y1 = int(max(0, P[:, 1].min())), int(min(H - 1, P[:, 1].max() + 1))
        if x0 > x1 or y0 > y1:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (xa, ya, za), (xb, yb, zb_), (xc, yc, zc) = P
        den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
        if abs(den) < 1e-9:
            continue
        l1 = ((yb - yc) * (xs - xc) + (xc - xb) * (ys - yc)) / den
        l2 = ((yc - ya) * (xs - xc) + (xa - xc) * (ys - yc)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
        z = l1 * za + l2 * zb_ + l3 * zc
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        win = inside & (z < sub)
        sub[win] = z[win]
        img[y0:y1 + 1, x0:x1 + 1][win] = col
    return Image.fromarray(img.astype(np.uint8))


views = [('Back', 0, 0.12), ('Back 3/4', 0.7, 0.25), ('Front 3/4', math.pi - 0.6, 0.15), ('Side', math.pi / 2, 0.05)]
out = Image.new('RGB', (1400, 1400))
for i, (name, yaw, pitch) in enumerate(views):
    im = view(yaw, pitch)
    ImageDraw.Draw(im).text((12, 10), name, fill=(255, 255, 255))
    out.paste(im, ((i % 2) * 700, (i // 2) * 700))
out.save(sys.argv[1] if len(sys.argv) > 1 else '/home/claude/moth/preview.png')
