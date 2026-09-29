"""Action animations: dashes (front / left / right / back / dash punch) and parkour (landing roll,
vault, ledge climb, slide, wall run, wall hop). Action priority: they play over locomotion.

The key poses are the approved v2 designs (Isaac's JJS parkour clip, stepped through at 60 fps);
this version adds in-betweens so every move starts with a small anticipation step and ends with
a settle, and no joint jumps more than ~75 deg between two poses except marked impact frames.

Durations come from the code / MovementConfig and must stay as they are:
  DashForward 0.45 s, DashLeft / DashRight / DashBack 0.34 s (played at speed 1).
  DashPunch 0.81 s: wind-up 0.16 (the jab lands at 0.16), hitbox 0.1, endlag 0.55.
  LandingRoll: stretched by the code to the roll time (0.45 s).
  Vault (+ step-up) 0.36 s, LedgeClimb 0.55 s, Slide loop, WallRun loop 0.24 s, WallHop 0.36 s.
"""
from poses import P, T, seq, only, planted, mirror_keys, NO_ROOT, ACTION
from timing import timeline, tween, ONE, SLOW_IN, SLOW_OUT, EVEN


def check_length(keys, want, name):
    got = keys[-1][0]
    assert abs(got - want) < 1e-6, f"{name} lasts {got:.3f}s, the code expects {want:.3f}s"
    return keys


# =================================================================================================
# LANDING ROLL, 0.45 s (the code stretches it to the roll). Touch down in a crouch, hands to the
# floor, tuck and turn a full circle low to the ground, feet back under, rise into a run.
# =================================================================================================
TUCK = dict(ra=(95, 10, 25), la=(95, 10, 25), rl=(105, 8), ll=(100, 8))
roll_touch = T(lean=30, head=(-10, 0, 0), ra=(50, 12), la=(45, 12), rl=(55, 6), ll=(20, 6))
roll_hands = T(lean=70, head=(25, 0, 0), ra=(75, 12), la=(75, 12), rl=(80, 6), ll=(40, 6))
roll_over = T(lean=140, head=(40, 0, 0), **TUCK)
roll_over2 = T(lean=210, head=(40, 0, 0), **TUCK)
roll_back = T(lean=275, head=(35, 0, 0), ra=(80, 12, 20), la=(80, 12, 20), rl=(110, 8), ll=(95, 8))
roll_feet = T(lean=330, head=(20, 0, 0), ra=(60, 14), la=(55, 14), rl=(75, 6), ll=(45, 6))
roll_up = T(lean=378, head=(-8, 0, 0), ra=(-30, 4), la=(45, 4, 10), rl=(30, 3), ll=(-25, 3))
roll_run = T(lean=376, head=(-6, 0, 0), ra=(-24, 4), la=(36, 4, 8), rl=(22, 3), ll=(-18, 3))
roll_keys = check_length(planted(timeline([
    (roll_touch, 0.03),
    *tween(roll_touch, roll_hands, ONE, 0.02),
    (roll_hands, 0.04),
    *tween(roll_hands, roll_over, ONE, 0.025),
    (roll_over, 0.05),
    (roll_over2, 0.06),
    (roll_back, 0.065),
    (roll_feet, 0.04),
    *tween(roll_feet, roll_up, ONE, 0.03),
    (roll_up, 0.04),
    *tween(roll_up, roll_run, ONE, 0.03),
    (roll_run, 0.02),
])), 0.45, "LandingRoll")
LANDING_ROLL = seq("LandingRoll", ACTION, False, roll_keys,
                   "Crouch on touchdown, hands to the floor, tucked full turn low to the ground, "
                   "feet back under, up into a run.")


