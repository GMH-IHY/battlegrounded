# BattlegroundsGame

The Roblox place and everything that builds it. How the game should play: [../docs/DesignPlan.md](../docs/DesignPlan.md).

## Opening the game

Double-click **BattlegroundsGame.rbxlx**, or open it from Roblox Studio with File > Open from File, then press Play. Characters use the **R6** rig.

The place contains:

- **ReplicatedStorage > Movement**: the movement modules (`CharacterMotor`, `Dash`, `WallHop`, `AutoParkour`, `LandingRoll`, `Stamina`), the Moth race (`Lantern`, `MothParts`), `Controls` (the keys as named actions), sounds and all tuning numbers (`MovementConfig`, `AnimationConfig`, `SoundConfig`).
- **ReplicatedStorage > Combat**: `M1Preview`, a placeholder sword M1 chain (animations and timings, no damage) until the combat system exists.
- **StarterPlayer > StarterCharacterScripts**: `MovementController` (input), `Animate` (locomotion loops + transition clips), `MovementSounds`.
- **StarterPlayer > StarterPlayerScripts**: the HUD, `BodyLean` (a very subtle stepped lean into turns), `MovementFx` (sweat in burnout, dust clouds), head look, shift lock (Tab), and Studio tools (the test panel and debug views).
- **ServerScriptService**: race setup, lantern, sounds, head look, collision groups, dash punch (until combat exists), and `StudioAnimationMirror`, which lets unpublished animations play in Studio playtests.
- **Workspace**: a baseplate, a spawn, **MovementTestCourse** (labelled obstacles: jump box, tall wall, 80-stud fall tower, runway, vault box, slide gap, ledge), **WallHopAlley**, **DashTestDummy**, and **AnimRig_R6** (the dummy the Animation Editor poses).

## Debug keys (Studio playtests)

| Key | Tool |
| --- | --- |
| F2 | Collision boxes |
| F3 | Speedometer / debug overlay |
| F4 | Test panel: run every suite or one (Tests > Suites), results on screen and in Output |
| P | Animation gallery (every pose of an animation side by side) |

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
| `python tools/models/moth_wings.py` | Rebuilds the Moth's paper wings (`MothPartsData.luau`) and the paper texture (`assets/textures/moth_wing_paper.png`). |
| `python -m pytest tests` | Offline animation checks: timing, pops, eased starts and ends, feet on the floor, names matching the game. |
| `selene src` | Lints the Luau code (`selene.toml`, Roblox API in `roblox.yml`). |

`default.project.json` says which `src/` folder goes where. `tools/place.py` reads it, and it also works with Rojo if you ever switch to live-sync.

Animations live in `tools/animations/` as Python: `anims.py` (locomotion + transition clips), `parkour_anims.py` (dashes, parkour), `moth_anims.py`, `combat_anims.py` (M1 swings), listed in `catalog.py`. Key poses are written by hand; `timing.py` generates the in-betweens. Every pose uses Constant easing. Studio playtests use the local copies; a live server needs each animation published and its ID pasted into `AnimationConfig`.

## Tests

- **In Studio (F4 during Play):** the test panel runs the suites in `StarterPlayerScripts > Tests > Suites` (Animation, Basics, Dash, Attacks, Landing, WallHop, Parkour, Flow, Truss, Moth, Performance, and the slow ParkourSweep). Tests press keys through `Controls`, the same code the keyboard uses, so they test what a player does. Adding a test: add `{ name = ..., run = function(t) ... end }` to a suite; `Tests > Harness` lists what `t` can do.
- **Offline:** `python -m pytest tests` checks every animation before Studio is opened.

## Moth wing texture

The wings are flat paper-coloured plates until the texture is uploaded. Upload `assets/textures/moth_wing_paper.png` to Roblox, paste its asset id into `WING_TEXTURE` in `tools/models/moth_wings.py`, run it, then `python tools/place.py sync`.
