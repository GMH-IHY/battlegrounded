--!strict
-- CombatFx (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > CombatFx
--
-- Every combat effect, drawn on each client (docs/art/ArtDirection.md, "Effects"). Like the
-- animations, everything changes in steps (FX_RATE per second), never smooth tweens.
--   slash        a thin flat arc of plates on a move's active frames, shaped by its Fx.Arc
--   warning      a short flash on an attacker winding up an unblockable: yellow = parry it,
--                blue = can't block or parry, get out of the way
--   hit          3-5 white plates in a star (red on a counter-hit, plus "COUNTER"), a damage number
--   block        blue-white plates and a flat guard plate in front of the blocker
--   parry        a white flash plate and a ring that grows in steps
--   status       the name over the target ("DRAFTED") and pale wind plates
--   hit pause    both characters' animations hold still for the hit's hitstop
--   shake        the camera shakes in steps when your own character hits or is hit
--   dagger       other characters draw the dagger for dagger moves (your own: CombatClient)
--   burnout      the burnout loop plays on burnt-out characters
-- Sounds come from SoundConfig through Sfx (played locally, nothing relayed).
-- Moves start from the "Move" attribute the server sets ("LocalMove" for your own character, which
-- CombatClient sets the moment you press, so your own slashes don't wait for the server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Moves = require(Combat:WaitForChild("Moves"))
local CombatRemotes = require(Combat:WaitForChild("CombatRemotes"))
local WeaponModels = require(Combat:WaitForChild("WeaponModels"))
local Sfx = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("Sfx"))

local player = Players.LocalPlayer
local FX_RATE = 20
local FRAME = 1 / 60
local MAX_DISTANCE = 200

local WHITE = Color3.new(1, 1, 1)
local SLASH_COLOR = Color3.fromRGB(235, 240, 255)
local COUNTER_COLOR = Color3.fromRGB(255, 70, 60)
local BLOCK_COLOR = Color3.fromRGB(150, 200, 255)
local YELLOW = Color3.fromRGB(255, 220, 40)
local BLUE = Color3.fromRGB(60, 140, 255)
local WIND_COLOR = Color3.fromRGB(215, 235, 240)

local folder = Instance.new("Folder")
folder.Name = "CombatFx"
folder.Parent = Workspace

-- PARTS -------------------------------------------------------------------------------------

type Piece = {
	part: Part,
	-- One entry per step: { cframe, size, transparency } (nil = keep).
	steps: { { cframe: CFrame?, size: Vector3?, transparency: number? } },
	index: number,
}

local pool: { Part } = {}
local pieces: { Piece } = {}
local rng = Random.new()

local function take(color: Color3, neon: boolean?): Part
	local part = table.remove(pool)
	if not part then
		local fresh = Instance.new("Part")
		fresh.Anchored = true
		fresh.CanCollide = false
		fresh.CanQuery = false
		fresh.CanTouch = false
		fresh.CastShadow = false
		fresh.TopSurface = Enum.SurfaceType.Smooth
		fresh.BottomSurface = Enum.SurfaceType.Smooth
		part = fresh
	end
	assert(part, "CombatFx: no part")
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.Parent = folder
	return part
end

-- A part that goes through `steps` (one per FX step), then disappears.
local function piece(color: Color3, steps: { { cframe: CFrame?, size: Vector3?, transparency: number? } }, neon: boolean?)
	local part = take(color, neon)
	local first = steps[1]
	part.CFrame = first.cframe or CFrame.identity
	part.Size = first.size or Vector3.one
	part.Transparency = first.transparency or 0
	table.insert(pieces, { part = part, steps = steps, index = 1 })
end

local function stepPieces()
	for i = #pieces, 1, -1 do
		local p = pieces[i]
		p.index += 1
		local step = p.steps[p.index]
		if not step then
			p.part.Parent = nil
			table.insert(pool, p.part)
			table.remove(pieces, i)
		else
			if step.cframe then
				p.part.CFrame = step.cframe
			end
			if step.size then
				p.part.Size = step.size
			end
			if step.transparency then
				p.part.Transparency = step.transparency
			end
		end
	end
end

local function near(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	return (camera.CFrame.Position - position).Magnitude <= MAX_DISTANCE
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- SLASHES -----------------------------------------------------------------------------------

-- Arc shapes in the character's space (+X right, +Y up, -Z forward): the plane (two unit axes),
-- the start and end angles (degrees), the radius and the centre.
type ArcShape = { u: Vector3, v: Vector3, from: number, to: number, radius: number, centre: Vector3 }
local ARCS: { [string]: ArcShape } = {
	Flat = { u = Vector3.xAxis, v = -Vector3.zAxis, from = -20, to = 200, radius = 3.8, centre = Vector3.new(0, 0.6, -0.6) },
	Backhand = { u = -Vector3.xAxis, v = -Vector3.zAxis, from = -20, to = 200, radius = 3.8, centre = Vector3.new(0, 0.4, -0.6) },
	Overhead = { u = Vector3.yAxis, v = -Vector3.zAxis, from = 10, to = 150, radius = 4, centre = Vector3.new(0.6, 0.4, -0.4) },
	Rising = { u = -Vector3.yAxis, v = -Vector3.zAxis, from = 10, to = 170, radius = 4, centre = Vector3.new(0.6, 0.6, -0.6) },
	Diagonal = { u = Vector3.new(1, 1, 0).Unit, v = -Vector3.zAxis, from = 0, to = 170, radius = 3.8, centre = Vector3.new(0, 0.4, -0.6) },
}

local function slash(root: BasePart, arc: string, heavy: boolean, hand: string)
	local base = root.CFrame
	if arc == "Thrust" or arc == "Stab" then
		local length = if arc == "Thrust" then 7 else 3.5
		local side = if hand == "Left" then -0.8 else 0.8
		local at = base * CFrame.new(side * 0.5, 0.3, -(1.5 + length / 2))
		piece(SLASH_COLOR, {
			{ cframe = at, size = Vector3.new(0.12, 0.5, length * 0.6), transparency = 0.2 },
			{ cframe = at, size = Vector3.new(0.12, 0.4, length), transparency = 0.35 },
			{ cframe = at, size = Vector3.new(0.1, 0.25, length), transparency = 0.6 },
		}, true)
		return
	end
	local shape = ARCS[arc] or ARCS.Flat
	local segments = if heavy then 7 else 5
	local width = if heavy then 0.7 else 0.45
	local radius = shape.radius + (if heavy then 0.5 else 0)
	local normal = shape.u:Cross(shape.v)
	for i = 1, segments do
		local a0 = math.rad(shape.from + (shape.to - shape.from) * (i - 1) / segments)
		local a1 = math.rad(shape.from + (shape.to - shape.from) * i / segments)
		local p0 = shape.centre + (shape.u * math.cos(a0) + shape.v * math.sin(a0)) * radius
		local p1 = shape.centre + (shape.u * math.cos(a1) + shape.v * math.sin(a1)) * radius
		local mid = (p0 + p1) / 2
		local along = (p1 - p0)
		local length = along.Magnitude
		-- A thin plate lying in the arc's plane, its long side along the arc.
		local local_ = CFrame.fromMatrix(mid, along.Unit, normal, along.Unit:Cross(normal))
		local at = base * local_
		-- The tip of the arc (the later segments) shows first and lasts longest: a trail.
		local share = i / segments
		local t0 = 0.15 + (1 - share) * 0.35
		piece(SLASH_COLOR, {
			{ cframe = at, size = Vector3.new(length + 0.05, 0.08, width), transparency = t0 },
			{ cframe = at, size = Vector3.new(length + 0.05, 0.08, width * 0.8), transparency = t0 + 0.2 },
			{ cframe = at, size = Vector3.new(length + 0.05, 0.06, width * 0.5), transparency = t0 + 0.45 },
		}, true)
	end
end

-- The attacker's move started: warning flash now, slash on its first active frame.
local function onMoveStarted(character: Model, value: unknown)
	if typeof(value) ~= "string" then
		if character ~= player.Character then
			WeaponModels.SetDaggerDrawn(character, false)
		end
		return
	end
	local id = string.match(value, "^([^#]+)")
	local move = if id then Moves.Get(id) else nil
	local root = rootOf(character)
	if not move or not root or not near(root.Position) then
		return
	end
	if character ~= player.Character then
		WeaponModels.SetDaggerDrawn(character, move.Weapon == "Dagger")
	end
	if move.Guard ~= "Normal" then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = if move.Guard == "Unblockable" then YELLOW else BLUE
		highlight.OutlineColor = highlight.FillColor
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency = 0.2
		highlight.OutlineTransparency = 0
		highlight.Parent = character
		task.spawn(function()
			for _, t in { 0.2, 0.45, 0.2, 0.5, 0.75 } do
				highlight.FillTransparency = t
				task.wait(1 / 15)
			end
			highlight:Destroy()
		end)
	end
	local heavy = move.Fx.Swing == "SwordSwingHeavy"
	task.delay(move.Startup * FRAME, function()
		local current = character:GetAttribute(if character == player.Character then "LocalMove" else "Move")
		local liveRoot = rootOf(character)
		if current == value and liveRoot then
			slash(liveRoot, move.Fx.Arc, heavy, move.Fx.Hand)
		end
	end)
end

-- HITS, BLOCKS, PARRIES ---------------------------------------------------------------------

local function star(position: Vector3, color: Color3, count: number, size: number)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local spin = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), angle)
		piece(color, {
			{ cframe = spin, size = Vector3.new(0.12, size * 0.6, 0.12), transparency = 0 },
			{ cframe = spin, size = Vector3.new(0.12, size, 0.12), transparency = 0.1 },
			{ cframe = spin, size = Vector3.new(0.08, size * 1.2, 0.08), transparency = 0.5 },
		}, true)
	end
