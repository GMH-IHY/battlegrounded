# BattlegroundsGame

The Roblox place and everything that builds it. How the game should play: [../docs/DesignPlan.md](../docs/DesignPlan.md).

## Opening the game

Double-click **BattlegroundsGame.rbxlx**, or open it from Roblox Studio with File > Open from File, then press Play. Characters use the **R6** rig.

The place contains:

- **ReplicatedStorage > Movement**: the movement modules (`CharacterMotor`, `Dash`, `WallHop`, `AutoParkour`, `LandingRoll`, `Stamina`), the Moth race (`Lantern`, `MothParts`), sounds and all tuning numbers (`MovementConfig`, `AnimationConfig`, `SoundConfig`).
- **StarterPlayer > StarterCharacterScripts**: `MovementController` (input), `Animate`, `MovementSounds`.
- **StarterPlayer > StarterPlayerScripts**: the HUD, head look, shift lock (Tab), and Studio debug tools.
- **ServerScriptService**: race setup, lantern, sounds, head look, collision groups, dash punch (until combat exists), and `StudioAnimationMirror`, which lets unpublished animations play in Studio playtests.
- **Workspace**: a baseplate, a spawn, **MovementTestCourse** (labelled obstacles: jump box, tall wall, 80-stud fall tower, runway, vault box, slide gap, ledge), **WallHopAlley**, **DashTestDummy**, and **AnimRig_R6** (the dummy the Animation Editor poses).

## Debug keys (Studio playtests)

| Key | Tool |
| --- | --- |
| F2 | Collision boxes |
| F3 | Speedometer / debug overlay |
| F4 | Automatic movement self-test (F6 dash, F8 wall hop, F10 landing roll only) |
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
| `selene src` | Lints the Luau code (`selene.toml`, Roblox API in `roblox.yml`). |

`default.project.json` says which `src/` folder goes where. `tools/place.py` reads it, and it also works with Rojo if you ever switch to live-sync.

Animations live in `tools/animations/` as Python (`anims.py`, `parkour_anims.py`, `moth_anims.py`, listed in `catalog.py`). Every pose uses Constant easing. Studio playtests use the local copies; a live server needs each animation published and its ID pasted into `AnimationConfig`.
