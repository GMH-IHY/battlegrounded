"""Keeps BattlegroundsGame.rbxlx in step with src/.

    python tools/place.py sync  [place.rbxlx]         write every script from src/ into the place
    python tools/place.py check [place.rbxlx]         list differences; exit code 1 if any
    python tools/place.py remove [place.rbxlx] A/B/C  delete instances by path (e.g. old test models)

Which src folder goes where comes from default.project.json (every "$path" in its tree), the same
file Rojo uses, so the two can never disagree. Inside a mapped container, sync makes the scripts
match src exactly: changed Source is replaced, new files are inserted, scripts whose file was
deleted are removed. Subfolders in src become Folders. Everything else in the place (the map,
parts, models, animations, settings you changed in Studio) is left alone, except the StarterPlayer
properties listed in default.project.json.

File names follow Rojo: X.server.luau = Script, X.client.luau = LocalScript, X.luau = ModuleScript.
"""
import json
import os
import sys

from lxml import etree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rbxlx  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACE = os.path.join(ROOT, "BattlegroundsGame.rbxlx")
PROJECT = os.path.join(ROOT, "default.project.json")
SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")
PROP_TAGS = {"Bool": "bool", "Float32": "float", "Enum": "token", "String": "string", "Int32": "int"}


def mappings():
    """[(instance path list, src dir)] from default.project.json."""
    tree = json.load(open(PROJECT))["tree"]
    out = []

    def walk(node, path):
        if "$path" in node:
            out.append((path, os.path.join(ROOT, node["$path"])))
        for key, value in node.items():
            if not key.startswith("$") and isinstance(value, dict):
                walk(value, path + [key])

    walk(tree, [])
    return out


def src_entries(directory):
    """{name: ("Script"|"LocalScript"|"ModuleScript", source) or ("Folder", dir)} for one folder."""
    entries = {}
    for f in sorted(os.listdir(directory)):
        full = os.path.join(directory, f)
        if os.path.isdir(full):
            entries[f] = ("Folder", full)
        elif f.endswith(".server.luau"):
            entries[f[: -len(".server.luau")]] = ("Script", open(full, encoding="utf-8").read())
        elif f.endswith(".client.luau"):
            entries[f[: -len(".client.luau")]] = ("LocalScript", open(full, encoding="utf-8").read())
        elif f.endswith(".luau"):
            entries[f[: -len(".luau")]] = ("ModuleScript", open(full, encoding="utf-8").read())
    return entries


def source_of(it):
    el = it.find("Properties/*[@name='Source']")
    return el, ((el.text or "") if el is not None else "")


def new_script(cls, name, source, parent):
    it, props = rbxlx.item(cls, name, parent)
    el = rbxlx.add(props, "ProtectedString", "Source")
    el.text = etree.CDATA(source)
    return it


def sync_container(container, directory, path, report, write):
    wanted = src_entries(directory)
    for existing in rbxlx.children(container):
        cls, name = existing.get("class"), rbxlx.name_of(existing)
        if cls in SCRIPT_CLASSES and (name not in wanted or wanted[name][0] != cls):
            report.append("removed  " + "/".join(path + [name]))
            if write:
                container.remove(existing)
    for name, (cls, payload) in wanted.items():
        here = path + [name]
        existing = rbxlx.child(container, cls, name)
        if cls == "Folder":
            if existing is None:
                report.append("added    " + "/".join(here) + " (Folder)")
                if not write:
                    continue
                existing, _ = rbxlx.item("Folder", name, container)
            sync_container(existing, payload, here, report, write)
        elif existing is None:
            report.append("added    " + "/".join(here))
            if write:
                new_script(cls, name, payload, container)
        else:
            el, current = source_of(existing)
            wrong_type = el is not None and el.tag != "ProtectedString"
            if current.strip() != payload.strip() or wrong_type:
                # Studio stores Source as ProtectedString; older tools wrote a plain <string>.
                report.append(("updated  " if current.strip() != payload.strip() else "retyped  ") + "/".join(here))
                if write:
                    if el is not None:
                        el.getparent().remove(el)
                    el = rbxlx.add(existing.find("Properties"), "ProtectedString", "Source")
                    el.text = etree.CDATA(payload)


def sync_properties(root, report, write):
    tree = json.load(open(PROJECT))["tree"]
    for service, node in tree.items():
        if service.startswith("$") or not isinstance(node, dict) or "$properties" not in node:
            continue
        inst = rbxlx.find(root, [service])
        if inst is None:
            continue
        props = inst.find("Properties")
        for name, typed in node["$properties"].items():
            (kind, value), = typed.items()
            text = str(value).lower() if kind == "Bool" else str(value)
            el = props.find(f"*[@name='{name}']")
            if el is not None and el.text == text:
                continue
            report.append(f"set      {service}.{name} = {text}")
            if write:
                if el is None:
                    el = rbxlx.add(props, PROP_TAGS[kind], name)
                el.text = text


def run(place, write):
    tree = rbxlx.load(place)
    root = tree.getroot()
    report = []
    for path, directory in mappings():
        container = rbxlx.find(root, path)
        if container is None:
            report.append("added    " + "/".join(path) + " (Folder)")
            if not write:
                continue
            container = rbxlx.ensure_folder(root, path)
        sync_container(container, directory, path, report, write)
    sync_properties(root, report, write)
    if write and report:
        rbxlx.save(tree, place)
    return report


def remove(place, paths):
    tree = rbxlx.load(place)
    for path in paths:
        node = rbxlx.find(tree.getroot(), path)
        if node is None:
            print("not found", path)
            continue
        node.getparent().remove(node)
        print("removed ", path)
    rbxlx.save(tree, place)


def main(argv):
    if not argv or argv[0] not in ("sync", "check", "remove"):
        raise SystemExit(__doc__)
    cmd, rest = argv[0], argv[1:]
    place = rest.pop(0) if rest and rest[0].endswith(".rbxlx") else PLACE
    if cmd == "remove":
        remove(place, rest)
        return
    report = run(place, write=(cmd == "sync"))
    for line in report:
        print(line)
    if cmd == "check":
        print("place matches src" if not report else f"{len(report)} difference(s)")
        sys.exit(1 if report else 0)
    print("nothing to do" if not report else f"wrote {place}")


if __name__ == "__main__":
    main(sys.argv[1:])
