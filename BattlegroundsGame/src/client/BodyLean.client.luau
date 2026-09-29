--!strict
-- BodyLean (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > BodyLean
--
-- Tilts every character very slightly into its turns and with its speed changes, on top of whatever
-- animation plays: banking into a curve while running, a lean forward when speeding up and back
-- when braking. It's visual only (nothing about movement changes) and computed on each client for
-- every character from its velocity, so nothing is sent over the network.
--
-- Stepped like the animations: the lean jumps to a new angle a few times a second (UpdateRate) in
-- whole steps of StepDegrees, instead of gliding. It's off while another move owns the body
-- (dash, wall run, parkour, roll, flight), in the air, when standing still, and faster than a run.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Kept extremely subtle: a hint of weight, never a pose of its own.
local BANK_PER_TURN = 0.025 -- degrees of tilt per degree/second of turning
local MAX_BANK = 3 -- degrees
local LEAN_PER_ACCEL = 0.02 -- degrees of forward lean per stud/s² of speed change
local MAX_LEAN = 2 -- degrees
local STEP_DEGREES = 1
local UPDATE_RATE = 15 -- per second
local MIN_SPEED = 6 -- studs/s: slower than this, no lean
-- Faster than running = a dash or a parkour move. The "busy" attributes below are only set on the
-- owner's client, so this is how other players' moves are recognized.
local MAX_SPEED = 30
local BUSY_ATTRIBUTES = { "Dashing", "WallRunning", "Parkour", "Rolling", "Flying" }
local GROUND_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

type Lean = {
	root: BasePart,
	humanoid: Humanoid,
	joint: Motor6D,
	c0Rotation: CFrame,
	lastDirection: Vector3,
	lastSpeed: number,
	lastSample: number,
	bank: number,
	lean: number,
}

local leans: { [Model]: Lean } = {}

local function quantize(degrees: number): number
	return math.round(degrees / STEP_DEGREES) * STEP_DEGREES
end

local function busy(character: Model): boolean
	for _, name in BUSY_ATTRIBUTES do
		local value = character:GetAttribute(name)
		if value ~= nil and value ~= false then
			return true
		end
	end
	return false
end

local function track(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local joint = if root then root:WaitForChild("RootJoint", 10) else nil
	if not (root and root:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid") and joint and joint:IsA("Motor6D")) then
		return
	end
	leans[character] = {
		root = root,
		humanoid = humanoid,
		joint = joint,
		c0Rotation = joint.C0.Rotation,
		lastDirection = Vector3.zero,
		lastSpeed = 0,
		lastSample = os.clock(),
		bank = 0,
		lean = 0,
	}
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			leans[character] = nil
		end
	end)
end

-- Picks the next stepped lean from how the velocity changed since the last sample.
local function sample(character: Model, lean: Lean, now: number)
	local dt = now - lean.lastSample
	lean.lastSample = now
	local velocity = lean.root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	local grounded = GROUND_STATES[lean.humanoid:GetState()] == true
	if speed < MIN_SPEED or speed > MAX_SPEED or not grounded or busy(character) or dt <= 0 then
		lean.bank, lean.lean = 0, 0
		lean.lastDirection = if speed > 0.1 then flat.Unit else Vector3.zero
		lean.lastSpeed = speed
		return
	end
	local direction = flat.Unit
	local turnRate = 0
	if lean.lastDirection.Magnitude > 0.5 then
		-- + = turning left (counter-clockwise seen from above).
		local sine = lean.lastDirection:Cross(direction).Y
		turnRate = math.deg(math.asin(math.clamp(sine, -1, 1))) / dt
	end
	local accel = (speed - lean.lastSpeed) / dt
	-- Turning left tilts the top of the body left (negative tilt); faster = more.
	local speedShare = math.clamp(speed / 26, 0, 1)
	lean.bank = quantize(math.clamp(-turnRate * BANK_PER_TURN * speedShare, -MAX_BANK, MAX_BANK))
	lean.lean = quantize(math.clamp(accel * LEAN_PER_ACCEL, -MAX_LEAN, MAX_LEAN))
	lean.lastDirection = direction
	lean.lastSpeed = speed
end

local nextSample = 0
RunService.PreSimulation:Connect(function()
	local now = os.clock()
	local resample = now >= nextSample
	if resample then
		nextSample = now + 1 / UPDATE_RATE
	end
	for character, lean in leans do
		if resample then
			sample(character, lean, now)
		end
		if lean.bank ~= 0 or lean.lean ~= 0 then
			-- Same convention as the animation tools: forward lean = -pitch, tilt right = -roll, in
			-- the character's space, turned into the RootJoint's own frame.
			local extra = CFrame.Angles(math.rad(-lean.lean), 0, math.rad(-lean.bank))
			lean.joint.Transform *= lean.c0Rotation:Inverse() * extra * lean.c0Rotation
		end
	end
end)

local function watch(player: Player)
	if player.Character then
		task.spawn(track, player.Character)
	end
	player.CharacterAdded:Connect(track)
end

for _, player in Players:GetPlayers() do
	watch(player)
end
Players.PlayerAdded:Connect(watch)
