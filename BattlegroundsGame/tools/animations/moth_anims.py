"""Moth race animations (paper wings, antennae, lantern). Constant easing: every pose snaps.

Poses may key only SOME joints: a joint missing from the pose isn't animated by that track, so
e.g. the lantern charge (upper body) plays over walking legs. Wing / antenna joints:
  RightForewing, LeftForewing, RightHindwing, LeftHindwing (Torso), RightAntenna, LeftAntenna (Head).
  wing(flap, raise): flap + swings the wing tip FORWARD, - folds it BACK; raise + lifts the tip.
  antenna(back, out): back + sweeps it backward; out + tilts the tip away from the head's middle.
At rest the plates fold back into an X across the back (tools/models/moth_wings.py).
"""
import numpy as np
from rig import rx, ry, rz, transform
from poses import P, seq, UPPER, ACTION, CORE, R6
from timing import timeline, tween, ONE, SLOW_IN, SLOW_OUT, SETTLE, EVEN


def m4(r):
    m = np.eye(4)
    m[:3, :3] = r
    return m


def wing_t(flap, raise_, left):
    s = -1 if left else 1
    return m4(ry(s * flap) @ rz(s * raise_))


def antenna_t(back, out, left):
    s = -1 if left else 1
    return m4(rx(back) @ rz(-s * out))


def wings(fore=(0, 0), hind=(0, 0)):
    """{joint: Transform} for all four wings; fore/hind = (flap, raise), mirrored left/right."""
    return {"RightForewing": wing_t(*fore, False), "LeftForewing": wing_t(*fore, True),
            "RightHindwing": wing_t(*hind, False), "LeftHindwing": wing_t(*hind, True)}


def antennae(back=0, out=0):
    return {"RightAntenna": antenna_t(back, out, False), "LeftAntenna": antenna_t(back, out, True)}


def K(r6=None, only=None, **extra):
    """A keyframe pose: {joint: Transform}. r6 = a full pose dict (converted), `only` limits which
    R6 joints are keyed. extra: dicts from wings() / antennae()."""
    out = {}
    if r6 is not None:
        for j in (only or R6):
            out[j] = transform(j, r6[j])
    for d in extra.values():
        out.update(d)
    return out


# Wings at rest: folded back into the X, tips up a touch.
REST_FORE, REST_HIND = (-32, 6), (-28, -4)

# ---------------- MothWings: resting loop under everything (Core priority) -------------------
# Folded; every ~2 s a quick double twitch, each twitch with an in-between on the way out and back.
w_rest = K(w=wings(REST_FORE, REST_HIND), a=antennae(8, 4))
w_twitch1 = K(w=wings((-12, 12), (-14, 2)), a=antennae(4, 8))
w_twitch2 = K(w=wings((-40, 2), (-34, -6)), a=antennae(12, 2))
WINGS_REST = seq("MothWings", CORE, True, timeline([
    (w_rest, 1.9),
    *tween(w_rest, w_twitch1, ONE, 0.04),
    (w_twitch1, 0.06),
    (w_twitch2, 0.06),
    *tween(w_twitch2, w_rest, SETTLE, 0.04),
    (w_rest, 1.02),
], loop=True), "Wings folded into an X; every ~2 s a quick double twitch with in-betweens.")


# ---------------- MothWingFlight: the tap flight (0.36 s) ------------------------------------
def superman(lean, arms_back, legs, head=None):
    return P(lean=lean, head_lean=head, ra=(-arms_back, 18), la=(-arms_back, 18),
             rl=(-legs[0], 4), ll=(-legs[1], 4))


wf_load = K(superman(12, 20, (4, 8)), w=wings((-50, 18), (-44, 12)), a=antennae(16, 5))
wf_wind = K(superman(25, 40, (8, 14)), w=wings((-70, 28), (-60, 20)), a=antennae(25, 6))       # wings wound back
wf_down = K(superman(60, 85, (20, 32)), w=wings((30, -18), (24, -24)), a=antennae(40, 2))       # big downstroke
wf_up = K(superman(62, 88, (24, 36)), w=wings((-45, 26), (-40, 18)), a=antennae(42, 2))
wf_down2 = K(superman(62, 88, (28, 34)), w=wings((25, -16), (20, -20)), a=antennae(40, 2))
wf_glide = K(superman(55, 70, (22, 30)), w=wings((-38, 20), (-34, 14)), a=antennae(34, 4))
WING_FLIGHT = seq("MothWingFlight", ACTION, False, timeline([
    (wf_load, 0.02),
    (wf_wind, 0.03),
    *tween(wf_wind, wf_down, SLOW_IN, 0.02),
    (wf_down, 0.06),
    *tween(wf_down, wf_up, ONE, 0.03),
    (wf_up, 0.04),
    *tween(wf_up, wf_down2, ONE, 0.03),
    (wf_down2, 0.04),
    *tween(wf_down2, wf_glide, SLOW_OUT, 0.02),
    (wf_glide, 0.05),
]), "Tap flight: wind the wings back, then a big downstroke that throws the body flat like a dive; "
    "two more beats with in-betweens; settles into a glide.")