end

local function ring(position: Vector3, facing: Vector3, color: Color3)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local base = CFrame.lookAlong(position, look)
	local count = 8
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local steps = {}
		for s, radius in { 0.8, 1.6, 2.4, 3 } do
			local at = base * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0)
			table.insert(steps, { cframe = at, size = Vector3.new(radius * 0.7, 0.14, 0.14), transparency = (s - 1) * 0.22 })
		end
		piece(color, steps, true)
	end
	piece(WHITE, {
		{ cframe = base, size = Vector3.new(2.6, 2.6, 0.1), transparency = 0.1 },
		{ cframe = base, size = Vector3.new(3.4, 3.4, 0.1), transparency = 0.5 },
	}, true)
end

local function label(model: Model, text: string, color: Color3, size: number)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, size + 6)
	gui.StudsOffset = Vector3.new(rng:NextNumber(-0.8, 0.8), 1.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.Arcade
	text_.TextSize = size
	text_.Text = text
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0
	text_.Parent = gui
	gui.Parent = head
	task.spawn(function()
		for step = 1, 6 do
			gui.StudsOffset += Vector3.new(0, 0.25, 0)
			if step >= 4 then
				text_.TextTransparency = (step - 3) * 0.3
				text_.TextStrokeTransparency = (step - 3) * 0.3
			end
			task.wait(0.1)
		end
		gui:Destroy()
	end)
end

-- Hit pause for characters whose animations this client doesn't run (everyone else's; your own
-- are paused by CombatClient).
local function freeze(model: Model?, seconds: number)
	if not model or model == player.Character or seconds <= 0 then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local held: { [AnimationTrack]: number } = {}
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Speed ~= 0 then
			held[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	task.delay(seconds, function()
		for track, speed in held do
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

-- CAMERA SHAKE ------------------------------------------------------------------------------

local shakeUntil = 0
local shakeAmount = 0
local shakeOffset = CFrame.identity
local nextShakeStep = 0

local function shake(amount: number, seconds: number)
	shakeAmount = math.max(shakeAmount, amount)
	shakeUntil = math.max(shakeUntil, os.clock() + seconds)
end

RunService:BindToRenderStep("CombatShake", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if now >= shakeUntil then
		shakeAmount = 0
		return
	end
	-- A new offset 30 times a second (stepped), shrinking as it ends.
	if now >= nextShakeStep then
		nextShakeStep = now + 1 / 30
		local a = shakeAmount * math.clamp((shakeUntil - now) / 0.2, 0.3, 1)
		shakeOffset = CFrame.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0)
			* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-a, a) * 3))
	end
	camera.CFrame *= shakeOffset
