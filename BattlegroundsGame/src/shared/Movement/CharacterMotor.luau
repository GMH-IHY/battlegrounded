--!strict
-- CharacterMotor (ModuleScript)
-- Location: ReplicatedStorage > Movement > CharacterMotor
--
-- The movement core for one character. It runs on the client (Roblox gives each player
-- physics ownership of their own character) and layers a custom velocity system on top
-- of the Humanoid:
--
--   Ground : the Humanoid moves the character, but we drive its WalkSpeed every frame
--            (walk -> run ramp, momentum decay, sharp-turn penalty).
--   Air    : we take over horizontal velocity with a LinearVelocity so momentum carries
--            through jumps, and add extra gravity while falling, capped at terminal velocity.
--   Passive: seated, swimming, climbing a ladder, ragdolled, dead... the Humanoid is left alone.
--   Suspended: another system (dash, wall run, an ability) has taken control. When it
--            calls Resume(), the motor picks up whatever velocity the body has, so momentum
--            carries between actions automatically.
--
-- Other client scripts can get the motor with CharacterMotor.Get(character).

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.MovementConfig)
local Perf = require(script.Parent.Perf)

export type Mode = "Ground" | "Air" | "Passive" | "Suspended"

-- The Humanoid climbs trusses at this share of its WalkSpeed (measured in Studio: 12 -> 8.4).
local HUMANOID_CLIMB_FACTOR = 0.7

local GROUND_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local AIR_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
}

local MIN_TIME = 1e-3
local PHYSICS_STEP = 1 / 240
local SHARP_TURN_COS = math.cos(math.rad(Config.SharpTurnAngle))
-- A jump that started this recently still counts for the current airtime. The Humanoid's
-- Jumping state can last less than one frame, so we can't rely on seeing it in _step.
local JUMP_MEMORY = 0.25
-- How long a wall we bumped into keeps blocking velocity toward it.
local WALL_MEMORY = 0.15
-- How long momentum handed over by another move survives the Humanoid slowing the body down.
local CARRY_MEMORY = 0.2
-- Keys must point within ~53 degrees of straight into a truss to grab it (cos).
local TRUSS_FACING = 0.6
-- Surfaces steeper than this (normal.Y below it) count as walls.
local WALL_MAX_NORMAL_Y = 0.7

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Moves vector `current` toward `target` by at most `maxDelta`.
local function moveTowards(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance < 1e-6 then
		return target
	end
	return current + delta * (maxDelta / distance)
end

-- Removes the part of `v` that points into a wall with outward normal `normal` (flat, unit).
local function slideAlong(v: Vector3, normal: Vector3): Vector3
	local into = v:Dot(normal)
	if into < 0 then
		return v - normal * into
	end
	return v
end

local function makeFrictionless(part: BasePart)
	local current = part.CurrentPhysicalProperties
	part.CustomPhysicalProperties =
		PhysicalProperties.new(current.Density, 0, current.Elasticity, 100, current.ElasticityWeight)
end

local CharacterMotor = {}
CharacterMotor.__index = CharacterMotor

type MotorData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	attachment: Attachment,
	airVelocity: LinearVelocity,
	gravityForce: VectorForce,
	lowerCollider: Part,
	wallRayHeights: { number },
	floorRayOffsets: { Vector3 },
	floorRayLength: number,
	standHeight: number,
	castParams: RaycastParams,
	connections: { RBXScriptConnection },

	mode: Mode,
	suspended: boolean,
	destroyed: boolean,

	sprinting: boolean,
	jumpHeld: boolean,

	groundSpeed: number,
	lastMoveDirection: Vector3,

	airHorizontal: Vector3,
	airSpeedCap: number,
	carried: Vector3,
	carriedUntil: number,
	fallTime: number,
	jumpedThisAirtime: boolean,
	lastJumpTime: number,
	coyoteUntil: number,
	jumpBufferUntil: number,
	moveJumpUntil: number,
	climbLockUntil: number,
	climbLocked: boolean,
	climbAllowed: boolean,
	wallNormal: Vector3,
	wallUntil: number,
	launchAllowedUntil: number,
	airRestY: number,
	groundRootY: number,
	jumpVelocityPending: boolean,
	landingHandler: (() -> boolean)?,
}

export type CharacterMotor = typeof(setmetatable({} :: MotorData, CharacterMotor))

local activeMotors: { [Model]: CharacterMotor } = {}

