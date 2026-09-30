"""The move tables in docs/MoveData.md and the move sets the game runs (src/shared/Combat/MoveSets)
must say the same thing: startup, active, recovery, damage and on-block advantage for every Sword,
Dagger and Lotus move.

    cd BattlegroundsGame && python -m pytest tests
"""
import os
import re

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "..", "docs", "MoveData.md")
SETS = os.path.join(ROOT, "src", "shared", "Combat", "MoveSets")

# Row name in the doc -> move ids it describes.
ROWS = {
    "Sword": {
        "M1 1 / M1 2": ["Sword.M1_1", "Sword.M1_2"],
        "M1 3": ["Sword.M1_3"],
        "M1 3 + Space (launcher)": ["Sword.Launcher"],
        "Air M1 1 / 2": ["Sword.AirM1_1", "Sword.AirM1_2"],
        "Air M1 3 (downward slash)": ["Sword.AirSpike"],
        "Running M1 (lunge)": ["Sword.Lunge"],
        "1": ["Sword.One"],
        "Air 1": ["Sword.AirOne"],
    },
    "Dagger": {
        "Stab": ["Dagger.Stab"],
        "Air slash": ["Dagger.AirSlash"],
    },
}


def first_number(cell):
    m = re.search(r"[-−]?\d+(\.\d+)?", cell)
    return float(m.group(0).replace("−", "-")) if m else None


def doc_rows(section):
    text = open(DOC, encoding="utf-8").read()
    start = text.index(f"## {section}")
    block = text[start:text.index("\n## ", start + 3)]
    lines = [ln for ln in block.splitlines() if ln.startswith("|")]
    header = [c.strip() for c in lines[0].strip("|").split("|")]
    rows = {}
    for ln in lines[2:]:
        cells = [c.strip() for c in ln.strip("|").split("|")]
        rows[cells[0]] = dict(zip(header, cells))
    return rows


def luau_moves():
    moves = {}
    for name in os.listdir(SETS):
        text = open(os.path.join(SETS, name), encoding="utf-8").read()
        for block in re.split(r"(?:Define|lotus)\(\{", text)[1:]:
            fields = {}
            for key in ("Startup", "Active", "Recovery", "WhiffRecovery", "Damage", "OnBlock", "MeterCost", "Cooldown"):
                m = re.search(rf"^\t\t{key} = (-?[\d.]+),", block, re.M)
                if m:
                    fields[key] = float(m.group(1))
            guard = re.search(r'Guard = "(\w+)"', block)
            fields["Guard"] = guard.group(1) if guard else "Normal"
            moves[re.search(r'Id = "([\w.]+)"', block).group(1)] = fields
    return moves


CASES = [(section, row, move_id) for section, rows in ROWS.items() for row, ids in rows.items() for move_id in ids]


@pytest.mark.parametrize("section,row,move_id", CASES, ids=[c[2] for c in CASES])
def test_move_matches_doc(section, row, move_id):
    doc = doc_rows(section)[row]
    move = luau_moves()[move_id]
    for column, key in (("Startup", "Startup"), ("Active", "Active"), ("Recovery", "Recovery"), ("Damage", "Damage")):
        assert first_number(doc[column]) == move[key], f"{column}: doc {doc[column]!r}, game {move.get(key)}"
    on_block = doc["On block"]
    if "Unblockable" in on_block:
        assert move["Guard"] != "Normal", "the doc says unblockable"
    else:
        assert first_number(on_block) == move.get("OnBlock", 0), f"On block: doc {on_block!r}, game {move.get('OnBlock', 0)}"
    miss = re.search(r"\((\d+) on miss\)", doc["Recovery"])
    if miss:
        assert float(miss.group(1)) == move.get("WhiffRecovery"), "whiff recovery"


