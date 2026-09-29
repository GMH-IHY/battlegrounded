"""Combat animations: the Sword and the Dagger, blocking and parrying, and every hit reaction.

Timings are docs/MoveData.md at 60 fps; each attack lasts exactly its move's frames (check_length):
startup ends on the wind-up pose, the active frames carry the cut (the first shows the blade mid-arc,
the next ones where it lands), and the recovery gets its in-betweens back to guard. Where a move
recovers faster on hit than on a whiff (the lunge), the animation lasts the whiff and the code stops
it early.

The sword sits on a wrist bone (SwordGrip, poses.grip): flex 0 = the blade points along the arm's
forward (tipped 25 deg down at rest), flex 90 = the blade continues the arm (thrusts, flat cuts).
Ground attacks keep a planted stance (legs by world angle, the body planted on the floor); air
attacks tuck the legs. Hit reactions snap into their first pose (the hit IS the snap), then hold.
"""
from poses import T, w_leg, seq, plant, planted, with_grip, grip, ACTION, MOVEMENT, CORE
from timing import timeline, tween, cycle, ONE, SLOW_IN, SETTLE, EVEN, QUICK_OUT, SLOW_OUT

F = 1 / 60
STANCE = {"R": (14, 4), "L": (-12, 4)}   # right foot a little forward (sword side), left back


def check_length(keys, frames, name):
    got = keys[-1][0]
    want = round(frames * F, 4)
    assert abs(got - want) < 2e-4, f"{name} lasts {got:.4f}s, the move lasts {frames} frames ({want:.4f}s)"
    return keys


def swing_pose(lean=0.0, turn=0.0, dy=0.0, tilt=0.0, head=(0, 0, 0), ra=(0, 0), la=(0, 0), step=0.0,
               flex=0.0, side=0.0):
    """Arms relative to the torso (they swing with it); legs by world angle so the stance stays
    planted however the torso leans. step widens the stance (a lunge into the cut)."""
    p = T(lean=lean, turn=turn, dy=dy, tilt=tilt, head=head, ra=ra, la=la)
    for s, joint in (("R", "Right Hip"), ("L", "Left Hip")):
        forward, out = STANCE[s]
        forward += step if s == "R" else -step
        p[joint] = w_leg(s, forward, out, lean=lean, tilt=tilt)
    return with_grip(plant(p), flex, side)


def air_pose(lean=0.0, turn=0.0, tilt=0.0, head=(0, 0, 0), ra=(0, 0), la=(0, 0), rl=(40, 6), ll=(10, 6),
             flex=0.0, side=0.0):
    """Airborne: legs tucked (relative to the torso), nothing planted."""
    return with_grip(T(lean=lean, turn=turn, tilt=tilt, head=head, ra=ra, la=la, rl=rl, ll=ll), flex, side)


# Guard between swings: a little crouched, sword arm forward and low, free arm up for balance.
ready = swing_pose(lean=8, head=(-6, 0, 0), ra=(38, 12, 8), la=(28, 10, 12), flex=10)
air_ready = air_pose(lean=6, head=(-4, 0, 0), ra=(40, 14, 8), la=(30, 12, 12), flex=10)


# =========================================================================================
# SWORD M1 CHAIN (ground)
# =========================================================================================

# M1 1: right to left. Wind up twisted right, sword arm out to the right with the blade trailing,
# then a flat cut across to the left. 5 / 2 / 11 frames.
m1a_wind = swing_pose(lean=10, turn=24, head=(-8, 0, -18), ra=(78, 70), la=(40, 10, 20), flex=70)
m1a_strike = swing_pose(step=6, lean=14, turn=-26, head=(-10, 0, 20), ra=(88, 4, 58), la=(-10, 16), flex=88)
m1a_follow = swing_pose(step=6, lean=13, turn=-30, head=(-10, 0, 22), ra=(70, 8, 64), la=(-14, 18), flex=80)
M1_1 = seq("M1Swing1", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, m1a_wind, SLOW_IN, F * 1.5),
    (m1a_wind, F),                                    # startup ends at 5 frames
    *tween(m1a_wind, m1a_strike, ONE, F),             # active frame 1: mid-cut
    (m1a_strike, F),                                  # active frame 2: the cut lands
    (m1a_follow, 4 * F),
    *tween(m1a_follow, ready, EVEN, 2 * F),
    (ready, 3 * F),
]), 18, "M1Swing1"), "Sword M1 1: wind up twisted right, a flat cut across to the left, recover to guard.")