function CharacterMotor.new(character: Model): CharacterMotor
	local humanoidInstance = character:WaitForChild("Humanoid")
	local rootInstance = character:WaitForChild("HumanoidRootPart")
	assert(humanoidInstance:IsA("Humanoid"), "CharacterMotor: Humanoid not found")
	assert(rootInstance:IsA("BasePart"), "CharacterMotor: HumanoidRootPart not found")
	local humanoid: Humanoid = humanoidInstance
	local root: BasePart = rootInstance

	humanoid.UseJumpPower = false
	humanoid.JumpHeight = Config.JumpHeight
	humanoid.WalkSpeed = Config.WalkSpeed

	local attachment = Instance.new("Attachment")
	attachment.Name = "MotorAttachment"
	attachment.Parent = root

	-- Horizontal-only velocity control used in the air. Plane mode leaves the Y axis to physics.
	local airVelocity = Instance.new("LinearVelocity")
	airVelocity.Name = "MotorAirVelocity"
	airVelocity.Attachment0 = attachment
	airVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	airVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	airVelocity.PrimaryTangentAxis = Vector3.xAxis
	airVelocity.SecondaryTangentAxis = Vector3.zAxis
	airVelocity.MaxForce = math.huge
	airVelocity.Enabled = false
	airVelocity.Parent = root

	-- Extra downward force while falling (or upward, to hold terminal velocity).
	local gravityForce = Instance.new("VectorForce")
	gravityForce.Name = "MotorGravity"
	gravityForce.Attachment0 = attachment
	gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
	gravityForce.ApplyAtCenterOfMass = true
	gravityForce.Force = Vector3.zero
	gravityForce.Parent = root

	-- R6 legs don't collide, so without this you could clear ledges about 2 studs taller than
	-- your jump. This invisible box fills the leg area, starting LowerColliderGap above the feet
	-- so small bumps and stairs are still stepped over by the Humanoid.
	-- It's a little wider and deeper than the torso: when it's pressed against a ledge you
	-- can't reach, the Humanoid's floor check (which uses the torso's footprint) stays just
	-- short of the ledge top, so the Humanoid can't pop you up onto the edge.
	local legLength = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local colliderHeight = math.max(legLength - Config.LowerColliderGap, 0.2)
	local lowerCollider = Instance.new("Part")
	lowerCollider.Name = "LowerBodyCollider"
	local margin = Config.LowerColliderMargin * 2
	lowerCollider.Size = Vector3.new(root.Size.X + margin, colliderHeight, root.Size.Z + margin)
	lowerCollider.Transparency = 1
	lowerCollider.Massless = true
	lowerCollider.CanCollide = true
	lowerCollider.CanQuery = false
	lowerCollider.CanTouch = false
	lowerCollider.CFrame = root.CFrame * CFrame.new(0, -(root.Size.Y + colliderHeight) / 2, 0)
	local colliderWeld = Instance.new("WeldConstraint")
	colliderWeld.Part0 = root
	colliderWeld.Part1 = lowerCollider
	colliderWeld.Parent = lowerCollider
	lowerCollider.Parent = character

	-- Heights (relative to the root) of the rays that look for walls: lower body, chest, head.
	local wallRayHeights = {
		-(root.Size.Y / 2 + colliderHeight) + 0.2,
		0,
		root.Size.Y / 2 + 0.8,
	}

	-- Points inside the body's footprint (root-local) that are checked for floor below. If none
	-- of them has floor within reach while the Humanoid thinks it's standing, it's perched on a
	-- ledge edge that only its own wider floor check can see.
	local floorRayOffsets = {
		Vector3.zero,
		Vector3.new(root.Size.X * 0.4, 0, 0),
		Vector3.new(-root.Size.X * 0.4, 0, 0),
		Vector3.new(0, 0, root.Size.Z * 0.4),
		Vector3.new(0, 0, -root.Size.Z * 0.4),
	}
	-- Generous on purpose: the Humanoid enters its landed state a little before touchdown.
	local floorRayLength = root.Size.Y / 2 + legLength + 2

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true

	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		attachment = attachment,
		airVelocity = airVelocity,
		gravityForce = gravityForce,
		lowerCollider = lowerCollider,
		wallRayHeights = wallRayHeights,
		floorRayOffsets = floorRayOffsets,
		floorRayLength = floorRayLength,
		standHeight = root.Size.Y / 2 + legLength,
		castParams = castParams,
		connections = {},

		mode = "Passive" :: Mode,
		suspended = false,
		destroyed = false,

		sprinting = false,
		jumpHeld = false,

		groundSpeed = 0,
		lastMoveDirection = Vector3.zero,

		airHorizontal = Vector3.zero,
		airSpeedCap = 0,
		carried = Vector3.zero,
		carriedUntil = 0,
		fallTime = 0,
		jumpedThisAirtime = false,
		lastJumpTime = -math.huge,
		coyoteUntil = 0,
		jumpBufferUntil = 0,
		moveJumpUntil = 0,
		climbLockUntil = 0,
		climbLocked = false,
		climbAllowed = true,
		wallNormal = Vector3.zero,
		wallUntil = 0,
		launchAllowedUntil = 0,
		airRestY = root.Position.Y,
		groundRootY = root.Position.Y,
		jumpVelocityPending = false,
		landingHandler = nil,
	}, CharacterMotor)

	-- Frictionless body, so a wall can never hold the character up. Applied to every part,
	-- including ones added later, because the Humanoid toggles CanCollide on limbs itself.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			makeFrictionless(descendant)
		end
	end
	table.insert(
		self.connections,
		character.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				makeFrictionless(descendant)
			end
		end)
	)

	-- Catch every jump, even ones whose Jumping state starts and ends between two frames.
	table.insert(
		self.connections,
		humanoid.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Jumping and old == Enum.HumanoidStateType.Climbing then
				-- Jumped off a truss / ladder: no snapping straight back on (jump-spamming up a
				-- truss). It can be grabbed again after TrussRegrabDelay once you're falling, and
				-- then only by steering into it (see _updateClimbGate).
				self.climbLocked = true
				self.climbLockUntil = os.clock() + Config.TrussRegrabDelay
				self:_setClimbAllowed(false)
			end
			if new == Enum.HumanoidStateType.Jumping then
				self.jumpVelocityPending = true
				self.jumpedThisAirtime = true
				self.lastJumpTime = os.clock()
				self.coyoteUntil = 0
			end
		end)
	)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_step(dt)
				Perf.add("CharacterMotor", os.clock() - t0)
			else
				self:_step(dt)
			end
		end)
	)
	table.insert(
		self.connections,
		humanoid.Died:Connect(function()
			self:Destroy()
		end)
	)
	table.insert(
		self.connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(game) then
				self:Destroy()
			end
		end)
	)

	activeMotors[character] = self
	character:SetAttribute("Sprinting", false)
	return self
