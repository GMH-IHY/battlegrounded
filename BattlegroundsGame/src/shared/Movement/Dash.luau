--!strict
-- Dash (ModuleScript)
-- Location: ReplicatedStorage > Movement > Dash
--
-- Shift dash for one character. Runs on the client, next to CharacterMotor (the player owns
-- their character's physics). All numbers are in MovementConfig.
--
--   Front dash (no keys, or W): long slide toward where the camera looks. M1 at any point
--     during it throws the dash punch: the slide carries on while you wind up the jab, then
--     you're stuck in heavy endlag. Hits early in the dash ragdoll instead of stun.
--   Quick-step (A, D, S or a diagonal): short slide in the held direction; the body keeps
--     facing the camera and plays the side / back animation.
--   Both follow the camera while they travel, so turning curves the dash.
--
-- While a dash runs, CharacterMotor is suspended; when it ends, the motor picks up the
-- dash's speed (momentum carries). Combat doesn't exist yet: a punch that connects is sent to
-- the server (DashPunchServer), which checks it and shows a hit report on the target.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
local Perf = require(script.Parent.Perf)
local CharacterMotor = require(script.Parent.CharacterMotor)
local AnimationLibrary = require(script.Parent.AnimationLibrary)
local Sfx = require(script.Parent.Sfx)

export type Kind = "Front" | "Left" | "Right" | "Back"
type Phase = "Idle" | "Dashing" | "Punch"

-- Dash direction rules (Isaac, Sep 26). A dash only ever goes in ONE of four directions:
--   W held (W, W+A, W+D)          -> front dash, straight forward
--   S held (S, S+A, S+D)          -> back dash, straight back
--   only A or only D              -> side dash, straight left / right
--   nothing, A+D, W+S             -> front dash (standing still)
-- A key counts as held when the move input has at least this much of it (0..1).
local AXIS_THRESHOLD = 0.3
-- Fastest upward speed a ground dash allows (slopes, stairs). Anything faster is an obstacle
-- trying to launch you.
local GROUND_MAX_RISE = 10
-- Surfaces steeper than this (normal.Y below it) count as walls.
local WALL_MAX_NORMAL_Y = 0.7
-- How hard the dash corrects toward its planned distance (studs/s of extra speed, at most).
local MAX_CORRECTION = 12

local TRACK_NAMES: { [string]: string } = {
	Front = "DashForward",
	Left = "DashLeft",
	Right = "DashRight",
	Back = "DashBack",
	Punch = "DashPunch",
}

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Rotates a flat vector about the up axis by `angle` radians (+ = left / counter-clockwise
-- seen from above).
local function yawRotate(v: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(v)
end

local Dash = {}
Dash.__index = Dash

type DashData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	tracks: { [string]: AnimationTrack },
	overlapParams: OverlapParams,
	castParams: RaycastParams,
	wallRayHeights: { number },
	maxRise: number,
	connections: { RBXScriptConnection },
	forwardHeld: () -> boolean,
	destroyed: boolean,

	phase: Phase,
	kind: Kind,
	startTime: number,
	duration: number,
	startSpeed: number,
	endSpeed: number,
	-- Direction of travel relative to the camera's forward (radians, + = left).
	relativeYaw: number,
	-- Set when Request was given an explicit forward (tests): the dash ignores the camera.
	fixedForward: Vector3?,
	distance: number,
	-- Where the body faces relative to the camera's forward.
	facingYaw: number,
	traveled: number,
	lastPosition: Vector3,
	lastDashTime: number,
	airDashesUsed: number,
	lastDistance: number,
	jumpPressAt: number,
	groundedAt: number,
	lastEndReason: string,

	punchStart: number,
	punchSpeed: number,
	punchHit: boolean,
	punchResult: string,
}

export type Dash = typeof(setmetatable({} :: DashData, Dash))

local active: { [Model]: Dash } = {}

-- `forwardHeld` tells the dash whether W is down (for starting a run as the dash ends).
function Dash.new(character: Model, motor: CharacterMotor.CharacterMotor, forwardHeld: () -> boolean): Dash
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root

	-- Horizontal velocity only; up/down stays with physics (gravity, slopes, ledges).
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	-- Holds the body's facing during a dash (the Humanoid's AutoRotate is off meanwhile).
	local align = Instance.new("AlignOrientation")
	align.Name = "DashFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local tracks: { [string]: AnimationTrack } = {}
	for key, name in TRACK_NAMES do
		local animation = AnimationLibrary.Get(name)
		if animation and animator then
			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			tracks[key] = track
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true
	-- Heights (relative to the root) of the rays that look for walls ahead: just above the
	-- step-over height, chest, head. Same idea as CharacterMotor's air wall check.
	local stepHeight = Config.LowerColliderGap + 0.2
	local wallRayHeights = { -(root.Size.Y / 2 + 2) + stepHeight, 0, root.Size.Y / 2 + 0.8 }

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		attachment = attachment,
		velocity = velocity,
		align = align,
		tracks = tracks,
		overlapParams = overlapParams,
		castParams = castParams,
		wallRayHeights = wallRayHeights,
		maxRise = 0,
		connections = {},
		forwardHeld = forwardHeld,
		destroyed = false,

		phase = "Idle" :: Phase,
		kind = "Front" :: Kind,
		startTime = 0,
		duration = 0,
		startSpeed = 0,
		endSpeed = 0,
		relativeYaw = 0,
		fixedForward = nil,
		distance = 0,
		facingYaw = 0,
		traveled = 0,
		lastPosition = root.Position,
		lastDashTime = -math.huge,
		airDashesUsed = 0,
		lastDistance = 0,
		jumpPressAt = -math.huge,
		groundedAt = -math.huge,
		lastEndReason = "",

		punchStart = 0,
		punchSpeed = 0,
		punchHit = false,
		punchResult = "",
	}, Dash)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_step(dt)
				Perf.add("Dash", os.clock() - t0)
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

	active[character] = self
	character:SetAttribute("Dashing", false)
	return self
