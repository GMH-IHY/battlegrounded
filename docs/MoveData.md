# Move Data — first build

Draft, Sep 29, 2026. Every number is a placeholder chosen so the rules in [DesignPlan.md](DesignPlan.md) fit together; playtests tune them.

**In the game (phase 2):** the global rules and stamina are `ReplicatedStorage > Combat > CombatConfig`; the Sword, Dagger and Lotus tables are `Combat > MoveSets > Sword / Dagger / Lotus` (meter rules in `CombatConfig`) (plus what the tables here don't list: hit pause per move, pushback, the step / lunge distance, the slash shape). `python -m pytest tests` checks these tables against the move sets, so change both together. Wind and Moth are still design only. Lotus is built as of phase 3 (see its notes below).

## Conventions

- **Frames:** 60 per second. Startup = frames before the first active frame.
- **Advantage:** + means the attacker can act first.
- **Hitbox:** width × height × length in studs, placed that many studs in front of the root part. An R6 character is about 2 wide and 5 tall.
- **Hit results:** Stun = normal hit stun. Ragdoll = knocked down. Launch = sent up.
- **Flash:** yellow = can't be blocked, can be parried. Blue = can't be parried, dash to dodge. None = normal.

## Global rules

| Rule | Value |
| --- | --- |
| HP | 100 |
| Block startup | 1 frame, buffered during stun |
| Blocking from behind | Fails (spores excepted) |
| Parry window / whiff recovery | 6 frames / 20 frames |
| Gap between M1s | 2 frames |
| Counter-hit | +8 frames of stun, ×1.2 damage |
| Get-up | 30 frames after landing, first 10 invincible; dash = tech roll |
| Juggle limit | 1 launch per combo; later launches become knockdowns |
| Shrinking stun | −2 frames of stun per hit in a combo |
| Damage scaling | From the 4th hit ×0.85 per hit, minimum ×0.4; moves after a 1 do ×0.8 |
| Damage budget | Normal confirm 15–20; best stage 3 confirm ≤ 35; maximum with ultimate ≤ 45 |

## Stamina

| Item | Value |
| --- | --- |
| Max SP | 100 |
| Refill | 15/s after 0.9 s without spending (ground); slower in the air |
| Dash / wall hop / parkour / abilities | 0 SP (dash cooldown 1.8 s) |
| Blocking | SP loss = damage blocked × 2.5 |
| Parry | +10 SP |
| Burnout | No stamina actions; blocked hits deal 25% chip damage; refill ×1.25; ends when full |

## Sword (primary)

| Move | Startup | Active | Recovery | On hit | On block | Damage | Hitbox | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M1 1 / M1 2 | 5 | 2 | 11 | Stun 15 (+3); gap 2 | 0 | 3 | 5×5×5, 3 in front | Cancel into 1 on hit |
| M1 3 | 7 | 3 | 18 | Ragdoll, knocked back 20 studs | −8 | 5 | 6×5×6, 3.5 in front | |
| M1 3 + Space (launcher) | 8 | 3 | 14 | Launch 25 studs up; jump right after | −10 | 4 | 5×7×5, 3 in front | |
| Air M1 1 / 2 | 5 | 2 | 11 | Stun 15, target hangs | 0 | 3 | 5×5×5, 3 in front | |
| Air M1 3 (downward slash) | 16 | 4 | 20 | Spiked to the ground, ragdoll | Unblockable, **yellow** | 6 | 6×8×6, 2 in front, 2 below | |
| Running M1 (lunge) | 12 | 6 (18 studs) | 24 (30 on miss) | Stun 30 | −22 | 6 | 5×5×5, moves with you | Can go behind a block |
| 1 | 12 | 4 | 22 | Stun 40, no ragdoll | −14 | 8 | 7×5×6, 3.5 in front | Cooldown 5 s (shared) |
| Air 1 | 10 | 4 | 18 | Stun 36, target hangs | −12 | 7 | 7×5×6, 3.5 in front | Shares 1's cooldown |

1's 40-frame stun lets any ability with startup ≤ ~25 frames follow for free.

## Dagger (secondary, right click)

| Move | Startup | Active | Recovery | On hit | On block | Damage | Hitbox | Cooldown |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Stab | 4 | 2 | 12 | Stun 16 → cancel into 1 | −2 | 2 | 3×4×4, 2.5 in front | 2.5 s |
| Air slash | 4 | 2 | 10 | Stun 16 → cancel into air 1 | −2 | 2 | 4×4×4, 2.5 in front | Shared |

## Lotus Fungus (magic)

**Meter**

| Rule | Value |
| --- | --- |
| Stages | 1: 0–40 · 2: 40–80 · 3: 80–100 |
| Taking damage | +0.5 meter per HP lost |
| Stage 1 stab hit | +10 |
| Stage 2 grab | Meter jumps to 80 |
| R heal channel (hold, ~1 s) | +6 HP, +20 meter; getting hit = counter-hit on you |
| R rip out (tap) | −10 HP, −25 meter |
| Stage 3 move | −15 to −20 meter |
| Stage 3 stab counter-hit | Refunds its cost |
| Missing a stage 3 move | −8 HP, doesn't refill the meter; short stagger |
| At stage 3 | Take ×1.25 damage |
| Passive drain | None |
| After G | Meter set to 20 |

**2: Stab**

| Stage | Startup | Active | Recovery | On hit | On block | Damage | Hitbox | Properties | Cooldown / meter |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 10 | 3 | 16 | Stun 20 | −6 | 5 | 2×2×9 strand | Parryable | 4 s; +10 on hit |
| 2 (ground strand) | 16 | Travels 30 studs at 60 studs/s | 20 | Launch 22 | Unblockable, **yellow** | 7 | 4×3×4 moving along the ground | Hits grounded and ragdolled targets, not airborne | 8 s |
| 3 | 14 | 4 | 20 | Stun 30 | **+8**, 15 studs pushback | 14 | 2.5×2.5×10 | 1 armour point; counter-hit consumes them and refunds meter | 6 s; −15 |
| Impale (stages 1 and 3, target airborne) | 12 | 3 | 20 | Held ~20 frames, then dropped (ragdoll); ends the combo | As the stage | ×1.6 of that stage | Growth erupts from the ground under the target, aim up to ~25 studs | Fungal patch appears under the target during startup | As the stage |

**3: Spore**

| Stage | Startup | Projectile | Recovery | On hit | On block | Damage | Properties | Cooldown / meter |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 9 | 1 sphere (2 studs), 80 studs/s, 40 range | 14 | Stun 18 (counter-hit 30) | +2 | 4 | Blockable from any side, even Infested; Wind can redirect it | 4 s |
| 2 | 12 | 3 in a 30° fan, 70 studs/s, 35 range | 16 | Applies **Infested** | 0 | 2 each | Same | 7 s |
| 3 (beam) | 24 | Beam 4×4×60, active 30 | 28 | Heavy hit, ragdoll | Unblockable, **blue** | 22 | Interruptible (no armour) | 10 s; −20 |

**4: Grab**

| Stage | Startup | Active | Recovery | On hit | On block | Damage | Hitbox | Properties | Cooldown / meter |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 18 | 3 | 30 | Feast, then throw 12 studs, ragdoll | Blockable: does nothing, you're open | 8 | 4×5×4, 2.5 in front | | 7 s |
| 2 | 20 | 3 | 26 | Combo ender; meter jumps to 80 | Unblockable, **blue** | 10 | Same | Slow for neutral, fine after a 1 | 10 s |
| 3 | 16 | 3 | 30 | Feast with everything, ragdoll | Blockable | 25 | Same | Can't be interrupted during startup | 12 s; −20 |

**R and G**

| Move | Input | Timing | Effect | Cooldown |
| --- | --- | --- | --- | --- |
| R heal | Hold R (up to 60 frames) | Channelled | +6 HP, +20 meter; a hit during it is a counter-hit | 8 s (shared) |
| R rip out | Tap R | Startup 10 | −10 HP, −25 meter | Shared |
| G | G at 100 meter | 30-frame startup with a flash | ~8 s of stage 3 form: stage 3 moves cost no meter; misses still hurt; meter to 20 after | 90 s |

**Links:** sword 1 → any Lotus move is free.

**Follow-ups (first draft, phase 3):** within 1 s of landing a hit with a different Lotus key, a spore (3) that hits adds +6 stun, and a grab (4) reaches 2 studs further. So stab → spore → grab is the stage 1 string.

**How the game does it (phase 3):** the stage is read when you press the key (`Loadout`), and the server checks it again. The stage 2 strand and the spores are server projectiles (`Projectiles`), parryable (no stagger) and blockable from any side. The impale is chosen when an airborne opponent is within 25 studs in front; the fungal patch appears under them at startup and the column rises from it. A grab or impale hit holds the target (state Held) and then throws or drops them into a knockdown. Stage 3 moves take their cost at startup; a miss costs 8 HP and a 20-frame stagger at the end of the move. The heal is a channel: letting R go ends it, and letting go within 10 frames turns it into the rip-out. Dummies never drop below 1 HP from fungus costs.

## Wind (element, Q)

| Input | Startup | Active | Recovery | Effect | On block | Damage | Hitbox | Cooldown |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Q + forward / sideways / standing | 10 | 6 | 18 | Push 30 studs (stagger, no ragdoll) | Pushes, no damage | 3 | Cone 10×6×18 | 8 s |
| Q + back | 10 | 6 | 18 | Pull to 5 studs in front of you | Same | 3 | Same | Shared |

Both redirect projectiles inside the cone and add +25 status build-up.

## Statuses

| Status | Applied by | Effect | Ends |
| --- | --- | --- | --- |
| Build-up bar | M1 +20, counter-hit +35, parry +40, 1 +25, dagger +15, Q +25 | Full at 100 → the element's status | Drains 15/s after 2 s without landing an M1 or Q; 6 s lockout after triggering |
| Drafted (Wind) | Full build-up bar | Next launch ×1.5 height, or next ragdoll +0.6 s | 5 s, or when used |
| Infested (Lotus stage 2 spore) | Spore hit | Next Lotus move that hits their block wraps them: 1.0 s knockdown | 6 s, or when used; spores never set it off |

## Moth (race, Ctrl) — after the lantern rework

| Move | Input | SP | Details |
| --- | --- | --- | --- |
| Wing burst | Tap Ctrl | 35 | ~20 studs toward the camera; cooldown 0.4 s |
| Lantern throw | Hold Ctrl, release | 0 | Charge 0.2–1.0 s; no damage; 30-stud light; hangs 5 s |
| Flight | Hold Space in the air inside your light | 20/s | Ends when you leave the light, burn out, or press M1 |
| Recall | Ctrl while the lantern is out | 0 | Flies back to you |
| Lantern knocked down | Any hit on it | — | Can't be thrown for 6 s |

## Example routes (for the damage budget)

1. **Ground starter:** M1 → 1 → stage 1 spore → M1 chain.
2. **Air route:** M1, M1, M1 + Space (launch) → air 1 → air dagger → air M1 3 (spike) → down slam.
3. **Slow-build starter:** dagger → 1 → any ability.
4. **Stage 3 finish:** M1 → 1 → stage 3 grab (≈ 31 after scaling).
5. **Drafted route:** win exchanges until Drafted → higher launch → longer air combo.
