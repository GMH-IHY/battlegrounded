"""Advanced movement animations: parkour (wall run / wall hop / landing roll / vault / ledge climb /
slide) and the dash set (front / left / right / back / dash punch).

Style (Isaac): Constant easing (every pose snaps), exaggerated, start slow and end fast (a small
first move, then the big one, then a recoil). R6 has no knees / elbows, so bends happen at the hips
and shoulders, and the BODY itself moves (drops, rises) instead of only angling limbs.

Poses are {joint: authored dict} and may key only SOME joints. The Slide never keys RootJoint:
AutoParkour already leans the torso back 70 deg and drops it 1.7 through RootJoint.C0, so the
animation only places the limbs and head on top of that.

Timings come from the code / MovementConfig:
  DashForward 0.45 s, DashLeft / DashRight / DashBack 0.34 s (played at speed 1).
  DashPunch: wind-up 0.16, hitbox 0.1, endlag 0.55 = 0.81 s.
  WallRun: loop while running (WallRunTime 0.22). WallHop: one-shot at the kick, ends in the Fall pose.
  LandingRoll: stretched by the code to the roll time (0.45 s).
  Vault (+ step-up): ~0.28 s. LedgeClimb: ~0.48 s (last pose holds). Slide: loop (0.35 - 2.5 s).
"""
import numpy as np
from rig import limb, body, pose, mirror, fk, SIZES
from anims import P, seq, one_shot, ACTION

R6 = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
NO_ROOT = R6[1:]


def T(lean=0.0, tilt=0.0, turn=0.0, dy=0.0, dz=0.0, head=(0, 0, 0),
      ra=(0, 0, 0), la=(0, 0, 0), rl=(0, 0), ll=(0, 0)):
    """Pose with limbs relative to the TORSO (not the world): (swing, out[, inward]).
    swing + = forward from hanging along the torso, out + = away from the body."""
    def arm(side, v):
        s = 1 if side == "R" else -1
        a = limb(side, swing=v[0], out=v[1])
        a["yaw"] += s * (v[2] if len(v) > 2 else 0)
        return a
    hl, ht, hturn = head
    return pose(root=body(lean=lean, tilt=tilt, turn=turn, dy=dy, dz=dz),
                head=body(lean=hl, tilt=ht, turn=hturn),
                ra=arm("R", ra), la=arm("L", la),
                rl=limb("R", swing=rl[0], out=rl[1]), ll=limb("L", swing=ll[0], out=ll[1]))


def only(p, joints):
    """Keep only some joints of a pose (the rest aren't keyed by the track)."""
    out = {j: p[j] for j in joints}
    out["_only"] = True
    return out


def _lowest(p):
    """Lowest point of a pose. Legs count by the CENTRE of their bottom face (the foot), not their
    corners: R6 hips pivot at the leg's outer top edge, so a splayed leg dips its inner corner and
    corner-planting pushed the whole body UP (why the old dash crouches looked tall)."""
    import itertools
    w = fk(p)
    lo = min((w[leg] @ np.array([0, -1, 0, 1]))[1] for leg in ("Right Leg", "Left Leg"))
    for part in ("Right Arm", "Left Arm", "Torso", "Head"):
        for c in itertools.product(*[(-s / 2, s / 2) for s in SIZES[part]]):
            lo = min(lo, (w[part] @ np.array([*c, 1]))[1] + 0.15)  # arms/body may sink a hair
    return lo


def planted(keys, floor=0.0):
    """Moves each pose's body up/down so its lowest point sits on the floor (ground moves)."""
    for _, p in keys:
        x, y, z = p["RootJoint"]["offset"]
        p["RootJoint"] = dict(p["RootJoint"], offset=(x, y + floor - _lowest(p), z))
    return keys