end

function Dash.Get(character: Model): Dash?
	return active[character]
end

-- INFO (debug overlay, tests) ------------------------------------------------------

function Dash.GetCooldownRemaining(self: Dash): number
	return math.max(0, Config.DashCooldown - (os.clock() - self.lastDashTime))
end

function Dash.IsBusy(self: Dash): boolean
	return self.phase ~= "Idle"
end

function Dash.GetPhase(self: Dash): string
	return self.phase
end

function Dash.GetKind(self: Dash): Kind
	return self.kind
end

-- Distance covered by the last finished dash (including a punch lunge).
function Dash.GetLastDistance(self: Dash): number
	return self.lastDistance
end

-- "" until a punch has resolved; then "miss", "stun" or "ragdoll".
function Dash.GetLastPunchResult(self: Dash): string
	return self.punchResult
end

-- ACTIONS ------------------------------------------------------------------------

local function cameraForward(root: BasePart): Vector3
	local camera = Workspace.CurrentCamera
	local look = if camera then flatten(camera.CFrame.LookVector) else Vector3.zero
	if look.Magnitude < 1e-3 then
		look = flatten(root.CFrame.LookVector)
	end
	return if look.Magnitude < 1e-3 then -Vector3.zAxis else look.Unit
end

-- Starts a dash. `moveDirection` defaults to the Humanoid's (the keys held, already turned
-- into world space by the camera). `forward` defaults to the camera's flat look direction and
-- then follows the camera while dashing; passing one fixes the direction (used by tests).
-- Returns whether a dash started.
function Dash.Request(self: Dash, moveDirection: Vector3?, forward: Vector3?): boolean
	if self.destroyed or self.phase ~= "Idle" then
		return false
	end
	local now = os.clock()
	if now - self.lastDashTime < Config.DashCooldown then
		return false
	end
	if self.humanoid.Health <= 0 then
		return false
	end
	-- Another movement owns the body (landing roll, wall run), even on its very first frame.
	if
		self.character:GetAttribute("Rolling") == true
		or self.character:GetAttribute("WallRunning") == true
		or self.character:GetAttribute("Parkour") ~= nil
		or self.character:GetAttribute("Flying") ~= nil
	then
		return false
	end
	local mode = self.motor:GetMode()
	if mode == "Passive" or mode == "Suspended" then
		return false
	end
	if mode == "Air" and self.airDashesUsed >= Config.AirDashes then
		return false
	end
	-- An attack's wind-up and hit can't be dashed out of (its recovery can).
	local attackPhase = self.character:GetAttribute("AttackPhase")
	if attackPhase == "Startup" or attackPhase == "Active" then
		return false
	end

	local camForward = forward or cameraForward(self.root)
	camForward = flatten(camForward)
	camForward = if camForward.Magnitude > 1e-3 then camForward.Unit else -Vector3.zAxis
	local move = flatten(moveDirection or self.humanoid.MoveDirection)

	-- Split the held input into forward/back and left/right parts relative to the camera.
	local camRight = Vector3.new(-camForward.Z, 0, camForward.X)
	local forwardAmount = move:Dot(camForward)
	local rightAmount = move:Dot(camRight)
	local kind: Kind = "Front"
	local relativeYaw = 0
	if forwardAmount > AXIS_THRESHOLD then
		kind = "Front"
	elseif forwardAmount < -AXIS_THRESHOLD then
		kind, relativeYaw = "Back", math.pi
	elseif rightAmount > AXIS_THRESHOLD then
		kind, relativeYaw = "Right", -math.pi / 2
	elseif rightAmount < -AXIS_THRESHOLD then
		kind, relativeYaw = "Left", math.pi / 2
	end
	local holding = move.Magnitude > 0.1

	local distance, duration, endSpeed
	if kind == "Front" then
		distance, duration = Config.FrontDashDistance, Config.FrontDashTime
		endSpeed = if not holding
			then 0
			elseif self.motor:IsSprinting() or self.forwardHeld() then Config.DashEndSpeedRunning * self.motor:GetHealthSpeedScale()
			else Config.DashEndSpeedWalking * self.motor:GetHealthSpeedScale()
	else
		distance, duration = Config.SideDashDistance, Config.SideDashTime
		endSpeed = if holding then Config.DashEndSpeedWalking * self.motor:GetHealthSpeedScale() else 0
	end
	-- Speed falls in a straight line from startSpeed to endSpeed, covering exactly `distance`.
	local startSpeed = math.max(2 * distance / duration - endSpeed, endSpeed)

	self.phase = "Dashing"
	self.kind = kind
	self.startTime = now
	self.duration = duration
	self.startSpeed = startSpeed
	self.endSpeed = endSpeed
	self.relativeYaw = relativeYaw
	self.fixedForward = if forward then camForward else nil
	self.distance = distance
	-- Front dash faces where it goes; quick-steps keep facing the camera.
	self.facingYaw = if kind == "Front" then relativeYaw else 0
	self.traveled = 0
	self.lastPosition = self.root.Position
	self.lastDashTime = now
	self.jumpPressAt = -math.huge
	self.groundedAt = if self:_onGround() then now else -math.huge
	self.punchResult = ""
	if mode == "Air" then
		self.airDashesUsed += 1
	end
	-- A dash never sends you upward: on the ground only enough rise for slopes and stairs, in
	-- the air no more than you were already rising.
	self.maxRise = if mode == "Air" then math.max(self.root.AssemblyLinearVelocity.Y, 0) else GROUND_MAX_RISE

	self.motor:Suspend()
	self.humanoid.AutoRotate = false
	self:_applyMotion(camForward, startSpeed, 1 / 60)
	self.velocity.Enabled = true
	self.align.Enabled = true

	self.character:SetAttribute("Dashing", true)
	self.character:SetAttribute("DashKind", kind)
	self.character:SetAttribute("IFramesUntil", Workspace:GetServerTimeNow() + Config.DashIFrames)

	self:_playOnly(kind)
	return true
