--!strict
-- AnimationGallery (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > AnimationGallery
--
-- Studio-only pose viewer. Press P during Play: copies of your character appear in a row,
-- each frozen on one pose of an animation, so every pose can be checked at once on the real
-- avatar. P again steps to the next camera angle, then the next animation; after the last
-- one the gallery closes. Reads the KeyframeSequences that StudioAnimationMirror copies into
-- ReplicatedStorage, so it always shows the latest saved edits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local KEY = Enum.KeyCode.P -- F7 is taken by Studio itself
local ORDER = {
	"DashForward",
	"DashRight",
	"DashLeft",
	"DashBack",
	"DashPunch",
	"Idle",
	"WalkForward",
	"Sprint",
	"Jump",
	"Fall",
	"Climb",
}
local ORIGIN = Vector3.new(140, 3, -120) -- open baseplate, away from the test course
local SPACING = 7
-- Camera angles, relative to the row (the copies face -Z).
type View = { name: string, offset: Vector3 }
local VIEWS: { View } = {
	{ name = "3/4 back", offset = Vector3.new(9, 5, 14) },
	{ name = "side (facing right)", offset = Vector3.new(0, 2, 0) }, -- special-cased below
	{ name = "front", offset = Vector3.new(0, 3, -16) },
}

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "AnimationGallery"
gui.ResetOnSpawn = false
gui.DisplayOrder = 300
gui.Enabled = false
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 10)
label.Size = UDim2.fromOffset(700, 34)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.3
label.Font = Enum.Font.ArialBold
label.TextSize = 20
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = ""
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local folder: Folder? = nil
local sequenceIndex = 0
local viewIndex = 0
local poseCount = 0

-- The times at which each distinct pose shows. build.py writes every pose at the END of the span
-- it covers (Constant easing shows the later keyframe), so a pose is visible between two keys.
local function poseTimes(sequence: KeyframeSequence): { number }
	local keys: { number } = {}
	for _, child in sequence:GetChildren() do
		if child:IsA("Keyframe") then
			table.insert(keys, child.Time)
		end
	end
	table.sort(keys)
	local times: { number } = {}
	for i = 1, #keys - 1 do
		table.insert(times, (keys[i] + keys[i + 1]) / 2)
	end
	if #times == 0 and #keys > 0 then
		table.insert(times, keys[1])
	end
	return times
end

local function clearGallery()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function makeCopy(source: Model): Model?
	local wasArchivable = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = wasArchivable
	if not copy then
		return nil
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("Constraint") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
	for _, child in copy:GetChildren() do
		if child.Name == "LowerBodyCollider" then
			child:Destroy()
		end
	end
	return copy
end

local function build(name: string): boolean
	clearGallery()
	local mirror = ReplicatedStorage:FindFirstChild("StudioAnimations")
	local sequence = mirror and mirror:FindFirstChild(name)
	local character = player.Character
	if not sequence or not sequence:IsA("KeyframeSequence") or not character then
		return false
	end
	local ok, animationId = pcall(function()
		return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(sequence)
	end)
	if not ok then
		return false
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local newFolder = Instance.new("Folder")
	newFolder.Name = "AnimationGallery"
	newFolder.Parent = Workspace
	folder = newFolder

	local times = poseTimes(sequence)
	poseCount = #times
	for i, t in times do
		local copy = makeCopy(character)
		if copy then
			copy.Name = string.format("%s_%d", name, i)
			local root = copy:FindFirstChild("HumanoidRootPart")
			local humanoid = copy:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid then
				root.CFrame = CFrame.lookAt(ORIGIN + Vector3.new((i - 1) * SPACING, 0, 0), ORIGIN + Vector3.new((i - 1) * SPACING, 0, -1))
				humanoid.PlatformStand = true
				copy.Parent = newFolder
				local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
				local track = animator:LoadAnimation(animation)
				track.Priority = Enum.AnimationPriority.Action4
				track:Play(0, 1, 0)
				track.TimePosition = t
			end
		end
	end
	return true
end

local function applyView()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local rowCenter = ORIGIN + Vector3.new((poseCount - 1) * SPACING / 2, 0, 0)
	local rowLength = math.max(poseCount - 1, 1) * SPACING
	local view = VIEWS[viewIndex]
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 40
	if view.name == "side (facing right)" then
		-- Each copy seen from its own left, one at a time would be ideal; a long lens from far
		-- along the row axis shows them overlapping, so instead look across the row from +X
		-- after turning every copy to face +X.
		if folder then
			for _, copy in folder:GetChildren() do
				local root = copy:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local position = root.Position
					root.CFrame = CFrame.lookAt(position, position + Vector3.xAxis)
				end
			end
		end
		local eye = rowCenter + Vector3.new(0, 2, rowLength * 1.35 + 14)
		camera.CFrame = CFrame.lookAt(eye, rowCenter + Vector3.new(0, -0.5, 0))
	else
		if folder then
			for _, copy in folder:GetChildren() do
				local root = copy:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local position = root.Position
					root.CFrame = CFrame.lookAt(position, position - Vector3.zAxis)
				end
			end
		end
		local scale = (rowLength * 1.2 + 12) / 16
		local eye = rowCenter + view.offset * scale
		camera.CFrame = CFrame.lookAt(eye, rowCenter + Vector3.new(0, -0.5, 0))
	end
	label.Text = string.format("%s  -  %d poses  -  %s view   (P: next)", ORDER[sequenceIndex], poseCount, view.name)
end

local function stop()
	clearGallery()
	gui.Enabled = false
	sequenceIndex, viewIndex = 0, 0
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
end

local function advance()
	if sequenceIndex == 0 then
		sequenceIndex, viewIndex = 1, 0
	end
	viewIndex += 1
	if viewIndex > #VIEWS then
		viewIndex = 1
		sequenceIndex += 1
	end
	while sequenceIndex <= #ORDER do
		if viewIndex ~= 1 or build(ORDER[sequenceIndex]) then
			gui.Enabled = true
			applyView()
			return
		end
		sequenceIndex += 1
	end
	stop()
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.KeyCode == KEY then
		advance()
	end
end)

-- Also steppable from the command bar: game.Players.LocalPlayer.PlayerGui.AnimationGallery.Next:Fire()
local nextEvent = Instance.new("BindableEvent")
nextEvent.Name = "Next"
nextEvent.Event:Connect(advance)
nextEvent.Parent = gui
