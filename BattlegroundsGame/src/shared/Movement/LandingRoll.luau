--!strict
-- LandingRoll (ModuleScript)
-- Location: ReplicatedStorage > Movement > LandingRoll
--
-- JJS-style landing roll for one character (client side, next to CharacterMotor, Dash, WallHop).
--
--   Fall from higher than a jump, then press Space right before you land: instead of a normal
--   landing (or a jump) you roll forward. The roll adds distance that grows with the fall
--   height, and you keep the horizontal speed you landed with (it's still yours when the roll
--   ends). All numbers are in MovementConfig (LANDING ROLL).
--
--   Intentional input only:
--     * The press has to be a NEW press made in the air within LandingRollWindow before touching
--       down. Holding Space through the landing doesn't roll (that's a normal bunny hop), a press
--       made too early doesn't roll, and the press that made the jump never counts.
--     * Falls no higher than a jump never roll: pressing before landing there is a normal
--       buffered jump, as before.
--   Edge cases:
--     * The fall is measured from the highest point of the airtime (wall hops included) to where
--       you land, so landing on a higher platform shortens it.
--     * Rolling into a wall slides along it (never climbs or launches); rolling off a ledge ends
--       the roll in the air with the roll's speed.
--     * No jump during the roll. A fresh press in the last LandingRollJumpBuffer of the roll jumps
--       right as it ends (roll-jump); Space still held from the roll press doesn't auto-jump.
--     * Not while dashing or wall running; a dash can't start during a roll.
--   Direction: where you aim. The way your keys point (camera-relative) if you hold any, else
--   the way the camera looks. Your landing speed is redirected that way (turning past 45
--   degrees from your momentum costs some of it, see LandingRollTurnKeep).
--
-- Animation: plays "LandingRoll" if it exists (AnimationConfig.Ids or a Studio KeyframeSequence);
-- otherwise the normal movement animations show. Attribute "Rolling" is true during the roll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
local Perf = require(script.Parent.Perf)
local AnimConfig = require(script.Parent.AnimationConfig)
local CharacterMotor = require(script.Parent.CharacterMotor)
local AnimationLibrary = require(script.Parent.AnimationLibrary)

-- Surfaces steeper than this (normal.Y below it) count as walls.
local WALL_MAX_NORMAL_Y = 0.7
-- Fastest upward speed a roll allows (slopes, stairs).
local MAX_RISE = 10
-- Off the ground this long during a roll = rolled off a ledge.
local AIRBORNE_END = 0.08
-- Below this landing speed there is no momentum to carry into the roll.
local MIN_MOMENTUM_SPEED = 3

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

type Phase = "Idle" | "Rolling"

local LandingRoll = {}
LandingRoll.__index = LandingRoll

type LandingRollData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	isBlocked: () -> boolean,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	castParams: RaycastParams,
	wallRayHeights: { number },
	track: AnimationTrack?,
	connections: { RBXScriptConnection },
	destroyed: boolean,

	phase: Phase,
	apexY: number,
	airVelocity: Vector3,
	standOffset: number,
	armedAt: number,
	jumpLocked: boolean,
	holdLock: boolean,

	rollStart: number,
	direction: Vector3,
	keepSpeed: number,
	bonusSpeed: number,
	airborneFor: number,
	rollPressAt: number,
	lastApplied: Vector3,
	traveled: number,
	lastPosition: Vector3,

	totalRolls: number,
	lastFall: number,
	lastDistance: number,
	lastInfo: string,
}

export type LandingRoll = typeof(setmetatable({} :: LandingRollData, LandingRoll))

local active: { [Model]: LandingRoll } = {}

local function animationExists(name: string): boolean
	local id = AnimConfig.Ids[name]
	if id and id ~= "" then
		return true
	end
	if RunService:IsStudio() then
		local folder = ReplicatedStorage:FindFirstChild(AnimConfig.StudioAnimationsFolder)
		return folder ~= nil and folder:FindFirstChild(name) ~= nil
	end
	return false
end

