--!strict
-- Lantern (ModuleScript)
-- Location: ReplicatedStorage > Movement > Lantern
--
-- The Moth race's lantern and wings, on Left Ctrl. Runs on the client next to CharacterMotor (the
-- player owns their character's physics, and the thrown lantern is simulated here too so it feels
-- instant). Only works while the character's "Race" attribute is "Moth". Numbers: MovementConfig
-- "MOTH: LANTERN + WINGS".
--
--   TAP  (lantern on the hip)       -> WING FLIGHT: ~WingFlightDistance studs where the camera looks,
--                                      then WingFlightKeep of the speed carries on.
--   HOLD (lantern on the hip)       -> take it in hand and charge; RELEASE throws it at the crosshair
--                                      (screen centre, shift lock or not), faster and farther the
--                                      longer you held. While charging you face the aim and see the
--                                      exact path (glowing dots) and where it lands (ring).
--   PRESS while it's in the air     -> it stops and hangs there (once per throw).
--   HOLD (lantern not on you)       -> fly: to an opponent the lantern tagged, or freely inside a
--                                      hanging lantern's light. Letting go ends it.
--   M1 during any flight            -> ends it (MovementController then throws the M1).
-- Touching the lantern puts it back on the hip; while flying that gives a burst of speed. After a grab
-- it can't be thrown for LanternGrabCooldown.
--
-- The throw is a projectile run in fixed steps by LanternPhysics: the preview and the real flight
-- use the same steps, so it lands on the ring. A direct hit on an opponent: LanternDamage + tag, and
-- it bounces back toward you. The first impact of a throw flashes (LanternFx.burst): opponents within
-- LanternBurstRadius that the flash can see are tagged (no damage). The server checks every hit.
--
-- Visuals: the server builds the lantern (LanternServer) and welds it to the hip / hand. While it's
-- out, this client HIDES the server copy (LocalTransparencyModifier only; it's never moved from here,
-- because moving it while it's still welded drags the character) and draws its own copy with no lag.
-- Other players see it through LanternViewer, which replays the same arc.
-- Attributes: "Flying" = Wings / Free / Tag, "LanternState" = Hip / Charging / Thrown / Suspended / Dropped.
-- Animations (MothAnimations): MothWingFlight, MothFly (loop), LanternCharge (loop), LanternThrow,
-- LanternSuspend.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
local AnimConfig = require(script.Parent.AnimationConfig)
local AnimationLibrary = require(script.Parent.AnimationLibrary)
local CharacterMotor = require(script.Parent.CharacterMotor)
local Stamina = require(script.Parent.Stamina)
local Perf = require(script.Parent.Perf)
local Sfx = require(script.Parent.Sfx)
local LanternPhysics = require(script.Parent.LanternPhysics)
local LanternFx = require(script.Parent.LanternFx)

local RACE = "Moth"
-- Where the lantern sits (must match LanternServer): in the right hand while charging (arm space),
-- on the right hip otherwise (torso space).
local HAND_OFFSET = CFrame.new(0, -1.72, 0)
local HIP_OFFSET = CFrame.new(1.18, -0.95, -0.05) * CFrame.Angles(0, 0, math.rad(-8))
-- Where a throw leaves from, in the (flat) facing of the root: right shoulder, a bit in front.
local THROW_ORIGIN = Vector3.new(1.0, 0.8, -1.2)
-- Throw preview while charging: glowing dots along the predicted flight, a ring where it lands.
local PREVIEW_SPACING = 2.2 -- studs between dots
local PREVIEW_MAX_BALLS = 48
local PREVIEW_COLOR = Color3.fromRGB(80, 200, 255)
local PREVIEW_HIT_COLOR = Color3.fromRGB(255, 85, 75) -- ring colour when the path ends on someone
local SYNC_INTERVAL = 1 / 20
-- Most fixed flight steps run in one frame (a long hitch just slows the lantern down a little).
local MAX_STEPS_PER_FRAME = 8
-- A lantern that falls this far below the lowest allowed height comes back to the hip.
local VOID_MARGIN = 20
-- How long to wait for the server to put the lantern back on the hip / hand before showing it anyway.
local MOUNT_WAIT = 2
local FORWARD_KEY_MIN = 0.3
local TAG_BRAKE = 9
local TAG_MIN_CLOSING = 6
local TAG_ARRIVE_SLACK = 0.3
local TAG_MAX_LEAD = 0.3
local TARGET_VEL_SMOOTHING = 0.5
-- The flight never rises faster than this when it starts on the ground (studs/s), so a flat camera
-- doesn't scrape the floor.
local MIN_TAKEOFF_LIFT = 6

export type LanternState = "Hip" | "Charging" | "Thrown" | "Suspended" | "Dropped"
export type FlightKind = "Wings" | "Free" | "Tag"

local ANIMS = {
	Rest = "MothWings", -- wings / antennae resting loop, under everything (Core priority)
	WingFlight = "MothWingFlight",
	Fly = "MothFly",
	Charge = "LanternCharge",
	Throw = "LanternThrow",
	Suspend = "LanternSuspend",
}

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A CFrame for a Cylinder part (round faces on its local X axis) lying flush on a surface.
local function cylinderSurfaceCFrame(position: Vector3, normal: Vector3, thickness: number): CFrame
	local n = if normal.Magnitude > 1e-4 then normal.Unit else Vector3.yAxis
	local center = position + n * (thickness * 0.5 + 0.015)
	local upRef = if math.abs(n.Y) > 0.85 then Vector3.zAxis else Vector3.yAxis
	local localZ = n:Cross(upRef).Unit
	local localY = localZ:Cross(n).Unit
	return CFrame.fromMatrix(center, n, localY, localZ)
end

local function turnTowards(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local dot = math.clamp(from:Dot(to), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle then
		return to
	end
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-4 then
		axis = if math.abs(from.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	end
	return CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(from).Unit
end

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

local function remote(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return if folder then folder:FindFirstChild(name) else nil
end

local function characterOf(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function cameraLook(root: BasePart): Vector3
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	return if look.Magnitude > 1e-3 then look.Unit else -Vector3.zAxis
end

local Lantern = {}
Lantern.__index = Lantern

type LanternData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	stamina: Stamina.Stamina,
	isBlocked: () -> boolean,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	animator: Animator?,
	tracks: { [string]: AnimationTrack },
	connections: { RBXScriptConnection },
	destroyed: boolean,

	pressing: boolean,
	pressAt: number,
	holdHandled: boolean,
	pressSuspended: boolean,

	state: LanternState,
	chargeStart: number,
	-- The lantern while it's out: where it is and how it moves.
	position: Vector3,
	lanternVelocity: Vector3,
	resting: boolean,
	-- The current throw (projectile): start values, fixed-step flight time, leftover frame time.
	throwOrigin: Vector3,
	throwVelocity: Vector3,
	throwGravity: number,
	flightTime: number,
	stepCarry: number,
	casts: LanternPhysics.Casts?,
	castsAt: number,
	throwAt: number,
	canSuspend: boolean,
	hitThisThrow: boolean,
	burstDone: boolean,
	suspendedUntil: number,
	grabbedAt: number,
	-- Local visuals.
	serverModel: Model?,
	localCopy: Model?,
	mountWaitUntil: number,
	preview: Folder?,
	previewBalls: { BasePart },
	previewEnd: BasePart?,
	facingAim: boolean,
	faceToken: number,
	aimPointForTest: Vector3?,
	lastSync: number,
	lastSyncPos: Vector3,

	tagTarget: Model?,
	tagUntil: number,
	burstTagged: { Model },

	flight: FlightKind?,
	heading: Vector3,
	speed: number,
	flightStart: number,
	wingEndAt: number,
	lastWingFlight: number,
	targetLastPos: Vector3,
	targetVel: Vector3,
	lastVelocity: Vector3,

	lastInfo: string,
	lastFlightEnd: string,
	lastThrowSpeed: number,
	lastLanding: Vector3?,
	throws: number,
}

export type Lantern = typeof(setmetatable({} :: LanternData, Lantern))

local active: { [Model]: Lantern } = {}

function Lantern.new(
	character: Model,
	motor: CharacterMotor.CharacterMotor,
	stamina: Stamina.Stamina,
	isBlocked: () -> boolean
): Lantern
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "LanternFlightAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "LanternFlightVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "LanternFlightFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = 60
	align.Enabled = false
	align.Parent = root

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		stamina = stamina,
		isBlocked = isBlocked,
		attachment = attachment,
		velocity = velocity,
		align = align,
		animator = animator,
		tracks = {} :: { [string]: AnimationTrack },
		connections = {},
		destroyed = false,

		pressing = false,
		pressAt = 0,
		holdHandled = true,
		pressSuspended = false,

		state = "Hip" :: LanternState,
		chargeStart = 0,
		position = root.Position,
		lanternVelocity = Vector3.zero,
		resting = false,
		throwOrigin = root.Position,
		throwVelocity = Vector3.zero,
		throwGravity = LanternPhysics.gravity(),
		flightTime = 0,
		stepCarry = 0,
		casts = nil,
		castsAt = -math.huge,
		throwAt = -math.huge,
		canSuspend = false,
		hitThisThrow = false,
		burstDone = false,
		suspendedUntil = 0,
		grabbedAt = -math.huge,
		serverModel = nil,
		localCopy = nil,
		mountWaitUntil = 0,
		preview = nil,
		previewBalls = {},
		previewEnd = nil,
		facingAim = false,
		faceToken = 0,
		aimPointForTest = nil,
		lastSync = 0,
		lastSyncPos = root.Position,

		tagTarget = nil,
		tagUntil = 0,
		burstTagged = {},

		flight = nil,
		heading = -Vector3.zAxis,
		speed = 0,
		flightStart = 0,
		wingEndAt = 0,
		lastWingFlight = -math.huge,
		targetLastPos = Vector3.zero,
		targetVel = Vector3.zero,
		lastVelocity = Vector3.zero,

		lastInfo = "",
		lastFlightEnd = "",
		lastThrowSpeed = 0,
		lastLanding = nil,
		throws = 0,
	}, Lantern)

	table.insert(
		self.connections,
		RunService.PreSimulation:Connect(function(dt: number)
			if self.flight then
				self:_stepFlight(dt)
			end
		end)
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(dt: number)
			if Perf.enabled then
				local t0 = os.clock()
				self:_renderStep(dt)
				Perf.add("Lantern", os.clock() - t0)
			else
				self:_renderStep(dt)
			end
		end)
	)
	table.insert(
		self.connections,
		humanoid.Died:Connect(function()
			self:Destroy()
		end)
	)

	character:SetAttribute("LanternState", "Hip")
	active[character] = self
	-- Wings resting loop while this character is a Moth (the race can change at runtime).
	-- The Animator only moves joints that exist when a track is loaded, so wait for the wing / antenna
	-- Motor6Ds (the server adds them) before loading the rest loop.
	local function wingsReady(): boolean
		local torso = character:FindFirstChild("Torso")
		local head = character:FindFirstChild("Head")
		return torso ~= nil and head ~= nil and torso:FindFirstChild("LeftHindwing") ~= nil
			and head:FindFirstChild("LeftAntenna") ~= nil
	end
	local function updateRest()
		if self.destroyed then
			return
		end
		if self:IsMoth() then
			local t0 = os.clock()
			while not wingsReady() and os.clock() - t0 < 10 and not self.destroyed do
				task.wait(0.1)
			end
			if self.destroyed or not self:IsMoth() then
				return
			end
			-- Reload so the track sees the wing joints even if it was loaded before them.
			local old = self.tracks.Rest
			if old then
				old:Stop(0)
				old:Destroy()
				local tracks: { [string]: AnimationTrack? } = self.tracks
				tracks.Rest = nil
			end
			self:_play("Rest")
		else
			self:_stop("Rest")
		end
	end
	table.insert(self.connections, character:GetAttributeChangedSignal("Race"):Connect(updateRest))
	task.defer(updateRest)
	return self
end

function Lantern.Get(character: Model): Lantern?
	return active[character]
end

-- INFO (debug overlay, tests) --------------------------------------------------

function Lantern.IsMoth(self: Lantern): boolean
	return self.character:GetAttribute("Race") == RACE
end

-- True while flying (a flight owns the body).
function Lantern.IsBusy(self: Lantern): boolean
	return self.flight ~= nil
end

function Lantern.GetFlight(self: Lantern): FlightKind?
	return self.flight
end

function Lantern.GetState(self: Lantern): LanternState
	return self.state
end

function Lantern.IsResting(self: Lantern): boolean
	return self.resting
end

function Lantern.GetPosition(self: Lantern): Vector3
	if self.state == "Hip" or self.state == "Charging" then
		return self:_handPosition()
	end
	return self.position
end

function Lantern.GetSpeed(self: Lantern): number
	return self.speed
end

function Lantern.GetHeading(self: Lantern): Vector3
	return self.heading
end

function Lantern.GetTurnRate(self: Lantern): number
	local span = math.max(Config.FlyMaxSpeed - Config.FlySlowSpeed, 1e-3)
	local t = math.clamp((self.speed - Config.FlySlowSpeed) / span, 0, 1)
	return Config.FlySharpTurnRate + (Config.FlyWideTurnRate - Config.FlySharpTurnRate) * t
end

function Lantern.GetTagTarget(self: Lantern): Model?
	if self.tagTarget and os.clock() < self.tagUntil then
		return self.tagTarget
	end
	return nil
end

function Lantern.GetGrabCooldown(self: Lantern): number
	return math.max(0, Config.LanternGrabCooldown - (os.clock() - self.grabbedAt))
end

-- The Moth's movement cooldown for the HUD: (seconds left, full length). The wing flight's cooldown
-- while it runs, else the no-throw time after grabbing the lantern. (0, 1) when ready.
function Lantern.GetMothCooldown(self: Lantern): (number, number)
	-- A wing flight can't start again until the current one is over AND its cooldown has passed.
	local since = os.clock() - self.lastWingFlight
	local total = math.max(Config.WingFlightCooldown, Config.WingFlightTime)
	if since < total then
		return total - since, total
	end
	local grab = self:GetGrabCooldown()
	if grab > 0 then
		return grab, Config.LanternGrabCooldown
	end
	return 0, 1
end

-- 0..1: how charged the throw is right now (0 if not charging).
function Lantern.GetCharge(self: Lantern): number
	if self.state ~= "Charging" then
		return 0
	end
	return math.clamp((os.clock() - self.chargeStart) / math.max(Config.LanternChargeTime, 1e-3), 0, 1)
end

function Lantern.GetLastInfo(self: Lantern): string
	return self.lastInfo
end

-- Why the last flight ended: "done", "released", "stamina", "arrived", "timeout", "lost", "lantern",
-- "grab", "m1", "cancel".
function Lantern.GetLastFlightEnd(self: Lantern): string
	return self.lastFlightEnd
end

function Lantern.GetLastThrowSpeed(self: Lantern): number
	return self.lastThrowSpeed
end

function Lantern.GetThrows(self: Lantern): number
	return self.throws
end

-- ANIMATION ----------------------------------------------------------------------

function Lantern._track(self: Lantern, key: string): AnimationTrack?
	local cached = self.tracks[key]
	if cached then
		return cached
	end
	local name = ANIMS[key]
	local animator = self.animator
	if not name or not animator or not animationExists(name) then
		return nil
	end
	local animation = AnimationLibrary.Get(name)
	if not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = if key == "Rest" then Enum.AnimationPriority.Core else Enum.AnimationPriority.Action
	self.tracks[key] = track
	return track
end

function Lantern._play(self: Lantern, key: string)
	local track = self:_track(key)
	if track and not (track.Looped and track.IsPlaying) then
		track:Play(0, 1, 1)
	end
end

function Lantern._stop(self: Lantern, key: string)
	local track = self.tracks[key]
	if track and track.IsPlaying then
		track:Stop(0)
	end
end

-- INPUT ------------------------------------------------------------------------

function Lantern.Press(self: Lantern)
	if self.pressing then
		return
	end
	self.pressing = true
	self.pressAt = os.clock()
	self.holdHandled = false
	self.pressSuspended = false
	-- In the air: the press itself suspends it (a hold can still turn into a flight after).
	if self:IsMoth() and self:_isAirborne() and self.canSuspend then
		self:Suspend()
		self.pressSuspended = true
	end
end

-- Release (also call on focus loss so the key can't stick).
function Lantern.Release(self: Lantern)
	if not self.pressing then
		return
	end
	self.pressing = false
	if self.state == "Charging" then
		self:_throw(nil)
	elseif self.flight == "Free" or self.flight == "Tag" then
		self:_endFlight("released")
	elseif not self.holdHandled and not self.pressSuspended then
		self:_tap()
	end
	self.holdHandled = true
end

-- M1 pressed. Ends any flight; returns true if it did (the caller then does the M1).
function Lantern.OnM1(self: Lantern): boolean
	if self.flight then
		self:_endFlight("m1")
		return true
	end
	return false
end

-- Cancels charging (e.g. on dash, jump, M1). Returns true if it was charging.
function Lantern.CancelCharge(self: Lantern): boolean
	if self.state ~= "Charging" then
		return false
	end
	self.state = "Hip"
	self.pressing = false
	self.holdHandled = true
	self.character:SetAttribute("LanternCharging", nil)
	self.character:SetAttribute("LanternState", "Hip")
	self:_showPreview(false)
	self:_releaseFacing()
	self:_stop("Charge")
	self.lastInfo = "charge cancelled"
	self:_announce()
	return true
end

function Lantern._tap(self: Lantern)
	if self.destroyed or self.humanoid.Health <= 0 then
		return
	end
	if not self:IsMoth() then
		self.lastInfo = "not a Moth"
		return
	end
	if self.state == "Hip" then
		self:WingFlight()
	elseif self.state == "Suspended" then
		self.lastInfo = "hanging: hold Ctrl inside its light to fly"
	else
		self.lastInfo = "no lantern: go grab it"
	end
end

-- Held past the tap time (once per press).
function Lantern._hold(self: Lantern)
	if not self:IsMoth() then
		self.lastInfo = "not a Moth"
		return
	end
	if self.state == "Hip" then
		if self.flight then
			return
		end
		local cooldown = self:GetGrabCooldown()
		if cooldown > 0 then
			self.lastInfo = string.format("just grabbed it: throw in %.1fs", cooldown)
			return
		end
		self:_startCharge()
		self:_faceAim()
	elseif not self.flight then
		self:_tryStartFlight()
	end
end

-- LANTERN ------------------------------------------------------------------------

function Lantern._startCharge(self: Lantern)
	self.state = "Charging"
	self.chargeStart = os.clock()
	self.lastInfo = "charging"
	self.character:SetAttribute("LanternCharging", true)
	self:_announce()
	self:_play("Charge")
	self:_showPreview(true)
end


function Lantern._throwSpeed(power: number): number
	return Config.LanternThrowSpeedMin + (Config.LanternThrowSpeedMax - Config.LanternThrowSpeedMin) * power
end

function Lantern._throwRange(power: number): number
	return Config.LanternThrowRangeMin + (Config.LanternThrowRangeMax - Config.LanternThrowRangeMin) * power
end

-- Fresh cast params for the lantern's flight (the character list changes as people spawn / die).
function Lantern._flightCasts(self: Lantern): LanternPhysics.Casts
	local now = os.clock()
	local casts = self.casts
	if casts and now - self.castsAt < 0.25 then
		return casts
	end
	local extra: { Instance } = {}
	if self.localCopy then
		table.insert(extra, self.localCopy)
	end
	if self.preview then
		table.insert(extra, self.preview)
	end
	local fresh = LanternPhysics.params(self.character, extra, true)
	self.casts = fresh
	self.castsAt = now
	return fresh
end

-- Where a throw leaves from: the right shoulder, a bit in front (pulled back if a wall is that close).
function Lantern._aimOrigin(self: Lantern): Vector3
	local root = self.root
	local look = flatten(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else -Vector3.zAxis
	local frame = CFrame.lookAt(root.Position, root.Position + look)
	local wanted = frame:PointToWorldSpace(THROW_ORIGIN)
	local hit = Workspace:Raycast(root.Position, wanted - root.Position, self:_flightCasts().world)
	if hit then
		return root.Position + (wanted - root.Position).Unit * math.max(hit.Distance - 0.6, 0)
	end
	return wanted
end

-- The point under the CROSSHAIR (the middle of the screen, shift lock or not). The ray starts level
-- with the character, so nothing between the camera and you (a wall behind you) catches it.
-- Characters count (aim at someone = aim at their body). Returns (point, hitSomething).
function Lantern._crosshairPoint(self: Lantern): (Vector3, boolean)
	if self.aimPointForTest then
		return self.aimPointForTest, true
	end
	local camera = Workspace.CurrentCamera
	if not camera or camera.ViewportSize.X <= 0 then
		return self.root.Position + cameraLook(self.root) * Config.LanternThrowRangeMax, false
	end
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X * 0.5, size.Y * 0.5)
	local dir = ray.Direction.Unit
	local skip = math.max(0, (self.root.Position - ray.Origin):Dot(dir))
	local start = ray.Origin + dir * skip
	local reach = Config.LanternThrowRangeMax + 150
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { self.character }
	if self.localCopy then
		table.insert(ignore, self.localCopy)
	end
	if self.preview then
		table.insert(ignore, self.preview)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(start, dir * reach, params)
	if hit then
		return hit.Position, true
	end
	return start + dir * reach, false
end

-- The throw for a given charge: (origin, launch velocity, speed). It passes through the crosshair
-- point, or the point that far along the line from the origin to it if it's farther than the range.
function Lantern._plan(self: Lantern, power: number): (Vector3, Vector3, number)
	local origin = self:_aimOrigin()
	local point = self:_crosshairPoint()
	local range = Lantern._throwRange(power)
	local toPoint = point - origin
	if toPoint.Magnitude > range then
		point = origin + toPoint.Unit * range
	elseif toPoint.Magnitude < 1 then
		point = origin + flatten(self.root.CFrame.LookVector).Unit * 5
	end
	local speed = Lantern._throwSpeed(power)
	return origin, LanternPhysics.solve(origin, point, speed, LanternPhysics.gravity()), speed
end

-- Throws at the crosshair (or along `direction`, for tests). `charge` 0..1 overrides the hold.
function Lantern._throw(self: Lantern, direction: Vector3?, charge: number?)
	if self.state ~= "Charging" and self.state ~= "Hip" then
		return
	end
	local power = charge or self:GetCharge()
	local origin, v0, speed = self:_plan(power)
	if direction then
		local dir = if direction.Magnitude > 1e-3 then direction.Unit else -Vector3.zAxis
		v0 = dir * speed
	end
	self:_showPreview(false)
	self.throwOrigin = origin
	self.throwVelocity = v0
	self.throwGravity = LanternPhysics.gravity()
	self.flightTime = 0
	self.stepCarry = 0
	self.casts = nil
	self.position = origin
	self.lanternVelocity = v0
	self.lastThrowSpeed = speed
	self.lastLanding = nil
	self.state = "Thrown"
	self.resting = false
	self.throwAt = os.clock()
	self.canSuspend = true
	self.hitThisThrow = false
	self.burstDone = false
	table.clear(self.burstTagged)
	self.throws += 1
	self.lastInfo = string.format("thrown (%d%% power)", math.floor(power * 100 + 0.5))
	self:_stop("Charge")
	self:_play("Throw")
	self:_faceAim()
	self:_releaseFacing(0.3)
	-- The throw animation keeps the charge's movement rule for a moment.
	self.character:SetAttribute("LanternCharging", true)
	task.delay(0.35, function()
		if not self.destroyed and self.state ~= "Charging" then
			self.character:SetAttribute("LanternCharging", nil)
		end
	end)
	self:_showLocalCopy(true)
	self:_announce()
end

function Lantern._showPreview(self: Lantern, show: boolean)
	if not show then
		if self.preview then
			self.preview:Destroy()
			self.preview = nil
		end
		table.clear(self.previewBalls)
		self.previewEnd = nil
		return
	end
	if not self.preview then
		local folder = Instance.new("Folder")
		folder.Name = "LanternThrowPreview"
		for i = 1, PREVIEW_MAX_BALLS do
			local ball = Instance.new("Part")
			ball.Name = "Dot" .. i
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(0.45, 0.45, 0.45)
			ball.Anchored = true
			ball.CanCollide = false
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CastShadow = false
			ball.Material = Enum.Material.Neon
			ball.Color = PREVIEW_COLOR
			ball.Transparency = 1
			ball.Parent = folder
			table.insert(self.previewBalls, ball)
		end
		local ring = Instance.new("Part")
		ring.Name = "Target"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.15, 5, 5)
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = PREVIEW_COLOR
		ring.Transparency = 1
		ring.Parent = folder
		self.previewEnd = ring
		folder.Parent = Workspace.CurrentCamera or Workspace
		self.preview = folder
	end
end

-- While charging the body turns to face where the crosshair points (flat), with or without shift
-- lock, so the throw always leaves from in front of you. Uses the flight's AlignOrientation (no
-- flight can run while charging).
function Lantern._faceAim(self: Lantern)
	if self.flight then
		return
	end
	local look = Vector3.new(cameraLook(self.root).X, 0, cameraLook(self.root).Z)
	if self.aimPointForTest then
		look = Vector3.new(self.aimPointForTest.X - self.root.Position.X, 0, self.aimPointForTest.Z - self.root.Position.Z)
	end
	if look.Magnitude < 1e-3 then
		return
	end
	if not self.facingAim then
		self.facingAim = true
		self.humanoid.AutoRotate = false
		self.align.Enabled = true
	end
	self.faceToken += 1
	self:_face(look.Unit)
end

-- Stops facing the aim, now or after `delay` seconds (so the throw animation finishes facing it).
function Lantern._releaseFacing(self: Lantern, delay: number?)
	if not self.facingAim then
		return
	end
	local token = self.faceToken
	local function release()
		if self.destroyed or not self.facingAim or self.faceToken ~= token or self.flight then
			return
		end
		self.facingAim = false
		self.align.Enabled = false
		-- Another move that took the body (dash, parkour...) handles AutoRotate itself.
		if self.motor:GetMode() ~= "Suspended" then
			self.humanoid.AutoRotate = true
		end
	end
	if delay and delay > 0 then
		task.delay(delay, release)
	else
		release()
	end
end

-- While charging: the exact predicted flight for the current charge (same steps as the real throw).
function Lantern._updatePreview(self: Lantern)
	self:_showPreview(true)
	local ring = self.previewEnd
	if not self.preview or not ring then
		return
	end
	self:_faceAim()
	local origin, v0 = self:_plan(self:GetCharge())
	local points, hit = LanternPhysics.predict(origin, v0, LanternPhysics.gravity(), self:_flightCasts(), Config.LanternMaxFlightTime)

	-- Dots every PREVIEW_SPACING studs along the path.
	local used = 0
	local sinceDot = PREVIEW_SPACING * 0.5
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local seg = (b - a).Magnitude
		local along = 0
		while sinceDot + (seg - along) >= PREVIEW_SPACING and used < #self.previewBalls do
			along += PREVIEW_SPACING - sinceDot
			sinceDot = 0
			used += 1
			local ball = self.previewBalls[used]
			ball.CFrame = CFrame.new(a:Lerp(b, along / math.max(seg, 1e-4)))
			ball.Transparency = 0.15 + 0.5 * (used / #self.previewBalls)
		end
		sinceDot += seg - along
		if used >= #self.previewBalls then
			break
		end
	end
	for i = used + 1, #self.previewBalls do
		self.previewBalls[i].Transparency = 1
	end

	-- The ring: flush on the surface it lands on, or facing you on the person it would hit.
	if hit then
		local onSomeone = hit.kind == "Character"
		local normal = if onSomeone then (origin - hit.position) else hit.normal
		local contact = if onSomeone then hit.position else hit.position - hit.normal * LanternPhysics.WORLD_RADIUS
		ring.CFrame = cylinderSurfaceCFrame(contact, normal, ring.Size.X)
		ring.Color = if onSomeone then PREVIEW_HIT_COLOR else PREVIEW_COLOR
		ring.Transparency = 0.3
	else
		ring.Transparency = 1
	end
end


-- Test helper: aim at this world point instead of the mouse cursor (nil = the cursor again).
function Lantern.SetAimForTest(self: Lantern, point: Vector3?)
	self.aimPointForTest = point
end

-- Test helper: throw right away with a given power (skips the hold).
function Lantern.ThrowForTest(self: Lantern, direction: Vector3?, charge: number)
	if self.state == "Hip" then
		self.state = "Charging"
	end
	self:_throw(direction, charge)
end

function Lantern.Suspend(self: Lantern): boolean
	if not self:_isAirborne() or not self.canSuspend then
		return false
	end
	self.state = "Suspended"
	self.lanternVelocity = Vector3.zero
	self.canSuspend = false
	-- A hung lantern doesn't flash when it later drops and lands.
	self.burstDone = true
	self.suspendedUntil = os.clock() + Config.LanternSuspendTime
	self.lastInfo = "suspended"
	self:_play("Suspend")
	self:_announce()
	return true
end

-- Back on the hip (touched it, or it fell out of the world).
function Lantern._grab(self: Lantern, reason: string?)
	local burst = self.flight ~= nil and reason == nil
	self.state = "Hip"
	self.resting = false
	self.lanternVelocity = Vector3.zero
	self.grabbedAt = if reason then -math.huge else os.clock()
	self.lastInfo = reason or "grabbed"
	-- The copy stays on the hip until the server has the lantern welded there again.
	self.mountWaitUntil = os.clock() + MOUNT_WAIT
	self:_announce()
	if burst and self.flight == "Tag" then
		-- Grabbed on the way to a tagged opponent: keep flying to them, faster.
		self.speed = math.min(self.speed + Config.LanternGrabBurst, Config.LanternGrabBurstMax)
		self.lastFlightEnd = "grab (kept flying)"
	elseif burst then
		local v = self.lastVelocity
		local dir = if v.Magnitude > 1e-3 then v.Unit else self.heading
		local speed = math.min(v.Magnitude + Config.LanternGrabBurst, Config.LanternGrabBurstMax)
		self:_endFlight("grab", dir * speed)
	end
end

function Lantern._isAirborne(self: Lantern): boolean
	return self.state == "Thrown" or (self.state == "Dropped" and not self.resting)
end

function Lantern._handPosition(self: Lantern): Vector3
	local arm = self.character:FindFirstChild("Right Arm")
	if arm and arm:IsA("BasePart") then
		return (arm.CFrame * HAND_OFFSET).Position
	end
	return self.root.Position + self.root.CFrame.RightVector * 1.5 - Vector3.new(0, 1, 0)
end

-- Where the lantern hangs on the body right now (hip, or hand while charging).
function Lantern._mountCFrame(self: Lantern): CFrame
	if self.state == "Charging" then
		local arm = self.character:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			return arm.CFrame * HAND_OFFSET
		end
	end
	local torso = self.character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso.CFrame * HIP_OFFSET
	end
	return self.root.CFrame * HIP_OFFSET
end

-- LOCAL VISUALS --------------------------------------------------------------------

function Lantern._serverModel(self: Lantern): Model?
	if self.serverModel and self.serverModel.Parent then
		return self.serverModel
	end
	local model = self.character:FindFirstChild("Lantern")
	if model and model:IsA("Model") then
		self.serverModel = model
		return model
	end
	local myUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
	if myUserId then
		for _, child in Workspace:GetChildren() do
			if child:IsA("Model") and child.Name == "Lantern" and child:GetAttribute("OwnerUserId") == myUserId then
				self.serverModel = child
				return child
			end
		end
	end
	return nil
end

-- True once the server has the lantern welded where the state says (hip / hand).
function Lantern._serverMounted(self: Lantern): boolean
	local model = self:_serverModel()
	local core = if model then model.PrimaryPart else nil
	if not model or not core or model.Parent ~= self.character then
		return false
	end
	local weld = core:FindFirstChild("HoldWeld")
	if not weld or not weld:IsA("Weld") or not weld.Enabled then
		return false
	end
	local wanted = if self.state == "Charging" then "Right Arm" else "Torso"
	return weld.Part0 ~= nil and weld.Part0.Name == wanted
end

-- Shows (or removes) this client's own copy and hides the server lantern while the copy is up.
function Lantern._showLocalCopy(self: Lantern, show: boolean)
	local serverModel = self:_serverModel()
	if show then
		if not self.localCopy and serverModel then
			self.localCopy = LanternFx.makeCopy(serverModel, "LanternLocalCopy")
			self.casts = nil
		end
		if serverModel then
			LanternFx.hideServer(serverModel, true)
		end
		self:_updateCopy()
	else
		if self.localCopy then
			self.localCopy:Destroy()
			self.localCopy = nil
			self.casts = nil
		end
		if serverModel then
			LanternFx.hideServer(serverModel, false)
		end
	end
end

function Lantern._updateCopy(self: Lantern)
	local copy = self.localCopy
	if not copy then
		return
	end
	local serverModel = self:_serverModel()
	if self.state == "Hip" or self.state == "Charging" then
		-- Just grabbed: hold the copy where the lantern belongs until the server has welded it there.
		if self:_serverMounted() or os.clock() > self.mountWaitUntil then
			self:_showLocalCopy(false)
			return
		end
		LanternFx.placeCopy(copy, self:_mountCFrame())
		LanternFx.styleCopy(copy, "Hip")
	else
		LanternFx.placeCopy(copy, LanternFx.pose(self.position, self.lanternVelocity, self.state == "Thrown"))
		LanternFx.styleCopy(copy, self.state)
	end
	-- Keep the server copy hidden (the camera's transparency code can reset parts in the character).
	if serverModel then
		local core = serverModel.PrimaryPart
		if core and core.LocalTransparencyModifier < 1 then
			LanternFx.hideServer(serverModel, true)
		end
	end
end

function Lantern._announce(self: Lantern)
	self.character:SetAttribute("LanternState", self.state)
	-- The flying lantern hums while it's thrown (follows the lantern; others hear it on theirs).
	if self.state == "Thrown" then
		local copy = self.localCopy
		local core: Instance? = if copy then copy.PrimaryPart else nil
		Sfx.Loop(self.character, "LanternTravel", true, { parent = core, on = "Lantern" })
	elseif Sfx.IsLooping(self.character, "LanternTravel") then
		Sfx.Loop(self.character, "LanternTravel", false)
	end
	local r = remote("LanternState")
	if r and r:IsA("RemoteEvent") then
		if self.state == "Thrown" then
			-- Everyone else replays the arc from these (LanternViewer).
			r:FireServer(self.state, self.position, {
				origin = self.throwOrigin,
				velocity = self.throwVelocity,
				gravity = self.throwGravity,
				start = Workspace:GetServerTimeNow(),
			})
		else
			r:FireServer(self.state, self.position)
		end
	end
	self.lastSyncPos = self.position
	self.lastSync = os.clock()
end

function Lantern._sync(self: Lantern)
	local now = os.clock()
	if now - self.lastSync < SYNC_INTERVAL or (self.position - self.lastSyncPos).Magnitude < 0.05 then
		return
	end
	self.lastSync = now
	self.lastSyncPos = self.position
	local r = remote("LanternSync")
	if r and r:IsA("UnreliableRemoteEvent") then
		r:FireServer(self.position)
	end
end

-- Cast params for body flight (slide along walls): the world, collidable parts, no characters.
function Lantern._castParams(self: Lantern, respectCollide: boolean): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { self.character }
	if self.localCopy then
		table.insert(ignore, self.localCopy)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = respectCollide
	return params
end

-- THE LANTERN OUT OF HAND ------------------------------------------------------------

-- The first impact of a throw: flash, and tag opponents in LanternBurstRadius the flash can see.
-- `direct` (someone hit directly) is already tagged and skipped.
function Lantern._burst(self: Lantern, at: Vector3, direct: Model?)
	if self.burstDone then
		return
	end
	self.burstDone = true
	LanternFx.burst(at)
	Sfx.Play(self.character, "LanternImpact", { at = at })
	local r = remote("LanternBurst")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(at)
	end
	local casts = self:_flightCasts()
	for _, who in LanternPhysics.characters(self.character) do
		if who ~= direct then
			local humanoid = who:FindFirstChildOfClass("Humanoid")
			local root = who:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				local d = (root.Position - at).Magnitude
				if d <= Config.LanternBurstRadius and LanternPhysics.clearLine(at, root.Position, casts) then
					table.insert(self.burstTagged, who)
					self:_tag(who, root.Position, "Burst")
				end
			end
		end
	end
end

-- Tags someone (locally right away, the server checks and marks them for everyone).
function Lantern._tag(self: Lantern, target: Model, at: Vector3, kind: "Direct" | "Burst")
	-- A direct hit always becomes the flight target; a burst tag only if nobody is tagged yet.
	if kind == "Direct" or not self:GetTagTarget() then
		self.tagTarget = target
		self.tagUntil = os.clock() + Config.LanternTagTime
	end
	local r = remote("LanternHit")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(target, at, kind)
	end
end

-- A direct hit: damage + tag (server), then it bounces back toward you and drops.
function Lantern._onHitCharacter(self: Lantern, target: Model, at: Vector3)
	self.hitThisThrow = true
	Sfx.Play(self.character, "LanternHit", { at = at })
	self.lastInfo = "hit " .. target.Name
	self:_tag(target, at, "Direct")
	self:_burst(at, target)
	local back = flatten(self.root.Position - at)
	back = if back.Magnitude > 1e-3 then back.Unit else Vector3.zero
	self.position = at + back * 0.8
	self.lanternVelocity = back * Config.LanternBounceBack + Vector3.new(0, Config.LanternBounceUp, 0)
	self:_drop(false)
end

-- Now loose: falling (resting = false) or lying still (resting = true).
function Lantern._drop(self: Lantern, resting: boolean)
	local changed = self.state ~= "Dropped" or self.resting ~= resting
	self.state = "Dropped"
	self.resting = resting
	if resting then
		self.lanternVelocity = Vector3.zero
		self.lastLanding = self.position
	end
	if changed then
		self:_announce()
	end
end

-- Landing / bumping into the world while falling or flying. Floors (normal up) stop it; walls and
-- ceilings take away the speed into them and it keeps falling.
function Lantern._touchWorld(self: Lantern, hit: LanternPhysics.Hit)
	self.position = hit.position
	if hit.normal.Y > 0.4 then
		self:_drop(true)
		return
	end
	local v = self.lanternVelocity
	local into = v:Dot(hit.normal)
	if into < 0 then
		v -= hit.normal * into
	end
	self.lanternVelocity = v * 0.3 + hit.normal * 3
	self.position = hit.position + hit.normal * 0.05
	-- Wedged somewhere steep with nowhere to fall: it stays there.
	self:_drop(v.Magnitude < 1.5)
end

-- One fixed step of a throw. Returns false once the throw is over.
function Lantern._stepThrow(self: Lantern, dt: number): boolean
	if self.flightTime == 0 then
		-- Point blank: someone between your body and where the throw leaves the hand is hit.
		local casts = self:_flightCasts()
		local from = self.root.Position + Vector3.new(0, 0.5, 0)
		if casts.characters then
			local close = LanternPhysics.cast(from, self.throwOrigin - from, { world = casts.world, characters = casts.characters })
			if close and close.kind == "Character" and close.character then
				self.lanternVelocity = self.throwVelocity
				self:_onHitCharacter(close.character, close.position)
				return false
			end
		end
	end
	local t = self.flightTime + dt
	local pos, vel = LanternPhysics.at(self.throwOrigin, self.throwVelocity, self.throwGravity, t)
	local hit = LanternPhysics.cast(self.position, pos - self.position, self:_flightCasts())
	if hit then
		self.lanternVelocity = vel
		if hit.kind == "Character" and hit.character then
			self:_onHitCharacter(hit.character, hit.position)
		else
			self:_burst(hit.position, nil)
			self:_touchWorld(hit)
		end
		return false
	end
	self.flightTime = t
	self.position = pos
	self.lanternVelocity = vel
	if t >= Config.LanternMaxFlightTime then
		self:_drop(false)
		return false
	end
	return true
end

-- One fixed step of a lantern falling freely (dropped, bounced, or out of flight time).
function Lantern._stepFall(self: Lantern, dt: number)
	self.lanternVelocity -= Vector3.new(0, Workspace.Gravity * dt, 0)
	local delta = self.lanternVelocity * dt
	local casts = self:_flightCasts()
	local hit = LanternPhysics.cast(self.position, delta, { world = casts.world, characters = nil })
	if hit then
		if not self.burstDone then
			self:_burst(hit.position, nil)
		end
		self:_touchWorld(hit)
	else
		self.position += delta
	end
end

function Lantern._stepLantern(self: Lantern, dt: number)
	local now = os.clock()
	if self.state == "Suspended" then
		if now >= self.suspendedUntil then
			self.lanternVelocity = Vector3.zero
			self:_drop(false)
		end
	elseif self:_isAirborne() then
		self.stepCarry = math.min(self.stepCarry + dt, LanternPhysics.STEP * MAX_STEPS_PER_FRAME)
		while self.stepCarry >= LanternPhysics.STEP and self:_isAirborne() do
			self.stepCarry -= LanternPhysics.STEP
			if self.state == "Thrown" then
				self:_stepThrow(LanternPhysics.STEP)
			else
				self:_stepFall(LanternPhysics.STEP)
			end
		end
		if self.position.Y < Workspace.FallenPartsDestroyHeight + VOID_MARGIN then
			self:_grab("it fell out of the world: back on the hip")
			self:_updateCopy()
			return
		end
	end

	if now - self.throwAt >= Config.LanternRegrabDelay then
		if (self.root.Position - self.position).Magnitude <= Config.LanternGrabRadius then
			self:_grab()
			self:_updateCopy()
			return
		end
	end
	self:_updateCopy()
	self:_sync()
end


-- FLIGHT ---------------------------------------------------------------------------

function Lantern._canFly(self: Lantern, cost: number): boolean
	if self.isBlocked() then
		self.lastInfo = "another move is running"
		return false
	end
	local mode = self.motor:GetMode()
	if mode == "Passive" or mode == "Suspended" then
		self.lastInfo = "can't fly now (" .. mode .. ")"
		return false
	end
	-- Overdraw: with any stamina left the move still comes out (and may burn you out).
	if not self.stamina:CanSpend(cost) then
		self.lastInfo = "burnt out"
		Sfx.Play(self.character, "Denied")
		return false
	end
	return true
end

function Lantern._beginFlight(self: Lantern, kind: FlightKind, heading: Vector3, speed: number)
	self.facingAim = false
	self.flight = kind
	self.heading = heading
	self.speed = speed
	self.flightStart = os.clock()
	self.motor:Suspend()
	self.humanoid.AutoRotate = false
	self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	self.lastVelocity = heading * speed
	self.velocity.VectorVelocity = self.lastVelocity
	self.velocity.Enabled = true
	self:_face(heading)
	self.align.Enabled = true
	self.character:SetAttribute("Flying", kind)
	self:_play(if kind == "Wings" then "WingFlight" else "Fly")
end

-- Tap: spread the wings and fly WingFlightDistance where the camera looks (test: `direction`).
function Lantern.WingFlight(self: Lantern, direction: Vector3?): boolean
	if self.flight or self.state ~= "Hip" then
		return false
	end
	if os.clock() - self.lastWingFlight < Config.WingFlightCooldown then
		self.lastInfo = "wing flight cooldown"
		return false
	end
	if not self:_canFly(Config.WingFlightCost) then
		return false
	end
	self.stamina:TrySpend(Config.WingFlightCost)
	local dir = direction or cameraLook(self.root)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else -Vector3.zAxis
	-- From the ground, never aim into the floor.
	if self.motor:GetMode() == "Ground" and dir.Y < 0.15 then
		dir = (flatten(dir) + Vector3.new(0, 0.15, 0)).Unit
	end
	local duration = Config.WingFlightTime
	local startSpeed = Config.RunSpeed * (Config.WingFlightSpeedMultiplier or 1.2) * self.motor:GetHealthSpeedScale()
	self.lastWingFlight = os.clock()
	self.wingEndAt = os.clock() + duration
	self.lastInfo = "wing flight"
	self:_beginFlight("Wings", dir, startSpeed)
	return true
end

function Lantern._tagValid(self: Lantern): (Model?, BasePart?)
	local target = self:GetTagTarget()
	if not target then
		return nil, nil
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not targetRoot or not targetRoot:IsA("BasePart") then
		return nil, nil
	end
	return target, targetRoot
end

function Lantern._insideLight(self: Lantern): boolean
	return self.state == "Suspended" and (self.root.Position - self.position).Magnitude <= Config.LanternLightRadius
end

-- Hold with the lantern away: tag flight, or free flight inside a hanging lantern's light.
function Lantern._tryStartFlight(self: Lantern)
	local _, targetRoot = self:_tagValid()
	local kind: FlightKind
	local goal: Vector3
	if targetRoot then
		kind = "Tag"
		goal = targetRoot.Position
	elseif self:_insideLight() then
		kind = "Free"
		goal = self.root.Position + cameraLook(self.root)
	else
		self.lastInfo = if self.state == "Suspended" then "outside the lantern's light" else "nothing to fly to"
		return
	end
	if not self:_canFly(Config.FlyStartStamina) then
		return
	end
	local toGoal = goal - self.root.Position
	local heading = if toGoal.Magnitude > 1e-3 then toGoal.Unit else cameraLook(self.root)
	local current = self.root.AssemblyLinearVelocity
	if kind == "Tag" then
		self.targetLastPos = (targetRoot :: BasePart).Position
		self.targetVel = (targetRoot :: BasePart).AssemblyLinearVelocity
		self:_beginFlight(kind, heading, math.max(current:Dot(heading), 20))
	else
		self:_beginFlight(kind, heading, math.max(current:Dot(heading), Config.FlySlowSpeed))
	end
	self.lastInfo = "flying (" .. kind .. ")"
end

function Lantern._endFlight(self: Lantern, reason: string, keep: Vector3?)
	local kind = self.flight
	if not kind then
		return
	end
	self.flight = nil
	self.lastFlightEnd = reason
	local carry = keep or self.lastVelocity
	self.velocity.Enabled = false
	self.align.Enabled = false
	self.humanoid.AutoRotate = true
	self.root.AssemblyLinearVelocity = carry
	self.motor:ApplyMomentum(carry)
	self.motor:AllowLaunch(0.35)
	self.motor:Resume()
	self.character:SetAttribute("Flying", nil)
	self:_stop("WingFlight")
	self:_stop("Fly")
end

function Lantern.Cancel(self: Lantern)
	self:_endFlight("cancel")
end

function Lantern._face(self: Lantern, direction: Vector3)
	local flat = flatten(direction)
	if flat.Magnitude < 1e-3 then
		return
	end
	self.align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
end

-- Removes the part of `v` going into anything solid just ahead (slide along walls and floors).
function Lantern._slide(self: Lantern, v: Vector3, dt: number): Vector3
	local params = self:_castParams(true)
	local speed = v.Magnitude
	if speed < 1e-3 then
		return v
	end
	local reach = v.Unit * (speed * dt + 1.4)
	for _, offset in { Vector3.zero, Vector3.new(0, -2.2, 0), Vector3.new(0, 1.2, 0) } do
		local hit = Workspace:Raycast(self.root.Position + offset, reach, params)
		if hit and not characterOf(hit.Instance) then
			local into = v:Dot(hit.Normal)
			if into < 0 then
				v -= hit.Normal * into
			end
		end
	end
	return v
end

function Lantern._stepFlight(self: Lantern, dt: number)
	local kind = self.flight
	if not kind then
		return
	end
	if not self:IsMoth() then
		self:_endFlight("cancel")
		return
	end
	local myPos = self.root.Position

	if kind == "Wings" then
		local duration = Config.WingFlightTime
		local elapsed = os.clock() - self.flightStart
		if elapsed >= duration or os.clock() >= self.wingEndAt then
			self:_endFlight("done", self.lastVelocity * Config.WingFlightKeep)
			return
		end
		local t = math.clamp(elapsed / math.max(duration, 1e-3), 0, 1)
		-- Match Front Dash's speed curve: explosive burst at start tapering smoothly down to running speed
		local endSpeed = Config.DashEndSpeedRunning * self.motor:GetHealthSpeedScale()
		local startSpeed = Config.RunSpeed * (Config.WingFlightSpeedMultiplier or 1.2) * self.motor:GetHealthSpeedScale()
		local currentSpeed = startSpeed + (endSpeed - startSpeed) * t
		local v = self.heading * currentSpeed
		if self.motor:GetMode() ~= "Air" and v.Y < MIN_TAKEOFF_LIFT and elapsed < 0.1 then
			v = Vector3.new(v.X, MIN_TAKEOFF_LIFT, v.Z)
		end
		v = self:_slide(v, dt)
		self.lastVelocity = v
		self.velocity.VectorVelocity = v
		return
	end

	if not self.stamina:Drain(Config.FlyDrain * dt) then
		self.lastInfo = "out of stamina"
		self:_endFlight("stamina")
		return
	end

	if kind == "Tag" then
		local target, targetRoot = self:_tagValid()
		if not target or not targetRoot then
			self:_endFlight("lost")
			return
		end
		if os.clock() - self.flightStart > Config.TagFlyMaxTime then
			self:_endFlight("timeout")
			return
		end
		if dt > 0 then
			local measured = (targetRoot.Position - self.targetLastPos) / dt
			self.targetVel = self.targetVel:Lerp(measured, TARGET_VEL_SMOOTHING)
		end
		self.targetLastPos = targetRoot.Position
		local distance = (targetRoot.Position - myPos).Magnitude
		if distance <= Config.TagFlyStopDistance + TAG_ARRIVE_SLACK then
			self:_endFlight("arrived", self.targetVel)
			return
		end
		local lead = math.min(distance / math.max(self.speed, 1), TAG_MAX_LEAD)
		local toAim = targetRoot.Position + self.targetVel * lead - myPos
		local desired = if toAim.Magnitude > 1e-3 then toAim.Unit else self.heading
		self.heading = turnTowards(self.heading, desired, math.rad(Config.TagFlyTurnRate) * dt)
		-- (A lantern grabbed on the way can push it above TagFlySpeed.)
		local closing = math.min(self.speed + Config.TagFlySpeed * 8 * dt, math.max(Config.TagFlySpeed, self.speed))
		closing = math.min(closing, (distance - Config.TagFlyStopDistance) * TAG_BRAKE + TAG_MIN_CLOSING)
		self.speed = closing
		local v = self:_slide(self.targetVel + self.heading * closing, dt)
		self.lastVelocity = v
		self.velocity.VectorVelocity = v
		self:_face(targetRoot.Position - myPos)
		return
	end

	-- Free flight inside the light.
	if self.state ~= "Suspended" then
		self:_endFlight("lantern")
		return
	end
	local fromCenter = myPos - self.position
	if fromCenter.Magnitude > Config.LanternLightRadius then
		self.lastInfo = "left the lantern's light"
		self:_endFlight("left_light")
		return
	end
	local desired = cameraLook(self.root)
	local camera = Workspace.CurrentCamera
	local camFlat = flatten(if camera then camera.CFrame.LookVector else self.root.CFrame.LookVector)
	local keys = flatten(self.humanoid.MoveDirection)
	local forward = camFlat.Magnitude > 1e-3 and keys:Dot(camFlat.Unit) > FORWARD_KEY_MIN
	local targetSpeed = if forward then Config.FlyMaxSpeed else Config.FlySlowSpeed
	if self.speed < targetSpeed then
		self.speed = math.min(self.speed + Config.FlySpeedChange * dt, targetSpeed)
	else
		self.speed = math.max(self.speed - Config.FlySpeedChange * dt, targetSpeed)
	end
	self.heading = turnTowards(self.heading, desired, math.rad(self:GetTurnRate()) * dt)
	local v = self.heading * self.speed
	-- Can't leave the light: at the edge, the outward part of the velocity is removed.
	fromCenter = myPos - self.position
	if fromCenter.Magnitude >= Config.LanternLightRadius - 1 and fromCenter.Magnitude > 1e-3 then
		local outward = fromCenter.Unit
		local out = v:Dot(outward)
		if out > 0 then
			v -= outward * out
		end
	end
	v = self:_slide(v, dt)
	self.lastVelocity = v
	self.velocity.VectorVelocity = v
	self:_face(self.heading)
end


function Lantern._renderStep(self: Lantern, dt: number)
	if self.destroyed then
		return
	end
	if self.pressing and not self.holdHandled and os.clock() - self.pressAt >= Config.LanternTapTime then
		self.holdHandled = true
		self:_hold()
	end
	if self.state == "Charging" then
		self:_updatePreview()
		self:_updateCopy()
	elseif self.state == "Hip" then
		self:_showPreview(false)
		self:_updateCopy()
	else
		self:_showPreview(false)
		self:_stepLantern(dt)
	end
end

function Lantern._step(self: Lantern, dt: number)
	if self.destroyed then
		return
	end
	self:_renderStep(dt)
	if self.flight then
		self:_stepFlight(dt)
	end
end

function Lantern.Destroy(self: Lantern)
	if self.destroyed then
		return
	end
	self:_endFlight("cancel")
	self.destroyed = true
	self.character:SetAttribute("LanternCharging", nil)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.localCopy then
		self.localCopy:Destroy()
		self.localCopy = nil
	end
	self:_showPreview(false)
	self.velocity:Destroy()
	self.align:Destroy()
	self.attachment:Destroy()
	if active[self.character] == self then
		active[self.character] = nil
	end
end

-- Test helpers ---------------------------------------------------------------------

-- Puts the lantern back on the hip right away (no cooldown).
function Lantern.ResetForTest(self: Lantern)
	self:_endFlight("cancel")
	self.pressing = false
	self.holdHandled = true
	self.character:SetAttribute("LanternCharging", nil)
	self.tagTarget = nil
	self.tagUntil = 0
	self.burstDone = false
	self.hitThisThrow = false
	table.clear(self.burstTagged)
	self:_showPreview(false)
	self:_releaseFacing()
	self:_stop("Charge")
	if self.state ~= "Hip" then
		self.state = "Hip"
		self.resting = false
		self.mountWaitUntil = os.clock() + MOUNT_WAIT
		self:_announce()
	end
	self.grabbedAt = -math.huge
	self.lastWingFlight = -math.huge
end

function Lantern.PlaceForTest(self: Lantern, position: Vector3, state: LanternState)
	self.position = position
	self.lanternVelocity = Vector3.zero
	self.throwAt = os.clock()
	self.state = state
	self.resting = state == "Dropped"
	self.canSuspend = false
	self.burstDone = true
	if state == "Suspended" then
		self.suspendedUntil = os.clock() + Config.LanternSuspendTime
	end
	self:_showLocalCopy(true)
	self:_announce()
end

-- Did this throw flash yet (first impact)?
function Lantern.HasBurst(self: Lantern): boolean
	return self.burstDone
end

-- Who the last burst tagged (tests / debug).
function Lantern.GetBurstTagged(self: Lantern): { Model }
	return table.clone(self.burstTagged)
end

-- Where the last throw came to rest (nil if it hasn't yet).
function Lantern.GetLastLanding(self: Lantern): Vector3?
	return self.lastLanding
end

-- The throw preview's predicted landing for a charge, without charging (tests).
function Lantern.PredictForTest(self: Lantern, power: number): (Vector3?, string?)
	local origin, v0 = self:_plan(power)
	local _, hit = LanternPhysics.predict(origin, v0, LanternPhysics.gravity(), self:_flightCasts(), Config.LanternMaxFlightTime)
	if hit then
		return hit.position, hit.kind
	end
	return nil, nil
end

return Lantern
