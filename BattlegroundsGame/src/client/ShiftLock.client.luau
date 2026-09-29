--!strict
-- ShiftLock (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > ShiftLock
--
-- Tab toggles shift lock (Isaac, Sep 28: Left Ctrl is now the race special, Tab "for now").
-- It's our own toggle because Roblox's built-in shift lock is bound to Shift (our dash key) and only works if each player has turned on
-- "Shift Lock Switch" in their Roblox settings.
--
-- How it works, and why it's built this way:
--   * Facing the camera: done by the ENGINE, the same way Roblox's own shift lock does it
--     (UserGameSettings.RotationType = CameraRelative). The previous version turned the
--     character by teleporting its root part every frame, which fought the Humanoid's physics
--     and made the character jitter and freak out while moving.
--   * Turning toward A/D: purely VISUAL. The physical body keeps facing the camera; only the
--     visible body is twisted toward where you're moving (RootJoint.C0), up to 90 degrees.
--     Other players see it too (sent with the head look). Pure left/right no longer sits on a
--     boundary, so the body can't flip 180 degrees back and forth.
--   * Mouse: locked where it already is and hidden, not teleported to the screen centre.
--     Teleporting it made the camera read a huge mouse movement and flick 80-120 degrees.
--
-- Note: Roblox also uses Tab to open / close the player list (top right). Both happen for now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UserGameSettings = UserSettings():GetService("UserGameSettings")
local Perf = require(ReplicatedStorage.Movement.Perf)

local TOGGLE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Tab] = true,
}
local CAMERA_OFFSET = Vector3.new(2.35, 0.65, 0) -- over the right shoulder, lifted slightly above head level
-- Moving more than this far from the camera's forward counts as walking backward.
local BACKWARD_ANGLE = math.rad(112.5)
local TURN_SPEED = 14 -- how fast the visible body swings toward the move direction

local player = Players.LocalPlayer
local enabled = false
local windowFocused = true
local bodyTurn = 0 -- radians the visible body is twisted from the camera direction (+ = left)
-- Furthest the visible body turns toward A/D. Pressing A (or D) alone turns it the same 45
-- degrees as W+A / S+A (Isaac, Sep 26), instead of swinging the body fully sideways.
local MAX_SIDE_TURN = math.rad(45)

type JointState = { baseC0: CFrame }
local rootJoints: { [Motor6D]: JointState } = {}

local function getCharacterParts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return character, humanoid, root
	end
	return character, nil, nil
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Twists the visible body by `turn` radians around the up axis without moving the root part.
local function applyBodyTurn(root: BasePart, turn: number)
	local joint = root:FindFirstChild("RootJoint")
	if not joint or not joint:IsA("Motor6D") then
		return
	end
	local state = rootJoints[joint]
	if not state then
		state = { baseC0 = joint.C0 }
		rootJoints[joint] = state
		local connection: RBXScriptConnection
		connection = joint.AncestryChanged:Connect(function()
			if not joint:IsDescendantOf(game) then
				rootJoints[joint] = nil
				connection:Disconnect()
			end
		end)
	end
	joint.C0 = CFrame.Angles(0, turn, 0) * state.baseC0
end

local function setEnabled(on: boolean)
	enabled = on
	UserGameSettings.RotationType = if on then Enum.RotationType.CameraRelative else Enum.RotationType.MovementRelative
	UserInputService.MouseIconEnabled = not on
	if not on then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local character, humanoid = getCharacterParts()
	if humanoid then
		humanoid.CameraOffset = if on then CAMERA_OFFSET else Vector3.zero
	end
	if character then
		character:SetAttribute("ShiftLock", on)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not TOGGLE_KEYS[input.KeyCode] then
		return
	end
	-- Roblox's player list also listens to Tab and can mark it as processed, so only a text box
	-- being typed in blocks the toggle.
	if gameProcessed and UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	setEnabled(not enabled)
end)

-- While the game window doesn't have focus (Alt-menu in Studio, alt-tab), don't fight for the
-- mouse. When focus comes back, the lock resumes wherever the cursor is, without a jump.
UserInputService.WindowFocusReleased:Connect(function()
	windowFocused = false
end)
UserInputService.WindowFocused:Connect(function()
	windowFocused = true
end)

-- Visible body twist for the current move direction, relative to where the root faces (the
-- camera), and whether that counts as walking backward.
--   Forward / sideways: turn toward the key side, at most 45 degrees (W+D and D alone both turn 45 right).
--   Mostly backward: walk backward, with the body turned toward the key side, the same way as
--   the forward diagonals (S+D turns right, S+A turns left), by the same amount the move
--   leans sideways (S+D = 45 degrees, straight S = 0).
local function targetTurn(moveDirection: Vector3, root: BasePart): (number, boolean)
	local move = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if move.Magnitude < 0.1 then
		return 0, false
	end
	move = move.Unit
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		return 0, false
	end
	forward = forward.Unit
	-- Rotation about the up axis from `forward` to `move` (+ = left).
	local angle = math.atan2(forward.Z * move.X - forward.X * move.Z, forward:Dot(move))
	if math.abs(angle) > BACKWARD_ANGLE then
		-- Backward: turn toward the side of the key, by how far the move leans sideways.
		local side = if angle > 0 then 1 else -1
		return side * (math.pi - math.abs(angle)), true
	end
	return math.clamp(angle, -MAX_SIDE_TURN, MAX_SIDE_TURN), false
end

local function onFrame(dt: number)
	local character, humanoid, root = getCharacterParts()

	if enabled then
		if windowFocused then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			UserInputService.MouseIconEnabled = false
		end
		-- Keep our settings on (the camera scripts or a respawn can reset them).
		if UserGameSettings.RotationType ~= Enum.RotationType.CameraRelative then
			UserGameSettings.RotationType = Enum.RotationType.CameraRelative
		end
		if humanoid and humanoid.CameraOffset ~= CAMERA_OFFSET then
			humanoid.CameraOffset = CAMERA_OFFSET
		end
	end

	if not character or not humanoid or not root then
		return
	end

	local target = 0
	local backward = false
	if enabled and humanoid.Health > 0 then
		local state = humanoid:GetState()
		if state ~= Enum.HumanoidStateType.Climbing and state ~= Enum.HumanoidStateType.Seated then
			target, backward = targetTurn(humanoid.MoveDirection, root)
		end
	end
	-- Animate plays the walk in reverse while this is set.
	character:SetAttribute("MoveBackward", backward)
	if
		character:GetAttribute("Dashing") == true
		or character:GetAttribute("Rolling") == true
		or character:GetAttribute("Parkour") ~= nil
	then
		-- A dash (or landing roll) sets its own facing and plays its own animation: no visual twist on top.
		bodyTurn = 0
	else
		bodyTurn = wrapAngle(bodyTurn + wrapAngle(target - bodyTurn) * (1 - math.exp(-TURN_SPEED * dt)))
		if math.abs(bodyTurn) < 1e-3 and target == 0 then
			bodyTurn = 0
		end
	end
	-- A slide leans the body with the same joint (AutoParkour owns it until the slide ends).
	if character:GetAttribute("Parkour") ~= "Slide" then
		applyBodyTurn(root, bodyTurn)
	end
	-- HeadLook sends this to the server so other players see the twist too.
	character:SetAttribute("BodyTurn", bodyTurn)
end

RunService.RenderStepped:Connect(function(dt: number)
	if Perf.enabled then
		local t0 = os.clock()
		onFrame(dt)
		Perf.add("ShiftLock", os.clock() - t0)
	else
		onFrame(dt)
	end
end)
