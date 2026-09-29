"""Small helpers for reading and writing Roblox XML place / model files (.rbxlx / .rbxmx).

Shared by tools/place.py (scripts) and tools/animations/build.py (KeyframeSequences, rig).
Every tool writes the place back the way Studio does: no XML declaration, empty elements as
<a></a>, CDATA kept, so the file stays diff-friendly and Studio opens it unchanged.
"""
import uuid

from lxml import etree

E = etree.Element
PARSER = etree.XMLParser(strip_cdata=False, huge_tree=True)


def load(path):
    return etree.parse(path, PARSER)


def save(tree, path):
    for el in tree.getroot().iter():
        if el.text is None and len(el) == 0:
            el.text = ""
    tree.write(path, encoding="utf-8", xml_declaration=False)


def ref():
    return "RBX" + uuid.uuid4().hex.upper()


def fmt(x):
    x = 0.0 if abs(x) < 1e-9 else float(x)
    return repr(round(x, 7))


def name_of(it):
    n = it.find("Properties/string[@name='Name']")
    return n.text if n is not None else it.get("class")


def children(parent):
    return [c for c in parent if c.tag == "Item"]


def child(parent, cls=None, name=None):
    for c in children(parent):
        if (cls is None or c.get("class") == cls) and (name is None or name_of(c) == name):
            return c
    return None


def find(root, path):
    """path: list of names or 'A/B/C'. Top level matches service names (e.g. 'ServerStorage')."""
    if isinstance(path, str):
        path = path.split("/")
    node = root
    for part in path:
        node = child(node, name=part)
        if node is None:
            return None
    return node


def ensure_folder(root, path):
    """Finds or creates Folders along path (the first element must be an existing service)."""
    parts = path.split("/") if isinstance(path, str) else list(path)
    node = find(root, parts[:1])
    if node is None:
        raise SystemExit("service not found in place: " + parts[0])
    for part in parts[1:]:
        nxt = child(node, name=part)
        if nxt is None:
            nxt, _ = item("Folder", part, node)
        node = nxt
    return node


def item(cls, name, parent=None):
    it = E("Item", {"class": cls, "referent": ref()})
    props = etree.SubElement(it, "Properties")
    add(props, "string", "Name", name)
    if parent is not None:
        parent.append(it)
    return it, props


def add(props, tag, name, text=None):
    el = etree.SubElement(props, tag, name=name)
    if text is not None:
        el.text = str(text)
    return el


def add_cf(props, name, m):
    el = add(props, "CoordinateFrame", name)
    for k, v in zip("XYZ", m[:3, 3]):
        etree.SubElement(el, k).text = fmt(v)
    for i in range(3):
        for j in range(3):
            etree.SubElement(el, f"R{i}{j}").text = fmt(m[i, j])


def add_v3(props, name, v):
    el = add(props, "Vector3", name)
    for k, x in zip("XYZ", v):
        etree.SubElement(el, k).text = fmt(x)


def color_int(rgb):
    r, g, b = rgb
    return (0xFF << 24) | (r << 16) | (g << 8) | b
