"""Adds (or replaces) the parkour + dash KeyframeSequences in a saved place, and patches changed
ModuleScripts' Source.

Usage: [ONLY=Name,Name] python parkour_build.py <in.rbxlx> <out.rbxlx> [ModulePath=file.luau ...]
  e.g. ReplicatedStorage/Movement/WallHop=src/shared/Movement/WallHop.luau

Sequences go to ServerStorage > RBX_ANIMSAVES > AnimRig_R6 (where StudioAnimationMirror reads them).
Poses only key the joints the pose has; parents of keyed joints are added as empty containers.
"""
import sys
import numpy as np
from lxml import etree
from build import item, add, add_cf, child, name_of, fmt, constant_keys, RIG_NAME
from rig import transform
from parkour_anims import ALL_NEW

PART_OF = {"RootJoint": "Torso", "Neck": "Head", "Right Shoulder": "Right Arm", "Left Shoulder": "Left Arm",
           "Right Hip": "Right Leg", "Left Hip": "Left Leg"}
LIMBS = ["Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]


def pose_el(parent, name, m, weight):
    p, pp = item("Pose", name, parent)
    add_cf(pp, "CFrame", m)
    add(pp, "token", "EasingDirection", 0)
    add(pp, "token", "EasingStyle", 1)  # Constant: snap
    add(pp, "float", "Weight", weight)
    add(pp, "float", "MaskWeight", 0)
    return p


def build_seq(anim):
    ks, kp = item("KeyframeSequence", anim["name"])
    add(kp, "bool", "Loop", "true" if anim["loop"] else "false")
    add(kp, "token", "Priority", anim["priority"])
    for t, p in constant_keys(anim["keys"]):
        by_part = {PART_OF[j]: transform(j, v) for j, v in p.items() if isinstance(v, dict)}
        kf, kfp = item("Keyframe", "Keyframe", ks)
        add(kfp, "float", "Time", fmt(t))
        hrp = pose_el(kf, "HumanoidRootPart", np.eye(4), 0)
        torso = pose_el(hrp, "Torso", by_part.get("Torso", np.eye(4)), 1 if "Torso" in by_part else 0)
        for part in LIMBS:
            if part in by_part:
                pose_el(torso, part, by_part[part], 1)
    return ks


def find_path(root, path):
    node = root
    for name in path.split("/"):
        node = next((c for c in node if c.tag == "Item" and name_of(c) == name), None)
        if node is None:
            raise SystemExit("not found: " + path)
    return node


def main(src, out, *modules):
    parser = etree.XMLParser(strip_cdata=False, huge_tree=True)
    tree = etree.parse(src, parser)
    root = tree.getroot()
    ss = child(root, "ServerStorage")
    holder = child(child(ss, name="RBX_ANIMSAVES"), name=RIG_NAME)
    import os
    only = [n for n in os.environ.get("ONLY", "").split(",") if n]
    for anim in ALL_NEW:
        if only and anim["name"] not in only:
            continue
        old = child(holder, "KeyframeSequence", anim["name"])
        if old is not None:
            holder.remove(old)
        holder.append(build_seq(anim))
    for spec in modules:
        path, file = spec.split("=")
        node = find_path(root, path)
        el = node.find("Properties/ProtectedString[@name='Source']")
        el.text = etree.CDATA(open(file, encoding="utf-8").read())
    for el in root.iter():
        if el.text is None and len(el) == 0:
            el.text = ""
    tree.write(out, encoding="utf-8", xml_declaration=False)
    print("wrote %d sequences, %d modules" % (len(ALL_NEW), len(modules)))


if __name__ == "__main__":
    main(*sys.argv[1:])
