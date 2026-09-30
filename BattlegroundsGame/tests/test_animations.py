"""Offline checks for every animation in tools/animations/catalog.py.

    cd BattlegroundsGame && python -m pytest tests

They catch the things that make stepped animation look wrong in game before Studio is opened:
broken timing, pops (a joint jumping too far between two poses), starts and ends with no
in-betweens, feet floating or sinking, and names that don't match what the Luau code loads.
"""
import os
import re
import sys

import numpy as np
import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "animations"))
from catalog import ALL  # noqa: E402
from rig import JOINTS, transform, inv, pose as rest_pose  # noqa: E402

SRC = os.path.join(ROOT, "src")
R6 = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
REST = rest_pose()

MIN_HOLD = 1 / 60 - 2e-4          # nothing shorter than one frame (keys are rounded to 0.1 ms)
MAX_STEP_DEG = 75                  # biggest turn of any joint between two poses (snaps excepted)
EDGE_STEP_DEG = 42                 # first and last move of a one-shot: eased, not a jump
FOOT_LOW, FOOT_HIGH = -0.3, 0.3    # ground animations: lowest foot vs the floor (studs)
MIN_EDGE_LENGTH = 0.2              # one-shots shorter than this are exempt from the edge rule

IDS = list(ALL)
NAMES = [a["name"] for a in ALL]


def rot(joint, v):
    return (transform(joint, v) if isinstance(v, dict) else v)[:3, :3]


def angle_between(a, b):
    c = (np.trace(a.T @ b) - 1) / 2
    return float(np.degrees(np.arccos(np.clip(c, -1, 1))))


def step_degrees(p, q):
    """Largest joint rotation between two poses (joints keyed in both)."""
    worst = 0.0
    for joint in set(p) & set(q):
        if joint.startswith("_"):
            continue
        worst = max(worst, angle_between(rot(joint, p[joint]), rot(joint, q[joint])))
    return worst


def distinct_steps(anim):
    """[(index of the later pose, degrees)] between consecutive keys, skipping the closing copy."""
    keys = anim["keys"]
    out = []
    last = len(keys) - 1
    for i in range(1, len(keys)):
        if i == last and not anim["loop"]:
            break  # the closing key repeats the last pose
        out.append((i, step_degrees(keys[i - 1][1], keys[i][1])))
    return out


def world(p):
    w = {"HumanoidRootPart": np.array([[1, 0, 0, 0], [0, 1, 0, 3], [0, 0, 1, 0], [0, 0, 0, 1]], float)}
    for j in R6:
        p0, p1, c0, c1 = JOINTS[j]
        v = p.get(j, REST[j])
        t = transform(j, v) if isinstance(v, dict) else v
        w[p1] = w[p0] @ c0 @ t @ inv(c1)
    return w


def lowest_foot(p):
    """Height of the lower foot: the centre of a leg's bottom face (R6 hips pivot at the leg's outer
    top edge, so a splayed leg dips an inner corner that isn't really the foot)."""
    w = world(p)
    return min((w[leg] @ np.array([0, -1, 0, 1]))[1] for leg in ("Right Leg", "Left Leg"))


def luau_ids():
    text = open(os.path.join(SRC, "shared", "Movement", "AnimationConfig.luau"), encoding="utf-8").read()
    block = re.search(r"Names = \{(.*?)\n\t\} ::", text, re.S).group(1)
    return re.findall(r"^\s*(\w+) = true", block, re.M)


# ---------------- structure ----------------------------------------------------------------
def test_names_are_unique():
    assert len(NAMES) == len(set(NAMES))


@pytest.mark.parametrize("anim", IDS, ids=NAMES)
def test_timing(anim):
    keys = anim["keys"]
    assert len(keys) >= 2, "needs at least a pose and its end key"
    assert keys[0][0] == 0, "starts at 0"
    for (t0, _), (t1, _) in zip(keys, keys[1:]):
        assert t1 - t0 >= MIN_HOLD, f"hold shorter than a frame at {t0:.3f}s"
    if anim["loop"]:
        assert step_degrees(keys[0][1], keys[-1][1]) < 0.05, "a loop must end on its first pose"


@pytest.mark.parametrize("anim", IDS, ids=NAMES)
def test_no_pops(anim):
    for i, deg in distinct_steps(anim):
        if i in anim.get("snaps", ()):
            continue
        assert deg <= MAX_STEP_DEG, f"pose #{i + 1} jumps {deg:.0f} deg from the one before (max {MAX_STEP_DEG})"


@pytest.mark.parametrize("anim", [a for a in ALL if not a["loop"]], ids=[a["name"] for a in ALL if not a["loop"]])
def test_eased_start_and_end(anim):
    """One-shots start with a small move (anticipation) and end with a small one (settle)."""
    if anim["keys"][-1][0] < MIN_EDGE_LENGTH:
        pytest.skip("too short to ease")
    steps = distinct_steps(anim)
    if len(steps) < 2:
        pytest.skip("single pose")
    first, last = steps[0][1], steps[-1][1]
    assert first <= EDGE_STEP_DEG, f"first move is {first:.0f} deg; add an in-between (max {EDGE_STEP_DEG})"
    assert last <= EDGE_STEP_DEG, f"last move is {last:.0f} deg; add a settle in-between (max {EDGE_STEP_DEG})"


@pytest.mark.parametrize("anim", [a for a in ALL if a.get("ground")], ids=[a["name"] for a in ALL if a.get("ground")])
def test_feet_on_the_floor(anim):
    for t, p in anim["keys"]:
        y = lowest_foot(p)
        assert FOOT_LOW <= y <= FOOT_HIGH, f"at {t:.2f}s the lowest foot is at {y:+.2f} (floor = 0)"


# ---------------- names vs the game --------------------------------------------------------
def test_animation_config_matches_catalog():
    ids = luau_ids()
    missing_in_config = sorted(set(NAMES) - set(ids))
    unknown_in_config = sorted(set(ids) - set(NAMES))
    assert not missing_in_config, f"add to AnimationConfig.Names: {missing_in_config}"
    assert not unknown_in_config, f"AnimationConfig.Names names no animation: {unknown_in_config}"


def test_code_only_loads_known_animations():
    used = set()
    for folder, _, files in os.walk(SRC):
        for f in files:
            if f.endswith(".luau"):
                text = open(os.path.join(folder, f), encoding="utf-8").read()
                used |= set(re.findall(r'AnimationLibrary\.Get\("(\w+)"\)', text))
    assert not sorted(used - set(NAMES)), f"loaded but not generated: {sorted(used - set(NAMES))}"