end)

-- SERVER EVENTS -----------------------------------------------------------------------------

local remotes = CombatRemotes.Get()

remotes.Fx.OnClientEvent:Connect(function(info: { [string]: any })
	local kind: string = if typeof(info.type) == "string" then info.type else ""
	local isStatus = kind == "Status"
	local attacker: Model? = if typeof(info.attacker) == "Instance" and info.attacker:IsA("Model") then info.attacker else nil
	local target: Model? = if typeof(info.target) == "Instance" and info.target:IsA("Model") then info.target else nil
	local position: Vector3 = if typeof(info.position) == "Vector3" then info.position else Vector3.zero
	local hitstop: number = if typeof(info.hitstop) == "number" then info.hitstop else 0
	local mine = player.Character ~= nil and (attacker == player.Character or target == player.Character)
	local move = if typeof(info.move) == "string" then Moves.Get(info.move) else nil
	if kind == "Hitbox" then
		return -- HitboxViewer draws these
	end
	if not isStatus and not near(position) then
		return
	end
	if kind == "Hit" then
		local counter = info.counter == true
		local heavy = hitstop >= 5 * FRAME
		star(position, if counter then COUNTER_COLOR else WHITE, if heavy then 5 else 4, if heavy then 2.2 else 1.6)
		freeze(attacker, hitstop)
		freeze(target, hitstop)
		if target then
			local damage = if typeof(info.damage) == "number" then info.damage else 0
			label(target, string.format("%g", damage), if counter then COUNTER_COLOR else WHITE, 22)
			if counter then
				label(target, "COUNTER", COUNTER_COLOR, 18)
			end
			Sfx.PlayRemote(target, if move then move.Fx.Hit else "SwordHit", 1, 1, position)
			if counter then
				Sfx.PlayRemote(target, "CounterHit", 1, 1, position)
			end
		end
		if mine then
			shake(if heavy then 0.35 else 0.18, if heavy then 0.22 else 0.12)
		end
	elseif kind == "Block" then
		star(position, BLOCK_COLOR, 3, 1.2)
		local root = rootOf(target)
		if root then
			local at = root.CFrame * CFrame.new(0, 0.3, -1.4)
			piece(BLOCK_COLOR, {
				{ cframe = at, size = Vector3.new(2.6, 3, 0.1), transparency = 0.3 },
				{ cframe = at, size = Vector3.new(2.8, 3.2, 0.1), transparency = 0.6 },
			}, true)
		end
		freeze(attacker, hitstop)
		freeze(target, hitstop)
		if target then
			Sfx.PlayRemote(target, "Block", 1, 1, position)
			local chip = if typeof(info.chip) == "number" then info.chip else 0
			if chip > 0 then
				label(target, string.format("%g", math.floor(chip * 10 + 0.5) / 10), BLOCK_COLOR, 16)
			end
		end
		if mine then
			shake(0.08, 0.08)
		end
	elseif kind == "Parry" then
		local root = rootOf(target)
		ring(position, if root then root.CFrame.LookVector else Vector3.zAxis, WHITE)
		if target then
			Sfx.PlayRemote(target, "Parry", 1, 1, position)
			label(target, "PARRY", WHITE, 20)
		end
		if mine then
			shake(0.22, 0.15)
		end
	elseif kind == "Armour" then
		star(position, Color3.fromRGB(255, 170, 60), 3, 1.4)
		freeze(attacker, hitstop)
		freeze(target, hitstop)
	elseif kind == "Status" and target then
		local status = if typeof(info.status) == "string" then info.status else ""
		label(target, string.upper(status), WIND_COLOR, 20)
		local root = rootOf(target)
		if root and status == "Drafted" then
			for i = 1, 4 do
				local angle = i * math.pi / 2
				local base = root.CFrame * CFrame.Angles(0, angle, 0)
				local steps = {}
				for s = 0, 3 do
					local at = base * CFrame.new(1.8, -1.5 + s * 0.9, 0) * CFrame.Angles(0, 0, math.rad(20))
					table.insert(steps, { cframe = at, size = Vector3.new(0.1, 1.4, 0.5), transparency = 0.3 + s * 0.15 })
				end
				piece(WIND_COLOR, steps)
			end
		end
	end
end)

