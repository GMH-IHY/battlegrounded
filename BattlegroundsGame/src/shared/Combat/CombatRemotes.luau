--!strict
-- CombatRemotes (ModuleScript)
-- Location: ReplicatedStorage > Combat > CombatRemotes
--
-- The combat remotes, in ReplicatedStorage > Remotes > Combat. The server creates them
-- (CombatRemotes.Create, from CombatServer); clients wait for them (CombatRemotes.Get).
--
-- Client -> server
--   Move(moveId, seq)             start a move (seq numbers your moves, for Result)
--   Block(held)                   F pressed (true) / released (false)
--   Release(slot)                 a move key let go (R: ends the heal channel)
--   Tech()                        Shift while downed: tech roll
--   Stamina(amount)               race mobility spent stamina (the server owns the meter)
--   Debug(op, ...)                Studio only: test helpers (see CombatServer)
-- Server -> one client
--   Result(seq, result, hitstop, advantage?)
--                                 your move: "Reject", "Hit", "Counter", "Block", "Parried", "Armour",
--                                 with its frame advantage when it has one (hit stun or block)
--   Hit(info)                     you got hit / blocked / parried / knocked: react (CombatClient)
-- Server -> everyone
--   Fx(info)                      hits, blocks, parries, statuses for effects (CombatFx)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatRemotes = {}

export type Remotes = {
	Move: RemoteEvent,
	Block: RemoteEvent,
	Release: RemoteEvent,
	Tech: RemoteEvent,
	Stamina: RemoteEvent,
	Result: RemoteEvent,
	Hit: RemoteEvent,
	Fx: RemoteEvent,
	Debug: RemoteFunction,
}

local EVENTS = { "Move", "Block", "Release", "Tech", "Stamina", "Result", "Hit", "Fx" }

local cached: Remotes? = nil

local function collect(folder: Instance): Remotes
	local out: { [string]: Instance } = {}
	for _, name in EVENTS do
		out[name] = folder:WaitForChild(name)
	end
	out.Debug = folder:WaitForChild("Debug")
	return (out :: any) :: Remotes
end

-- Server: makes the remotes (once).
function CombatRemotes.Create(): Remotes
	assert(RunService:IsServer(), "CombatRemotes.Create is server-only")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		remotes = folder
	end
	assert(remotes, "no Remotes folder")
	local folder = remotes:FindFirstChild("Combat")
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Combat"
		for _, name in EVENTS do
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = created
		end
		local debugRemote = Instance.new("RemoteFunction")
		debugRemote.Name = "Debug"
		debugRemote.Parent = created
		created.Parent = remotes
		folder = created
	end
	assert(folder, "no Combat remotes")
	local made = collect(folder)
	cached = made
	return made
end

-- Client (or server after Create): waits for the remotes.
function CombatRemotes.Get(): Remotes
	if cached then
		return cached
	end
	local folder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Combat")
	local found = collect(folder)
	cached = found
	return found
end

return CombatRemotes