end

-- Returns the motor running on this character, if any.
function CharacterMotor.Get(character: Model): CharacterMotor?
	return activeMotors[character]
end

-- INPUT ----------------------------------------------------------------------

function CharacterMotor.SetSprinting(self: CharacterMotor, sprinting: boolean)
	if self.sprinting == sprinting then
		return
	end
	self.sprinting = sprinting
	self.character:SetAttribute("Sprinting", sprinting)
end

function CharacterMotor.SetJumpHeld(self: CharacterMotor, held: boolean)
	self.jumpHeld = held
end

function CharacterMotor.IsJumpHeld(self: CharacterMotor): boolean
	return self.jumpHeld
end

-- Call once per jump PRESS (not every frame while held). On the ground the Humanoid jumps by
-- itself; this adds coyote time (jump just after walking off a ledge) and jump buffering
-- (jump pressed just before landing). Returns true if this press made a jump right now.
function CharacterMotor.RequestJump(self: CharacterMotor): boolean
	if self.mode ~= "Air" then
		return self.mode == "Ground"
	end
	local now = os.clock()
	local rising = self.root.AssemblyLinearVelocity.Y > 1
	if not self.jumpedThisAirtime and not rising and now <= self.coyoteUntil then
		self.coyoteUntil = 0
		self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		return true
	end
	self.jumpBufferUntil = now + Config.JumpBufferTime
	return false
end

-- API FOR OTHER MOVEMENT SYSTEMS ---------------------------------------------

-- Hand control to another system (dash, wall run, ability). The motor stops applying forces.
function CharacterMotor.Suspend(self: CharacterMotor)
	self.suspended = true
end

-- Take control back. The motor reads the body's current velocity, so momentum carries over.
function CharacterMotor.Resume(self: CharacterMotor)
	self.suspended = false
end

