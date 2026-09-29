"""Authoring helpers shared by every animation module.

Three ways to write a pose (all return {joint: authored dict}, see rig.py):
  pose(...)  raw joint dicts (rig.body / rig.limb)
  T(...)     limbs relative to the TORSO: (swing, out[, inward]); swing + = forward from hanging
  P(...)     limbs by their WORLD angle: (forward, outward) in degrees; the head keeps level

Style rules (docs/art/ArtDirection.md): Constant easing, exaggerated, start slow and end fast
(a small first move, then the big one, then a recoil). R6 has no knees or elbows, so bends happen
at the hips and shoulders and the BODY itself drops, rises and twists.
"""
import itertools

import numpy as np

from rig import limb, body, pose, fk, SIZES

# Enum.AnimationPriority tokens.
IDLE, MOVEMENT, ACTION, CORE = 0, 1, 2, 1000
R6 = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
NO_ROOT = R6[1:]
UPPER = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder"]


def seq(name, priority, loop, keys, notes, ground=False, snaps=()):
    """One animation. ground: the feet should touch the floor in every pose (tests check it).
    snaps: indexes of poses allowed to jump far from the pose before (deliberate impact frames)."""
    return {"name": name, "priority": priority, "loop": loop, "keys": keys, "notes": notes,
            "ground": ground, "snaps": tuple(snaps)}


def one_shot(poses_and_times, end):
    """[(time, pose), ...] -> keyframes; the last pose holds until `end`."""
    keys = [(round(t, 4), p) for t, p in poses_and_times]
    keys.append((round(end, 4), poses_and_times[-1][1]))
    return keys


def mirror_keys(keys):
    from rig import mirror
    return [(t, mirror(p)) for t, p in keys]


# ---------------- limb helpers ----------------------------------------------------------
def arm(side, swing=0, inward=0, out=0):
    """Arm kept against the torso: swings forward/back from the shoulder. inward + swings it across
    the front of the body. `out` stays small: rolling an R6 arm outward opens a gap at the shoulder."""
    s = 1 if side == "R" else -1
    return {"pitch": swing, "roll": s * out, "yaw": s * inward, "offset": (0, 0, 0)}


def leg(side, swing=0, out=0):
    return limb(side, swing=swing, out=out)


def w_leg(side, forward=0.0, outward=0.0, lean=0.0, tilt=0.0):
    """Leg by its WORLD angle: forward = degrees in front of straight down (negative = behind),
    outward = degrees out to its own side. lean/tilt are the torso's (tilt + = top to the right)."""
    s = 1 if side == "R" else -1
    return limb(side, swing=forward + lean, out=outward + s * tilt)


def w_arm(side, forward=0.0, outward=0.0, lean=0.0, tilt=0.0, inward=0.0):
    """Arm by its WORLD angle (same meaning as w_leg). inward swings it across the body."""
    s = 1 if side == "R" else -1
    a = limb(side, swing=forward + lean, out=outward + s * tilt)
    a["yaw"] += s * inward
    return a


def P(lean=0.0, tilt=0.0, turn=0.0, head_lean=None, head_tilt=None, head_turn=0.0, dy=0.0, dz=0.0,
      ra=(0, 0), la=(0, 0), rl=(0, 0), ll=(0, 0), ra_in=0.0, la_in=0.0):
    """A full pose from WORLD limb angles. Each limb is (forward, outward) in world degrees.
    The head keeps looking level by default (it cancels most of the torso's lean / tilt)."""
    hl = -lean * 0.8 if head_lean is None else head_lean
    ht = -tilt * 0.7 if head_tilt is None else head_tilt
    return pose(root=body(lean=lean, tilt=tilt, turn=turn, dy=dy, dz=dz),
                head=body(lean=hl, tilt=ht, turn=head_turn),
                ra=w_arm("R", *ra, lean=lean, tilt=tilt, inward=ra_in),
                la=w_arm("L", *la, lean=lean, tilt=tilt, inward=la_in),
                rl=w_leg("R", *rl, lean=lean, tilt=tilt),
                ll=w_leg("L", *ll, lean=lean, tilt=tilt))


def T(lean=0.0, tilt=0.0, turn=0.0, dy=0.0, dz=0.0, head=(0, 0, 0),
      ra=(0, 0, 0), la=(0, 0, 0), rl=(0, 0), ll=(0, 0)):
    """A full pose with limbs relative to the TORSO: (swing, out[, inward]).
    head = (lean, tilt, turn) relative to the torso."""
    def arm_(side, v):
        s = 1 if side == "R" else -1
        a = limb(side, swing=v[0], out=v[1])
        a["yaw"] += s * (v[2] if len(v) > 2 else 0)
        return a
    hl, ht, hturn = head
    return pose(root=body(lean=lean, tilt=tilt, turn=turn, dy=dy, dz=dz),
                head=body(lean=hl, tilt=ht, turn=hturn),
                ra=arm_("R", ra), la=arm_("L", la),
                rl=limb("R", swing=rl[0], out=rl[1]), ll=limb("L", swing=ll[0], out=ll[1]))


def only(p, joints):
    """Keep only some joints of a pose (the rest aren't keyed, so they layer over other tracks)."""
    out = {j: p[j] for j in joints if j in p}
    out["_only"] = True
    return out


# ---------------- planting --------------------------------------------------------------
def lowest(p):
    """Lowest point of a pose (standing root at y = 3, floor at 0). Legs count by the centre of their
    bottom face (the foot): R6 hips pivot at the leg's outer top edge, so a splayed leg dips an inner
    corner. Arms / torso / head may sink a hair into the floor (hands planted)."""
    w = fk(p)
    lo = min((w[lg] @ np.array([0, -1, 0, 1]))[1] for lg in ("Right Leg", "Left Leg"))
    for part in ("Right Arm", "Left Arm", "Torso", "Head"):
        for c in itertools.product(*[(-s / 2, s / 2) for s in SIZES[part]]):
            lo = min(lo, (w[part] @ np.array([*c, 1]))[1] + 0.15)
    return lo


def plant(p, floor=0.0):
    """Moves the body up or down so the pose's lowest point sits on the floor. Returns a new pose."""
    out = dict(p)
    x, y, z = out["RootJoint"]["offset"]
    out["RootJoint"] = dict(out["RootJoint"], offset=(x, y + floor - lowest(p), z))
    return out


def planted(keys, floor=0.0):
    """Plants every pose of a key list (ground moves: crouches really are low, nothing hovers)."""
    return [(t, plant(p, floor)) for t, p in keys]
