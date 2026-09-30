--!strict
-- Lantern (ModuleScript)
-- Location: ReplicatedStorage > Movement > Lantern
--
-- The Moth race's lantern and wings (docs/MoveData.md, "Moth"). Runs on the client next to
-- CharacterMotor (the player owns their character's physics, and the thrown lantern is simulated
-- here too so it feels instant). Only works while the character's "Race" attribute is "Moth".
-- Numbers: MovementConfig "MOTH: LANTERN + WINGS".
--
--   Ctrl TAP  (lantern on the hip)  -> WING BURST: ~WingFlightDistance studs where the camera looks,
--                                      then WingFlightKeep of the speed carries on.
--   Ctrl HOLD (lantern on the hip)  -> take it in hand and charge; RELEASE throws it at the crosshair
--                                      (screen centre, shift lock or not), faster and farther the
--                                      longer you held. While charging you face the aim and see the
--                                      exact path (glowing dots) and where it will hang (ring).
--   Ctrl PRESS (lantern out)        -> RECALL: it flies back to your hand.
--   Space HELD in the air inside your own light -> FLY where the camera looks (W = faster). Letting
--                                      go, leaving the light, burning out or M1 ends it.
-- A throw does no damage: it stops at the first thing it meets (wall, floor, someone) or at the aimed
-- point, and HANGS there lighting LanternLightRadius studs for LanternSuspendTime, then flies back.
-- Knocked down (the server sets KnockId on the lantern when someone else's attack touches it): it
-- falls and lies there (walk into it or recall it) and can't be thrown for LanternKnockLockout.
--
-- The throw is a projectile run in fixed steps by LanternPhysics: the preview and the real flight
-- use the same steps, so it hangs on the ring.
--
-- Visuals: the server builds the lantern (LanternServer) and welds it to the hip / hand. While it's
-- out, this client HIDES the server copy (LocalTransparencyModifier only; it's never moved from here,
-- because moving it while it's still welded drags the character) and draws its own copy with no lag.
-- Other players see it through LanternViewer, which replays the same arc.
-- Attributes: "Flying" = Wings / Free, "LanternState" = Hip / Charging / Thrown / Suspended /
-- Dropped / Returning.
-- Animations (MothAnimations): MothWingFlight, MothFly (loop), LanternCharge (loop), LanternThrow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)
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
-- Throw preview while charging: glowing dots along the predicted flight, a ring where it will hang.
local PREVIEW_SPACING = 2.2 -- studs between dots
local PREVIEW_MAX_BALLS = 48
local PREVIEW_COLOR = Color3.fromRGB(80, 200, 255)
local SYNC_INTERVAL = 1 / 20
-- Most fixed flight steps run in one frame (a long hitch just slows the lantern down a little).
local MAX_STEPS_PER_FRAME = 8
-- A lantern that falls this far below the lowest allowed height comes back to the hip.
local VOID_MARGIN = 20
-- How long to wait for the server to put the lantern back on the hip / hand before showing it anyway.
local MOUNT_WAIT = 2
-- A recalled lantern this close to the hand is back.
local RECALL_ARRIVE = 1.5
-- Hanging this far off whatever it stopped against (studs), so it isn't inside a wall or a person.
local HANG_OFFSET = 0.35
local FORWARD_KEY_MIN = 0.3
-- The flight never rises faster than this when it starts on the ground (studs/s), so a flat camera
-- doesn't scrape the floor.
local MIN_TAKEOFF_LIFT = 6

export type LanternState = "Hip" | "Charging" | "Thrown" | "Suspended" | "Dropped" | "Returning"
export type FlightKind = "Wings" | "Free"

local ANIMS = {
	Rest = "MothWings", -- wings / antennae resting loop, under everything (Core priority)
	WingFlight = "MothWingFlight",
	Fly = "MothFly",
	Charge = "LanternCharge",
	Throw = "LanternThrow",
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
	return AnimationLibrary.Exists(name)
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
	-- Space, for the flight: when it was pressed, and whether this press already tried to fly.
	jumpWasHeld: boolean,
	jumpAt: number,
	flyTried: boolean,

	state: LanternState,
	chargeStart: number,
	-- The lantern while it's out: where it is and how it moves.
	position: Vector3,
	lanternVelocity: Vector3,
	resting: boolean,
	-- The current throw (projectile): start values, fixed-step flight time, when it stops, leftover
	-- frame time.
	throwOrigin: Vector3,
	throwVelocity: Vector3,
	throwGravity: number,
	throwStop: number,
	flightTime: number,
	stepCarry: number,
	casts: LanternPhysics.Casts?,
	castsAt: number,
	throwAt: number,
	suspendedUntil: number,
	grabbedAt: number,
	-- Knocked down: no throwing until then (os.clock); the server's KnockId last seen.
	knockUntil: number,
	knockSeen: number?,
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

	flight: FlightKind?,
	heading: Vector3,
	speed: number,
	flightStart: number,
	wingEndAt: number,
	lastWingFlight: number,
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
		jumpWasHeld = false,
		jumpAt = 0,
		flyTried = false,

		state = "Hip" :: LanternState,
		chargeStart = 0,
		position = root.Position,
		lanternVelocity = Vector3.zero,
		resting = false,
		throwOrigin = root.Position,
		throwVelocity = Vector3.zero,
		throwGravity = LanternPhysics.gravity(),
		throwStop = Config.LanternMaxFlightTime,
		flightTime = 0,
		stepCarry = 0,
		casts = nil,
		castsAt = -math.huge,
		throwAt = -math.huge,
		suspendedUntil = 0,
		grabbedAt = -math.huge,
		knockUntil = 0,
		knockSeen = nil,
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

		flight = nil,
		heading = -Vector3.zAxis,
		speed = 0,
		flightStart = 0,
		wingEndAt = 0,
		lastWingFlight = -math.huge,
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

-- INFO (HUD, debug overlay, tests) ---------------------------------------------

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

-- Seconds until it can be thrown again after coming back to the hand.
function Lantern.GetGrabCooldown(self: Lantern): number
	return math.max(0, Config.LanternGrabCooldown - (os.clock() - self.grabbedAt))
end

-- Seconds until it can be thrown again after being knocked down.
function Lantern.GetKnockLockout(self: Lantern): number
	return math.max(0, self.knockUntil - os.clock())
end

-- Seconds before a throw is allowed (the longer of the two above).
function Lantern.GetThrowLockout(self: Lantern): number
	return math.max(self:GetGrabCooldown(), self:GetKnockLockout())
end

-- The Moth's movement cooldown for the HUD: (seconds left, full length). The wing burst's cooldown
-- while it runs, else the knocked-down lockout, else the no-throw time after it came back.
-- (0, 1) when ready.
function Lantern.GetMothCooldown(self: Lantern): (number, number)
	-- A wing burst can't start again until the current one is over AND its cooldown has passed.
	local since = os.clock() - self.lastWingFlight
	local total = math.max(Config.WingFlightCooldown, Config.WingFlightTime)
	if since < total then
		return total - since, total
	end
	local knock = self:GetKnockLockout()
	if knock > 0 then
		return knock, Config.LanternKnockLockout
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

-- 0..1: how much of the hanging time is left (0 unless it's hanging).
function Lantern.GetLightLeft(self: Lantern): number
	if self.state ~= "Suspended" then
		return 0
	end
	return math.clamp((self.suspendedUntil - os.clock()) / math.max(Config.LanternSuspendTime, 1e-3), 0, 1)
end

-- True while you're inside your own hanging lantern's light (where holding Space flies).
function Lantern.InsideLight(self: Lantern): boolean
	return self:_insideLight()
end

function Lantern.GetLastInfo(self: Lantern): string
	return self.lastInfo
end

-- Why the last flight ended: "done", "released", "stamina", "left_light", "lantern", "m1", "cancel".
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

-- Ctrl pressed.
function Lantern.Press(self: Lantern)
	if self.pressing then
		return
	end
	self.pressing = true
	self.pressAt = os.clock()
	self.holdHandled = false
	-- With the lantern out, Ctrl calls it back at once (the rest of this press does nothing).
	if self:IsMoth() and self:Recall() then
		self.holdHandled = true
	end
end

-- Ctrl released (also call on focus loss so the key can't stick).
function Lantern.Release(self: Lantern)
	if not self.pressing then
		return
	end
	self.pressing = false
	if self.state == "Charging" then
		self:_throw(nil)
	elseif not self.holdHandled then
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
	elseif self.state == "Returning" then
		self.lastInfo = "on its way back"
	end
end

-- Held past the tap time (once per press).
function Lantern._hold(self: Lantern)
	if not self:IsMoth() then
		self.lastInfo = "not a Moth"
		return
	end
	if self.state ~= "Hip" or self.flight then
		return
	end
	local knock = self:GetKnockLockout()
	if knock > 0 then
		self.lastInfo = string.format("knocked down: throw in %.1fs", knock)
		Sfx.Play(self.character, "Denied")
		return
	end
	local cooldown = self:GetGrabCooldown()
	if cooldown > 0 then
		self.lastInfo = string.format("just caught it: throw in %.1fs", cooldown)
		return
	end
	self:_startCharge()
	self:_faceAim()
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

-- The throw for a given charge: (origin, launch velocity, speed, stop time). It passes through the
-- crosshair point, or the point that far along the line from the origin to it if it's farther than
-- the range, and stops there (stop time = when it gets there) unless it meets something first.
function Lantern._plan(self: Lantern, power: number): (Vector3, Vector3, number, number)
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
	local v0 = LanternPhysics.solve(origin, point, speed, LanternPhysics.gravity())
	return origin, v0, speed, Lantern._stopTime(origin, v0, point)
end

-- When a throw launched at v0 from origin gets to `point` (by its flat distance; straight up / down
-- by height), capped at LanternMaxFlightTime.
function Lantern._stopTime(origin: Vector3, v0: Vector3, point: Vector3): number
	local flatV = Vector3.new(v0.X, 0, v0.Z).Magnitude
	local t
	if flatV > 1 then
		t = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z).Magnitude / flatV
	else
		t = (point - origin).Magnitude / math.max(v0.Magnitude, 1)
	end
	return math.clamp(t, LanternPhysics.STEP, Config.LanternMaxFlightTime)
end

-- Throws at the crosshair (or along `direction`, for tests). `charge` 0..1 overrides the hold.
function Lantern._throw(self: Lantern, direction: Vector3?, charge: number?)
	if self.state ~= "Charging" and self.state ~= "Hip" then
		return
	end
	local power = charge or self:GetCharge()
	local origin, v0, speed, stop = self:_plan(power)
	if direction then
		local dir = if direction.Magnitude > 1e-3 then direction.Unit else -Vector3.zAxis
		v0 = dir * speed
		stop = math.min(Lantern._throwRange(power) / speed, Config.LanternMaxFlightTime)
	end
	self:_showPreview(false)
	self.throwOrigin = origin
	self.throwVelocity = v0
	self.throwGravity = LanternPhysics.gravity()
	self.throwStop = stop
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

-- While charging: the exact predicted flight for the current charge (same steps as the real throw),
-- and the ring where it will hang (flush on a surface, or facing you in the air).
function Lantern._updatePreview(self: Lantern)
	self:_showPreview(true)
	local ring = self.previewEnd
	if not self.preview or not ring then
		return
	end
	self:_faceAim()
	local origin, v0, _, stop = self:_plan(self:GetCharge())
	local points, hit = LanternPhysics.predict(origin, v0, LanternPhysics.gravity(), self:_flightCasts(), stop)

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

	if hit and hit.kind == "World" then
		ring.CFrame = cylinderSurfaceCFrame(hit.position - hit.normal * LanternPhysics.WORLD_RADIUS, hit.normal, ring.Size.X)
	else
		local at = if hit then hit.position else points[#points]
		ring.CFrame = cylinderSurfaceCFrame(at, origin - at, ring.Size.X)
	end
	ring.Transparency = 0.3
end

-- Test helper: aim at this world point instead of the crosshair (nil = the crosshair again).
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

-- Stops and hangs at `position`, lit, for LanternSuspendTime.
function Lantern._hang(self: Lantern, position: Vector3)
	self.state = "Suspended"
	self.position = position
	self.lanternVelocity = Vector3.zero
	self.resting = false
	self.suspendedUntil = os.clock() + Config.LanternSuspendTime
	self.lastLanding = position
	self.lastInfo = "hanging: hold Space in the air inside its light to fly"
	LanternFx.burst(position)
	Sfx.Play(self.character, "LanternSuspend", { at = position })
	self:_announce()
end

-- Ctrl with the lantern out: it flies back to your hand. Returns true if it was out.
function Lantern.Recall(self: Lantern): boolean
	if self.state ~= "Thrown" and self.state ~= "Suspended" and self.state ~= "Dropped" then
		return false
	end
	self.state = "Returning"
	self.resting = false
	self.lanternVelocity = Vector3.zero
	self.lastInfo = "recalled"
	Sfx.Play(self.character, "LanternGrab")
	self:_announce()
	return true
end

-- Someone else's attack touched it: it falls, and it can't be thrown for a while.
function Lantern._knocked(self: Lantern)
	self.knockUntil = os.clock() + Config.LanternKnockLockout
	if self.state == "Thrown" or self.state == "Suspended" then
		self.lanternVelocity = Vector3.new(0, -4, 0)
		self:_drop(false)
		self.lastInfo = "knocked down"
	end
end

-- Back on the hip (caught it, picked it up, or it fell out of the world).
function Lantern._grab(self: Lantern, reason: string?)
	self.state = "Hip"
	self.resting = false
	self.lanternVelocity = Vector3.zero
	self.grabbedAt = if reason then -math.huge else os.clock()
	self.lastInfo = reason or "caught"
	-- The copy stays on the hip until the server has the lantern welded there again.
	self.mountWaitUntil = os.clock() + MOUNT_WAIT
	self:_announce()
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
	-- The flying lantern hums while it's thrown or coming back (follows the lantern; others hear it
	-- on theirs).
	local flying = self.state == "Thrown" or self.state == "Returning"
	if flying then
		local copy = self.localCopy
		local core: Instance? = if copy then copy.PrimaryPart else nil
		Sfx.Loop(self.character, "LanternTravel", true, { parent = core, on = "Lantern" })
	elseif Sfx.IsLooping(self.character, "LanternTravel") then
		Sfx.Loop(self.character, "LanternTravel", false)
	end
	local r = remote("LanternState")
	if r and r:IsA("RemoteEvent") then
		if self.state == "Thrown" then
			-- Everyone else replays the arc from these (LanternViewer), up to where it stops.
			r:FireServer(self.state, self.position, {
				origin = self.throwOrigin,
				velocity = self.throwVelocity,
				gravity = self.throwGravity,
				start = Workspace:GetServerTimeNow(),
				stop = self.throwStop,
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

-- Now loose: falling (resting = false) or lying still (resting = true).
function Lantern._drop(self: Lantern, resting: boolean)
	local changed = self.state ~= "Dropped" or self.resting ~= resting
	self.state = "Dropped"
	self.resting = resting
	if resting then
		self.lanternVelocity = Vector3.zero
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

-- One fixed step of a throw. Returns false once the throw is over (it hangs).
function Lantern._stepThrow(self: Lantern, dt: number): boolean
	local t = math.min(self.flightTime + dt, self.throwStop)
	local pos, vel = LanternPhysics.at(self.throwOrigin, self.throwVelocity, self.throwGravity, t)
	local hit = LanternPhysics.cast(self.position, pos - self.position, self:_flightCasts())
	if hit then
		-- Stops against whatever it meets and hangs just off it (a person: on the side it came from).
		local away = if hit.kind == "Character" then self.position - hit.position else hit.normal
		away = if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis
		self:_hang(hit.position + away * HANG_OFFSET)
		return false
	end
	self.flightTime = t
	self.position = pos
	self.lanternVelocity = vel
	if t >= self.throwStop then
		self:_hang(pos)
		return false
	end
	return true
end

-- One fixed step of a lantern falling freely (knocked down).
function Lantern._stepFall(self: Lantern, dt: number)
	self.lanternVelocity -= Vector3.new(0, Workspace.Gravity * dt, 0)
	local delta = self.lanternVelocity * dt
	local casts = self:_flightCasts()
	local hit = LanternPhysics.cast(self.position, delta, { world = casts.world, characters = nil })
	if hit then
		self:_touchWorld(hit)
	else
		self.position += delta
	end
end

-- Flying back to the hand, straight through everything.
function Lantern._stepReturn(self: Lantern, dt: number)
	local to = self:_handPosition() - self.position
	local step = Config.LanternRecallSpeed * dt
	if to.Magnitude <= math.max(step, RECALL_ARRIVE) then
		self:_grab()
		return
	end
	self.lanternVelocity = to.Unit * Config.LanternRecallSpeed
	self.position += to.Unit * step
end

-- The server says someone knocked it (KnockId changed on the lantern).
function Lantern._checkKnock(self: Lantern)
	local model = self:_serverModel()
	if not model then
		return
	end
	local id = model:GetAttribute("KnockId")
	local value = if typeof(id) == "number" then id else 0
	if self.knockSeen == nil then
		self.knockSeen = value
	elseif value ~= self.knockSeen then
		self.knockSeen = value
		self:_knocked()
	end
end

function Lantern._stepLantern(self: Lantern, dt: number)
	local now = os.clock()
	if self.state == "Suspended" then
		if now >= self.suspendedUntil then
			self:Recall()
			self.lastInfo = "the light went out: coming back"
		end
	elseif self.state == "Returning" then
		self:_stepReturn(dt)
		-- (Re-read as the full type: _stepReturn may have caught it.)
		local after: LanternState = (self :: any).state
		if after == "Hip" then
			self:_updateCopy()
			return
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

	-- Lying on the floor (knocked down): walk into it to pick it up.
	if self.state == "Dropped" and now - self.throwAt >= Config.LanternRegrabDelay then
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

function Lantern._insideLight(self: Lantern): boolean
	return self.state == "Suspended" and (self.root.Position - self.position).Magnitude <= Config.LanternLightRadius
end

-- Space held in the air inside your own light: take off (once per press).
function Lantern._checkSpace(self: Lantern)
	local held = self.motor:IsJumpHeld()
	local now = os.clock()
	if held and not self.jumpWasHeld then
		self.jumpAt = now
		self.flyTried = false
	end
	self.jumpWasHeld = held
	if not held or self.flyTried or self.flight or now - self.jumpAt < Config.FlyHoldDelay then
		return
	end
	if not self:IsMoth() or self.motor:GetMode() ~= "Air" or not self:_insideLight() then
		return
	end
	self.flyTried = true
	if not self:_canFly(Config.FlyStartStamina) then
		return
	end
	local heading = cameraLook(self.root)
	local current = self.root.AssemblyLinearVelocity
	self:_beginFlight("Free", heading, math.max(current:Dot(heading), Config.FlySlowSpeed))
	self.lastInfo = "flying"
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

	-- Free flight inside your light.
	if self.state ~= "Suspended" then
		self:_endFlight("lantern")
		return
	end
	if not self.motor:IsJumpHeld() then
		self:_endFlight("released")
		return
	end
	if (self.root.Position - self.position).Magnitude > Config.LanternLightRadius then
		self.lastInfo = "left the lantern's light"
		self:_endFlight("left_light")
		return
	end
	if not self.stamina:Drain(Config.FlyDrain * dt) then
		self.lastInfo = "out of stamina"
		self:_endFlight("stamina")
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
	local v = self:_slide(self.heading * self.speed, dt)
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
	self:_checkKnock()
	self:_checkSpace()
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
	if rawequal(active[self.character], self) then
		active[self.character] = nil
	end
end

-- Test helpers ---------------------------------------------------------------------

-- Puts the lantern back on the hip right away (no cooldowns).
function Lantern.ResetForTest(self: Lantern)
	self:_endFlight("cancel")
	self.pressing = false
	self.holdHandled = true
	self.character:SetAttribute("LanternCharging", nil)
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
	self.knockUntil = 0
	self.lastWingFlight = -math.huge
end

-- Puts the lantern at `position` in `state` (Suspended = hanging with a fresh timer).
function Lantern.PlaceForTest(self: Lantern, position: Vector3, state: LanternState)
	self.position = position
	self.lanternVelocity = Vector3.zero
	self.throwAt = os.clock()
	self.state = state
	self.resting = state == "Dropped"
	if state == "Suspended" then
		self.suspendedUntil = os.clock() + Config.LanternSuspendTime
	end
	self:_showLocalCopy(true)
	self:_announce()
end

-- Where the last throw stopped and hung (nil until it does).
function Lantern.GetLastLanding(self: Lantern): Vector3?
	return self.lastLanding
end

-- Where the preview says a throw with this charge will hang, without charging (tests).
function Lantern.PredictForTest(self: Lantern, power: number): Vector3
	local origin, v0, _, stop = self:_plan(power)
	local points, hit = LanternPhysics.predict(origin, v0, LanternPhysics.gravity(), self:_flightCasts(), stop)
	if hit then
		local away = if hit.kind == "Character" then points[math.max(#points - 1, 1)] - hit.position else hit.normal
		away = if away.Magnitude > 1e-3 then away.Unit else Vector3.yAxis
		return hit.position + away * HANG_OFFSET
	end
	return points[#points]
end

return Lantern
