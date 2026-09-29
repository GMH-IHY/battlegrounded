"""Builds the browser animation viewer: every animation, played with constant easing at real speed.

    python tools/animations/viewer.py out.html     the viewer page (open it in any browser)
    python tools/animations/viewer.py out.json     the data only

Each pose is stored as world-space part transforms (R6 body; partial poses are drawn over the rest
pose). The page itself is viewer_template.html with the data pasted in.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from catalog import ALL  # noqa: E402
from preview import world_pieces, BODY_COLORS  # noqa: E402

PARTS = list(BODY_COLORS)  # Torso, Head, arms, legs (the order world_pieces draws them in)
NO_EXTRAS = {"joints": [], "parts": []}


def export():
    data = []
    for a in ALL:
        keys = []
        for t, p in a["keys"]:
            pieces = world_pieces(p, NO_EXTRAS)[:len(PARTS)]
            keys.append({"t": t, "parts": {n: [round(float(x), 4) for x in piece["m"].T.flatten()]
                                           for n, piece in zip(PARTS, pieces)}})
        data.append({"name": a["name"], "loop": a["loop"], "notes": a.get("notes", ""), "keys": keys})
    return data


def main(out):
    data = export()
    payload = json.dumps(data, separators=(",", ":"))
    if out.endswith(".html"):
        html = open(os.path.join(HERE, "viewer_template.html"), encoding="utf-8").read()
        open(out, "w", encoding="utf-8").write(html.replace("__DATA__", payload))
    else:
        open(out, "w", encoding="utf-8").write(payload)
    print(f"wrote {out} ({len(data)} animations)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
