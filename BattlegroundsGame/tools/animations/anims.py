"""The movement animation set. Every keyframe is a full pose; all poses use Constant easing
(snap from pose to pose). Loops end with a copy of their first pose so the last pose holds
for its full beat before the loop wraps."""
from rig import pose, limb, body, mirror, fk
from aim import aimed

IDLE, MOVEMENT = 0, 1  # Enum.AnimationPriority tokens


def seq(name, priority, loop, keys, notes):
    return {"name": name, "priority": priority, "loop": loop, "keys": keys, "notes": notes}


def loop_keys(poses, step):
    keys = [(round(i * step, 4), p) for i, p in enumerate(poses)]
    keys.append((round(len(poses) * step, 4), poses[0]))
    return keys


# ---------------- Idle: empty-handed, arms at the sides ----------------------------------
# Both legs slide forward (a straight shift, no rotation), so the feet sit ahead of the torso.
IDLE_LEG_SHIFT = 0.2  # studs the whole legs move forward

def idle_leg(side, root_dy=0.0):
    leg = limb(side)
    leg["offset"] = (0, -root_dy, -IDLE_LEG_SHIFT)  # cancel the torso's breathing bob so feet stay planted
    return leg

idle_a = pose(root=body(), head=body(),
              ra=limb("R", out=3), la=limb("L", out=3),
              rl=idle_leg("R"), ll=idle_leg("L"))
idle_b = pose(root=body(dy=0.06, lean=-1), head=body(lean=-3),          # breath in: chest up, chin up
              ra=limb("R", out=6, swing=2), la=limb("L", out=6, swing=2),
              rl=idle_leg("R", 0.06), ll=idle_leg("L", 0.06))
idle_c = pose(root=body(dy=0.03), head=body(lean=-1),                   # half-way back down
              ra=limb("R", out=4, swing=1), la=limb("L", out=4, swing=1),
              rl=idle_leg("R", 0.03), ll=idle_leg("L", 0.03))
IDLE_ANIM = seq("Idle", IDLE, True,
                [(0.0, idle_a), (1.2, idle_b), (1.7, idle_c), (2.4, idle_a)],
                "Empty-handed. Arms at the sides with a stepped breath; legs shifted forward.")

def timed_loop(poses_and_holds):
    """[(pose, seconds held), ...] -> keyframes; the first pose is repeated at the end."""
    keys, t = [], 0.0
    for p, hold in poses_and_holds:
        keys.append((round(t, 4), p)); t += hold
    keys.append((round(t, 4), poses_and_holds[0][0]))
    return keys


def arm(side, swing=0, inward=0, out=0):
    """Arm kept against the torso: swings forward/back from the shoulder. inward: + swings the
    arm's plane across the front of the body (how the references pump their arms). out stays
    tiny on purpose; rolling an R6 arm outward opens a gap at the shoulder."""
    s = 1 if side == "R" else -1
    return {"pitch": swing, "roll": s * out, "yaw": s * inward, "offset": (0, 0, 0)}


def leg(side, swing=0, out=0):
    return limb(side, swing=swing, out=out)


# ---------------- Walk (the only walk cycle) ---------------------------------------------
# From the Die of Death gameplay video (civilian walk/run, 60fps frame-by-frame) and
# PursuerWalk: a new pose every ~0.1 s, 8 poses per cycle. The BACK leg peels up behind
# further than the front leg reaches forward. Arms swing from the shoulder, tight to the body.
# 8 poses x 0.1 s = 0.8 s cycle, authored for walk speed 14.
walk_contact = pose(root=body(lean=3, dy=-0.05), head=body(lean=-2),
                    ra=arm("R", swing=-30), la=arm("L", swing=32, inward=6),
                    rl=leg("R", swing=24), ll=leg("L", swing=-30))
walk_down = pose(root=body(lean=4, tilt=2, dy=-0.12), head=body(lean=-3, tilt=-2),
                 ra=arm("R", swing=-22), la=arm("L", swing=24, inward=4),
                 rl=leg("R", swing=14), ll=leg("L", swing=-36))                       # back leg peels up
