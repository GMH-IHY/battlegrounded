# Battlegrounds Game — Master Design Plan

Sep 26, 2026 · @Isaac

## Vision & pillars

A Roblox battlegrounds game where players build their own fighter from five choices and win through execution, reads and movement, not by having the newest character. Like Die of Death, it wears the look and feel of classic 2010–2014 Roblox while playing as a tighter fighting game than the modern battlegrounds it draws from.

Design pillars:

1. **Build is identity.** Weapon + secondary + magic system + element + race = one fighter. Every slot changes how you play, and every slot carries lore.
2. **Fundamentals beat cooldowns.** Spacing, blocking, parrying, feints and punishes decide fights. Abilities extend what good fundamentals earn; they do not replace them.
3. **Movement is a skill.** Dash cancels, air options and momentum give players room to express themselves and escape pressure without a "get off me" button.
4. **Awakening is a resource, not a transformation.** Each magic system spends its bar differently, so meter management is part of the build's skill ceiling.
5. **Readable, then deep.** A new player can pick a build and understand it in one match; tech is discovered, not required.
6. **Classic Roblox aesthetic.** UI, emotes and presentation draw on 2010–2014 Roblox. The game doesn't mock other games, and the lore stays sincere while it's adapted to fit a Roblox world.

## Controls

The input map gives every build slot its own key, so a player always knows which choice a move comes from. Proposed additions are marked *(proposed)*.

| Key | Action | Source slot | Notes |
| --- | --- | --- | --- |
| WASD | Move | — | Directional input also modifies attacks (see Combat core) |
| Left click | M1 | Weapon | 4–5 hit string; forward/back/air variants |
| Right click | Feint | — | Cancels M1 or ability startup; costs posture |
| Shift | Dash | — | Directional; cancels recovery on hit |
| F | Block (hold) / Parry (tap) | — | SF3-style timed parry on tap |
| 1 | Weapon ability | Weapon | Variants: tap, hold, air, while running, after M1 |
| 2, 3, 4 | Magic abilities | Magic system | Draw on or feed the awakening bar |
| R | Magic special | Magic system | Main spender of the awakening bar |
| Q | Element special | Element | Applies the element's status effect |
| Ctrl | Race special | Race | Race only; no other action shares this key |
| G | Ultimate | Magic system | Long cooldown, YBA-style (e.g. time stop) |
| T | Secondary weapon | Secondary | Offhand weapon or consumable item |
| E | Interact | — | Map objects, pickups; grabs *(proposed)* |
| Space | Jump; landing roll | — | Roll when landing from above jump height; double jump *(proposed)* |

Console and mobile layouts come later; keep every action on one button so remapping stays simple.

## Combat core

Combat runs on a 60 Hz frame model with a posture meter, a strike-block-parry-feint triangle, and cancel rules — JJS's pace and readability on top of Street Fighter's structure and Deepwoken's mind games.

**What we take from each reference**

| Reference | What we borrow | What we leave out |
| --- | --- | --- |
| Jujutsu Shenanigans | Fast M1 strings, ragdoll/knockback finishers, flashy abilities, readable camera | Unpunishable ability spam, M1 stun-lock |
| Deepwoken | Feints, posture that breaks, parry windows, weapon-type identity | Slow RPG grind, gear stat walls |
| Street Fighter III | Tap parry (block for free and gain advantage), deep neutral | Arcade-only execution barriers |
| Street Fighter 6 | Drive-style shared resource, Drive Rush-like dash cancel, burnout state, clear frame advantage | Motion inputs |

**The core loop**

- **M1 string:** 4 hits (weapon may change count). Hit 4 knocks back or launches depending on held direction. Missing an M1 has recovery you can be punished in.
- **Block (hold F):** stops damage, drains posture. Blocking from behind fails.
- **Parry (tap F, \~6-frame window):** negates the hit and gives frame advantage. Whiffing a parry leaves you vulnerable for \~20 frames, so mashing is punished.
- **Feint (right click):** cancels your M1 or ability startup. Costs posture and has a cooldown (\~2 s) so it stays a read, not a loop.
- **Guard break:** empty posture → stunned for \~1 s and the next hit is a guaranteed combo starter.
- **Grab / guard-crush option:** a slow unblockable (weapon hold-1 or a dedicated input) that beats turtling but loses to any strike.

**Resources on the HUD**

1. Health
2. Posture — drains on block and feint, regenerates when not blocking
3. Awakening bar — per magic system (own section)
4. Cooldowns for 1–4, R, Q, Ctrl, G

**Frame and cancel rules**

- Every move has startup / active / recovery values and an on-block advantage, stored in data, not scripts.
- Cancel hierarchy: M1 → weapon ability → magic ability → R / Q → G. Dash can cancel recovery only on hit.
- Hitstun decays over a combo (combo scaling) and damage scales down after \~5 hits, so combos are expressive but not touch-of-death.
- Burst / escape: a shared "combo breaker" costs awakening bar, which forces a choice between escaping and spending on your magic.