# M1 2: left to right, a backhand. 5 / 2 / 11 frames.
m1b_wind = swing_pose(lean=10, turn=-24, head=(-8, 0, 18), ra=(80, 0, 60), la=(20, 14), flex=80)
m1b_strike = swing_pose(step=6, lean=14, turn=26, head=(-10, 0, -20), ra=(86, 78, -6), la=(40, 12, 24), flex=88)
m1b_follow = swing_pose(step=6, lean=13, turn=30, head=(-10, 0, -22), ra=(72, 84, -8), la=(44, 12, 26), flex=80)
M1_2 = seq("M1Swing2", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, m1b_wind, SLOW_IN, F * 1.5),
    (m1b_wind, F),
    *tween(m1b_wind, m1b_strike, ONE, F),
    (m1b_strike, F),
    (m1b_follow, 4 * F),
    *tween(m1b_follow, ready, EVEN, 2 * F),
    (ready, 3 * F),
]), 18, "M1Swing2"), "Sword M1 2: backhand; wind up with the arm across the chest, cut out to the right.")

# M1 3: a heavy overhead chop that knocks down. 7 / 3 / 18 frames.
m1c_lift = swing_pose(lean=2, turn=8, head=(-10, 0, -6), ra=(120, 12), la=(90, 12, 20), flex=30)
m1c_wind = swing_pose(lean=-8, dy=0.1, turn=10, head=(-14, 0, -8), ra=(172, 10), la=(150, 12, 16), flex=20)
m1c_strike = swing_pose(step=16, lean=34, dy=-0.25, turn=-6, head=(-26, 0, 4), ra=(60, 6, 10), la=(30, 14), flex=35)
m1c_follow = swing_pose(step=16, lean=38, dy=-0.3, turn=-8, head=(-28, 0, 6), ra=(34, 8, 12), la=(20, 16), flex=50)
M1_3 = seq("M1Swing3", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, m1c_lift, ONE, F),
    (m1c_lift, 2 * F),
    *tween(m1c_lift, m1c_wind, ONE, F),
    (m1c_wind, 2 * F),                                # startup ends at 7 frames
    *tween(m1c_wind, m1c_strike, ONE, F),             # active frame 1: mid-chop
    (m1c_strike, 2 * F),                              # the chop lands
    (m1c_follow, 8 * F),
    *tween(m1c_follow, ready, SETTLE, 2 * F),
    (ready, 6 * F),
]), 28, "M1Swing3"), "Sword M1 3: sword lifted high, then a full-body chop down; long recovery.")

# M1 3 with Space held: the LAUNCHER. Sink low with the blade trailing down behind, then a rising
# cut that stands you up on your toes. 8 / 3 / 14 frames.
launch_sink = swing_pose(lean=18, dy=-0.35, turn=18, head=(-12, 0, -10), ra=(-10, 24), la=(40, 12, 20), flex=60)
launch_low = swing_pose(lean=24, dy=-0.55, turn=24, head=(-18, 0, -14), ra=(-34, 28), la=(50, 14, 24), flex=75)
_launch_strike = swing_pose(step=4, lean=-6, dy=0.15, turn=-10, head=(10, 0, 6), ra=(150, 8, 10), la=(-20, 20), flex=85)
launch_top = swing_pose(step=4, lean=-12, dy=0.2, turn=-14, head=(14, 0, 8), ra=(176, 6, 6), la=(-30, 22), flex=90)
LAUNCHER = seq("SwordLauncher", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, launch_sink, SLOW_IN, F),
    (launch_sink, 2 * F),
    *tween(launch_sink, launch_low, ONE, F),
    (launch_low, 2 * F),                              # startup ends at 8 frames
    *tween(launch_low, launch_top, (0.33, 0.66), F),  # active 1-2: the blade sweeps up
    (launch_top, F),                                  # active 3: at the top
    (launch_top, 5 * F),
    *tween(launch_top, ready, (0.35, 0.7), 2 * F),
    (ready, 5 * F),
]), 25, "SwordLauncher"), "Sword launcher: sink low with the blade trailing, a rising cut up onto the toes.")

