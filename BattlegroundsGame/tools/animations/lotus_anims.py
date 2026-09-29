"""Lotus Fungus animations: everything the left (fungus) arm does, plus being held and consumed.

Timings are the Lotus moves in docs/MoveData.md at 60 fps (check_length); the grab is timed for the
stage 3 grab's 16-frame startup and the other stages play it slower (Move.AnimSpeed). The sword
stays in the right hand, held low and out of the way. Loops: the heal channel, the feast (holding a
grabbed opponent) and being held.
"""
from combat_anims import swing_pose, air_pose, ready, check_length, F
from poses import seq, plant, T, ACTION
from timing import timeline, tween, cycle, ONE, SLOW_IN, SETTLE, EVEN

# Sword arm tucked low and back while the fungus arm works.
SWORD_LOW = (14, 22)

# =========================================================================================
# 2: STAB
# =========================================================================================

# Stage 1: a quick strand stab. Shoulder turned in, the left arm snaps straight out (the strand
# grows 9 studs from the hand, CombatFx). 10 / 3 / 16.
st_coil = swing_pose(lean=6, turn=-22, head=(-4, 0, 16), ra=SWORD_LOW, la=(40, 20, -20), flex=10)
st_load = swing_pose(lean=8, turn=-30, dy=-0.1, head=(-6, 0, 22), ra=SWORD_LOW, la=(56, 26, -26), flex=10)
st_hit = swing_pose(step=8, lean=16, turn=26, head=(-12, 0, -18), ra=(8, 24), la=(94, 0, 12), flex=10)
st_hold = swing_pose(step=8, lean=17, turn=28, head=(-12, 0, -20), ra=(6, 24), la=(96, 0, 14), flex=10)
STAB = seq("LotusStab", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, st_coil, SLOW_IN, 1.5 * F),
    (st_coil, 3 * F),
    *tween(st_coil, st_load, ONE, F),
    (st_load, 2 * F),                                 # startup ends at 10 frames
    *tween(st_load, st_hit, ONE, F),                  # active 1
    (st_hit, F),
    (st_hold, F),                                     # active 3
    (st_hold, 6 * F),
    *tween(st_hold, ready, EVEN, 2 * F),
    (ready, 6 * F),
]), 29, "LotusStab"), "Lotus stab (stage 1): shoulder turned in, the fungus arm snaps straight out.", ground=True)

# Stage 2: the ground strand. Drop low and slam the fungus palm into the floor; the strand races
# away along the ground. 16 / 1 / 20.
gs_rise = swing_pose(lean=-4, dy=0.05, turn=-10, head=(4, 0, 8), ra=SWORD_LOW, la=(150, 20, 10), flex=10)
gs_high = swing_pose(lean=-8, dy=0.1, turn=-14, head=(8, 0, 10), ra=SWORD_LOW, la=(172, 16, 8), flex=10)
gs_slam = swing_pose(step=10, lean=44, dy=-0.9, turn=6, head=(-30, 0, -4), ra=(20, 30), la=(64, 10, 6), flex=10)
gs_press = swing_pose(step=10, lean=46, dy=-0.95, turn=6, head=(-30, 0, -4), ra=(22, 30), la=(60, 10, 6), flex=10)
gs_up = swing_pose(step=6, lean=20, dy=-0.4, turn=2, head=(-12, 0, 0), ra=SWORD_LOW, la=(40, 12, 4), flex=10)
STRAND = seq("LotusStrand", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, gs_rise, SLOW_IN, 2 * F),
    (gs_rise, 4 * F),
    *tween(gs_rise, gs_high, ONE, F),
    (gs_high, 6 * F),                                 # startup ends at 16 frames
    (gs_slam, F),                                     # the slam: the strand goes
    (gs_press, 8 * F),
    *tween(gs_press, gs_up, EVEN, 2 * F),
    (gs_up, 4 * F),
    *tween(gs_up, ready, SETTLE, F),
    (ready, 2 * F),
]), 37, "LotusStrand"), "Ground strand (stage 2): arm raised high, a full-body slam of the palm into the floor.",
    ground=True, snaps=(6,))

