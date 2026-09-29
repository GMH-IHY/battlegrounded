"""Builds MothRace.rbxmx: blocky sculk-style fluffy moth wings + feathery antennae for an R6 rig.

Coordinates are Torso-local (Torso centre = origin, character faces -Z, back is +Z).
Every visible part is welded to an invisible "bone" part, and each bone hangs off a Motor6D,
so the wings and antennae can be animated in the Animation Editor.
"""
import math, random, json
import numpy as np

S = 0.22          # wing voxel size (studs)
THICK = 0.14      # wing membrane thickness
FLUFF_THICK = 0.26

COL = {
    'D': ((11, 26, 31), 'SmoothPlastic'),    # sculk black
    'S': ((16, 58, 64), 'SmoothPlastic'),    # deep teal
    'M': ((24, 95, 102), 'SmoothPlastic'),   # mid teal
    'F': ((104, 156, 158), 'Fabric'),        # fluff
    'G': ((41, 223, 235), 'Neon'),           # glow
    'P': ((150, 250, 255), 'Neon'),          # bright speck
}
FRINGE = ((150, 204, 202), 'Fabric')
TUFT = [((104, 156, 158), 'Fabric'), ((150, 204, 202), 'Fabric'), ((16, 58, 64), 'Fabric')]
MATERIAL = {'SmoothPlastic': 272, 'Neon': 288, 'Fabric': 1312, 'Plastic': 256}

# Right wings, col 0 = spine side. Row 0 = top.
FOREWING = """
.............FFFF.
...........FFSSSSF
.........FFSSDDDSF
.......FFSSDDGGDSF
.....FFSSDDGDDGDSF
...FFSSMDDDGDDGMF.
.FFSSMMDDDDDGGDMF.
FSSMMDDDPDDDDDMSF.
FSMDDPDDDDDPDMSF..
FSMMDDDDPDMMSSF...
FSSMMSSMMSSFFF....
.FFFSSFFFF........
"""
FORE_BASE_ROW = 8   # hinge row

HINDWING = """
FFSSMMSSFF.....
FSMDDDDDMSFF...
FSDDDDDGGDMSF..
FSDDDDGDDGDSF..
.FSDDDGDPGDDSF.
.FSMDDDGGDDMSF.
..FSMDPDDDDMSF.
...FSSMDDPMSF..
....FFSSMSSF...
.....FFFSFF....
.......FF......
"""
HIND_BASE_ROW = 1


def grid(txt):
    rows = [r for r in txt.strip('\n').split('\n')]
    w = max(len(r) for r in rows)
    return [r.ljust(w, '.') for r in rows]


def rotx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def cf(pos, rot=None):
    m = np.eye(4)
    if rot is not None:
        m[:3, :3] = rot
    m[:3, 3] = pos
    return m


MIRROR = np.diag([-1.0, 1.0, 1.0, 1.0])


def mirror(m):
    return MIRROR @ m @ MIRROR


class Part:
    def __init__(self, name, m, size, color=(0, 0, 0), mat='SmoothPlastic', transparency=0.0, bone=None):
        self.name, self.m, self.size = name, m, size
        self.color, self.mat, self.transparency, self.bone = color, mat, transparency, bone
        self.children = []


rng = random.Random(7)