# =================================================================================================
# VAULT (also the step-up), 0.36 s, in the air over the obstacle (the code moves the body).
# Speed vault: left hand plants on the top, the legs swing over to the right side level with the
# top, then come down in front into a running landing.
# =================================================================================================
vault_reach = T(lean=22, head=(-14, 0, 0), ra=(-35, 6), la=(55, 8, 10), rl=(45, 4), ll=(-30, 4))
vault_plant = T(lean=25, tilt=-28, head=(-12, 22, 0), ra=(40, 95), la=(62, 4, 8), rl=(60, 55), ll=(55, 40))
vault_over = T(lean=18, tilt=-38, head=(-8, 30, 0), ra=(60, 110), la=(35, 14), rl=(85, 45), ll=(80, 35))
vault_down = T(lean=8, tilt=-14, head=(-4, 12, 0), ra=(55, 70), la=(-25, 18), rl=(40, 14), ll=(20, 8))
vault_land = T(lean=16, dy=-0.2, head=(-12, 0, 0), ra=(-40, 8), la=(50, 6, 10), rl=(35, 3), ll=(-30, 3))
vault_run = T(lean=14, dy=-0.08, head=(-10, 0, 0), ra=(-30, 6), la=(38, 6, 8), rl=(26, 3), ll=(-22, 3))
vault_keys = check_length(timeline([
    (vault_reach, 0.02),
    *tween(vault_reach, vault_plant, SLOW_IN, 0.017),
    (vault_plant, 0.05),
    *tween(vault_plant, vault_over, ONE, 0.02),
    (vault_over, 0.056),
    *tween(vault_over, vault_down, ONE, 0.03),
    (vault_down, 0.04),
    *tween(vault_down, vault_land, ONE, 0.03),
    (vault_land, 0.04),
    *tween(vault_land, vault_run, ONE, 0.02),
    (vault_run, 0.02),
]), 0.36, "Vault")
VAULT = seq("Vault", ACTION, False, vault_keys,
            "Speed vault: left hand plants, legs swing over to the right side level with the top, "
            "then down in front into a running landing.")


# =================================================================================================
# LEDGE CLIMB, 0.55 s (the code raises the body up the face, then over the top).
# Both hands slap the ledge, pull the chest up to them, right knee onto the top, push down with
# both arms, step up into a run.
# =================================================================================================
lc_reach = T(lean=4, head=(-18, 0, 0), ra=(150, 10), la=(135, 10), rl=(30, 3), ll=(-6, 3))
lc_grab = T(lean=6, dy=-0.15, head=(-20, 0, 0), ra=(172, 8), la=(172, 8), rl=(15, 3), ll=(40, 3))
lc_pull = T(lean=18, head=(-12, 0, 0), ra=(115, 10), la=(115, 10), rl=(55, 3), ll=(25, 3))
lc_knee = T(lean=34, head=(-24, 0, 0), ra=(35, 16), la=(35, 16), rl=(95, 4), ll=(-15, 3))
lc_lock = T(lean=36, head=(-26, 0, 0), ra=(-15, 14), la=(-15, 14), rl=(70, 4), ll=(-45, 3))
lc_step = T(lean=14, head=(-10, 0, 0), ra=(-35, 5), la=(45, 5, 10), rl=(30, 3), ll=(-25, 3))
lc_run = T(lean=12, head=(-8, 0, 0), ra=(-26, 5), la=(34, 5, 8), rl=(22, 3), ll=(-18, 3))
climb_keys = check_length(timeline([
    (lc_reach, 0.03),
    *tween(lc_reach, lc_grab, ONE, 0.02),
    (lc_grab, 0.05),
    *tween(lc_grab, lc_pull, ONE, 0.04),
    (lc_pull, 0.05),
    *tween(lc_pull, lc_knee, ONE, 0.04),
    (lc_knee, 0.05),
    *tween(lc_knee, lc_lock, ONE, 0.03),
    (lc_lock, 0.05),
    *tween(lc_lock, lc_step, EVEN, 0.03),
    (lc_step, 0.05),
    *tween(lc_step, lc_run, ONE, 0.04),
    (lc_run, 0.04),
]), 0.55, "LedgeClimb")
LEDGE_CLIMB = seq("LedgeClimb", ACTION, False, climb_keys,
                  "Hands slap the ledge, pull the chest up, knee onto the top, both arms push down, "
                  "step up into a run.")


# =================================================================================================
# SLIDE (loop). RootJoint is NOT keyed: AutoParkour leans the torso back 70 and drops it 1.7
# through RootJoint.C0. Relative to that leaned torso: right leg straight out along the floor,
# left leg raised a little, right hand dragging behind, left arm up in front, head tipped forward.
# =================================================================================================
def slide_pose(drag):
    return only(T(head=(52, 0, 0), ra=(-112 + drag, 22), la=(30 + drag, 28, 10),
                  rl=(9, 6), ll=(24 + drag * 0.5, 16)), NO_ROOT)


