"""Every animation the game uses, in one list. build.py, preview.py and viewer.py read this.

Each entry: {"name", "priority" (Enum.AnimationPriority token), "loop", "keys": [(time, pose)], "notes"}.
"""
from anims import ALL as MOVEMENT
from parkour_anims import ALL_NEW as PARKOUR
from moth_anims import MOTH
from combat_anims import COMBAT

ALL = MOVEMENT + PARKOUR + MOTH + COMBAT

_names = [a["name"] for a in ALL]
assert len(_names) == len(set(_names)), "two animations share a name"
