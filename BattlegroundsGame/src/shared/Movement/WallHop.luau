--!strict
-- WallHop (ModuleScript)
-- Location: ReplicatedStorage > Movement > WallHop
--
-- JJS-style wall hopping for one character (client side, next to CharacterMotor and Dash).
--
--   Start: in the air with Space held (or pressed a moment ago) and your input pointing INTO a
--          wall AND ALONG it at the same time (W+D / W+A toward a wall, the JJS input). Running
--          parallel to a wall or straight into it does NOT hop: parkour must be intentional.
--          v3 edge cases (Isaac, Sep 26):
--            * The run ALWAYS goes the way your input points along the wall, never from your
--              momentum or the camera, so you can't hop the opposite way you're going.
--            * The wall must continue ahead of you (no hop that instantly runs off a corner or the
--              wall's end), there must be headroom (no hop under a ceiling), and other characters
--              don't count as walls.
--            * With two walls in reach (alley, inner corner), the one your input points into most
--              is used.
--            * Turning your input to point the other way along the wall mid-run kicks you off
--              immediately (you change direction instead of being carried the old way).
--          v4 (Isaac, Sep 26):
--            * Just jumping into a wall does NOT hop. After leaving the ground you either keep
--              HOLDING Space from the jump, or PRESS Space again in the air. The press that made
--              the jump doesn't count.
--            * A press slightly before reaching the wall (0.25 s) or slightly after leaving it
--              (0.12 s, "wall coyote time") still hops.
--            * Kick strength follows your keys when you leave the wall: still pointing into it
--              = small push (climb the same wall); along it = medium; pointing AWAY (toward the
--              other wall of an alley) = big push across, so zig-zagging reaches the other side.
--              Pointing away mid-run kicks you off right then; pointing away within
--              WallHopLateLeap after the kick still upgrades it to the big push.
--            * The run keeps your speed along the wall if you arrive faster than the run speed.
--          v5 (Isaac, Sep 26): the KEYS must be a forward key plus a side key (W+D / W+A),
--            checked relative to the camera. Before, only the world direction was checked, so W
--            alone at an angle to a wall counted as "into and along" and hopped.
--            * "Holding" means held longer than a tap (WallHopHoldTime), so a quick jump while
--              standing right next to a wall doesn't hop either. A press just before landing is a
--              buffered jump, not a hop press; a coyote jump press isn't one either.
--   Run:   you run along the wall and upward for WallRunTime (the wall holds you up).
--   Kick:  you jump off, away from the wall, carrying your speed along it. Holding Space and
--          steering back into a wall chains another hop.
--   Hops per airtime depend on health (MovementConfig: 3 / 2 / 1). Landing refills them.
--   Characters at least WallHopScaleFrom times normal size hop proportionally faster/farther.
--
-- Animations: plays "WallRunRight" / "WallRunLeft" while running and "WallHopRight" /
-- "WallHopLeft" on the kick, by which side the wall is on (Right = wall on your right). If a sided
-- one doesn't exist it falls back to "WallRun" / "WallHop", and without those the normal jump/fall
-- animations show. Each loads only if it exists (AnimationConfig.Ids or a Studio KeyframeSequence).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
local Perf = require(script.Parent.Perf)
local AnimConfig = require(script.Parent.AnimationConfig)
local CharacterMotor = require(script.Parent.CharacterMotor)
local AnimationLibrary = require(script.Parent.AnimationLibrary)
local Sfx = require(script.Parent.Sfx)

-- Surfaces with |normal.Y| below this count as walls.
local WALL_MAX_NORMAL_Y = 0.3

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

type Phase = "Idle" | "Running"
type Candidate = { hit: RaycastResult, normal: Vector3, into: number, along: Vector3 }

local WallHop = {}
WallHop.__index = WallHop

type WallHopData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	isBlocked: () -> boolean,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	castParams: RaycastParams,
	tracks: { [string]: AnimationTrack },
	connections: { RBXScriptConnection },
	destroyed: boolean,
	scale: number,

	phase: Phase,
	runStart: number,
	wallNormal: Vector3,
	runDirection: Vector3,
	runSpeed: number,
	hopsUsed: number,
	lastKick: number,
	kickNormal: Vector3,
	kickPush: number,
	lateLeapOpen: boolean,
	lastWall: Instance?,
	lastPress: number,
	holdStart: number,
	recent: Candidate?,
	recentAt: number,
	totalHops: number,
	wallSide: string,
	runTrack: AnimationTrack?,
	lastFailure: string,
}

