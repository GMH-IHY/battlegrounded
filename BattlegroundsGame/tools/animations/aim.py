"""Aim limbs at WORLD directions (x = right, y = up, -z = forward), solved numerically.
Lets a pose be written as 'this leg points down and toward the dash' instead of joint angles."""
import numpy as np
from scipy.optimize import minimize
from rig import fk, pose, body

JOINT = {"ra": "Right Shoulder", "la": "Left Shoulder", "rl": "Right Hip", "ll": "Left Hip"}
PART = {"ra": "Right Arm", "la": "Left Arm", "rl": "Right Leg", "ll": "Left Leg"}


def _dir(p, key):
    w = fk(p)[PART[key]]
    top = w @ np.array([0, 1, 0, 1]); end = w @ np.array([0, -1, 0, 1])
    d = (end - top)[:3]
    return d / np.linalg.norm(d)


def aimed(root, head, targets, twist=None):
    """root/head: body(...) dicts. targets: {"ra": (x,y,z), ...} world directions (shoulder->hand,
    hip->foot). Returns a full pose."""
    p = pose(root=root, head=head)
    for key, t in targets.items():
        t = np.array(t, float); t /= np.linalg.norm(t)
        j = JOINT[key]
        def cost(v):
            p[j] = {"pitch": v[0], "roll": v[1], "yaw": (twist or {}).get(key, 0.0), "offset": (0, 0, 0)}
            return 1 - _dir(p, key) @ t + 2e-6 * (v[0] ** 2 + v[1] ** 2)
        best = None
        for p0 in (-90, 0, 90):
            for r0 in (-60, 0, 60):
                res = minimize(cost, [p0, r0], method="Nelder-Mead", options={"xatol": 0.2, "fatol": 1e-7})
                if best is None or res.fun < best.fun:
                    best = res
        cost(best.x)
    return p
