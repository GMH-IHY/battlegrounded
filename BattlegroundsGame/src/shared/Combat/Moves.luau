--!strict
-- Moves (ModuleScript)
-- Location: ReplicatedStorage > Combat > Moves
--
-- Every move of every move set (MoveSets > *), by Id, plus the frame math both the server (hits)
-- and the attacker's client (animation, movement) use, so they agree on every phase.

local MoveTypes = require(script.Parent.MoveTypes)

export type Move = MoveTypes.Move
export type Phase = "Startup" | "Active" | "Recovery" | "Done"

local Moves = {}

local byId: { [string]: Move } = {}
local all: { Move } = {}

for _, module in script.Parent:WaitForChild("MoveSets"):GetChildren() do
	if module:IsA("ModuleScript") then
		local set = (require :: any)(module) :: { Move }
		for _, move in set do
			assert(byId[move.Id] == nil, "Moves: two moves share the id " .. move.Id)
			byId[move.Id] = move
			table.insert(all, move)
		end
	end
end
table.sort(all, function(a, b)
	return a.Id < b.Id
end)

Moves.FRAME = 1 / 60

function Moves.Get(id: string): Move?
	return byId[id]
end

function Moves.All(): { Move }
	return all
end

-- Frames from the start to the end of the move (whiff = the miss recovery).
function Moves.Total(move: Move, whiff: boolean?): number
	local recovery = if whiff and move.WhiffRecovery then move.WhiffRecovery else move.Recovery
	return move.Startup + move.Active + recovery
end

-- The phase at `frame` frames into the move (0 = the first frame).
function Moves.PhaseAt(move: Move, frame: number, whiff: boolean?): Phase
	if frame < move.Startup then
		return "Startup"
	elseif frame < move.Startup + move.Active then
		return "Active"
	elseif frame < Moves.Total(move, whiff) then
		return "Recovery"
	end
	return "Done"
end

-- The hitbox's centre for an attacker standing at `root`.
function Moves.HitboxCFrame(move: Move, root: CFrame): CFrame
	return root * CFrame.new(0, move.Hitbox.Up, -move.Hitbox.Forward)
end

return Moves
