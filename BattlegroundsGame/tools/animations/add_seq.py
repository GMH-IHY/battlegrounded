"""Add (or replace) only the named KeyframeSequences in a saved place, leaving every other
animation (including ones edited in Studio) untouched.
Usage: python add_seq.py <in.rbxlx> <out.rbxlx> Name [Name...]"""
import sys
from lxml import etree
from build import build_seq, RIG_NAME, child, name_of
from anims import ALL


def main(src, dst, names):
    tree = etree.parse(src, etree.XMLParser(strip_cdata=False, huge_tree=True)); root = tree.getroot()
    ss = child(root, "ServerStorage")
    holder = child(child(ss, name="RBX_ANIMSAVES"), name=RIG_NAME)
    by_name = {a["name"]: a for a in ALL}
    for name in names:
        new = build_seq(by_name[name])
        old = child(holder, "KeyframeSequence", name)
        if old is not None:
            holder.replace(old, new); print("replaced", name)
        else:
            holder.append(new); print("added", name)
    for el in root.iter():
        if el.text is None and len(el) == 0: el.text = ""
    tree.write(dst, encoding="utf-8", xml_declaration=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