# =================================================================================================
# LANDING ROLL: forward roll over the shoulder-line, 0.45 s (the code stretches it to the roll).
# Touch down in a crouch, hands go to the floor, the body tucks and turns a full circle low to
# the ground, feet come back under, rise into a run. Every pose sits on the floor.
# =================================================================================================
TUCK = dict(ra=(95, 10, 25), la=(95, 10, 25), rl=(105, 8), ll=(100, 8))
roll_keys = planted([
    (0.00, T(lean=30, head=(-10, 0, 0), ra=(50, 12), la=(45, 12), rl=(55, 6), ll=(20, 6))),        # touchdown crouch
    (0.04, T(lean=70, head=(25, 0, 0), ra=(75, 12), la=(75, 12), rl=(80, 6), ll=(40, 6))),          # hands to the floor
    (0.10, T(lean=140, head=(40, 0, 0), **TUCK)),                                                   # tuck, over the head
    (0.16, T(lean=210, head=(40, 0, 0), **TUCK)),
    (0.22, T(lean=275, head=(35, 0, 0), ra=(80, 12, 20), la=(80, 12, 20), rl=(110, 8), ll=(95, 8))),
    (0.29, T(lean=330, head=(20, 0, 0), ra=(60, 14), la=(55, 14), rl=(75, 6), ll=(45, 6))),          # feet back under
    (0.36, T(lean=18, head=(-8, 0, 0), ra=(-30, 4), la=(45, 4, 10), rl=(30, 3), ll=(-25, 3))),     # up into a run
])
LANDING_ROLL = seq("LandingRoll", ACTION, False, one_shot(roll_keys, 0.45),
                   "Crouch on touchdown, hands to the floor, tucked full turn low to the ground, "
                   "feet back under, up into a run.")


# =================================================================================================
# VAULT (also the step-up), ~0.28 s, in the air over the obstacle (the code moves the body).
# Speed vault: left hand plants on the top, the body tips over it and both legs swing over to the
# right side, then come down in front into a running landing.
# =================================================================================================
vault_keys = [
    (0.00, T(lean=22, head=(-14, 0, 0), ra=(-35, 6), la=(55, 8, 10), rl=(45, 4), ll=(-30, 4))),     # last step, hand reaches
    (0.04, T(lean=25, tilt=-28, head=(-12, 22, 0), ra=(40, 95), la=(62, 4, 8),                      # hand plants, legs whip up right
             rl=(60, 55), ll=(55, 40))),
    (0.11, T(lean=18, tilt=-38, head=(-8, 30, 0), ra=(60, 110), la=(35, 14),                        # over the top: legs level to the right
             rl=(85, 45), ll=(80, 35))),
    (0.19, T(lean=8, tilt=-14, head=(-4, 12, 0), ra=(55, 70), la=(-25, 18),                         # legs swing down in front, hand pushes off
             rl=(40, 14), ll=(20, 8))),
    (0.27, T(lean=16, dy=-0.2, head=(-12, 0, 0), ra=(-40, 8), la=(50, 6, 10), rl=(35, 3), ll=(-30, 3))),  # land running
]
VAULT = seq("Vault", ACTION, False, one_shot(vault_keys, 0.36),
            "Speed vault: left hand plants, legs swing over to the right side level with the top, "
            "then down in front into a running landing.")


# =================================================================================================
# LEDGE CLIMB, ~0.48 s (the code raises the body up the face, then over the top).
# Both hands slap the ledge, pull the chest up to them, right knee comes up onto the top, push
# down with both arms, step up into a run.
# =================================================================================================
climb_keys = [
    (0.00, T(lean=4, head=(-18, 0, 0), ra=(165, 10), la=(150, 10), rl=(35, 3), ll=(-8, 3))),         # reach up
    (0.05, T(lean=6, dy=-0.15, head=(-20, 0, 0), ra=(172, 8), la=(172, 8), rl=(15, 3), ll=(40, 3))),  # hands grab, foot on the wall
    (0.14, T(lean=18, head=(-12, 0, 0), ra=(115, 10), la=(115, 10), rl=(55, 3), ll=(25, 3))),        # pull chest to the hands
    (0.24, T(lean=34, head=(-24, 0, 0), ra=(35, 16), la=(35, 16), rl=(95, 4), ll=(-15, 3))),        # knee onto the top, arms push
    (0.33, T(lean=36, head=(-26, 0, 0), ra=(-15, 14), la=(-15, 14), rl=(70, 4), ll=(-45, 3))),      # arms locked down, lift out
    (0.42, T(lean=14, head=(-10, 0, 0), ra=(-35, 5), la=(45, 5, 10), rl=(30, 3), ll=(-25, 3))),     # step up into a run
]
LEDGE_CLIMB = seq("LedgeClimb", ACTION, False, one_shot(climb_keys, 0.55),
                  "Hands slap the ledge, pull the chest up, knee onto the top, both arms push down, "
                  "step up into a run.")