end

-- M1. Only does something during a front dash. Returns whether the punch started.
function Dash.Punch(self: Dash): boolean
	if self.phase ~= "Dashing" or self.kind ~= "Front" then
		return false
	end
	local now = os.clock()
	local t = math.clamp((now - self.startTime) / self.duration, 0, 1)
	local current = self.startSpeed + (self.endSpeed - self.startSpeed) * t
	-- Slowing to a stop over the wind-up covers speed * windup / 2; make sure it lunges at least
	-- DashPunchMinLunge.
	local minSpeed = 2 * Config.DashPunchMinLunge / math.max(Config.DashPunchWindup, 1e-3)
	self.phase = "Punch"
	self.punchStart = now
	self.punchSpeed = math.max(current, minSpeed)
	self.punchHit = false
	self.character:SetAttribute("DashKind", "Punch")
	self:_playOnly("Punch")
	return true
end

-- SIMULATION ---------------------------------------------------------------------

function Dash._playOnly(self: Dash, key: string)
	for name, track in self.tracks do
		if name ~= key and track.IsPlaying then
			track:Stop(0)
		end
	end
	local track = self.tracks[key]
	if track then
		track:Play(0, 1, 1)
	end
end

function Dash._forward(self: Dash): Vector3
	return self.fixedForward or cameraForward(self.root)