-- CHARACTERS --------------------------------------------------------------------------------

local watched: { [Model]: boolean } = {}

local function watch(character: Model)
	if watched[character] then
		return
	end
	watched[character] = true
	character:GetAttributeChangedSignal("Move"):Connect(function()
		if character ~= player.Character then
			onMoveStarted(character, character:GetAttribute("Move"))
		end
	end)
	character:GetAttributeChangedSignal("LocalMove"):Connect(function()
		if character == player.Character then
			onMoveStarted(character, character:GetAttribute("LocalMove"))
		end
	end)
	local function burnout()
		local on = character:GetAttribute("Burnout") == true
		pcall(Sfx.LoopRemote, character, "Burnout", on, 1, 1)
		if not on and character:GetAttribute("Stamina") ~= nil then
			pcall(Sfx.PlayRemote, character, "BurnoutRecover", 1, 1)
		end
	end
	character:GetAttributeChangedSignal("Burnout"):Connect(burnout)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			watched[character] = nil
		end
	end)
end

local function watchPlayer(p: Player)
	if p.Character then
		watch(p.Character)
	end
	p.CharacterAdded:Connect(watch)
end

for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

task.spawn(function()
	local dummies = Workspace:WaitForChild("TrainingDummies", 30)
	if not dummies then
		return
	end
	for _, model in dummies:GetChildren() do
		if model:IsA("Model") then
			watch(model)
		end
	end
	dummies.ChildAdded:Connect(function(model)
		if model:IsA("Model") then
			watch(model)
		end
	end)
end)

-- STEPS -------------------------------------------------------------------------------------

local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator >= 1 / FX_RATE then
		accumulator %= 1 / FX_RATE
		stepPieces()
	end
end)
