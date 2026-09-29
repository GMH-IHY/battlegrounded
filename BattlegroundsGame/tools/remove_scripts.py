"""Removes instances by path from a saved place (e.g. a script deleted from src).
Usage: python remove_scripts.py <in.rbxlx> <out.rbxlx> Path/To/Item [...]"""
import sys
from lxml import etree
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from sync_place import find

def main(src, out, *paths):
    parser = etree.XMLParser(strip_cdata=False, huge_tree=True)
    tree = etree.parse(src, parser)
    root = tree.getroot()
    for path in paths:
        node = find(root, path.split("/"))
        if node is None:
            print("not found", path)
            continue
        node.getparent().remove(node)
        print("removed ", path)
    for el in root.iter():
        if el.text is None and len(el) == 0:
            el.text = ""
    tree.write(out, encoding="utf-8", xml_declaration=False)

if __name__ == "__main__":
    main(*sys.argv[1:])