-- Overwrite the carried horizontal momentum (e.g. a launch). Direction on the ground still
-- follows player input; only the speed carries.
function CharacterMotor.ApplyMomentum(self: CharacterMotor, velocity: Vector3)
	local flat = flatten(velocity)
	self.groundSpeed = flat.Magnitude
	self.airHorizontal = flat
	self.airSpeedCap = flat.Magnitude
	-- The Humanoid's own ground controller can eat this speed in the frames before the motor
	-- takes over again (e.g. a jump straight out of a slide), so remember it for a moment.
	self.carried = flat
	self.carriedUntil = os.clock() + CARRY_MEMORY
	if flat.Magnitude > 0 then
		self.humanoid.WalkSpeed = flat.Magnitude
	end
	if self.mode == "Air" then
		self.airVelocity.PlaneVelocity = Vector2.new(flat.X, flat.Z)
	end
end

-- A jump pressed near the end of another move (vault, climb, slide, dash). It fires the first
-- moment you're on the ground (and allowed to jump) within `window` seconds: right away if the
-- move ended on the ground, on landing if it ended in the air.
function CharacterMotor.BufferJump(self: CharacterMotor, window: number)
	self.moveJumpUntil = os.clock() + window
end

-- Called the moment you land from the air, before a buffered jump fires. Return true to take
-- over the landing (e.g. a landing roll); the buffered jump is then skipped.
function CharacterMotor.SetLandingHandler(self: CharacterMotor, handler: (() -> boolean)?)
	self.landingHandler = handler
end

-- Lets the character rise faster than a jump for `duration` seconds (knock-ups, launchers).
function CharacterMotor.AllowLaunch(self: CharacterMotor, duration: number)
	self.launchAllowedUntil = math.max(self.launchAllowedUntil, os.clock() + duration)
end

function CharacterMotor.GetMode(self: CharacterMotor): Mode
	return self.mode
end

function CharacterMotor.IsSprinting(self: CharacterMotor): boolean
	return self.sprinting
end

-- The ground speed the motor is currently aiming for (walk or run).
-- Speed multiplier from health: 1 at HealthSpeedFullAbove or more, down to LowHealthSpeedScale
-- at 0 health.
function CharacterMotor.GetHealthSpeedScale(self: CharacterMotor): number
	local humanoid = self.humanoid
	if humanoid.MaxHealth <= 0 or humanoid.Health <= 0 then
		return Config.LowHealthSpeedScale
	end
	local full = math.clamp(Config.HealthSpeedFullAbove, 1e-3, 1)
	local t = math.clamp(humanoid.Health / humanoid.MaxHealth / full, 0, 1)
	return Config.LowHealthSpeedScale + (1 - Config.LowHealthSpeedScale) * t
end

function CharacterMotor.GetWalkSpeed(self: CharacterMotor): number
	return Config.WalkSpeed * self:GetHealthSpeedScale()
end

function CharacterMotor.GetRunSpeed(self: CharacterMotor): number
	return Config.RunSpeed * self:GetHealthSpeedScale()
end

function CharacterMotor.GetTargetSpeed(self: CharacterMotor): number
	return if self.sprinting then self:GetRunSpeed() else self:GetWalkSpeed()
end

-- Current horizontal speed of the body, in studs/s.
function CharacterMotor.GetHorizontalSpeed(self: CharacterMotor): number
	return flatten(self.root.AssemblyLinearVelocity).Magnitude
end

-- SIMULATION -----------------------------------------------------------------

