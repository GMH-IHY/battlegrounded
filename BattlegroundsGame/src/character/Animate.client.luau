--!strict
-- Animate (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > Animate
--
-- Plays the movement animations. It's named "Animate" on purpose: Roblox only adds its own
-- default Animate script when the character doesn't already have one, so this replaces it.
--
-- LOOPS: every frame one loop is picked from the character's state:
--   climbing        -> Climb (speed follows climb speed; frozen when still, reversed going down)
--   just jumped     -> Jump (until you start dropping)
--   in the air      -> Fall
--   on the ground   -> Idle / WalkForward / Sprint (the walk plays in reverse when moving backward
--                      in shift lock). Walk and Sprint keep their step timing when switching.
--
-- TRANSITIONS: when the state changes, a short clip plays in the loop's place first, so the body
-- never jumps straight from one loop into another (all poses snap; the clips add the in-betweens):
--   standing -> walking / running   WalkStart / SprintStart (end on the loop's first pose)
--   running -> standing              SprintStop (a skid)
--   sharp turn while running         SprintTurn
--   landing                          LandHeavy (long fall, no roll: the motor's landing lag),
--                                    LandRun (landing while moving), LandLight (standing)
-- A clip gives way as soon as it no longer fits: moving again cuts a stop or a standing landing,
-- stopping cuts a start, and leaving the ground or grabbing a truss cuts any of them. Only the
-- heavy landing plays out (you can't move during its lag anyway).
--
-- The playing locomotion animation's name is mirrored to the character attribute "LocoAnim"
-- (tests and debug tools read it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("AnimationConfig")
movementFolder:WaitForChild("AnimationLibrary")
movementFolder:WaitForChild("CharacterMotor")

local Config = require(ReplicatedStorage.Movement.AnimationConfig)
local AnimationLibrary = require(ReplicatedStorage.Movement.AnimationLibrary)
local CharacterMotor = require(ReplicatedStorage.Movement.CharacterMotor)
local Perf = require(ReplicatedStorage.Movement.Perf)

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	local created = Instance.new("Animator")
	created.Parent = humanoid
	animator = created
end
assert(animator, "Animate: no Animator")

local LOOPS = { "Idle", "WalkForward", "Sprint", "Jump", "Fall", "Climb" }
local CLIPS = { "WalkStart", "SprintStart", "SprintStop", "SprintTurn", "LandLight", "LandRun", "LandHeavy" }
-- Animations that share a stride; switching between them keeps the step timing.
local STRIDE: { [string]: boolean } = {
	WalkForward = true,
	Sprint = true,
}
local MOVING: { [string]: boolean } = {
	WalkForward = true,
	Sprint = true,
}
local JUMP_HOLD = 0.6 -- longest the Jump animation can stay up before Fall takes over
local NO_ANIMATION_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Seated] = true,
}

-- How each clip gives way (see the header).
type ClipRule = { cutWhenMoving: boolean, cutWhenStopped: boolean }
local CLIP_RULES: { [string]: ClipRule } = {
	WalkStart = { cutWhenMoving = false, cutWhenStopped = true },
	SprintStart = { cutWhenMoving = false, cutWhenStopped = true },
	SprintTurn = { cutWhenMoving = false, cutWhenStopped = true },
	LandRun = { cutWhenMoving = false, cutWhenStopped = true },
	SprintStop = { cutWhenMoving = true, cutWhenStopped = false },
	LandLight = { cutWhenMoving = true, cutWhenStopped = false },
	LandHeavy = { cutWhenMoving = false, cutWhenStopped = false },
}

local tracks: { [string]: AnimationTrack } = {}
for _, name in LOOPS do
	local animation = AnimationLibrary.Get(name)
	if animation then
		tracks[name] = animator:LoadAnimation(animation)
	end
end
for _, name in CLIPS do
	local animation = AnimationLibrary.Get(name)
	if animation then
		local track = animator:LoadAnimation(animation)
		track.Looped = false
		track.Priority = Enum.AnimationPriority.Movement
		tracks[name] = track
	end
end

local current: string? = nil -- the loop playing
local clip: string? = nil -- the transition clip playing in the loop's place
local lastLoop: string? = nil -- the loop picked last frame (even while a clip covered it)
local lastSpeed = 0 -- horizontal speed last frame
local lastMove = Vector3.zero -- move direction last frame
local lastTurnAt = -math.huge
local pendingLanding: CharacterMotor.LandingInfo? = nil
local pendingLandingAt = -math.huge
local jumpStartedAt = -math.huge
local airborneSince: number? = nil
local connections: { RBXScriptConnection } = {}
local motor: CharacterMotor.CharacterMotor? = nil
local stopListening: (() -> ())? = nil

-- A landing is used within this long, even if the Humanoid still says "falling" for a frame.
local LANDING_MEMORY = 0.15
-- A tiny landing (a step down) doesn't play a landing clip.
local LAND_MIN_FALL = 2.5
local LAND_MIN_IMPACT = 30
-- Running at least this fast (studs/s) when you stop plays the skid.
local STOP_MIN_SPEED = 18
-- A turn sharper than this (cos of the angle between move directions) while running plays SprintTurn.
local TURN_COS = math.cos(math.rad(110))
local TURN_MIN_SPEED = 16
local TURN_COOLDOWN = 0.35

local function clampRate(rate: number): number
	return math.clamp(rate, Config.MinPlaybackRate, Config.MaxPlaybackRate)
end

local function publish(name: string?)
	if character:GetAttribute("LocoAnim") ~= name then
		character:SetAttribute("LocoAnim", name)
	end
end

local function stopClip()
	if clip then
		local track = tracks[clip]
		if track then
			track:Stop(0)
		end
		clip = nil
	end
end

local function startClip(name: string): boolean
	local track = tracks[name]
	if not track then
		return false
	end
	stopClip()
	if current then
		local loopTrack = tracks[current]
		if loopTrack then
			loopTrack:Stop(0)
		end
		current = nil
	end
	clip = name
	track:Play(0, 1, 1)
	publish(name)
	return true
end

local function play(name: string?, speed: number, fresh: boolean)
	if name == current then
		local track = if name then tracks[name] else nil
		if track and track.Speed ~= speed then
			track:AdjustSpeed(speed)
		end
		return
	end

	local oldTrack = if current then tracks[current] else nil
	local newTrack = if name then tracks[name] else nil
	local phase: number? = nil
	if not fresh and oldTrack and current and name and STRIDE[current] and STRIDE[name] and oldTrack.Length > 0 then
		phase = oldTrack.TimePosition / oldTrack.Length
	end

	if oldTrack then
		oldTrack:Stop(Config.FadeTime)
	end
	current = name
	if newTrack then
		newTrack:Play(Config.FadeTime, 1, speed)
		if phase and newTrack.Length > 0 then
			newTrack.TimePosition = phase * newTrack.Length
		end
	end
	publish(name)
end

local function chooseGround(velocity: Vector3): (string, number)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	if speed < Config.IdleSpeed then
		return "Idle", 1
	end

	-- Angle of travel relative to where the VISIBLE body faces: 0 = forward, +90 = right,
	-- -90 = left, +-180 = back. In shift lock the visible body is twisted toward A/D
	-- (ShiftLock's "BodyTurn"), so strafing counts as walking forward and a backward move
	-- plays the walk in reverse.
	local bodyTurn = character:GetAttribute("BodyTurn")
	local facing = root.CFrame
	if typeof(bodyTurn) == "number" then
		facing *= CFrame.Angles(0, bodyTurn, 0)
	end
	local localVelocity = facing:VectorToObjectSpace(flat)
	local angle = math.deg(math.atan2(localVelocity.X, -localVelocity.Z))
	local absAngle = math.abs(angle)

	-- In shift lock, ShiftLock decides what counts as backward (the body is turned toward the
	-- key side while backing up, so the angle alone can't tell).
	if character:GetAttribute("ShiftLock") == true then
		absAngle = if character:GetAttribute("MoveBackward") == true then 180 else 0
	end

	if character:GetAttribute("Sprinting") == true and absAngle <= 67.5 then
		return "Sprint", clampRate(speed / Config.SprintAnimSpeed)
	end

	local rate = clampRate(speed / Config.WalkAnimSpeed)
	if absAngle >= 112.5 then
		return "WalkForward", -rate
	end
	return "WalkForward", rate
end

local function choose(): (string?, number)
	local state = humanoid:GetState()
	if NO_ANIMATION_STATES[state] then
		airborneSince = nil
		return nil, 1
	end

	local velocity = root.AssemblyLinearVelocity
	local now = os.clock()

	if state == Enum.HumanoidStateType.Climbing then
		airborneSince = nil
		return "Climb", math.clamp(velocity.Y / Config.ClimbAnimSpeed, -Config.MaxPlaybackRate, Config.MaxPlaybackRate)
	end

	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if airborne then
		airborneSince = airborneSince or now
		local sinceJump = now - jumpStartedAt
		local jumpTrack = tracks.Jump
		local jumpStillPlaying = current ~= "Jump" or (if jumpTrack then jumpTrack.IsPlaying else false)
		if sinceJump < JUMP_HOLD and jumpStillPlaying and (velocity.Y > 0 or sinceJump < 0.12) then
			return "Jump", 1
		end
		local airTime = now - (airborneSince :: number)
		if current == "Fall" or current == "Jump" or airTime >= Config.FallDelay or velocity.Y < -Config.FallSpeedThreshold then
			return "Fall", 1
		end
		-- A short drop: keep whatever was playing.
		local keep = current or lastLoop or "Idle"
		local track = tracks[keep]
		return keep, if track then track.Speed else 1
	end

	airborneSince = nil
	return chooseGround(velocity)
end

-- Which clip (if any) the change from last frame's loop to this one calls for.
local function transitionFor(loop: string?, speed: number, move: Vector3, now: number): string?
	local landing = pendingLanding
	pendingLanding = nil
	if landing and not landing.handled and character:GetAttribute("Parkour") == nil then
		if landing.heavy then
			return "LandHeavy"
		end
		if landing.fall >= LAND_MIN_FALL or landing.impact >= LAND_MIN_IMPACT then
			return if loop and MOVING[loop] then "LandRun" else "LandLight"
		end
	end
	if loop == "Idle" and lastLoop == "Sprint" and lastSpeed >= STOP_MIN_SPEED then
		return "SprintStop"
	end
	if lastLoop == "Idle" and loop == "Sprint" then
		return "SprintStart"
	end
	if lastLoop == "Idle" and loop == "WalkForward" and speed > 0 then
		return "WalkStart"
	end
	if loop == "Sprint" and lastLoop == "Sprint" and lastSpeed >= TURN_MIN_SPEED and now - lastTurnAt > TURN_COOLDOWN then
		if move.Magnitude > 0.5 and lastMove.Magnitude > 0.5 and move.Unit:Dot(lastMove.Unit) < TURN_COS then
			lastTurnAt = now
			return "SprintTurn"
		end
	end
	return nil
end

local function step()
	if not motor then
		motor = CharacterMotor.Get(character)
		if motor then
			stopListening = motor:OnLanded(function(info: CharacterMotor.LandingInfo)
				pendingLanding = info
				pendingLandingAt = os.clock()
			end)
		end
	end

	local now = os.clock()
	local loop, speed = choose()
	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local move = humanoid.MoveDirection
	local grounded = loop == "Idle" or (loop ~= nil and MOVING[loop] == true)

	if pendingLanding and now - pendingLandingAt > LANDING_MEMORY then
		pendingLanding = nil
	end
	local wanted = if grounded then transitionFor(loop, speed, move, now) else nil
	if wanted then
		startClip(wanted)
	end

	local fresh = false
	if clip then
		local rule = CLIP_RULES[clip]
		local track = tracks[clip]
		local finished = track == nil or not track.IsPlaying
		local cut = not grounded
			or (rule.cutWhenMoving and loop ~= nil and MOVING[loop] == true)
			or (rule.cutWhenStopped and loop == "Idle")
		if finished or cut then
			stopClip()
			fresh = true -- a clip ends on the loop's first pose: start the loop from there
		end
	end

	lastLoop = loop
	lastSpeed = flatSpeed
	lastMove = move
	if clip then
		return
	end
	play(loop, speed, fresh)
end

table.insert(
	connections,
	humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Jumping then
			jumpStartedAt = os.clock()
			-- Restart the jump even if it was already playing (buffered / quick re-jumps).
			if current == "Jump" then
				current = nil
				local track = tracks.Jump
				if track then
					track:Stop(0)
				end
			end
		end
	end)
)

table.insert(
	connections,
	RunService.Heartbeat:Connect(function()
		local t0 = if Perf.enabled then os.clock() else 0
		step()
		if Perf.enabled then
			Perf.add("Animate", os.clock() - t0)
		end
	end)
)

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if stopListening then
		stopListening()
		stopListening = nil
	end
	for _, track in tracks do
		track:Stop(0)
	end
end

script.Destroying:Connect(cleanup)
humanoid.Died:Connect(cleanup)