walk_pass = pose(root=body(lean=3, tilt=3, dy=0.08), head=body(lean=-2, tilt=-3),
                 ra=arm("R", swing=-4), la=arm("L", swing=6),
                 rl=leg("R", swing=-6), ll=leg("L", swing=4))                         # legs together
walk_up = pose(root=body(lean=3, tilt=2, dy=0.1), head=body(lean=-2, tilt=-2),
               ra=arm("R", swing=16, inward=4), la=arm("L", swing=-14),
               rl=leg("R", swing=-20), ll=leg("L", swing=20))                         # left leg reaching
WALK_HALF = [walk_contact, walk_down, walk_pass, walk_up]
WALK = WALK_HALF + [mirror(p) for p in WALK_HALF]
WALK_ANIM = seq("WalkForward", MOVEMENT, True, loop_keys(WALK, 0.1),
                "8 poses, 0.8 s cycle. Body faces where you walk; the head follows the camera.")

# ---------------- Sprint ------------------------------------------------------------------
# Die of Death civilian run (video 0:26-0:28 and 4:26-4:28, side views, 60fps): pose every
# ~0.08 s, 8 per cycle (~0.65 s). At the stride both arms are near horizontal, one forward
# (crossing a little in front) and one back; the back leg kicks way up behind while the front
# leg only reaches a little; torso leans forward. Between strides a short passing pose: arms
# drop, legs gather under the body, body rises. Authored for run speed 26.
run_stride = pose(root=body(lean=16, tilt=-3, dy=-0.12), head=body(lean=-12, tilt=3),
                  ra=arm("R", swing=-75), la=arm("L", swing=88, inward=14),
                  rl=leg("R", swing=30), ll=leg("L", swing=-62))
run_kick = pose(root=body(lean=15, tilt=-2, dy=-0.03), head=body(lean=-11, tilt=2),
                ra=arm("R", swing=-62), la=arm("L", swing=74, inward=12),
                rl=leg("R", swing=18), ll=leg("L", swing=-72))                        # back leg kicks higher
run_pass = pose(root=body(lean=10, tilt=2, dy=0.14), head=body(lean=-8, tilt=-2),
                ra=arm("R", swing=-12), la=arm("L", swing=16),
                rl=leg("R", swing=-10), ll=leg("L", swing=6))                         # arms drop, legs gather
run_reach = pose(root=body(lean=13, tilt=3, dy=0.08), head=body(lean=-10, tilt=-3),
                 ra=arm("R", swing=34, inward=8), la=arm("L", swing=-30),
                 rl=leg("R", swing=-34), ll=leg("L", swing=26))                       # left leg reaching
RUN_HALF = [run_stride, run_kick, run_pass, run_reach]
SPRINT = RUN_HALF + [mirror(p) for p in RUN_HALF]
SPRINT_ANIM = seq("Sprint", MOVEMENT, True, loop_keys(SPRINT, 0.08),
                  "8 poses, 0.64 s cycle (Die of Death civilian run).")

# ---------------- Jump (one-shot) ---------------------------------------------------------
# A running leap in the same style as the run: the lead knee drives up, the other leg trails
# behind, and the OPPOSITE arm leads as the arms swing up (like the run). Four poses on the way up, then the last pose holds
# and is almost exactly the Fall pose, so the hand-off at the top of the jump doesn't pop.
jump_takeoff = pose(root=body(lean=8, dy=-0.04), head=body(lean=-6),
                    ra=arm("R", swing=-30), la=arm("L", swing=55, inward=6),
                    rl=leg("R", swing=55), ll=leg("L", swing=-34))
jump_rise = pose(root=body(lean=4, dy=0.04), head=body(lean=-7),
                 ra=arm("R", swing=40, inward=4), la=arm("L", swing=90, inward=6),
                 rl=leg("R", swing=46), ll=leg("L", swing=-38))
