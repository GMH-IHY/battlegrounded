# Battlegrounds Game — Design Plan

Sep 29, 2026 · @Isaac

This is the source of truth for how the game plays. Move numbers live in [MoveData.md](MoveData.md), the look in [art/ArtDirection.md](art/ArtDirection.md), and the world in [lore/](lore/).

## Vision & pillars

A Roblox battlegrounds game that parodies anime battlegrounds games (JJS, TSB and the rest) with original ideas: unusual abilities, free, flowing anime movement, and a fighting game underneath that rewards thinking. You build your own fighter from five picks and win through spacing, M1s, parries and stamina management, not by having the newest character.

1. **Movement comes first.** Moving should feel great before any attack exists: flowing, fast, anime. Combat then builds on movement (side dash into a clean M1, wall hop into an air attack) instead of stopping it.
2. **M1 neutral is the star.** M1s, blocks, parries and spacing decide fights. Abilities extend what good fundamentals earn.
3. **Stamina is the Drive gauge.** One meter (SF6's Drive gauge meets SF3's parry) that blocking, race mobility and greed drain, with a brutal burnout.
4. **Build is identity.** Weapon + secondary + magic system + element + race = one fighter. Each slot has one clear job.
5. **Magic decides how you win.** Every magic system is utility-first, with moves that change depending on what you did before. There is no awakening and no second moveset.
6. **Satire with sincere craft.** The game pokes fun at the genre with original ideas, not by copying other games' assets or names. It looks like classic 2010–2014 Roblox and Die of Death: low-poly parts, flat colours, constant-easing animation.
7. **Readable, then deep.** A new player understands a build in one match; the tech is discovered, not required.

## Controls

Every slot owns its keys, so a player always knows where a move comes from.

| Key | Action | Slot | Notes |
| --- | --- | --- | --- |
| WASD | Move | — | Double-tap W to run |
| Left click | M1 | Weapon | 3-hit chain; Space held / air / running variants |
| Right click | Secondary weapon | Secondary | Dagger: tap to stab, air slash in the air |
| Shift | Dash | — | Directional; no stamina cost, cooldown only |
| F | Block (hold) / Parry (tap) | — | Block is buffered during stun |
| 1 | Weapon ability | Weapon | Sword: ground and air versions |
| 2, 3, 4 | Magic abilities | Magic system | Change with the magic system's state |
| R | Magic utility | Magic system | Lotus: heal to grow / rip out to shrink |
| G | Ultimate | Magic system | Long cooldown |
| Q | Element special | Element | Catches runners or makes space, plus one small trick |
| Ctrl | Race special | Race | Moth: lantern and wings |
| Space | Jump / wall hop / landing roll | — | Moth: hold in the air inside your light to fly |
| T | Free | — | Kept free for later |
| E | Interact | — | Map objects |
| Tab | Shift lock | — | Temporary key |

Feint is removed. Right click belongs to the secondary weapon.

## Movement