function CharacterMotor._step(self: CharacterMotor, dt: number)
	if self.destroyed then
		return
	end

	local state = self.humanoid:GetState()
	local newMode: Mode
	if self.suspended then
		newMode = "Suspended"
	elseif GROUND_STATES[state] then
		newMode = "Ground"
	elseif AIR_STATES[state] then
		newMode = "Air"
	else
		newMode = "Passive"
	end

	if newMode ~= self.mode then
		self:_enterMode(newMode)
	end

	-- Truss re-grab lock after jumping off one: lifted once the delay is over and you're falling
	-- (so you're always lower than where you jumped from), or when you land.
	if self.climbLocked then
		local falling = self.root.AssemblyLinearVelocity.Y < 0
		if self.mode == "Ground" or (os.clock() >= self.climbLockUntil and falling) then
			self.climbLocked = false
		end
	end
	self:_updateClimbGate(state)

	-- Trusses / ladders: the Humanoid climbs at its WalkSpeed, which is otherwise whatever the
	-- last mode left (26 after sprinting in, 14 walking in, 0 after grabbing it from the air, so
	-- you couldn't move). Climbing always uses its own speed (slower at low HP like running).
	if self.mode == "Passive" then
		if state == Enum.HumanoidStateType.Climbing then
			self.humanoid.WalkSpeed = Config.TrussClimbSpeed * self:GetHealthSpeedScale() / HUMANOID_CLIMB_FACTOR
		else
			self.humanoid.WalkSpeed = self:GetWalkSpeed()
		end
	end

	-- A jump buffered from the end of another move.
	if self.moveJumpUntil > 0 then
		if os.clock() > self.moveJumpUntil then
			self.moveJumpUntil = 0
		elseif
			self.mode == "Ground"
			and self:_hasFloor()
			and self.humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		then
			-- Real floor underfoot only: right after a vault the Humanoid can still say "running"
			-- for a frame while you're already past the edge (that jump would be dropped).
			self.moveJumpUntil = 0
			self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end

	if self.mode == "Ground" then
		self:_stepGround(dt)
		self:_holdTerminalOnTouchdown(dt)
		self:_dropIfPerched()
	elseif self.mode == "Air" then
		self:_stepAir(dt)
	end

	if self.mode == "Ground" or self.mode == "Air" then
		self:_limitRiseSpeed()
	end
end

-- Nothing in basic movement should send you up faster than a jump. Without this cap the
-- Humanoid's step-up can fight the leg collider at a ledge edge and fling you upward.
-- Abilities that launch the player call AllowLaunch() first.
function CharacterMotor._limitRiseSpeed(self: CharacterMotor)
	if os.clock() < self.launchAllowedUntil then
		return
	end
	local maxRise = math.sqrt(2 * Workspace.Gravity * Config.JumpHeight) * 1.08
	local velocity = self.root.AssemblyLinearVelocity
	if velocity.Y > maxRise then
		self.root.AssemblyLinearVelocity = Vector3.new(velocity.X, maxRise, velocity.Z)
	end
end

-- Is there floor under the body (any of the floor rays hits)?
function CharacterMotor._hasFloor(self: CharacterMotor): boolean
	local rootCFrame = self.root.CFrame
	local down = Vector3.new(0, -self.floorRayLength, 0)
	for _, offset in self.floorRayOffsets do
		if Workspace:Raycast(rootCFrame:PointToWorldSpace(offset), down, self.castParams) then
			return true
		end
	end
	return false
end

-- Stops the Humanoid from snapping you up onto a ledge your body never actually got over.
function CharacterMotor._dropIfPerched(self: CharacterMotor)
	local root = self.root
	if self:_hasFloor() then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	if velocity.Y > 0 then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	end
	self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

-- The Humanoid switches to a ground state a moment before its feet actually touch down.
-- Keep the terminal-velocity cap during that last frame so a long fall can't overshoot it.
function CharacterMotor._holdTerminalOnTouchdown(self: CharacterMotor, dt: number)
	local root = self.root
	local velocity = root.AssemblyLinearVelocity
	local gravity = Workspace.Gravity
	if velocity.Y - gravity * dt <= -Config.TerminalVelocity then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, -Config.TerminalVelocity, velocity.Z)
		self.gravityForce.Force = Vector3.new(0, gravity * root.AssemblyMass, 0)
	elseif self.gravityForce.Force ~= Vector3.zero then
		self.gravityForce.Force = Vector3.zero
	end
end

function CharacterMotor._enterMode(self: CharacterMotor, newMode: Mode)
	local oldMode = self.mode
	local now = os.clock()
	local flat = flatten(self.root.AssemblyLinearVelocity)
	self.mode = newMode

	if newMode == "Air" then
		-- Standing height to measure the jump from: where the root was on the last grounded
		-- frame (never lower than the floor estimate, in case it was still settling from a landing).
		self.airRestY = if oldMode == "Ground"
			then math.max(self:_restHeight(), self.groundRootY)
			else self:_restHeight()
		-- Just handed momentum by another move (slide-jump, vault-jump): take off with it even if
		-- the Humanoid slowed the body down in between.
		if now <= self.carriedUntil and self.carried.Magnitude > flat.Magnitude then
			local direction = if flat.Magnitude > 1 and flat.Unit:Dot(self.carried.Unit) > 0.5
				then flat.Unit
				else self.carried.Unit
			flat = direction * self.carried.Magnitude
			local current = self.root.AssemblyLinearVelocity
			self.root.AssemblyLinearVelocity = Vector3.new(flat.X, current.Y, flat.Z)
		end
		self.airHorizontal = flat
		self.airSpeedCap = flat.Magnitude
		self.fallTime = 0
		self.wallUntil = 0
		self.jumpedThisAirtime = now - self.lastJumpTime <= JUMP_MEMORY
		if not self.jumpedThisAirtime and oldMode == "Ground" then
			-- Walked off a ledge (or got knocked off): allow a late jump.
			self.coyoteUntil = now + Config.CoyoteTime
		else
			self.coyoteUntil = 0
		end
		self.airVelocity.PlaneVelocity = Vector2.new(flat.X, flat.Z)
		self.airVelocity.Enabled = true
		return
	end

	self.airVelocity.Enabled = false
	self.gravityForce.Force = Vector3.zero

	if newMode == "Ground" then
		-- Carry the speed we arrived with; _stepGround bleeds off anything above the target.
		self.groundSpeed = flat.Magnitude
		-- A move that ended a hair above the floor (a slide standing up) lands straight away; the
		-- Humanoid's landing would otherwise eat the speed it handed over.
		if now <= self.carriedUntil and self.carried.Magnitude > flat.Magnitude then
			local direction = if flat.Magnitude > 1 and flat.Unit:Dot(self.carried.Unit) > 0.5
				then flat.Unit
				else self.carried.Unit
			local carried = direction * self.carried.Magnitude
			local current = self.root.AssemblyLinearVelocity
			self.root.AssemblyLinearVelocity = Vector3.new(carried.X, current.Y, carried.Z)
			self.groundSpeed = self.carried.Magnitude
			self.humanoid.WalkSpeed = self.groundSpeed
		end
		self.lastMoveDirection = Vector3.zero
		self.jumpedThisAirtime = false
		local handled = false
		local handler = self.landingHandler
		if oldMode == "Air" and handler then
			handled = handler()
		end
		-- Buffered jump. If Space is still held, the Humanoid jumps on its own.
		if not handled and oldMode == "Air" and now <= self.jumpBufferUntil and not self.jumpHeld then
			self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		self.jumpBufferUntil = 0
	end
end

function CharacterMotor._stepGround(self: CharacterMotor, dt: number)
	local humanoid = self.humanoid
	self.groundRootY = self.root.Position.Y
	local moveDirection = humanoid.MoveDirection
	if self.character:GetAttribute("LanternCharging") == true then
		local camera = Workspace.CurrentCamera
		local camLook = if camera then camera.CFrame.LookVector else self.root.CFrame.LookVector
		local flatCam = Vector3.new(camLook.X, 0, camLook.Z)
		if flatCam.Magnitude > 1e-3 then
			flatCam = flatCam.Unit
			local fDot = moveDirection:Dot(flatCam)
			if fDot > 0 then
				moveDirection -= flatCam * fDot
			end
		end
	end

	if moveDirection.Magnitude < 0.01 then
		-- Standing still: stop crisply (fighting games need a reliable neutral).
		self.groundSpeed = 0
		self.lastMoveDirection = Vector3.zero
		humanoid.WalkSpeed = self:GetWalkSpeed()
		return
	end
	moveDirection = moveDirection.Unit

	local walk = self:GetWalkSpeed()
	local run = self:GetRunSpeed()
	local target = if self.sprinting then run else walk
	local speed = math.max(self.groundSpeed, walk)

	-- Sharp turns while running cost speed.
	if speed > walk and self.lastMoveDirection ~= Vector3.zero then
		if self.lastMoveDirection:Dot(moveDirection) < SHARP_TURN_COS then
			speed = walk + (speed - walk) * Config.SharpTurnKeep
		end
	end

	if speed < target then
		local rate = (run - walk) / math.max(Config.RunAccelTime, MIN_TIME)
		speed = math.min(speed + rate * dt, target)
	elseif speed > target then
		local rate
		if speed > run then
			rate = Config.MomentumDecay
		else
			rate = (run - walk) / math.max(Config.RunDecelTime, MIN_TIME)
		end
		speed = math.max(speed - rate * dt, target)
	end

	self.groundSpeed = speed
	self.lastMoveDirection = moveDirection
	humanoid.WalkSpeed = speed
end

-- Where the root sits when standing on the floor below (falls back to the current height).
function CharacterMotor._restHeight(self: CharacterMotor): number
	local root = self.root
	local result = Workspace:Raycast(root.Position, Vector3.new(0, -(self.standHeight + 1.5), 0), self.castParams)
	if result then
		return result.Position.Y + self.standHeight
	end
	return root.Position.Y
end

function CharacterMotor._stepAir(self: CharacterMotor, dt: number)
	local root = self.root
	local now = os.clock()
	local gravity = Workspace.Gravity
	local apexY = self.airRestY + Config.JumpHeight

	-- Exact jumps: the Humanoid's own jump varies with how its hip spring is compressed at
	-- takeoff. Replace its launch speed with the one that peaks exactly JumpHeight above
	-- where you were standing.
	if self.jumpVelocityPending then
		self.jumpVelocityPending = false
		local rise = apexY - root.Position.Y
		if rise > 0 then
			local current = root.AssemblyLinearVelocity
			-- Roblox steps physics at 240 Hz; that stepping loses about v * step / 2 of height
			-- versus the ideal formula, so solve for the speed that makes up for it.
			local half = gravity * PHYSICS_STEP / 2
			local speed = half + math.sqrt(half * half + 2 * gravity * rise)
			root.AssemblyLinearVelocity = Vector3.new(current.X, speed, current.Z)
		end
	end

	-- Nothing in basic movement takes you higher than a jump from where you took off.
	if os.clock() >= self.launchAllowedUntil and root.Position.Y > apexY + 0.2 then
		local current = root.AssemblyLinearVelocity
		if current.Y > 0 then
			root.AssemblyLinearVelocity = Vector3.new(current.X, 0, current.Z)
		end
	end

	local velocity = root.AssemblyLinearVelocity
	local actualFlat = flatten(velocity)

	-- If physics couldn't deliver what we asked for last frame, we hit something. The missing
	-- velocity points into the obstacle; remember that direction as a wall for a moment.
	local blocked = self.airHorizontal - actualFlat
	if blocked.Magnitude > 1 then
		self.wallNormal = -blocked.Unit
		self.wallUntil = now + WALL_MEMORY
		self.airHorizontal = actualFlat
		self.airSpeedCap = math.min(self.airSpeedCap, actualFlat.Magnitude)
	end

	-- Steering: you keep take-off speed but can't gain speed in the air.
	local moveDirection = self.humanoid.MoveDirection
	if self.character:GetAttribute("LanternCharging") == true then
		local camera = Workspace.CurrentCamera
		local camLook = if camera then camera.CFrame.LookVector else self.root.CFrame.LookVector
		local flatCam = Vector3.new(camLook.X, 0, camLook.Z)
		if flatCam.Magnitude > 1e-3 then
			flatCam = flatCam.Unit
			local fDot = moveDirection:Dot(flatCam)
			if fDot > 0 then
				moveDirection -= flatCam * fDot
			end
		end
	end
	if moveDirection.Magnitude > 0.01 then
		local maxSpeed = math.max(self.airSpeedCap, Config.AirMinSpeed * self:GetHealthSpeedScale())
		local wish = moveDirection.Unit * maxSpeed
		self.airHorizontal = moveTowards(self.airHorizontal, wish, Config.AirAcceleration * dt)
	else
		local speed = self.airHorizontal.Magnitude
		if speed > 0 then
			local newSpeed = math.max(speed - Config.AirDrag * dt, 0)
			self.airHorizontal *= newSpeed / speed
		end
	end

	-- Momentum above run speed (dash-jump, wall hop, roll, slide) bleeds off slowly in the air, so
	-- it carries through a jump but chaining hops can't keep it forever.
	local run = self:GetRunSpeed()
	if self.airSpeedCap > run then
		self.airSpeedCap = math.max(run, self.airSpeedCap - Config.AirMomentumDecay * dt)
		local speed = self.airHorizontal.Magnitude
		if speed > self.airSpeedCap then
			self.airHorizontal *= self.airSpeedCap / speed
		end
	end

	-- Never push into a wall: that's what pins you to it. Slide along it instead.
	self.airHorizontal = self:_removeWallPush(self.airHorizontal, dt)

	-- Speed lost mid-air (turning around, drag, walls) is gone for this airtime.
	self.airSpeedCap = math.min(self.airSpeedCap, math.max(self.airHorizontal.Magnitude, Config.AirMinSpeed * self:GetHealthSpeedScale()))
	self.airVelocity.PlaneVelocity = Vector2.new(self.airHorizontal.X, self.airHorizontal.Z)
	-- The Humanoid must not "walk" in the air: its walking includes an automatic step-up that
	-- lifts you onto ledges in front of you, even ones your jump can't reach. Our LinearVelocity
	-- does all the horizontal moving here.
	self.humanoid.WalkSpeed = 0

	-- Gravity: normal on the way up, ramping heavier on the way down.
	local multiplier = 1
	if velocity.Y < 0 then
		self.fallTime += dt
		local t = math.clamp(self.fallTime / math.max(Config.FallGravityRampTime, MIN_TIME), 0, 1)
		multiplier = 1 + (Config.FallGravityMax - 1) * t
	else
		self.fallTime = 0
		if Config.VariableJumpHeight and self.jumpedThisAirtime and not self.jumpHeld then
			multiplier = Config.JumpCutGravityMultiplier
		end
	end

	local mass = root.AssemblyMass
	local predictedY = velocity.Y - gravity * multiplier * dt
	if predictedY <= -Config.TerminalVelocity then
		-- At terminal velocity: pin the fall speed and cancel gravity so it can't overshoot.
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, -Config.TerminalVelocity, velocity.Z)
		self.gravityForce.Force = Vector3.new(0, gravity * mass, 0)
	else
		self.gravityForce.Force = Vector3.new(0, -(multiplier - 1) * gravity * mass, 0)
	end
