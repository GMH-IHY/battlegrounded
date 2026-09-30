--!strict
-- OverheadBars (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > OverheadBars
--
-- Status bars over everyone else's head (players and training dummies), in the HUD's style:
--   HP          green bar with the number
--   build-up    thin white bar under it: how close they are to your element's status (Buildup)
--   statuses    small tags: DRAFTED, INFESTED, BURNOUT, the Lotus stage (L2 / L3) and FORM
-- Read from the attributes the server's Fighter publishes. Updated in steps (10 a second), like
-- everything else in the look. Your own are on the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatConfig"))

local player = Players.LocalPlayer

local FONT = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)
local BAR_BG = Color3.fromRGB(22, 22, 24)
local HP_FILL = Color3.fromRGB(46, 160, 38)
local HP_LOW = Color3.fromRGB(200, 60, 40)
local BUILDUP_FILL = Color3.fromRGB(215, 235, 240)
local TAG_COLORS: { [string]: Color3 } = {
	DRAFTED = Color3.fromRGB(215, 235, 240),
	INFESTED = Color3.fromRGB(16, 152, 168),
	BURNOUT = Color3.fromRGB(230, 120, 30),
	FORM = Color3.fromRGB(16, 152, 168),
	L2 = Color3.fromRGB(16, 152, 168),
	L3 = Color3.fromRGB(16, 152, 168),
}
local STEP = 0.1 -- seconds between updates
local MAX_DISTANCE = 120

type View = {
	model: Model,
	humanoid: Humanoid,
	gui: BillboardGui,
	hpFill: Frame,
	hpText: TextLabel,
	buildupFill: Frame,
	tags: TextLabel,
}

local views: { [Model]: View } = {}

local function frame(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function add(model: Model)
	if views[model] or model == player.Character then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	if not humanoid or not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OverheadBars"
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = MAX_DISTANCE
	gui.ResetOnSpawn = false
	gui.Adornee = head

	local hpBack = frame(gui, UDim2.fromOffset(110, 12), UDim2.fromOffset(0, 12), BAR_BG)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = hpBack
	local hpFill = frame(hpBack, UDim2.fromScale(1, 1), UDim2.new(), HP_FILL)
	local hpText = Instance.new("TextLabel")
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.FontFace = FONT
	hpText.TextSize = 10
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.TextStrokeTransparency = 0.3
	hpText.ZIndex = 2
	hpText.Parent = hpBack

	local buildupBack = frame(gui, UDim2.fromOffset(110, 3), UDim2.fromOffset(0, 25), BAR_BG)
	local buildupFill = frame(buildupBack, UDim2.fromScale(0, 1), UDim2.new(), BUILDUP_FILL)

	local tags = Instance.new("TextLabel")
	tags.BackgroundTransparency = 1
	tags.Size = UDim2.fromOffset(110, 11)
	tags.FontFace = FONT
	tags.TextSize = 10
	tags.RichText = true
	tags.TextStrokeTransparency = 0.3
	tags.TextColor3 = Color3.new(1, 1, 1)
	tags.Text = ""
	tags.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	views[model] = {
		model = model,
		humanoid = humanoid,
		gui = gui,
		hpFill = hpFill,
		hpText = hpText,
		buildupFill = buildupFill,
		tags = tags,
	}
end

local function remove(model: Model)
	local view = views[model]
	if view then
		view.gui:Destroy()
		views[model] = nil
	end
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function update(view: View)
	local model = view.model
	local humanoid = view.humanoid
	local share = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	view.hpFill.Size = UDim2.fromScale(share, 1)
	view.hpFill.BackgroundColor3 = if share < 0.3 then HP_LOW else HP_FILL
	view.hpText.Text = tostring(math.ceil(math.max(humanoid.Health, 0)))
	local buildup = model:GetAttribute("Buildup")
	local b = if typeof(buildup) == "number" then buildup else 0
	view.buildupFill.Size = UDim2.fromScale(math.clamp(b / CombatConfig.BuildupMax, 0, 1), 1)

	local list = {}
	local function tag(name: string)
		table.insert(list, string.format('<font color="%s">%s</font>', hex(TAG_COLORS[name] or Color3.new(1, 1, 1)), name))
	end
	if model:GetAttribute("Drafted") == true then
		tag("DRAFTED")
	end
	if model:GetAttribute("Infested") == true then
		tag("INFESTED")
	end
	if model:GetAttribute("Burnout") == true then
		tag("BURNOUT")
	end
	if model:GetAttribute("LotusForm") == true then
		tag("FORM")
	else
		local stage = model:GetAttribute("LotusStage")
		if stage == 2 then
			tag("L2")
		elseif stage == 3 then
			tag("L3")
		end
	end
	view.tags.Text = table.concat(list, "  ")
	view.gui.Enabled = humanoid.Health > 0
end

-- Every character with a Humanoid in the Workspace (players and the dummies' folder).
local function scan()
	local seen: { [Model]: boolean } = {}
	local function consider(model: Instance)
		if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
			seen[model] = true
			add(model)
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			consider(other.Character)
		end
	end
	local dummies = Workspace:FindFirstChild("TrainingDummies")
	if dummies then
		for _, child in dummies:GetChildren() do
			consider(child)
		end
	end
	for model in views do
		if not seen[model] or not model:IsDescendantOf(Workspace) or model == player.Character then
			remove(model)
		end
	end
end

local nextStep = 0
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now < nextStep then
		return
	end
	nextStep = now + STEP
	scan()
	for _, view in views do
		update(view)
	end
end)
