"""Contact sheet for the Moth animations: every keyframe pose (with wings / antennae) from a back 3/4
view and a side view. Usage: python moth_preview.py <moth_parts.json> <out.png> [AnimName ...]"""
import json, math, sys
import numpy as np
from PIL import Image, ImageDraw
from rig import fk, SIZES, JOINTS, inv, transform
from anims import pose, body, limb
from moth_anims import MOTH, R6

BODY_COLORS = {"Torso": (40, 90, 170), "Head": (245, 205, 48), "Right Arm": (245, 205, 48), "Left Arm": (245, 205, 48),
               "Right Leg": (60, 140, 70), "Left Leg": (60, 140, 70)}
C = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
BOX_T = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
WC = np.array([(-.5, -.5, -.5), (-.5, -.5, .5), (-.5, .5, .5), (.5, -.5, -.5), (.5, -.5, .5), (.5, .5, .5)])
WED_T = [(0, 2, 1), (3, 4, 5), (0, 1, 4), (0, 4, 3), (1, 2, 5), (1, 5, 4), (0, 3, 5), (0, 5, 2)]


def _cyl(n=12):
    v = [(x, 0.5 * math.cos(2 * math.pi * i / n), 0.5 * math.sin(2 * math.pi * i / n)) for x in (-.5, .5) for i in range(n)]
    v += [(-.5, 0, 0), (.5, 0, 0)]
    t = []
    for i in range(n):
        j = (i + 1) % n
        t += [(i, j, n + j), (i, n + j, n + i), (2 * n, j, i), (2 * n + 1, n + i, n + j)]
    return np.array(v), t


def _ball(nu=10, nv=6):
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


CYL, BALL = _cyl(), _ball()
LIGHT = np.array([0.35, 0.8, 0.5]); LIGHT /= np.linalg.norm(LIGHT)
REST_POSE = pose()


def full_pose(keyed, carry):
    """Keyed joints override `carry` (the previous displayed state); unkeyed R6 joints show rest."""
    state = dict(carry)
    state.update(keyed)
    return state


def world_boxes(state, data):
    """state: {joint: Transform}. Returns list of box dicts in world space (root at y=3)."""
    p = dict(REST_POSE)
    world = {"HumanoidRootPart": np.array([[1, 0, 0, 0], [0, 1, 0, 3], [0, 0, 1, 0], [0, 0, 0, 1]], float)}
    for j in ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]:
        p0, p1, c0, c1 = JOINTS[j]
        t = state[j] if j in state else transform(j, p[j])
        world[p1] = world[p0] @ c0 @ t @ inv(c1)
    boxes = [dict(m=world[n], size=SIZES[n], color=c, kind="box", neon=False) for n, c in BODY_COLORS.items()]
    bone = {}
    for jd in data["joints"]:
        t = state.get(jd["name"], np.eye(4))
        bone[jd["name"]] = world[jd["part0"]] @ np.array(jd["c0"]) @ t
    for s in data["parts"]:
        kind = "wedge" if s["cls"] == "WedgePart" else s["shape"].lower()
        boxes.append(dict(m=bone[s["bone"]] @ np.array(s["rel"]), size=s["size"], color=tuple(s["color"]),
                          kind=kind, neon=s["mat"] == "Neon"))
    return boxes


def render(boxes, yaw, pitch, W=300, H=340, scale=34, centre=np.array([0, 3.2, 0.5])):
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    fwd = np.array([-sy * cp, -sp, -cy * cp]); right = np.array([cy, 0, -sy]); up = np.cross(right, fwd)
    zb = np.full((H, W), np.inf)
    img = np.zeros((H, W, 3)); img[:] = (128, 128, 128)
    # floor line
    for b in boxes:
        local, idx = {"box": (C, BOX_T), "block": (C, BOX_T), "wedge": (WC, WED_T), "cylinder": CYL, "ball": BALL}[b["kind"]]
        m = b["m"]
        V = (local * np.array(b["size"])) @ m[:3, :3].T + m[:3, 3]
        ctr = V.mean(0)
        for i, j, k in idx:
            a, bb, c = V[i], V[j], V[k]
            n = np.cross(bb - a, c - a)
            ln = np.linalg.norm(n)
            if ln < 1e-12:
                continue
            n /= ln
            if n @ ((a + bb + c) / 3 - ctr) < 0:
                n = -n
            if n @ fwd > 0.02:
                continue
            col = np.array(b["color"], float) * (1.0 if b["neon"] else 0.45 + 0.55 * max(0.0, n @ LIGHT) + 0.1)
            P = np.array([[W / 2 + (q - centre) @ right * scale, H / 2 - (q - centre) @ up * scale, (q - centre) @ fwd] for q in (a, bb, c)])
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
            ins = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            z = l1 * za + l2 * zb_ + l3 * zc
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            win = ins & (z < sub)
            sub[win] = z[win]
            img[y0:y1 + 1, x0:x1 + 1][win] = np.clip(col, 0, 255)
    return Image.fromarray(img.astype(np.uint8))


VIEWS = [("back 3/4", 0.6, 0.18), ("side", math.pi / 2, 0.05), ("front 3/4", math.pi - 0.6, 0.12)]


def sheet(anims, data, out):
    rows = []
    for a in anims:
        keys = a["keys"][:-1] if len(a["keys"]) > 1 else a["keys"]
        carry = {}
        tiles = []
        for t, keyed in keys:
            state = full_pose(keyed, {})
            boxes = world_boxes(state, data)
            col = [render(boxes, yaw, pitch) for _, yaw, pitch in VIEWS]
            tile = Image.new("RGB", (300, 340 * len(VIEWS) + 22), (40, 40, 40))
            for i, im in enumerate(col):
                tile.paste(im, (0, 22 + i * 340))
            ImageDraw.Draw(tile).text((6, 5), f"{a['name']} @ {t:.2f}s", fill=(255, 255, 255))
            tiles.append(tile)
        row = Image.new("RGB", (300 * len(tiles), tiles[0].height), (40, 40, 40))
        for i, t in enumerate(tiles):
            row.paste(t, (i * 300, 0))
        rows.append(row)
    Wd = max(r.width for r in rows)
    img = Image.new("RGB", (Wd, sum(r.height for r in rows)), (30, 30, 30))
    y = 0
    for r in rows:
        img.paste(r, (0, y)); y += r.height
    img.save(out)


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    names = sys.argv[3:]
    anims = [a for a in MOTH if not names or a["name"] in names]
    sheet(anims, data, sys.argv[2])