end

function CharacterMotor._removeWallPush(self: CharacterMotor, horizontal: Vector3, dt: number): Vector3
	-- Wall we bumped into recently (from the velocity check above).
	if os.clock() <= self.wallUntil then
		horizontal = slideAlong(horizontal, self.wallNormal)
	end

	local speed = horizontal.Magnitude
	if speed < 0.1 then
		return horizontal
	end

	-- Look ahead with rays from inside the body (lower body, chest, head).
	local direction = horizontal / speed
	local reach = direction * (1.5 + speed * dt)
	local position = self.root.Position
	for _, height in self.wallRayHeights do
		local result = Workspace:Raycast(position + Vector3.new(0, height, 0), reach, self.castParams)
		if result and math.abs(result.Normal.Y) < WALL_MAX_NORMAL_Y then
			local normal = flatten(result.Normal)
			if normal.Magnitude > 1e-3 then
				horizontal = slideAlong(horizontal, normal.Unit)
			end
		end
	end
	return horizontal
end

-- TRUSSES / LADDERS -----------------------------------------------------------

-- Grabbing a truss is deliberate, like the rest of the parkour. The Humanoid may only start
-- climbing when your keys point into something climbable right in front of you, never while
-- another move owns the body (dash, wall run, vault / climb / slide, landing roll), and never
-- during the re-grab lock after jumping off one. Brushing past a truss, falling past one, or a
-- move that passes next to one doesn't grab it. Once on, you stay on until you jump off.
function CharacterMotor._updateClimbGate(self: CharacterMotor, state: Enum.HumanoidStateType)
	local allow
	-- selene: allow(if_same_then_else) -- order matters: the climbing check comes before the lock
	if self.suspended then
		allow = false
	elseif state == Enum.HumanoidStateType.Climbing then
		allow = true
	elseif self.climbLocked then
		allow = false
	else
		allow = self:_keysIntoWall()
	end
	self:_setClimbAllowed(allow)
