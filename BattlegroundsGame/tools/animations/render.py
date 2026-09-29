"""Contact sheets: every pose of every animation from a 3/4 view and a side view."""
import itertools, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from rig import fk, SIZES
from anims import ALL

COLORS = {"Torso": "#2f6fd6", "Head": "#f5cd30", "Right Arm": "#f5cd30", "Left Arm": "#f5cd30",
          "Right Leg": "#4b974b", "Left Leg": "#4b974b"}

def box_faces(m, size):
    sx, sy, sz = (s / 2 for s in size)
    c = np.array(list(itertools.product([-sx, sx], [-sy, sy], [-sz, sz])))
    w = (m[:3, :3] @ c.T).T + m[:3, 3]
    idx = [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
    # Roblox (x, y, z) -> plot (x, -z, y) so "up" is up and forward is +plot-y
    return [[(p[0], -p[2], p[1]) for p in w[f]] for f in idx]

def draw(ax, p, elev, azim):
    w = fk(p)
    for part, color in COLORS.items():
        pc = Poly3DCollection(box_faces(w[part], SIZES[part]), facecolor=color, edgecolor="#222", linewidths=0.6)
        ax.add_collection3d(pc)
    face = w["Head"] @ np.array([[1,0,0,0],[0,1,0,0.1],[0,0,1,-0.55],[0,0,0,1]])
    ax.add_collection3d(Poly3DCollection(box_faces(face, (0.9, 0.3, 0.1)), facecolor="#222"))
    ax.plot([-2.5, 2.5], [0, 0], [0, 0], color="#999", lw=0.8)
    ax.set_xlim(-2.3, 2.3); ax.set_ylim(-2.3, 2.3); ax.set_zlim(0.2, 4.8)
    ax.set_box_aspect((1, 1, 1)); ax.view_init(elev=elev, azim=azim); ax.set_axis_off()

def sheet(anim, path):
    keys = anim["keys"][:-1] if anim["loop"] else anim["keys"][:-1] or anim["keys"]
    n = len(keys)
    fig = plt.figure(figsize=(3.2 * n, 9.9))
    for i, (t, p) in enumerate(keys):
        a = fig.add_subplot(3, n, i + 1, projection="3d"); draw(a, p, 12, 55)
        a.set_title(f"t={t:.2f}s", fontsize=9)
        c = fig.add_subplot(3, n, n + i + 1, projection="3d"); draw(c, p, 5, 90)
        b = fig.add_subplot(3, n, 2 * n + i + 1, projection="3d"); draw(b, p, 5, 0)
    fig.suptitle(f'{anim["name"]}  (rows: 3/4 view, front view, side view facing right)', fontsize=10)
    fig.subplots_adjust(left=0, right=1, bottom=0, top=0.92, wspace=-0.1, hspace=-0.05); fig.savefig(path, dpi=80); plt.close(fig)

if __name__ == "__main__":
    out = sys.argv[1]
    for a in ALL:
        sheet(a, f"{out}/{a['name']}.png")