# RUNNING M1: the LUNGE. Coil back with the left hand pointing the way, then a long thrust with
# the whole body stretched out; you slide with it. 12 / 6 / 30 (24 on hit) frames.
lunge_coil = swing_pose(lean=-4, turn=24, dy=-0.1, head=(-2, 0, -20), ra=(24, 30, -8), la=(78, 8, 24), flex=15)
lunge_deep = swing_pose(lean=-8, turn=32, dy=-0.2, head=(0, 0, -26), ra=(14, 36, -12), la=(86, 8, 30), flex=10)
lunge_strike = swing_pose(step=22, lean=30, turn=-14, dy=-0.4, head=(-24, 0, 12), ra=(96, 0, 12), la=(-40, 14), flex=92)
lunge_reach = swing_pose(step=24, lean=34, turn=-16, dy=-0.45, head=(-26, 0, 14), ra=(98, 0, 12), la=(-46, 16), flex=92)
lunge_recover = swing_pose(step=12, lean=18, turn=-6, dy=-0.2, head=(-14, 0, 6), ra=(60, 8, 10), la=(-10, 14), flex=50)
LUNGE = seq("SwordLunge", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, lunge_coil, SLOW_IN, 1.5 * F),  # 3 frames
    (lunge_coil, 3 * F),
    *tween(lunge_coil, lunge_deep, ONE, F),
    (lunge_deep, 4 * F),                              # startup ends at 12 frames
    *tween(lunge_deep, lunge_strike, ONE, F),         # active: the thrust shoots out...
    (lunge_strike, 2 * F),
    (lunge_reach, 3 * F),                             # ...and stays out while you slide
    (lunge_reach, 9 * F),
    *tween(lunge_reach, lunge_recover, EVEN, 3 * F),
    (lunge_recover, 4 * F),
    *tween(lunge_recover, ready, SETTLE, 2 * F),
    (ready, 7 * F),
]), 48, "SwordLunge"), "Running M1 lunge: coil back pointing the way, a long full-body thrust, slide, recover.")

# 1: the LINKER. A meaty two-handed cleave: a big coil to the right with the free hand joining
# the grip, a held beat, then a cut across that stays out for 4 frames. 12 / 4 / 22 frames.
one_coil = swing_pose(lean=6, turn=30, head=(-6, 0, -22), ra=(96, 76), la=(70, 10, 64), flex=60)
one_load = swing_pose(lean=10, turn=42, dy=-0.15, head=(-8, 0, -30), ra=(104, 88), la=(80, 6, 76), flex=75)
one_strike = swing_pose(step=12, lean=20, turn=-34, dy=-0.2, head=(-14, 0, 24), ra=(86, 6, 64), la=(70, 8, 40), flex=90)
one_through = swing_pose(step=12, lean=22, turn=-46, dy=-0.25, head=(-16, 0, 30), ra=(78, 10, 74), la=(58, 10, 50), flex=90)
ONE_ = seq("SwordOne", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, one_coil, SLOW_IN, 1.5 * F),
    (one_coil, 3 * F),
    *tween(one_coil, one_load, ONE, F),
    (one_load, 4 * F),                                # startup ends at 12 frames
    *tween(one_load, one_strike, ONE, F),             # active 1: mid-cleave
    (one_strike, F),
    (one_through, 2 * F),                             # active 3-4: through
    (one_through, 8 * F),
    *tween(one_through, ready, EVEN, 3 * F),
    (ready, 8 * F),
]), 38, "SwordOne"), "Sword 1: a meaty two-handed cleave; big coil right, held beat, a cut across that stays out.")

