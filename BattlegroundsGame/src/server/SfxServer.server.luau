--!strict
-- SfxServer (Script)
-- Location: ServerScriptService > SfxServer
--
-- Passes movement sounds on: each player's client plays its own movement sounds right away and
-- reports them here (Sfx module); this sends them to every OTHER player so they hear them on that
-- character. Only names in SoundConfig, sane numbers, positions near the character, and a rate
-- limit per player (a bad client can't spam everyone's speakers).
-- Studio: lists the audio files that have no Sound in ReplicatedStorage > Sounds yet (sounds are
-- local for now: import the audio folder into Studio once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("SoundConfig")
local SoundConfig = require(ReplicatedStorage.Movement.SoundConfig)
local Sfx = require(ReplicatedStorage.Movement.Sfx)

if game:GetService("RunService"):IsStudio() then
	task.defer(function()
		local missing = Sfx.Missing()
		if #missing > 0 then
			warn(string.format("[Sfx] %d audio file(s) have no Sound in ReplicatedStorage > Sounds (import them in Studio): %s",
				#missing, table.concat(missing, ", ")))
		end
	end)
end

local MAX_PER_SECOND = 30 -- one-shots + loop changes per player
local MAX_POINT_DISTANCE = 160 -- a one-shot "at" position may be this far from the character
local TARGETS: { [string]: boolean } = { Lantern = true }

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotes = folder
end
assert(remotes, "Remotes folder missing")

local oneShot = Instance.new("UnreliableRemoteEvent")
oneShot.Name = "MovementSfx"
oneShot.Parent = remotes
local loop = Instance.new("RemoteEvent")
loop.Name = "MovementSfxLoop"
loop.Parent = remotes

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: Bucket } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = MAX_PER_SECOND, last = now }
		buckets[player] = b
	end
	b.tokens = math.min(MAX_PER_SECOND, b.tokens + (now - b.last) * MAX_PER_SECOND)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function finite(n: unknown, lo: number, hi: number): number?
	if typeof(n) ~= "number" or n ~= n then
		return nil
	end
	return math.clamp(n :: number, lo, hi)
end

local function validName(name: unknown): boolean
	return typeof(name) == "string" and SoundConfig[name :: string] ~= nil
end

local function othersOf(player: Player): { Player }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(list, other)
		end
	end
	return list
end

oneShot.OnServerEvent:Connect(function(player: Player, name: unknown, speed: unknown, volume: unknown, at: unknown)
	local character = player.Character
	if not character or not validName(name) or not allow(player) then
		return
	end
	local s = finite(speed, 0.25, 4)
	local v = finite(volume, 0, 2)
	if not s or not v then
		return
	end
	local point: Vector3? = nil
	if at ~= nil then
		if typeof(at) ~= "Vector3" then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or (root.Position - (at :: Vector3)).Magnitude > MAX_POINT_DISTANCE then
			return
		end
		point = at :: Vector3
	end
	for _, other in othersOf(player) do
		oneShot:FireClient(other, character, name, s, v, point)
	end
end)

loop.OnServerEvent:Connect(function(player: Player, name: unknown, on: unknown, speed: unknown, volume: unknown, target: unknown)
	local character = player.Character
	if not character or not validName(name) or typeof(on) ~= "boolean" or not allow(player) then
		return
	end
	local s = finite(speed, 0.25, 4)
	local v = finite(volume, 0, 2)
	if not s or not v then
		return
	end
	local t: string? = nil
	if target ~= nil then
		if typeof(target) ~= "string" or not TARGETS[target :: string] then
			return
		end
		t = target :: string
	end
	for _, other in othersOf(player) do
		loop:FireClient(other, character, name, on, s, v, t)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	buckets[player] = nil
end)