def wing_parts(bone_name, bone_m, rows, base_row, fringe_skip_cols=2):
    """Voxel parts for one (right-side) wing, placed in world space via bone_m."""
    parts = []
    h, w = len(rows), len(rows[0])

    def local(col, row, dz=0.0):
        return np.array([(col + 0.5) * S, (base_row - row) * S, dz])

    def add(local_pos, size, key_or_style, name):
        (color, mat) = COL[key_or_style] if isinstance(key_or_style, str) else key_or_style
        m = bone_m @ cf(local_pos)
        parts.append(Part(name, m, size, color, mat, bone=bone_name))

    # run-length merge rows (fluff cells stay single so they can be jittered)
    for r, row in enumerate(rows):
        c = 0
        while c < w:
            k = row[c]
            if k == '.':
                c += 1
                continue
            e = c
            while e + 1 < w and row[e + 1] == k:
                e += 1
            n = e - c + 1
            centre = (local(c, r) + local(e, r)) / 2
            thick = THICK + (0.04 if k in 'GP' else 0.0)  # glow sits slightly proud on both faces
            if k == 'F':
                add(centre + np.array([0, 0, rng.uniform(-0.03, 0.03)]), (S * n, S * 1.02, FLUFF_THICK), 'F', 'Fluff')
            else:
                add(centre, (S * n, S, thick), k, 'Glow' if k in 'GP' else 'Membrane')
            c = e + 1

    # fringe: fuzzy bits poking out past the fluff edge
    def filled(c, r):
        return 0 <= r < h and 0 <= c < w and rows[r][c] != '.'

    for r in range(h):
        for c in range(w):
            if rows[r][c] != 'F' or c < fringe_skip_cols:
                continue
            for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if filled(c + dc, r + dr) or c + dc < fringe_skip_cols:
                    continue
                if rng.random() > 0.65:
                    continue
                sz = S * rng.uniform(0.45, 0.65)
                off = S * rng.uniform(0.45, 0.6)
                p = local(c, r, rng.uniform(-0.05, 0.05)) + np.array([dc * off, -dr * off, 0])
                p += np.array([rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 0])
                add(p, (sz, sz, sz * 0.9), FRINGE, 'Fringe')
    return parts