# =========================================================================================
# SWORD (air)
# =========================================================================================

# Air M1 1: a diagonal cut down to the left. 5 / 2 / 11 frames.
a1_wind = air_pose(lean=-4, turn=20, head=(-4, 0, -14), ra=(150, 50), la=(40, 14, 20), flex=55)
a1_strike = air_pose(lean=16, turn=-22, head=(-12, 0, 16), ra=(70, 10, 50), la=(-10, 20), flex=88, rl=(30, 8), ll=(24, 6))
a1_follow = air_pose(lean=18, turn=-26, head=(-14, 0, 18), ra=(56, 12, 56), la=(-16, 22), flex=85, rl=(30, 8), ll=(24, 6))
AIR_1 = seq("SwordAirSlash1", ACTION, False, check_length(timeline([
    (air_ready, F),
    *tween(air_ready, a1_wind, SLOW_IN, F * 1.5),
    (a1_wind, F),
    *tween(a1_wind, a1_strike, ONE, F),
    (a1_strike, F),
    (a1_follow, 4 * F),
    *tween(a1_follow, air_ready, EVEN, 2 * F),
    (air_ready, 3 * F),
]), 18, "SwordAirSlash1"), "Air M1 1: legs tucked, a diagonal cut down to the left.")

# Air M1 2: a rising backhand out to the right. 5 / 2 / 11 frames.
a2_wind = air_pose(lean=12, turn=-22, head=(-8, 0, 16), ra=(76, 0, 62), la=(20, 16), flex=82)
a2_strike = air_pose(lean=-6, turn=20, head=(4, 0, -18), ra=(114, 70, 0), la=(44, 14, 26), flex=88, rl=(24, 8), ll=(44, 6))
a2_follow = air_pose(lean=-8, turn=24, head=(6, 0, -20), ra=(124, 74, -2), la=(48, 14, 28), flex=85, rl=(24, 8), ll=(44, 6))
AIR_2 = seq("SwordAirSlash2", ACTION, False, check_length(timeline([
    (air_ready, F),
    *tween(air_ready, a2_wind, SLOW_IN, F * 1.5),
    (a2_wind, F),
    *tween(a2_wind, a2_strike, ONE, F),
    (a2_strike, F),
    (a2_follow, 4 * F),
    *tween(a2_follow, air_ready, SETTLE, 2 * F),
    (air_ready, 3 * F),
]), 18, "SwordAirSlash2"), "Air M1 2: a rising backhand cut out to the right.")

# Air M1 3: the SPIKE, an unblockable downward slash. A long wind-up curled back with the sword
# high behind the head (the yellow flash plays here), then a full vertical cut. 16 / 4 / 20 frames.
spike_lift = air_pose(lean=-10, turn=6, head=(8, 0, -4), ra=(150, 12), la=(120, 14, 16), flex=30, rl=(50, 6), ll=(30, 6))
spike_curl = air_pose(lean=-24, turn=8, head=(14, 0, -6), ra=(178, 8), la=(160, 12, 12), flex=15, rl=(70, 8), ll=(56, 8))
spike_curl2 = air_pose(lean=-28, turn=8, head=(16, 0, -6), ra=(184, 8), la=(166, 12, 12), flex=10, rl=(76, 8), ll=(62, 8))
spike_strike = air_pose(lean=34, turn=-4, head=(-26, 0, 2), ra=(70, 4, 6), la=(40, 16), flex=90, rl=(20, 6), ll=(-10, 6))
spike_down = air_pose(lean=44, turn=-6, head=(-30, 0, 4), ra=(30, 6, 8), la=(20, 18), flex=95, rl=(10, 6), ll=(-20, 6))
SPIKE = seq("SwordAirSpike", ACTION, False, check_length(timeline([
    (air_ready, F),
    *tween(air_ready, spike_lift, SLOW_IN, 1.5 * F),
    (spike_lift, 3 * F),
    *tween(spike_lift, spike_curl, ONE, F),
    (spike_curl, 3 * F),
    (spike_curl2, 5 * F),                             # startup ends at 16 frames
    *tween(spike_curl2, spike_strike, ONE, F),        # active 1: the cut comes over
    (spike_strike, F),
    (spike_down, 2 * F),                              # active 3-4: straight down
    (spike_down, 8 * F),
    *tween(spike_down, air_ready, EVEN, 3 * F),
    (air_ready, 6 * F),
]), 40, "SwordAirSpike"), "Air M1 3 spike: curl back with the sword behind the head, a full vertical cut down.")

