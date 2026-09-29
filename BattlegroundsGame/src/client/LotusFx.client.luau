--!strict
-- LotusFx (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > LotusFx
--
-- The Lotus Fungus effects, drawn on each client in the sculk palette (docs/art/ArtDirection.md),
-- stepped like everything else (FxPieces), never tweened:
--   stab 1       a dark strand shooting 9 studs out of the fungus hand
--   stab 3       a pale bone spike thrust out of the forearm
--   impale       a fungal patch spreading under the target during the wind-up ("Patch"), then bone
--                spikes erupting out of it
--   spores       low-poly spore balls flying (from the server's "Projectile" messages); the ground
--                strand is a trail of spikes racing along the floor; both burst where they end
--   beam         a dark shaft with a flickering cyan core for its 30 active frames
--   grab         growth swallowing the hand as it reaches; on a catch, tendrils to the victim
--   heal / rip   cyan specks rising / a chunk of growth torn off in debris; +HP / -HP labels
--   form         dark shells swelling around the body in steps, bursting when it ends
--   consumed     the fungus biting back: debris and a label
--   Infested     blobs growing over the victim's limbs in steps and pulsing while it lasts; the wrap
--                (their block hit by a Lotus move) covers them, then bursts
-- Moves start from the "Move" attribute (the server's) or "LocalMove" (your own, at once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Moves = require(Combat:WaitForChild("Moves"))
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local CombatRemotes = require(Combat:WaitForChild("CombatRemotes"))
local FxPieces = require(Combat:WaitForChild("FxPieces"))
local Sfx = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("Sfx"))

local player = Players.LocalPlayer
local FRAME = 1 / 60
local STEP = 1 / FxPieces.Rate
local MAX_DISTANCE = 220

local BASE = Color3.fromRGB(16, 20, 24)
local DARK_TEAL = Color3.fromRGB(15, 45, 54)
local GREEN = Color3.fromRGB(27, 58, 42)
local BLUE = Color3.fromRGB(22, 48, 90)
local CYAN = Color3.fromRGB(16, 152, 168)
local BONE = Color3.fromRGB(200, 194, 168)
local HEAL_TEXT = Color3.fromRGB(120, 230, 200)

local rng = Random.new()
local piece = FxPieces.Piece

local function near(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	return (camera.CFrame.Position - position).Magnitude <= MAX_DISTANCE
end

local function part(model: Model?, name: string): BasePart?
	local p = model and model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

-- The fungus hand (the bottom of the left arm), facing where the arm points.
local function handCFrame(model: Model): CFrame?
	local arm = part(model, "Left Arm")
	return if arm then arm.CFrame * CFrame.new(0, -1, 0) else nil
end

local function steps(count: number, fn: (i: number) -> FxPieces.Step): { FxPieces.Step }
	local out = {}
	for i = 1, count do
		table.insert(out, fn(i))
	end
	return out
end

local function label(model: Model, text: string, color: Color3)
	local head = part(model, "Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 26)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arcade
	t.TextSize = 20
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.Parent = gui
	gui.Parent = head
	task.spawn(function()
		for i = 1, 6 do
			gui.StudsOffset += Vector3.new(0, 0.25, 0)
			if i >= 4 then
				t.TextTransparency = (i - 3) * 0.3
				t.TextStrokeTransparency = (i - 3) * 0.3
			end
			task.wait(0.1)
		end
		gui:Destroy()
	end)
end

-- A burst of palette debris (sphere shell + cubes) at `position`.
local function burst(position: Vector3, size: number)
	piece(BASE, {
		{ cframe = CFrame.new(position), size = Vector3.one * size, transparency = 0.2 },
		{ cframe = CFrame.new(position), size = Vector3.one * size * 1.6, transparency = 0.5 },
		{ cframe = CFrame.new(position), size = Vector3.one * size * 2.1, transparency = 0.8 },
	}, false, Enum.PartType.Ball)
	for i = 1, 6 do
		local direction = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1), rng:NextNumber(-1, 1)).Unit
		local color = ({ BASE, GREEN, BLUE, DARK_TEAL, CYAN, BASE })[i]
		local cube = rng:NextNumber(0.2, 0.4)
		piece(color, steps(5, function(k)
			local at = position + direction * size * 0.4 * k - Vector3.new(0, 0.12 * k * k, 0)
			return { cframe = CFrame.new(at) * CFrame.Angles(k, k * 0.7, 0), size = Vector3.one * cube * (1 - k * 0.15), transparency = 0 }
		end), color == CYAN)
	end
end

-- MOVES ---------------------------------------------------------------------------------------

local function strand(model: Model, length: number, width: number, color: Color3, frames: number)
	local hand = handCFrame(model)
	local root = part(model, "HumanoidRootPart")
	if not hand or not root then
		return
	end
	local look = root.CFrame.LookVector
	local count = math.max(math.ceil(frames * FRAME / STEP), 3)
	piece(color, steps(count, function(i)
		local grow = math.min(i / 2, 1)
		local l = length * grow
		local at = CFrame.lookAlong(hand.Position + look * (l / 2), look)
		return { cframe = at, size = Vector3.new(width, width, l), transparency = if i == count then 0.6 else 0 }
	end))
	-- A glowing tip.
	piece(CYAN, steps(count, function(i)
		local grow = math.min(i / 2, 1)
		return { cframe = CFrame.new(hand.Position + look * length * grow), size = Vector3.one * (width * 1.3), transparency = 0 }
	end), true)
end

local function beam(model: Model, frames: number)
	local root = part(model, "HumanoidRootPart")
	if not root then
		return
	end
	local base = root.CFrame * CFrame.new(-0.6, 0.4, -31)
	local count = math.ceil(frames * FRAME / STEP)
	piece(BASE, steps(count, function(i)
		local w = if i % 2 == 0 then 3.6 else 4
		return { cframe = base, size = Vector3.new(w, w, 60), transparency = 0.35 }
	end))
	piece(CYAN, steps(count, function(i)
		local w = if i % 2 == 0 then 0.8 else 1.3
		return { cframe = base, size = Vector3.new(w, w, 60.2), transparency = 0.1 }
	end), true)
end

local function handCover(model: Model, frames: number)
	local hand = handCFrame(model)
	if not hand then
		return
	end
	local count = math.max(math.ceil(frames * FRAME / STEP), 2)
	piece(BASE, steps(count, function(i)
		local s = if i == 1 then 0.9 else 1.3
		return { cframe = hand, size = Vector3.one * s, transparency = 0 }
	end), false, Enum.PartType.Ball)
end

local function onMove(character: Model, value: unknown)
	if typeof(value) ~= "string" then
		return
	end
	local id = string.match(value, "^([^#]+)")
	local move = if id then Moves.Get(id) else nil
	local root = part(character, "HumanoidRootPart")
	if not move or move.Magic ~= "Lotus" or not root or not near(root.Position) then
		return
	end
	local arc = move.Fx.Arc
	local attribute = if character == player.Character then "LocalMove" else "Move"
	local function atActive(fn: () -> ())
		task.delay(move.Startup * FRAME, function()
			if character:GetAttribute(attribute) == value then
				fn()
			end
		end)
	end
	if arc == "Strand" then
		atActive(function()
			strand(character, 9, 0.45, BASE, move.Active + 6)
		end)
	elseif arc == "Spike" then
		atActive(function()
			strand(character, 10, 0.7, BONE, move.Active + 8)
		end)
	elseif arc == "Beam" then
		-- The charge: cyan specks drawn in toward the hand.
		local hand = handCFrame(character)
		if hand then
			for _ = 1, 5 do
				local from = hand.Position + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1, 3), rng:NextNumber(-3, 3))
				piece(CYAN, steps(6, function(k)
					return { cframe = CFrame.new(from:Lerp(hand.Position, k / 6)), size = Vector3.one * 0.2, transparency = 0 }
				end), true)
			end
		end
		atActive(function()
			beam(character, move.Active)
		end)
	elseif arc == "Grab" then
		handCover(character, move.Startup + move.Active)
	elseif move.Id == "Lotus.Heal" then
		local count = math.ceil(move.Active * FRAME / STEP)
		local arm = part(character, "Left Arm")
		if arm then
			for i = 1, count, 2 do
				task.delay(i * STEP, function()
					if character:GetAttribute(attribute) ~= value then
						return
					end
					local from = arm.Position + Vector3.new(rng:NextNumber(-0.8, 0.8), -0.5, rng:NextNumber(-0.8, 0.8))
					piece(CYAN, steps(5, function(k)
						return { cframe = CFrame.new(from + Vector3.new(0, 0.4 * k, 0)), size = Vector3.one * 0.18, transparency = (k - 1) * 0.18 }
					end), true)
				end)
			end
		end
	end
