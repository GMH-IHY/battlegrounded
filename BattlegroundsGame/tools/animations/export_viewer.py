"""Writes the animation data for the web animation viewer (every pose of every animation as
world-space part transforms). Usage: python export_viewer.py out.json"""
import json, sys
from rig import fk
from anims import ALL

PARTS = ["Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]


def main(out):
    data = []
    for a in ALL:
        keys = []
        for t, p in a["keys"]:
            w = fk(p)
            keys.append({"t": t, "parts": {n: [round(float(x), 4) for x in w[n].T.flatten()] for n in PARTS}})
        data.append({"name": a["name"], "loop": a["loop"], "notes": a["notes"], "keys": keys})
    json.dump(data, open(out, "w"), separators=(",", ":"))
    print(len(data), "animations")




def build_html(out_html):
    """Fills viewer_template.html with the current animations."""
    import os, tempfile
    tmp = os.path.join(tempfile.gettempdir(), "anims_viewer.json")
    main(tmp)
    html = open(os.path.join(os.path.dirname(__file__), "viewer_template.html")).read()
    open(out_html, "w").write(html.replace("__DATA__", open(tmp).read()))
    print("wrote", out_html)


if __name__ == "__main__":
    # python export_viewer.py out.html  -> the viewer page;  out.json -> data only
    if sys.argv[1].endswith(".html"):
        build_html(sys.argv[1])
    else:
        main(sys.argv[1])