-- `isBlocked` returns true while something else owns the character (a dash, a wall run).
function LandingRoll.new(character: Model, motor: CharacterMotor.CharacterMotor, isBlocked: () -> boolean): LandingRoll
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "RollAttachment"
	attachment.Parent = root

	-- Horizontal only; up/down stays with physics (slopes, ledges).
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "RollVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "RollFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true

	local track: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator and animationExists("LandingRoll") then
		local animation = AnimationLibrary.Get("LandingRoll")
		if animation then
			local loaded = animator:LoadAnimation(animation)
			loaded.Priority = Enum.AnimationPriority.Action
			loaded.Looped = false
			track = loaded
		end
	end

	local stepHeight = Config.LowerColliderGap + 0.2
	local wallRayHeights = { -(root.Size.Y / 2 + 2) + stepHeight, 0, root.Size.Y / 2 + 0.8 }

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		isBlocked = isBlocked,
		attachment = attachment,
		velocity = velocity,
		align = align,
		castParams = castParams,
		wallRayHeights = wallRayHeights,
		track = track,
		connections = {},
		destroyed = false,

		phase = "Idle" :: Phase,
		apexY = root.Position.Y,
		airVelocity = Vector3.zero,
		standOffset = 3,
		armedAt = -math.huge,
		jumpLocked = false,
		holdLock = false,

		rollStart = 0,
		direction = Vector3.zAxis,
		keepSpeed = 0,
		bonusSpeed = 0,
		airborneFor = 0,
		rollPressAt = -math.huge,
		lastApplied = Vector3.zero,
		traveled = 0,
		lastPosition = root.Position,

		totalRolls = 0,
		lastFall = 0,
		lastDistance = 0,
		lastInfo = "",
	}, LandingRoll)

	motor:SetLandingHandler(function(): boolean
		return self:_onLanded()
	end)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_step(dt)
				Perf.add("LandingRoll", os.clock() - t0)
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
	character:SetAttribute("Rolling", false)
	return self
end

function LandingRoll.Get(character: Model): LandingRoll?
	return active[character]
end

-- Call on every Space press. `madeJump` = this press made a jump (ground or coyote jump).
function LandingRoll.OnJumpPressed(self: LandingRoll, madeJump: boolean?)
	local now = os.clock()
	if self.phase == "Rolling" then
		self.rollPressAt = now
		return
	end
	if not madeJump and self.motor:GetMode() == "Air" then
		self.armedAt = now
	end
end

function LandingRoll.IsRolling(self: LandingRoll): boolean
	return self.phase == "Rolling"
end

-- Debug / tests.
function LandingRoll.GetTotalRolls(self: LandingRoll): number
	return self.totalRolls
end

function LandingRoll.GetLastFall(self: LandingRoll): number
	return self.lastFall
end

function LandingRoll.GetLastDistance(self: LandingRoll): number
	return self.lastDistance
end

