"""Locomotion: the loops Animate picks from every frame, plus the short transition clips it plays
between them (start walking or running, turn around, land) so a state change never jumps
straight from one loop into another.

Loops end with a copy of their first pose (timing.cycle); one-shots hold their last pose. Every
pose snaps (Constant easing); smoothness comes from in-between spacing (timing.py).
"""
from rig import pose, limb, body, mirror
from poses import seq, arm, leg, P, T, planted, plant, IDLE, MOVEMENT, ACTION
from timing import timeline, cycle, tween, lerp_pose, SLOW_IN, SLOW_OUT, SETTLE, ONE, QUICK_OUT, EVEN

# =========================================================================================
# IDLE (loop, ~2.3 s). Empty-handed, arms at the sides, feet a touch ahead of the torso.
# A stepped breath: every change between the three breath poses gets an in-between, so the
# chest rises and falls in small steps instead of popping.
# =========================================================================================
IDLE_LEG_SHIFT = 0.2  # studs the whole legs move forward


def idle_leg(side, root_dy=0.0, swing=0.0):
    lg = limb(side, swing=swing)
    lg["offset"] = (0, -root_dy, -IDLE_LEG_SHIFT)  # cancel the torso's bob so the feet stay planted
    return lg


def idle_pose(dy=0.0, lean=0.0, head=0.0, arm_out=3.0, arm_swing=0.0, tilt=0.0):
    return pose(root=body(dy=dy, lean=lean, tilt=tilt), head=body(lean=head, tilt=-tilt * 0.6),
                ra=limb("R", out=arm_out, swing=arm_swing), la=limb("L", out=arm_out, swing=arm_swing),
                rl=idle_leg("R", dy), ll=idle_leg("L", dy))


idle_rest = idle_pose()
idle_in = idle_pose(dy=0.06, lean=-1.5, head=-3, arm_out=6, arm_swing=2)     # breath in: chest and chin up
idle_out = idle_pose(dy=-0.02, lean=1.0, head=1, arm_out=3, arm_swing=-1)    # breath out, a little slumped
IDLE_ANIM = seq("Idle", IDLE, True, timeline([
    (idle_rest, 0.45),
    *tween(idle_rest, idle_in, ONE, 0.1),
    (idle_in, 0.55),
    *tween(idle_in, idle_rest, ONE, 0.12),
    (idle_rest, 0.3),
    *tween(idle_rest, idle_out, ONE, 0.1),
    (idle_out, 0.45),
    *tween(idle_out, idle_rest, ONE, 0.1),
], loop=True), "Arms at the sides, stepped breath with in-betweens (in, rest, out, rest).", ground=True)

# =========================================================================================
# WALK (loop, 0.8 s, authored for walk speed 14). Approved cycle, unchanged: from the Die of
# Death civilian walk. A new pose every 0.1 s; the back leg peels up behind further than the
# front leg reaches forward; arms swing from the shoulder, tight to the body.
# =========================================================================================
walk_contact = pose(root=body(lean=3, dy=-0.05), head=body(lean=-2),
                    ra=arm("R", swing=-30), la=arm("L", swing=32, inward=6),
                    rl=leg("R", swing=24), ll=leg("L", swing=-30))
walk_down = pose(root=body(lean=4, tilt=2, dy=-0.12), head=body(lean=-3, tilt=-2),
                 ra=arm("R", swing=-22), la=arm("L", swing=24, inward=4),
                 rl=leg("R", swing=14), ll=leg("L", swing=-36))
walk_pass = pose(root=body(lean=3, tilt=3, dy=0.08), head=body(lean=-2, tilt=-3),
                 ra=arm("R", swing=-4), la=arm("L", swing=6),
                 rl=leg("R", swing=-6), ll=leg("L", swing=4))
walk_up = pose(root=body(lean=3, tilt=2, dy=0.1), head=body(lean=-2, tilt=-2),
               ra=arm("R", swing=16, inward=4), la=arm("L", swing=-14),
               rl=leg("R", swing=-20), ll=leg("L", swing=20))
WALK_HALF = [walk_contact, walk_down, walk_pass, walk_up]
WALK = WALK_HALF + [mirror(p) for p in WALK_HALF]
WALK_ANIM = seq("WalkForward", MOVEMENT, True, cycle(WALK, 0.1),
                "8 poses, 0.8 s cycle. Body faces where you walk.")

