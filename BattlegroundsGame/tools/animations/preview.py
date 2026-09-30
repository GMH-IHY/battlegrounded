"""Contact sheets: every pose of every animation, drawn from three angles, one row per animation.

    python tools/animations/preview.py <out.png> [Name ...]

Poses that key only some joints are drawn over the rest pose. The Moth's wings and antennae are
drawn from the same data the game builds them from (src/shared/Movement/MothPartsData.luau), and so
are the sword (on its animated SwordGrip bone), the sheath and the dagger (in the left hand for the
Dagger* animations, on the hip otherwise): src/shared/Combat/WeaponModelsData.luau.
The renderer is a tiny flat-shaded z-buffer, so it needs only numpy and Pillow.
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rig import JOINTS, SIZES, inv, transform, pose  # noqa: E402
from catalog import ALL  # noqa: E402

MOTH_DATA = os.path.join(HERE, "..", "..", "src", "shared", "Movement", "MothPartsData.luau")
WEAPON_DATA = os.path.join(HERE, "..", "..", "src", "shared", "Combat", "WeaponModelsData.luau")
FUNGUS_DATA = os.path.join(HERE, "..", "..", "src", "shared", "Combat", "FungusData.luau")
R6 = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
BODY_COLORS = {"Torso": (40, 90, 170), "Head": (245, 205, 48), "Right Arm": (245, 205, 48),
               "Left Arm": (245, 205, 48), "Right Leg": (60, 140, 70), "Left Leg": (60, 140, 70)}
REST = pose()
TILE_W, TILE_H, LABEL_H = 260, 300, 20
VIEWS = [("back 3/4", 0.6, 0.18), ("side", math.pi / 2, 0.05), ("front 3/4", math.pi - 0.6, 0.12)]
LIGHT = np.array([0.35, 0.8, 0.5]) / np.linalg.norm([0.35, 0.8, 0.5])

# Unit meshes (vertices in -0.5..0.5, triangles).
BOX = (np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)]),
       [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6),
        (0, 6, 4), (1, 5, 7), (1, 7, 3)])
WEDGE = (np.array([(-.5, -.5, -.5), (-.5, -.5, .5), (-.5, .5, .5), (.5, -.5, -.5), (.5, -.5, .5), (.5, .5, .5)]),
         [(0, 2, 1), (3, 4, 5), (0, 1, 4), (0, 4, 3), (1, 2, 5), (1, 5, 4), (0, 3, 5), (0, 5, 2)])


def _cylinder(n=12):
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


MESHES = {"box": BOX, "block": BOX, "wedge": WEDGE, "cylinder": _cylinder(), "ball": _ball()}


# ---------------- Moth extras (wings / antennae) --------------------------------------------
def _cframe(nums):
    m = np.eye(4)
    m[:3, 3] = nums[:3]
    m[:3, :3] = np.array(nums[3:12]).reshape(3, 3)
    return m


def _floats(s):
    return [float(x) for x in s.split(",")]


def load_moth_parts(path=MOTH_DATA):
    """Parses the generated MothPartsData module: bone joints + parts relative to their bone."""
    if not os.path.exists(path):
        return {"joints": [], "parts": []}
    text = open(path, encoding="utf-8").read()
    joints = [{"name": n, "part0": p0, "c0": _cframe(_floats(c))} for n, p0, c in
              re.findall(r'Name = "(\w+)", Part0 = "(\w+)", C0 = CFrame\.new\(([^)]*)\)', text)]
    parts = []
    for bone, cls, shape, size, cf, rgb, mat in re.findall(
            r'Bone = "(\w+)", Name = "\w+", Class = "(\w+)", Shape = "(\w+)", Size = Vector3\.new\(([^)]*)\), '
            r'CFrame = CFrame\.new\(([^)]*)\), Color = Color3\.fromRGB\(([^)]*)\), Material = Enum\.Material\.(\w+)', text):
        parts.append({"bone": bone, "kind": "wedge" if cls == "WedgePart" else shape.lower(),
                      "size": _floats(size), "rel": _cframe(_floats(cf)),
                      "color": tuple(int(float(x)) for x in rgb.split(",")), "neon": mat == "Neon"})
    return {"joints": joints, "parts": parts}


def load_weapons(path=WEAPON_DATA):
    """Parses the generated WeaponModelsData module: the SwordGrip bone, the weld mounts, the parts."""
    if not os.path.exists(path):
        return {"joints": [], "mounts": {}, "parts": []}
    text = open(path, encoding="utf-8").read()
    joints_block = text[text.index("local Joints"):text.index("local Mounts")]
    mounts_block = text[text.index("local Mounts"):text.index("local Parts")]
    pat = r'Name = "(\w+)", Part0 = "([\w ]+)", C0 = CFrame\.new\(([^)]*)\)'
    joints = [{"name": n, "part0": p0, "c0": _cframe(_floats(c))} for n, p0, c in re.findall(pat, joints_block)]
    mounts = {n: {"part0": p0, "c0": _cframe(_floats(c))} for n, p0, c in re.findall(pat, mounts_block)}
    return {"joints": joints, "mounts": mounts, "parts": load_moth_parts(path)["parts"]}


def load_fungus(path=FUNGUS_DATA):
    """Parses the generated FungusData module: growth pieces on their limb, by stage."""
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read()
    out = []
    for limb, stage, shape, size, cf, rgb, neon in re.findall(
            r'Limb = "([\w ]+)", Stage = (\d), Name = "\w+", Shape = "(\w+)", Size = Vector3\.new\(([^)]*)\), '
            r'CFrame = CFrame\.new\(([^)]*)\), Color = Color3\.fromRGB\(([^)]*)\), Neon = (\w+)', text):
        out.append({"limb": limb, "stage": int(stage), "kind": shape.lower(), "size": _floats(size),
                    "rel": _cframe(_floats(cf)), "color": tuple(int(float(x)) for x in rgb.split(",")),
                    "neon": neon == "true"})
    return out


# Lotus animations are drawn with the growth of this stage (0 = none).
def fungus_stage_for(name):
    return 3 if name.startswith("Lotus") else 0


# ---------------- posing ----------------------------------------------------------------
def joint_transform(joint, v):
    return transform(joint, v) if isinstance(v, dict) else v


def world_pieces(keyed, extras, weapons=None, dagger_drawn=False, fungus=None, fungus_stage=0):
    """Everything to draw for one pose, in world space (standing R6 root at y = 3)."""
    world = {"HumanoidRootPart": np.array([[1, 0, 0, 0], [0, 1, 0, 3], [0, 0, 1, 0], [0, 0, 0, 1]], float)}
    for j in R6:
        p0, p1, c0, c1 = JOINTS[j]
        t = joint_transform(j, keyed[j]) if j in keyed else transform(j, REST[j])
        world[p1] = world[p0] @ c0 @ t @ inv(c1)
    pieces = [dict(m=world[n], size=SIZES[n], color=c, kind="box", neon=False) for n, c in BODY_COLORS.items()]
    uses_extras = any(j["name"] in keyed for j in extras["joints"])
    if uses_extras:
        bone = {j["name"]: world[j["part0"]] @ j["c0"] @ joint_transform(j["name"], keyed.get(j["name"], np.eye(4)))
                for j in extras["joints"]}
        for s in extras["parts"]:
            pieces.append(dict(m=bone[s["bone"]] @ s["rel"], size=s["size"], color=s["color"], kind=s["kind"],
                               neon=s["neon"]))
    if weapons and weapons["joints"]:
        frame = {j["name"]: world[j["part0"]] @ j["c0"] @ joint_transform(j["name"], keyed.get(j["name"], np.eye(4)))
                 for j in weapons["joints"]}
        mounts = weapons["mounts"]
        dagger = mounts["DaggerHand" if dagger_drawn else "DaggerHip"]
        frame["Dagger"] = world[dagger["part0"]] @ dagger["c0"]
        frame["Sheath"] = world[mounts["Sheath"]["part0"]] @ mounts["Sheath"]["c0"]
        for s in weapons["parts"]:
            pieces.append(dict(m=frame[s["bone"]] @ s["rel"], size=s["size"], color=s["color"], kind=s["kind"],
                               neon=s["neon"]))
    for s in fungus or []:
        if s["stage"] <= fungus_stage:
            pieces.append(dict(m=world[s["limb"]] @ s["rel"], size=s["size"], color=s["color"], kind=s["kind"],
                               neon=s["neon"]))
    return pieces


# ---------------- rendering -------------------------------------------------------------
def render(pieces, yaw, pitch, W=TILE_W, H=TILE_H, scale=30, centre=np.array([0, 3.0, 0.3])):
    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    fwd = np.array([-sy * cp, -sp, -cy * cp])
    right = np.array([cy, 0, -sy])
    up = np.cross(right, fwd)
    zbuf = np.full((H, W), np.inf)
    img = np.zeros((H, W, 3))
    img[:] = (128, 128, 128)
    ground_y = H / 2 - (np.array([0, 0, 0]) - centre) @ up * scale
    img[int(min(H - 1, max(0, ground_y))):, :] = (112, 112, 112)
    for b in pieces:
        local, tris = MESHES[b["kind"]]
        m = b["m"]
        V = (local * np.array(b["size"])) @ m[:3, :3].T + m[:3, 3]
        ctr = V.mean(0)
        for i, j, k in tris:
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
            P = np.array([[W / 2 + (q - centre) @ right * scale, H / 2 - (q - centre) @ up * scale, (q - centre) @ fwd]
                          for q in (a, bb, c)])
            x0, x1 = int(max(0, P[:, 0].min())), int(min(W - 1, P[:, 0].max() + 1))
            y0, y1 = int(max(0, P[:, 1].min())), int(min(H - 1, P[:, 1].max() + 1))
            if x0 > x1 or y0 > y1:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            (xa, ya, za), (xb, yb, zb), (xc, yc, zc) = P
            den = (yb - yc) * (xa - xc) + (xc - xb) * (ya - yc)
            if abs(den) < 1e-9:
                continue
            l1 = ((yb - yc) * (xs - xc) + (xc - xb) * (ys - yc)) / den
            l2 = ((yc - ya) * (xs - xc) + (xa - xc) * (ys - yc)) / den
            l3 = 1 - l1 - l2
            inside = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            z = l1 * za + l2 * zb + l3 * zc
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            win = inside & (z < sub)
            sub[win] = z[win]
            img[y0:y1 + 1, x0:x1 + 1][win] = np.clip(col, 0, 255)
    return Image.fromarray(img.astype(np.uint8))


def poses_to_draw(anim):
    """A loop's last key repeats its first, so it's skipped."""
    keys = anim["keys"]
    return keys[:-1] if anim["loop"] and len(keys) > 1 else keys


def sheet(anims, out):
    extras = load_moth_parts()
    weapons = load_weapons()
    fungus = load_fungus()
    rows = []
    for a in anims:
        tiles = []
        keys = poses_to_draw(a)
        for idx, (t, keyed) in enumerate(keys):
            hold = (keys[idx + 1][0] if idx + 1 < len(keys) else a["keys"][-1][0]) - t
            pieces = world_pieces(keyed, extras, weapons, a["name"].startswith("Dagger"), fungus,
                                  fungus_stage_for(a["name"]))
            tile = Image.new("RGB", (TILE_W, TILE_H * len(VIEWS) + LABEL_H), (40, 40, 40))
            for i, (_, yaw, pitch) in enumerate(VIEWS):
                tile.paste(render(pieces, yaw, pitch), (0, LABEL_H + i * TILE_H))
            label = f"{a['name']}  #{idx + 1}  t={t:.2f}s  hold {hold * 1000:.0f}ms"
            ImageDraw.Draw(tile).text((6, 4), label, fill=(255, 255, 255))
            tiles.append(tile)
        row = Image.new("RGB", (TILE_W * len(tiles), tiles[0].height), (40, 40, 40))
        for i, tile in enumerate(tiles):
            row.paste(tile, (i * TILE_W, 0))
        rows.append(row)
    img = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)), (30, 30, 30))
    y = 0
    for r in rows:
        img.paste(r, (0, y))
        y += r.height
    img.save(out)
    print(f"wrote {out} ({len(anims)} animation(s); rows = views: {', '.join(v[0] for v in VIEWS)})")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    names = sys.argv[2:]
    unknown = [n for n in names if n not in {a["name"] for a in ALL}]
    if unknown:
        raise SystemExit("unknown animation(s): " + ", ".join(unknown))
    sheet([a for a in ALL if not names or a["name"] in names], sys.argv[1])
