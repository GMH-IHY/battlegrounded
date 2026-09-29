--!strict
-- HeadLook (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > HeadLook
--
-- Turns heads a little toward where each player's camera points, like Die of Death: the body
-- faces the way you walk and the head glances where you're looking. It's kept subtle, and it
-- moves in steps (jumps to a new angle, then holds it) to match the snappy animations.
--   Your character: aimed from your camera, and sent to the server a few times a second
--                   (HeadLookServer) so other players see it.
--   Other players:  read from their character's "HeadLook" attribute.
-- It also carries the shift-lock body twist (ShiftLock's "BodyTurn"), so other players see a
-- shift-locked character's body turn toward A/D too ("BodyTwist" attribute).
-- The head is turned by rotating the Neck joint's C0, which animations don't touch, so it
-- stacks on top of whatever animation is playing. All the numbers are in AnimationConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("AnimationConfig")
local Config = require(ReplicatedStorage.Movement.AnimationConfig)

-- With HeadLookEnabled off the head is never touched, but this script keeps running: it also
-- carries the shift-lock body twist to other players.
local HEAD_ENABLED = Config.HeadLookEnabled

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("HeadLook") :: UnreliableRemoteEvent
local localPlayer = Players.LocalPlayer

local MAX_YAW = math.rad(Config.HeadMaxYaw)
local MAX_PITCH = math.rad(Config.HeadMaxPitch)
local MIN_STEP = math.rad(Config.HeadMinStep)
-- When the camera looks back at your own face (past this angle), the head faces forward
-- instead of whipping from one shoulder to the other.
local LOOK_BACK_LIMIT = math.rad(125)
local SEND_INTERVAL = 1 / math.max(Config.HeadLookSendRate, 1)

type HeadState = { baseC0: CFrame, yaw: number, pitch: number, steppedAt: number }
-- Keyed by the Neck joint. Not a weak table: Roblox can drop Instance keys from weak tables
-- while the Instance still exists, which made the head re-capture an already-turned neck as
-- its rest pose and drift further every time. Entries are removed when the neck is destroyed.
local states: { [Motor6D]: HeadState } = {}

local lastSentAt = 0
local lastSentYaw, lastSentPitch, lastSentTwist = 0, 0, 0
local TWIST_SEND_THRESHOLD = math.rad(3)
local TWIST_SMOOTHING = 14 -- other players' body twist catches up this fast (not stepped)

-- Other players' shift-lock body twist (ShiftLock twists our own locally), keyed by RootJoint.
type TwistState = { baseC0: CFrame, twist: number }
local twists: { [Motor6D]: TwistState } = {}

local function applyTwist(character: Model, target: number, dt: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild("RootJoint")
	if not joint or not joint:IsA("Motor6D") then
		return
	end
	local state = twists[joint]
	if not state then
		state = { baseC0 = joint.C0, twist = 0 }
		twists[joint] = state
		local connection: RBXScriptConnection
		connection = joint.AncestryChanged:Connect(function()
			if not joint:IsDescendantOf(game) then
				twists[joint] = nil
				connection:Disconnect()
			end
		end)
	end
	local diff = (target - state.twist + math.pi) % (2 * math.pi) - math.pi
	state.twist += diff * (1 - math.exp(-TWIST_SMOOTHING * dt))
	joint.C0 = CFrame.Angles(0, state.twist, 0) * state.baseC0
end

local function getNeck(character: Model): Motor6D?
	local torso = character:FindFirstChild("Torso")
	local neck = torso and torso:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		return neck
	end
	return nil
end

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Where the head should point, from the camera direction relative to the torso.
local function cameraTarget(character: Model): (number, number)
	local camera = Workspace.CurrentCamera
	local torso = character:FindFirstChild("Torso")
	if not camera or not torso or not torso:IsA("BasePart") then
		return 0, 0
	end
	local direction = torso.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	local yaw = math.atan2(-direction.X, -direction.Z) -- + = left
	local pitch = math.asin(math.clamp(direction.Y, -1, 1)) -- + = up
	if math.abs(yaw) > LOOK_BACK_LIMIT then
		return 0, 0
	end
	yaw = math.clamp(yaw * Config.HeadYawScale, -MAX_YAW, MAX_YAW)
	pitch = math.clamp(pitch * Config.HeadPitchScale, -MAX_PITCH, MAX_PITCH)
	return yaw, pitch
end

local function apply(neck: Motor6D, targetYaw: number, targetPitch: number)
	local state = states[neck]
	if not state then
		state = { baseC0 = neck.C0, yaw = 0, pitch = 0, steppedAt = 0 }
		states[neck] = state
		local connection: RBXScriptConnection
		connection = neck.AncestryChanged:Connect(function()
			if not neck:IsDescendantOf(game) then
				states[neck] = nil
				connection:Disconnect()
			end
		end)
	end
	-- Stepped, not smoothed: at most one jump per HeadStepInterval, and tiny changes are ignored.
	local now = os.clock()
	if now - state.steppedAt < Config.HeadStepInterval then
		return
	end
	if math.abs(targetYaw - state.yaw) < MIN_STEP and math.abs(targetPitch - state.pitch) < MIN_STEP then
		return
	end
	state.steppedAt = now
	state.yaw = targetYaw
	state.pitch = targetPitch
	local base = state.baseC0
	neck.C0 = CFrame.new(base.Position)
		* CFrame.Angles(0, targetYaw, 0)
		* CFrame.Angles(targetPitch, 0, 0)
		* base.Rotation
end

RunService.RenderStepped:Connect(function(dt: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local neck = getNeck(character)
		if not neck then
			continue
		end

		local yaw, pitch = 0, 0
		if player == localPlayer then
			if HEAD_ENABLED and isAlive(character) then
				yaw, pitch = cameraTarget(character)
			end
			local twistValue = character:GetAttribute("BodyTurn") -- set by ShiftLock
			local twist = if typeof(twistValue) == "number" then twistValue else 0
			local now = os.clock()
			local changed = math.abs(yaw - lastSentYaw) > MIN_STEP * 0.5
				or math.abs(pitch - lastSentPitch) > MIN_STEP * 0.5
				or math.abs(twist - lastSentTwist) > TWIST_SEND_THRESHOLD
			if changed and now - lastSentAt >= SEND_INTERVAL then
				lastSentAt = now
				lastSentYaw, lastSentPitch, lastSentTwist = yaw, pitch, twist
				remote:FireServer(yaw, pitch, twist)
			end
		else
			local look = character:GetAttribute("HeadLook")
			if typeof(look) == "Vector2" and isAlive(character) then
				yaw, pitch = look.X, look.Y
			end
			local twistValue = character:GetAttribute("BodyTwist") -- set by HeadLookServer
			applyTwist(character, if typeof(twistValue) == "number" then twistValue else 0, dt)
		end
		if HEAD_ENABLED then
			apply(neck, yaw, pitch)
		end
	end
end)