end

-- SERVER EVENTS -------------------------------------------------------------------------------

local flying: { [number]: { FxPieces.Handle } } = {}

local function projectile(info: { [string]: any })
	local id = info.id
	local position: Vector3 = info.position
	local direction: Vector3 = info.direction
	local speed: number = info.speed
	local range: number = info.range
	if typeof(id) ~= "number" or typeof(position) ~= "Vector3" or typeof(direction) ~= "Vector3" or not near(position) then
		return
	end
	local count = math.max(math.ceil(range / speed / STEP), 1)
	local handles = {}
	if info.ground == true then
		-- The ground strand: spikes breaking out of the floor along its path, each lasting a moment.
		for i = 1, count do
			task.delay(i * STEP, function()
				if not flying[id] then
					return
				end
				local at = position + direction * speed * i * STEP
				for s = 1, 2 do
					local side = direction:Cross(Vector3.yAxis).Unit * (if s == 1 then 0.8 else -0.8)
					local tilt = CFrame.lookAlong(at + side, direction) * CFrame.Angles(math.rad(-60), 0, math.rad(if s == 1 then -20 else 20))
					piece(if s == 1 then BONE else BASE, {
						{ cframe = tilt * CFrame.new(0, 0.5, 0), size = Vector3.new(0.3, 1, 0.3), transparency = 0 },
						{ cframe = tilt * CFrame.new(0, 1.2, 0), size = Vector3.new(0.35, 2.4, 0.35), transparency = 0 },
						{ cframe = tilt * CFrame.new(0, 0.8, 0), size = Vector3.new(0.3, 1.6, 0.3), transparency = 0.4 },
					})
				end
			end)
		end
		flying[id] = handles
		return
	end
	-- A spore: a dark ball with a cyan core, stepping along its line.
	local ball = piece(DARK_TEAL, steps(count, function(i)
		return { cframe = CFrame.new(position + direction * speed * i * STEP) * CFrame.Angles(i, i * 0.5, 0), size = Vector3.one * 2, transparency = 0 }
	end), false, Enum.PartType.Ball)
	local core = piece(CYAN, steps(count, function(i)
		return { cframe = CFrame.new(position + direction * speed * i * STEP), size = Vector3.one * 0.7, transparency = 0 }
	end), true, Enum.PartType.Ball)
	for _, h in { ball, core } do
		if h then
			table.insert(handles, h)
		end
	end
	flying[id] = handles
	local attacker = info.attacker
	if typeof(attacker) == "Instance" and attacker:IsA("Model") then
		Sfx.PlayRemote(attacker, "SporeThrow", 1, 1, position)
	end
