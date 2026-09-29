"""Stepped timing: build animations from key poses plus generated in-betweens.

Every pose still SNAPS in game (Constant easing). Smoothness comes from spacing: a move that
starts slow gets its in-betweens bunched near the start pose, a move that settles gets them
bunched near the end pose. That is the "choppy but smooth" look (docs/art/ArtDirection.md).

    keys = timeline([
        (ready, 0.05),
        *tween(ready, strike, SLOW_IN, 0.03),   # two in-betweens, small move first
        (strike, 0.08),
        *tween(strike, ready, SETTLE, 0.04),    # overshoot is authored; in-betweens settle into it
        (ready, 0.06),
    ])

A pose maps joint names to an authored dict (rig.py: pitch / yaw / roll / offset) or a ready
4x4 Transform (Moth wing bones). Keys starting with "_" are flags and are carried along.
"""
import numpy as np
from scipy.spatial.transform import Rotation, Slerp

# In-between spacings (fractions of the way from the first pose to the second).
SLOW_IN = (0.15, 0.45)          # anticipation: a small move first, then the big one
SLOW_OUT = (0.55, 0.85)         # most of the move at once, then a small settle
SETTLE = (0.6, 0.9)             # into a rest pose at the end of an action
EVEN = (0.33, 0.66)
ONE = (0.5,)
QUICK_IN = (0.3,)               # one in-between near the start
QUICK_OUT = (0.7,)              # one in-between near the end


def _lerp(a, b, t):
    return a + (b - a) * t


def _lerp_joint(a, b, t):
    if isinstance(a, dict) and isinstance(b, dict):
        return {
            "pitch": _lerp(a["pitch"], b["pitch"], t),
            "yaw": _lerp(a["yaw"], b["yaw"], t),
            "roll": _lerp(a["roll"], b["roll"], t),
            "offset": tuple(_lerp(x, y, t) for x, y in zip(a["offset"], b["offset"])),
        }
    if isinstance(a, np.ndarray) and isinstance(b, np.ndarray):
        rots = Rotation.from_matrix(np.stack([a[:3, :3], b[:3, :3]]))
        out = np.eye(4)
        out[:3, :3] = Slerp([0, 1], rots)([t]).as_matrix()[0]
        out[:3, 3] = _lerp(a[:3, 3], b[:3, 3], t)
        return out
    return b if t >= 0.5 else a


def lerp_pose(a, b, t):
    """The pose a share t of the way from a to b. Joints keyed in only one pose stay as they are."""
    out = {}
    for joint in set(a) | set(b):
        if joint.startswith("_"):
            out[joint] = a.get(joint, b.get(joint))
        elif joint in a and joint in b:
            out[joint] = _lerp_joint(a[joint], b[joint], t)
        else:
            out[joint] = a[joint] if joint in a else b[joint]
    out.pop("_planted", None)
    return out


def tween(a, b, fractions, hold):
    """In-between poses from a toward b, each held `hold` seconds: [(pose, hold), ...].
    `hold` may be a list with one value per in-between."""
    holds = hold if isinstance(hold, (list, tuple)) else [hold] * len(fractions)
    return [(lerp_pose(a, b, f), h) for f, h in zip(fractions, holds)]


def timeline(steps, loop=False):
    """[(pose, hold seconds), ...] -> keyframes [(time, pose)].
    One-shots end with a copy of the last pose at the end time (it holds for its full beat);
    loops end with a copy of the first pose (the loop wraps without a double frame)."""
    keys, t = [], 0.0
    for p, hold in steps:
        keys.append((round(t, 4), p))
        t += hold
    keys.append((round(t, 4), steps[0][0] if loop else steps[-1][0]))
    return keys


def cycle(poses, holds):
    """A loop from poses with one hold each (a single number = the same for all)."""
    holds = holds if isinstance(holds, (list, tuple)) else [holds] * len(poses)
    return timeline(list(zip(poses, holds)), loop=True)


def length(keys):
    return keys[-1][0]


def retime(keys, total):
    """Scales a key list so it lasts `total` seconds (keeps the spacing)."""
    scale = total / keys[-1][0]
    return [(round(t * scale, 4), p) for t, p in keys]