def build():
    top = []  # list of models: (model_name, mount Part, [bones], [visible parts], motor specs)

    # ---------------- WINGS ----------------
    mount = Part('WingMount', cf([0, 0, 0]), (0.2, 0.2, 0.2), transparency=1.0)
    wing_defs = [
        # name, hinge (torso-local, right side), sweep back, raise, rows, base row
        ('Forewing', [0.25, 0.45, 0.62], math.radians(22), math.radians(6), grid(FOREWING), FORE_BASE_ROW),
        ('Hindwing', [0.25, -0.25, 0.66], math.radians(30), math.radians(-14), grid(HINDWING), HIND_BASE_ROW),
    ]
    bones, visible, motors = [], [], []
    for name, hinge, sweep, raise_, rows, base in wing_defs:
        rot = roty(-sweep) @ rotz(raise_)
        bone_r = cf(hinge, rot)
        parts_r = wing_parts('Right' + name, bone_r, rows, base)
        for side, bm, parts in (('Right', bone_r, parts_r), ('Left', mirror(bone_r), None)):
            bname = side + name
            bone = Part(bname, bm, (0.2, 0.2, 0.2), transparency=1.0)
            bones.append(bone)
            motors.append((bname, 'WingMount', bname))
            if parts is None:
                parts = []
                for p in parts_r:
                    q = Part(p.name, mirror(p.m), p.size, p.color, p.mat, bone=bname)
                    parts.append(q)
            visible += parts

    # root tuft covering the hinges (welded to the mount, doesn't flap)
    for i in range(22):
        x = rng.uniform(-0.55, 0.55)
        y = rng.uniform(-0.45, 0.75)
        z = 0.58 + rng.uniform(0.0, 0.14)
        sz = rng.uniform(0.2, 0.34)
        color, mat = TUFT[i % 3]
        visible.append(Part('Tuft', cf([x, y, z], rotz(rng.uniform(-0.4, 0.4))), (sz, sz, sz), color, mat, bone='WingMount'))
    top.append(('MothWings', mount, bones, visible, motors, 'Torso'))

    # ---------------- ANTENNAE ----------------
    amount = Part('AntennaMount', cf([0, 1.5, 0]), (0.2, 0.2, 0.2), transparency=1.0)  # R6 head centre
    abones, avis, amotors = [], [], []
    base = np.array([0.32, 2.0, -0.25])   # right antenna root on the head top, a bit forward
    bone_r = cf(base)
    # stalk points in bone-local space
    pts = [np.zeros(3)]
    n_seg = 10
    L = 2.1
    for i in range(1, n_seg + 1):
        t = i / n_seg
        phi = math.radians(12 + 40 * t ** 1.6 + (38 * (t - 0.8) / 0.2 if t > 0.8 else 0))  # curls outward/down at the tip
        seg = L / n_seg
        d = np.array([math.sin(phi), math.cos(phi), 0.12])
        d = d / np.linalg.norm(d)
        pts.append(pts[-1] + d * seg)
    parts_r = []

    def rod(a, b, thick, color, mat, name):
        mid = (a + b) / 2
        v = b - a
        length = np.linalg.norm(v)
        yax = v / length
        xax = np.cross(yax, np.array([0, 0, 1.0]))
        if np.linalg.norm(xax) < 1e-6:
            xax = np.array([1.0, 0, 0])
        xax /= np.linalg.norm(xax)
        zax = np.cross(xax, yax)
        R = np.column_stack([xax, yax, zax])
        return Part(name, bone_r @ cf(mid, R), (thick, length + thick * 0.6, thick), color, mat, bone='RightAntenna')

    for i in range(n_seg):
        t = i / n_seg
        th = 0.15 - 0.05 * t
        parts_r.append(rod(pts[i], pts[i + 1], th, (11, 26, 31), 'SmoothPlastic', 'Stalk'))
    # feathery barbs on both sides of the stalk (bipectinate), longest in the middle
    for i in range(2, n_seg):
        t = i / n_seg
        a, b = pts[i - 1], pts[i + 1]
        tan = (b - a) / np.linalg.norm(b - a)
        perp = np.cross(tan, np.array([0, 0, 1.0]))
        perp /= np.linalg.norm(perp)
        length = 0.12 + 0.42 * math.sin(math.pi * min(t / 0.9, 1)) ** 0.8
        for sgn in (1, -1):
            d = perp * sgn * math.cos(math.radians(40)) + tan * math.sin(math.radians(40))
            tip = pts[i] + d * length
            col = (24, 95, 102) if i % 2 == 0 else (16, 58, 64)
            parts_r.append(rod(pts[i], tip, 0.07, col, 'SmoothPlastic', 'Barb'))
            fuzz = FRINGE if sgn == 1 else COL['F']
            parts_r.append(Part('BarbFluff', bone_r @ cf(tip, None), (0.1, 0.1, 0.1), fuzz[0], fuzz[1], bone='RightAntenna'))
    # glowing club at the tip + a spark halfway
    parts_r.append(Part('Glow', bone_r @ cf(pts[-1]), (0.2, 0.2, 0.2), COL['G'][0], 'Neon', bone='RightAntenna'))
    parts_r.append(Part('Glow', bone_r @ cf(pts[0] + np.array([0, 0.02, 0])), (0.22, 0.14, 0.22), COL['S'][0], 'Fabric', bone='RightAntenna'))

    for side, bm in (('Right', bone_r), ('Left', mirror(bone_r))):
        bname = side + 'Antenna'
        abones.append(Part(bname, bm, (0.2, 0.2, 0.2), transparency=1.0))
        amotors.append((bname, 'AntennaMount', bname))
        for p in parts_r:
            if side == 'Right':
                avis.append(p)
            else:
                avis.append(Part(p.name, mirror(p.m), p.size, p.color, p.mat, bone=bname))
    top.append(('MothAntennae', amount, abones, avis, amotors, 'Head'))
    return top


# ---------------- XML ----------------
_ref = [0]


def ref():
    _ref[0] += 1
    return 'RBXMOTH%06d' % _ref[0]


def cf_xml(name, m):
    R = m[:3, :3]
    p = m[:3, 3]
    s = f'<CoordinateFrame name="{name}"><X>{p[0]:.4f}</X><Y>{p[1]:.4f}</Y><Z>{p[2]:.4f}</Z>'
    for i in range(3):
        for j in range(3):
            s += f'<R{i}{j}>{R[i, j]:.6f}</R{i}{j}>'
    return s + '</CoordinateFrame>'