# ---------------- MothFly: flying (lantern light / tag), loop -------------------------------
def flyer(tilt=0.0):
    return P(lean=38, tilt=tilt, head_lean=-24, ra=(-30, 30), la=(-30, 30), rl=(-18, 6), ll=(-8, 4))


fly_up = K(flyer(2), w=wings((-50, 30), (-44, 22)), a=antennae(32, 6))
fly_mid = K(flyer(0), w=wings((5, 4), (2, 0)), a=antennae(30, 5))
fly_down = K(flyer(-2), w=wings((30, -22), (24, -26)), a=antennae(28, 4))
fly_rec = K(flyer(0), w=wings((-15, 10), (-14, 6)), a=antennae(30, 5))
FLY = seq("MothFly", ACTION, True, timeline([
    (fly_up, 0.08), (fly_mid, 0.06), (fly_down, 0.08), (fly_rec, 0.08),
], loop=True), "Flying: body leaning into the flight, arms out and back, legs trailing, wings beating "
    "(slow upstroke, fast downstroke).")


# ---------------- LanternCharge: hold (upper body only), loop -------------------------------
def charge(arm_up, shake=0.0):
    return P(lean=-6, turn=28, head_turn=-24, head_lean=4, ra=(arm_up, 16 + shake), la=(70, 8), la_in=18)


ch_a = K(charge(196), only=UPPER)
ch_b = K(charge(203, 3), only=UPPER)
CHARGE = seq("LanternCharge", ACTION, True, timeline([(ch_a, 0.12), (ch_b, 0.12)], loop=True),
             "Holding Ctrl: lantern hauled up and back over the right shoulder, body twisted away, left "
             "arm out front aiming; a small shake while it charges.")


# ---------------- LanternThrow: release, one-shot (upper body) ------------------------------
th_pull = K(P(lean=-8, turn=32, head_turn=-26, ra=(212, 18), la=(75, 8), la_in=18), only=UPPER)
th_whip = K(P(lean=14, turn=-18, head_turn=14, ra=(118, 6), la=(10, 20)), only=UPPER)
th_follow = K(P(lean=24, turn=-34, head_turn=26, ra=(62, 0), ra_in=24, la=(-24, 18)), only=UPPER)
th_recoil = K(P(lean=8, turn=-12, head_turn=10, ra=(24, 4), la=(-8, 10)), only=UPPER)
th_rest = K(P(lean=2, turn=-4, head_turn=3, ra=(8, 4), la=(2, 6)), only=UPPER)
THROW = seq("LanternThrow", ACTION, False, timeline([
    (ch_a, 0.02),
    *tween(ch_a, th_pull, ONE, 0.02),
    (th_pull, 0.02),
    *tween(th_pull, th_whip, EVEN, 0.017),
    (th_whip, 0.03),
    *tween(th_whip, th_follow, ONE, 0.02),
    (th_follow, 0.06),
    *tween(th_follow, th_recoil, ONE, 0.03),
    (th_recoil, 0.05),
    *tween(th_recoil, th_rest, ONE, 0.03),
    (th_rest, 0.02),
]), "Release: a last pull back from the charge pose, the arm whips over the top, the body unwinds past "
    "centre, follow-through across the body, recoil and settle.")


# ---------------- LanternSuspend: press in the air, one-shot (left arm + head) --------------
LEFT_ARM = ["Neck", "Left Shoulder"]
su_rest = K(P(head_lean=-4, la=(60, 6), la_in=6), only=LEFT_ARM)
su_raise = K(P(head_lean=-6, la=(95, 6), la_in=8), only=LEFT_ARM)
su_point = K(P(head_lean=-10, la=(138, 4), la_in=12), only=LEFT_ARM)      # point up at it
su_hold = K(P(head_lean=-8, la=(128, 6), la_in=12), only=LEFT_ARM)
su_drop = K(P(head_lean=-2, la=(40, 8)), only=LEFT_ARM)
SUSPEND = seq("LanternSuspend", ACTION, False, timeline([
    (su_rest, 0.02),
    (su_raise, 0.02),
    *tween(su_raise, su_point, ONE, 0.017),
    (su_point, 0.05),
    (su_hold, 0.06),
    *tween(su_hold, su_drop, EVEN, 0.03),
    (su_drop, 0.05),
]), "Press in the air: the left hand snaps up and points at the lantern to hold it there.")

MOTH = [WINGS_REST, WING_FLIGHT, FLY, CHARGE, THROW, SUSPEND]
