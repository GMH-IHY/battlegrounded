--!strict
-- Hud (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > Hud
--
-- The in-game HUD, bottom centre, in the Die of Death style: a row of dark square skill slots
-- (keybind in the top-left corner, skill name under it, cooldown seconds over it), then the green HP
-- bar and the blue SP (stamina) bar, then two half-width bars: the dash cooldown and the Moth's
-- movement cooldown. While the lantern charges, the slots give way to "HOLD CTRL" + a charge bar,
-- and a crosshair shows in the middle of the screen (the throw aims there).
--
-- Only the Race (Ctrl) slot is live for now; the others are placeholders for the build slots in the
-- design plan (weapon, magic, element, ultimate, secondary) until those systems exist.
-- Everything is sized for a 720 px tall screen and scaled to the real one (UIScale).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local movement = ReplicatedStorage:WaitForChild("Movement")
movement:WaitForChild("Dash")
movement:WaitForChild("Lantern")
movement:WaitForChild("MovementConfig")
local Dash = require(ReplicatedStorage.Movement.Dash)
local Lantern = require(ReplicatedStorage.Movement.Lantern)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- LOOK ------------------------------------------------------------------------------------------
local REF_HEIGHT = 720
local FONT = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)
local WHITE = Color3.new(1, 1, 1)
local SLOT_BG = Color3.fromRGB(14, 14, 16)
local SLOT_BORDER = Color3.fromRGB(70, 70, 76)
local BAR_BG = Color3.fromRGB(22, 22, 24)
local HP_FILL = Color3.fromRGB(46, 160, 38)
local HP_TEXT = Color3.fromRGB(190, 255, 160)
local SP_FILL = Color3.fromRGB(28, 104, 196)
local SP_TEXT = Color3.fromRGB(170, 215, 255)
local DASH_FILL = Color3.fromRGB(235, 235, 235)
local MOTH_FILL = Color3.fromRGB(80, 200, 255)
local RECHARGE_FILL = Color3.fromRGB(120, 120, 126)
local CHARGE_FILL = Color3.fromRGB(80, 200, 255)

local SLOT = 62 -- slot size (px at 720p)
local SLOT_GAP = 8
local BAR_W, BAR_H = 150, 16
local HALF_GAP = 6
local HALF_W, HALF_H = (BAR_W - HALF_GAP) / 2, 9

-- Placeholder skills (design plan keys) + the live race slot.
type SlotSpec = { key: string, name: string, live: string? }
local SLOTS: { SlotSpec } = {
	{ key = "1", name = "Weapon" },
	{ key = "2", name = "Magic I" },
	{ key = "3", name = "Magic II" },
	{ key = "4", name = "Magic III" },
	{ key = "R", name = "Magic Special" },
	{ key = "Q", name = "Element" },
	{ key = "G", name = "Ultimate" },
	{ key = "T", name = "Secondary" },
	{ key = "Ctrl", name = "Race", live = "Race" },
}

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- BUILD ------------------------------------------------------------------------------------------

