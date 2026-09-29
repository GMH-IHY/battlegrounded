--!strict
-- MovementFx (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > MovementFx
--
-- Small retro movement effects for every character nearby (docs/art/ArtDirection.md):
--   sweat  small blue balls popping off the head while the character is burnt out (the server's
--          "Burnout" attribute, which replicates)
--   dust   a low-poly grey cloud at the feet on a hard landing and when a dash starts: a few
--          faceted puffs (two cubes turned against each other) that swell, drift and fade in steps
-- Each client draws them from what it can see, so nothing extra is sent over the network. Every
-- effect moves in steps (FX_RATE updates per second, no tweening), like the animations. Parts are
-- pooled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FX_RATE = 20 -- effect updates per second (the step size)
local MAX_DISTANCE = 150 -- no effects for characters farther than this from the camera
local GRAVITY = 60 -- studs/s² for sweat drops (lighter than real: they arc)

local SWEAT_INTERVAL = 0.3 -- seconds between drops while burnt out
local SWEAT_SIZE = 0.22
local SWEAT_LIFE = 0.35
local SWEAT_COLOR = Color3.fromRGB(110, 190, 255)

local DUST_COLOR = Color3.fromRGB(190, 186, 176)
local LAND_IMPACT = 45 -- falling at least this fast (studs/s) when landing kicks up dust
local BIG_IMPACT = 95 -- ... this fast: a bigger cloud
local PUFF_LIFE = 0.45
local PUFF_DRAG = 6 -- per second: puffs slow down as they drift
local DASH_JUMP = 22 -- horizontal speed jumping up by this much in one frame = a dash started
local DASH_MIN_SPEED = 40
-- In the air, by Humanoid state (it replicates for every character; FloorMaterial isn't reliable
-- for other players' characters).
local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

-- A particle is one or more parts moving together. "drop" particles shrink as they fall; "puff"
-- particles swell to their full size, then shrink and fade (a cloud).
type Particle = {
	parts: { Part },
	offsets: { CFrame },
	cframe: CFrame,
	velocity: Vector3,
	gravity: number,
	drag: number,
	size: number,
	kind: "drop" | "puff",
	life: number,
	age: number,
}

type Watch = {
	character: Model,
	root: BasePart,
	head: BasePart?,
	humanoid: Humanoid,
	lastVelocity: Vector3,
	airborne: boolean,
	lowestVy: number,
	nextSweat: number,
}

local folder = Instance.new("Folder")
folder.Name = "MovementFx"
folder.Parent = Workspace

local pool: { Part } = {}
local particles: { Particle } = {}
local watched: { [Model]: Watch } = {}
local rng = Random.new()

local function take(shape: Enum.PartType): Part
	local part = table.remove(pool)
	if not part then
		local fresh = Instance.new("Part")
		fresh.Anchored = true
		fresh.CanCollide = false
		fresh.CanQuery = false
		fresh.CanTouch = false
		fresh.CastShadow = false
		fresh.Material = Enum.Material.SmoothPlastic
		fresh.TopSurface = Enum.SurfaceType.Smooth
		fresh.BottomSurface = Enum.SurfaceType.Smooth
		part = fresh
	end
	assert(part, "MovementFx: no part")
	part.Shape = shape
	part.Transparency = 0
	part.Parent = folder
	return part
end

local function release(part: Part)
	part.Parent = nil
	table.insert(pool, part)
end

local function place(p: Particle)
	for i, part in p.parts do
		part.CFrame = p.cframe * p.offsets[i]
	end
end

local function resize(p: Particle, size: number, transparency: number)
	for _, part in p.parts do
		part.Size = Vector3.one * math.max(size, 0.05)
		part.Transparency = transparency
	end
end

local function spawnDrop(size: number, color: Color3, position: Vector3, velocity: Vector3)
	local part = take(Enum.PartType.Ball)
	part.Color = color
	local p: Particle = {
		parts = { part },
		offsets = { CFrame.identity },
		cframe = CFrame.new(position),
		velocity = velocity,
		gravity = GRAVITY,
		drag = 0,
		size = size,
		kind = "drop",
		life = SWEAT_LIFE,
		age = 0,
	}
	resize(p, size, 0)
	place(p)
	table.insert(particles, p)
end

-- One faceted puff: two cubes, the second turned 45° on two axes, so together they read as a
-- chunky low-poly ball.
local function spawnPuff(size: number, position: Vector3, velocity: Vector3)
	local a, b = take(Enum.PartType.Block), take(Enum.PartType.Block)
	local shade = rng:NextNumber(0.9, 1.05)
	local color = Color3.new(
		math.min(DUST_COLOR.R * shade, 1),
		math.min(DUST_COLOR.G * shade, 1),
		math.min(DUST_COLOR.B * shade, 1)
	)
	a.Color, b.Color = color, color
	local spin = CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
	local p: Particle = {
		parts = { a, b },
		offsets = { CFrame.identity, CFrame.Angles(math.rad(45), math.rad(45), 0) },
		cframe = CFrame.new(position) * spin,
		velocity = velocity,
		gravity = 0,
		drag = PUFF_DRAG,
		size = size,
		kind = "puff",
		life = PUFF_LIFE * rng:NextNumber(0.85, 1.15),
		age = 0,
	}
	resize(p, size * 0.5, 0)
	place(p)
	table.insert(particles, p)
end

local function sweat(watch: Watch)
	local head = watch.head
	if not head then
		return
	end
	local look = watch.root.CFrame
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local origin = head.Position + look.RightVector * (0.55 * side) + Vector3.new(0, 0.2, 0)
	local velocity = look.RightVector * (side * rng:NextNumber(3, 6)) - look.LookVector * rng:NextNumber(1, 3)
		+ Vector3.new(0, rng:NextNumber(8, 12), 0)
	spawnDrop(SWEAT_SIZE, SWEAT_COLOR, origin, velocity)
end

-- A cloud of `count` puffs at the feet: a ring (landing) or a spray behind (dash start).
local function dust(watch: Watch, count: number, spread: number, size: number, behind: boolean)
	local root = watch.root
	local feet = root.Position - Vector3.new(0, 2.6, 0)
	for i = 1, count do
		local angle
		if behind then
			local back = -root.CFrame.LookVector
			angle = math.atan2(back.X, back.Z) + rng:NextNumber(-0.8, 0.8)
		else
			angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		end
		local out = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local velocity = out * spread * rng:NextNumber(0.8, 1.2) + Vector3.new(0, rng:NextNumber(1.5, 3.5), 0)
		spawnPuff(size * rng:NextNumber(0.8, 1.25), feet + out * 0.7, velocity)
	end
end

local function track(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (root and root:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local head = character:FindFirstChild("Head")
	watched[character] = {
		character = character,
		root = root,
		head = if head and head:IsA("BasePart") then head else nil,
		humanoid = humanoid,
		lastVelocity = root.AssemblyLinearVelocity,
		airborne = false,
		lowestVy = 0,
		nextSweat = 0,
	}
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			watched[character] = nil
		end
	end)
end

-- Every frame: events (landings, dash starts) are caught the frame they happen.
local function watchCharacters(now: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, watch in watched do
		local root = watch.root
		local velocity = root.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local lastFlat = Vector3.new(watch.lastVelocity.X, 0, watch.lastVelocity.Z).Magnitude
		local near = (root.Position - eye).Magnitude <= MAX_DISTANCE
		local airborne = AIR_STATES[watch.humanoid:GetState()] == true

		if airborne then
			watch.lowestVy = math.min(watch.lowestVy, velocity.Y)
		elseif watch.airborne then
			-- Just landed: dust by how hard.
			local impact = -watch.lowestVy
			if near and impact >= BIG_IMPACT then
				dust(watch, 6, 12, 1.6, false)
			elseif near and impact >= LAND_IMPACT then
				dust(watch, 4, 8, 1.1, false)
			end
			watch.lowestVy = 0
		end
		watch.airborne = airborne

		if near and not airborne and flatSpeed >= DASH_MIN_SPEED and flatSpeed - lastFlat >= DASH_JUMP then
			dust(watch, 3, 6, 1, true)
		end

		if near and watch.character:GetAttribute("Burnout") == true and now >= watch.nextSweat then
			watch.nextSweat = now + SWEAT_INTERVAL * rng:NextNumber(0.8, 1.2)
			sweat(watch)
		end
		watch.lastVelocity = velocity
	end
end

-- FX_RATE times a second: move every particle one step.
local function stepParticles(dt: number)
	for i = #particles, 1, -1 do
		local p = particles[i]
		p.age += dt
		if p.age >= p.life then
			for _, part in p.parts do
				release(part)
			end
			table.remove(particles, i)
			continue
		end
		p.velocity -= Vector3.new(0, p.gravity * dt, 0)
		p.velocity *= math.max(1 - p.drag * dt, 0)
		p.cframe += p.velocity * dt
		local t = p.age / p.life
		if p.kind == "drop" then
			resize(p, p.size * (1 - t), 0)
		elseif t < 0.35 then
			-- Swell in steps to full size.
			resize(p, p.size * (0.5 + t / 0.35 * 0.5), 0)
		else
			-- Shrink a little and fade out in steps.
			local fade = (t - 0.35) / 0.65
			resize(p, p.size * (1 - fade * 0.4), math.floor(fade * 4) / 4 * 0.8)
		end
		place(p)
	end
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	watchCharacters(os.clock())
	accumulator += dt
	local step = 1 / FX_RATE
	if accumulator >= step then
		accumulator %= step
		stepParticles(step)
	end
end)

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(track, player.Character)
	end
	player.CharacterAdded:Connect(track)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