SLIDE = seq("Slide", ACTION, True, timeline([
    (slide_pose(0), 0.08),
    (slide_pose(3), 0.06),
    (slide_pose(6), 0.08),
    (slide_pose(3), 0.06),
], loop=True), "Leaning back (the code does the lean): right leg out along the floor, left leg up a bit, "
    "right hand drags behind, left arm up front; stepped chatter. Keys only the limbs and head.")


# =================================================================================================
# WALL RUN (loop while on the wall, 0.24 s cycle). WallRunRight = wall on your RIGHT.
# World-angle poses so both feet point down into the wall, with a full knee-up / drive stride,
# the body bobbing between strides and both arms pumping opposite the legs. At this speed the
# stride snaps are the style (4 poses in 0.24 s).
# =================================================================================================
WR_TILT, WR_LEAN = -30, 12   # top of the body away from the wall, a little forward


def wallrun(rl, ll, ra, la, dy):
    return P(lean=WR_LEAN, tilt=WR_TILT, head_lean=-6, head_tilt=20, dy=dy,
             rl=rl, ll=ll, ra=ra, la=la, la_in=8)


wr_a = wallrun(rl=(72, 44), ll=(-48, -30), ra=(-50, 38), la=(72, 18), dy=-0.12)  # right knee up, left drives
wr_b = wallrun(rl=(18, 46), ll=(-8, -34), ra=(-5, 26), la=(22, 16), dy=0.14)     # passing, body up
wr_c = wallrun(rl=(-48, 46), ll=(72, -30), ra=(70, 40), la=(-48, 14), dy=-0.12)  # left knee up, right drives
wr_d = wallrun(rl=(-8, 46), ll=(18, -34), ra=(20, 28), la=(-5, 16), dy=0.14)
WALL_RUN_RIGHT = seq("WallRunRight", ACTION, True, timeline([
    (wr_a, 0.06), (wr_b, 0.06), (wr_c, 0.06), (wr_d, 0.06),
], loop=True), "Wall on the right: tilted away from it, both feet driving into it with a full knee-up "
    "stride, body bobbing, arms pumping.", snaps=(1, 2, 3, 4))
WALL_RUN_LEFT = seq("WallRunLeft", ACTION, True, mirror_keys(WALL_RUN_RIGHT["keys"]),
                    "Mirror of WallRunRight (wall on the left).", snaps=(1, 2, 3, 4))


# =================================================================================================
# WALL HOP (one-shot at the kick, 0.36 s). WallHopRight = kicking off a wall on your RIGHT.
# A short LOAD (knees tucked against the wall, body low), then a snap to FULL EXTENSION held for a
# beat (the impact frame): the wall leg shot out nearly flat into the wall, the body thrown away,
# the far arm flung up. Then a tuck, easing into the Fall pose.
# =================================================================================================
hop_preload = P(lean=14, tilt=-6, head_lean=-8, head_tilt=6, rl=(40, 30), ll=(36, -8), ra=(18, 44), la=(24, 20), la_in=6)
hop_load = P(lean=20, tilt=-10, head_lean=-10, head_tilt=10, rl=(58, 42), ll=(52, -12), ra=(30, 62), la=(35, 28), la_in=10)
hop_kick = P(lean=4, tilt=-40, head_lean=-4, head_tilt=30, rl=(-12, 78), ll=(14, -6), ra=(-45, 26), la=(18, 150))
hop_impact = P(lean=2, tilt=-44, head_lean=-2, head_tilt=32, rl=(-16, 84), ll=(18, -4), ra=(-50, 30), la=(20, 158))
hop_tuck = T(lean=8, tilt=-12, head=(-8, 8, 0), ra=(120, 34), la=(140, 44), rl=(80, 12), ll=(70, 8))
hop_fall = T(lean=-4, head=(6, 0, 0), ra=(115, 14), la=(100, 16), rl=(18, 0), ll=(-8, 3))
hop_keys = check_length(timeline([
    (hop_preload, 0.017),
    (hop_load, 0.02),
    (hop_kick, 0.085),                                # KICK: snap to full extension
    (hop_impact, 0.048),
    *tween(hop_impact, hop_tuck, EVEN, 0.02),
    (hop_tuck, 0.05),
    *tween(hop_tuck, hop_fall, SLOW_OUT, 0.03),
    (hop_fall, 0.04),
]), 0.36, "WallHop")
WALL_HOP_RIGHT = seq("WallHopRight", ACTION, False, hop_keys,
                     "Wall on the right: load against it, snap to full extension (right leg shot into the "
                     "wall, body thrown away, left arm flung overhead) held a beat, tuck, ease into Fall.",
                     snaps=(2,))