local function text(parent: Instance, name: string, value: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = value
	label.TextSize = size
	label.TextColor3 = color or WHITE
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = parent
	return label
end

local function corner(parent: Instance, px: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
end

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = playerGui

local scale = Instance.new("UIScale")
scale.Parent = gui

-- The bottom-centre column; everything stacks upward from the bottom edge.
local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0.5, 1)
column.Position = UDim2.new(0.5, 0, 1, -10)
column.Size = UDim2.fromOffset(#SLOTS * (SLOT + SLOT_GAP), 170)
column.BackgroundTransparency = 1
column.Parent = gui

-- A plain bar: dark back, coloured fill (Scale X = fraction), optional texts.
type Bar = { back: Frame, fill: Frame, left: TextLabel?, right: TextLabel? }
local function bar(name: string, w: number, h: number, fillColor: Color3, rightText: string?, rightColor: Color3?): Bar
	local back = Instance.new("Frame")
	back.Name = name
	back.Size = UDim2.fromOffset(w, h)
	back.BackgroundColor3 = BAR_BG
	back.BackgroundTransparency = 0.1
	back.BorderSizePixel = 0
	corner(back, 3)
	stroke(back, Color3.new(0, 0, 0), 1)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	corner(fill, 3)
	fill.Parent = back
	local left, right
	if rightText then
		left = text(back, "Value", "", h - 3)
		left.Size = UDim2.new(1, -30, 1, 0)
		left.Position = UDim2.fromOffset(4, 0)
		left.TextXAlignment = Enum.TextXAlignment.Center
		left.ZIndex = 3
		right = text(back, "Tag", rightText, h - 3, rightColor)
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, -5, 0, 0)
		right.Size = UDim2.new(0, 30, 1, 0)
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.ZIndex = 3
	end
	return { back = back, fill = fill, left = left, right = right }
end

-- Bars, bottom up: half bars, SP, HP.
local halfRow = Instance.new("Frame")
halfRow.Name = "Cooldowns"
halfRow.AnchorPoint = Vector2.new(0.5, 1)
halfRow.Position = UDim2.new(0.5, 0, 1, 0)
halfRow.Size = UDim2.fromOffset(BAR_W, HALF_H + 12)
halfRow.BackgroundTransparency = 1
halfRow.Parent = column

local dashBar = bar("Dash", HALF_W, HALF_H, DASH_FILL)
dashBar.back.AnchorPoint = Vector2.new(0, 1)
dashBar.back.Position = UDim2.fromScale(0, 1)
dashBar.back.Parent = halfRow
local dashLabel = text(halfRow, "DashLabel", "DASH", 10)
dashLabel.AnchorPoint = Vector2.new(0, 1)
dashLabel.Position = UDim2.new(0, 2, 1, -HALF_H - 1)
dashLabel.Size = UDim2.fromOffset(HALF_W, 11)
dashLabel.TextXAlignment = Enum.TextXAlignment.Left

local mothBar = bar("Moth", HALF_W, HALF_H, MOTH_FILL)
mothBar.back.AnchorPoint = Vector2.new(1, 1)
mothBar.back.Position = UDim2.fromScale(1, 1)
mothBar.back.Parent = halfRow
local mothLabel = text(halfRow, "MothLabel", "WINGS", 10)
mothLabel.AnchorPoint = Vector2.new(1, 1)
mothLabel.Position = UDim2.new(1, -2, 1, -HALF_H - 1)
mothLabel.Size = UDim2.fromOffset(HALF_W, 11)
mothLabel.TextXAlignment = Enum.TextXAlignment.Right

local spBar = bar("SP", BAR_W, BAR_H, SP_FILL, "SP", SP_TEXT)
spBar.back.AnchorPoint = Vector2.new(0.5, 1)
spBar.back.Position = UDim2.new(0.5, 0, 1, -(HALF_H + 12 + 5))
spBar.back.Parent = column

local hpBar = bar("HP", BAR_W, BAR_H, HP_FILL, "HP", HP_TEXT)
hpBar.back.AnchorPoint = Vector2.new(0.5, 1)
hpBar.back.Position = UDim2.new(0.5, 0, 1, -(HALF_H + 12 + 5 + BAR_H + 6))
hpBar.back.Parent = column

local BARS_TOP = HALF_H + 12 + 5 + BAR_H + 6 + BAR_H + 8

-- Skill slots.
local slotRow = Instance.new("Frame")
slotRow.Name = "Slots"
slotRow.AnchorPoint = Vector2.new(0.5, 1)
slotRow.Position = UDim2.new(0.5, 0, 1, -BARS_TOP)
slotRow.Size = UDim2.fromOffset(#SLOTS * (SLOT + SLOT_GAP) - SLOT_GAP, SLOT + 20)
slotRow.BackgroundTransparency = 1
slotRow.Parent = column
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, SLOT_GAP)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = slotRow

type Slot = {
	root: Frame,
	box: Frame,
	boxStroke: UIStroke,
	icon: Frame,
	shade: Frame,
	timer: TextLabel,
	status: TextLabel,
	name: TextLabel,
	key: TextLabel,
	ready: boolean,
}
local slots: { [string]: Slot } = {}

for i, spec in SLOTS do
	local holder = Instance.new("Frame")
	holder.Name = "Slot_" .. spec.key
	holder.LayoutOrder = i
	holder.Size = UDim2.fromOffset(SLOT, SLOT + 20)
	holder.BackgroundTransparency = 1
	holder.Parent = slotRow

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(SLOT, SLOT)
	box.BackgroundColor3 = SLOT_BG
	box.BackgroundTransparency = 0.25
	box.BorderSizePixel = 0
	box.ClipsDescendants = true
	box.Parent = holder
	local boxStroke = Instance.new("UIStroke")
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Color = SLOT_BORDER
	boxStroke.Thickness = 1
	boxStroke.Parent = box

	-- Placeholder icon: an empty inset frame (the real icon art goes here later).
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.52)
	icon.Size = UDim2.fromOffset(SLOT - 22, SLOT - 22)
	icon.BackgroundTransparency = 1
	icon.Parent = box
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(48, 48, 52)
	iconStroke.Thickness = 1
	iconStroke.Parent = icon

	-- Cooldown shade (fills from the bottom by the time left) + seconds.
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.ZIndex = 2
	shade.Parent = box
	local timer = text(box, "Timer", "", 22)
	timer.Size = UDim2.fromScale(1, 1)
	timer.ZIndex = 3
	local status = text(box, "Status", "", 12)
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -3)
	status.Size = UDim2.new(1, 0, 0, 12)
	status.ZIndex = 3

	local key = text(box, "Key", spec.key, if #spec.key > 1 then 13 else 18)
	key.Position = UDim2.fromOffset(4, 2)
	key.Size = UDim2.fromOffset(SLOT - 8, 18)
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextYAlignment = Enum.TextYAlignment.Top
	key.ZIndex = 4

	local name = text(holder, "SkillName", spec.name, 13)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, SLOT + 2)
	name.Size = UDim2.fromOffset(SLOT + SLOT_GAP + 20, 16)
	name.TextWrapped = false

	-- Placeholders are dimmed so it's clear they don't do anything yet.
	if not spec.live then
		box.BackgroundTransparency = 0.45
		key.TextTransparency = 0.25
		name.TextTransparency = 0.3
	end

	slots[spec.key] = {
		root = holder,
		box = box,
		boxStroke = boxStroke,
		icon = icon,
		shade = shade,
		timer = timer,
		status = status,
		name = name,
		key = key,
		ready = true,
	}