# =========================================================================================
# SPRINT (loop, 0.64 s, authored for run speed 26). Approved cycle, unchanged: Die of Death
# civilian run. At the stride both arms are near horizontal, one forward and one back; the back
# leg kicks way up behind while the front leg only reaches a little.
# =========================================================================================
run_stride = pose(root=body(lean=16, tilt=-3, dy=-0.12), head=body(lean=-12, tilt=3),
                  ra=arm("R", swing=-75), la=arm("L", swing=88, inward=14),
                  rl=leg("R", swing=30), ll=leg("L", swing=-62))
run_kick = pose(root=body(lean=15, tilt=-2, dy=-0.03), head=body(lean=-11, tilt=2),
                ra=arm("R", swing=-62), la=arm("L", swing=74, inward=12),
                rl=leg("R", swing=18), ll=leg("L", swing=-72))
run_pass = pose(root=body(lean=10, tilt=2, dy=0.14), head=body(lean=-8, tilt=-2),
                ra=arm("R", swing=-12), la=arm("L", swing=16),
                rl=leg("R", swing=-10), ll=leg("L", swing=6))
run_reach = pose(root=body(lean=13, tilt=3, dy=0.08), head=body(lean=-10, tilt=-3),
                 ra=arm("R", swing=34, inward=8), la=arm("L", swing=-30),
                 rl=leg("R", swing=-34), ll=leg("L", swing=26))
RUN_HALF = [run_stride, run_kick, run_pass, run_reach]
SPRINT = RUN_HALF + [mirror(p) for p in RUN_HALF]
SPRINT_ANIM = seq("Sprint", MOVEMENT, True, cycle(SPRINT, 0.08),
                  "8 poses, 0.64 s cycle (Die of Death civilian run).",
                  snaps=(2, 6))  # the back leg whips forward into the passing pose: a deliberate snap

# =========================================================================================
# JUMP (one-shot, played at take-off; holds its last pose, which is the Fall pose).
# The body has already left the floor, so the anticipation is one quick push pose, then the
# lead knee drives up with the opposite arm, both arms rise, and the top eases into Fall.
# =========================================================================================
jump_push = pose(root=body(lean=10, dy=-0.1), head=body(lean=-6),
                 ra=arm("R", swing=-24), la=arm("L", swing=18, inward=4),
                 rl=leg("R", swing=26), ll=leg("L", swing=-22))
jump_drive = pose(root=body(lean=8, dy=-0.02), head=body(lean=-6),
                  ra=arm("R", swing=-34), la=arm("L", swing=58, inward=6),
                  rl=leg("R", swing=56), ll=leg("L", swing=-34))
jump_rise = pose(root=body(lean=2, dy=0.05), head=body(lean=-6),
                 ra=arm("R", swing=62, out=6, inward=4), la=arm("L", swing=100, out=6, inward=4),
                 rl=leg("R", swing=40), ll=leg("L", swing=-28))
fall_a = pose(root=body(lean=-4), head=body(lean=6),
              ra=arm("R", swing=115, out=14), la=arm("L", swing=100, out=16),
              rl=leg("R", swing=18), ll=leg("L", swing=-8, out=3))
JUMP_ANIM = seq("Jump", MOVEMENT, False, timeline([
    (jump_push, 0.03),
    *tween(jump_push, jump_drive, ONE, 0.03),
    (jump_drive, 0.05),
    *tween(jump_drive, jump_rise, ONE, 0.04),
    (jump_rise, 0.06),
    *tween(jump_rise, fall_a, SLOW_OUT, 0.05),
    (fall_a, 0.14),
]), "Push, knee drive with the opposite arm, arms rise, eases into the Fall pose at the top.")

# =========================================================================================
# FALL (loop, 0.8 s). Calm, not a flail: arms held up in front, legs hanging, head down toward
# the landing. Small changes held 0.2 s each so it drifts.
# =========================================================================================
fall_b = pose(root=body(lean=-5, dy=0.03), head=body(lean=7),
              ra=arm("R", swing=124, out=12), la=arm("L", swing=108, out=14),
              rl=leg("R", swing=12), ll=leg("L", swing=-2, out=3))
FALL_ANIM = seq("Fall", MOVEMENT, True, cycle([fall_a, fall_b, mirror(fall_a), mirror(fall_b)], 0.2),
                "Calm 4-pose fall, 0.8 s cycle; the Jump ends on its first pose.")

# =========================================================================================
# CLIMB (trusses / ladders, loop, 0.72 s; speed follows climb speed, 0 freezes it).
# Hands grip in front of the face at different heights, one knee comes up onto the next rung,
# the body pulls up with the hands level.
# =========================================================================================
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
CLIMB_ANIM = seq("Climb", MOVEMENT, True, cycle(CLIMB_HALF + [mirror(p) for p in CLIMB_HALF], 0.12),
                 "Hand over hand, 6 poses, 0.72 s cycle.")

