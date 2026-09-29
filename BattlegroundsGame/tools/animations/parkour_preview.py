"""Contact sheets for parkour_anims: every pose from a 3/4 view, the front and the side (facing right).
Usage: python parkour_preview.py <out_dir> [Name ...]"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from rig import fk, SIZES, cf, rx, pose as full_pose
from render import box_faces, COLORS
from parkour_anims import ALL_NEW

SLIDE_ROOT = cf(0, 3, 0) @ cf(0, -1.7, 0) @ np.block([[rx(70), np.zeros((3, 1))], [np.zeros((1, 3)), np.ones((1, 1))]])


def complete(p):
    base = full_pose()
    base.update({k: v for k, v in p.items() if isinstance(v, dict)})
    return base


def draw(ax, p, elev, azim, root):
    w = fk(complete(p), root)
    for part, color in COLORS.items():
        ax.add_collection3d(Poly3DCollection(box_faces(w[part], SIZES[part]), facecolor=color, edgecolor="#222", linewidths=0.6))
    face = w["Head"] @ np.array([[1, 0, 0, 0], [0, 1, 0, 0.1], [0, 0, 1, -0.55], [0, 0, 0, 1]])
    ax.add_collection3d(Poly3DCollection(box_faces(face, (0.9, 0.3, 0.1)), facecolor="#222"))
    g = [[(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)]]
    ax.add_collection3d(Poly3DCollection(g, facecolor=(0.6, 0.6, 0.6, 0.25), edgecolor="none"))
    ax.set_xlim(-2.8, 2.8); ax.set_ylim(-2.8, 2.8); ax.set_zlim(-0.6, 5.0)
    ax.set_box_aspect((1, 1, 1)); ax.view_init(elev=elev, azim=azim); ax.set_axis_off()


def sheet(anim, path):
    keys = anim["keys"][:-1] if len(anim["keys"]) > 1 else anim["keys"]
    root = SLIDE_ROOT if anim["name"] == "Slide" else None
    n = len(keys)
    fig = plt.figure(figsize=(3.0 * n, 9.3))
    for i, (t, p) in enumerate(keys):
        a = fig.add_subplot(3, n, i + 1, projection="3d"); draw(a, p, 14, 235, root)   # 3/4 from behind-left
        a.set_title(f"t={t:.2f}s", fontsize=9)
        c = fig.add_subplot(3, n, n + i + 1, projection="3d"); draw(c, p, 5, 90, root)  # front
        b = fig.add_subplot(3, n, 2 * n + i + 1, projection="3d"); draw(b, p, 5, 0, root)  # side, facing right
    fig.suptitle(f'{anim["name"]}  (rows: 3/4 from behind, front view, side view facing right)', fontsize=10)
    fig.subplots_adjust(left=0, right=1, bottom=0, top=0.92, wspace=-0.1, hspace=-0.05)
    fig.savefig(path, dpi=70); plt.close(fig)


if __name__ == "__main__":
    out, names = sys.argv[1], sys.argv[2:]
    for a in ALL_NEW:
        if not names or a["name"] in names:
            sheet(a, f"{out}/{a['name']}.png")
