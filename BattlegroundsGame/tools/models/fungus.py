"""The Lotus Fungus growth on the body, by stage (docs/art/ArtDirection.md, "Lotus Fungus").

    python tools/models/fungus.py

Writes src/shared/Combat/FungusData.luau; the game builds the growth from it (FungusParts.luau) and
shows the parts of your stage and below (growth snaps from stage to stage), and the animation tools
draw it in previews of the Lotus animations.

Stage 1 = the forearm; stage 2 = the whole left arm and the shoulder; stage 3 = the shoulder, the
left of the chest, part of the back and the neck. The hand (the bottom of the arm) always stays
bare, so the dagger and the lantern still work. Low-poly blobs (balls and small blocks) in the sculk
palette, dark green / dark blue speckles, a few glowing cyan specks (Neon) and pale bone spikes.
Everything is placed by a fixed random seed, so the growth is the same on every run.
"""
import math
import os
import random

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_LUAU = os.path.join(ROOT, "src", "shared", "Combat", "FungusData.luau")

BASE = (0x10, 0x14, 0x18)
VARIATION = [(0x18, 0x20, 0x28), (0x0F, 0x2D, 0x36)]
GREEN = (0x1B, 0x3A, 0x2A)
BLUE = (0x16, 0x30, 0x5A)
CYAN = (0x10, 0x98, 0xA8)
BONE = (0xC8, 0xC2, 0xA8)

HAND_TOP = -0.55  # the hand (arm-local y below this) stays bare


def rot_to(direction):
    """A rotation whose +Y points along `direction`."""
    y = np.array(direction, float)
    y /= np.linalg.norm(y)
    helper = np.array([0, 0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0, 0])
    x = np.cross(y, helper)
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.column_stack([x, y, z])


def cf(pos, rot=None):
    m = np.eye(4)
    m[:3, 3] = pos
    if rot is not None:
        m[:3, :3] = rot
    return m


# Surfaces to grow on: (limb, stage, point sampler returning (position, outward normal)).
def arm_surface(y_range, faces):
    """A sampler over the left arm's faces within an arm-local y range. Faces: -x (outer), -z (front),
    +z (back), +x (inner), +y (top)."""
    def sample(rng):
        face = rng.choice(faces)
        if face == "+y":
            return np.array([rng.uniform(-0.4, 0.4), 1.0, rng.uniform(-0.4, 0.4)]), np.array([0, 1.0, 0])
        y = rng.uniform(*y_range)
        t = rng.uniform(-0.4, 0.4)
        return {
            "-x": (np.array([-0.5, y, t]), np.array([-1.0, 0, 0])),
            "+x": (np.array([0.5, y, t]), np.array([1.0, 0, 0])),
            "-z": (np.array([t, y, -0.5]), np.array([0, 0, -1.0])),
            "+z": (np.array([t, y, 0.5]), np.array([0, 0, 1.0])),
        }[face]
    return sample


def torso_surface(regions):
    """Regions of the torso (2 x 2 x 1): ("front"|"back"|"top", x range, y range)."""
    def sample(rng):
        face, xr, yr = rng.choice(regions)
        x, y = rng.uniform(*xr), rng.uniform(*yr)
        if face == "front":
            return np.array([x, y, -0.5]), np.array([0, 0, -1.0])
        if face == "back":
            return np.array([x, y, 0.5]), np.array([0, 0, 1.0])
        return np.array([x, 1.0, rng.uniform(-0.4, 0.4)]), np.array([0, 1.0, 0])
    return sample


def head_surface():
    """The lower left of the head (head part 2 x 1 x 1)."""
    def sample(rng):
        return np.array([rng.uniform(-0.6, -0.2), rng.uniform(-0.5, -0.2), rng.uniform(-0.3, 0.3)]), np.array([-0.7, -0.3, 0])
    return sample


# (stage, limb, sampler, blobs, speckles, glows, spikes)
LAYERS = [
    (1, "Left Arm", arm_surface((HAND_TOP + 0.32, 0.15), ["-x", "-x", "-z", "+z", "+x"]), 10, 3, 2, 3),
    (2, "Left Arm", arm_surface((0.15, 0.95), ["-x", "-x", "-z", "+z", "+x"]), 9, 3, 1, 2),
    (2, "Left Arm", arm_surface((0.6, 1.0), ["+y"]), 3, 0, 1, 1),
    (3, "Torso", torso_surface([("front", (-0.95, -0.2), (0.0, 0.95)), ("top", (-0.95, -0.3), (0, 0))]), 10, 3, 2, 3),
    (3, "Torso", torso_surface([("back", (-0.95, -0.1), (0.1, 0.95))]), 6, 2, 1, 2),
    (3, "Head", head_surface(), 2, 1, 0, 0),
]

