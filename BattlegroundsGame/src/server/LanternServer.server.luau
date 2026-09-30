--!strict
-- LanternServer (Script)
-- Location: ServerScriptService > LanternServer
--
-- The Moth's lantern on the server: builds it for every Moth character (welded on the right hip; in
-- the right hand while charging a throw) and keeps it where the owner's client says while it's out
-- (the owner simulates it: LanternState + LanternSync). The model carries what other clients need
-- to draw it smoothly (LanternViewer): tag "MothLantern", attributes OwnerUserId, State, the throw's
-- start values (ThrowOrigin / ThrowVelocity / ThrowGravity / ThrowStart, server time / ThrowStop,
-- seconds until it stops) and the flash where it starts hanging (BurstAt / BurstId).
-- The lantern does no damage. CombatServer knocks it down when an attack touches it (KnockId, and
-- LockUntil = server time until it can be thrown again); throws before then are refused.
-- The lantern is only ever moved here while it's loose: re-pivoting it while it's welded to the
-- character would drag the whole character.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local IS_STUDIO = RunService:IsStudio()

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("MovementConfig")
local Config = require(ReplicatedStorage.Movement.MovementConfig)

-- In the right hand while charging (arm space; must match Lantern.luau) and on the right hip
-- (torso space) the rest of the time.
local HAND_OFFSET = CFrame.new(0, -1.72, 0)
local HIP_OFFSET = CFrame.new(1.18, -0.95, -0.05) * CFrame.Angles(0, 0, math.rad(-8))
local DARK = Color3.fromRGB(16, 38, 44)
local CORE_OFF = Color3.fromRGB(46, 110, 118)
local GLOW = Color3.fromRGB(120, 240, 255)
-- How far from its owner a reported lantern position may be (studs).
local MAX_SYNC_DISTANCE = Config.LanternThrowRangeMax + Config.LanternLightRadius + 80
local MIN_THROW_INTERVAL = 0.25

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotes = folder
end
assert(remotes, "Remotes folder missing")

local stateRemote = Instance.new("RemoteEvent")
stateRemote.Name = "LanternState"
stateRemote.Parent = remotes
local syncRemote = Instance.new("UnreliableRemoteEvent")
syncRemote.Name = "LanternSync"
syncRemote.Parent = remotes

local STATES: { [string]: boolean } = {
	Hip = true,
	Charging = true,
	Thrown = true,
	Suspended = true,
	Dropped = true,
	Returning = true,
}

type Info = {
	state: string,
	lastThrow: number,
}
local info: { [Player]: Info } = {}

local function reject(player: Player, reason: string)
	if IS_STUDIO then
		warn(string.format("[Lantern] rejected %s: %s", player.Name, reason))
	end
end

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