export type WallHop = typeof(setmetatable({} :: WallHopData, WallHop))

local active: { [Model]: WallHop } = {}

-- Only loads animations that actually exist, so a missing one doesn't spam warnings.
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

-- `isBlocked` returns true while something else owns the character (a dash, an attack).
function WallHop.new(character: Model, motor: CharacterMotor.CharacterMotor, isBlocked: () -> boolean): WallHop
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "WallHopAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "WallRunVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "WallRunFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true

	local tracks: { [string]: AnimationTrack } = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, name in { "WallRun", "WallHop", "WallRunRight", "WallRunLeft", "WallHopRight", "WallHopLeft" } do
			if animationExists(name) then
				local animation = AnimationLibrary.Get(name)
				if animation then
					local track = animator:LoadAnimation(animation)
					track.Priority = Enum.AnimationPriority.Action
					tracks[name] = track
				end
			end
		end
	end

	-- Size relative to a normal R6 character (root part is 2 studs tall).
	local sizeRatio = root.Size.Y / 2
	local scale = if sizeRatio >= Config.WallHopScaleFrom then sizeRatio else 1

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
		tracks = tracks,
		connections = {},
		destroyed = false,
		scale = scale,

		phase = "Idle" :: Phase,
		runStart = 0,
		wallNormal = Vector3.zero,
		runDirection = Vector3.zero,
		runSpeed = 0,
		hopsUsed = 0,
		lastKick = -math.huge,
		kickNormal = Vector3.zero,
		kickPush = 0,
		lateLeapOpen = false,
		lastWall = nil,
		lastPress = -math.huge,
		holdStart = -math.huge,
		recent = nil,
		recentAt = -math.huge,
		totalHops = 0,
		wallSide = "Right",
		runTrack = nil,
		lastFailure = "",
	}, WallHop)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_step(dt)
				Perf.add("WallHop", os.clock() - t0)
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
	character:SetAttribute("WallRunning", false)
	return self
end

function WallHop.Get(character: Model): WallHop?
	return active[character]
end

-- Call on every Space press. `madeJump` = this press made a jump (on the ground, or a coyote jump
-- just after walking off a ledge). Only airborne presses that did NOT make a jump count as a hop
-- press, so jumping into a wall alone never hops.
function WallHop.OnJumpPressed(self: WallHop, madeJump: boolean?)
	local now = os.clock()
	self.holdStart = now
	if not madeJump and self.motor:GetMode() == "Air" then
		self.lastPress = now
	end
end

-- Hops allowed this airtime at the current health.
function WallHop.GetMaxHops(self: WallHop): number
	local share = self.humanoid.Health / math.max(self.humanoid.MaxHealth, 1)
	if share > 2 / 3 then
		return Config.WallHopsHigh
	elseif share > 1 / 3 then
		return Config.WallHopsMid
	end
	return Config.WallHopsLow
end

function WallHop.GetHopsLeft(self: WallHop): number
	return math.max(self:GetMaxHops() - self.hopsUsed, 0)
end

function WallHop.IsRunning(self: WallHop): boolean
	return self.phase == "Running"
end

-- Total hops since spawn (tests).
function WallHop.GetTotalHops(self: WallHop): number
	return self.totalHops
end

-- Why the last attempt near a wall didn't hop (debug overlay / tests).
function WallHop.GetLastFailure(self: WallHop): string
	return self.lastFailure
end

local function isCharacterPart(instance: Instance): boolean
	local model = instance:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- Casts from chest and knee height; both must hit the same kind of wall.
