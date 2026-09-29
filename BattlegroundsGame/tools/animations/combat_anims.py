"""Combat animations. For now: the sword's 3-hit M1 chain, played by the placeholder M1 until the
combat system exists (the sword model comes with it; the arm motion is already the sword's).

Timings are docs/MoveData.md at 60 fps:
  M1 1 / M1 2: startup 5 frames (0.083 s), active 2 (0.033), recovery 11 (0.183) = 0.30 s
  M1 3:        startup 7 (0.117),          active 3 (0.05),  recovery 18 (0.30)  = 0.467 s
The active frames carry the cut: the first shows the sword mid-arc, the second where it lands. The
wind-up and the recovery get in-betweens. Full body: the torso leans and twists into each swing
while the legs hold a planted stance (their world angle is kept, so a lean doesn't tip them).
"""
from poses import T, w_leg, seq, plant, ACTION
from timing import timeline, tween, ONE, SLOW_IN, SETTLE, EVEN

F = 1 / 60
STANCE = {"R": (14, 4), "L": (-12, 4)}   # right foot a little forward (sword side), left back


def swing_pose(lean=0.0, turn=0.0, dy=0.0, head=(0, 0, 0), ra=(0, 0), la=(0, 0), step=0.0):
    """Arms relative to the torso (they swing with it); legs by world angle so the stance stays
    planted however the torso leans. step widens the stance (a lunge into the cut)."""
    p = T(lean=lean, turn=turn, dy=dy, head=head, ra=ra, la=la)
    for side, joint in (("R", "Right Hip"), ("L", "Left Hip")):
        forward, out = STANCE[side]
        forward += step if side == "R" else -step
        p[joint] = w_leg(side, forward, out, lean=lean)
    return plant(p)


# Guard between swings: a little crouched, sword arm forward and low, free arm up for balance.
ready = swing_pose(lean=8, head=(-6, 0, 0), ra=(38, 12, 8), la=(28, 10, 12))

# M1 1: right to left. Wind up with the torso twisted right and the sword arm out to the right,
# then cut across to the left.
m1a_wind = swing_pose(lean=10, turn=24, head=(-8, 0, -18), ra=(78, 70), la=(40, 10, 20))
m1a_strike = swing_pose(step=6, lean=14, turn=-26, head=(-10, 0, 20), ra=(88, 4, 58), la=(-10, 16))
m1a_follow = swing_pose(step=6, lean=13, turn=-30, head=(-10, 0, 22), ra=(70, 8, 64), la=(-14, 18))
M1_1 = seq("M1Swing1", ACTION, False, timeline([
    (ready, F),
    *tween(ready, m1a_wind, SLOW_IN, F * 1.5),
    (m1a_wind, F),                                    # startup ends at 5 frames
    *tween(m1a_wind, m1a_strike, ONE, F),             # active frame 1: mid-cut
    (m1a_strike, F),                                  # active frame 2: the cut lands
    (m1a_follow, 4 * F),
    *tween(m1a_follow, ready, EVEN, 2 * F),
    (ready, 3 * F),
]), "M1 1: wind up twisted right with the sword arm out, cut across to the left, recover to guard.")

# M1 2: left to right, a backhand. Wind up with the arm across the chest, cut out to the right.
m1b_wind = swing_pose(lean=10, turn=-24, head=(-8, 0, 18), ra=(80, 0, 60), la=(20, 14))
m1b_strike = swing_pose(step=6, lean=14, turn=26, head=(-10, 0, -20), ra=(86, 78, -6), la=(40, 12, 24))
m1b_follow = swing_pose(step=6, lean=13, turn=30, head=(-10, 0, -22), ra=(72, 84, -8), la=(44, 12, 26))
M1_2 = seq("M1Swing2", ACTION, False, timeline([
    (ready, F),
    *tween(ready, m1b_wind, SLOW_IN, F * 1.5),
    (m1b_wind, F),
    *tween(m1b_wind, m1b_strike, ONE, F),
    (m1b_strike, F),
    (m1b_follow, 4 * F),
    *tween(m1b_follow, ready, EVEN, 2 * F),
    (ready, 3 * F),
]), "M1 2: backhand: wind up with the arm across the chest, cut out to the right, recover to guard.")

# M1 3: a heavy overhead. The sword goes up high with the body leaning back, then chops down with
# the whole body dropping into it; long recovery.
m1c_lift = swing_pose(lean=2, turn=8, head=(-10, 0, -6), ra=(120, 12), la=(90, 12, 20))
m1c_wind = swing_pose(lean=-8, dy=0.1, turn=10, head=(-14, 0, -8), ra=(172, 10), la=(150, 12, 16))
m1c_strike = swing_pose(step=16, lean=34, dy=-0.25, turn=-6, head=(-26, 0, 4), ra=(60, 6, 10), la=(30, 14))
m1c_follow = swing_pose(step=16, lean=38, dy=-0.3, turn=-8, head=(-28, 0, 6), ra=(34, 8, 12), la=(20, 16))
M1_3 = seq("M1Swing3", ACTION, False, timeline([
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
]), "M1 3: sword lifted high with the body leaning back, then a full-body chop down; long recovery.")

COMBAT = [M1_1, M1_2, M1_3]
