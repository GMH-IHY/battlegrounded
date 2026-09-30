--!strict
-- CollisionViewer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > CollisionViewer
--
-- Debug view of every character's collision boxes (yours, other players', dummies). Settings menu (gear)
-- > Debug > Collision boxes, or from the command bar:
-- game.Players.LocalPlayer.PlayerGui.CollisionViewer.Toggle:Fire()
--   green   body parts that are colliding right now (Head, Torso, ...)
--   orange  extra collision boxes movement adds (LowerBodyCollider for the legs, SlideCollider
--           while sliding)
--   yellow  outline of the HumanoidRootPart (what the physics moves; not a collision box)
-- Parts that aren't colliding at the moment (arms and legs, or the body while sliding) aren't
-- drawn. Only you see it. Set MovementConfig.DebugSpeedometer = false before release to remove
-- both debug views.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))
local Config = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("MovementConfig"))

if not Config.DebugSpeedometer then
	return
end

local SLIDE_GROUP = "ParkourSlideBody"
local EXTRA_COLLIDERS: { [string]: boolean } = {
	LowerBodyCollider = true,
	SlideCollider = true,
}
local GREEN = Color3.fromRGB(80, 230, 110)
local ORANGE = Color3.fromRGB(255, 150, 40)
local YELLOW = Color3.fromRGB(255, 230, 60)
local RESCAN_INTERVAL = 0.5

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CollisionViewer"
gui.ResetOnSpawn = false
gui.Enabled = false
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 8)
label.Size = UDim2.fromOffset(420, 22)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.4
label.BorderSizePixel = 0
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextColor3 = Color3.new(1, 1, 1)
label.Text = "Collision boxes: green body, orange extra colliders, yellow root"
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local shown = false
local folder: Folder? = nil
local boxes: { [BasePart]: BoxHandleAdornment } = {}
local outlines: { [BasePart]: SelectionBox } = {}
local characters: { Model } = {}
local rescanTimer = 0

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(boxes)
	table.clear(outlines)
end

local function rescan()
	table.clear(characters)
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			table.insert(characters, child)
		end
	end
end

local function isColliding(part: BasePart): boolean
	return part.CanCollide and part.CollisionGroup ~= SLIDE_GROUP
end

local function update()
	local container = folder
	if not container then
		return
	end
	local seen: { [BasePart]: boolean } = {}
	for _, character in characters do
		if character.Parent then
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") then
					if descendant.Name == "HumanoidRootPart" then
						seen[descendant] = true
						if not outlines[descendant] then
							local outline = Instance.new("SelectionBox")
							outline.Adornee = descendant
							outline.Color3 = YELLOW
							outline.LineThickness = 0.03
							outline.SurfaceTransparency = 1
							outline.Parent = container
							outlines[descendant] = outline
						end
					elseif isColliding(descendant) then
						seen[descendant] = true
						local box = boxes[descendant]
						if not box then
							local created = Instance.new("BoxHandleAdornment")
							created.Adornee = descendant
							created.AlwaysOnTop = true
							created.ZIndex = 5
							created.Transparency = 0.55
							created.Color3 = if EXTRA_COLLIDERS[descendant.Name] then ORANGE else GREEN
							created.Parent = container
							boxes[descendant] = created
							box = created
						end
						if box then
							box.Size = descendant.Size
						end
					end
				end
			end
		end
	end
	for part, box in boxes do
		if not seen[part] then
			box:Destroy()
			boxes[part] = nil
		end
	end
	for part, outline in outlines do
		if not seen[part] then
			outline:Destroy()
			outlines[part] = nil
		end
	end
end

local function setShown(on: boolean)
	shown = on
	gui.Enabled = on
	clear()
	if on then
		local created = Instance.new("Folder")
		created.Name = "CollisionViewer"
		created.Parent = Workspace.CurrentCamera
		folder = created
		rescan()
		update()
	end
end

local setSwitch = SettingsMenu.AddToggle("Debug", "Collision boxes", false, setShown)

local toggleEvent = Instance.new("BindableEvent")
toggleEvent.Name = "Toggle"
toggleEvent.Event:Connect(function()
	setShown(not shown)
	setSwitch(shown)
end)
toggleEvent.Parent = gui

RunService.Heartbeat:Connect(function(dt: number)
	if not shown then
		return
	end
	rescanTimer += dt
	if rescanTimer >= RESCAN_INTERVAL then
		rescanTimer = 0
		rescan()
	end
	update()
end)