function WallHop._castWall(self: WallHop, origin: Vector3, direction: Vector3): RaycastResult?
	local chest = Workspace:Raycast(origin, direction, self.castParams)
	if not chest or math.abs(chest.Normal.Y) >= WALL_MAX_NORMAL_Y or isCharacterPart(chest.Instance) then
		return nil
	end
	local low = Workspace:Raycast(origin - Vector3.new(0, self.root.Size.Y * 0.75, 0), direction, self.castParams)
	if not low or math.abs(low.Normal.Y) >= WALL_MAX_NORMAL_Y then
		return nil
	end
	return chest
end

-- Every wall around the body within reach that the input points into AND along.
-- Returns the one the input points into most.
function WallHop._findWall(self: WallHop, move: Vector3): Candidate?
	local root = self.root
	local reach = root.Size.X / 2 + Config.WallHopReach * self.scale
	local best: Candidate? = nil
	local sawWall = false
	for i = 0, 7 do
		local direction = CFrame.Angles(0, i * math.pi / 4, 0):VectorToWorldSpace(move) * reach
		local hit = self:_castWall(root.Position, direction)
		if hit then
			sawWall = true
			local normal = flatten(hit.Normal)
			if normal.Magnitude > 1e-3 then
				normal = normal.Unit
				local into = -move:Dot(normal)
				local along = move + normal * into
				if into >= Config.WallHopIntoMin and along.Magnitude >= Config.WallHopAlongMin then
					if not best or into > best.into then
						best = { hit = hit, normal = normal, into = into, along = along.Unit }
					end
				elseif not best then
					self.lastFailure = if into < Config.WallHopIntoMin
						then "input not pointing into the wall"
						else "input not pointing along the wall"
				end
			end
		end
	end
	if not sawWall then
		self.lastFailure = "no wall in reach"
	end
	return best
end

-- The wall has to continue ahead in the run direction, and there has to be headroom.
function WallHop._roomToRun(self: WallHop, candidate: Candidate): boolean
	local root = self.root
	local reach = root.Size.X / 2 + Config.WallHopReach * self.scale + 0.5
	local ahead = root.Position + candidate.along * Config.WallHopAheadCheck * self.scale
	if not self:_castWall(ahead, -candidate.normal * reach) then
		self.lastFailure = "wall ends ahead"
		return false
	end
	local headroom = Workspace:Raycast(root.Position, Vector3.yAxis * Config.WallHopHeadroom * self.scale, self.castParams)
	if headroom then
		self.lastFailure = "no headroom"
		return false
	end
	return true
end

function WallHop._step(self: WallHop, _dt: number)
	if self.destroyed then
		return
	end
	local mode = self.motor:GetMode()
	if self.phase == "Idle" then
		if mode == "Air" then
			self:_lateLeap()
		end
		if mode == "Ground" then
			self.lateLeapOpen = false
			self.hopsUsed = 0
			-- A press just before landing is a buffered jump, not a hop press.
			self.lastPress = -math.huge
			self.recent = nil
		end
		self:_tryStart(mode)
	else
		self:_stepRun()
	end
end

-- Keys turned away from the wall just AFTER the kick (a normal reaction time) still get the full
-- push across, so zig-zag timing doesn't have to be frame perfect.
function WallHop._lateLeap(self: WallHop)
	if not self.lateLeapOpen then
		return
	end
	if os.clock() - self.lastKick > Config.WallHopLateLeap then
		self.lateLeapOpen = false
		return
	end
	local move = flatten(self.humanoid.MoveDirection)
	if move.Magnitude < 0.1 or move.Unit:Dot(self.kickNormal) <= Config.WallHopLeapAway then
		return
	end
	self.lateLeapOpen = false
	local extra = Config.WallHopPushAway * self.scale - self.kickPush
	if extra <= 0 then
		return
	end
	local velocity = self.root.AssemblyLinearVelocity
	local horizontal = flatten(velocity) + self.kickNormal * extra
	self.root.AssemblyLinearVelocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)
	self.motor:ApplyMomentum(horizontal)
end