def color_int(c):
    return 0xFF000000 | (c[0] << 16) | (c[1] << 8) | c[2]


def part_xml(p, rid, inner=''):
    return (f'<Item class="Part" referent="{rid}"><Properties>'
            f'<string name="Name">{p.name}</string>'
            f'<bool name="Anchored">false</bool><bool name="CanCollide">false</bool>'
            f'<bool name="CanQuery">false</bool><bool name="CanTouch">false</bool>'
            f'<bool name="CastShadow">false</bool><bool name="Massless">true</bool>'
            f'<bool name="Locked">false</bool>'
            + cf_xml('CFrame', p.m) +
            f'<Color3uint8 name="Color3uint8">{color_int(p.color)}</Color3uint8>'
            f'<token name="Material">{MATERIAL[p.mat]}</token>'
            f'<float name="Transparency">{p.transparency}</float>'
            f'<token name="TopSurface">0</token><token name="BottomSurface">0</token>'
            f'<token name="formFactorRaw">3</token><token name="shape">1</token>'
            f'<Vector3 name="size"><X>{p.size[0]:.4f}</X><Y>{p.size[1]:.4f}</Y><Z>{p.size[2]:.4f}</Z></Vector3>'
            f'</Properties>{inner}</Item>')


def joint_xml(cls, name, p0, p1, c0, c1):
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{name}</string>'
            + cf_xml('C0', c0) + cf_xml('C1', c1) +
            f'<Ref name="Part0">{p0 or "null"}</Ref><Ref name="Part1">{p1}</Ref>'
            f'</Properties></Item>')


def string_value(name, value):
    return (f'<Item class="StringValue" referent="{ref()}"><Properties>'
            f'<string name="Name">{name}</string><string name="Value">{value}</string></Properties></Item>')


def model_xml(model_name, mount, bones, visible, motors, attach_to):
    ids = {b.name: ref() for b in bones}
    mount_id = ref()
    ids[mount.name] = mount_id
    mats = {b.name: b.m for b in bones}
    mats[mount.name] = mount.m
    out = [f'<Item class="Model" referent="{ref()}"><Properties><string name="Name">{model_name}</string></Properties>']
    out.append(string_value('AttachTo', attach_to))
    # mount: holds the motor to the character (Part0 filled in by MothParts.Attach) and the bone motors
    inner = joint_xml('Motor6D', mount.name, None, mount_id, np.eye(4), np.eye(4))
    for mname, p0, p1 in motors:
        c0 = np.linalg.inv(mats[p0]) @ mats[p1]
        inner += joint_xml('Motor6D', mname, ids[p0], ids[p1], c0, np.eye(4))
    out.append(part_xml(mount, mount_id, inner))
    for b in bones:
        out.append(part_xml(b, ids[b.name]))
    for p in visible:
        pid = ref()
        weld = joint_xml('Weld', 'Weld', ids[p.bone], pid, np.linalg.inv(mats[p.bone]) @ p.m, np.eye(4))
        out.append(part_xml(p, pid, weld))
    out.append('</Item>')
    return ''.join(out)


if __name__ == '__main__':
    models = build()
    body = ''.join(model_xml(*m) for m in models)
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           f'<Item class="Folder" referent="{ref()}"><Properties><string name="Name">MothRace</string></Properties>'
           + body + '</Item></roblox>')
    open('/home/claude/moth/MothRace.rbxmx', 'w').write(xml)
    # dump boxes for the preview renderer
    dump = []
    for name, mount, bones, visible, motors, _ in models:
        for p in visible:
            dump.append({'m': p.m.tolist(), 'size': list(p.size), 'color': list(p.color), 'mat': p.mat, 'group': name})
    json.dump(dump, open('/home/claude/moth/boxes.json', 'w'))
    for name, mount, bones, visible, motors, _ in models:
        print(name, 'visible parts:', len(visible), 'bones:', [b.name for b in bones])