# Air 1: a big diagonal cleave from high right to low left. 10 / 4 / 18 frames.
aone_coil = air_pose(lean=-10, turn=28, head=(4, 0, -20), ra=(160, 40), la=(90, 10, 50), flex=45, rl=(50, 6), ll=(30, 6))
aone_load = air_pose(lean=-16, turn=36, head=(8, 0, -26), ra=(172, 46), la=(104, 8, 60), flex=40, rl=(60, 6), ll=(40, 6))
aone_strike = air_pose(lean=24, turn=-30, head=(-18, 0, 22), ra=(64, 10, 56), la=(60, 10, 40), flex=90, rl=(26, 6), ll=(4, 6))
aone_through = air_pose(lean=28, turn=-40, head=(-20, 0, 28), ra=(46, 12, 62), la=(50, 10, 46), flex=92, rl=(26, 6), ll=(4, 6))
AIR_ONE = seq("SwordAirOne", ACTION, False, check_length(timeline([
    (air_ready, F),
    *tween(air_ready, aone_coil, SLOW_IN, 1.5 * F),
    (aone_coil, 2 * F),
    *tween(aone_coil, aone_load, ONE, F),
    (aone_load, 3 * F),                               # startup ends at 10 frames
    *tween(aone_load, aone_strike, ONE, F),
    (aone_strike, F),
    (aone_through, 2 * F),
    (aone_through, 7 * F),
    *tween(aone_through, air_ready, EVEN, 3 * F),
    (air_ready, 5 * F),
]), 32, "SwordAirOne"), "Air 1: a big two-handed diagonal cleave from high right to low left.")

# =========================================================================================
# DAGGER (left hand, drawn from the hip for the move)
# =========================================================================================

# Stab: a quick left jab with the shoulder turned in; the sword arm pulls back. 4 / 2 / 12 frames.
dag_draw = swing_pose(lean=8, turn=-10, head=(-6, 0, 8), ra=(30, 18, 4), la=(-24, 12), flex=10)
dag_cock = swing_pose(lean=10, turn=-16, head=(-8, 0, 12), ra=(24, 22), la=(30, 10, -10), flex=10)
dag_stab = swing_pose(step=8, lean=16, turn=26, head=(-12, 0, -18), ra=(10, 24), la=(92, 0, 14), flex=5)
dag_hold = swing_pose(step=8, lean=17, turn=28, head=(-12, 0, -20), ra=(8, 24), la=(94, 0, 16), flex=5)
DAGGER_STAB = seq("DaggerStab", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, dag_draw, ONE, F),
    (dag_draw, F),
    (dag_cock, F),                                    # startup ends at 4 frames
    *tween(dag_cock, dag_stab, ONE, F),               # active 1
    (dag_stab, F),                                    # active 2: the jab lands
    (dag_hold, 4 * F),
    *tween(dag_hold, ready, EVEN, 2 * F),
    (ready, 4 * F),
]), 18, "DaggerStab"), "Dagger stab: draw from the hip, a quick left jab with the shoulder turned in.")