-- True when the held keys are a forward key plus a side key (W+A / W+D), judged relative to the
-- camera like the keys themselves (the world direction alone can't tell W from W+D).
function WallHop._diagonalKeys(self: WallHop, move: Vector3): boolean
	local camera = Workspace.CurrentCamera
	local look = if camera then flatten(camera.CFrame.LookVector) else flatten(self.root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		look = flatten(self.root.CFrame.LookVector)
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	return move:Dot(look) >= Config.WallHopKeyMin and math.abs(move:Dot(right)) >= Config.WallHopKeyMin
end

function WallHop._tryStart(self: WallHop, mode: string)
	if mode ~= "Air" or self.isBlocked() or self.humanoid.Health <= 0 or self:GetHopsLeft() <= 0 then
		self.recent = nil
		return
	end
	local now = os.clock()
	local move = flatten(self.humanoid.MoveDirection)
	local candidate: Candidate? = nil
	local diagonal = move.Magnitude >= 0.1 and self:_diagonalKeys(move.Unit)
	if move.Magnitude >= 0.1 then
		candidate = self:_findWall(move.Unit)
		if candidate and not diagonal then
			-- W alone (or A / D alone) can point into and along a wall when the camera is at an
			-- angle to it. The JJS input is a forward key AND a side key: W+D / W+A.
			self.lastFailure = "hold W + A or D toward the wall (W alone doesn't hop)"
			candidate = nil
		end
	end
	-- Remember the last usable wall for a moment (a press just after leaving it still hops).
	if candidate then
		self.recent = candidate
		self.recentAt = now
	elseif diagonal and self.recent and now - self.recentAt <= Config.WallHopCoyote then
		candidate = self.recent
	end
	if not candidate then
		return
	end
	-- Space: HELD (longer than a tap, so a quick jump next to a wall doesn't hop), or pressed
	-- again while airborne a moment ago.
	local holding = self.motor:IsJumpHeld() and now - self.holdStart >= Config.WallHopHoldTime
	if not holding and now - self.lastPress > Config.WallHopPressBuffer then
		self.lastFailure = "jumped into the wall: press Space again or hold it"
		return
	end
	local sinceKick = now - self.lastKick
	if sinceKick < Config.WallHopRegrabOther then
		return
	end
	-- The same wall again needs a little longer, so one wall isn't hopped twice by accident.
	if candidate.hit.Instance == self.lastWall and sinceKick < Config.WallHopRegrab then
		return
	end
	if not self:_roomToRun(candidate) then
		return
	end
	self.lastFailure = ""
	self.lastWall = candidate.hit.Instance
	self.lastPress = -math.huge -- one press, one hop
	self.recent = nil
	self:_startRun(candidate.normal, candidate.along)
end

function WallHop._startRun(self: WallHop, normal: Vector3, along: Vector3)
	self.phase = "Running"
	self.runStart = os.clock()
	self.wallNormal = normal
	self.runDirection = along
	-- Which side of the body the wall is on (the body faces along the wall while running).
	local right = along:Cross(Vector3.yAxis)
	self.wallSide = if (-normal):Dot(right) >= 0 then "Right" else "Left"
	-- Keep your speed along the wall if you arrive faster than the run speed.
	local arriving = self.root.AssemblyLinearVelocity:Dot(along)
	self.runSpeed = math.max(Config.WallRunSpeed * self.scale, math.min(arriving, Config.WallRunMaxSpeed * self.scale))
	self.hopsUsed += 1
	self.totalHops += 1

	self.motor:Suspend()
	self.humanoid.AutoRotate = false
	self.velocity.VectorVelocity = self:_runVelocity()
	self.velocity.Enabled = true
	self.align.CFrame = CFrame.lookAlong(Vector3.zero, along)
	self.align.Enabled = true
	self.character:SetAttribute("WallRunning", true)

	local track = self:_sidedTrack("WallRun")
	self.runTrack = track
	if track then
		track:Play(0)
	end
end

-- "WallRun" / "WallHop" for the side the wall is on (e.g. "WallRunRight"), else the plain one.
function WallHop._sidedTrack(self: WallHop, base: string): AnimationTrack?
	return self.tracks[base .. self.wallSide] or self.tracks[base]
end

function WallHop._stopRunTrack(self: WallHop)
	local track = self.runTrack
	if track and track.IsPlaying then
		track:Stop(0)
	end
	self.runTrack = nil
end

function WallHop._runVelocity(self: WallHop): Vector3
	local s = self.scale
	-- A small pull into the wall keeps the body against it while running.
	return self.runDirection * self.runSpeed + Vector3.yAxis * Config.WallRunRise * s - self.wallNormal * 2
end

function WallHop._stepRun(self: WallHop)
	local elapsed = os.clock() - self.runStart
	-- Kick off when the time is up, the wall ends, or the input turns back the other way along it.
	local stillOnWall = Workspace:Raycast(
		self.root.Position,
		-self.wallNormal * (self.root.Size.X / 2 + Config.WallHopReach * self.scale + 0.5),
		self.castParams
	) ~= nil
	local move = flatten(self.humanoid.MoveDirection)
	local reversed = move.Magnitude > 0.1 and move.Unit:Dot(self.runDirection) < -0.3
	-- Keys pointing away from the wall = leap off now (toward the other wall of an alley).
	local leaping = move.Magnitude > 0.1 and move.Unit:Dot(self.wallNormal) > Config.WallHopLeapAway
	if elapsed >= Config.WallRunTime or not stillOnWall or reversed or leaping or self.isBlocked() then
		self:_kick()
		return
	end
	self.velocity.VectorVelocity = self:_runVelocity()
end

function WallHop._kick(self: WallHop)
	if self.phase ~= "Running" then
		return
	end
	self.phase = "Idle"
	self.lastKick = os.clock()
	self.velocity.Enabled = false
	self.align.Enabled = false
	self.humanoid.AutoRotate = true
	self.character:SetAttribute("WallRunning", false)
	self:_stopRunTrack()

	local s = self.scale
	local gravity = Workspace.Gravity
	local up = math.sqrt(2 * gravity * Config.WallHopHeight * s)
	-- Push away from the wall by where your keys point as you leave it: into the wall = small (to
	-- climb the same wall), along = medium, away = big (across an alley to the other wall).
	local move = flatten(self.humanoid.MoveDirection)
	local away = if move.Magnitude > 0.1 then move.Unit:Dot(self.wallNormal) else 0
	local push
	if away >= 0 then
		push = Config.WallHopPush + (Config.WallHopPushAway - Config.WallHopPush) * math.min(away / 0.7, 1)
	else
		push = Config.WallHopPush + (Config.WallHopPushInto - Config.WallHopPush) * math.min(-away / 0.7, 1)
	end
	self.kickNormal = self.wallNormal
	self.kickPush = push * s
	self.lateLeapOpen = true
	local carry = math.max(Config.WallHopCarry * s, self.runSpeed * 0.85)
	local horizontal = self.wallNormal * push * s + self.runDirection * carry
	self.root.AssemblyLinearVelocity = horizontal + Vector3.yAxis * up

	-- Hand back to the motor: it keeps this speed in the air, and may rise above a normal jump.
	self.motor:ApplyMomentum(horizontal)
	self.motor:AllowLaunch(0.6)
	self.motor:Resume()

	local hopTrack = self:_sidedTrack("WallHop")
	if hopTrack then
		hopTrack:Play(0)
	end
	Sfx.Play(self.character, "WallKick")
	Sfx.Play(self.character, "Jump", { volume = 0.7, speed = 1.1 })
end

-- Ends a wall run early without kicking (e.g. getting hit, once combat exists).
function WallHop.Cancel(self: WallHop)
	if self.phase ~= "Running" then
		return
	end
	self.phase = "Idle"
	self.velocity.Enabled = false
	self.align.Enabled = false
	self.humanoid.AutoRotate = true
	self.character:SetAttribute("WallRunning", false)
	self:_stopRunTrack()
	self.motor:Resume()
end

function WallHop.Destroy(self: WallHop)
	if self.destroyed then
		return
	end
	self:Cancel()
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

return WallHop
