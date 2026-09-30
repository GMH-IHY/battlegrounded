"""Combo damage checker: replays a combo route with the server's damage rules and checks it against
the damage budget (docs/DesignPlan.md, "Damage budget"; CombatConfig Budget*).

The rules are HitResolver's: from the ScalingFrom-th hit x ScalingPerHit per hit (never below
ScalingMin), every move after a linker (sword 1) x AfterLinker, a counter-hit x CounterHitDamage,
each hit rounded to 0.1. A target at Lotus stage 3 takes x Stage3DamageTaken on top. Numbers are read
from src/ (the move sets and CombatConfig), so the checker always uses what the game runs.

    python tools/combo.py                        # every example route (ROUTES) against its budget
    python tools/combo.py "M1_1 > M1_2 > One > Lotus.Grab3"
    python tools/combo.py "!M1_1 > One > Spore2 x3" --stage3

A step is a move id, or the end of one ("M1_1" = "Sword.M1_1"); "!" in front = a counter-hit;
" xN" after = N hits of it (a fan of spores).
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETS = os.path.join(ROOT, "src", "shared", "Combat", "MoveSets")
CONFIG = os.path.join(ROOT, "src", "shared", "Combat", "CombatConfig.luau")

# The example routes of docs/MoveData.md ("Example routes"), with the budget each must stay under.
ROUTES = [
    ("Ground starter", "M1_1 > One > Spore1 > M1_1 > M1_2 > M1_3", "Normal"),
    ("Air route", "M1_1 > M1_2 > Launcher > AirOne > AirSlash > AirSpike > M1_1", "Normal"),
    ("Slow-build starter", "Dagger.Stab > One > Grab1", "Normal"),
    ("Stage 3 finish", "M1_1 > One > Grab3", "Stage3"),
    ("Drafted route", "M1_1 > M1_2 > Launcher > AirOne > AirSlash > AirM1_1 > AirM1_2 > AirSpike > M1_1", "Stage3"),
]


def config():
    text = open(CONFIG, encoding="utf-8").read()
    return {k: float(v) for k, v in re.findall(r"^\t(\w+) = (-?[\d.]+),", text, re.M)}


def moves():
    out = {}
    for name in sorted(os.listdir(SETS)):
        text = open(os.path.join(SETS, name), encoding="utf-8").read()
        for block in re.split(r"(?:Define|lotus|wind)\(\{", text)[1:]:
            move_id = re.search(r'Id = "([\w.]+)"', block).group(1)
            damage = re.search(r"^\t\tDamage = (-?[\d.]+),", block, re.M)
            out[move_id] = {
                "damage": float(damage.group(1)) if damage else 0.0,
                "linker": re.search(r"^\t\tLinker = true", block, re.M) is not None,
            }
    return out


def find(step, all_moves):
    if step in all_moves:
        return step
    hits = [m for m in all_moves if m.endswith("." + step)]
    if len(hits) != 1:
        raise SystemExit(f"unknown or ambiguous move {step!r} ({', '.join(hits) or 'no match'})")
    return hits[0]


def parse(route, all_moves):
    steps = []
    for raw in route.split(">"):
        raw = raw.strip()
        m = re.fullmatch(r"(!?)([\w.]+)(?:\s*x(\d+))?", raw)
        if not m:
            raise SystemExit(f"can't read step {raw!r}")
        counter, name, times = m.group(1) == "!", find(m.group(2), all_moves), int(m.group(3) or 1)
        steps += [(name, counter)] * times
    return steps


def replay(route, stage3=False, cfg=None, all_moves=None):
    """[(move, counter, scale, damage)], total — the way HitResolver adds up a combo."""
    cfg = cfg or config()
    all_moves = all_moves or moves()
    hits, after_linker, rows, total = 0, False, [], 0.0
    for move_id, counter in parse(route, all_moves):
        move = all_moves[move_id]
        hits += 1
        scale = 1.0
        if hits >= cfg["ScalingFrom"]:
            scale = max(cfg["ScalingPerHit"] ** (hits - cfg["ScalingFrom"] + 1), cfg["ScalingMin"])
        if after_linker:
            scale *= cfg["AfterLinker"]
        damage = move["damage"] * scale * (cfg["CounterHitDamage"] if counter else 1)
        damage = int(damage * 10 + 0.5) / 10  # math.floor(x * 10 + 0.5) / 10
        if stage3:
            damage *= cfg["Stage3DamageTaken"]
        if move["linker"]:
            after_linker = True
        total += damage
        rows.append((move_id, counter, scale, damage))
    return rows, round(total, 2)


def budget(name, cfg=None):
    cfg = cfg or config()
    return cfg["Budget" + name]


def report(label, route, stage3, limit, cfg, all_moves):
    rows, total = replay(route, stage3, cfg, all_moves)
    print(f"{label}: {route}" + ("  (target at stage 3)" if stage3 else ""))
    for i, (move_id, counter, scale, damage) in enumerate(rows, 1):
        print(f"  {i:2d}. {('!' if counter else '') + move_id:22s} x{scale:.2f}  {damage:5.1f}")
    verdict = "" if limit is None else ("  OK" if total <= limit else f"  OVER BUDGET ({limit:g})")
    print(f"  total {total:.1f}{verdict}\n")
    return limit is None or total <= limit


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("route", nargs="?", help='e.g. "M1_1 > One > Grab3"')
    parser.add_argument("--stage3", action="store_true", help="the target is at Lotus stage 3 (takes more damage)")
    parser.add_argument("--budget", choices=("Normal", "Stage3", "Max"), help="check against this budget")
    args = parser.parse_args()
    cfg, all_moves = config(), moves()
    if args.route:
        limit = budget(args.budget, cfg) if args.budget else None
        ok = report("Route", args.route, args.stage3, limit, cfg, all_moves)
    else:
        ok = all([report(label, route, False, budget(kind, cfg), cfg, all_moves) for label, route, kind in ROUTES])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
