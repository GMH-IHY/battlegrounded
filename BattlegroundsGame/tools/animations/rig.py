"""R6 rig math: joints, pose -> Motor6D.Transform conversion, forward kinematics, mirroring.

Authoring space (character space): +X = character's right, +Y = up, -Z = forward.
Every limb angle is authored as a rotation of that limb *in the parent part's frame*,
pivoting at the joint, then converted to the Motor6D.Transform Roblox stores in a Pose.
"""
import numpy as np

def rx(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

def ry(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

def rz(d):
    a = np.radians(d); c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

def cf(x, y, z, *r):
    m = np.eye(4); m[:3, 3] = (x, y, z)
    if r:
        m[:3, :3] = np.array(r, dtype=float).reshape(3, 3)
    return m

def inv(m):
    o = np.eye(4); o[:3, :3] = m[:3, :3].T; o[:3, 3] = -m[:3, :3].T @ m[:3, 3]
    return o

# Standard R6 joints: name -> (Part0, Part1, C0, C1)
JOINTS = {
    "RootJoint":      ("HumanoidRootPart", "Torso",
                       cf(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Neck":           ("Torso", "Head",
                       cf(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Right Shoulder": ("Torso", "Right Arm",
                       cf(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Shoulder":  ("Torso", "Left Arm",
                       cf(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
    "Right Hip":      ("Torso", "Right Leg",
                       cf(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Hip":       ("Torso", "Left Leg",
                       cf(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
}
PART_OF_JOINT = {j: v[1] for j, v in JOINTS.items()}
SIZES = {"HumanoidRootPart": (2, 2, 1), "Torso": (2, 2, 1), "Head": (2, 1, 1),
         "Right Arm": (1, 2, 1), "Left Arm": (1, 2, 1), "Right Leg": (1, 2, 1), "Left Leg": (1, 2, 1)}

# ---- authoring helpers -------------------------------------------------------------
# A joint pose is a dict: pitch/yaw/roll in degrees (Ry(yaw) @ Rx(pitch) @ Rz(roll)), offset (x,y,z).
# Signs in raw terms: +pitch swings a hanging limb FORWARD but tips torso/head BACK;
# +yaw turns LEFT; +roll swings a hanging limb toward +X (right).

def limb(side, swing=0, out=0, twist=0, yaw=0):
    """Arm/leg. swing: + forward. out: + away from body. twist: + toe/palm turns outward. yaw: + swings plane rightward."""
    s = 1 if side == "R" else -1
    return {"pitch": swing, "roll": s * out, "yaw": -yaw + (-s * twist), "offset": (0, 0, 0)}

def body(lean=0, turn=0, tilt=0, dy=0, dz=0):
    """Torso (RootJoint) or head. lean: + forward. turn: + to the right. tilt: + top leans right. dy: + up. dz: + forward."""
    return {"pitch": -lean, "yaw": -turn, "roll": -tilt, "offset": (0, dy, -dz)}

def pose(root=None, head=None, ra=None, la=None, rl=None, ll=None):
    return {"RootJoint": root or body(), "Neck": head or body(),
            "Right Shoulder": ra or limb("R"), "Left Shoulder": la or limb("L"),
            "Right Hip": rl or limb("R"), "Left Hip": ll or limb("L")}

def mirror(p):
    swap = {"Right Shoulder": "Left Shoulder", "Left Shoulder": "Right Shoulder",
            "Right Hip": "Left Hip", "Left Hip": "Right Hip"}
    out = {}
    for j, v in p.items():
        if not isinstance(v, dict):  # flags such as "_planted"
            out[j] = v
            continue
        ox, oy, oz = v["offset"]
        out[swap.get(j, j)] = {"pitch": v["pitch"], "yaw": -v["yaw"], "roll": -v["roll"], "offset": (-ox, oy, oz)}
    return out

def rot(v):
    return ry(v["yaw"]) @ rx(v["pitch"]) @ rz(v["roll"])

def transform(joint, v):
    """Authored (parent-space rotation about the joint + offset) -> Motor6D.Transform."""
    rc = JOINTS[joint][2][:3, :3]
    t = np.eye(4)
    t[:3, :3] = rc.T @ rot(v) @ rc
    t[:3, 3] = rc.T @ np.array(v["offset"], dtype=float)
    return t

# ---- forward kinematics (for previews / sanity checks) ------------------------------
def fk(p, root_cf=None):
    world = {"HumanoidRootPart": root_cf if root_cf is not None else cf(0, 3, 0)}
    for j in ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]:
        p0, p1, c0, c1 = JOINTS[j]
        world[p1] = world[p0] @ c0 @ transform(j, p[j]) @ inv(c1)
    return world