# Air slash: a flat left-hand cut across, right to left from the body's left side. 4 / 2 / 10 frames.
dair_draw = air_pose(lean=6, turn=-14, head=(-4, 0, 10), ra=(30, 18), la=(30, 36), flex=10)
dair_cock = air_pose(lean=8, turn=-20, head=(-6, 0, 14), ra=(24, 22), la=(70, 60), flex=10)
dair_strike = air_pose(lean=14, turn=22, head=(-10, 0, -16), ra=(14, 24), la=(86, 6, 56), flex=5, rl=(30, 8), ll=(20, 6))
dair_follow = air_pose(lean=15, turn=26, head=(-10, 0, -18), ra=(12, 24), la=(80, 8, 64), flex=5, rl=(30, 8), ll=(20, 6))
DAGGER_AIR = seq("DaggerAirSlash", ACTION, False, check_length(timeline([
    (air_ready, F),
    *tween(air_ready, dair_draw, ONE, F),
    (dair_draw, F),
    (dair_cock, F),
    *tween(dair_cock, dair_strike, ONE, F),
    (dair_strike, F),
    (dair_follow, 4 * F),
    *tween(dair_follow, air_ready, EVEN, 2 * F),
    (air_ready, 2 * F),
]), 16, "DaggerAirSlash"), "Dagger air slash: a flat left-hand cut across the body.")

# =========================================================================================
# DEFENCE
# =========================================================================================

# Block: the sword held flat across the front, the free forearm braced behind it, a low stance.
guard = swing_pose(lean=10, dy=-0.15, head=(-8, 0, 0), ra=(84, 0, 66), la=(74, 8, 44), flex=88, step=4)
guard_b = swing_pose(lean=11, dy=-0.18, head=(-8, 0, 0), ra=(84, 0, 67), la=(74, 8, 45), flex=88, step=4)
BLOCK = seq("BlockHold", ACTION, True, cycle([guard, guard_b], [0.4, 0.4]),
            "Block: sword flat across the front, free arm braced behind it, low stance.", ground=True)
guard_hit = swing_pose(lean=-4, dy=-0.1, head=(8, 0, 0), ra=(96, 2, 60), la=(86, 10, 40), flex=86, step=6)
BLOCK_HIT = seq("BlockImpact", ACTION, False, timeline([
    (guard_hit, 2 * F),
    *tween(guard_hit, guard, SETTLE, 2 * F),
    (guard, 5 * F),
]), "A hit on the guard: rocked back, arms pushed up, back into the block.", ground=True)

# Parry: a sharp outward flick from the guard, then back to ready.
parry_flick = swing_pose(lean=4, turn=18, head=(-4, 0, -10), ra=(112, 60, -6), la=(40, 14, 10), flex=80)
parry_open = swing_pose(lean=2, turn=22, head=(-2, 0, -12), ra=(120, 70, -10), la=(30, 16, 6), flex=78)
PARRY = seq("Parry", ACTION, False, timeline([
    (guard, F),
    *tween(guard, parry_flick, (0.25, 0.55), F),
    (parry_flick, 2 * F),
    (parry_open, 4 * F),
    *tween(parry_open, ready, EVEN, 2 * F),
    (ready, 4 * F),
]), "Parry: a sharp outward flick of the blade from the guard, then back to ready.", ground=True)

# Parried: your attack got parried. Arms flung up and back, stagger. 20 frames (ParryStun).
staggered = swing_pose(lean=-18, dy=0.05, head=(16, 0, 0), ra=(150, 40), la=(124, 30), flex=30, step=-6)
staggered_2 = swing_pose(lean=-20, dy=0.05, head=(18, 0, 0), ra=(156, 42), la=(130, 32), flex=28, step=-6)
PARRIED = seq("Parried", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, staggered, (0.35, 0.7), F),
    (staggered, 2 * F),
    (staggered_2, 7 * F),
    *tween(staggered_2, ready, (0.5, 0.85), 2 * F),
    (ready, 4 * F),
]), 20, "Parried"), "Parried: arms flung up and back, a stagger, then back to guard.", ground=True)

# =========================================================================================
# HIT REACTIONS (Action priority; the code stops them when the stun ends)
# =========================================================================================
REACT = ACTION

