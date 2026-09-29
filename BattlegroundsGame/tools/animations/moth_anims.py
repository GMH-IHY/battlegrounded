"""Moth race animations (wings, antennae, lantern). Constant easing: every pose snaps.

Poses may key only SOME joints: a joint missing from the pose isn't animated by that track, so
e.g. the lantern charge (upper body) plays over walking legs. Wing / antenna joints:
  RightForewing, LeftForewing, RightHindwing, LeftHindwing (Torso), RightAntenna, LeftAntenna (Head).
  wing(flap, raise): flap + swings the wing tip FORWARD, - folds it BACK; raise + lifts the tip.
  antenna(back, out): back + sweeps it backward; out + tilts the tip away from the head's middle.
Authoring notes (Isaac): R6 has no knees/elbows, so bends happen at the hip / shoulder; exaggerate;
start slow, end fast (small first move, then the big one, then a recoil).
"""
import numpy as np
from rig import rx, ry, rz, transform, body, limb
from anims import P, one_shot, seq, ACTION, MOVEMENT

CORE = 1000  # Enum.AnimationPriority.Core: under everything (the wings' resting loop)

R6 = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
WINGS = ["RightForewing", "LeftForewing", "RightHindwing", "LeftHindwing"]
ANTENNAE = ["RightAntenna", "LeftAntenna"]


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
    """A keyframe pose: {joint: Transform}. r6 = a full pose() dict (converted), `only` limits which
    R6 joints are keyed. extra: dicts from wings()/antennae()."""
    out = {}
    if r6 is not None:
        for j in (only or R6):
            out[j] = transform(j, r6[j])
    for d in extra.values():
        out.update(d)
    return out


# Wings at rest: folded back a little, tips up a touch.
REST_FORE, REST_HIND = (-32, 6), (-28, -4)


# ---------------- MothWings: resting loop under everything -----------------------------------
w_rest = K(w=wings(REST_FORE, REST_HIND), a=antennae(8, 4))
w_twitch1 = K(w=wings((-12, 12), (-14, 2)), a=antennae(4, 8))
w_twitch2 = K(w=wings((-40, 2), (-34, -6)), a=antennae(12, 2))
w_twitch3 = K(w=wings((-20, 9), (-20, 0)), a=antennae(6, 6))
WINGS_REST = seq("MothWings", CORE, True,
                 [(0.0, w_rest), (1.9, w_twitch1), (1.98, w_twitch2), (2.06, w_twitch3), (2.14, w_rest), (3.2, w_rest)],
                 "Wings folded back; every ~2 s a quick double twitch (snaps).")


# ---------------- MothWingFlight: the tap flight (0.35 s) ------------------------------------
def superman(lean, arms_back, legs, head=None):
    return P(lean=lean, head_lean=head,
             ra=(-arms_back, 18), la=(-arms_back, 18),
             rl=(-legs[0], 4), ll=(-legs[1], 4))

wf0 = K(superman(25, 40, (8, 14)), w=wings((-70, 28), (-60, 20)), a=antennae(25, 6))       # wings wound back
wf1 = K(superman(60, 85, (20, 32)), w=wings((30, -18), (24, -24)), a=antennae(40, 2))       # big downstroke, launch
wf2 = K(superman(62, 88, (24, 36)), w=wings((-45, 26), (-40, 18)), a=antennae(42, 2))
wf3 = K(superman(62, 88, (28, 34)), w=wings((25, -16), (20, -20)), a=antennae(40, 2))
wf4 = K(superman(55, 70, (22, 30)), w=wings((-38, 20), (-34, 14)), a=antennae(34, 4))
WING_FLIGHT = seq("MothWingFlight", ACTION, False,
                  one_shot([(0.0, wf0), (0.04, wf1), (0.12, wf2), (0.19, wf3), (0.27, wf4)], 0.36),
                  "Tap flight: wind the wings back, then a big downstroke that throws the body flat like a "
                  "dive; two more beats; arms swept back, legs trailing.")


# ---------------- MothFly: flying (lantern light / tag), loop -------------------------------
def flyer(tilt=0.0):
    return P(lean=38, tilt=tilt, head_lean=-24,
             ra=(-30, 30), la=(-30, 30), rl=(-18, 6), ll=(-8, 4))

fly_up = K(flyer(2), w=wings((-50, 30), (-44, 22)), a=antennae(32, 6))
fly_mid = K(flyer(0), w=wings((5, 4), (2, 0)), a=antennae(30, 5))
fly_down = K(flyer(-2), w=wings((30, -22), (24, -26)), a=antennae(28, 4))
fly_rec = K(flyer(0), w=wings((-15, 10), (-14, 6)), a=antennae(30, 5))
FLY = seq("MothFly", ACTION, True,
          [(0.0, fly_up), (0.08, fly_mid), (0.14, fly_down), (0.22, fly_rec), (0.3, fly_up)],
          "Flying: body leaning into the flight, arms out and back, legs hanging behind, wings beating "
          "(slow upstroke, fast downstroke).")


# ---------------- LanternCharge: hold (upper body only), loop -------------------------------
UPPER_R = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder"]

def charge(arm_up, shake=0.0):
    return P(lean=-6, turn=28, head_turn=-24, head_lean=4,
             ra=(arm_up, 16 + shake), la=(70, 8), la_in=18)

ch_a = K(charge(196), only=UPPER_R)
ch_b = K(charge(203, 3), only=UPPER_R)
CHARGE = seq("LanternCharge", ACTION, True,
             [(0.0, ch_a), (0.12, ch_b), (0.24, ch_a)],
             "Holding Ctrl: lantern hauled up and back over the right shoulder, body twisted away, left "
             "arm out front aiming; a small shake while it charges.")


# ---------------- LanternThrow: release, one-shot (upper body) ------------------------------
th0 = K(P(lean=-8, turn=32, head_turn=-26, ra=(212, 18), la=(75, 8), la_in=18), only=UPPER_R)    # last pull back
th1 = K(P(lean=14, turn=-18, head_turn=14, ra=(118, 6), la=(10, 20)), only=UPPER_R)              # whip
th2 = K(P(lean=24, turn=-34, head_turn=26, ra=(62, 0), ra_in=24, la=(-24, 18)), only=UPPER_R)    # follow-through
th3 = K(P(lean=8, turn=-12, head_turn=10, ra=(24, 4), la=(-8, 10)), only=UPPER_R)                # recoil
THROW = seq("LanternThrow", ACTION, False,
            one_shot([(0.0, th0), (0.04, th1), (0.09, th2), (0.2, th3)], 0.32),
            "Release: a last tiny pull back, then the arm whips over the top, the body unwinds past "
            "centre, follow-through across the body, small recoil.")


# ---------------- LanternSuspend: press in the air, one-shot (left arm + head) --------------
UPPER_L = ["Neck", "Left Shoulder"]
su0 = K(P(head_lean=-6, la=(95, 6), la_in=8), only=UPPER_L)
su1 = K(P(head_lean=-10, la=(138, 4), la_in=12), only=UPPER_L)      # snap point up at it
su2 = K(P(head_lean=-8, la=(128, 6), la_in=12), only=UPPER_L)
su3 = K(P(head_lean=-2, la=(40, 8)), only=UPPER_L)
SUSPEND = seq("LanternSuspend", ACTION, False,
              one_shot([(0.0, su0), (0.03, su1), (0.14, su2), (0.22, su3)], 0.3),
              "Press in the air: the left hand snaps up and points at the lantern to hold it there.")

MOTH = [WINGS_REST, WING_FLIGHT, FLY, CHARGE, THROW, SUSPEND]
