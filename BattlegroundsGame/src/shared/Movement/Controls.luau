--!strict
-- Controls (ModuleScript)
-- Location: ReplicatedStorage > Movement > Controls
--
-- The movement keys as named actions, so the keyboard and the tests go through the same code.
-- MovementController registers the actions for its character; the keyboard handlers call them,
-- and the in-Studio tests (StarterPlayerScripts > Tests) call them the same way:
--   Controls.Get(character).press.Dash()
-- Actions: Jump (Space), Dash (Shift), Race (Left Ctrl), Forward (W), M1 (left click),
-- M2 (right click: the secondary weapon), One (1: the weapon ability), Block (F: hold to block,
-- a fresh press is a parry try), and the magic keys Two, Three, Four (2 / 3 / 4), R (hold = heal,
-- tap = rip out) and G, and Wind's Q. A press without a release is fine for one-shot actions.
--
-- The Humanoid's own jump (Humanoid.Jump while Space is held) comes from Roblox's control script,
-- not from here: tests that hold Jump set Humanoid.Jump themselves.

export type ActionName =
	"Jump"
	| "Dash"
	| "Race"
	| "Forward"
	| "M1"
	| "M2"
	| "One"
	| "Block"
	| "Two"
	| "Three"
	| "Four"
	| "R"
	| "G"
	| "Q"
export type ActionSet = {
	Jump: () -> (),
	Dash: () -> (),
	Race: () -> (),
	Forward: () -> (),
	M1: () -> (),
	M2: () -> (),
	One: () -> (),
	Block: () -> (),
	Two: () -> (),
	Three: () -> (),
	Four: () -> (),
	R: () -> (),
	G: () -> (),
	Q: () -> (),
}
export type Actions = { press: ActionSet, release: ActionSet }

local Controls = {}

local registry: { [Model]: Actions } = {}

function Controls.Register(character: Model, actions: Actions)
	registry[character] = actions
end

function Controls.Unregister(character: Model)
	registry[character] = nil
end

function Controls.Get(character: Model): Actions?
	return registry[character]
end

return Controls