# =================================================================================================
# SLIDE (loop). RootJoint is NOT keyed: the code already leans the torso back 70 and drops it.
# Relative to that leaned torso: right leg straight out in front along the floor, left leg
# raised a little, right hand dragging on the floor behind, left arm up in front for balance,
# head tipped forward to look where you're going.
# =================================================================================================
def slide_pose(drag):
    return only(T(head=(52, 0, 0), ra=(-112 + drag, 22), la=(30 + drag, 28, 10),
                  rl=(9, 6), ll=(24 + drag * 0.5, 16)), NO_ROOT)

SLIDE = seq("Slide", ACTION, True,
            [(0.0, slide_pose(0)), (0.12, slide_pose(5)), (0.24, slide_pose(0))],
            "Leaning back (the code does the lean): right leg out along the floor, left leg up a bit, "
            "right hand drags behind, left arm up front; small chatter. Keys only the limbs and head.")


# =================================================================================================
# WALL RUN (loop while on the wall, 0.24 s cycle). WallRunRight = wall on your RIGHT.
# v2 (Isaac: "wall run animation on the legs could be better"): world-angle poses (P) so the legs
# really point DOWN INTO THE WALL (both feet toward it; v1 had the left leg splaying away), with a
# full stride: knee-up (leg swung high in front) / drive (other leg pushed far behind), the body
# bobbing between strides, and both arms pumping opposite the legs.
# =================================================================================================
WR_TILT, WR_LEAN = -30, 12   # top of the body away from the wall, a little forward

def wallrun(rl, ll, ra, la, dy):
    p = P(lean=WR_LEAN, tilt=WR_TILT, head_lean=-6, head_tilt=20,
          rl=rl, ll=ll, ra=ra, la=la, la_in=8)
    p["RootJoint"]["offset"] = (0, dy, 0)
    return p

# legs: (forward, outward) in world degrees; toward the wall = +out for the right leg, -out for the left
wr_a = wallrun(rl=(72, 44), ll=(-48, -30), ra=(-50, 38), la=(72, 18), dy=-0.12)  # right knee up, left drives
wr_b = wallrun(rl=(18, 46), ll=(-8, -34), ra=(-5, 26), la=(22, 16), dy=0.14)     # passing, body up
wr_c = wallrun(rl=(-48, 46), ll=(72, -30), ra=(70, 40), la=(-48, 14), dy=-0.12)  # left knee up, right drives
wr_d = wallrun(rl=(-8, 46), ll=(18, -34), ra=(20, 28), la=(-5, 16), dy=0.14)
WALL_RUN_RIGHT = seq("WallRunRight", ACTION, True,
                     [(0.0, wr_a), (0.06, wr_b), (0.12, wr_c), (0.18, wr_d), (0.24, wr_a)],
                     "Wall on the right: tilted away from it, both feet driving into it with a full "
                     "knee-up stride, body bobbing, arms pumping.")
WALL_RUN_LEFT = seq("WallRunLeft", ACTION, True,
                    [(t, mirror(p)) for t, p in WALL_RUN_RIGHT["keys"]],
                    "Mirror of WallRunRight (wall on the left).")


# =================================================================================================
# WALL HOP (one-shot at the kick). WallHopRight = kicking off a wall on your RIGHT.
# v2 (Isaac: "the kick off the wall being more impactful"): a short LOAD (both knees tucked
# against the wall, body low), then a snap to FULL EXTENSION held for a beat (the impact frame):
# the wall leg shot out straight and nearly flat into the wall, the body thrown away from it, the
# far arm flung up over the head, the near arm whipped down and back. Then a tuck and the Fall pose.
# =================================================================================================
hop_keys = [
    (0.000, P(lean=20, tilt=-10, head_lean=-10, head_tilt=10,                                      # load against the wall
              rl=(58, 42), ll=(52, -12), ra=(30, 62), la=(35, 28), la_in=10)),
    (0.035, P(lean=4, tilt=-40, head_lean=-4, head_tilt=30,                                        # KICK: full extension
              rl=(-12, 78), ll=(14, -6), ra=(-45, 26), la=(18, 150))),
    (0.120, P(lean=2, tilt=-44, head_lean=-2, head_tilt=32,                                        # impact frame, a hair further
              rl=(-16, 84), ll=(18, -4), ra=(-50, 30), la=(20, 158))),
    (0.180, T(lean=8, tilt=-12, head=(-8, 8, 0), ra=(120, 34), la=(140, 44), rl=(80, 12), ll=(70, 8))),  # tuck
    (0.260, T(lean=-4, head=(6, 0, 0), ra=(115, 14), la=(100, 16), rl=(18, 0), ll=(-8, 3))),         # = Fall pose
]
WALL_HOP_RIGHT = seq("WallHopRight", ACTION, False, one_shot(hop_keys, 0.36),
                     "Wall on the right: load against it, snap to full extension (right leg shot into "
                     "the wall, body thrown away, left arm flung overhead) held a beat, tuck, Fall pose.")