flinch_a = swing_pose(lean=-14, turn=10, head=(18, 0, -8), ra=(34, 22), la=(40, 22), flex=10)
flinch_a2 = swing_pose(lean=-16, turn=12, head=(20, 0, -10), ra=(30, 24), la=(36, 24), flex=10)
flinch_a3 = swing_pose(lean=-12, turn=10, head=(14, 0, -8), ra=(26, 20), la=(32, 20), flex=10)
HIT_1 = seq("HitStun1", REACT, False, timeline([
    *tween(ready, flinch_a, (0.6,), F),
    (flinch_a, 2 * F),
    (flinch_a2, 6 * F),
    *tween(flinch_a2, flinch_a3, ONE, 3 * F),
    (flinch_a3, 36 * F),
]), "Hit stun: head and chest knocked back with a twist, held until the stun ends.", ground=True)

flinch_b = swing_pose(lean=-10, turn=-14, tilt=8, head=(14, -6, 10), ra=(20, 26), la=(46, 18), flex=10)
flinch_b2 = swing_pose(lean=-12, turn=-16, tilt=10, head=(16, -8, 12), ra=(16, 28), la=(42, 20), flex=10)
flinch_b3 = swing_pose(lean=-8, turn=-12, tilt=6, head=(10, -4, 8), ra=(18, 22), la=(36, 18), flex=10)
HIT_2 = seq("HitStun2", REACT, False, timeline([
    *tween(ready, flinch_b, (0.6,), F),
    (flinch_b, 2 * F),
    (flinch_b2, 6 * F),
    *tween(flinch_b2, flinch_b3, ONE, 3 * F),
    (flinch_b3, 36 * F),
]), "Hit stun (alternate): knocked back twisting the other way, held until the stun ends.", ground=True)

air_hit = air_pose(lean=-20, turn=8, head=(18, 0, -6), ra=(60, 30), la=(70, 30), rl=(20, 10), ll=(-10, 10))
air_hit2 = air_pose(lean=-24, turn=10, head=(20, 0, -8), ra=(66, 32), la=(76, 32), rl=(24, 12), ll=(-14, 12))
HIT_AIR = seq("HitAir", REACT, False, timeline([
    *tween(air_ready, air_hit, (0.6,), F),
    (air_hit, 2 * F),
    (air_hit2, 42 * F),
]), "Hit in the air: flung back with the legs dangling, hanging until the stun ends.")

# Knocked down (M1 3, a spike, a knockdown hit): tumbling back through the air, then held until
# the landing (the code switches to Downed).
tumble_1 = air_pose(lean=-40, head=(20, 0, 0), ra=(120, 40), la=(110, 40), rl=(50, 12), ll=(20, 12))
tumble_2 = air_pose(lean=-70, head=(24, 0, 0), ra=(150, 50), la=(140, 50), rl=(80, 14), ll=(40, 14))
tumble_3 = air_pose(lean=-86, head=(20, 0, 0), ra=(160, 60), la=(150, 60), rl=(60, 16), ll=(30, 16))
KNOCKBACK = seq("Knockback", REACT, False, timeline([
    *tween(air_ready, tumble_1, (0.3, 0.65), F),
    (tumble_1, 3 * F),
    *tween(tumble_1, tumble_2, ONE, 2 * F),
    (tumble_2, 4 * F),
    *tween(tumble_2, tumble_3, ONE, 3 * F),
    (tumble_3, 60 * F),
]), "Knocked down: tumbling back through the air, arms flung over the head, held until landing.")

# Launched: sent straight up, arched back, arms and legs trailing.
launched_1 = air_pose(lean=-26, head=(20, 0, 0), ra=(20, 40), la=(24, 40), rl=(-10, 10), ll=(-20, 10))
launched_2 = air_pose(lean=-40, head=(26, 0, 0), ra=(10, 50), la=(14, 50), rl=(-20, 12), ll=(-30, 12))
LAUNCHED = seq("Launched", REACT, False, timeline([
    *tween(ready, launched_1, (0.5,), F),
    (launched_1, 3 * F),
    *tween(launched_1, launched_2, ONE, 2 * F),
    (launched_2, 50 * F),
]), "Launched: sent up arched back, arms and legs trailing, held while rising.")

