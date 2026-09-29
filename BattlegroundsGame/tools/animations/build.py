"""Insert an R6 animation rig + the movement KeyframeSequences into a saved .rbxlx.

Usage: python build.py <saved.rbxlx> <out.rbxlx> <out_anims.rbxmx>

Workspace > AnimRig_R6                       (anchored R6 dummy for the Animation Editor)
ServerStorage > RBX_ANIMSAVES > AnimRig_R6   (ObjectValue -> rig; the editor's Load menu lists its children)
                                  > Idle, WalkForward, ... (KeyframeSequences)
Re-running replaces both, so it's safe to regenerate after tweaking anims.py.
"""
import sys, uuid
import numpy as np
from lxml import etree
from rig import JOINTS, SIZES, transform, cf, ry
from anims import ALL

RIG_NAME = "AnimRig_R6"
RIG_CF = cf(0, 3, -30) @ np.block([[ry(180), np.zeros((3, 1))], [np.zeros((1, 3)), np.ones((1, 1))]])
COLORS = {"Head": (245, 205, 48), "Torso": (13, 105, 172), "Right Arm": (245, 205, 48),
          "Left Arm": (245, 205, 48), "Right Leg": (75, 151, 75), "Left Leg": (75, 151, 75),
          "HumanoidRootPart": (163, 162, 165)}
E = etree.Element
def ref(): return "RBX" + uuid.uuid4().hex.upper()
def fmt(x):
    x = 0.0 if abs(x) < 1e-9 else float(x)
    return repr(round(x, 7))

def item(cls, name, parent=None):
    it = E("Item", {"class": cls, "referent": ref()})
    props = etree.SubElement(it, "Properties")
    add(props, "string", "Name", name)
    if parent is not None: parent.append(it)
    return it, props

def add(props, tag, name, text=None):
    el = etree.SubElement(props, tag, name=name)
    if text is not None: el.text = str(text)
    return el

def add_cf(props, name, m):
    el = add(props, "CoordinateFrame", name)
    for k, v in zip("XYZ", m[:3, 3]): etree.SubElement(el, k).text = fmt(v)
    for i in range(3):
        for j in range(3): etree.SubElement(el, f"R{i}{j}").text = fmt(m[i, j])

def add_v3(props, name, v):
    el = add(props, "Vector3", name)
    for k, x in zip("XYZ", v): etree.SubElement(el, k).text = fmt(x)

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
        add(pp, "token", "TopSurface", 0); add(pp, "token", "BottomSurface", 0)
        c = add(pp, "Color3uint8", "Color3uint8")
        r, g, b = COLORS[name]; c.text = str((0xFF << 24) | (r << 16) | (g << 8) | b)
        parts[name] = part
    head = parts["Head"]
    mesh, mep = item("SpecialMesh", "Mesh", head)
    add(mep, "token", "MeshType", 0); add_v3(mep, "Scale", (1.25, 1.25, 1.25))
    face, fp = item("Decal", "face", head)
    add(fp, "Content", "Texture"); etree.SubElement(fp[-1], "url").text = "rbxasset://textures/face.png"
    add(fp, "token", "Face", 5)
    for j, (p0, p1, c0, c1) in JOINTS.items():
        m, pr = item("Motor6D", j, parts[p0])
        add_cf(pr, "C0", c0); add_cf(pr, "C1", c1)
        add(pr, "Ref", "Part0", parts[p0].get("referent"))
        add(pr, "Ref", "Part1", parts[p1].get("referent"))
    hum, hp = item("Humanoid", "Humanoid", model)
    add(hp, "token", "RigType", 0)
    add(hp, "token", "DisplayDistanceType", 2)
    item("Animator", "Animator", hum)
    add(mp, "Ref", "PrimaryPart", parts["HumanoidRootPart"].get("referent"))
    return model

# ---------------- animations ------------------------------------------------------------
LIMBS = [("Head", "Neck"), ("Right Arm", "Right Shoulder"), ("Left Arm", "Left Shoulder"),
         ("Right Leg", "Right Hip"), ("Left Leg", "Left Hip")]

def pose_el(parent, name, m, weight):
    p, pp = item("Pose", name, parent)
    add_cf(pp, "CFrame", m)
    add(pp, "token", "EasingDirection", 0)
    add(pp, "token", "EasingStyle", 1)          # PoseEasingStyle.Constant: snap, no tweening
    add(pp, "float", "Weight", weight)
    add(pp, "float", "MaskWeight", 0)
    return p

def constant_keys(keys):
    """anims.py lists each pose at the time it should APPEAR and hold until the next one.
    Roblox's Constant easing works the other way: between two keyframes it shows the LATER
    keyframe's pose (checked in Studio: at t=0.25 and 0.30 a walk with keys at 0.24/0.36 shows
    the 0.36 pose). So each pose is written at the END of the span it should cover."""
    out = [keys[0]]
    for i in range(1, len(keys)):
        out.append((keys[i][0], keys[i - 1][1]))
    return out


def build_seq(anim):
    ks, kp = item("KeyframeSequence", anim["name"])
    add(kp, "bool", "Loop", "true" if anim["loop"] else "false")
    add(kp, "token", "Priority", anim["priority"])
    for t, pose in constant_keys(anim["keys"]):
        kf, kfp = item("Keyframe", "Keyframe", ks)
        add(kfp, "float", "Time", fmt(t))
        hrp = pose_el(kf, "HumanoidRootPart", np.eye(4), 0)
        torso = pose_el(hrp, "Torso", transform("RootJoint", pose["RootJoint"]), 1)
        for part, joint in LIMBS:
            pose_el(torso, part, transform(joint, pose[joint]), 1)
    return ks

# ---------------- place patching ------------------------------------------------------
def name_of(it):
    n = it.find("Properties/string[@name='Name']")
    return n.text if n is not None else None

def child(parent, cls=None, name=None):
    for c in parent:
        if c.tag == "Item" and (cls is None or c.get("class") == cls) and (name is None or name_of(c) == name):
            return c

def main(saved, out, out_rbxmx):
    parser = etree.XMLParser(strip_cdata=False, huge_tree=True)
    tree = etree.parse(saved, parser); root = tree.getroot()
    ws = child(root, "Workspace"); ss = child(root, "ServerStorage")
    old = child(ws, "Model", RIG_NAME)
    if old is not None: ws.remove(old)
    rig = build_rig(); ws.append(rig)
    saves = child(ss, name="RBX_ANIMSAVES")
    if saves is None:
        saves, _ = item("Model", "RBX_ANIMSAVES", ss)
    holder = child(saves, name=RIG_NAME)
    if holder is not None: saves.remove(holder)
    holder, hp = item("ObjectValue", RIG_NAME, saves)
    add(hp, "Ref", "Value", rig.get("referent"))
    seqs = [build_seq(a) for a in ALL]
    for s in seqs: holder.append(s)
    for el in root.iter():
        if el.text is None and len(el) == 0: el.text = ""
    tree.write(out, encoding="utf-8", xml_declaration=False)

    # A standalone model file too: a Folder of the same KeyframeSequences (drag into Studio).
    m = E("roblox", {"version": "4"})
    folder, _ = item("Folder", "MovementAnimations", m)
    for a in ALL: folder.append(build_seq(a))
    etree.ElementTree(m).write(out_rbxmx, encoding="utf-8", xml_declaration=False)
    print("rig + %d animations written" % len(ALL))

if __name__ == "__main__":
    main(*sys.argv[1:4])
