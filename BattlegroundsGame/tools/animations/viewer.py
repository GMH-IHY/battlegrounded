"""Builds the browser animation viewer: every animation, played with constant easing at real speed.

    python tools/animations/viewer.py out.html     the viewer page (open it in any browser)
    python tools/animations/viewer.py out.json     the data only

Each pose is stored as world-space part transforms (R6 body plus the sword, sheath and dagger;
partial poses are drawn over the rest pose). The page itself is viewer_template.html with the data
(DATA) and the weapon pieces' sizes / colours (EXTRAS) pasted in.
"""
import json

import numpy as np
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from catalog import ALL  # noqa: E402
from preview import world_pieces, load_weapons, load_fungus, fungus_stage_for, BODY_COLORS  # noqa: E402

PARTS = list(BODY_COLORS)  # Torso, Head, arms, legs (the order world_pieces draws them in)
NO_EXTRAS = {"joints": [], "parts": []}


def export():
    weapons = load_weapons()
    fungus = load_fungus()
    data, extras = [], []
    for a in ALL:
        keys = []
        for t, p in a["keys"]:
            # Every animation draws the full growth (hidden below its stage) so the piece list is fixed.
            pieces = world_pieces(p, NO_EXTRAS, weapons, a["name"].startswith("Dagger"), fungus, 3)
            names = PARTS + [f"W{i}" for i in range(len(pieces) - len(PARTS))]
            if not extras:
                extras = [{"size": [float(x) for x in piece["size"]], "color": list(piece["color"])}
                          for piece in pieces[len(PARTS):]]
            if fungus_stage_for(a["name"]) == 0:
                # Hide the growth on non-Lotus animations (shrink it to nothing).
                for piece in pieces[len(pieces) - len(fungus):]:
                    piece["m"] = piece["m"] @ np.diag([0.0, 0.0, 0.0, 1.0])
            keys.append({"t": t, "parts": {n: [round(float(x), 4) for x in piece["m"].T.flatten()]
                                           for n, piece in zip(names, pieces)}})
        data.append({"name": a["name"], "loop": a["loop"], "notes": a.get("notes", ""), "keys": keys})
    return data, extras


def main(out):
    data, extras = export()
    payload = json.dumps(data, separators=(",", ":"))
    if out.endswith(".html"):
        html = open(os.path.join(HERE, "viewer_template.html"), encoding="utf-8").read()
        html = html.replace("__EXTRAS__", json.dumps(extras, separators=(",", ":")))
        open(out, "w", encoding="utf-8").write(html.replace("__DATA__", payload))
    else:
        open(out, "w", encoding="utf-8").write(payload)
    print(f"wrote {out} ({len(data)} animations)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
