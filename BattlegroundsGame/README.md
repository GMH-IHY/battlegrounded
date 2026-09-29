# BattlegroundsGame

## Opening the game

Double-click **BattlegroundsGame.rbxlx**, or open it from Roblox Studio with File > Open from File, then press Play.

The place contains:

- **ReplicatedStorage > Movement**: `MovementConfig` and `CharacterMotor`.
- **StarterPlayer > StarterCharacterScripts**: `MovementController`.
- **StarterPlayer > StarterPlayerScripts**: `DebugSpeedometer`, an on-screen speed counter in the bottom-left corner (F3 hides it). Green means you're at the planned speed, yellow means close, red means off.
- Characters use the **R6** rig (StarterPlayer avatar setting). The speedometer's "Rig" line confirms it.
- **Workspace**: a classic studded baseplate, a spawn, and **MovementTestCourse**, a set of labelled obstacles for testing movement:

| Obstacle | Use now | Use later |
| --- | --- | --- |
| Jump box (4 high, blue) | Coyote time and jump buffering | — |
| Tall wall (grey) | Jumping into it should kill your momentum | Wall run |
| Fall tower (80 high truss) | Climb it, jump off, check fall speed and terminal velocity | Landing roll |
| Runway (white strip) | Running and sharp turns | Sliding |
| Vault box (3 high, yellow) | — | Auto-vault |
| Slide gap (3 studs of clearance) | — | Auto-slide |
| Ledge (9 high, red) | Too high to jump onto | Ledge climb |

## Keep saving as .rbxlx

When you save in Studio, keep the **.rbxlx** format. It's a text file, so when I update scripts later I can patch them straight into your saved place without touching anything you've built. If you save as .rbxl (binary), I can't edit it.

## The other files

- `src/`: the script source files, the same code that's inside the place.
- `default.project.json` and `tools/gen_project.py`: how the place was generated with Rojo. You can ignore these unless you want to switch to Rojo live-sync later.