# Stage 3: the heavy spike. A deep coil with the fungus arm drawn back, then a lunging thrust (a
# bone spike grows from the forearm, CombatFx). 14 / 4 / 20.
hs_coil = swing_pose(lean=0, turn=-30, dy=-0.1, head=(0, 0, 24), ra=SWORD_LOW, la=(-20, 24, -10), flex=10)
hs_deep = swing_pose(lean=-4, turn=-40, dy=-0.2, head=(2, 0, 30), ra=SWORD_LOW, la=(-40, 28, -14), flex=10)
hs_hit = swing_pose(step=16, lean=26, turn=30, dy=-0.35, head=(-20, 0, -22), ra=(4, 26), la=(96, 0, 10), flex=10)
hs_hold = swing_pose(step=18, lean=28, turn=32, dy=-0.4, head=(-22, 0, -24), ra=(2, 26), la=(98, 0, 12), flex=10)
HEAVY = seq("LotusHeavyStab", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, hs_coil, SLOW_IN, 1.5 * F),
    (hs_coil, 4 * F),
    *tween(hs_coil, hs_deep, ONE, F),
    (hs_deep, 5 * F),                                 # startup ends at 14 frames
    *tween(hs_deep, hs_hit, (0.33, 0.66), F),         # active 1-2: the thrust
    (hs_hit, F),
    (hs_hold, F),
    (hs_hold, 8 * F),
    *tween(hs_hold, ready, EVEN, 3 * F),
    (ready, 6 * F),
]), 38, "LotusHeavyStab"), "Heavy stab (stage 3): a deep coil, then a lunging thrust of the fungus arm.",
    ground=True)

# Impale: palm pressed toward the ground, then the hand clenches and yanks up: growth erupts under the
# airborne target. 12 / 3 / 20.
im_press = swing_pose(lean=18, dy=-0.3, head=(-10, 0, 0), ra=SWORD_LOW, la=(40, 16, 6), flex=10)
im_deep = swing_pose(lean=24, dy=-0.45, head=(-14, 0, 0), ra=SWORD_LOW, la=(30, 18, 6), flex=10)
im_yank = swing_pose(lean=-10, dy=0.1, head=(18, 0, 0), ra=(24, 26), la=(150, 12, 4), flex=10)
im_top = swing_pose(lean=-14, dy=0.15, head=(22, 0, 0), ra=(26, 28), la=(166, 10, 2), flex=10)
IMPALE = seq("LotusImpale", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, im_press, SLOW_IN, 2 * F),
    (im_press, 3 * F),
    *tween(im_press, im_deep, ONE, F),
    (im_deep, 3 * F),                                 # startup ends at 12 frames
    *tween(im_deep, im_yank, (0.35, 0.7), F),         # active: the yank up
    (im_yank, F),
    (im_top, 8 * F),
    *tween(im_top, ready, (0.35, 0.7), 3 * F),
    (ready, 6 * F),
]), 35, "LotusImpale"), "Impale: palm pressed toward the floor, then clenched and yanked skyward.", ground=True)

# =========================================================================================
# 3: SPORE
# =========================================================================================

# Stage 1: one spore flicked from the fungus hand. 9 / 1 / 14.
sf_back = swing_pose(lean=4, turn=-24, head=(-2, 0, 18), ra=SWORD_LOW, la=(60, 60, -10), flex=10)
sf_load = swing_pose(lean=6, turn=-30, head=(-4, 0, 22), ra=SWORD_LOW, la=(70, 70, -14), flex=10)
sf_flick = swing_pose(step=4, lean=12, turn=18, head=(-8, 0, -14), ra=(10, 24), la=(92, 6, 30), flex=10)
sf_follow = swing_pose(step=4, lean=12, turn=22, head=(-8, 0, -16), ra=(10, 24), la=(84, 8, 40), flex=10)
SPORE = seq("LotusSporeFlick", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, sf_back, SLOW_IN, 1.5 * F),
    (sf_back, 2 * F),
    *tween(sf_back, sf_load, ONE, F),
    (sf_load, 2 * F),                                 # startup ends at 9 frames
    *tween(sf_load, sf_flick, ONE, F),                # the release
    (sf_flick, 3 * F),
    (sf_follow, 5 * F),
    *tween(sf_follow, ready, EVEN, 2 * F),
    (ready, 2 * F),
]), 24, "LotusSporeFlick"), "Spore (stage 1): the fungus hand flicks a spore forward from the side.", ground=True)

