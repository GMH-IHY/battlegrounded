--!strict
-- AutoParkour (ModuleScript)
-- Location: ReplicatedStorage > Movement > AutoParkour
--
-- JJS-style automatic parkour for one character (client side, next to CharacterMotor, Dash,
-- WallHop, LandingRoll). No extra key: it happens when you SPRINT into an obstacle.
--
--   Vault    obstacle top up to VaultMaxHeight above your feet and at most VaultMaxDepth deep
--            (bins, rails, tables, counters): you go over it and keep your speed.
--   Step-up  same height but deeper (a box or platform): you hop up onto it and keep running.
--   Climb    a LEDGE YOUR HANDS REACH (top up to LedgeReach above your feet): sprint into it
--            from the ground (tops above VaultMaxHeight), or jump at it with your keys on it and
--            grab it in the air if the jump wouldn't clear it anyway. You scale it and stand on top.
--   Slide    an overhang you can't walk under but can slide under (SlideMinClearance up to
--            standing height): you slide under, keep your speed, and stand up once there's room.
--
-- v2 (Isaac, Sep 26: "sliding flings you super hard", "sliding is very finicky, ledge climbing
-- too", "should be a smooth auto parkour experience"):
--   * The slide no longer lays the physical body down. Your normal collision parts stop
--     colliding and a small low SlideCollider (1.1 to 2.2 studs above the feet) takes over, so
--     the Humanoid keeps holding your height exactly like when running: nothing pushes you up or
--     down, nothing can fling. The lean back is VISUAL only (the torso joint). You stand up only
--     once there's room around the whole body, so standing never overlaps the roof.
--   * Vaults and climbs go straight over the obstacle (along its face normal), not along your
--     keys, so hitting it at an angle still goes cleanly over.
--   * Triggers are easier: up to ParkourMaxAngle 55 degrees off head-on, half your run speed, and
--     pressed right up against the obstacle (after being stopped by it) counts at any speed.
--   * Vault/climb forces are capped, so being blocked mid-move can't build up a launch; you can
--     never leave a vault or climb moving upward.
--
-- v3 (Isaac, Sep 26: "not sure why you auto climb on boxes 9 studs tall", "go sideways against a
-- ledge ... get yourself diagonal towards the ledge and get yourself stuck"):
--   * Ledge climbing = scaling a ledge your hands reach. A 9-stud box is out of reach from the
--     ground (sprinting into it does nothing); jump at it and you grab and scale it.
--   * Anything you end up standing on (climb, step-up) must fit the WHOLE body: near a corner or
--     the end of a ledge you're shifted sideways onto it, or it doesn't happen at all (no
--     half-on climbs that snag).
--   * A climb that stops rising lets go; a blocked move waits ParkourFailCooldown before trying
--     again (no retry loops against a wall).
--
-- Intentional input: on the ground you must be sprinting; in the air your keys must point at
-- the ledge. Your keys must point at the obstacle. Walking
-- into things or brushing past at a steep angle does nothing.
-- Never: steps, anything taller than the limits (wall hop instead), tops with no room (ceiling,
-- railing), gaps too low for the slide collider, other characters.
-- Not during a dash, wall run or landing roll; none of those can start during parkour. No
-- jumping during parkour.
--
-- Animations: plays "Vault" (also for a step-up), "LedgeClimb" and "Slide" if they exist
-- (a local KeyframeSequence in AnimationConfig.Names). Attribute "Parkour" = the action while it
-- runs. NOTE: the slide lean is set on this client only (joint changes don't replicate); other
-- players will need it replicated once multiplayer visuals are done.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
local Perf = require(script.Parent.Perf)
local CharacterMotor = require(script.Parent.CharacterMotor)
local AnimationLibrary = require(script.Parent.AnimationLibrary)

export type Action = "Vault" | "StepUp" | "Climb" | "Slide"
type Phase = "Idle" | "Over" | "ClimbUp" | "ClimbOver" | "Slide"

-- Collision group the body parts use while sliding (registered by the server script
-- CollisionGroups; it doesn't collide with anything).
local SLIDE_GROUP = "ParkourSlideBody"
-- Obstacle faces: |normal.Y| below this.
local FACE_MAX_NORMAL_Y = 0.5
-- Walkable tops: normal.Y above this.
local TOP_MIN_NORMAL_Y = 0.7
-- Heights (above the feet) of the rays that look for an obstacle ahead.
local PROBE_HEIGHTS: { number } = { 1.4, 2.2, 3.0, 3.8, 4.6 }
-- In the air the hands reach higher: also look at arm height.
local AIR_PROBE_HEIGHTS: { number } = { 1.4, 2.2, 3.0, 3.8, 4.6, 5.4, 6.2 }
-- Height of a standing character (feet to head top) plus a little margin.
local STAND_CLEARANCE = 5.3
-- Longest any vault / climb may take before it gives up.
local MAX_MOVE_TIME = 1.2
-- How quickly the body turns to a move's direction (AlignOrientation responsiveness).
local FACING_RESPONSIVENESS = 45
-- Longest the pull over a ledge's edge may take (seconds).
local CLIMB_OVER_MAX_TIME = 0.45
-- Pressed up against an obstacle this close counts even when it has stopped you.
local AGAINST_DISTANCE = 1.3
-- Slid along a face farther than this (studs) = brushing along it, not clipping its corner.
local CORNER_SLIDE_GRACE = 3
-- Velocity more than this many degrees off the keys = deflected by something.
local DEFLECTED_COS = math.cos(math.rad(12))
-- Strongest acceleration the vault / climb velocity may use (studs/s^2).
local MAX_ACCELERATION = 1500

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function isCharacterPart(instance: Instance): boolean
	local model = instance:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function animationExists(name: string): boolean
	return AnimationLibrary.Exists(name)
end

local function slideGroupReady(): boolean
	local ok, registered = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(SLIDE_GROUP)
	end)
	return ok and registered == true
end

type Plan = {
	action: Action,
	direction: Vector3, -- which way to go over / under it
	faceDistance: number, -- from the root to the obstacle face, along `direction`
	topY: number, -- vault / step-up / climb: height of the top surface
	releaseDistance: number, -- vault / step-up / climb: how far along `direction` to carry you
	shift: number, -- climb / step-up: sideways correction so the body fits on the ledge
	part: string?, -- debug: what it reacted to
}

type Candidate = { hit: RaycastResult, distance: number, normal: Vector3, steep: boolean, side: number }

type SavedPart = { part: BasePart, canCollide: boolean, group: string }

-- Lets parkour take over a front dash that runs into something (keeping the dash's speed).
export type DashHook = {
	isDashing: () -> boolean, -- a front dash is running
	velocity: () -> Vector3, -- its current (flat) velocity
	handOff: () -> (), -- end it, keeping that velocity
}

-- Lets parkour take over a wall run whose wall (or a ledge ahead) comes within grabbing reach:
-- the wall hop ends without its kick and you climb up instead.
export type WallRunHook = {
	isRunning: () -> boolean, -- a wall run is going on
	handOff: () -> (), -- end it without kicking
}

local AutoParkour = {}
AutoParkour.__index = AutoParkour

type AutoParkourData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	isBlocked: () -> boolean,
	attachment: Attachment,
	velocity: LinearVelocity,
	slideVelocity: LinearVelocity,
	align: AlignOrientation,
	slideCollider: Part,
	rootJoint: Motor6D?,
	baseC0: CFrame,
	castParams: RaycastParams,
	tracks: { [string]: AnimationTrack },
	connections: { RBXScriptConnection },
	destroyed: boolean,

	phase: Phase,
	action: Action?,
	direction: Vector3,
	speed: number,
	startPosition: Vector3,
	startTime: number,
	faceDistance: number,
	topY: number,
	releaseDistance: number,
	standOffset: number,
	floorY: number,
	wentUnder: boolean,
	stalledFor: number,
	lastEnd: number,
	lastFailed: boolean,
	shiftLeft: number,
	shiftStart: Vector3,
	right: Vector3,
	progressY: number,
	noProgressFor: number,
	jumpLocked: boolean,
	savedParts: { SavedPart },

	counts: { [string]: number },
	lastInfo: string,
	lastStartMode: string,
	lastDetail: string,
	jumpPressAt: number,
	lastEndSpeed: number,
	cornerDebug: string,
	deflectedFor: number,
	cornerSlide: string,
	dashHook: DashHook?,
	wallRunHook: WallRunHook?,
	entrySpeed: number,
	overStart: number,
	maxRise: number,
}

export type AutoParkour = typeof(setmetatable({} :: AutoParkourData, AutoParkour))

local active: { [Model]: AutoParkour } = {}

-- `isBlocked` returns true while something else owns the character (dash, wall run, roll).
function AutoParkour.new(character: Model, motor: CharacterMotor.CharacterMotor, isBlocked: () -> boolean): AutoParkour
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "ParkourAttachment"
	attachment.Parent = root

	-- Vault / climb: full velocity (up and over), with a capped force.
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "ParkourVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = root.AssemblyMass * MAX_ACCELERATION
	velocity.Enabled = false
	velocity.Parent = root

	-- Slide: horizontal only. Height stays with the Humanoid, like running.
	local slideVelocity = Instance.new("LinearVelocity")
	slideVelocity.Name = "ParkourSlideVelocity"
	slideVelocity.Attachment0 = attachment
	slideVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	slideVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	slideVelocity.PrimaryTangentAxis = Vector3.xAxis
	slideVelocity.SecondaryTangentAxis = Vector3.zAxis
	slideVelocity.MaxForce = math.huge
	slideVelocity.Enabled = false
	slideVelocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "ParkourFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	-- Turns fast but smoothly (a rigid align snapped the body to the new facing in one frame).
	align.RigidityEnabled = false
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = FACING_RESPONSIVENESS
	align.Enabled = false
	align.Parent = root

	-- The body while sliding: a low box from 1.1 to 2.2 studs above the feet (anything lower is
	-- stepped over, like the leg box). Off until a slide starts.
	local scale = root.Size.Y / 2
	local standOffset = 3 * scale
	local slideCollider = Instance.new("Part")
	slideCollider.Name = "SlideCollider"
	slideCollider.Size = Vector3.new(1.6, 1.1, 1.6) * scale
	slideCollider.Transparency = 1
	slideCollider.CanCollide = false
	slideCollider.CanQuery = false
	slideCollider.CanTouch = false
	slideCollider.Massless = true
	slideCollider.CFrame = root.CFrame * CFrame.new(0, -standOffset + (Config.LowerColliderGap + 0.55) * scale, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = slideCollider
	weld.Parent = slideCollider
	slideCollider.Parent = character

	local rootJoint = root:FindFirstChild("RootJoint")
	local joint: Motor6D? = if rootJoint and rootJoint:IsA("Motor6D") then rootJoint else nil

	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true

	local tracks: { [string]: AnimationTrack } = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, name in { "Vault", "LedgeClimb", "Slide" } do
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

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		isBlocked = isBlocked,
		attachment = attachment,
		velocity = velocity,
		slideVelocity = slideVelocity,
		align = align,
		slideCollider = slideCollider,
		rootJoint = joint,
		baseC0 = if joint then joint.C0 else CFrame.identity,
		castParams = castParams,
		tracks = tracks,
		connections = {},
		destroyed = false,

		phase = "Idle" :: Phase,
		action = nil,
		direction = Vector3.zAxis,
		speed = 0,
		startPosition = root.Position,
		startTime = 0,
		faceDistance = 0,
		topY = 0,
		releaseDistance = 0,
		standOffset = standOffset,
		floorY = 0,
		wentUnder = false,
		stalledFor = 0,
		lastEnd = -math.huge,
		lastFailed = false,
		shiftLeft = 0,
		shiftStart = root.Position,
		right = Vector3.xAxis,
		progressY = 0,
		noProgressFor = 0,
		jumpLocked = false,
		savedParts = {},

		counts = { Vault = 0, StepUp = 0, Climb = 0, Slide = 0 },
		lastInfo = "",
		lastStartMode = "",
		lastDetail = "",
		jumpPressAt = -math.huge,
		lastEndSpeed = 0,
		cornerDebug = "",
		deflectedFor = 0,
		cornerSlide = "",
		dashHook = nil,
		wallRunHook = nil,
		entrySpeed = 0,
		overStart = 0,
		maxRise = 0,
	}, AutoParkour)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_step(dt)
				Perf.add("AutoParkour", os.clock() - t0)
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
	character:SetAttribute("Parkour", nil)
	return self
end

function AutoParkour.Get(character: Model): AutoParkour?
	return active[character]
end

-- Space pressed during a move: if it's near the end, you jump as soon as the move is over
-- (on the ground right away, or on landing after a vault).
-- A slide-jump: Space during a slide jumps out of it as soon as there's room to stand (right
-- away in the open, or when you clear what you're under), keeping the slide's speed.
function AutoParkour.OnJumpPressed(self: AutoParkour)
	if self.phase ~= "Idle" then
		self.jumpPressAt = os.clock()
	end
end

function AutoParkour.SetDashHook(self: AutoParkour, hook: DashHook?)
	self.dashHook = hook
end

function AutoParkour.SetWallRunHook(self: AutoParkour, hook: WallRunHook?)
	self.wallRunHook = hook
end

function AutoParkour.IsBusy(self: AutoParkour): boolean
	return self.phase ~= "Idle"
end

function AutoParkour.GetAction(self: AutoParkour): string
	return self.action or ""
end

-- Debug / tests: how many times each action ran, and what the last check found.
function AutoParkour.GetCount(self: AutoParkour, action: string): number
	return self.counts[action] or 0
end

function AutoParkour.GetLastInfo(self: AutoParkour): string
	return self.lastInfo
end

-- "Ground" or "Air": where the last action started from.
function AutoParkour.GetLastStartMode(self: AutoParkour): string
	return self.lastStartMode
end

-- Fastest upward speed during the last action (tests: a fling shows up here).
-- Debug: what the last move reacted to and where it started.
function AutoParkour.GetLastDetail(self: AutoParkour): string
	return self.lastDetail
end

-- Debug: the last steep (corner) probe hit and whether it counted as a corner.
function AutoParkour.GetCornerDebug(self: AutoParkour): string
	return self.cornerDebug
end

-- Horizontal speed the last action handed back to normal movement (tests).
function AutoParkour.GetLastEndSpeed(self: AutoParkour): number
	return self.lastEndSpeed
end

function AutoParkour.GetLastMaxRise(self: AutoParkour): number
	return self.maxRise
end

-- DETECTION ----------------------------------------------------------------------

function AutoParkour._cast(self: AutoParkour, origin: Vector3, direction: Vector3): RaycastResult?
	if Perf.enabled then
		Perf.count("AutoParkour rays", 1)
	end
	local result = Workspace:Raycast(origin, direction, self.castParams)
	if result and isCharacterPart(result.Instance) then
		return nil
	end
	return result
end

-- A face of an obstacle ahead (not a slope, not a character), up to the corner angle limit.
-- Returns the hit and whether it's steeper than ParkourMaxAngle (only usable at a corner).
function AutoParkour._faceAhead(self: AutoParkour, origin: Vector3, direction: Vector3, length: number): (RaycastResult?, boolean)
	local hit = self:_cast(origin, direction * length)
	if not hit or math.abs(hit.Normal.Y) >= FACE_MAX_NORMAL_Y then
		return nil, false
	end
	local normal = flatten(hit.Normal)
	if normal.Magnitude < 1e-3 then
		return nil, false
	end
	local facing = -normal.Unit:Dot(direction)
	if facing < math.cos(math.rad(Config.ParkourCornerMaxAngle)) then
		return nil, false
	end
	return hit, facing < math.cos(math.rad(Config.ParkourMaxAngle))
end

-- A steep hit counts only if the face ENDS within ParkourCornerZone ahead (the way you're moving
-- along it): you're clipping its corner, not brushing along it.
function AutoParkour._atCorner(self: AutoParkour, hit: RaycastResult, keys: Vector3): boolean
	local normal = flatten(hit.Normal).Unit
	-- Slid along this face a while (it deflected you well before its end): reaching the end you
	-- just run past the corner. Clipping a corner deflects you only a stud or two before.
	local velocity = flatten(self.root.AssemblyLinearVelocity)
	if Config.DebugSpeedometer then
		self.cornerSlide = string.format("slid %.1f vn %.2f", self.deflectedFor, if velocity.Magnitude > 2 then math.abs(velocity.Unit:Dot(normal)) else -1)
	end
	if self.deflectedFor > CORNER_SLIDE_GRACE then
		return false
	end
	local along = keys - normal * keys:Dot(normal)
	if along.Magnitude < 1e-3 then
		return false
	end
	along = along.Unit
	local probe = hit.Position + normal * 0.4 + along * Config.ParkourCornerZone
	local back = self:_cast(probe, -normal * 1.2)
	return back == nil or back.Instance ~= hit.Instance
end

-- Is the line from `origin` along `direction` clear for `length` studs?
function AutoParkour._clear(self: AutoParkour, origin: Vector3, direction: Vector3, length: number): boolean
	return self:_cast(origin, direction * length) == nil
end

-- Top surface of whatever is under `point` (flat), searched from `fromY` down to `toY`.
-- Returns its height if it's walkable and has standing room above it.
function AutoParkour._topAt(self: AutoParkour, point: Vector3, fromY: number, toY: number): number?
	local hit = self:_cast(Vector3.new(point.X, fromY, point.Z), Vector3.new(0, toY - fromY, 0))
	if not hit or hit.Normal.Y < TOP_MIN_NORMAL_Y then
		return nil
	end
	if not self:_clear(Vector3.new(point.X, hit.Position.Y + 0.1, point.Z), Vector3.yAxis, STAND_CLEARANCE) then
		return nil
	end
	return hit.Position.Y
end

-- Something you stand on after the move (climb, step-up) must be under the WHOLE body, not
-- just its middle: near a corner or the end of a ledge, half the body would hang off and snag.
-- True if, with the body shifted `offset` sideways, both sides and the middle have the same top.
function AutoParkour._fits(self: AutoParkour, column: Vector3, right: Vector3, offset: number, topY: number, fromY: number, toY: number): boolean
	local half = Config.LedgeBodyHalfWidth
	for _, side in { -half, 0, half } do
		local top = self:_topAt(column + right * (offset + side), fromY, toY)
		if not top or math.abs(top - topY) > 0.6 then
			return false
		end
	end
	return true
end

-- The way over the top is clear for the whole body (left, middle, right lanes, from just above
-- the top to head height), with the body shifted `offset` sideways.
function AutoParkour._pathClear(self: AutoParkour, position: Vector3, direction: Vector3, right: Vector3, offset: number, topY: number, length: number): boolean
	local half = Config.LedgeBodyHalfWidth
	for _, side in { -half, 0, half } do
		local lane = position + right * (offset + side)
		for _, above in { 0.6, 2.5, 4.8 } do
			if not self:_clear(Vector3.new(lane.X, topY + above, lane.Z), direction, length) then
				return false
			end
		end
	end
	return true
end

-- A slide under an overhang `faceDistance` ahead along `keys`, or nil (with lastInfo saying why).
function AutoParkour._slidePlan(self: AutoParkour, position: Vector3, footY: number, keys: Vector3, faceDistance: number, faceName: string): Plan?
	local column = flatten(position) + keys * (faceDistance + 0.3)
	-- Open low down all the way under it (the slide collider's height).
	for _, height in { Config.LowerColliderGap + 0.2, Config.LowerColliderGap + 1.0 } do
		if not self:_clear(Vector3.new(position.X, footY + height, position.Z), keys, faceDistance + 2) then
			self.lastInfo = "something low in the way of a slide"
			return nil
		end
	end
	local under = self:_cast(Vector3.new(column.X, footY + 0.3, column.Z), Vector3.new(0, STAND_CLEARANCE, 0))
	if not under then
		return nil -- tall enough to walk under
	end
	local clearance = under.Position.Y - footY
	if clearance < Config.SlideMinClearance then
		self.lastInfo = string.format("gap %.1f too low to slide (%.1f)", clearance, Config.SlideMinClearance)
		return nil
	end
	if not self:_cast(Vector3.new(column.X, footY + 0.5, column.Z), Vector3.new(0, -2.5, 0)) then
		self.lastInfo = "no floor under the gap"
		return nil
	end
	return {
		action = "Slide",
		direction = keys,
		faceDistance = faceDistance,
		topY = under.Position.Y,
		releaseDistance = 0,
		shift = 0,
		part = under.Instance.Name .. "/face " .. faceName,
	}
end

-- `keys` = where the input points. `maxDistance`: only faces this close count (the
-- pressed-against case).
function AutoParkour._plan(self: AutoParkour, keys: Vector3, speed: number, airborne: boolean, maxDistance: number?): Plan?
	local root = self.root
	local position = root.Position
	local footY = position.Y - self.standOffset
	local look = maxDistance
		or if airborne
			then Config.LedgeGrabDistance + speed * 0.05
			else math.max(Config.ParkourLookMin, 0.6 + speed * Config.ParkourLookTime)

	-- Nearest obstacle face at any probe height (in the air also up at hand height), cast from
	-- the middle of the body AND both shoulders: running at the corner of a box, the shoulder hits
	-- it while the middle slips past.
	local heights: { number } = if airborne then AIR_PROBE_HEIGHTS else PROBE_HEIGHTS
	local keysRight = Vector3.new(-keys.Z, 0, keys.X)
	-- Every face hit (one per face, nearest point), tried nearest first: at a corner the nearest
	-- face may not work (a steep side) while the other one does.
	local candidates: { Candidate } = {}
	local nearestDistance = math.huge
	local lowestBlocked = false
	-- The middle of the body on its own (slides are decided from it: a slide steers along a
	-- low side wall that only a shoulder would touch).
	local middleHit = false
	local middleDistance = math.huge
	local middleLow = false
	local middleName = ""
	for _, side in { 0, -Config.LedgeBodyHalfWidth, Config.LedgeBodyHalfWidth } do
		local origin = position + keysRight * side
		for i, height in ipairs(heights) do
			local hit, steep = self:_faceAhead(Vector3.new(origin.X, footY + height, origin.Z), keys, look)
			if hit and steep then
				local ok = self:_atCorner(hit, keys)
				if not ok then
					hit = nil
				end
				local h = hit or (nil :: RaycastResult?)
				self.cornerDebug = if not Config.DebugSpeedometer then "" else string.format("steep hit side %.1f h%d corner %s at (%.1f, %.1f) %s", side, i, tostring(ok), (h and h.Position.X) or 0, (h and h.Position.Z) or 0, self.cornerSlide)
			end
			if hit then
				local distance = (flatten(hit.Position) - flatten(origin)):Dot(keys)
				if i == 1 then
					lowestBlocked = true
				end
				nearestDistance = math.min(nearestDistance, distance)
				local normal = flatten(hit.Normal).Unit
				local existing: Candidate? = nil
				for _, candidate in candidates do
					if candidate.hit.Instance == hit.Instance and candidate.normal:Dot(normal) > 0.98 then
						existing = candidate
						break
					end
				end
				if not existing then
					table.insert(candidates, { hit = hit, distance = distance, normal = normal, steep = steep, side = side })
				elseif distance < existing.distance then
					existing.hit = hit
					existing.distance = distance
					existing.side = side
				end
				if side == 0 and not steep then
					middleHit = true
					if distance < middleDistance then
						middleDistance = distance
						middleName = hit.Instance.Name
					end
					if i == 1 then
						middleLow = true
					end
				end
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.distance < b.distance
	end)

	-- Overhang in front of the middle of the body (knee height open, something at chest / head
	-- height): slide under it, going the way the keys point.
	if middleHit and not middleLow and not airborne then
		local slide = self:_slidePlan(position, footY, keys, middleDistance, middleName)
		if slide then
			return slide
		end
	end
	-- Only an overhang (nothing at knee height) and no slide: nothing to go over.
	if not airborne and not lowestBlocked then
		return nil
	end

	for _, candidate in candidates do
		-- A face you come at within the angle limit: straight over it, along its normal. A corner
		-- you clip at a steeper angle: over it the way the keys point.
		-- A steep corner is planned from the ray that hit it (a shoulder, often): your middle line
		-- would pass beside the corner.
		local direction = if candidate.steep then keys else -candidate.normal
		local baseShift = if candidate.steep then candidate.side else 0
		-- Flow: from the ground, vault / step up the way you're running (not snapped square to
		-- the face) when that line works. Climbs still go straight up the face.
		if not candidate.steep and not airborne and keys:Dot(-candidate.normal) < 0.995 then
			local flowing = self:_planOver(candidate.hit, keys, position, footY, airborne, 0)
			if flowing and flowing.action ~= "Climb" then
				return flowing
			end
		end
		local plan = self:_planOver(candidate.hit, direction, position, footY, airborne, baseShift)
		if plan then
			return plan
		end
		if candidate.steep then
			if Config.DebugSpeedometer then
				self.cornerDebug ..= " | planOver failed: " .. self.lastInfo
			end
		end
	end
	return nil
end

-- Vault / step-up / climb over the face `nearest`, moving along `direction`.
-- `baseShift`: sideways offset (along `right`) of the line to plan from, relative to your middle.
function AutoParkour._planOver(self: AutoParkour, nearest: RaycastResult, direction: Vector3, position: Vector3, footY: number, airborne: boolean, baseShift: number): Plan?
	local root = self.root
	local partName = nearest.Instance.Name
	local right = Vector3.new(-direction.Z, 0, direction.X)
	-- Where the middle of the body crosses the face's plane, going along `direction` (coming in
	-- steep at a corner, that's farther than the hit, which may have come from a shoulder).
	local normal = flatten(nearest.Normal).Unit
	local into = -normal:Dot(direction)
	if into < 0.05 then
		return nil
	end
	local offset = flatten(nearest.Position) - flatten(position) - right * baseShift
	local faceDistance = offset:Dot(-normal) / into
	-- On your middle line, as far along as the planned line meets the face (shifts are measured
	-- from your middle line).
	local column = flatten(position) + direction * (faceDistance + 0.3)
	-- Sideways shifts to try (your line straight over, then a body-width either side), so a
	-- corner or a taller thing next to the obstacle never catches one side of the body.
	-- At a corner the middle of the body can be off the obstacle entirely, so shifts go up to
	-- about a body width, toward the side the obstacle is on first.
	local hitSide = if offset:Dot(right) >= 0 then 1 else -1
	local half = Config.LedgeBodyHalfWidth
	local shifts = { 0, hitSide * (half + 0.1), -hitSide * (half + 0.1), hitSide * (2 * half + 0.1), -hitSide * (2 * half + 0.1) }
	for i, shift in shifts do
		shifts[i] = shift + baseShift
	end

	-- Hands reach LedgeReach above the feet: nothing higher can be climbed. The top is looked for
	-- on your line, else a shift away (at a corner your line can pass beside it).
	local fromY = footY + Config.LedgeReach + 0.5
	local toY = footY + 0.3
	local topY: number? = nil
	for _, shift in shifts do
		topY = self:_topAt(column + right * shift, fromY, toY)
		if topY then
			break
		end
	end
	if not topY then
		self.lastInfo = if airborne then "ledge out of reach" else "too tall: jump to grab it"
		return nil
	end
	local height = topY - footY
	if not airborne and height <= Config.LowerColliderGap + 0.1 then
		return nil -- just a step
	end
	if airborne then
		if height < Config.LedgeAirMin then
			return nil -- feet already over it: you land on it normally
		end
		-- Still rising high enough to clear it anyway? Let the jump do it.
		local vy = root.AssemblyLinearVelocity.Y
		if vy > 0 and footY + vy * vy / (2 * Workspace.Gravity) >= topY + 0.5 then
			return nil
		end
	end
	-- Vault: low and thin, from the ground.
	if not airborne and height <= Config.VaultMaxHeight then
		for _, shift in shifts do
			local line = column + right * shift
			-- The middle of the body must actually go over the obstacle at the same height.
			local over = self:_cast(Vector3.new(line.X, topY + 0.5, line.Z), Vector3.new(0, -1.2, 0))
			if over and math.abs(over.Position.Y - topY) <= 0.6 then
				local depth: number? = nil
				local step = 0.5
				local k = step
				while k <= Config.VaultMaxDepth + step do
					local probe = line + direction * k
					if not self:_cast(Vector3.new(probe.X, topY + 0.5, probe.Z), Vector3.new(0, -1.2, 0)) then
						depth = k
						break
					end
					k += step
				end
				if depth and self:_pathClear(position, direction, right, shift, topY, faceDistance + 0.3 + depth + 1.5) then
					return {
						action = "Vault",
						direction = direction,
						faceDistance = faceDistance,
						topY = topY,
						releaseDistance = faceDistance + 0.3 + depth + 0.6,
						shift = shift,
						part = partName,
					}
				end
			end
		end
	end

	-- Climb / step-up: you end up standing on it, so the whole body must fit on the ledge, and
	-- the way up and over must be clear for the whole body.
	local shift: number? = nil
	for _, candidate in shifts do
		if self:_fits(column + direction * 0.7, right, candidate, topY, fromY, toY)
			and self:_pathClear(position, direction, right, candidate, topY, faceDistance + 1.5)
		then
			shift = candidate
			break
		end
	end
	if not shift then
		self.lastInfo = "too close to a corner or something beside it"
		return nil
	end
	local action: Action = if not airborne and height <= Config.VaultMaxHeight then "StepUp" else "Climb"
	local release = faceDistance + (if action == "StepUp" then 1.4 else 1.3)
	return { action = action, direction = direction, faceDistance = faceDistance, topY = topY, releaseDistance = release, shift = shift, part = partName }
end

function AutoParkour._step(self: AutoParkour, dt: number)
	if self.destroyed then
		return
	end
	if self.phase ~= "Idle" then
		self:_stepAction(dt)
		return
	end

	local mode = self.motor:GetMode()
	-- A front dash counts as sprinting at the dash's speed, in the dash's direction: dashing into
	-- something vaults / climbs / slides it and keeps the dash's momentum.
	local hook = self.dashHook
	local dashing = hook ~= nil and hook.isDashing()
	if dashing then
		mode = if self.humanoid.FloorMaterial ~= Enum.Material.Air then "Ground" else "Air"
	end
	-- A wall run counts as being in the air: a ledge in reach (the top of the wall you're running
	-- up, or one ahead) gets grabbed the same way as jumping at it.
	local wallHook = self.wallRunHook
	local wallRunning = not dashing and wallHook ~= nil and wallHook.isRunning()
	if wallRunning then
		mode = "Air"
	end
	if mode == "Ground" and not dashing then
		local floor = self:_cast(self.root.Position, Vector3.new(0, -6, 0))
		if floor then
			self.standOffset = self.root.Position.Y - floor.Position.Y
		end
	end
	if mode ~= "Ground" and mode ~= "Air" then
		return
	end
	local sinceEnd = os.clock() - self.lastEnd
	if sinceEnd < Config.ParkourCooldown or (self.lastFailed and sinceEnd < Config.ParkourFailCooldown) then
		return
	end
	if self.humanoid.Health <= 0 or self.isBlocked() then
		return
	end
	-- On the ground it's sprint-only; grabbing a ledge you jumped at just needs the keys on it.
	if mode == "Ground" and not self.motor:IsSprinting() and not dashing then
		return
	end
	local move = flatten(self.humanoid.MoveDirection)
	local flat = flatten(self.root.AssemblyLinearVelocity)
	if dashing and hook then
		flat = hook.velocity()
		move = if flat.Magnitude > 0.1 then flat.Unit else move
	end
	if move.Magnitude < 0.5 then
		self.deflectedFor = 0
		return
	end
	local keys = move.Unit
	local speed = flat.Magnitude
	-- How far the body has been pushed off the keys' direction (sliding along something).
	if speed > 2 and flat.Unit:Dot(keys) < DEFLECTED_COS then
		self.deflectedFor += speed * dt
	else
		self.deflectedFor = 0
	end
	local plan: Plan? = nil
	if mode == "Ground" then
		local moving = speed >= self.motor:GetRunSpeed() * Config.ParkourMinSpeedShare
			and flat.Unit:Dot(keys) >= math.cos(math.rad(Config.ParkourMaxAngle))
		if moving then
			plan = self:_plan(keys, speed, false)
		else
			-- Stopped by the obstacle (or starting right next to it): pressed up against it counts.
			plan = self:_plan(keys, 0, false, AGAINST_DISTANCE)
		end
	else
		plan = self:_plan(keys, speed, true)
	end
	if plan and wallRunning and plan.action ~= "Climb" then
		plan = nil -- only a ledge grab takes over a wall run
	end
	if plan then
		self.lastStartMode = if dashing then "Dash" elseif wallRunning then "WallRun" else mode
		if wallRunning and wallHook then
			wallHook.handOff()
		end
		if dashing and hook then
			hook.handOff()
		end
		self:_start(plan, speed)
	end
end

-- ACTIONS ------------------------------------------------------------------------

function AutoParkour._setJumpLock(self: AutoParkour, locked: boolean)
	if self.jumpLocked == locked then
		return
	end
	self.jumpLocked = locked
	self.motor:SetJumpLock("Parkour", locked)
end

function AutoParkour._start(self: AutoParkour, plan: Plan, speed: number)
	local action: Action = plan.action :: any
	self.action = action
	self.direction = plan.direction
	self.startPosition = self.root.Position
	self.startTime = os.clock()
	self.faceDistance = plan.faceDistance
	self.topY = plan.topY
	self.releaseDistance = plan.releaseDistance
	self.shiftLeft = plan.shift
	self.shiftStart = self.root.Position
	self.right = Vector3.new(-plan.direction.Z, 0, plan.direction.X)
	self.progressY = self.root.Position.Y
	self.noProgressFor = 0
	self.stalledFor = 0
	self.wentUnder = false
	self.maxRise = 0
	self.jumpPressAt = -math.huge
	self.counts[action] += 1
	self.lastInfo = action
	local p = self.root.Position
	self.lastDetail = string.format("%s on %s at (%.1f, %.1f, %.1f) top %.1f face %.1f", action, plan.part or "?", p.X, p.Y, p.Z, plan.topY, plan.faceDistance)

	local run = self.motor:GetRunSpeed()
	-- Carried speed (e.g. from a dash) is capped so a move never launches you absurdly fast.
	speed = math.min(speed, Config.MomentumMaxSpeed * self.motor:GetHealthSpeedScale())
	self.entrySpeed = speed
	self:_setJumpLock(true)
	self.motor:Suspend()
	self.humanoid.AutoRotate = false
	self.align.CFrame = CFrame.lookAlong(Vector3.zero, self.direction)
	self.align.Enabled = true
	if action == "Slide" then
		self.phase = "Slide"
		self.speed = math.max(speed, run)
		self.floorY = self.root.Position.Y - self.standOffset
		self:_setSlideBody(true)
		self.slideVelocity.PlaneVelocity = Vector2.new(self.direction.X, self.direction.Z) * self.speed
		self.slideVelocity.Enabled = true
	else
		self.phase = if action == "Climb" then "ClimbUp" else "Over"
		self.speed = if action == "Climb" then speed else math.max(speed, run * Config.VaultMinSpeedShare)
		self.velocity.MaxForce = self.root.AssemblyMass * MAX_ACCELERATION
		self.velocity.VectorVelocity = self.root.AssemblyLinearVelocity
		self.velocity.Enabled = true
	end
	self.character:SetAttribute("Parkour", action)

	local trackName = if action == "StepUp" then "Vault" elseif action == "Climb" then "LedgeClimb" else action
	local track = self.tracks[trackName]
	if track then
		track:Play(0.08)
	end
end

-- Slide body: every normal body part stops colliding and the low SlideCollider takes over; the
-- torso leans back visually. Undone when `on` is false.
function AutoParkour._setSlideBody(self: AutoParkour, on: boolean)
	local useGroup = slideGroupReady()
	if on then
		table.clear(self.savedParts)
		for _, descendant in self.character:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= self.slideCollider then
				table.insert(self.savedParts, { part = descendant, canCollide = descendant.CanCollide, group = descendant.CollisionGroup })
				if useGroup then
					descendant.CollisionGroup = SLIDE_GROUP
				end
				descendant.CanCollide = false
			end
		end
		self.slideCollider.CanCollide = true
		self:_applySlidePose(true)
	else
		for _, saved in self.savedParts do
			if saved.part.Parent then
				if useGroup then
					saved.part.CollisionGroup = saved.group
				end
				saved.part.CanCollide = saved.canCollide
			end
		end
		table.clear(self.savedParts)
		self.slideCollider.CanCollide = false
		self:_applySlidePose(false)
	end
end

-- Visual lean: the torso (and everything on it) drops and leans back; the root doesn't move.
function AutoParkour._applySlidePose(self: AutoParkour, on: boolean)
	local joint = self.rootJoint
	if not joint then
		return
	end
	if on then
		joint.C0 = CFrame.new(0, -Config.SlideVisualDrop, 0) * CFrame.Angles(math.rad(Config.SlideLean), 0, 0) * self.baseC0
	else
		joint.C0 = self.baseC0
	end
end

function AutoParkour._traveled(self: AutoParkour): number
	return flatten(self.root.Position - self.startPosition):Dot(self.direction)
end

-- Never push into a wall: slide along it (same idea as the dash).
function AutoParkour._slideAlongWalls(self: AutoParkour, velocity: Vector3, heights: { number }, dt: number): Vector3
	local position = self.root.Position
	for _ = 1, 2 do
		local speed = velocity.Magnitude
		if speed < 0.1 then
			break
		end
		local reach = velocity / speed * (1.4 + speed * dt)
		for _, y in heights do
			local hit = self:_cast(Vector3.new(position.X, y, position.Z), reach)
			if hit and math.abs(hit.Normal.Y) < 0.7 then
				local normal = flatten(hit.Normal)
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

-- Sideways speed that finishes the "fit on the ledge" shift quickly.
function AutoParkour._lateral(self: AutoParkour, feetY: number): Vector3
	-- Only once the feet are over the top: shifting earlier would push into the obstacle's side.
	if feetY < self.topY - 0.2 then
		return Vector3.zero
	end
	local done = flatten(self.root.Position - self.shiftStart):Dot(self.right)
	local remaining = self.shiftLeft - done
	if math.abs(remaining) < 0.05 then
		return Vector3.zero
	end
	return self.right * math.clamp(remaining / 0.08, -12, 12)
end

function AutoParkour._stepAction(self: AutoParkour, dt: number)
	if self.humanoid.Health <= 0 then
		self:_finish(false)
		return
	end
	self.maxRise = math.max(self.maxRise, self.root.AssemblyLinearVelocity.Y)
	local position = self.root.Position
	local feetY = position.Y - self.standOffset
	local traveled = self:_traveled()
	local elapsed = os.clock() - self.startTime
	local phase = self.phase

	if phase == "Over" then
		if traveled >= self.releaseDistance then
			self:_finish(true)
			return
		end
		if elapsed > MAX_MOVE_TIME or self:_stalled(dt) then
			self.lastInfo = (self.action or "") .. " blocked"
			self:_finish(false)
			return
		end
		local target = self.topY + Config.VaultClearance
		local horizontal = self.speed
		local toFace = self.faceDistance - traveled
		-- Rise so the feet reach the clearance height by the time you reach the face (a smooth
		-- hop up, not a jolt), then hold it over the top.
		local timeLeft = if toFace > 0 then toFace / math.max(horizontal, 1) else 0
		local rise = math.clamp((target - feetY) / math.max(timeLeft, 0.05), -Config.VaultRiseSpeed, Config.VaultRiseSpeed)
		-- Too close to rise in time: ease off (don't stop dead) so the feet clear the edge.
		if feetY < self.topY + 0.1 and toFace < 0.9 then
			horizontal *= Config.VaultLateSpeedShare
		end
		self.velocity.VectorVelocity = self.direction * horizontal + Vector3.yAxis * rise + self:_lateral(feetY)
	elseif phase == "ClimbUp" then
		if elapsed > MAX_MOVE_TIME or self:_cast(position + Vector3.new(0, 2, 0), Vector3.new(0, 1.2, 0)) then
			self.lastInfo = "climb blocked"
			self:_finish(false)
			return
		end
		-- Not actually rising (snagged on something): let go instead of hanging there.
		if position.Y > self.progressY + 0.05 then
			self.progressY = position.Y
			self.noProgressFor = 0
		else
			self.noProgressFor += dt
			if self.noProgressFor > 0.2 then
				self.lastInfo = "climb snagged"
				self:_finish(false)
				return
			end
		end
		if feetY >= self.topY + 0.3 then
			self.phase = "ClimbOver"
			self.overStart = os.clock()
			return
		end
		local gap = self.faceDistance - traveled
		local approach = if gap > 0.7 then math.clamp(self.speed, 8, Config.ClimbApproachMaxSpeed) else 1
		-- Slow down near the top so it doesn't overshoot the edge.
		local rise = math.min(Config.ClimbSpeed, math.max((self.topY + 0.3 - feetY) / 0.05, 6))
		self.velocity.VectorVelocity = self.direction * approach + Vector3.yAxis * rise + self:_lateral(feetY)
	elseif phase == "ClimbOver" then
		if traveled >= self.releaseDistance then
			self:_finish(true)
			return
		end
		if elapsed > MAX_MOVE_TIME + 0.5 or self:_stalled(dt) then
			self.lastInfo = "climb blocked"
			self:_finish(false)
			return
		end
		-- Pulling over the edge never drags on: if something keeps you from moving forward (you
		-- slide sideways along it instead), let go. On top = done; otherwise it was blocked.
		if os.clock() - self.overStart > CLIMB_OVER_MAX_TIME then
			local onTop = feetY >= self.topY - 0.2 and self:_cast(position, Vector3.new(0, -(self.standOffset + 0.6), 0)) ~= nil
			if not onTop then
				self.lastInfo = "climb blocked"
			end
			self:_finish(onTop)
			return
		end
		local hold = math.clamp((self.topY + 0.3 - feetY) / 0.05, -5, 8)
		self.velocity.VectorVelocity = self.direction * Config.ClimbOverSpeed + Vector3.yAxis * hold + self:_lateral(feetY)
	elseif phase == "Slide" then
		self:_stepSlide(dt)
	end
end

-- True once the body has been pushing without moving for a moment.
function AutoParkour._stalled(self: AutoParkour, dt: number): boolean
	local commanded = flatten(self.velocity.VectorVelocity).Magnitude
	local actual = flatten(self.root.AssemblyLinearVelocity).Magnitude
	if commanded > 4 and actual < 1 then
		self.stalledFor += dt
	else
		self.stalledFor = 0
	end
	return self.stalledFor > 0.2
end

-- Room for the whole standing body here: columns across its width and depth, feet to head.
function AutoParkour._canStand(self: AutoParkour): boolean
	local position = flatten(self.root.Position)
	local forward = self.direction
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local baseY = self.root.Position.Y - self.standOffset + Config.LowerColliderGap
	local height = STAND_CLEARANCE - Config.LowerColliderGap
	for _, along in { -0.7, 0, 0.7, 1.4 } do
		for _, side in { -0.9, 0, 0.9 } do
			local at = position + forward * along + right * side
			if not self:_clear(Vector3.new(at.X, baseY, at.Z), Vector3.yAxis, height) then
				return false
			end
		end
	end
	return true
end

function AutoParkour._stepSlide(self: AutoParkour, dt: number)
	local elapsed = os.clock() - self.startTime
	-- Keep the pose (something else may have touched the joint) and the body non-colliding (the
	-- Humanoid may switch parts back on).
	self:_applySlidePose(true)
	for _, saved in self.savedParts do
		if saved.part.CanCollide then
			saved.part.CanCollide = false
		end
	end

	local canStand = self:_canStand()
	if not canStand then
		self.wentUnder = true
	end
	-- Slide-jump: Space pressed during this slide (or just before it) jumps out once you've cleared
	-- what you slid under. Never before: that would jump into the overhang.
	local slideJump = self.jumpPressAt >= self.startTime - Config.SlideJumpWindow
	if slideJump and canStand and (self.wentUnder or elapsed >= Config.SlideMinTime + 0.25) then
		self:_finish(true)
		self.motor:BufferJump(Config.MoveJumpLandWindow)
		return
	end
	-- Stand up once there's room, after a minimum slide (sooner if it never went under anything).
	if canStand and elapsed >= Config.SlideMinTime and (self.wentUnder or elapsed >= Config.SlideMinTime + 0.25) then
		self:_finish(true)
		return
	end
	if elapsed > Config.SlideMaxTime and canStand then
		self:_finish(true)
		return
	end

	-- Steer with the keys.
	local move = flatten(self.humanoid.MoveDirection)
	if move.Magnitude > 0.1 then
		local current = self.direction
		local wanted = move.Unit
		local angle = math.acos(math.clamp(current:Dot(wanted), -1, 1))
		local maxTurn = math.rad(Config.SlideSteerRate) * dt
		if angle > 1e-3 then
			local blended = current:Lerp(wanted, math.min(maxTurn / angle, 1))
			if blended.Magnitude > 1e-3 then
				self.direction = blended.Unit
				self.align.CFrame = CFrame.lookAlong(Vector3.zero, self.direction)
			end
		end
	end

	-- Friction, but never so slow you get stuck under something.
	self.speed = math.max(self.speed - Config.SlideFriction * dt, self.motor:GetWalkSpeed())
	local footY = self.root.Position.Y - self.standOffset
	local heights = { footY + Config.LowerColliderGap + 0.2, footY + Config.LowerColliderGap + 1.0 }
	local horizontal = self:_slideAlongWalls(self.direction * self.speed, heights, dt)
	self.slideVelocity.PlaneVelocity = Vector2.new(horizontal.X, horizontal.Z)
end

function AutoParkour._finish(self: AutoParkour, completed: boolean)
	if self.phase == "Idle" then
		return
	end
	local action = self.action
	local wasSlide = self.phase == "Slide"
	self.phase = "Idle"
	self.lastEnd = os.clock()
	-- A move that got blocked waits a little longer before trying again (no retry loops).
	self.lastFailed = not completed
	self.velocity.Enabled = false
	self.slideVelocity.Enabled = false
	self.align.Enabled = false
	if wasSlide then
		self:_setSlideBody(false)
	end
	self.humanoid.AutoRotate = true
	self.character:SetAttribute("Parkour", nil)
	self:_setJumpLock(false)
	for name, track in self.tracks do
		if track.IsPlaying and (name ~= "Vault" or not completed) then
			track:Stop(0.1)
		end
	end

	-- Momentum: vaults and slides keep their speed. Never
	-- leave moving upward.
	-- A climb comes out at your entry speed (a sprint stays a sprint), at least ClimbExitSpeed,
	-- never above run speed.
	local run = self.motor:GetRunSpeed()
	local speed = if action == "Climb" then math.min(math.max(Config.ClimbExitSpeed, self.entrySpeed), run) else self.speed
	if not completed and action ~= "Slide" then
		speed = math.min(speed, flatten(self.root.AssemblyLinearVelocity).Magnitude)
	end
	local carry = self.direction * speed
	self.lastEndSpeed = speed
	local vy = math.min(self.root.AssemblyLinearVelocity.Y, 0)
	self.root.AssemblyLinearVelocity = Vector3.new(carry.X, vy, carry.Z)
	self.motor:ApplyMomentum(carry)
	self.motor:Resume()
	if completed and os.clock() - self.jumpPressAt <= Config.MoveJumpBuffer then
		self.motor:BufferJump(Config.MoveJumpLandWindow)
	end
	if completed then
		self.lastInfo = (action or "") .. " done"
	end
	self.action = nil
end

-- Ends parkour early (e.g. getting hit, once combat exists). A slide under something keeps
-- going until there's room to stand.
function AutoParkour.Cancel(self: AutoParkour)
	if self.phase == "Slide" and not self:_canStand() then
		return
	end
	self:_finish(false)
end

function AutoParkour.Destroy(self: AutoParkour)
	if self.destroyed then
		return
	end
	self:_finish(false)
	self.destroyed = true
	self:_setJumpLock(false)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.velocity:Destroy()
	self.slideVelocity:Destroy()
	self.align:Destroy()
	self.attachment:Destroy()
	self.slideCollider:Destroy()
	if active[self.character] == self then
		active[self.character] = nil
	end
end

return AutoParkour