WALL_HOP_LEFT = seq("WallHopLeft", ACTION, False, mirror_keys(hop_keys),
                    "Mirror of WallHopRight (wall on the left).", snaps=(2,))


# =================================================================================================
# DASHES (Action priority, every joint keyed, every pose planted on the floor).
# Front / back are authored in the side plane only, side dashes in the front plane only. The body
# drops by SPLITTING the legs (no knees).
# =================================================================================================
# FRONT, 0.45 s: small dip, then the lunge: torso pitched ~50, front leg angled forward under the
# body, back leg stretched far behind, one arm swept back and out, the other hanging in front.
# Rises over the last ~0.15 s with the arm coming forward, settling run-ready.
fd_dip = P(lean=18, ra=(-15, 6), la=(20, 6), rl=(18, 2), ll=(-18, 2))
fd_lunge = P(lean=50, ra=(-70, 28), la=(18, 6), rl=(42, 3), ll=(-68, 3))
fd_deep = P(lean=54, ra=(-78, 32), la=(22, 6), rl=(46, 3), ll=(-72, 3))
fd_rise = P(lean=30, ra=(-20, 12), la=(30, 6), rl=(28, 2), ll=(-40, 2))
fd_ready = P(lean=15, ra=(25, 6), la=(-20, 6), rl=(20, 2), ll=(-22, 2))
fd_keys = check_length(planted(timeline([
    (fd_dip, 0.025),
    *tween(fd_dip, fd_lunge, SLOW_IN, 0.017),
    (fd_lunge, 0.086),
    (fd_deep, 0.12),
    *tween(fd_deep, fd_rise, EVEN, 0.035),
    (fd_rise, 0.04),
    *tween(fd_rise, fd_ready, ONE, 0.03),
    (fd_ready, 0.045),
])), 0.45, "DashForward")
DASH_FORWARD = seq("DashForward", ACTION, False, fd_keys,
                   "Dip, then a low lunge: torso pitched ~50, back leg stretched far behind, right arm "
                   "swept back and out; rises with the arm coming forward, settles run-ready.", ground=True)

# SIDE (moving LEFT), 0.34 s: a compact low side-step. The legs stay under the body in a boxer's
# scissor and only open a little to the side, which drops the hips. The body tips into the step.
# The lead (left) arm reaches out toward where you're going, the trailing arm counter-swings back.
sd_dip = P(lean=14, tilt=-5, rl=(-8, 10), ll=(12, 10), ra=(12, 10), la=(20, 14))
sd_push = P(lean=20, tilt=-14, rl=(-24, 24), ll=(26, 20), ra=(-42, 20), la=(55, 38), la_in=6)
sd_glide = P(lean=22, tilt=-16, rl=(-28, 26), ll=(30, 22), ra=(-44, 20), la=(66, 36), la_in=6)
sd_gather = P(lean=12, tilt=-7, rl=(-12, 12), ll=(14, 12), ra=(-18, 12), la=(30, 20))
sd_settle = P(lean=6, tilt=-2, rl=(-4, 4), ll=(6, 4), ra=(-6, 6), la=(10, 8))
sd_keys = check_length(planted(timeline([
    (sd_dip, 0.02),
    *tween(sd_dip, sd_push, ONE, 0.017),
    (sd_push, 0.078),
    (sd_glide, 0.085),
    *tween(sd_glide, sd_gather, EVEN, 0.03),
    (sd_gather, 0.04),
    *tween(sd_gather, sd_settle, ONE, 0.02),
    (sd_settle, 0.02),
])), 0.34, "DashLeft")
DASH_LEFT = seq("DashLeft", ACTION, False, sd_keys,
                "Quick-step left: low compact side-step, legs scissored under the body, body tips into it, "
                "left arm reaches ahead, right arm counter-swings back; legs gather and settle.", ground=True)
DASH_RIGHT = seq("DashRight", ACTION, False, mirror_keys(sd_keys), "Mirror of DashLeft.", ground=True)