jump_rise2 = pose(root=body(lean=0, dy=0.06), head=body(lean=-5),
                  ra=arm("R", swing=86, out=8), la=arm("L", swing=108, out=8, inward=4),
                  rl=leg("R", swing=34), ll=leg("L", swing=-24))
jump_top = pose(root=body(lean=-3, dy=0.05), head=body(lean=2),
                ra=arm("R", swing=114, out=12), la=arm("L", swing=100, out=14),
                rl=leg("R", swing=20), ll=leg("L", swing=-8))
JUMP_ANIM = seq("Jump", MOVEMENT, False,
                [(0.0, jump_takeoff), (0.08, jump_rise), (0.16, jump_rise2), (0.26, jump_top), (0.4, jump_top)],
                "One-shot running leap, 4 poses; the last one matches the Fall pose.")

# ---------------- Fall (loop) -------------------------------------------------------------
# Calm, not a jittery flail: arms held up in front at shoulder-ish height and a little apart,
# legs hanging with one slightly forward, head tipped down toward the landing. Small changes
# between poses, held 0.2 s each, so it drifts instead of shaking. 4 poses, 0.8 s cycle.
fall_a = pose(root=body(lean=-4), head=body(lean=6),
              ra=arm("R", swing=115, out=14), la=arm("L", swing=100, out=16),
              rl=leg("R", swing=18), ll=leg("L", swing=-8, out=3))
fall_b = pose(root=body(lean=-5, dy=0.03), head=body(lean=7),
              ra=arm("R", swing=124, out=12), la=arm("L", swing=108, out=14),
              rl=leg("R", swing=12), ll=leg("L", swing=-2, out=3))
FALL_HALF = [fall_a, fall_b]
FALL_ANIM = seq("Fall", MOVEMENT, True, loop_keys(FALL_HALF + [mirror(p) for p in FALL_HALF], 0.2),
                "Calm 4-pose fall, 0.8 s cycle; starts from the Jump's last pose.")

# ---------------- Climb (trusses/ladders, loop) -------------------------------------------
# Die of Death has no climb. Facing the truss: hands grip in front of the face at different
# heights (not straight overhead), one knee comes up onto the next rung, then the body pulls
# up with the hands level. 6 poses x 0.12 s = 0.72 s cycle. Speed follows climb speed.
climb_reach = pose(root=body(lean=6, dy=-0.1), head=body(lean=-10),
                   ra=arm("R", swing=160, inward=10), la=arm("L", swing=100, inward=12),
                   rl=leg("R", swing=0), ll=leg("L", swing=55))
climb_step = pose(root=body(lean=6, dy=0.0), head=body(lean=-10),
                  ra=arm("R", swing=148, inward=10), la=arm("L", swing=112, inward=12),
                  rl=leg("R", swing=12), ll=leg("L", swing=40))
climb_pull = pose(root=body(lean=5, dy=0.12), head=body(lean=-9),
                  ra=arm("R", swing=132, inward=10), la=arm("L", swing=130, inward=10),
                  rl=leg("R", swing=28), ll=leg("L", swing=22))
CLIMB_HALF = [climb_reach, climb_step, climb_pull]
CLIMB_ANIM = seq("Climb", MOVEMENT, True, loop_keys(CLIMB_HALF + [mirror(p) for p in CLIMB_HALF], 0.12),
                 "Hand over hand, 6 poses, 0.72 s cycle. Speed follows climb speed; 0 freezes on the truss.")

ALL = [IDLE_ANIM, WALK_ANIM, SPRINT_ANIM, JUMP_ANIM, FALL_ANIM, CLIMB_ANIM]


