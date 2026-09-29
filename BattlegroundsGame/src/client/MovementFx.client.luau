--!strict
-- MovementFx (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > MovementFx
--
-- Small retro movement effects for every character nearby (docs/art/ArtDirection.md):
--   sweat  small blue balls popping off the head while running
--   dust   grey cubes kicked out at the feet on a hard landing and when a dash starts
-- Each client draws them from what it can see (speeds replicate; the owner-only attributes like
-- "Sprinting" don't), so nothing is sent over the network. Every effect moves in steps (FxRate
-- updates per second, no tweening), like the animations. Parts are pooled.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FX_RATE = 20 -- effect updates per second (the step size)
local MAX_DISTANCE = 150 -- no effects for characters farther than this from the camera
local GRAVITY = 60 -- studs/s² for sweat drops (lighter than real: they arc)

local SWEAT_SPEED = 21 -- running at least this fast sweats (run speed is 26)
local SWEAT_INTERVAL = 0.32 -- seconds between drops
local SWEAT_SIZE = 0.22
local SWEAT_LIFE = 0.35
local SWEAT_COLOR = Color3.fromRGB(110, 190, 255)

local DUST_COLOR = Color3.fromRGB(190, 186, 176)
local LAND_IMPACT = 45 -- falling at least this fast (studs/s) when landing kicks up dust
local HEAVY_IMPACT = 95 -- ... this fast: a bigger ring
local DASH_JUMP = 22 -- horizontal speed jumping up by this much in one frame = a dash started
local DASH_MIN_SPEED = 40
-- In the air, by Humanoid state (it replicates for every character; FloorMaterial isn't reliable
-- for other players' characters).
local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

type Particle = {
	part: Part,
	velocity: Vector3,
	gravity: number,
	shrink: number,
	life: number,
	age: number,
}

type Watch = {
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

local function spawn(shape: Enum.PartType, size: number, color: Color3, cframe: CFrame, velocity: Vector3, gravity: number, life: number)
	local part = take(shape)
	part.Size = Vector3.one * size
	part.Color = color
	part.CFrame = cframe
	table.insert(particles, {
		part = part,
		velocity = velocity,
		gravity = gravity,
		shrink = size / math.max(life * FX_RATE, 1),
		life = life,
		age = 0,
	})
end

local function sweat(watch: Watch)
	local head = watch.head
	if not head then
		return
	end
	local look = watch.root.CFrame
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local origin = head.Position + look.RightVector * (0.55 * side) + Vector3.new(0, 0.2, 0)
	local velocity = look.RightVector * (side * rng:NextNumber(3, 6)) - look.LookVector * rng:NextNumber(4, 8)
		+ Vector3.new(0, rng:NextNumber(8, 12), 0)
	spawn(Enum.PartType.Ball, SWEAT_SIZE, SWEAT_COLOR, CFrame.new(origin), velocity, GRAVITY, SWEAT_LIFE)
end

local function dust(watch: Watch, count: number, spread: number, size: number, behind: boolean)
	local root = watch.root
	local feet = root.Position - Vector3.new(0, 2.8, 0)
	for i = 1, count do
		local angle
		if behind then
			local back = -root.CFrame.LookVector
			angle = math.atan2(back.X, back.Z) + rng:NextNumber(-0.7, 0.7)
		else
			angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		end
		local out = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local velocity = out * spread * rng:NextNumber(0.8, 1.2) + Vector3.new(0, rng:NextNumber(2, 5), 0)
		local cframe = CFrame.new(feet + out * 0.6) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0)
		spawn(Enum.PartType.Block, size * rng:NextNumber(0.8, 1.2), DUST_COLOR, cframe, velocity, 0, 0.25)
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
			if near and impact >= HEAVY_IMPACT then
				dust(watch, 10, 14, 0.7, false)
			elseif near and impact >= LAND_IMPACT then
				dust(watch, 6, 9, 0.5, false)
			end
			watch.lowestVy = 0
		end
		watch.airborne = airborne

		if near and not airborne and flatSpeed >= DASH_MIN_SPEED and flatSpeed - lastFlat >= DASH_JUMP then
			dust(watch, 4, 7, 0.45, true)
		end

		if near and not airborne and flatSpeed >= SWEAT_SPEED and flatSpeed < DASH_MIN_SPEED and now >= watch.nextSweat then
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
			release(p.part)
			table.remove(particles, i)
		else
			p.velocity -= Vector3.new(0, p.gravity * dt, 0)
			p.part.CFrame += p.velocity * dt
			local size = math.max(p.part.Size.X - p.shrink, 0.05)
			p.part.Size = Vector3.one * size
		end
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