# BACK, 0.34 s: hop backward off the front (left) foot. The right leg reaches back to lead the
# step; the body stays over the feet. The left arm swings forward and up, the right arm drops back.
bd_dip = P(lean=10, rl=(8, 4), ll=(-4, 4), ra=(8, 8), la=(12, 8))
bd_push = P(lean=16, rl=(-36, 8), ll=(30, 6), ra=(-30, 16), la=(68, 14), la_in=10)
bd_glide = P(lean=18, rl=(-40, 8), ll=(34, 6), ra=(-34, 18), la=(74, 16), la_in=10)
bd_gather = P(lean=10, rl=(-14, 4), ll=(14, 4), ra=(-12, 10), la=(32, 10))
bd_settle = P(lean=5, rl=(-4, 3), ll=(4, 3), ra=(-4, 5), la=(10, 6))
bd_keys = check_length(planted(timeline([
    (bd_dip, 0.02),
    *tween(bd_dip, bd_push, SLOW_IN, 0.017),
    (bd_push, 0.056),
    (bd_glide, 0.085),
    *tween(bd_glide, bd_gather, EVEN, 0.03),
    (bd_gather, 0.04),
    *tween(bd_gather, bd_settle, ONE, 0.02),
    (bd_settle, 0.025),
])), 0.34, "DashBack")
DASH_BACK = seq("DashBack", ACTION, False, bd_keys,
                "Back-step: right leg reaches back and leads, left foot stays under, body over the feet; "
                "left arm swings forward, right arm drops back; legs gather and settle.", ground=True)

# DASH PUNCH, 0.81 s: still in the lunge, the right arm cocks back with the torso twisted away;
# the straight jab SNAPS out at 0.16 s (the hitbox) with the right shoulder driven forward; endlag
# with both fists up by the face; one arm drops, recover.
LUNGE_LEGS = dict(rl=(-8, 3), ll=(72, 3))
dp_cock = T(lean=40, turn=22, head=(-30, 0, -18), ra=(-30, 14), la=(95, 8, 22), **LUNGE_LEGS)
dp_cock2 = T(lean=42, turn=34, head=(-32, 0, -28), ra=(-55, 18), la=(100, 8, 26), **LUNGE_LEGS)
dp_jab = T(lean=46, turn=-32, head=(-34, 0, 26), ra=(136, 2, 6), la=(40, 6, 30), rl=(-20, 3), ll=(80, 3))
dp_jab2 = T(lean=44, turn=-28, head=(-32, 0, 22), ra=(132, 4, 6), la=(45, 6, 30), rl=(-18, 3), ll=(78, 3))
dp_guard = T(lean=14, head=(-10, 0, 0), ra=(150, 6, 28), la=(142, 6, 30), rl=(-8, 3), ll=(35, 3))
dp_drop = T(lean=12, head=(-8, 0, 0), ra=(146, 6, 28), la=(30, 6, 10), rl=(-6, 3), ll=(30, 3))
dp_recover = T(lean=8, head=(-5, 0, 0), ra=(20, 5), la=(10, 5), rl=(0, 2), ll=(14, 2))
dp_stand = T(lean=4, head=(-2, 0, 0), ra=(6, 4), la=(4, 4), rl=(0, 2), ll=(6, 2))
dp_keys = check_length(planted(timeline([
    (dp_cock, 0.04),
    *tween(dp_cock, dp_cock2, ONE, 0.04),
    (dp_cock2, 0.08),                                 # the jab lands at 0.16
    (dp_jab, 0.06),
    (dp_jab2, 0.04),
    *tween(dp_jab2, dp_guard, EVEN, 0.03),
    (dp_guard, 0.17),
    *tween(dp_guard, dp_drop, ONE, 0.03),
    (dp_drop, 0.15),
    *tween(dp_drop, dp_recover, EVEN, 0.03),
    (dp_recover, 0.04),
    *tween(dp_recover, dp_stand, ONE, 0.02),
    (dp_stand, 0.02),
])), 0.81, "DashPunch")
DASH_PUNCH = seq("DashPunch", ACTION, False, dp_keys,
                 "Right arm cocks back with the torso twisted away, the jab snaps out at 0.16 s with the "
                 "shoulder driven forward; endlag with both fists up by the face, left arm drops, recover.",
                 ground=True, snaps=(3,))

PARKOUR = [LANDING_ROLL, VAULT, LEDGE_CLIMB, SLIDE, WALL_RUN_RIGHT, WALL_RUN_LEFT, WALL_HOP_RIGHT, WALL_HOP_LEFT]
DASHES = [DASH_FORWARD, DASH_LEFT, DASH_RIGHT, DASH_BACK, DASH_PUNCH]
ALL_NEW = PARKOUR + DASHES
