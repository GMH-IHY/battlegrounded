--!strict
-- DashPunchServer (Script)
-- Location: ServerScriptService > DashPunchServer
--
-- Receives dash punches that connected on the attacker's screen, checks they're believable,
-- and (until the combat system exists) shows a hit report above the target instead of
-- dealing damage. When combat is built, replace `report` with the real hit: 4 blockable
-- damage, stun (or ragdoll for early hits), extra endlag for the attacker when blocked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("MovementConfig")
local Config = require(ReplicatedStorage.Movement.MovementConfig)

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotes = folder
end
assert(remotes, "Remotes folder missing")

local remote = Instance.new("RemoteEvent")
remote.Name = "DashPunch"
remote.Parent = remotes

-- Largest believable gap between the two root parts when the punch lands. The attacker is
-- moving at up to ~90 studs/s during a dash, and the server sees them a few frames late, so
-- this is the hitbox reach plus a whole dash of slack (tested: 17.9 studs on a normal hit).
local MAX_RANGE = 12 + Config.FrontDashDistance
-- A player can't punch more often than this (the dash cooldown, with some slack for lag).
local MIN_INTERVAL = Config.DashCooldown * 0.7

local lastPunch: { [Player]: number } = {}

local function report(target: Model, attacker: Player, ragdoll: boolean)
	local head = target:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("DashPunchReport")
	if old then
		old:Destroy()
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DashPunchReport"
	billboard.Size = UDim2.fromOffset(220, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.ArialBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextColor3 = if ragdoll then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 230, 90)
	label.Text = string.format("%d dmg - %s", Config.DashPunchDamage, if ragdoll then "RAGDOLL" else "STUN")
	label.Parent = billboard
	billboard.Parent = head
	task.delay(1.5, function()
		billboard:Destroy()
	end)
	target:SetAttribute("LastDashPunch", if ragdoll then "ragdoll" else "stun")
	print(string.format("[DashPunch] %s hit %s: %s", attacker.Name, target.Name, if ragdoll then "ragdoll" else "stun"))
end

-- In Studio, say why a punch was thrown out (helps when testing).
local function reject(player: Player, reason: string)
	if IS_STUDIO then
		warn(string.format("[DashPunch] rejected %s: %s", player.Name, reason))
	end
end

remote.OnServerEvent:Connect(function(player: Player, target: unknown, ragdoll: unknown)
	if typeof(target) ~= "Instance" or not target:IsA("Model") or typeof(ragdoll) ~= "boolean" then
		reject(player, "bad arguments")
		return
	end
	local character = player.Character
	if not character or target == character or not target:IsDescendantOf(workspace) then
		reject(player, "bad target")
		return
	end
	local now = os.clock()
	if now - (lastPunch[player] or -math.huge) < MIN_INTERVAL then
		reject(player, "too soon after the last punch")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		reject(player, "attacker not alive")
		return
	end
	if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot or not targetRoot:IsA("BasePart") then
		reject(player, "target not alive")
		return
	end
	local gap = (root.Position - targetRoot.Position).Magnitude
	if gap > MAX_RANGE then
		reject(player, string.format("out of range (%.1f studs)", gap))
		return
	end

	lastPunch[player] = now
	report(target, player, ragdoll)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastPunch[player] = nil
end)
