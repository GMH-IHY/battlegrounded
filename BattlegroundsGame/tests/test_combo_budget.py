"""Every example combo route (tools/combo.py ROUTES, docs/MoveData.md "Example routes") must stay
within its damage budget (CombatConfig Budget*), with the server's scaling rules.

Routes listed in OVER_BUDGET are known to be over and waiting on a balance decision: they're
expected failures, and the test says so as soon as one fits again (strict).
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import combo  # noqa: E402

# label -> why it's allowed to be over for now.
OVER_BUDGET = {
    "Ground starter": "20.4 vs 20: the post-linker M1 chain adds up just past the normal budget",
    "Air route": "21.4 vs 20: the air 1 and the spike after the launcher",
}


def _cases():
    for label, route, kind in combo.ROUTES:
        marks = [pytest.mark.xfail(strict=True, reason=OVER_BUDGET[label])] if label in OVER_BUDGET else []
        yield pytest.param(label, route, kind, id=label, marks=marks)


@pytest.mark.parametrize("label,route,kind", list(_cases()))
def test_route_within_budget(label, route, kind):
    _, total = combo.replay(route)
    assert total <= combo.budget(kind), f"{label}: {total} > {kind} budget {combo.budget(kind)}"


def test_rules_match_the_docs():
    # docs/MoveData.md: "Stage 3 finish: M1 -> 1 -> stage 3 grab (about 31 after scaling)".
    _, total = combo.replay("M1_1 > One > Grab3")
    assert total == pytest.approx(31, abs=0.5)


def test_scaling_floor_and_counter():
    rows, _ = combo.replay("!M1_1 > M1_2 > M1_3 > M1_1 > M1_2 > M1_3 > M1_1 > M1_2 > M1_3 > M1_1")
    cfg = combo.config()
    assert rows[0][3] == pytest.approx(3 * cfg["CounterHitDamage"], abs=0.05)
    assert min(r[2] for r in rows) == pytest.approx(cfg["ScalingMin"])