WALL_HOP_LEFT = seq("WallHopLeft", ACTION, False, [(t, mirror(p)) for t, p in WALL_HOP_RIGHT["keys"]],
                    "Mirror of WallHopRight (wall on the left).")


# =================================================================================================
# DASHES (Action priority, every joint keyed). Clip notes in anims.py (JJS, stepped at 60 fps).
# Front / back are authored in the side plane only, side dashes in the front plane only (no mixing
# of lean + tilt + turn: that's what pushed limbs toward the camera in the old attempts). The body
# drops by SPLITTING the legs (no knees), and every pose is planted on the floor.
# =================================================================================================
# FRONT, 0.45 s: small dip, then the lunge: torso pitched ~50, front leg angled forward under the
# body, back leg stretched far behind, one arm swept back and out, the other hanging in front.
# Rises over the last ~0.15 s with the arm coming forward.
front_keys = planted([
    (0.00, P(lean=18, ra=(-15, 6), la=(20, 6), rl=(18, 2), ll=(-18, 2))),                          # dip
    (0.04, P(lean=50, ra=(-70, 28), la=(18, 6), rl=(42, 3), ll=(-68, 3))),                         # lunge
    (0.14, P(lean=54, ra=(-78, 32), la=(22, 6), rl=(46, 3), ll=(-72, 3))),                         # deeper, holds
    (0.30, P(lean=30, ra=(-20, 12), la=(30, 6), rl=(28, 2), ll=(-40, 2))),                         # rising, arm comes forward
    (0.38, P(lean=15, ra=(25, 6), la=(-20, 6), rl=(20, 2), ll=(-22, 2))),                          # run-ready
])
DASH_FORWARD = seq("DashForward", ACTION, False, one_shot(front_keys, 0.45),
                   "Dip, then a low lunge: torso pitched ~50, back leg stretched far behind, right arm "
                   "swept back and out, left hangs in front; rises with the arm coming forward.")

# SIDE (moving LEFT), 0.34 s. v2 (Isaac: "right arm is wonky, the legs separate and splay the body
# out like a star, with the left arm just kind of hanging there"): a compact low side-step instead of
# a star. The legs stay under the body in a boxer's scissor (one forward, one back) and only open a
# little to the side, which is what drops the hips. The body tips into the step. BOTH arms work:
# the lead (left) arm reaches forward-out toward where you're going, the trailing (right) arm
# counter-swings back, close to the body.
left_keys = planted([
    (0.00, P(lean=14, tilt=-5, rl=(-8, 10), ll=(12, 10), ra=(12, 10), la=(20, 14))),               # small dip
    (0.03, P(lean=20, tilt=-14, rl=(-24, 24), ll=(26, 20), ra=(-42, 20), la=(55, 38), la_in=6)),     # push off the right foot
    (0.12, P(lean=22, tilt=-16, rl=(-28, 26), ll=(30, 22), ra=(-44, 20), la=(66, 36), la_in=6)),     # glide, lowest
    (0.22, P(lean=12, tilt=-7, rl=(-12, 12), ll=(14, 12), ra=(-18, 12), la=(30, 20))),              # legs gather
    (0.29, P(lean=6, tilt=-2, rl=(-4, 4), ll=(6, 4), ra=(-6, 6), la=(10, 8))),                      # settle
])
DASH_LEFT = seq("DashLeft", ACTION, False, one_shot(left_keys, 0.34),
                "Quick-step left: low compact side-step, legs scissored under the body (no star), body "
                "tips into it, left arm reaches ahead, right arm counter-swings back; legs gather.")