# The shell under the blobs: a low-poly sleeve / patch per stage, so the growth reads as one mass.
# (limb, stage, size, centre)
SHELLS = [
    (1, "Left Arm", (1.12, 0.72, 1.12), (0, -0.19, 0)),           # the forearm, stopping above the hand
    (2, "Left Arm", (1.12, 0.86, 1.12), (0, 0.575, 0)),           # the upper arm
    (2, "Left Arm", (1.2, 0.28, 1.2), (0, 1.02, 0)),              # the shoulder cap
    (3, "Torso", (0.95, 1.05, 0.14), (-0.52, 0.45, -0.53)),       # the left of the chest
    (3, "Torso", (0.95, 0.85, 0.14), (-0.52, 0.5, 0.53)),         # the back
    (3, "Torso", (0.85, 0.14, 0.95), (-0.55, 1.03, 0)),           # over the shoulder
    (3, "Torso", (0.7, 0.26, 0.7), (-0.25, 1.08, 0)),             # up the neck
]


def build():
    rng = random.Random(7)
    parts = []
    for stage, limb, size, centre in SHELLS:
        parts.append((limb, stage, "Shell", "Block", size, cf(centre), BASE, False))
    for stage, limb, sample, blobs, speckles, glows, spikes in LAYERS:
        for i in range(blobs):
            pos, normal = sample(rng)
            size = rng.uniform(0.4, 0.7)
            # Sitting on the shell: most of the blob shows.
            centre = pos + normal * size * 0.15
            color = BASE if i % 3 else rng.choice(VARIATION)
            shape = "Ball" if i % 4 else "Block"
            tilt = rot_to(normal) @ np.array(
                [[math.cos(i), 0, math.sin(i)], [0, 1, 0], [-math.sin(i), 0, math.cos(i)]])
            parts.append((limb, stage, "Blob", shape, (size, size * rng.uniform(0.8, 1.0), size), cf(centre, tilt), color, False))
        for _ in range(speckles):
            pos, normal = sample(rng)
            s = rng.uniform(0.12, 0.18)
            parts.append((limb, stage, "Speckle", "Block", (s, s, s), cf(pos + normal * 0.14), rng.choice([GREEN, BLUE]), False))
        for _ in range(glows):
            pos, normal = sample(rng)
            parts.append((limb, stage, "Glow", "Block", (0.12, 0.12, 0.12), cf(pos + normal * 0.16), CYAN, True))
        for _ in range(spikes):
            pos, normal = sample(rng)
            length = rng.uniform(0.35, 0.6)
            out = normal + np.array([rng.uniform(-0.4, 0.4), rng.uniform(0, 0.4), rng.uniform(-0.4, 0.4)])
            rot = rot_to(out)
            centre = pos + rot[:, 1] * length / 2
            parts.append((limb, stage, "Spike", "Block", (0.1, length, 0.1), cf(centre, rot), BONE, False))
    return parts


def fmt_cf(m):
    p = m[:3, 3]
    r = m[:3, :3]
    nums = [p[0], p[1], p[2]] + [r[i, j] for i in range(3) for j in range(3)]
    return "CFrame.new(" + ", ".join(f"{0.0 if abs(x) < 5e-6 else x:.5f}" for x in nums) + ")"


def write_luau():
    parts = build()
    for limb, _, name, _, size, rel, _, _ in parts:
        if limb == "Left Arm":
            bottom = rel[1, 3] - (size[1] if name == "Shell" else max(size)) / 2
            assert bottom >= HAND_TOP - 0.02, f"a {name} reaches the hand (bottom at {bottom:.2f})"
    lines = [
        "--!strict",
        "-- FungusData (ModuleScript, ReplicatedStorage > Combat > FungusData)",
        "-- GENERATED by tools/models/fungus.py. Don't edit by hand: change the script and rerun it.",
        "-- The Lotus Fungus growth: every piece, the limb it grows on (CFrame relative to that limb) and",
        "-- the meter stage it appears at.",
        "",
        "export type PartSpec = { Limb: string, Stage: number, Name: string, Shape: string, Size: Vector3, "
        "CFrame: CFrame, Color: Color3, Neon: boolean }",
        "",
        "local Parts: { PartSpec } = {",
    ]
    for limb, stage, name, shape, size, rel, color, neon in parts:
        lines.append(
            f'\t{{ Limb = "{limb}", Stage = {stage}, Name = "{name}", Shape = "{shape}", '
            f"Size = Vector3.new({size[0]:.4f}, {size[1]:.4f}, {size[2]:.4f}), CFrame = {fmt_cf(rel)}, "
            f"Color = Color3.fromRGB({color[0]}, {color[1]}, {color[2]}), Neon = {'true' if neon else 'false'} }},")
    lines += ["}", "", "return { Parts = Parts }", ""]
    open(OUT_LUAU, "w", encoding="utf-8").write("\n".join(lines))
    counts = {s: sum(1 for p in parts if p[1] == s) for s in (1, 2, 3)}
    print(f"wrote {OUT_LUAU} ({len(parts)} parts; by stage {counts})")


if __name__ == "__main__":
    write_luau()
