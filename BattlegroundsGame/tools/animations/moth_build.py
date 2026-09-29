"""Puts the Moth animations and the Moth wings/antennae on the Animation Editor rig in a saved place.

Usage: python moth_build.py <in.rbxlx> <out.rbxlx> <moth_parts.json>

  Workspace > AnimRig_R6 gets the wing / antenna bones (Motor6Ds on Torso / Head, same as in game)
  and their visual parts, so the Animation Editor can pose them.
  ServerStorage > RBX_ANIMSAVES > AnimRig_R6 gets (or replaces) the MOTH KeyframeSequences.
Poses only include the joints a keyframe keys; parents of keyed joints are added as empty containers.
"""
import json, sys, uuid
import numpy as np
from lxml import etree
from build import item, add, add_cf, add_v3, child, name_of, fmt, constant_keys, RIG_NAME
from moth_anims import MOTH

PART_OF = {"RootJoint": "Torso", "Neck": "Head", "Right Shoulder": "Right Arm", "Left Shoulder": "Left Arm",
           "Right Hip": "Right Leg", "Left Hip": "Left Leg"}
CHILDREN_OF_TORSO = ["Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg",
                     "RightForewing", "LeftForewing", "RightHindwing", "LeftHindwing"]
CHILDREN_OF_HEAD = ["RightAntenna", "LeftAntenna"]
MATERIAL = {"SmoothPlastic": 272, "Neon": 288, "Plastic": 256}
SHAPE = {"Ball": 0, "Block": 1, "Cylinder": 2}


def pose_el(parent, name, m, weight):
    p, pp = item("Pose", name, parent)
    add_cf(pp, "CFrame", m)
    add(pp, "token", "EasingDirection", 0)
    add(pp, "token", "EasingStyle", 1)  # Constant
    add(pp, "float", "Weight", weight)
    add(pp, "float", "MaskWeight", 0)
    return p


def build_seq(anim):
    ks, kp = item("KeyframeSequence", anim["name"])
    add(kp, "bool", "Loop", "true" if anim["loop"] else "false")
    add(kp, "token", "Priority", anim["priority"])
    for t, keyed in constant_keys(anim["keys"]):
        by_part = {PART_OF.get(j, j): m for j, m in keyed.items()}
        kf, kfp = item("Keyframe", "Keyframe", ks)
        add(kfp, "float", "Time", fmt(t))
        hrp = pose_el(kf, "HumanoidRootPart", np.eye(4), 0)
        torso = pose_el(hrp, "Torso", by_part.get("Torso", np.eye(4)), 1 if "Torso" in by_part else 0)
        for part in CHILDREN_OF_TORSO:
            head_needed = part == "Head" and any(c in by_part for c in CHILDREN_OF_HEAD)
            if part in by_part or head_needed:
                el = pose_el(torso, part, by_part.get(part, np.eye(4)), 1 if part in by_part else 0)
                if part == "Head":
                    for c in CHILDREN_OF_HEAD:
                        if c in by_part:
                            pose_el(el, c, by_part[c], 1)
    return ks


def color_int(c):
    return (0xFF << 24) | (c[0] << 16) | (c[1] << 8) | c[2]


def add_wings_to_rig(rig, data):
    parts = {name_of(c): c for c in rig if c.tag == "Item" and c.get("class") == "Part"}
    torso, head = parts["Torso"], parts["Head"]

    def cf_of(part):
        el = part.find("Properties/CoordinateFrame[@name='CFrame']")
        m = np.eye(4)
        m[:3, 3] = [float(el.find(k).text) for k in "XYZ"]
        for i in range(3):
            for j in range(3):
                m[i, j] = float(el.find(f"R{i}{j}").text)
        return m

    old = next((c for c in rig if c.tag == "Item" and name_of(c) == "MothWings"), None)
    if old is not None:
        rig.remove(old)
    for p in (torso, head):
        for c in list(p):
            if c.tag == "Item" and c.get("class") == "Motor6D" and name_of(c) in [j["name"] for j in data["joints"]]:
                p.remove(c)
    model, _ = item("Model", "MothWings", rig)
    bones = {}
    for j in data["joints"]:
        p0 = torso if j["part0"] == "Torso" else head
        c0 = np.array(j["c0"])
        bone_cf = cf_of(p0) @ c0
        bone, bp = item("Part", j["name"], model)
        add_cf(bp, "CFrame", bone_cf)
        add_v3(bp, "size", (0.2, 0.2, 0.2))
        for k, v in (("Anchored", "false"), ("CanCollide", "false"), ("CanQuery", "false"), ("CanTouch", "false"), ("Massless", "true")):
            add(bp, "bool", k, v)
        add(bp, "float", "Transparency", 1)
        motor, mp = item("Motor6D", j["name"], p0)
        add_cf(mp, "C0", c0)
        add_cf(mp, "C1", np.eye(4))
        add(mp, "Ref", "Part0", p0.get("referent"))
        add(mp, "Ref", "Part1", bone.get("referent"))
        bones[j["name"]] = (bone, bone_cf)
    for s in data["parts"]:
        bone, bone_cf = bones[s["bone"]]
        rel = np.array(s["rel"])
        cls = "WedgePart" if s["cls"] == "WedgePart" else "Part"
        part, pp = item(cls, s["name"], model)
        add_cf(pp, "CFrame", bone_cf @ rel)
        add_v3(pp, "size", s["size"])
        for k, v in (("Anchored", "false"), ("CanCollide", "false"), ("CanQuery", "false"), ("CanTouch", "false"),
                     ("Massless", "true"), ("CastShadow", "false")):
            add(pp, "bool", k, v)
        c = add(pp, "Color3uint8", "Color3uint8")
        c.text = str(color_int(s["color"]))
        add(pp, "token", "Material", MATERIAL[s["mat"]])
        add(pp, "token", "TopSurface", 0)
        add(pp, "token", "BottomSurface", 0)
        if cls == "Part":
            add(pp, "token", "shape", SHAPE[s["shape"]])
        weld, wp = item("Weld", "Weld", part)
        add_cf(wp, "C0", rel)
        add_cf(wp, "C1", np.eye(4))
        add(wp, "Ref", "Part0", bone.get("referent"))
        add(wp, "Ref", "Part1", part.get("referent"))


def main(src, dst, parts_json):
    data = json.load(open(parts_json))
    tree = etree.parse(src, etree.XMLParser(strip_cdata=False, huge_tree=True))
    root = tree.getroot()
    ws, ss = child(root, "Workspace"), child(root, "ServerStorage")
    rig = child(ws, "Model", RIG_NAME)
    add_wings_to_rig(rig, data)
    holder = child(child(ss, name="RBX_ANIMSAVES"), name=RIG_NAME)
    for anim in MOTH:
        new = build_seq(anim)
        old = child(holder, "KeyframeSequence", anim["name"])
        if old is not None:
            holder.replace(old, new)
            print("replaced", anim["name"])
        else:
            holder.append(new)
            print("added", anim["name"])
    for el in root.iter():
        if el.text is None and len(el) == 0:
            el.text = ""
    tree.write(dst, encoding="utf-8", xml_declaration=False)


if __name__ == "__main__":
    main(*sys.argv[1:4])