# =========================================================================================
# DASHES (Action priority: they play over the movement animations and key every joint)
# Reference: Isaac's JJS parkour clip (Sep 26), stepped through frame by frame at 60 fps.
# Version 2 (Isaac: v1 looked goofy). What changed and why:
#   * Limbs are now authored by their angle in the WORLD (w_leg / w_arm below), not relative
#     to a leaning torso. v1's front leg reached far forward like a split; in the clip the
#     front leg stays planted UNDER the body and only the back leg stretches out behind.
#   * Every pose is planted: the lowest point of the body sits exactly on the floor, so the
#     crouches really are low instead of hovering or sinking.
#   * Fewer giant sideways arm rolls; arms follow what the clip shows (one arm leads, one
#     trails), not a T-pose.
#
#   Front dash (0:36.63-37.17, 3/4 back view): torso pitched ~50 deg, head up looking ahead;
#     the support leg is roughly vertical under the hips, the other leg is stretched straight
#     back almost flat along the ground; one arm swept back and out, the other hanging down in
#     front. Rises over the last ~0.15 s with the arm coming forward.
#   Quick-step (0:22.60-23.20, back view, moving left): crouch, then the body tips INTO the
#     slide (~30 deg), the lead arm reaches out toward the slide at shoulder height, the
#     trailing leg kicks out sideways nearly flat, the lead leg stays under the body. The
#     trailing leg comes back down over ~0.2 s and the legs gather.
#   Dash punch (0:49.4 front view, 0:55.9 back view): still in the lunge with the punching arm
#     cocked back and the torso twisted away, then a straight jab with the shoulder driven
#     forward, then a long endlag with both fists up in front of the face; one arm drops and
#     it recovers.
# =========================================================================================
ACTION = 2


def one_shot(poses_and_times, end):
    """[(time, pose), ...] -> keyframes; the last pose holds until `end`."""
    keys = [(round(t, 4), p) for t, p in poses_and_times]
    keys.append((round(end, 4), poses_and_times[-1][1]))
    return keys


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


def P(lean=0.0, tilt=0.0, turn=0.0, head_lean=None, head_tilt=None, head_turn=0.0,
      ra=(0, 0), la=(0, 0), rl=(0, 0), ll=(0, 0), ra_in=0.0, la_in=0.0):
    """A full pose from world limb angles. Each limb is (forward, outward) in world degrees.
    The head keeps looking level by default (it cancels the torso's lean/tilt)."""
    hl = -lean * 0.8 if head_lean is None else head_lean
    ht = -tilt * 0.7 if head_tilt is None else head_tilt
    return pose(root=body(lean=lean, tilt=tilt, turn=turn),
                head=body(lean=hl, tilt=ht, turn=head_turn),
                ra=w_arm("R", *ra, lean=lean, tilt=tilt, inward=ra_in),
                la=w_arm("L", *la, lean=lean, tilt=tilt, inward=la_in),
                rl=w_leg("R", *rl, lean=lean, tilt=tilt),
                ll=w_leg("L", *ll, lean=lean, tilt=tilt))


def _plant(anims, floor=-0.05):
    """Moves the body up or down so the lowest corner of every pose sits exactly on the floor
    (0 with the root at 3, like a standing R6): crouches are really low, nothing hovers or sinks."""
    import itertools
    import numpy as np
    from rig import fk, SIZES
    for a in anims:
        for _, p in a["keys"]:
            if p.get("_planted"):
                continue
            w = fk(p)
            lo = min((w[part] @ np.array([*c, 1]))[1]
                     for part in ["Right Leg", "Left Leg", "Right Arm", "Left Arm", "Torso", "Head"]
                     for c in itertools.product(*[(-s / 2, s / 2) for s in SIZES[part]]))
            x, y, z = p["RootJoint"]["offset"]
            p["RootJoint"] = dict(p["RootJoint"], offset=(x, y + (floor - lo), z))
            p["_planted"] = True



# Dash animations (front / side / back / dash punch) were REMOVED at Isaac's request (Sep 26).
# The dash code still plays DashForward / DashLeft / DashRight / DashBack / DashPunch if a
# KeyframeSequence with that name is added in Studio (or an ID in AnimationConfig.Ids).
DASH = []