## Movement system

Movement is momentum-based: every option preserves or redirects speed, so skilled players chain them into routes that newer players can't follow.

| Option | Input | Rule |
| --- | --- | --- |
| Dash | Shift + direction | 2 charges, \~1.5 s recharge each; i-frames only on the first \~4 frames |
| Dash cancel | Shift during move recovery (on hit) | Extends combos; costs a dash charge |
| Side-dash → M1 | Shift + A/D, then M1 | Fast whiff-punish tool |
| Sprint | Double-tap W or hold after dash | Enables running variants of 1 |
| Double jump | Space in air | Resets on landing or on hit |
| Air dash | Shift in air | 1 per airtime |
| Wall run / wall jump | Jump into wall | Map-dependent; keeps momentum |
| Landing roll | Space on landing, when falling from above jump height | Keeps momentum and skips landing lag; replaces sliding, which isn't in the game |
| Tech roll | Dash on landing from knockdown | Avoids okizeme (wake-up pressure) |

Skill expression comes from buffer windows (inputs queue \~6 frames early), animation cancels, and momentum carried between options. Every movement tool should have a clear counter so it never becomes a free escape: dash i-frames are short and dash recovery can be punished.

## Loadout

A fighter is five picks; each slot owns specific keys and one clear job, so any combination still plays coherently.

| Slot | Count | Owns | Job in the build | Tied to region? |
| --- | --- | --- | --- | --- |
| Weapon | 8 | M1, key 1 (+ variants) | Range, speed, M1 string shape, combo starter | No |
| Secondary weapon | 8 | T | Offhand weapon or consumable item: extends combos, covers a build's weak spot, or adds utility | No |
| Magic system | 8 | Keys 2, 3, 4, R, G, awakening bar | Game plan, resource style, ultimate; sets how strong your element is | Yes |
| Element | 8 | Key Q, status effect on some hits | Status effect and matchup flavour | Yes (birth conditions) |
| Race | 8 | Key Ctrl, passive stats | Movement or defensive trait | Yes (one per region) |

Players can mix and match freely: race, element, magic system and weapons don't have to come from the same region. The region link is lore only.

**Weapon key-1 variant template** (every weapon fills the same grid, so moves stay learnable):

| Variant | Input | Typical role |
| --- | --- | --- |
| Tap | 1 | Main special |
| Hold | Hold 1 | Charged / armoured version or guard crush |
| Air | 1 in air | Spike or air-to-ground |
| Running | 1 while sprinting | Gap-closer |
| After M1 | 1 after hit 2–4 | Combo route |

**Placeholders for your roster** — to fill when you walk me through the lore:

- Weapons (8): *TBD*
- Secondary weapons (8): *TBD*
- Magic systems (8, one per region; known so far: Lotus Fungus, Sirellium): *TBD*
- Elements (8): *Fire, Cold, Lightning, Wind, Shadow, Iron, Light, Earth (tied to the conditions you're born in)*
- Races (8): one per region, names and traits *TBD*

For each entry we'll capture: lore summary, playstyle in one line, moves per key, awakening interaction, and any cross-slot synergies (e.g. a race whose lore ties to one element).

Lore for every slot lives in Lore.

## Awakening bar

The awakening bar is each magic system's own resource — how it fills, what spends it, and what happens when it's full or empty all differ — closer to SF6's Drive gauge than to a JJS awakening.

Every magic system defines four rules:

1. **Fill:** how it gains meter (landing hits, taking damage, parrying, standing still, time passing).
2. **Spend:** what uses it (R special, empowered 2/3/4, combo breaker).
3. **Full state:** a small bonus at max, never a new moveset.
4. **Empty state:** a drawback, like SF6 burnout, so spending everything is a real risk.

Example archetypes to map your eight systems onto:

| Archetype | Fill | Spend | Twist |
| --- | --- | --- | --- |
| Charge | Hold a key to channel | Big R release | Vulnerable while charging |
| Overheat | Every spell adds heat | Heat powers spells up | At 100% you are locked out briefly |
| Blood price | Taking damage | Empowered spells | Spending can cost HP |
| Stacks | Hitting with magic | Consume stacks on R | Stacks decay if you stop attacking |
| Debt | Starts full | Spells borrow from it | Refills slowly; empty = weaker defence |
| Rhythm | Timed inputs / parries | Perfect timing = free casts | Missed timing drains bar |

The shared combo breaker also costs bar, so every system faces the same question: escape now or save it.

**From the lore:** a magic system makes elemental power strong-sided (Lotus Fungus) or weak-sided (Sirellium), so each magic system carries a strength modifier for Q and element status effects. The region energy types (Positive, Negative, Finance) are lore categories only and have no gameplay effect.

## Ultimates (G)

The ultimate is a match-shaping move on a \~90–120 s cooldown, like YBA's time stop, and it must always have counterplay.

- **Where it comes from:** each magic system has its own ultimate, so there are 8 to balance.
- **Types:** field effect (time stop, gravity zone), cinematic hit (grab-based, whiffable), buff window (8–10 s), or counter stance.
- **Counterplay rules:** every ultimate has a visible startup (≥ 15 frames or a clear flash), can be dodged, parried or outranged, and whiffing it puts it on full cooldown.
- **Time-stop-style effects:** cap at \~3 s, the frozen target takes reduced damage, and their posture can't break during the stop.
- **Not an awakening:** no moveset swap; the awakening bar and G stay separate.

## Balance framework

Five slots of 8 make 8⁵ = 32,768 builds, so we balance slots against budgets and rules, never build by build.

- **Slot budgets:** each slot gets a fixed budget for damage, range, mobility, defence and utility. A weapon high in range must pay in speed or damage.
- **Lanes:** each slot may only affect its own lane (race = movement/defence, element = status, etc.). This blocks runaway stacking like 3 slots all adding speed.
- **Status caps:** element effects share a cap (e.g. one DoT and one slow at a time), and duration shrinks on repeat application.
- **Combo scaling:** global damage and hitstun decay keep any combination from looping.
- **Telemetry:** log pick rate, win rate and damage per slot item, plus top pair synergies. Flag anything above 55% win rate or 25% pick rate.
- **Test matrix:** before launch, test each weapon against each weapon (64 matchups) with a fixed "baseline" loadout in the other slots, then spot-check the most-picked combos.

## Technical architecture

The server owns every hit, resource and cooldown; the client predicts animations and movement so combat feels instant, and all move data lives in ModuleScripts so designers tune numbers without touching code.

| System | Approach |
| --- | --- |
| Project setup | Rojo + Wally + strict Luau, shared/server/client layout |
| Input | Client InputController maps keys → action names, sends one validated remote per action |
| Move data | One ModuleScript per weapon / magic / element / race: frames, damage, posture, hitbox, VFX ids |
| State machine | Server-side per-character state (idle, attacking, blocking, stunned, ragdoll) gates every action |
| Hitboxes | Server spatial queries (GetPartBoundsInBox / shapecasts) with small lag compensation; client draws VFX immediately |
| Networking | Rate-limited remotes, server-validated cooldowns and range, no client-sent damage |
| Animation | Animation markers drive active frames; priorities set so movement never overrides attacks |
| Data | Loadouts, unlocks and stats saved with session locking and retry |
| Testing | Gated debug commands: frame-data overlay, hitbox view, infinite meter, dummy that blocks/parries |

Build a data-driven "move runner" first; every weapon and spell is then content, not new code.

## Roadmap & milestones

Build the fighting game first with one build, then widen the roster slot by slot; each phase ends with a gate you can playtest.

| Phase | Scope | Gate to move on |
| --- | --- | --- |
| 0. Design | Finish this doc; write up all 40 roster entries and adapt the lore to a Roblox setting | Every slot item has a one-line playstyle and key list |
| 1. Core combat | Move runner, M1, block, parry, feint, posture, dash, landing roll, one placeholder weapon | 1v1 with a friend feels good with no abilities at all |
| 2. Vertical slice | 2 weapons, 1 secondary, 2 magic systems + bars + ultimates, 2 elements, 2 races, 1 map | 10 testers can pick builds and play a full free-for-all match |
| 3. Roster build-out | Remaining items, released one at a time; every item is free once released | Each new item passes the 64-matchup check |
| 4. Presentation | Loadout menu, tutorial, classic 2010–2014 Roblox UI, emotes and sounds | New player learns a build in one match |
| 5. Launch prep | Telemetry, balance pass, anti-exploit review, monetisation (cosmetics only) | Closed beta with stable win rates |

The biggest risk is scope: 40 items with lore and five variants each. Phase 2 exists so the formula is proven before that content is built.

## Open questions

- [x] Secondary weapon: offhand weapon or consumable for combo extension, covering weak spots, or utility
- [x] Secondary weapon key: T
- [x] Parry: tap F
- [x] G: comes from the magic system
- [x] Ctrl: race special only; no slide, landing roll on Space instead
- [x] Mode: free-for-all battlegrounds
- [x] Availability: every item is available once released; items ship one at a time
- [x] Tone: classic 2010–2014 Roblox aesthetic, not parody
- [x] Races: 8, one per region
- [x] Elements: Fire, Cold, Lightning, Wind, Shadow, Iron, Light, Earth, tied to region
- [x] Regions: the 8 names from Genesis 00; Lotus Fungus and Sirellium are regional magic systems
- [x] Mixing: race, element, magic and weapons can be combined freely across regions
- [x] Positive / Negative / Finance: lore categories only, no gameplay effect
- [ ] Which element and magic system belong to each region? (Waiting on region lore; code comes first, brainstorming after)