# Lotus: the tables sit under bold sub-headings of "## Lotus Fungus (magic)". Row -> move ids.
LOTUS_ROWS = {
    "2: Stab": {
        "1": ["Lotus.Stab1"],
        "2 (ground strand)": ["Lotus.Strand2"],
        "3": ["Lotus.Stab3"],
        "Impale (stages 1 and 3, target airborne)": ["Lotus.Impale1", "Lotus.Impale3"],
    },
    "3: Spore": {"1": ["Lotus.Spore1"], "2": ["Lotus.Spore2"], "3 (beam)": ["Lotus.Beam3"]},
    "4: Grab": {"1": ["Lotus.Grab1"], "2": ["Lotus.Grab2"], "3": ["Lotus.Grab3"]},
    "R and G": {"R heal": ["Lotus.Heal"], "R rip out": ["Lotus.RipOut"], "G": ["Lotus.Form"]},
}
# The impale does x1.6 of the stab of the same stage.
IMPALE_OF = {"Lotus.Impale1": "Lotus.Stab1", "Lotus.Impale3": "Lotus.Stab3"}


def lotus_table(title):
    text = open(DOC, encoding="utf-8").read()
    start = text.index("## Lotus Fungus")
    start = text.index(f"**{title}**", start)
    lines = []
    for ln in text[start:].splitlines()[1:]:
        if ln.startswith("|"):
            lines.append(ln)
        elif lines:
            break
    header = [c.strip() for c in lines[0].strip("|").split("|")]
    return {cells[0]: dict(zip(header, cells)) for cells in ([c.strip() for c in ln.strip("|").split("|")] for ln in lines[2:])}


LOTUS_CASES = [(table, row, move_id) for table, rows in LOTUS_ROWS.items() for row, ids in rows.items() for move_id in ids]


@pytest.mark.parametrize("table,row,move_id", LOTUS_CASES, ids=[c[2] for c in LOTUS_CASES])
def test_lotus_matches_doc(table, row, move_id):
    doc = lotus_table(table)[row]
    moves = luau_moves()
    move = moves[move_id]
    if table == "R and G":
        timing = doc["Input"] + " " + doc["Timing"]
        if move_id == "Lotus.Heal":
            assert f"up to {int(move['Active'])} frames" in timing
        else:
            assert first_number(doc["Timing"]) == move["Startup"], f"Startup: doc {doc['Timing']!r}"
        assert first_number(doc["Cooldown"]) in (None, move["Cooldown"]), f"Cooldown: doc {doc['Cooldown']!r}"
        return
    for column in ("Startup", "Recovery"):
        assert first_number(doc[column]) == move[column], f"{column}: doc {doc[column]!r}, game {move.get(column)}"
    if "Active" in doc and first_number(doc["Active"]) is not None and "Travels" not in doc["Active"]:
        assert first_number(doc["Active"]) == move["Active"], f"Active: doc {doc['Active']!r}"
    if move_id in IMPALE_OF:
        assert move["Damage"] == pytest.approx(moves[IMPALE_OF[move_id]]["Damage"] * 1.6), "impale = x1.6 of the stab"
    else:
        assert first_number(doc["Damage"]) == move["Damage"], f"Damage: doc {doc['Damage']!r}, game {move['Damage']}"
    on_block = doc["On block"]
    if "Unblockable" in on_block:
        assert move["Guard"] != "Normal", "the doc says unblockable"
    elif first_number(on_block) is not None:
        assert first_number(on_block) == move.get("OnBlock", 0), f"On block: doc {on_block!r}, game {move.get('OnBlock', 0)}"
    cost = re.search(r"[-−](\d+)$", doc["Cooldown / meter"])
    if cost and move_id not in IMPALE_OF:
        assert float(cost.group(1)) == move.get("MeterCost"), "meter cost"
    if move_id not in IMPALE_OF:
        assert first_number(doc["Cooldown / meter"]) == move["Cooldown"], "cooldown"


def test_every_move_is_documented():
    documented = {i for rows in ROWS.values() for ids in rows.values() for i in ids}
    documented |= {i for rows in LOTUS_ROWS.values() for ids in rows.values() for i in ids}
    assert sorted(set(luau_moves()) - documented) == [], "add these moves to docs/MoveData.md and ROWS here"
