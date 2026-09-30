"""Wind animations: the Q push and pull (both 10 / 6 / 18 frames, docs/MoveData.md).

The left (free) hand does the wind; the sword stays low in the right. Push: draw the palm back to
the hip, then shove it out flat. Pull: reach the palm out, then yank it back to the chest.
"""
from combat_anims import swing_pose, ready, check_length, F
from poses import seq, ACTION
from timing import timeline, tween, ONE, SLOW_IN, SETTLE, EVEN

# Sword arm low and out of the way.
SWORD_LOW = (14, 22)

# Push: palm drawn back by the hip, shoulder turned away; then a full shove forward.
pu_draw = swing_pose(lean=-2, turn=-24, dy=-0.05, head=(0, 0, 18), ra=SWORD_LOW, la=(-24, 18, -10), flex=8)
pu_load = swing_pose(lean=-4, turn=-32, dy=-0.12, head=(2, 0, 24), ra=SWORD_LOW, la=(-36, 22, -14), flex=8)
pu_shove = swing_pose(step=10, lean=14, turn=24, dy=-0.2, head=(-8, 0, -16), ra=(10, 24), la=(90, -4, 16), flex=8)
pu_hold = swing_pose(step=10, lean=15, turn=26, dy=-0.22, head=(-8, 0, -18), ra=(10, 24), la=(92, -4, 18), flex=8)
PUSH = seq("WindPush", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, pu_draw, SLOW_IN, F),
    (pu_draw, 2 * F),
    *tween(pu_draw, pu_load, ONE, F),
    (pu_load, 4 * F),                                 # startup ends at 10 frames
    *tween(pu_load, pu_shove, (0.35, 0.7), F),        # active: the shove
    (pu_shove, F),
    (pu_hold, 3 * F),                                 # active ends at 16 frames
    (pu_hold, 8 * F),
    *tween(pu_hold, ready, EVEN, 1.5 * F),
    (ready, 7 * F),
]), 34, "WindPush"), "Wind push (Q): palm drawn back to the hip, then shoved out flat.", ground=True)

# Pull: palm reaching out, fingers open; then yanked back to the chest, body leaning away.
pl_reach = swing_pose(step=6, lean=10, turn=18, head=(-6, 0, -12), ra=SWORD_LOW, la=(84, -2, 10), flex=8)
pl_far = swing_pose(step=8, lean=14, turn=24, dy=-0.08, head=(-8, 0, -16), ra=SWORD_LOW, la=(92, -4, 14), flex=8)
pl_yank = swing_pose(step=-4, lean=-8, turn=-20, dy=-0.15, head=(4, 0, 14), ra=(12, 24), la=(40, 12, -20), flex=30)
pl_hold = swing_pose(step=-4, lean=-9, turn=-22, dy=-0.17, head=(4, 0, 16), ra=(12, 24), la=(36, 14, -22), flex=34)
PULL = seq("WindPull", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, pl_reach, SLOW_IN, F),
    (pl_reach, 2 * F),
    *tween(pl_reach, pl_far, ONE, F),
    (pl_far, 4 * F),                                  # startup ends at 10 frames
    *tween(pl_far, pl_yank, (0.35, 0.7), F),          # active: the yank
    (pl_yank, F),
    (pl_hold, 3 * F),                                 # active ends at 16 frames
    (pl_hold, 8 * F),
    *tween(pl_hold, ready, SETTLE, 1.5 * F),
    (ready, 7 * F),
]), 34, "WindPull"), "Wind pull (S + Q): palm reaching out, then yanked back to the chest.", ground=True)

WIND = [PUSH, PULL]
