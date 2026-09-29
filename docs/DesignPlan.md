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

- Side or back dash → an attack: the dash ends on the click, keeping its speed, and the attack starts that frame. A front dash's M1 is the sword's running lunge. An attack late in a landing roll (from 0.25 s) or during a Moth flight cuts in too.
- Transition clips (walk / sprint start, sprint turn, light / running landing) and in-betweens at the start and end of every animation: choppy but smooth. Stopping from a run goes straight to idle (no skid). There's no heavy landing: a long fall never locks you.
- An extremely subtle stepped lean of the torso into turns and with speed changes (at most 3°; every character, visual only).
- Small retro effects: sweat balls only while burnt out, a low-poly dust cloud when landing hard and when a dash starts.
## Combat core

Combat runs on a 60 Hz frame model. The server owns every hit, resource and cooldown.

**How it's built (phase 2).** The server keeps a `Fighter` for every player and training dummy: a state machine (Idle, Blocking, Attacking, Stunned, Blockstun, Parried, Launched, Knockdown, Downed, TechRoll), the move it runs, stamina, cooldowns, the M1 chain, the combo it's taking and its build-up. Every frame it steps each move's frames and checks the active hitboxes itself (slightly padded for lag); `HitResolver` decides parry / block / armour / hit. The attacker's client plays the move at once (animation, step, lunge, hanging in the air), asks the server to run it, and pauses for the hit pause when the server says it landed; a refused move stops. The victim's client moves its own body (players own their physics) from the server's reaction message. Fighters pass through each other (collision group "Fighters").

**Lotus on top of it (phase 3).** The `Fighter` also holds the Lotus meter, the G form timer and Infested, and publishes them as attributes (Lotus, LotusStage, LotusForm, Infested) that the HUD, `FungusParts` (the growth on the arm and body) and `LotusFx` read. Moves carry the Lotus rules as data (stage, meter cost / gain, whiff penalty, projectile, grab, targeted, channel, status), so `HitResolver` and `Fighter` stay generic. Grabs and impales add one state, Held.

- **Knockdowns are animated, not physics ragdolls:** the body flies on a set path, tumbles in the air (stepped animation), lies on the floor, gets up. It reads better with constant easing and makes timing exact.
- **Hit pause:** both characters freeze for a few frames (4 on an M1, up to 7 on heavy hits) and the move's clock stops meanwhile, so the frame data stays true.
- **Soft lock:** an attack started with an opponent within 12 studs and 70° of where you face turns you toward them.
- **Parry:** each fresh press of F (while you can act) opens a 6-frame window; a window that parries nothing blocks new windows for 20 frames (holding F still blocks), so mashing doesn't parry. A parried attacker is stuck 20 frames.

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
- **Ragdoll (knockdown).** Most other moves knock down, which ends combos. Down slams and other hits on grounded players are allowed as often as you like (they don't reset the get-up clock); getting up is always faster than a full 3-hit M1 chain (0.5 s after landing, first 10 frames invincible, dash to tech roll).
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
- **Refill:** 15 SP/s after 0.9 s without spending (6/s in the air), so burnout lasts 5–6 s.
- The server owns the meter. Race moves spend it from the client (sent to the server, counted locally until the server catches up). While burnt out, sweat pops off your head and the SP bar blinks orange.

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
| Move data | One ModuleScript per weapon / magic / element / race (`ReplicatedStorage > Combat > MoveSets`): frames, damage, hitboxes, flags. `Loadout` picks the variant a key makes (chain position, air, running, Space held). |
| State machine | Server-side per character (`ServerScriptService > Combat > Fighter`) gates every action. |
| Hits | Server spatial queries with small lag compensation (`HitResolver`); clients play animations and effects immediately (`CombatClient`, `CombatFx`). |
| Animation | Generated in Python (`tools/animations`), constant easing, written into the place; previews as contact sheets and a browser viewer. |
| Testing | Studio only: F4 test panel (movement and combat suites), F3 frame data overlay, F5 hitbox view, training dummies (stand / block / block after a hit / parry / attack). |

## Roadmap

Each phase ends with a Studio playtest and a commit.

| Phase | Scope |
| --- | --- |
| 0. Cleanup & foundation | Remove dead code, merge the place and animation tools, set up linting, write these docs. **Done Sep 29.** |
| 1. Movement rework | Regenerate every movement animation with more in-between poses at the start and end, transition animations, torso lean, cancels into attacks, new Moth paper wings, sweat and dust effects. **Built Sep 29, waiting on a Studio playtest.** |
| 2. Combat core + Sword + Dagger | State machine, move runner, hits / block / parry / counter-hit, stamina and burnout, get-up, juggle limit, scaling, status build-up, warning flashes, hit pause and screen shake, training dummy, sword and dagger models and moves. **Built Sep 29, waiting on a Studio playtest.** |
| 3. Lotus Fungus | Meter and stages, every 2 / 3 / 4 variant, R and G, fungus arm and body growth, infection wrap and burst, the opponent's reactions. **Built Sep 29, waiting on a Studio playtest** (sounds are placeholders; the follow-up rules are a first draft). |
| 4. Wind + Moth | Q push / pull and Drafted; lantern rework and flight in your own light. |
| 5. HUD & balance tools | HUD tied to the loadout, stage meter, status bars over heads, cooldowns; combo damage checker. |

## Open questions

- [x] Movement self-test: replaced by the F4 test panel (Tests > Suites), which covers the old checks plus the new ones.
- [x] T: free, does nothing.
- [ ] Final damage scaling numbers (after playtests).
- [ ] Dash invincibility: the dash's first 4 frames are meant to be invincible, but the server doesn't know when a player dashes yet (movement is client-side). Until then a dash dodges by distance only.
- [x] Knockdowns: animated knockdowns instead of physics ragdolls (exact timing, reads better with constant easing).
- [ ] Which element and magic system belong to each region (lore only; no gameplay effect).
