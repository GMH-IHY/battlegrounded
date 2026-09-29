"""Patch script changes from a freshly built place into the place saved from Studio.

Usage: python sync_place.py <saved.rbxlx> <built.rbxlx> <out.rbxlx>

For every Script/LocalScript/ModuleScript in the built place, the script at the same
path (by names) in the saved place gets its Source replaced; scripts that don't exist
yet are inserted under the same parent. Everything else in the saved place (maps,
parts, settings you changed in Studio) is left alone, except the StarterPlayer
properties listed in STARTER_PLAYER_PROPS.
"""

import copy
import sys
import uuid

from lxml import etree

SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}
STARTER_PLAYER_PROPS = {"CharacterUseJumpPower", "CharacterJumpHeight", "GameSettingsAvatar", "EnableMouseLockOption"}


def name_of(item):
    node = item.find("Properties/string[@name='Name']")
    return node.text if node is not None else item.get("class")


def child_items(parent):
    return [c for c in parent if c.tag == "Item"]


def path_of(item):
    parts = []
    while item is not None and item.tag == "Item":
        parts.append(name_of(item))
        item = item.getparent()
    return list(reversed(parts))


def find(root, path):
    node = root
    for part in path:
        match = next((c for c in child_items(node) if name_of(c) == part), None)
        if match is None:
            return None
        node = match
    return node


def fresh_referents(item):
    for node in item.iter("Item"):
        node.set("referent", "RBX" + uuid.uuid4().hex.upper())


def main(saved_path, built_path, out_path):
    parser = etree.XMLParser(strip_cdata=False, remove_blank_text=False, huge_tree=True)
    saved = etree.parse(saved_path, parser)
    built = etree.parse(built_path, parser)
    saved_root, built_root = saved.getroot(), built.getroot()

    for item in built_root.iter("Item"):
        if item.get("class") not in SCRIPT_CLASSES:
            continue
        path = path_of(item)
        target = find(saved_root, path)
        source = item.find("Properties/*[@name='Source']")
        if target is not None:
            dest = target.find("Properties/*[@name='Source']")
            dest.text = etree.CDATA(source.text or "")
            print("updated ", "/".join(path))
        else:
            parent = find(saved_root, path[:-1])
            if parent is None:
                print("SKIPPED (parent missing)", "/".join(path))
                continue
            clone = copy.deepcopy(item)
            for child in child_items(clone):  # nested scripts are handled on their own
                clone.remove(child)
            fresh_referents(clone)
            clone_source = clone.find("Properties/*[@name='Source']")
            clone_source.text = etree.CDATA(source.text or "")
            parent.append(clone)
            print("inserted", "/".join(path))

    built_sp = find(built_root, ["StarterPlayer"])
    saved_sp = find(saved_root, ["StarterPlayer"])
    if built_sp is not None and saved_sp is not None:
        for prop in built_sp.find("Properties"):
            name = prop.get("name")
            if name in STARTER_PLAYER_PROPS:
                existing = saved_sp.find(f"Properties/*[@name='{name}']")
                if existing is not None:
                    existing.text = prop.text
                else:
                    saved_sp.find("Properties").append(copy.deepcopy(prop))
                print("set      StarterPlayer." + name, "=", prop.text)

    # Keep empty elements as <a></a> like Studio writes them.
    for element in saved_root.iter():
        if element.text is None and len(element) == 0:
            element.text = ""

    saved.write(out_path, encoding="utf-8", xml_declaration=False)


if __name__ == "__main__":
    main(*sys.argv[1:4])
