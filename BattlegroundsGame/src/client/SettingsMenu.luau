--!strict
-- SettingsMenu (ModuleScript)
-- Location: StarterPlayer > StarterPlayerScripts > SettingsMenu
--
-- The settings menu: a gear button in the top-right corner opens a panel of switches and buttons,
-- grouped in sections. Nothing uses function keys (Studio and the Roblox player both keep most of
-- them for themselves), so every debug tool lives here:
--   local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))
--   local setShown = SettingsMenu.AddToggle("Debug", "Hitbox view", false, function(on) ... end)
--   setShown(false) -- when the tool turns itself off (its own Close button), so the switch agrees
--   SettingsMenu.AddButton("Debug", "Animation gallery", function() ... end)
-- The UI is built on the first require; items show in the order they're added, sections in SECTIONS
-- order (unknown sections go last).

local Players = game:GetService("Players")

local SECTIONS = { "Game", "Debug" }

local BG = Color3.fromRGB(16, 16, 18)
local ROW = Color3.fromRGB(30, 30, 34)
local BORDER = Color3.fromRGB(70, 70, 76)
local TEXT = Color3.fromRGB(235, 235, 235)
local MUTED = Color3.fromRGB(150, 150, 156)
local ON = Color3.fromRGB(46, 160, 38)
local OFF = Color3.fromRGB(60, 60, 66)
local FONT = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)
local ROW_H = 30
local WIDTH = 260

local SettingsMenu = {}

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 250

local function stroke(parent: GuiObject)
	local s = Instance.new("UIStroke")
	s.Color = BORDER
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local gear = Instance.new("TextButton")
gear.Name = "Gear"
gear.AnchorPoint = Vector2.new(1, 0)
gear.Position = UDim2.new(1, -10, 0, 6)
gear.Size = UDim2.fromOffset(34, 34)
gear.BackgroundColor3 = BG
gear.BackgroundTransparency = 0.2
gear.BorderSizePixel = 0
gear.AutoButtonColor = true
gear.FontFace = FONT
gear.TextSize = 22
gear.TextColor3 = TEXT
gear.Text = "⚙"
gear.Parent = gui
stroke(gear)

local panel = Instance.new("ScrollingFrame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, 46)
panel.Size = UDim2.new(0, WIDTH, 0.7, 0)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 4
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Visible = false
panel.Parent = gui
stroke(panel)

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 4)
list.Parent = panel
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 10)
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = panel

gear.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

-- Sections -----------------------------------------------------------------------------------------

local sectionOrder: { [string]: number } = {}
local sectionCount: { [string]: number } = {}

local function sectionIndex(section: string): number
	local known = table.find(SECTIONS, section)
	if known then
		return known
	end
	if not sectionOrder[section] then
		local n = #SECTIONS
		for _ in sectionOrder do
			n += 1
		end
		sectionOrder[section] = n + 1
	end
	return sectionOrder[section]
end

-- LayoutOrder for the next item of a section (its header comes first).
local function nextOrder(section: string): number
	local base = sectionIndex(section) * 1000
	if not sectionCount[section] then
		sectionCount[section] = 0
		local header = Instance.new("TextLabel")
		header.Name = section
		header.LayoutOrder = base
		header.Size = UDim2.new(1, 0, 0, 22)
		header.BackgroundTransparency = 1
		header.FontFace = FONT
		header.TextSize = 13
		header.TextColor3 = MUTED
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = string.upper(section)
		header.Parent = panel
	end
	sectionCount[section] += 1
	return base + sectionCount[section]
end

local function row(section: string, label: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = label
	button.LayoutOrder = nextOrder(section)
	button.Size = UDim2.new(1, 0, 0, ROW_H)
	button.BackgroundColor3 = ROW
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.FontFace = FONT
	button.TextSize = 14
	button.TextColor3 = TEXT
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = "  " .. label
	button.Parent = panel
	return button
end

-- Items --------------------------------------------------------------------------------------------

-- A switch. onChange runs on every change (not for the initial value). Returns a setter that moves
-- the switch without calling onChange, for when the tool turns itself on or off.
function SettingsMenu.AddToggle(section: string, label: string, initial: boolean, onChange: (boolean) -> ()): (boolean) -> ()
	local button = row(section, label)
	local switch = Instance.new("Frame")
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.new(1, -6, 0.5, 0)
	switch.Size = UDim2.fromOffset(34, 16)
	switch.BorderSizePixel = 0
	switch.Parent = button
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(14, 14)
	knob.BackgroundColor3 = TEXT
	knob.BorderSizePixel = 0
	knob.Parent = switch

	local value = initial
	local function show()
		switch.BackgroundColor3 = if value then ON else OFF
		knob.Position = if value then UDim2.new(1, -15, 0.5, 0) else UDim2.new(0, 1, 0.5, 0)
	end
	show()
	button.Activated:Connect(function()
		value = not value
		show()
		onChange(value)
	end)
	return function(on: boolean)
		value = on
		show()
	end
end

-- A plain button (runs onPress each click). Returns the button so the caller can relabel it.
function SettingsMenu.AddButton(section: string, label: string, onPress: () -> ()): TextButton
	local button = row(section, label)
	button.TextXAlignment = Enum.TextXAlignment.Center
	button.Text = label
	button.Activated:Connect(onPress)
	return button
end

function SettingsMenu.Close()
	panel.Visible = false
end

gui.Parent = player:WaitForChild("PlayerGui")

return SettingsMenu