Movement is momentum-based and runs on the client (the player owns their character's physics).

| Option | Input | Rule |
| --- | --- | --- |
| Run | Double-tap W | Enables running variants of attacks |
| Dash | Shift + direction | Cooldown only, no stamina |
| Wall hop / wall run | Space into and along a wall | Free |
| Auto parkour | Sprint into obstacles | Vault, ledge climb, slide; free |
| Landing roll | Space just before landing from a high fall | Free; keeps momentum |
| Tech roll | Dash on landing from a knockdown | Part of get-up |
| Race mobility | Ctrl | Costs a lot of stamina |

**What the movement rework adds (phase 1):**

- Side or back dash → M1: the dash ends on the click, keeping its speed, and the swing starts that frame. A front dash's M1 is the dash punch (the future running lunge). M1 late in a landing roll (from 0.25 s) or during a Moth flight cuts into a swing too.
- Transition clips (walk / sprint start, skid stop, sprint turn, light / running / heavy landing) and in-betweens at the start and end of every animation: choppy but smooth.
- **Heavy landing:** falling at least 16 studs without a landing roll = 0.25 s of barely moving, no jump, no dash (MovementConfig HeavyLand*). The roll is how you skip it.
- A stepped lean of the torso into turns and with speed changes (every character, visual only).
- Small retro effects: sweat balls when running, dust cubes when landing hard and when a dash starts.
- Until combat exists, M1 is a placeholder 3-hit sword swing with the real timings and no damage.

## Combat core

Combat runs on a 60 Hz frame model. The server owns every hit, resource and cooldown.

**M1s interrupt, they don't combo.** Each sword M1 stuns and interrupts, but its stun ends about 2 frames before the next M1 can hit.

| In that gap the defender... | Result |
| --- | --- |
| Holds F (block buffered during stun) | Blocks the next M1; costs stamina |
| Taps F on the next M1 | Parry; no stamina lost, a little gained |
| Presses an ability | It starts in the gap and gets counter-hit |
| Uses a move with armour | Gets through |

- **Counter-hits:** an M1 that hits during a move's startup stuns longer (+8 frames), enough for a guaranteed follow-up.
- **After a blocked third M1** the attacker is at a disadvantage, so it's the defender's turn.
- **Free combo route:** M1 → 1 → ability → M1. Anything more has to come from cooldowns being ready; nothing costs stamina.
- **The sword's 1 is the linker.** It never ragdolls and leaves a long stun, so any ability can follow. It is unsafe on block. Its 5 s cooldown (shared by the ground and air versions) is what limits combo length: one 1 per combo.
- **Ragdoll.** Most other moves ragdoll, which ends combos. Down slams and other hits on grounded players are allowed as often as you like; getting up is always faster than a full 3-hit M1 chain (about 0.5 s after landing, first frames invincible, dash to tech roll).
- **Unblockables** are always slower. Warning flashes, ULTRAKILL-style: **yellow** = can't be blocked, can be parried; **blue** = can't be parried, dash to dodge. Normal moves don't flash.
- **Armour** absorbs a set number of hits (for example, one armour point: a second hit interrupts).
- **Juggle limit:** one launch per combo. Any later launch becomes a normal knockdown.
- **Shrinking stun:** every hit in a combo shortens the target's stun by 2 frames.
- **Damage scaling:** from the 4th hit, ×0.85 per hit, minimum ×0.4; moves after a 1 do ×0.8. (Placeholder until playtests.)
- **Damage budget:** normal confirm 15–20, best stage 3 confirm ≤ 35, absolute maximum with an ultimate ≤ 45 (HP 100). Any route over budget gets fixed.

**Element status build-up.** Each fighter has a build-up bar for the opponent's element. Winning exchanges fills it (M1 hit, counter-hit, parry, 1, dagger, Q); magic moves don't. Full bar → the element's status, then a 6 s lockout. The bar drains when you stop landing M1s or Q, which makes M1s matter even more.

## Stamina (SP)

One meter, 100 SP. Posture is merged into it.

| Action | SP |
| --- | --- |
| Dash, wall hop, auto parkour | 0 |
| Race mobility (Moth wing burst, flight) | Considerable / drain per second |
| Blocking a hit | Drain grows with the hit |
| Parry | +10 |
| Abilities | 0 (cooldowns only) |

- **Overdraw:** a stamina move still comes out with too little SP, then you're in burnout.
- **Burnout:** nothing that costs stamina. You can still block and parry, but blocked hits deal chip damage to HP. You leave burnout only when the meter is full again; it refills 25% faster meanwhile.
- **Refill:** about 15 SP/s after a short pause, so burnout lasts 5–6 s (the current code refills 45/s; changes in phase 2).

## Loadout

| Slot | Keys | Job |
| --- | --- | --- |
| Weapon | M1, 1 | Neutral: the M1 chain, the linker, spacing |
| Secondary | Right click | A fast option every build can carry; covers slow builds |
| Magic system | 2, 3, 4, R, G | How you win: utility, setups, the big payoff |
| Element | Q + status | Catch runners or make space, plus one small trick; status from weapon wins |
| Race | Ctrl + passives | Movement or defence |

Players mix slots freely. Eight of each is the long-term target; the first build is below.

## First build

| Slot | Pick | Summary |
| --- | --- | --- |
| Weapon | **Sword** | One-handed, right hand. 3-hit M1 chain; Space held on hit 3 = launcher; air hit 3 = unblockable downward slash; running M1 = committal lunge that can go behind a block. 1 = meaty linker, air 1 = air linker. |
| Secondary | **Dagger** | Right click stab about 1 frame faster than an M1, links into 1, has a cooldown. In the air: a fast air slash that links into air 1. Sheathed on the hip, drawn with the left hand. |
| Magic | **Lotus Fungus** | Meter in three stages (40 / 40 / 20). 2 = stab, 3 = spore, 4 = grab, R = grow or shrink, G = full stage 3 form. Stage 1 links, stage 2 is decently strong, stage 3 is power that spends meter and hurts you if you miss. |
| Element | **Wind** | Q: forward or neutral = push, back = pull; redirects projectiles. Status: Drafted (next launch higher or next ragdoll longer). |
| Race | **Moth** | Ctrl: tap = wing burst; hold = throw the lantern (lights an area); hold Space inside your own light to fly; Ctrl again recalls the lantern. |

**Hands:** the right hand always holds the sword. The left hand is shared by the fungus, the dagger and the lantern throw; they never happen at the same time.

**Lotus Fungus in one paragraph.** An escalation system: you feed the fungus your own health to climb stages and spend it at the top for power. Taking damage and landing Lotus stabs raise the meter; R's heal channel raises it (and a hit during the channel is an automatic counter-hit on you), R's rip-out lowers it at an HP cost. At stage 3 you take 25% more damage, every stage 3 move spends meter, and missing one consumes you (HP loss that doesn't refill the meter). G needs a full meter and gives about 8 s of free stage 3 moves, then drops you to the middle of stage 1. Full numbers: [MoveData.md](MoveData.md).

## Balance framework

- **Slot lanes:** each slot affects only its own lane (race = movement / defence, element = status and Q, and so on) so builds can't stack the same strength three times.
- **Cooldowns + the one-1-per-combo rule + juggle limit + shrinking stun + scaling** keep combos expressive but short.
- **Status caps:** one status at a time per element, 6 s lockout after it triggers.
- **Telemetry (launch prep):** pick rate, win rate and damage per slot item; flag anything above 55% win rate or 25% pick rate.
- **Test matrix:** every weapon against every weapon with a baseline loadout, then the most-picked combos; every combo route checked against the damage budget.

## Technical architecture

| System | Approach |
| --- | --- |
| Project | Strict Luau in `BattlegroundsGame/src`, shared / server / client / character folders. `tools/place.py sync` writes src into the `.rbxlx`; `default.project.json` lists the mappings (Rojo-compatible). |
| Lint | selene with the Roblox standard library (`selene.toml`). |
| Movement | Client-side modules next to `CharacterMotor` (the player owns their physics). |
| Input | One controller maps keys to action names and sends one validated request per action. |
| Move data | One ModuleScript per weapon / magic / element / race: frames, damage, hitboxes, flags, variants with the conditions that pick them. |
| State machine | Server-side per character (idle, attacking, blocking, stunned, ragdoll, burnout) gates every action. |
| Hits | Server spatial queries with small lag compensation; clients play animations and effects immediately. |
| Animation | Generated in Python (`tools/animations`), constant easing, written into the place; previews as contact sheets and a browser viewer. |
| Testing | Debug tools gated to Studio: frame data overlay, hitbox view, training dummy (stand / block / parry), movement self-test. |

## Roadmap

Each phase ends with a Studio playtest and a commit.

| Phase | Scope |
| --- | --- |
| 0. Cleanup & foundation | Remove dead code, merge the place and animation tools, set up linting, write these docs. **Done Sep 29.** |
| 1. Movement rework | Regenerate every movement animation with more in-between poses at the start and end, transition animations, torso lean, cancels into attacks, new Moth paper wings, sweat and dust effects. **Built Sep 29, waiting on a Studio playtest.** |
| 2. Combat core + Sword + Dagger | State machine, move runner, hits / block / parry / counter-hit, stamina and burnout, get-up, juggle limit, scaling, status build-up, warning flashes, hit pause and screen shake, training dummy, sword and dagger models and moves. |
| 3. Lotus Fungus | Meter and stages, every 2 / 3 / 4 variant, R and G, fungus arm and body growth, infection wrap and burst, the opponent's reactions. |
| 4. Wind + Moth | Q push / pull and Drafted; lantern rework and flight in your own light. |
| 5. HUD & balance tools | HUD tied to the loadout, stage meter, status bars over heads, cooldowns; combo damage checker. |

## Open questions

- [x] Movement self-test: replaced by the F4 test panel (Tests > Suites), which covers the old checks plus the new ones.
- [x] T: free, does nothing.
- [ ] Final damage scaling numbers (after playtests).
- [ ] Which element and magic system belong to each region (lore only; no gameplay effect).
