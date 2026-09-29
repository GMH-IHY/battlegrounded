--!strict
-- HeadLookServer (Script)
-- Location: ServerScriptService > HeadLookServer
--
-- Each client tells the server where its head is turned (from its camera). The server checks
-- the numbers, clamps them to the allowed range and stores them on the character as the
-- "HeadLook" attribute, so every other client can turn that character's head too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("AnimationConfig")
local Config = require(ReplicatedStorage.Movement.AnimationConfig)

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotes = folder
end
assert(remotes, "HeadLookServer: Remotes folder missing")

local remote = Instance.new("UnreliableRemoteEvent")
remote.Name = "HeadLook"
remote.Parent = remotes

local MAX_YAW = math.rad(Config.HeadMaxYaw)
local MAX_PITCH = math.rad(Config.HeadMaxPitch)
local MAX_TWIST = math.rad(120) -- ShiftLock twists at most ~112 degrees
-- Generous allowance above the normal send rate; anything past it is dropped.
local MAX_PER_SECOND = Config.HeadLookSendRate * 2 + 5

local budgets: { [Player]: { windowStart: number, count: number } } = {}

local function withinBudget(player: Player): boolean
	local now = os.clock()
	local budget = budgets[player]
	if not budget or now - budget.windowStart >= 1 then
		budgets[player] = { windowStart = now, count = 1 }
		return true
	end
	budget.count += 1
	return budget.count <= MAX_PER_SECOND
end

local function validAngle(value: any): boolean
	-- A number, and not NaN (NaN is the only value not equal to itself).
	return typeof(value) == "number" and value == value
end

remote.OnServerEvent:Connect(function(player: Player, yaw: any, pitch: any, twist: any)
	if not withinBudget(player) then
		return
	end
	if not validAngle(yaw) or not validAngle(pitch) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local clampedYaw = math.clamp(yaw :: number, -MAX_YAW, MAX_YAW)
	local clampedPitch = math.clamp(pitch :: number, -MAX_PITCH, MAX_PITCH)
	if Config.HeadLookEnabled then
		character:SetAttribute("HeadLook", Vector2.new(clampedYaw, clampedPitch))
	end
	-- Shift-lock body twist toward A/D (visual only).
	if validAngle(twist) then
		character:SetAttribute("BodyTwist", math.clamp(twist :: number, -MAX_TWIST, MAX_TWIST))
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	budgets[player] = nil
end)