# Stage 2: a fan of three: a wide backhand sweep across. 12 / 1 / 16.
fn_back = swing_pose(lean=6, turn=24, head=(-4, 0, -18), ra=SWORD_LOW, la=(80, 0, 70), flex=10)
fn_load = swing_pose(lean=8, turn=32, dy=-0.1, head=(-6, 0, -24), ra=SWORD_LOW, la=(86, 0, 80), flex=10)
fn_sweep = swing_pose(step=6, lean=14, turn=-20, head=(-10, 0, 18), ra=(10, 24), la=(88, 70, -8), flex=10)
fn_follow = swing_pose(step=6, lean=14, turn=-26, head=(-10, 0, 22), ra=(10, 24), la=(84, 80, -10), flex=10)
FAN = seq("LotusSporeFan", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, fn_back, SLOW_IN, 2 * F),
    (fn_back, 3 * F),
    *tween(fn_back, fn_load, ONE, F),
    (fn_load, 3 * F),                                 # startup ends at 12 frames
    *tween(fn_load, fn_sweep, (0.35, 0.7), F),        # the sweep: three spores fan out
    (fn_sweep, F),
    (fn_follow, 6 * F),
    *tween(fn_follow, ready, EVEN, 2 * F),
    (ready, 4 * F),
]), 29, "LotusSporeFan"), "Spore fan (stage 2): a wide backhand sweep that throws three spores.", ground=True)

# Stage 3: the beam. A long charge with the fungus arm pulled back and the sword hand bracing it,
# then both thrust forward and hold while the beam fires. 24 / 30 / 28.
bm_charge = swing_pose(lean=-6, turn=-26, dy=-0.15, head=(4, 0, 18), ra=(40, 10, 50), la=(10, 30, -10), flex=10)
bm_charge2 = swing_pose(lean=-8, turn=-32, dy=-0.25, head=(6, 0, 22), ra=(44, 10, 56), la=(-10, 34, -12), flex=10)
bm_fire = swing_pose(step=12, lean=14, turn=4, dy=-0.3, head=(-8, 0, -2), ra=(86, 4, 24), la=(92, 2, 10), flex=10)
bm_fire2 = swing_pose(step=12, lean=16, turn=4, dy=-0.34, head=(-10, 0, -2), ra=(88, 4, 26), la=(94, 2, 12), flex=10)
bm_spent = swing_pose(step=6, lean=22, turn=0, dy=-0.3, head=(-16, 0, 0), ra=(30, 20), la=(40, 20, 6), flex=10)
BEAM = seq("LotusBeam", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, bm_charge, SLOW_IN, 2 * F),
    (bm_charge, 6 * F),
    *tween(bm_charge, bm_charge2, ONE, F),
    (bm_charge2, 12 * F),                             # startup ends at 24 frames
    *tween(bm_charge2, bm_fire, ONE, F),              # the beam fires
    (bm_fire, 5 * F),
    (bm_fire2, 5 * F),
    (bm_fire, 5 * F),
    (bm_fire2, 5 * F),
    (bm_fire, 5 * F),
    (bm_fire2, 4 * F),                                # 30 active frames
    *tween(bm_fire2, bm_spent, EVEN, 3 * F),
    (bm_spent, 10 * F),
    *tween(bm_spent, ready, EVEN, 3 * F),
    (ready, 6 * F),
]), 82, "LotusBeam"), "Spore beam (stage 3): a long charge, both arms thrust forward and hold while it fires.",
    ground=True)