LOOPS = [IDLE_ANIM, WALK_ANIM, SPRINT_ANIM, JUMP_ANIM, FALL_ANIM, CLIMB_ANIM]

# =========================================================================================
# TRANSITIONS (Movement priority, one-shots). Animate plays one of these in the locomotion slot
# when the state changes, then hands over to the loop. They're visual only: control is never
# delayed.
# =========================================================================================

# WALK START (0.1 s): from standing, a small weight shift onto the first step, ends on the walk
# contact pose so the cycle carries on from its first frame.
walk_shift = pose(root=body(lean=2, dy=-0.03), head=body(lean=-1),
                  ra=arm("R", swing=-8), la=arm("L", swing=10, inward=2),
                  rl=idle_leg("R", swing=8), ll=idle_leg("L", swing=-8))
WALK_START = seq("WalkStart", MOVEMENT, False, timeline([
    (walk_shift, 0.04),
    *tween(walk_shift, walk_contact, ONE, 0.03),
    (walk_contact, 0.03),
]), "Weight shift into the first step; ends on the walk's first pose.", ground=True)

# SPRINT START (0.2 s): push off. A low lean-in, the drive leg pushes back, the arms load, then
# the first running stride (the Sprint loop's first pose).
start_load = P(lean=8, dy=-0.1, ra=(-12, 4), la=(14, 4), rl=(8, 2), ll=(-6, 2))
start_push = P(lean=22, dy=-0.2, ra=(-40, 8), la=(52, 6), la_in=10, rl=(18, 2), ll=(-40, 2))
SPRINT_START = seq("SprintStart", MOVEMENT, False, planted(timeline([
    (start_load, 0.04),
    *tween(start_load, start_push, ONE, 0.03),
    (start_push, 0.05),
    *tween(start_push, run_stride, QUICK_OUT, 0.03),
    (run_stride, 0.05),
])), "Push off: low lean-in, drive leg pushes back, arms load, into the first stride.", ground=True)

# SPRINT TURN (0.22 s): turning around at speed. Plant, dip and lean into the new direction with
# the arms swinging across, then push into a stride.
turn_plant = P(lean=-8, tilt=10, dy=-0.3, ra=(30, 30), la=(-20, 24), rl=(30, 10), ll=(-10, 6))
turn_push = P(lean=18, tilt=-6, dy=-0.18, ra=(-50, 12), la=(60, 10), la_in=10, rl=(24, 3), ll=(-44, 3))
SPRINT_TURN = seq("SprintTurn", MOVEMENT, False, planted(timeline([
    (turn_plant, 0.05),
    *tween(turn_plant, turn_push, SLOW_IN, 0.03),
    (turn_push, 0.05),
    *tween(turn_push, run_stride, QUICK_OUT, 0.03),
    (run_stride, 0.03),
])), "Plant and dip leaning into the turn, arms swing across, push into a stride.", ground=True)

# LAND LIGHT (0.2 s): a normal jump landing while standing still. Squash, recover in steps, Idle.
land_squash = P(lean=10, dy=-0.35, head_lean=-4, ra=(28, 16), la=(24, 16), rl=(22, 5), ll=(-14, 5))
land_up = P(lean=4, dy=-0.12, ra=(10, 8), la=(8, 8), rl=(10, 3), ll=(-6, 3))
LAND_LIGHT = seq("LandLight", MOVEMENT, False, planted(timeline([
    (land_squash, 0.05),
    *tween(land_squash, land_up, ONE, 0.04),
    (land_up, 0.04),
    *tween(land_up, idle_rest, SETTLE, 0.025),
    (idle_rest, 0.02),
])), "Squash on touchdown, recover in steps into Idle.", ground=True)

# LAND RUN (0.14 s): landing while moving. A quick absorb mid-stride that flows into the run.
land_run_absorb = P(lean=16, dy=-0.3, ra=(-30, 8), la=(40, 8), la_in=8, rl=(20, 2), ll=(-28, 2))
LAND_RUN = seq("LandRun", MOVEMENT, False, planted(timeline([
    (land_run_absorb, 0.05),
    *tween(land_run_absorb, run_stride, ONE, 0.04),
    (run_stride, 0.05),
])), "Absorb mid-stride, straight back into the run.", ground=True)

TRANSITIONS = [WALK_START, SPRINT_START, SPRINT_TURN, LAND_LIGHT, LAND_RUN]
ALL = LOOPS + TRANSITIONS
