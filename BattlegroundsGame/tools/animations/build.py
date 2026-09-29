"""Writes every animation into the place as KeyframeSequences (constant easing: poses snap).

    python tools/animations/build.py [place.rbxlx] [--only Name,Name] [--rig]

Sequences go to ServerStorage > RBX_ANIMSAVES > AnimRig_R6, where the Animation Editor lists them
and StudioAnimationMirror copies them for playtests. A sequence with the same name is replaced;
any other sequence (for example one you made in Studio) is left alone.

Workspace > AnimRig_R6 (the anchored R6 dummy the editor poses) is created if it's missing.
--rig rebuilds it from scratch, which drops anything attached to it by hand.

Every animation module lists (time, pose) keys. A pose maps joint names to either an authored
dict (rig.py: pitch/yaw/roll/offset, converted with rig.transform) or a ready 4x4 Transform
(extra bones such as the Moth's wings). Joints missing from a pose aren't keyed, so partial poses
layer over other animations.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import rbxlx  # noqa: E402
from rbxlx import item, add, add_cf, add_v3, child, fmt  # noqa: E402
from rig import JOINTS, SIZES, transform, cf, ry  # noqa: E402
from catalog import ALL  # noqa: E402

PLACE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "BattlegroundsGame.rbxlx")
RIG_NAME = "AnimRig_R6"
RIG_CF = cf(0, 3, -30) @ np.block([[ry(180), np.zeros((3, 1))], [np.zeros((1, 3)), np.ones((1, 1))]])
COLORS = {"Head": (245, 205, 48), "Torso": (13, 105, 172), "Right Arm": (245, 205, 48),
          "Left Arm": (245, 205, 48), "Right Leg": (75, 151, 75), "Left Leg": (75, 151, 75),
          "HumanoidRootPart": (163, 162, 165)}

# Joint -> the part its Pose is named after, and where that Pose hangs in the Keyframe tree.
PART_OF = {"RootJoint": "Torso", "Neck": "Head", "Right Shoulder": "Right Arm", "Left Shoulder": "Left Arm",
           "Right Hip": "Right Leg", "Left Hip": "Left Leg"}
TORSO_CHILDREN = ["Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg",
                  "RightForewing", "LeftForewing", "RightHindwing", "LeftHindwing"]
HEAD_CHILDREN = ["RightAntenna", "LeftAntenna"]


# ---------------- rig -------------------------------------------------------------------
def build_rig():
    model, mp = item("Model", RIG_NAME)
    world = {"HumanoidRootPart": RIG_CF}
    for j, (p0, p1, c0, c1) in JOINTS.items():
        world[p1] = world[p0] @ c0 @ np.linalg.inv(c1)
    parts = {}
    for name in ["HumanoidRootPart", "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]:
        part, pp = item("Part", name, model)
        add_cf(pp, "CFrame", world[name])
        add_v3(pp, "size", SIZES[name])
        add(pp, "bool", "Anchored", "true" if name == "HumanoidRootPart" else "false")
        add(pp, "bool", "CanCollide", "false")
        add(pp, "bool", "CanQuery", "true")
        add(pp, "bool", "CanTouch", "false")
        add(pp, "float", "Transparency", 1 if name == "HumanoidRootPart" else 0)
        add(pp, "token", "TopSurface", 0)
        add(pp, "token", "BottomSurface", 0)
        add(pp, "Color3uint8", "Color3uint8", rbxlx.color_int(COLORS[name]))
        parts[name] = part
    head = parts["Head"]
    _, mep = item("SpecialMesh", "Mesh", head)
    add(mep, "token", "MeshType", 0)
    add_v3(mep, "Scale", (1.25, 1.25, 1.25))
    _, fp = item("Decal", "face", head)
    add(fp, "Content", "Texture")
    rbxlx.etree.SubElement(fp[-1], "url").text = "rbxasset://textures/face.png"
    add(fp, "token", "Face", 5)
    for j, (p0, p1, c0, c1) in JOINTS.items():
        _, pr = item("Motor6D", j, parts[p0])
        add_cf(pr, "C0", c0)
        add_cf(pr, "C1", c1)
        add(pr, "Ref", "Part0", parts[p0].get("referent"))
        add(pr, "Ref", "Part1", parts[p1].get("referent"))
    hum, hp = item("Humanoid", "Humanoid", model)
    add(hp, "token", "RigType", 0)
    add(hp, "token", "DisplayDistanceType", 2)
    item("Animator", "Animator", hum)
    add(mp, "Ref", "PrimaryPart", parts["HumanoidRootPart"].get("referent"))
    return model


# ---------------- animations ------------------------------------------------------------
def constant_keys(keys):
    """Anim modules list each pose at the time it should APPEAR and hold until the next one.
    Roblox's Constant easing works the other way: between two keyframes it shows the LATER
    keyframe's pose (checked in Studio: at t=0.25 and 0.30 a walk with keys at 0.24/0.36 shows
    the 0.36 pose). So each pose is written at the END of the span it should cover."""
    out = [keys[0]]
    for i in range(1, len(keys)):
        out.append((keys[i][0], keys[i - 1][1]))
    return out


def keyed_transforms(p):
    """{part name: Motor6D.Transform} for the joints this pose keys."""
    out = {}
    for joint, v in p.items():
        if isinstance(v, dict):
            out[PART_OF[joint]] = transform(joint, v)
        elif isinstance(v, np.ndarray):
            out[PART_OF.get(joint, joint)] = v
    return out


def pose_el(parent, name, m, weight):
    p, pp = item("Pose", name, parent)
    add_cf(pp, "CFrame", m)
    add(pp, "token", "EasingDirection", 0)
    add(pp, "token", "EasingStyle", 1)  # PoseEasingStyle.Constant: snap, no tweening
    add(pp, "float", "Weight", weight)
    add(pp, "float", "MaskWeight", 0)
    return p


def build_seq(anim):
    ks, kp = item("KeyframeSequence", anim["name"])
    add(kp, "bool", "Loop", "true" if anim["loop"] else "false")
    add(kp, "token", "Priority", anim["priority"])
    for t, p in constant_keys(anim["keys"]):
        by_part = keyed_transforms(p)
        kf, kfp = item("Keyframe", "Keyframe", ks)
        add(kfp, "float", "Time", fmt(t))
        hrp = pose_el(kf, "HumanoidRootPart", np.eye(4), 0)
        torso = pose_el(hrp, "Torso", by_part.get("Torso", np.eye(4)), 1 if "Torso" in by_part else 0)
        for part in TORSO_CHILDREN:
            needed_for_head = part == "Head" and any(c in by_part for c in HEAD_CHILDREN)
            if part in by_part or needed_for_head:
                el = pose_el(torso, part, by_part.get(part, np.eye(4)), 1 if part in by_part else 0)
                if part == "Head":
                    for c in HEAD_CHILDREN:
                        if c in by_part:
                            pose_el(el, c, by_part[c], 1)
    return ks


def main(argv):
    place, only, rebuild_rig = PLACE, [], False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--only":
            only = [n for n in args.pop(0).split(",") if n]
        elif a == "--rig":
            rebuild_rig = True
        else:
            place = a
    unknown = [n for n in only if n not in {x["name"] for x in ALL}]
    if unknown:
        raise SystemExit("unknown animation(s): " + ", ".join(unknown))

    tree = rbxlx.load(place)
    root = tree.getroot()
    ws, ss = child(root, "Workspace"), child(root, "ServerStorage")
    rig = child(ws, "Model", RIG_NAME)
    if rig is None or rebuild_rig:
        if rig is not None:
            ws.remove(rig)
        rig = build_rig()
        ws.append(rig)
        print("built", RIG_NAME)
    saves = child(ss, name="RBX_ANIMSAVES")
    if saves is None:
        saves, _ = item("Model", "RBX_ANIMSAVES", ss)
    holder = child(saves, name=RIG_NAME)
    if holder is None:
        holder, hp = item("ObjectValue", RIG_NAME, saves)
        add(hp, "Ref", "Value", rig.get("referent"))
    else:
        value = holder.find("Properties/Ref[@name='Value']")
        value.text = rig.get("referent")

    count = 0
    for anim in ALL:
        if only and anim["name"] not in only:
            continue
        new = build_seq(anim)
        old = child(holder, "KeyframeSequence", anim["name"])
        if old is not None:
            holder.replace(old, new)
        else:
            holder.append(new)
        count += 1
    rbxlx.save(tree, place)
    print(f"wrote {count} animation(s) to {place}")


if __name__ == "__main__":
    main(sys.argv[1:])