end

-- Points the dash velocity and the body facing, using the camera's current forward.
function Dash._applyMotion(self: Dash, camForward: Vector3, speed: number, dt: number)
	local direction = yawRotate(camForward, self.relativeYaw)
	local flat = self:_slideAlongWalls(direction * speed, dt)
	self.velocity.PlaneVelocity = Vector2.new(flat.X, flat.Z)
	local facing = yawRotate(camForward, self.facingYaw)
	self.align.CFrame = CFrame.lookAlong(Vector3.zero, facing)
end

-- Never push into a wall or the side of an obstacle: that's what flings you up and over it.
-- The velocity slides along the surface instead (or stops, head-on).
function Dash._slideAlongWalls(self: Dash, velocity: Vector3, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.1 then
		return velocity
	end
	local position = self.root.Position
	for _ = 1, 2 do -- twice, for corners
		speed = velocity.Magnitude
		if speed < 0.1 then
			break
		end
		local reach = velocity / speed * (1.6 + speed * dt)
		for _, height in self.wallRayHeights do
			local result = Workspace:Raycast(position + Vector3.new(0, height, 0), reach, self.castParams)
			if result and math.abs(result.Normal.Y) < WALL_MAX_NORMAL_Y then
				local normal = flatten(result.Normal)
				if normal.Magnitude > 1e-3 then
					normal = normal.Unit
					local into = velocity:Dot(normal)
					if into < 0 then
						velocity -= normal * into
					end
				end
			end
		end
	end
	return velocity
end

function Dash._limitRise(self: Dash)
	local velocity = self.root.AssemblyLinearVelocity
	if velocity.Y > self.maxRise then
		self.root.AssemblyLinearVelocity = Vector3.new(velocity.X, self.maxRise, velocity.Z)
	end
end

function Dash._step(self: Dash, dt: number)
	if self.destroyed then
		return
	end
	if self.phase == "Idle" then
		if self.motor:GetMode() == "Ground" then
			self.airDashesUsed = 0
		end
		return
	end

	local now = os.clock()
	local position = self.root.Position
	self.traveled += flatten(position - self.lastPosition).Magnitude
	self.lastPosition = position

	if self.phase == "Dashing" then
		local elapsed = now - self.startTime
		if self:_onGround() then
			self.groundedAt = now
		end
		-- A dash-jump pressed when it couldn't fire yet (too early, or mid air dash) fires the
		-- moment it can.
		if self.jumpPressAt >= self.startTime and self:_canDashJump(now) then
			self:_jumpCancel()
			return
		end
		local remaining = self.distance - self.traveled
		-- Done when the distance is covered, or (blocked by a wall) a little after the time is up.
		if remaining <= 0.05 or elapsed >= self.duration + 0.1 then
			self:_finish()
			return
		end
		-- Planned speed for the coming step, plus a small correction toward the planned distance
		-- (so every dash comes out exactly as long as configured). The correction is capped: when a
		-- wall stops you, the dash must not keep shoving harder and harder into it.
		local tMid = math.min((elapsed + dt / 2) / self.duration, 1)
		local planSpeed = self.startSpeed + (self.endSpeed - self.startSpeed) * tMid
		local t1 = math.min((elapsed + dt) / self.duration, 1)
		local planned = self.duration * (self.startSpeed * t1 + (self.endSpeed - self.startSpeed) * t1 * t1 / 2)
		local correction = math.clamp((planned - self.traveled) / math.max(dt, 1e-3) - planSpeed, -MAX_CORRECTION, MAX_CORRECTION)
		local speed = math.max(planSpeed + correction, 0)
		if t1 >= 1 then
			speed = math.max(speed, math.min(remaining / math.max(dt, 1e-3), self.endSpeed + MAX_CORRECTION))
		end
		self:_applyMotion(self:_forward(), speed, dt)
		self:_limitRise()
	elseif self.phase == "Punch" then
		local elapsed = now - self.punchStart
		local windup = Config.DashPunchWindup
		local activeEnd = windup + Config.DashPunchActive
		if elapsed < windup then
			local t = math.clamp((elapsed + dt / 2) / windup, 0, 1)
			self:_applyMotion(self:_forward(), self.punchSpeed * (1 - t), dt)
			self:_limitRise()
		else
			-- Planted: no more sliding, and turning the camera no longer turns you.
			self.velocity.PlaneVelocity = Vector2.zero
			self:_limitRise()
			if elapsed < activeEnd then
				if not self.punchHit then
					self:_checkHit()
				end
			else
				if self.punchResult == "" then
					self.punchResult = "miss"
				end
				local endlag = Config.DashPunchEndlag
				if elapsed >= activeEnd + endlag then
					self:_finish()
				end
			end
		end
	end
end

function Dash._checkHit(self: Dash)
	local size: Vector3 = Config.DashPunchHitbox
	local box = self.root.CFrame * CFrame.new(0, 0, -(size.Z / 2 + 0.5))
	local parts = Workspace:GetPartBoundsInBox(box, size, self.overlapParams)
	local best: Model? = nil
	local bestDistance = math.huge
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		local targetHumanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		if model and targetHumanoid and targetHumanoid.Health > 0 and model ~= self.character then
			local distance = (part.Position - self.root.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				best = model
			end
		end
	end
	if not best then
		return
	end
	self.punchHit = true
	Sfx.PlayAny(self.character, { "DashPunchHit", "DashPunchHit2" })
	local ragdoll = self.traveled < Config.FrontDashDistance * Config.DashPunchRagdollShare
	self.punchResult = if ragdoll then "ragdoll" else "stun"

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("DashPunch")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(best, ragdoll)
	end
end

-- Space during a dash (not the punch, whose endlag is the commitment) is a DASH-JUMP at any
-- point: the dash ends right away and you jump with its current speed. Off the ground it still
-- works within DashJumpCoyote of the dash touching the ground; in a pure air dash the press is
-- kept and jumps the moment the dash touches down (or on landing, if it was near the end).
function Dash.OnJumpPressed(self: Dash)
	if self.phase ~= "Dashing" then
		return
	end
	local now = os.clock()
	self.jumpPressAt = now
	if self:_canDashJump(now) then
		self:_jumpCancel()
	end
end

function Dash._onGround(self: Dash): boolean
	return self.humanoid.FloorMaterial ~= Enum.Material.Air
end

-- On the ground (or just left it during this dash), and past DashJumpMinTime.
function Dash._canDashJump(self: Dash, now: number): boolean
	if now - self.startTime < Config.DashJumpMinTime then
		return false
	end
	return self:_onGround() or now - self.groundedAt <= Config.DashJumpCoyote
end

-- The dash's velocity right now (flat). Zero when not dashing.
function Dash.GetCurrentVelocity(self: Dash): Vector3
	if self.phase ~= "Dashing" then
		return Vector3.zero
	end
	local v = self.velocity.PlaneVelocity
	return Vector3.new(v.X, 0, v.Y)
end

-- A front dash in progress (the one parkour can take over).
function Dash.IsFrontDashing(self: Dash): boolean
	return self.phase == "Dashing" and self.kind == "Front"
end

-- Why the last dash ended: "done", "jump" (dash-jump), "move" (handed to parkour), "attack"
-- (cancelled into an attack), "cancel".
function Dash.GetLastEndReason(self: Dash): string
	return self.lastEndReason
end

-- Ends the dash keeping its current speed, for another move to take over (parkour).
function Dash.HandOff(self: Dash)
	if self.phase ~= "Dashing" then
		return
	end
	local carry = self:GetCurrentVelocity()
	local cap = Config.MomentumMaxSpeed * self.motor:GetHealthSpeedScale()
	if carry.Magnitude > cap then
		carry = carry.Unit * cap
	end
	self.jumpPressAt = -math.huge
	self:_finish(carry)
	self.lastEndReason = "move"
end

function Dash._jumpCancel(self: Dash)
	local carry = self:GetCurrentVelocity()
	local cap = Config.MomentumMaxSpeed * self.motor:GetHealthSpeedScale()
	if carry.Magnitude > cap then
		carry = carry.Unit * cap
	end
	self.jumpPressAt = -math.huge
	self:_finish(carry)
	self.lastEndReason = "jump"
	self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

-- `keep`: hand this velocity to the motor instead of the dash's end speed (dash-jump, hand-off).
function Dash._finish(self: Dash, keep: Vector3?)
	if self.phase == "Idle" then
		return
	end
	self.lastEndReason = "done"
	self.lastDistance = self.traveled
	local wasDashing = self.phase == "Dashing"
	if wasDashing and os.clock() - self.jumpPressAt <= Config.MoveJumpBuffer then
		self.motor:BufferJump(Config.MoveJumpLandWindow)
	end
	self.phase = "Idle"
	self.velocity.Enabled = false
	self.align.Enabled = false
	self.humanoid.AutoRotate = true
	self.character:SetAttribute("Dashing", false)
	self.character:SetAttribute("DashKind", nil)

	-- Hand the speed back to the motor so it carries on: the dash's end speed, in the direction
	-- it was going (a punch ends planted).
	local carry = if keep then keep
		elseif wasDashing then yawRotate(self:_forward(), self.relativeYaw) * self.endSpeed
		else Vector3.zero
	self.root.AssemblyLinearVelocity = Vector3.new(carry.X, self.root.AssemblyLinearVelocity.Y, carry.Z)
	self.motor:ApplyMomentum(carry)
	self.motor:Resume()
	if Config.RunAfterDash and self.forwardHeld() then
		self.motor:SetSprinting(true)
	end
end

-- M1 during a side or back dash: the dash ends right now, handing its current speed to the motor
-- (you slide into the swing), and the attack takes over. Returns whether it did. A front dash's M1
-- is the dash punch instead (Punch), and the punch itself can't be cancelled.
function Dash.CancelIntoAttack(self: Dash): boolean
	if self.phase ~= "Dashing" or self.kind == "Front" then
		return false
	end
	local carry = self:GetCurrentVelocity()
	local cap = Config.MomentumMaxSpeed * self.motor:GetHealthSpeedScale()
	if carry.Magnitude > cap then
		carry = carry.Unit * cap
	end
	for _, track in self.tracks do
		track:Stop(0)
	end
	self.jumpPressAt = -math.huge
	self:_finish(carry)
	self.lastEndReason = "attack"
	return true
end

-- Ends a dash early (e.g. getting hit, once combat exists).
function Dash.Cancel(self: Dash)
	for _, track in self.tracks do
		track:Stop(0)
	end
	self:_finish()
	self.lastEndReason = "cancel"
end

function Dash.Destroy(self: Dash)
	if self.destroyed then
		return
	end
	if self.phase ~= "Idle" then
		self:_finish()
	end
	self.destroyed = true
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.velocity:Destroy()
	self.align:Destroy()
	self.attachment:Destroy()
	if active[self.character] == self then
		active[self.character] = nil
	end
end

return Dash