end

local function projectileEnd(info: { [string]: any })
	local id = info.id
	if typeof(id) ~= "number" then
		return
	end
	local handles = flying[id]
	flying[id] = nil
	if handles then
		for _, h in handles do
			FxPieces.Stop(h)
		end
	end
	if typeof(info.position) == "Vector3" and near(info.position) then
		burst(info.position, 1.2)
	end
end

local function patch(info: { [string]: any })
	local at: Vector3 = info.position
	local seconds: number = if typeof(info.seconds) == "number" then info.seconds else 0.2
	if typeof(at) ~= "Vector3" or not near(at) then
		return
	end
	local count = math.max(math.ceil(seconds / STEP), 2)
	local disc = CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	piece(BASE, steps(count + 8, function(i)
		local r = math.min(1.5 + i * 0.8, 5)
		return { cframe = disc, size = Vector3.new(0.1, r, r), transparency = if i > count + 5 then 0.5 else 0 }
	end), false, Enum.PartType.Cylinder)
	piece(CYAN, steps(count, function(i)
		return { cframe = CFrame.new(at + Vector3.new(0, 0.1, 0)), size = Vector3.new(0.3, 0.1, 0.3) * (1 + i * 0.3), transparency = 0 }
	end), true)
	-- The eruption, when the wind-up ends.
	task.delay(seconds, function()
		for i = 1, 5 do
			local angle = i / 5 * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (if i == 5 then 0 else 1.4)
			-- Leaning in toward the middle a little.
			local lean = CFrame.Angles(offset.Z * 0.15, 0, -offset.X * 0.15)
			local color = if i % 2 == 0 then BONE else BASE
			piece(color, steps(10, function(k)
				local h = if k <= 3 then k * 5 else (if k >= 8 then (11 - k) * 5 else 15)
				return { cframe = CFrame.new(at + offset) * lean * CFrame.new(0, h / 2, 0), size = Vector3.new(0.5, h, 0.5), transparency = 0 }
			end))
		end
	end)
