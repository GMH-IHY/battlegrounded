import json, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

boxes = json.load(open('/home/claude/moth/boxes.json'))
GREY = (163, 162, 165)
dummy = [
    ([0, 0, 0], [2, 2, 1], (40, 127, 71)),
    ([0, 1.5, 0], [2, 1, 1], (245, 205, 48)),   # head (R6 head part is 2x1x1)
    ([1.5, 0, 0], [1, 2, 1], (245, 205, 48)),
    ([-1.5, 0, 0], [1, 2, 1], (245, 205, 48)),
    ([0.5, -2, 0], [1, 2, 1], (13, 105, 172)),
    ([-0.5, -2, 0], [1, 2, 1], (13, 105, 172)),
]
for pos, size, col in dummy:
    m = np.eye(4); m[:3, 3] = pos
    boxes.append({'m': m.tolist(), 'size': size, 'color': list(col), 'mat': 'Plastic', 'group': 'dummy'})

CORN = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
FACES = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)),
         ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]
LIGHT = np.array([0.4, 0.8, 0.5]); LIGHT /= np.linalg.norm(LIGHT)


def view(yaw, pitch, W=700, H=700, scale=62, centre=(0, 0.8, 0)):
    # camera looks along -forward; yaw 0 = camera behind the character (at +Z) looking toward -Z
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    fwd = np.array([-sy * cp, -sp, -cy * cp])      # view direction
    right = np.array([cy, 0, -sy])
    up = np.cross(right, fwd)
    img = Image.new('RGB', (W, H), (122, 122, 122))
    d = ImageDraw.Draw(img)
    polys = []
    for b in boxes:
        m = np.array(b['m']); R = m[:3, :3]; p = m[:3, 3]
        corners = (CORN * np.array(b['size'])) @ R.T + p
        for idx, n in FACES:
            nw = R @ np.array(n, float)
            if nw @ fwd >= 0:
                continue
            pts = corners[list(idx)]
            depth = (pts - centre) @ fwd
            proj = [(W / 2 + ((q - centre) @ right) * scale, H / 2 - ((q - centre) @ up) * scale) for q in pts]
            col = np.array(b['color'], float)
            if b['mat'] != 'Neon':
                col = col * (0.55 + 0.45 * max(0, nw @ LIGHT))
            else:
                col = np.minimum(255, col * 1.1)
            polys.append((depth.mean(), proj, tuple(int(c) for c in col), b['mat'] == 'Neon'))
    polys.sort(key=lambda t: -t[0])
    for _, proj, col, neon in polys:
        d.polygon(proj, fill=col, outline=(int(col[0] * .7), int(col[1] * .7), int(col[2] * .7)) if not neon else col)
    return img


views = [('Back', 0, 0.12), ('Back 3/4', 0.7, 0.25), ('Front 3/4', math.pi - 0.6, 0.15), ('Side', math.pi / 2, 0.05)]
tiles = []
for name, yaw, pitch in views:
    im = view(yaw, pitch)
    ImageDraw.Draw(im).text((12, 10), name, fill=(255, 255, 255))
    tiles.append(im)
out = Image.new('RGB', (1400, 1400))
for i, t in enumerate(tiles):
    out.paste(t, ((i % 2) * 700, (i // 2) * 700))
out.save(sys.argv[1] if len(sys.argv) > 1 else '/home/claude/moth/preview.png')
