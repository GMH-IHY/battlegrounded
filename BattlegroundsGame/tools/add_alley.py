"""Add (or replace) Workspace > WallHopAlley: two parallel walls for practicing wall hop zig-zags.
Copies TallWall's look. Walls at x = 100 and x = 114 (12-stud gap), z 28..92, 30 tall.
Usage: python tools/add_alley.py <in.rbxlx> <out.rbxlx>"""
import sys, copy, uuid
from lxml import etree

NAME = "WallHopAlley"
WALLS = [("AlleyWallLeft", 100), ("AlleyWallRight", 114)]


def name_of(item):
    e = item.find("Properties/string[@name='Name']")
    return e.text if e is not None else None


def main(src, dst):
    tree = etree.parse(src, etree.XMLParser(strip_cdata=False, huge_tree=True))
    root = tree.getroot()
    ws = next(c for c in root if c.tag == "Item" and c.get("class") == "Workspace")
    for c in list(ws):
        if c.tag == "Item" and name_of(c) == NAME:
            ws.remove(c)
    template = next(c for c in ws.iter("Item") if name_of(c) == "TallWall")
    model = etree.SubElement(ws, "Item", {"class": "Model", "referent": "RBX" + uuid.uuid4().hex.upper()})
    props = etree.SubElement(model, "Properties")
    n = etree.SubElement(props, "string", {"name": "Name"}); n.text = NAME
    for wall_name, x in WALLS:
        part = copy.deepcopy(template)
        part.set("referent", "RBX" + uuid.uuid4().hex.upper())
        for child in list(part):
            if child.tag == "Item":
                part.remove(child)
        part.find("Properties/string[@name='Name']").text = wall_name
        cf = part.find("Properties/CoordinateFrame[@name='CFrame']")
        for k, v in zip("XYZ", (x, 15, 60)):
            cf.find(k).text = str(v)
        for k, v in zip(["R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"], [1, 0, 0, 0, 1, 0, 0, 0, 1]):
            cf.find(k).text = str(v)
        size = part.find("Properties/Vector3[@name='size']")
        if size is None:
            size = part.find("Properties/Vector3[@name='Size']")
        for k, v in zip("XYZ", (2, 30, 64)):
            size.find(k).text = str(v)
        uid = part.find("Properties/UniqueId[@name='UniqueId']")
        if uid is not None:
            part.find("Properties").remove(uid)
        model.append(part)
    tree.write(dst, encoding="utf-8", xml_declaration=False)
    print("alley added")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