-- Simple JJS-style lantern: dark frame, glowing core, handle. Core is the PrimaryPart.
local function buildLantern(): Model
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local core = part("Core", Vector3.new(0.45, 0.55, 0.45), CORE_OFF, Enum.Material.SmoothPlastic)
	core.Parent = model
	model.PrimaryPart = core
	type Piece = { name: string, size: Vector3, offset: Vector3 }
	local pieces: { Piece } = {
		{ name = "Top", size = Vector3.new(0.7, 0.14, 0.7), offset = Vector3.new(0, 0.35, 0) },
		{ name = "Bottom", size = Vector3.new(0.7, 0.14, 0.7), offset = Vector3.new(0, -0.35, 0) },
		{ name = "Post1", size = Vector3.new(0.1, 0.56, 0.1), offset = Vector3.new(0.28, 0, 0.28) },
		{ name = "Post2", size = Vector3.new(0.1, 0.56, 0.1), offset = Vector3.new(-0.28, 0, 0.28) },
		{ name = "Post3", size = Vector3.new(0.1, 0.56, 0.1), offset = Vector3.new(0.28, 0, -0.28) },
		{ name = "Post4", size = Vector3.new(0.1, 0.56, 0.1), offset = Vector3.new(-0.28, 0, -0.28) },
		{ name = "HandleL", size = Vector3.new(0.08, 0.3, 0.08), offset = Vector3.new(-0.16, 0.55, 0) },
		{ name = "HandleR", size = Vector3.new(0.08, 0.3, 0.08), offset = Vector3.new(0.16, 0.55, 0) },
		{ name = "HandleTop", size = Vector3.new(0.4, 0.08, 0.08), offset = Vector3.new(0, 0.72, 0) },
	}
	for _, spec in pieces do
		local p = part(spec.name, spec.size, DARK, Enum.Material.SmoothPlastic)
		p.CFrame = core.CFrame * CFrame.new(spec.offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = core
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	-- The suspended lantern's light sphere (kept in Workspace so anchored parts are never inside the Character).
	local sphere = part("LightSphere", Vector3.one * Config.LanternLightRadius * 2, GLOW, Enum.Material.ForceField)
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.Transparency = 1
	sphere.Parent = Workspace
	model.Destroying:Connect(function()
		sphere:Destroy()
	end)
	local sphereRef = Instance.new("ObjectValue")
	sphereRef.Name = "LightSphereRef"
	sphereRef.Value = sphere
	sphereRef.Parent = model
	return model
end

local playerLanterns: { [Player]: Model } = {}

local function lanternOf(player: Player): (Model?, BasePart?)
	local model = playerLanterns[player]
	if model and model.PrimaryPart then
		return model, model.PrimaryPart
	end
	local character = player.Character
	local charLantern = if character then character:FindFirstChild("Lantern") else nil
	if not charLantern or not charLantern:IsA("Model") or not charLantern.PrimaryPart then
		return nil, nil
	end
	return charLantern, charLantern.PrimaryPart
end

-- "Hip" / "Hand": welded there; nil: loose (thrown, hanging, lying), placed by the owner's reports.
-- Never PivotTo while welded: the weld moves the lantern to the body, not the body to the lantern.
local function setMount(player: Player, mount: string?)
	local character = player.Character
	local model, core = lanternOf(player)
	if not character or not model or not core then
		return
	end
	local weld = core:FindFirstChild("HoldWeld")
	if not weld or not weld:IsA("Weld") then
		return
	end
	if mount then
		local part0 = character:FindFirstChild(if mount == "Hand" then "Right Arm" else "Torso")
		if part0 and part0:IsA("BasePart") then
			local targetC0 = if mount == "Hand" then HAND_OFFSET else HIP_OFFSET
			weld.Enabled = false
			core.Anchored = false
			core.AssemblyLinearVelocity = Vector3.zero
			core.AssemblyAngularVelocity = Vector3.zero
			model.Parent = character
			weld.Part0 = part0
			weld.C0 = targetC0
			weld.C1 = CFrame.identity
			weld.Enabled = true
		end
	else
		weld.Enabled = false
		model.Parent = Workspace
		core.Anchored = true
	end
	local lit = mount == nil
	core.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	core.Color = if lit then GLOW else CORE_OFF
end

local function place(player: Player, position: Vector3)
	local model, core = lanternOf(player)
	if not model or not core then
		return
	end
	core.CFrame = CFrame.new(position)
	local sphereRef = model:FindFirstChild("LightSphereRef") :: ObjectValue?
	local sphere = if sphereRef and sphereRef.Value and sphereRef.Value:IsA("BasePart") then sphereRef.Value else nil
	if sphere then
		sphere.CFrame = CFrame.new(position)
	end
end

local function giveLantern(player: Player, character: Model)
	if lanternOf(player) then
		return
	end
	-- (With deferred signals the character may not be in Workspace yet here; that's fine.)
	local torso = character:WaitForChild("Torso", 5)
	if not torso or not torso:IsA("BasePart") then
		warn("[Lantern] " .. player.Name .. "'s character has no Torso (R6 only)")
		return
	end
	local model = buildLantern()
	local core = model.PrimaryPart :: BasePart
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("State", "Hip")
	model:SetAttribute("BurstId", 0)
	CollectionService:AddTag(model, "MothLantern")
	model:PivotTo(torso.CFrame * HIP_OFFSET)
	local weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = torso
	weld.Part1 = core
	weld.C0 = HIP_OFFSET
	weld.Parent = core
	local sphereRef = model:FindFirstChild("LightSphereRef") :: ObjectValue?
	local sphere = if sphereRef and sphereRef.Value and sphereRef.Value:IsA("BasePart") then sphereRef.Value else nil
	if sphere then
		sphere.CFrame = core.CFrame
	end
	model.Parent = character
	playerLanterns[player] = model
	info[player] = { state = "Hip", lastThrow = -math.huge }
end

local function onCharacter(player: Player, character: Model)
	local function check()
		local isMoth = character:GetAttribute("Race") == "Moth"
		local existing = lanternOf(player)
		if isMoth and not existing then
			giveLantern(player, character)
		elseif not isMoth and existing then
			existing:Destroy()
			playerLanterns[player] = nil
		end
	end
	character:GetAttributeChangedSignal("Race"):Connect(check)
	check()
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		local model = playerLanterns[player]
		if model then
			model:Destroy()
			playerLanterns[player] = nil
		end
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	local model = playerLanterns[player]
	if model then
		model:Destroy()
		playerLanterns[player] = nil
	end
	info[player] = nil
end)

local function nearOwner(player: Player, position: Vector3, within: number?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= (within or MAX_SYNC_DISTANCE)
end

stateRemote.OnServerEvent:Connect(function(player: Player, state: unknown, position: unknown, throw: unknown)
	if typeof(state) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	local data = info[player]
	local model, core = lanternOf(player)
	if not data or not model or not core then
		return
	end
	if not STATES[state] then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	if state == "Thrown" then
		local now = os.clock()
		if now - data.lastThrow < MIN_THROW_INTERVAL then
			reject(player, "throwing too fast")
			return
		end
		local lockUntil = model:GetAttribute("LockUntil")
		if typeof(lockUntil) == "number" and lockUntil > serverNow + 0.25 then
			reject(player, "thrown while knocked down")
			return
		end
		-- The throw's start values, for other clients to replay the arc.
		if typeof(throw) ~= "table" then
			reject(player, "throw without its start values")
			return
		end
		local t = throw :: { [string]: unknown }
		local origin, velocity, gravity, start, stop = t.origin, t.velocity, t.gravity, t.start, t.stop
		if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" or typeof(gravity) ~= "number" or typeof(start) ~= "number"
			or typeof(stop) ~= "number" then
			reject(player, "bad throw values")
			return
		end
		local expectedGravity = Workspace.Gravity * Config.LanternThrowGravity
		if not nearOwner(player, origin, 12) or velocity.Magnitude > Config.LanternThrowSpeedMax + 5
			or math.abs(gravity - expectedGravity) > 1 then
			reject(player, "impossible throw")
			return
		end
		model:SetAttribute("ThrowOrigin", origin)
		model:SetAttribute("ThrowVelocity", velocity)
		model:SetAttribute("ThrowGravity", expectedGravity)
		model:SetAttribute("ThrowStart", math.clamp(start, serverNow - 1, serverNow))
		model:SetAttribute("ThrowStop", math.clamp(stop, 0, Config.LanternMaxFlightTime))
		data.lastThrow = now
	end
	local previous = data.state
	data.state = state
	model:SetAttribute("State", state)
	local mount = if state == "Hip" then "Hip" elseif state == "Charging" then "Hand" else nil
	setMount(player, mount)
	if not mount and nearOwner(player, position) then
		place(player, position)
	end
	if state == "Dropped" then
		core.Material = Enum.Material.SmoothPlastic
		core.Color = CORE_OFF
	end
	if state == "Suspended" and previous ~= "Suspended" and nearOwner(player, position) then
		-- It stopped and lit up: everyone else sees the flash (LanternViewer).
		model:SetAttribute("BurstAt", position)
		model:SetAttribute("BurstId", ((model:GetAttribute("BurstId") :: number?) or 0) + 1)
	end
	local sphereRef = model:FindFirstChild("LightSphereRef") :: ObjectValue?
	local sphere = if sphereRef and sphereRef.Value and sphereRef.Value:IsA("BasePart") then sphereRef.Value else nil
	if sphere then
		sphere.Transparency = if state == "Suspended" then 0.82 else 1
	end
end)

syncRemote.OnServerEvent:Connect(function(player: Player, position: unknown)
	local data = info[player]
	if typeof(position) ~= "Vector3" or not data or data.state == "Hip" or data.state == "Charging" then
		return
	end
	if nearOwner(player, position) then
		place(player, position)
	end
end)