end

local function tendrils(attacker: Model, target: Model, seconds: number)
	local count = math.max(math.ceil(seconds / STEP), 2)
	for t = 1, 3 do
		piece(if t == 2 then CYAN else BASE, steps(count, function(i)
			local hand = handCFrame(attacker)
			local torso = part(target, "Torso")
			if not hand or not torso then
				return { transparency = 1 }
			end
			local from = hand.Position
			local to = torso.Position + Vector3.new(0, (t - 2) * 0.6, 0)
			local wobble = Vector3.new(0, math.sin(i + t) * 0.3, 0)
			local mid = (from + to) / 2 + wobble
			local length = (to - from).Magnitude
			return { cframe = CFrame.lookAlong(mid, (to - from).Unit), size = Vector3.new(0.18, 0.18, length), transparency = 0 }
		end), t == 2)
	end
end

-- Growth over a whole body, then burst (the wrap).
local function wrap(target: Model, seconds: number)
	local limbs = { "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Head" }
	local count = math.max(math.ceil(seconds / STEP), 3)
	for _, name in limbs do
		local limb = part(target, name)
		if limb then
			for b = 1, 2 do
				local offset = Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.5, 0.5))
				piece(if b == 1 then BASE else DARK_TEAL, steps(count, function(i)
					local s = math.min(0.4 + i * 0.25, 1.3) + (if i % 4 < 2 then 0 else 0.1)
					return { cframe = limb.CFrame * CFrame.new(offset), size = Vector3.one * s, transparency = 0 }
				end), false, Enum.PartType.Ball)
			end
		end
	end
	task.delay(seconds, function()
		local torso = part(target, "Torso")
		if torso then
			burst(torso.Position, 3)
		end
	end)
end

local remotes = CombatRemotes.Get()
remotes.Fx.OnClientEvent:Connect(function(info: { [string]: any })
	local kind = if typeof(info.type) == "string" then info.type else ""
	local target: Model? = if typeof(info.target) == "Instance" and info.target:IsA("Model") then info.target else nil
	local attacker: Model? = if typeof(info.attacker) == "Instance" and info.attacker:IsA("Model") then info.attacker else nil
	if kind == "Projectile" then
		projectile(info)
	elseif kind == "ProjectileEnd" then
		projectileEnd(info)
	elseif kind == "Patch" then
		patch(info)
	elseif kind == "Hit" and attacker and target and typeof(info.move) == "string" then
		local move = Moves.Get(info.move)
		local grab = move and move.Grab
		if grab then
			tendrils(attacker, target, grab.Hold * FRAME)
		end
	elseif kind == "Lotus" and target then
		local what = info.what
		local torso = part(target, "Torso")
		local at = if torso then torso.Position else (if typeof(info.position) == "Vector3" then info.position else Vector3.zero)
		if not near(at) then
			return
		end
		if what == "Heal" then
			local share = if typeof(info.share) == "number" then info.share else 1
			label(target, string.format("+%g HP", math.floor(CombatConfig.HealHealth * share * 10 + 0.5) / 10), HEAL_TEXT)
			Sfx.PlayRemote(target, "FungusHeal", 1, 1, at)
		elseif what == "RipOut" then
			local arm = part(target, "Left Arm")
			burst(if arm then arm.Position else at, 1.2)
			label(target, string.format("-%d HP", CombatConfig.RipOutHealth), Color3.fromRGB(255, 120, 110))
			Sfx.PlayRemote(target, "FungusRip", 1, 1, at)
		elseif what == "Form" then
			for s = 1, 3 do
				piece(BASE, steps(8, function(i)
					local size = 3 + s * 1.2 + math.min(i, 4) * 0.5
					return { cframe = CFrame.new(at), size = Vector3.one * size, transparency = 0.55 + s * 0.1 + i * 0.03 }
				end), false, Enum.PartType.Ball)
			end
			label(target, "FORM", CYAN)
			Sfx.PlayRemote(target, "FungusForm", 1, 1, at)
		elseif what == "FormEnd" then
			burst(at, 2.5)
		elseif what == "Consumed" then
			burst(at, 1.8)
			label(target, "CONSUMED", Color3.fromRGB(255, 120, 110))
			Sfx.PlayRemote(target, "FungusRip", 0.8, 1, at)
		elseif what == "Wrap" then
			wrap(target, CombatConfig.WrapFrames * FRAME)
			label(target, "WRAPPED", CYAN)
			Sfx.PlayRemote(target, "FungusFeast", 1, 1, at)
		end
	end
end)