# =========================================================================================
# 4: GRAB
# =========================================================================================

# The reach: coil, then the fungus arm lunges out to grab (the growth covers the hand, CombatFx).
# Timed for the 16-frame stage 3 grab; 16 / 3 / 30.
gr_coil = swing_pose(lean=4, turn=-20, dy=-0.1, head=(-2, 0, 14), ra=SWORD_LOW, la=(30, 30, -6), flex=10)
gr_load = swing_pose(lean=6, turn=-28, dy=-0.2, head=(-4, 0, 20), ra=SWORD_LOW, la=(20, 36, -10), flex=10)
gr_reach = swing_pose(step=14, lean=24, turn=24, dy=-0.3, head=(-18, 0, -16), ra=(6, 26), la=(90, 10, 16), flex=10)
gr_reach2 = swing_pose(step=14, lean=26, turn=26, dy=-0.32, head=(-18, 0, -18), ra=(6, 26), la=(88, 12, 20), flex=10)
gr_miss = swing_pose(step=10, lean=28, turn=14, dy=-0.36, head=(-22, 0, -8), ra=(20, 26), la=(50, 16, 10), flex=10)
GRAB = seq("LotusGrab", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, gr_coil, SLOW_IN, 2 * F),
    (gr_coil, 4 * F),
    *tween(gr_coil, gr_load, ONE, F),
    (gr_load, 6 * F),                                 # startup ends at 16 frames
    *tween(gr_load, gr_reach, ONE, F),                # active: the grab
    (gr_reach, F),
    (gr_reach2, F),
    (gr_reach2, 6 * F),
    *tween(gr_reach2, gr_miss, EVEN, 3 * F),
    (gr_miss, 8 * F),                                 # the whiff: overextended, open
    *tween(gr_miss, ready, SETTLE, 3 * F),
    (ready, 4 * F),
]), 49, "LotusGrab"), "Grab: a coil, then the fungus arm lunges out; a miss leaves you overextended.", ground=True)

# Feast: holding the grabbed opponent while the growth eats. A loop the code plays for the hold.
fe_a = swing_pose(step=10, lean=18, turn=10, dy=-0.2, head=(-10, 0, -6), ra=(20, 26), la=(90, 10, 10), flex=10)
fe_b = swing_pose(step=10, lean=24, turn=14, dy=-0.3, head=(-16, 0, -10), ra=(26, 28), la=(80, 14, 16), flex=10)
FEAST = seq("LotusFeast", ACTION, True, cycle([fe_a, fe_b], [0.1, 0.1]),
            "Feast: gripping the grabbed opponent, lurching as the growth feeds.", ground=True)

# Held: caught by a grab or an impale. Arched, arms and legs hanging, twitching.
hd_a = air_pose(lean=-16, head=(20, 0, 0), ra=(30, 30), la=(26, 30), rl=(-6, 10), ll=(-12, 10))
hd_b = air_pose(lean=-20, head=(24, 0, 6), ra=(40, 36), la=(18, 26), rl=(-10, 12), ll=(-6, 8))
HELD = seq("LotusHeld", ACTION, True, cycle([hd_a, hd_b], [0.12, 0.12]),
           "Held by the fungus (grabbed or impaled): arched back, limbs hanging, twitching.")

# =========================================================================================
# R AND G
# =========================================================================================

# Heal channel: hunched, clutching the fungus arm to the chest while it drinks. Loop.
hl_a = swing_pose(lean=20, dy=-0.3, head=(-16, 0, 0), ra=(40, 10, 60), la=(60, 6, 50), flex=10)
hl_b = swing_pose(lean=24, dy=-0.36, head=(-20, 0, 4), ra=(44, 10, 62), la=(56, 6, 54), flex=10)
HEAL = seq("LotusHeal", ACTION, True, cycle([hl_a, hl_b], [0.15, 0.15]),
           "Heal channel: hunched, clutching the fungus arm to the chest, breathing with it.", ground=True)