DASH_RIGHT = seq("DashRight", ACTION, False, [(t, mirror(p)) for t, p in DASH_LEFT["keys"]],
                 "Mirror of DashLeft.")

# BACK, 0.34 s. v2: hop backward off the front (left) foot. The right leg reaches back to lead
# the step, the left stays forward under you; the body stays over the feet (small forward lean).
# The arms counter-balance instead of mirroring each other: the left arm swings forward and up,
# the right arm drops back beside the hip. Then the legs gather.
back_keys = planted([
    (0.00, P(lean=10, rl=(8, 4), ll=(-4, 4), ra=(8, 8), la=(12, 8))),                                # small dip
    (0.03, P(lean=16, rl=(-36, 8), ll=(30, 6), ra=(-30, 16), la=(68, 14), la_in=10)),               # push off, right leg reaches back
    (0.12, P(lean=18, rl=(-40, 8), ll=(34, 6), ra=(-34, 18), la=(74, 16), la_in=10)),               # glide
    (0.22, P(lean=10, rl=(-14, 4), ll=(14, 4), ra=(-12, 10), la=(32, 10))),                         # legs gather
    (0.29, P(lean=5, rl=(-4, 3), ll=(4, 3), ra=(-4, 5), la=(10, 6))),                               # settle
])
DASH_BACK = seq("DashBack", ACTION, False, one_shot(back_keys, 0.34),
                "Back-step: right leg reaches back and leads, left foot stays under, body over the feet; "
                "left arm swings forward, right arm drops back; legs gather.")

# DASH PUNCH, 0.81 s (wind-up 0.16, hit 0.16-0.26, endlag to 0.81). Torso-relative limbs so the
# twist (turn) doesn't swing the arms in the world. Still in the lunge, right arm cocks back with
# the torso twisted away; straight jab with the right shoulder driven forward; endlag with both fists
# up in front of the face; one arm drops, recover.
LUNGE_LEGS = dict(rl=(-8, 3), ll=(72, 3))  # left leg forward, right leg behind (torso leaned ~40)
punch_keys = planted([
    (0.00, T(lean=40, turn=22, head=(-30, 0, -18), ra=(-30, 14), la=(95, 8, 22), **LUNGE_LEGS)),      # cocks back
    (0.08, T(lean=42, turn=34, head=(-32, 0, -28), ra=(-55, 18), la=(100, 8, 26), **LUNGE_LEGS)),     # further (slow start)
    (0.16, T(lean=46, turn=-32, head=(-34, 0, 26), ra=(136, 2, 6), la=(40, 6, 30),                    # JAB
             rl=(-20, 3), ll=(80, 3))),
    (0.26, T(lean=44, turn=-28, head=(-32, 0, 22), ra=(132, 4, 6), la=(45, 6, 30), rl=(-18, 3), ll=(78, 3))),
    (0.32, T(lean=14, head=(-10, 0, 0), ra=(150, 6, 28), la=(142, 6, 30), rl=(-8, 3), ll=(35, 3))),    # fists up by the face
    (0.55, T(lean=12, head=(-8, 0, 0), ra=(146, 6, 28), la=(30, 6, 10), rl=(-6, 3), ll=(30, 3))),      # left arm drops
    (0.70, T(lean=8, head=(-5, 0, 0), ra=(20, 5), la=(10, 5), rl=(0, 2), ll=(14, 2))),                  # recover
])
DASH_PUNCH = seq("DashPunch", ACTION, False, one_shot(punch_keys, 0.81),
                 "Right arm cocks back with the torso twisted away, then a straight jab with the shoulder "
                 "driven forward; endlag with both fists up by the face, left arm drops, recover.")

PARKOUR = [LANDING_ROLL, VAULT, LEDGE_CLIMB, SLIDE, WALL_RUN_RIGHT, WALL_RUN_LEFT, WALL_HOP_RIGHT, WALL_HOP_LEFT]
DASHES = [DASH_FORWARD, DASH_LEFT, DASH_RIGHT, DASH_BACK, DASH_PUNCH]
ALL_NEW = PARKOUR + DASHES
