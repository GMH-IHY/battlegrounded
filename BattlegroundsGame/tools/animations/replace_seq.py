"""Replace only the named KeyframeSequences in a saved place (leaves everything else, including
other animations edited in Studio, untouched). Usage: python replace_seq.py <in> <out> Name [Name...]"""
import sys
from lxml import etree
from build import build_seq, RIG_NAME
from anims import ALL

def main(src, dst, names):
    tree = etree.parse(src, etree.XMLParser(strip_cdata=False, huge_tree=True)); root = tree.getroot()
    by_name = {a["name"]: a for a in ALL}
    for ks in list(root.iter("Item")):
        if ks.get("class") != "KeyframeSequence": continue
        name = ks.find("Properties/string[@name='Name']").text
        holder = ks.getparent()
        if name in names and holder.find("Properties/string[@name='Name']").text == RIG_NAME:
            new = build_seq(by_name[name]); holder.replace(ks, new); print("replaced", name)
    for el in root.iter():
        if el.text is None and len(el) == 0: el.text = ""
    tree.write(dst, encoding="utf-8", xml_declaration=False)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], set(sys.argv[3:]))