-- What happened on the last landing ("rolled ...", or why it didn't roll).
function LandingRoll.GetLastInfo(self: LandingRoll): string
	return self.lastInfo
end

function LandingRoll._setJumpLock(self: LandingRoll, locked: boolean)
	if self.jumpLocked == locked then
		return
	end
	self.jumpLocked = locked
	self.motor:SetJumpLock("LandingRoll", locked)
end

-- Root height when standing on whatever is below (nil if nothing within range).
function LandingRoll._groundRootY(self: LandingRoll): number?
	local hit = Workspace:Raycast(self.root.Position, Vector3.new(0, -120, 0), self.castParams)
	if hit then
		return hit.Position.Y + self.standOffset
	end
	return nil
end

function LandingRoll._rollBonus(self: LandingRoll, fall: number): number
	return math.min(
		Config.LandingRollBaseDistance + (fall - Config.LandingRollMinFall) * Config.LandingRollDistancePerStud,
		Config.LandingRollMaxBonus
	)
end

function LandingRoll._step(self: LandingRoll, dt: number)
	if self.destroyed then
		return
	end
	if self.phase == "Rolling" then
		self:_stepRoll(dt)
		return
	end

	local mode = self.motor:GetMode()
	local position = self.root.Position
	local now = os.clock()

	if mode == "Ground" then
		self.apexY = position.Y
		local floor = Workspace:Raycast(position, Vector3.new(0, -6, 0), self.castParams)
		if floor then
			self.standOffset = position.Y - floor.Position.Y
		end
		self.armedAt = -math.huge
		-- Space still held from the roll press: no auto-jump until it's released.
		if self.holdLock and not self.motor:IsJumpHeld() then
			self.holdLock = false
		end
		if not self.holdLock then
			self:_setJumpLock(false)
		end
		return
	end

	-- In the air (or wall running / air dashing): track the highest point of this airtime.
	self.apexY = math.max(self.apexY, position.Y)
	if mode == "Air" then
		self.airVelocity = self.root.AssemblyLinearVelocity
		self.holdLock = false
	end

	-- Armed by a fresh press: stop the Humanoid from jumping on touchdown if this landing will
	-- be a roll (Space may still be held as the feet touch).
	local armed = now - self.armedAt <= Config.LandingRollWindow
	local lock = false
	if armed and mode == "Air" and self.root.AssemblyLinearVelocity.Y < 0 then
		local groundY = self:_groundRootY()
		lock = groundY ~= nil and self.apexY - groundY >= Config.LandingRollMinFall
	end
	self:_setJumpLock(lock or self.holdLock)
end

-- Called by the motor the moment you land from the air. True = rolling (skip the buffered jump).
function LandingRoll._onLanded(self: LandingRoll): boolean
	local now = os.clock()
	local fall = self.apexY - self.root.Position.Y
	self.lastFall = fall
	local sincePress = now - self.armedAt
	self.armedAt = -math.huge
	if self.destroyed or self.phase ~= "Idle" or self.isBlocked() or self.humanoid.Health <= 0 then
		self:_setJumpLock(false)
		return false
	end
	if fall < Config.LandingRollMinFall then
		if sincePress <= Config.LandingRollWindow then
			self.lastInfo = string.format("fall %.1f too short to roll (%.1f)", fall, Config.LandingRollMinFall)
		end
		self:_setJumpLock(false)
		return false
	end
	if sincePress > Config.LandingRollWindow then
		self.lastInfo = if sincePress < 1
			then string.format("pressed %.2fs early (window %.2fs)", sincePress, Config.LandingRollWindow)
			else string.format("no roll: fell %.1f, press Space right before landing", fall)
		self:_setJumpLock(false)
		return false
	end
	self:_startRoll(fall)
	return true
end

function LandingRoll._startRoll(self: LandingRoll, fall: number)
	local flat = flatten(self.airVelocity)
	-- Direction: where you aim. Keys (they're camera-relative) if you hold any, else where the
	-- camera looks. The landing speed is redirected that way; turning away from your momentum
	-- costs some of it (none up to 45 degrees, down to LandingRollTurnKeep for a full reverse).
	local direction: Vector3
	local move = flatten(self.humanoid.MoveDirection)
	if move.Magnitude > 0.1 then
		direction = move.Unit
	else
		local camera = Workspace.CurrentCamera
		local look = if camera then flatten(camera.CFrame.LookVector) else flatten(self.root.CFrame.LookVector)
		if look.Magnitude < 1e-3 then
			look = flatten(self.root.CFrame.LookVector)
		end
		direction = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis
	end
	local keep = 0
	if flat.Magnitude >= MIN_MOMENTUM_SPEED then
		local angle = math.deg(math.acos(math.clamp(flat.Unit:Dot(direction), -1, 1)))
		local share = if angle <= 45 then 1 else 1 - (1 - Config.LandingRollTurnKeep) * (angle - 45) / 135
		keep = flat.Magnitude * share
	end
	local bonus = self:_rollBonus(fall)
	local duration = Config.LandingRollTime

	self.phase = "Rolling"
	self.rollStart = os.clock()
	self.direction = direction
	self.keepSpeed = keep
	-- Extra speed falls in a straight line to 0 over the roll, adding exactly `bonus` studs.
	self.bonusSpeed = 2 * bonus / duration
	self.airborneFor = 0
	self.rollPressAt = -math.huge
	self.traveled = 0
	self.lastPosition = self.root.Position
	self.totalRolls += 1
	self.lastInfo = string.format("rolled: fall %.1f, +%.1f studs, kept %.1f speed", fall, bonus, keep)

	self:_setJumpLock(true)
	self.motor:Suspend()
	self.humanoid.AutoRotate = false
	self.align.CFrame = CFrame.lookAlong(Vector3.zero, direction)
	self.align.Enabled = true
	self:_applySpeed(keep + self.bonusSpeed, 1 / 60)
	self.velocity.Enabled = true
	self.character:SetAttribute("Rolling", true)

	local track = self.track
	if track then
		track:Play(0, 1, track.Length > 0 and track.Length / duration or 1)
	end
end

-- Never push into a wall or the side of an obstacle: the velocity slides along it instead.
function LandingRoll._slideAlongWalls(self: LandingRoll, velocity: Vector3, dt: number): Vector3
	local position = self.root.Position
	for _ = 1, 2 do
		local speed = velocity.Magnitude
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

function LandingRoll._applySpeed(self: LandingRoll, speed: number, dt: number)
	local flat = self:_slideAlongWalls(self.direction * speed, dt)
	self.lastApplied = flat
	self.velocity.PlaneVelocity = Vector2.new(flat.X, flat.Z)
end

function LandingRoll._stepRoll(self: LandingRoll, dt: number)
	local position = self.root.Position
	self.traveled += flatten(position - self.lastPosition).Magnitude
	self.lastPosition = position

	local elapsed = os.clock() - self.rollStart
	local duration = Config.LandingRollTime
	if self.humanoid.Health <= 0 or elapsed >= duration then
		self:_finish(true)
		return
	end
	-- Rolled off a ledge: end the roll and fall with its speed.
	if self.humanoid.FloorMaterial == Enum.Material.Air then
		self.airborneFor += dt
		if self.airborneFor >= AIRBORNE_END then
			self:_finish(false)
			return
		end
	else
		self.airborneFor = 0
	end

	local t = math.min((elapsed + dt / 2) / duration, 1)
	self:_applySpeed(self.keepSpeed + self.bonusSpeed * (1 - t), dt)
	local velocity = self.root.AssemblyLinearVelocity
	if velocity.Y > MAX_RISE then
		self.root.AssemblyLinearVelocity = Vector3.new(velocity.X, MAX_RISE, velocity.Z)
	end
end

function LandingRoll._finish(self: LandingRoll, onGround: boolean)
	if self.phase ~= "Rolling" then
		return
	end
	self.phase = "Idle"
	self.lastDistance = self.traveled
	self.velocity.Enabled = false
	self.align.Enabled = false
	self.humanoid.AutoRotate = true
	self.character:SetAttribute("Rolling", false)
	local track = self.track
	if track and track.IsPlaying and onGround then
		track:Stop(0)
	end

	-- Momentum: carry the speed the roll ends with (the landing speed, or less after a wall).
	local carry = if onGround then self.direction * self.keepSpeed else self.lastApplied
	carry = self:_slideAlongWalls(carry, 1 / 60)
	local velocity = self.root.AssemblyLinearVelocity
	self.root.AssemblyLinearVelocity = Vector3.new(carry.X, velocity.Y, carry.Z)
	self.motor:ApplyMomentum(carry)
	self.motor:Resume()
	self.apexY = self.root.Position.Y

	if not onGround then
		self.holdLock = false
		self:_setJumpLock(false)
		return
	end
	local rollJump = os.clock() - self.rollPressAt <= Config.LandingRollJumpBuffer
	if rollJump then
		self.holdLock = false
		self:_setJumpLock(false)
		self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	elseif self.motor:IsJumpHeld() then
		-- Still holding the roll press: stay on the ground until Space is released.
		self.holdLock = true
	else
		self.holdLock = false
		self:_setJumpLock(false)
	end
end

-- M1 late in a roll (from RollAttackCancelTime on): the roll ends keeping its speed and the attack
-- takes over. Returns whether it did.
function LandingRoll.CancelIntoAttack(self: LandingRoll): boolean
	if self.phase ~= "Rolling" or os.clock() - self.rollStart < Config.RollAttackCancelTime then
		return false
	end
	self:Cancel()
	return true
end

-- Ends a roll early without the roll-jump (e.g. getting hit, once combat exists).
function LandingRoll.Cancel(self: LandingRoll)
	if self.phase ~= "Rolling" then
		return
	end
	self.rollPressAt = -math.huge
	self:_finish(self.humanoid.FloorMaterial ~= Enum.Material.Air)
end

function LandingRoll.Destroy(self: LandingRoll)
	if self.destroyed then
		return
	end
	self:Cancel()
	self.destroyed = true
	self.motor:SetLandingHandler(nil)
	self:_setJumpLock(false)
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

return LandingRoll
