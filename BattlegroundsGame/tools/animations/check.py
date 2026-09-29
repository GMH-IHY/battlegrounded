"""Lowest point of each pose (ground is y=0 with the root at y=3 like a standing R6)."""
import itertools, sys, numpy as np
from rig import fk, SIZES
from anims import DASH
def lowest(p):
    w = fk(p); lo = 9
    for part in ["Right Leg","Left Leg","Right Arm","Left Arm","Torso","Head"]:
        sx,sy,sz=(s/2 for s in SIZES[part])
        for c in itertools.product([-sx,sx],[-sy,sy],[-sz,sz]):
            y=(w[part]@np.array([*c,1]))[1]; lo=min(lo,y)
    return lo
for a in DASH:
    print(a["name"], " ".join(f"{t:.2f}:{lowest(p):+.2f}" for t,p in a["keys"][:-1]))