end

-- Keys point into a wall-like surface (a truss, a ladder) within TrussGrabReach of the body.
function CharacterMotor._keysIntoWall(self: CharacterMotor): boolean
	local move = flatten(self.humanoid.MoveDirection)
	if move.Magnitude < 0.1 then
		return false
	end
	move = move.Unit
	local root = self.root
	local reach = root.Size.X / 2 + Config.TrussGrabReach
	for _, height in { 0, -1.5 } do
		local hit = Workspace:Raycast(root.Position + Vector3.new(0, height, 0), move * reach, self.castParams)
		if hit and math.abs(hit.Normal.Y) < WALL_MAX_NORMAL_Y then
			local normal = flatten(hit.Normal)
			if normal.Magnitude > 1e-3 and normal.Unit:Dot(move) < -TRUSS_FACING then
				return true
			end
		end
	end
	return false
end

function CharacterMotor._setClimbAllowed(self: CharacterMotor, allow: boolean)
	if self.climbAllowed == allow then
		return
	end
	self.climbAllowed = allow
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, allow)
end

-- CLEANUP --------------------------------------------------------------------

function CharacterMotor.Destroy(self: CharacterMotor)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if not self.climbAllowed then
		self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.airVelocity:Destroy()
	self.gravityForce:Destroy()
	self.attachment:Destroy()
	self.lowerCollider:Destroy()
	if activeMotors[self.character] == self then
		activeMotors[self.character] = nil
	end
end

return CharacterMotor