# Rip out: the sword hand grabs the growth on the fungus arm and tears a chunk off. 10 / 1 / 14.
rp_grab = swing_pose(lean=16, dy=-0.2, turn=-16, head=(-12, 0, 14), ra=(60, 6, 70), la=(50, 20, 30), flex=10)
rp_hold = swing_pose(lean=20, dy=-0.25, turn=-20, head=(-14, 0, 18), ra=(64, 6, 74), la=(46, 22, 34), flex=10)
rp_tear = swing_pose(lean=-6, dy=0.05, turn=20, head=(10, 0, -14), ra=(110, 60, -10), la=(20, 30, 10), flex=10)
RIP = seq("LotusRipOut", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, rp_grab, SLOW_IN, 2 * F),
    (rp_grab, F),
    *tween(rp_grab, rp_hold, ONE, F),
    (rp_hold, 3 * F),                                 # startup ends at 10 frames
    *tween(rp_hold, rp_tear, (0.35, 0.7), F),         # the tear
    (rp_tear, 6 * F),
    *tween(rp_tear, ready, EVEN, 2 * F),
    (ready, 3 * F),
]), 25, "LotusRipOut"), "Rip out: the sword hand grabs the growth on the arm and tears a chunk off.", ground=True)

# The form: hunched as the growth surges, then a roar with the arms flung wide. 30 / 1 / 20.
fm_hunch = swing_pose(lean=30, dy=-0.4, head=(-24, 0, 0), ra=(20, 20, 40), la=(24, 20, 40), flex=10)
fm_deep = swing_pose(lean=38, dy=-0.55, head=(-28, 0, 0), ra=(10, 16, 50), la=(14, 16, 50), flex=10)
fm_roar = swing_pose(lean=-16, dy=0.1, head=(26, 0, 0), ra=(100, 70), la=(110, 80), flex=10)
fm_roar2 = swing_pose(lean=-18, dy=0.12, head=(28, 0, 0), ra=(104, 72), la=(114, 82), flex=10)
FORM = seq("LotusForm", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, fm_hunch, SLOW_IN, 3 * F),
    (fm_hunch, 8 * F),
    *tween(fm_hunch, fm_deep, ONE, 2 * F),
    (fm_deep, 13 * F),                                # startup ends at 30 frames
    *tween(fm_deep, fm_roar, (0.35, 0.7), F),         # the roar
    (fm_roar, 4 * F),
    (fm_roar2, 6 * F),
    *tween(fm_roar2, ready, (0.35, 0.7), 2 * F),
    (ready, 5 * F),
]), 51, "LotusForm"), "Stage 3 form: hunched as the growth surges over the body, then a roar, arms wide.",
    ground=True)

# Consumed: a stage 3 move missed and the fungus bites back. Doubled over clutching the arm. 20 frames.
cs_bite = swing_pose(lean=34, dy=-0.4, turn=-14, head=(-22, 0, 12), ra=(60, 6, 70), la=(20, 30, 20), flex=10)
cs_bite2 = swing_pose(lean=38, dy=-0.45, turn=-18, head=(-26, 0, 14), ra=(62, 6, 72), la=(14, 32, 22), flex=10)
CONSUMED = seq("LotusConsumed", ACTION, False, check_length(timeline([
    (ready, F),
    *tween(ready, cs_bite, (0.35, 0.7), F),
    (cs_bite, 2 * F),
    (cs_bite2, 8 * F),
    *tween(cs_bite2, ready, (0.5, 0.85), 2 * F),
    (ready, 3 * F),
]), 20, "LotusConsumed"), "Consumed: a stage 3 miss; doubled over clutching the fungus arm.", ground=True)

LOTUS = [STAB, STRAND, HEAVY, IMPALE, SPORE, FAN, BEAM, GRAB, FEAST, HELD, HEAL, RIP, FORM, CONSUMED]

_ = (plant, T)
