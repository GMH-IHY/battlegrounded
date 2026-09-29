"""Add (or replace) Workspace > DashTestDummy: an anchored R6 dummy for dash-punch tests.
Usage: python tools/add_dummy.py <in.rbxlx> <out.rbxlx>"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "animations"))
import numpy as np
from lxml import etree
import build
from build import child, name_of, cf, ry, item, add, add_v3

NAME = "DashTestDummy"
POSITION = (80, 3, 40)


def main(src, dst):
    tree = etree.parse(src, etree.XMLParser(strip_cdata=False, huge_tree=True)); root = tree.getroot()
    ws = child(root, "Workspace")
    old = child(ws, "Model", NAME)
    if old is not None:
        ws.remove(old)
    rot = np.eye(4); rot[:3, :3] = ry(90)  # face -X, toward the runway
    build.RIG_CF = cf(*POSITION) @ rot
    model = build.build_rig()
    model.find("Properties/string[@name='Name']").text = NAME
    head = next(c for c in model if c.tag == "Item" and name_of(c) == "Head")
    gui, gp = item("BillboardGui", "Label", head)
    el = add(gp, "UDim2", "Size")
    for k, v in (("XS", 0), ("XO", 240), ("YS", 0), ("YO", 30)):
        etree.SubElement(el, k).text = str(v)
    add_v3(gp, "StudsOffset", (0, 4.2, 0))
    add(gp, "float", "MaxDistance", 80)
    label, lp = item("TextLabel", "Text", gui)
    el = add(lp, "UDim2", "Size")
    for k, v in (("XS", 1), ("XO", 0), ("YS", 1), ("YO", 0)):
        etree.SubElement(el, k).text = str(v)
    add(lp, "float", "BackgroundTransparency", 1)
    add(lp, "string", "Text", "Test dummy - Shift then M1 to dash punch")
    add(lp, "bool", "TextScaled", "true")
    add(lp, "float", "TextStrokeTransparency", 0)
    c = add(lp, "Color3", "TextColor3")
    for k in "RGB":
        etree.SubElement(c, k).text = "1"
    ws.append(model)
    for el in root.iter():
        if el.text is None and len(el) == 0: el.text = ""
    tree.write(dst, encoding="utf-8", xml_declaration=False)
    print("dummy added at", POSITION)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
