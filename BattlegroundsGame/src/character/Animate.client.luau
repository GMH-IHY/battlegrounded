--!strict
-- Animate (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > Animate
--
-- Plays the movement animations. It's named "Animate" on purpose: Roblox only adds its own
-- default Animate script when the character doesn't already have one, so this replaces it.
--
-- Every frame it picks one animation from the character's state:
--   climbing        -> Climb (speed follows climb speed; frozen when still, reversed going down)
--   just jumped     -> Jump (until you start dropping)
--   in the air      -> Fall
--   on the ground   -> Idle / Walk / Sprint. There's one walk cycle: the character turns to face
--                      where it's going, and the head turns toward the camera (HeadLook).
--                      If something ever makes you move backward while facing forward
--                      (shift lock), the walk plays in reverse.
-- Walk and Sprint keep their step timing when switching between each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("AnimationConfig")
movementFolder:WaitForChild("AnimationLibrary")

local Config = require(ReplicatedStorage.Movement.AnimationConfig)
local AnimationLibrary = require(ReplicatedStorage.Movement.AnimationLibrary)
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

local NAMES = {
	"Idle",
	"WalkForward",
	"Sprint",
	"Jump",
	"Fall",
	"Climb",
}
-- Animations that share a stride; switching between them keeps the step timing.
local STRIDE: { [string]: boolean } = {
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

local tracks: { [string]: AnimationTrack } = {}
for _, name in NAMES do
	local animation = AnimationLibrary.Get(name)
	if animation then
		tracks[name] = animator:LoadAnimation(animation)
	end
end

local current: string? = nil
local jumpStartedAt = -math.huge
local airborneSince: number? = nil
local connections: { RBXScriptConnection } = {}

local function clampRate(rate: number): number
	return math.clamp(rate, Config.MinPlaybackRate, Config.MaxPlaybackRate)
end

local function play(name: string?, speed: number)
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
	if oldTrack and current and name and STRIDE[current] and STRIDE[name] and oldTrack.Length > 0 then
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
		local keep = current or "Idle"
		local track = tracks[keep]
		return keep, if track then track.Speed else 1
	end

	airborneSince = nil
	return chooseGround(velocity)
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
		local name, speed = choose()
		play(name, speed)
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
	for _, track in tracks do
		track:Stop(0)
	end
end

script.Destroying:Connect(cleanup)
humanoid.Died:Connect(cleanup)
