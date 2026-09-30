# BattlegroundsGame

The Roblox place and everything that builds it. How the game should play: [../docs/DesignPlan.md](../docs/DesignPlan.md).

## Opening the game

Double-click **BattlegroundsGame.rbxlx**, or open it from Roblox Studio with File > Open from File, then press Play. Characters use the **R6** rig.

The place contains:

- **ReplicatedStorage > Movement**: the movement modules (`CharacterMotor`, `Dash`, `WallHop`, `AutoParkour`, `LandingRoll`, `Stamina`), the Moth race (`Lantern`, `MothParts`), `Controls` (the keys as named actions), sounds and all tuning numbers (`MovementConfig`, `AnimationConfig`, `SoundConfig`).
- **ReplicatedStorage > Combat**: the move data (`MoveSets > Sword, Dagger, Lotus, Wind`, `Moves`, `Loadout` (also each build item's HUD slots), `CombatConfig`), your own side of fights (`CombatClient`: predicted moves, block / parry, reactions), knockback physics (`CombatBody`), animations (`CombatAnimator`, `Reactions`), remotes, the weapon models (`WeaponModels`, generated `WeaponModelsData`) and the Lotus fungus growth (`FungusParts`, generated `FungusData`; `FxPieces` is the small effect-part helper).
- **StarterPlayer > StarterCharacterScripts**: `MovementController` (every key: movement and combat), `Animate` (locomotion loops + transition clips), `MovementSounds`.
- **StarterPlayer > StarterPlayerScripts**: the HUD (slots built from your build, `Loadout.Items`; your statuses and build-up; a combo counter coloured by the damage budget), `OverheadBars` (HP, build-up and statuses over everyone else's head), `BodyLean` (a very subtle stepped lean into turns), `MovementFx` (sweat in burnout, dust clouds), `CombatFx` (slashes, hit sparks, parry rings, warning flashes, hit pause, screen shake), `LotusFx` (strands, spikes, the beam, spores, fungal patches, wraps, bursts, heal specks, Infested blobs), head look, shift lock (Tab), the settings menu (`SettingsMenu`, the gear button) and the debug tools it switches (test panel, frame data, collision and hitbox views, animation gallery).
- **ServerScriptService**: `CombatServer` with `Combat > Fighter` (each fighter's state machine, stamina, cooldowns), `HitResolver`, `Projectiles` (spores and the ground strand; Wind turns them around) and `Dummies` (the training dummies); race setup, lantern, sounds, head look, collision groups, and `StudioAnimationMirror`, which plays the local (unpublished) animations in Studio playtests.
- **Workspace**: a baseplate, a spawn, **MovementTestCourse** (labelled obstacles: jump box, tall wall, 80-stud fall tower, runway, vault box, slide gap, ledge), **WallHopAlley** and **AnimRig_R6**. At runtime the server adds **TrainingDummies** at x = 80 (DummyStand, DummyBlock, DummyBlockAfterHit, DummyParry, DummyAttack; labels show their mode and the last combo) (the dummy the Animation Editor poses).

## Settings menu and debug tools

The gear button in the top-right corner opens the settings menu. No debug tool uses a function key (Studio and the Roblox player keep most of them); they're all switches under **Debug**:

| Item | Tool |
| --- | --- |
| Speedometer + frame data | Speed readout plus combat frame data: your move, its frame and phase, the last result and its frame advantage (on by default) |
| Collision boxes | Every character's collision boxes |
| Test panel (Studio) | Run every suite or one (Tests > Suites), results on screen and in Output |
| Hitbox view (Studio) | Attack hitboxes: yours in blue the moment you swing, the server's in orange (red when they touch someone), projectiles too |
| Animation gallery (Studio) | Every pose of an animation side by side; Next / Close buttons on screen |

Other scripts add their own items with `SettingsMenu.AddToggle` / `AddButton` (`StarterPlayerScripts > SettingsMenu`).

## Combat and Moth keys

| Key | Move |
| --- | --- |
| 2 / 3 / 4 | Stab / spore / grab; the variant follows your meter stage (HUD bar above HP) |
| R / G | Hold R to heal, tap R to rip it out; G at a full meter for the stage 3 form |
| Q | Wind push; with S held, pull |
| Ctrl (Moth) | Tap = wing burst; hold and release = throw the lantern (it hangs and lights the area); press with it out = recall |
| Space (Moth) | Hold in the air inside your own light to fly |

## Keep saving as .rbxlx

When you save in Studio, keep the **.rbxlx** format. It's a text file, so script and animation updates can be patched straight into your saved place without touching anything you've built. A binary .rbxl can't be edited that way.

## Tools

Run from this folder. They need Python 3 with `lxml`, `numpy`, `scipy` and `Pillow`.

| Command | What it does |
| --- | --- |
| `python tools/place.py sync` | Writes every script in `src/` into the place: changed scripts are updated, new ones added, deleted ones removed. Nothing else in the place is touched. |
| `python tools/place.py check` | Lists where the place and `src/` differ (exit code 1 if they do). |
| `python tools/place.py remove A/B/C` | Deletes an instance from the place by path. |
| `python tools/animations/build.py [--only Name,Name]` | Writes the animations into the place (ServerStorage > RBX_ANIMSAVES > AnimRig_R6), replacing ones with the same name. |
| `python tools/animations/preview.py out.png [Name ...]` | Contact sheet: every pose from three angles. |
| `python tools/animations/viewer.py out.html` | A browser page that plays every animation at real speed. |
| `python tools/models/weapons.py` | Rebuilds the sword, dagger and sheath (`src/shared/Combat/WeaponModelsData.luau`). |
| `python tools/combo.py [route]` | Combo damage checker: replays the example routes (or yours) with the server's scaling rules and checks them against the damage budget. |
| `python tools/models/fungus.py` | Rebuilds the Lotus fungus growth for all three stages (`src/shared/Combat/FungusData.luau`). |
| `python tools/models/moth_wings.py` | Rebuilds the Moth's paper wings (`MothPartsData.luau`) and the paper texture (`assets/textures/moth_wing_paper.png`). |
| `python -m pytest tests` | Offline checks: animations (timing, pops, eased starts and ends, feet on the floor, names matching the game) and the move tables in docs/MoveData.md matching the move sets. |
| `selene src` | Lints the Luau code (`selene.toml`, Roblox API in `roblox.yml`). |

`default.project.json` says which `src/` folder goes where. `tools/place.py` reads it, and it also works with Rojo if you ever switch to live-sync.

Animations live in `tools/animations/` as Python: `anims.py` (locomotion + transition clips), `parkour_anims.py` (dashes, parkour), `moth_anims.py`, `combat_anims.py` (sword, dagger, block, parry, hit reactions), `wind_anims.py` (the Q push and pull), `lotus_anims.py` (every Lotus move, held / consumed reactions), listed in `catalog.py`. Key poses are written by hand; `timing.py` generates the in-betweens. Every pose uses Constant easing. Animations are local for now (nothing is published): `build.py` writes them into the place and `StudioAnimationMirror` plays them in Studio playtests (`AnimationConfig.Names` lists them). Roblox only plays unpublished animations in Studio.

## Sounds (local)

Nothing is published: every sound is a Sound object in the place under **ReplicatedStorage > Sounds**. Import the audio folder into Studio once (keep the file names: `Sfx` finds each sound by its `SoundConfig` name or by its file name, e.g. `universeDash`, in any subfolder). At the start of every Studio playtest the Output lists the audio files that are still missing.

## Tests

- **In Studio (settings menu > Debug > Test panel, during Play):** the test panel runs the suites in `StarterPlayerScripts > Tests > Suites` (Animation, Basics, Dash, Attacks, Combat, Lotus, Wind, Landing, WallHop, Parkour, Flow, Truss, Moth, Performance, and the slow ParkourSweep). Tests press keys through `Controls`, the same code the keyboard uses, so they test what a player does. Adding a test: add `{ name = ..., run = function(t) ... end }` to a suite; `Tests > Harness` lists what `t` can do.
- **Offline:** `python -m pytest tests` checks every animation before Studio is opened.

## Moth wing texture

The wings are flat paper-coloured plates until the texture is uploaded. Upload `assets/textures/moth_wing_paper.png` to Roblox, paste its asset id into `WING_TEXTURE` in `tools/models/moth_wings.py`, run it, then `python tools/place.py sync`.