-- INFESTED ------------------------------------------------------------------------------------

type Infestation = { parts: { Part }, connection: RBXScriptConnection? }
local infested: { [Model]: Infestation } = {}

local function clearInfestation(model: Model, pop: boolean)
	local current = infested[model]
	if not current then
		return
	end
	infested[model] = nil
	if current.connection then
		current.connection:Disconnect()
	end
	for _, p in current.parts do
		if pop then
			burst(p.Position, 0.8)
		end
		p:Destroy()
	end
end

-- Blobs on the limbs (welded, local only), growing in steps, then pulsing until it ends.
local function infest(model: Model)
	clearInfestation(model, false)
	local state: Infestation = { parts = {}, connection = nil }
	infested[model] = state
	type Spot = { limb: string, at: Vector3 }
	local spots: { Spot } = {
		{ limb = "Left Arm", at = Vector3.new(-0.4, -0.2, 0.2) },
		{ limb = "Right Leg", at = Vector3.new(0.3, 0.3, -0.4) },
		{ limb = "Torso", at = Vector3.new(0.6, -0.4, -0.45) },
		{ limb = "Right Arm", at = Vector3.new(0.45, 0.4, 0) },
		{ limb = "Left Leg", at = Vector3.new(-0.2, -0.5, 0.45) },
	}
	for i, spot in spots do
		local limb = part(model, spot.limb)
		if limb then
			local blob = Instance.new("Part")
			blob.Shape = Enum.PartType.Ball
			blob.Size = Vector3.one * 0.3
			blob.Color = if i % 2 == 0 then DARK_TEAL else BASE
			blob.Material = Enum.Material.SmoothPlastic
			blob.CanCollide = false
			blob.CanQuery = false
			blob.CanTouch = false
			blob.Massless = true
			blob.CastShadow = false
			blob.CFrame = limb.CFrame * CFrame.new(spot.at)
			local weld = Instance.new("Weld")
			weld.Part0 = limb
			weld.Part1 = blob
			weld.C0 = CFrame.new(spot.at)
			weld.Parent = blob
			blob.Parent = model
			table.insert(state.parts, blob)
		end
	end
	local started = os.clock()
	local lastStep = -1
	state.connection = RunService.Heartbeat:Connect(function()
		local stepIndex = math.floor((os.clock() - started) / 0.15)
		if stepIndex == lastStep then
			return
		end
		lastStep = stepIndex
		local grown = math.min(0.3 + stepIndex * 0.15, 0.75)
		local pulse = if stepIndex > 3 and stepIndex % 3 == 0 then 0.12 else 0
		for _, blob in state.parts do
			blob.Size = Vector3.one * (grown + pulse)
		end
	end)
end

local function watch(model: Model)
	model:GetAttributeChangedSignal("Move"):Connect(function()
		if model ~= player.Character then
			onMove(model, model:GetAttribute("Move"))
		end
	end)
	model:GetAttributeChangedSignal("LocalMove"):Connect(function()
		if model == player.Character then
			onMove(model, model:GetAttribute("LocalMove"))
		end
	end)
	model:GetAttributeChangedSignal("Infested"):Connect(function()
		if model:GetAttribute("Infested") == true then
			infest(model)
		else
			clearInfestation(model, true)
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			clearInfestation(model, false)
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