# Downed: lying on the back on the floor (Core priority stays under nothing: Action).
lying = plant(T(lean=-90, head=(-10, 0, 0), ra=(20, 30), la=(20, 30), rl=(6, 8), ll=(-4, 8)))
lying_b = plant(T(lean=-90, dy=0.03, head=(-12, 0, 0), ra=(22, 30), la=(18, 30), rl=(6, 8), ll=(-4, 8)))
DOWNED = seq("Downed", REACT, True, cycle([lying, lying_b], [0.3, 0.3]),
             "Downed: flat on the back on the floor, a little breathing.")

# Get up: roll the shoulders up, knees in, into a crouch, into guard. 0.3 s.
sit_up = plant(T(lean=-50, head=(-20, 0, 0), ra=(-40, 20), la=(-40, 20), rl=(60, 8), ll=(40, 8)))
crouch_up = plant(T(lean=10, head=(-10, 0, 0), ra=(-10, 14), la=(0, 14), rl=(90, 8), ll=(40, 8)))
rise_up = swing_pose(lean=16, dy=-0.4, head=(-10, 0, 0), ra=(20, 12), la=(24, 12), flex=10)
GET_UP = seq("GetUp", REACT, False, timeline([
    (lying, F),
    *tween(lying, sit_up, SLOW_IN, F),
    (sit_up, 2 * F),
    *tween(sit_up, crouch_up, EVEN, F),
    (crouch_up, 2 * F),
    *tween(crouch_up, rise_up, ONE, F),
    (rise_up, 2 * F),
    *tween(rise_up, ready, SETTLE, F),
    (ready, 3 * F),
]), "Get up: shoulders up, knees in, a crouch, back into guard.")

# Tech roll: a quick backward roll out of the knockdown, back onto the feet. 0.3 s.
roll_tuck = plant(T(lean=-130, head=(-30, 0, 0), ra=(60, 20), la=(60, 20), rl=(110, 8), ll=(100, 8)))
roll_over = plant(T(lean=-200, head=(-30, 0, 0), ra=(80, 20), la=(80, 20), rl=(120, 8), ll=(110, 8)))
roll_feet = plant(T(lean=-290, head=(-20, 0, 0), ra=(40, 20), la=(40, 20), rl=(100, 8), ll=(70, 8)))


def _full_turn(p):
    # The same pose, with the body's pitch one full turn back, so the roll keeps turning the same way.
    return dict(p, RootJoint=dict(p["RootJoint"], pitch=p["RootJoint"]["pitch"] + 360))


roll_crouch = _full_turn(swing_pose(lean=20, dy=-0.5, head=(-10, 0, 0), ra=(20, 16), la=(24, 16), flex=10))
ready_full = _full_turn(ready)
TECH_ROLL = seq("TechRoll", REACT, False, timeline([
    (lying, F),
    *tween(lying, roll_tuck, SLOW_IN, F),
    (roll_tuck, F),
    *tween(roll_tuck, roll_over, ONE, F),
    (roll_over, F),
    *tween(roll_over, roll_feet, ONE, F),
    (roll_feet, F),
    *tween(roll_feet, roll_crouch, ONE, F),
    (roll_crouch, 3 * F),
    *tween(roll_crouch, ready_full, SETTLE, F),
    (ready_full, 3 * F),
]), "Tech roll: a quick backward roll out of the knockdown, onto the feet, into guard.")

SWORD = [M1_1, M1_2, M1_3, LAUNCHER, LUNGE, ONE_, AIR_1, AIR_2, SPIKE, AIR_ONE]
DAGGER = [DAGGER_STAB, DAGGER_AIR]
DEFENCE = [BLOCK, BLOCK_HIT, PARRY, PARRIED]
REACTIONS = [HIT_1, HIT_2, HIT_AIR, KNOCKBACK, LAUNCHED, DOWNED, GET_UP, TECH_ROLL]
COMBAT = SWORD + DAGGER + DEFENCE + REACTIONS

# Unused imports kept for authoring convenience.
_ = (grip, planted, MOVEMENT, CORE)