end

-- The Moth slot's icon: a tiny lantern (cap, glowing core, base).
local raceSlot = slots.Ctrl
local lanternIcon = Instance.new("Frame")
lanternIcon.Name = "LanternIcon"
lanternIcon.AnchorPoint = Vector2.new(0.5, 0.5)
lanternIcon.Position = UDim2.fromScale(0.5, 0.52)
lanternIcon.Size = UDim2.fromOffset(22, 30)
lanternIcon.BackgroundTransparency = 1
lanternIcon.Visible = false
lanternIcon.Parent = raceSlot.box
local function block(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end
block(lanternIcon, 8, 0, 6, 3, Color3.fromRGB(40, 70, 76)) -- handle
block(lanternIcon, 3, 3, 16, 4, Color3.fromRGB(24, 48, 54)) -- cap
local core = block(lanternIcon, 5, 7, 12, 16, MOTH_FILL)
block(lanternIcon, 3, 23, 16, 4, Color3.fromRGB(24, 48, 54)) -- base

-- Charge bar (replaces the slots while charging).
local chargeArea = Instance.new("Frame")
chargeArea.Name = "Charge"
chargeArea.AnchorPoint = Vector2.new(0.5, 1)
chargeArea.Position = UDim2.new(0.5, 0, 1, -BARS_TOP)
chargeArea.Size = UDim2.fromOffset(320, 52)
chargeArea.BackgroundTransparency = 1
chargeArea.Visible = false
chargeArea.Parent = column
local chargeText = text(chargeArea, "Label", "HOLD CTRL", 26)
chargeText.Size = UDim2.new(1, 0, 0, 28)
local chargeBar = bar("Bar", 320, 18, CHARGE_FILL)
chargeBar.back.AnchorPoint = Vector2.new(0.5, 1)
chargeBar.back.Position = UDim2.fromScale(0.5, 1)
chargeBar.back.Parent = chargeArea

-- Crosshair (middle of the screen = where the throw aims).
local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(28, 28)
crosshair.BackgroundTransparency = 1
crosshair.Visible = false
crosshair.Parent = gui

local crosshairTicks: { Frame } = {}
local function tick(x: number, y: number, w: number, h: number)
	local f = block(crosshair, x, y, w, h, WHITE)
	stroke(f, Color3.new(0, 0, 0), 1)
	table.insert(crosshairTicks, f)
end
tick(13, 0, 2, 8)
tick(13, 20, 2, 8)
tick(0, 13, 8, 2)
tick(20, 13, 8, 2)
tick(13, 13, 2, 2)

-- Target-lock indicator (diamond framing the center dot when soft-locked onto an enemy)
local lockDiamond = Instance.new("Frame")
lockDiamond.Name = "LockDiamond"
lockDiamond.AnchorPoint = Vector2.new(0.5, 0.5)
lockDiamond.Position = UDim2.fromScale(0.5, 0.5)
lockDiamond.Size = UDim2.fromOffset(18, 18)
lockDiamond.BackgroundTransparency = 1
lockDiamond.Rotation = 45
stroke(lockDiamond, Color3.fromRGB(255, 85, 75), 1.5)
lockDiamond.Visible = false
lockDiamond.Parent = crosshair

-- UPDATE -----------------------------------------------------------------------------------------

local POP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function pop(target: GuiObject)
	local s = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = target
	s.Scale = 1.12
	TweenService:Create(s, POP, { Scale = 1 }):Play()
end

local function setFill(b: Bar, fraction: number)
	b.fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	b.fill.Visible = fraction > 0.001
end

local function formatSeconds(t: number): string
	return if t >= 10 then string.format("%ds", math.ceil(t)) else string.format("%.1fs", t)
end

local dashWasReady = true
local mothWasReady = true

local function update()
	local camera = Workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(camera.ViewportSize.Y / REF_HEIGHT, 0.6, 1.6)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	gui.Enabled = character ~= nil and humanoid ~= nil
	if not character or not humanoid then
		return
	end

	-- HP / SP.
	local maxHp = math.max(humanoid.MaxHealth, 1)
	local hp = math.max(humanoid.Health, 0)
	setFill(hpBar, hp / maxHp)
	if hpBar.left then
		hpBar.left.Text = string.format("%d/%d", math.ceil(hp), math.floor(maxHp + 0.5))
	end
	local sp = character:GetAttribute("Stamina")
	local spMax = character:GetAttribute("StaminaMax")
	local spValue = if typeof(sp) == "number" then sp else Config.StaminaMax
	local spTop = if typeof(spMax) == "number" then spMax else Config.StaminaMax
	setFill(spBar, spValue / math.max(spTop, 1))
	if spBar.left then
		spBar.left.Text = string.format("%d/%d", math.floor(spValue + 0.5), spTop)
	end

	-- Dash cooldown (full = ready).
	local dash = Dash.Get(character)
	local dashLeft = if dash then dash:GetCooldownRemaining() else 0
	setFill(dashBar, 1 - dashLeft / math.max(Config.DashCooldown, 1e-3))
	local dashReady = dashLeft <= 0
	dashBar.fill.BackgroundColor3 = if dashReady then DASH_FILL else RECHARGE_FILL
	if dashReady and not dashWasReady then
		pop(dashBar.back)
	end
	dashWasReady = dashReady

	-- Moth: movement cooldown bar + the race slot.
	local moth = Lantern.Get(character)
	local isMoth = moth ~= nil and moth:IsMoth()
	mothBar.back.Visible = isMoth
	mothLabel.Visible = isMoth
	lanternIcon.Visible = isMoth
	raceSlot.icon.Visible = not isMoth
	local charging = false
	if moth and isMoth then
		local left, total = moth:GetMothCooldown()
		setFill(mothBar, 1 - left / math.max(total, 1e-3))
		local ready = left <= 0
		mothBar.fill.BackgroundColor3 = if ready then MOTH_FILL else RECHARGE_FILL
		if ready and not mothWasReady then
			pop(mothBar.back)
		end
		mothWasReady = ready

		local state = moth:GetState()
		charging = state == "Charging"
		local flight = moth:GetFlight()
		raceSlot.name.Text = if state == "Hip" or state == "Charging" then "Lantern" else "Fly"
		local grab = moth:GetGrabCooldown()
		if state == "Hip" and grab > 0 then
			raceSlot.shade.Size = UDim2.fromScale(1, grab / math.max(Config.LanternGrabCooldown, 1e-3))
			raceSlot.timer.Text = formatSeconds(grab)
		else
			raceSlot.shade.Size = UDim2.fromScale(1, 0)
			raceSlot.timer.Text = ""
		end
		raceSlot.status.Text = if flight then "FLYING"
			elseif state == "Thrown" then "THROWN"
			elseif state == "Suspended" then "HANGING"
			elseif state == "Dropped" then "GRAB IT"
			else ""
		local out = state ~= "Hip" and state ~= "Charging"
		core.BackgroundColor3 = if out then Color3.fromRGB(40, 70, 76) else MOTH_FILL
		raceSlot.boxStroke.Color = if charging or flight then MOTH_FILL else SLOT_BORDER
		raceSlot.boxStroke.Thickness = if charging or flight then 2 else 1
		if charging then
			setFill(chargeBar, moth:GetCharge())
		end
	else
		raceSlot.name.Text = "Race"
		raceSlot.status.Text = ""
		raceSlot.timer.Text = ""
		raceSlot.shade.Size = UDim2.fromScale(1, 0)
		raceSlot.boxStroke.Color = SLOT_BORDER
		raceSlot.boxStroke.Thickness = 1
	end
	slotRow.Visible = not charging
	chargeArea.Visible = charging

	local shiftLocked = character:GetAttribute("ShiftLock") == true
	local targetLocked = character:GetAttribute("LanternTargetAcquired") == true
	crosshair.Visible = charging or shiftLocked
	lockDiamond.Visible = charging and targetLocked
	local tickColor = if (charging and targetLocked) then Color3.fromRGB(255, 85, 75) else WHITE
	for _, t in crosshairTicks do
		t.BackgroundColor3 = tickColor
	end
end

RunService.RenderStepped:Connect(update)
