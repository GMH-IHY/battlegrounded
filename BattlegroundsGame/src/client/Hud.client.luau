--!strict
-- Hud (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > Hud
--
-- The in-game HUD, bottom centre, in the Die of Death style: a row of dark square skill slots
-- (keybind in the top-left corner, skill name under it, cooldown seconds over it), then the green HP
-- bar and the blue SP (stamina) bar, then two half-width bars: the dash cooldown and the Moth's
-- movement cooldown. While the lantern charges, the slots give way to "HOLD CTRL" + a charge bar,
-- and a crosshair shows in the middle of the screen (the throw aims there).
-- In burnout the SP bar turns orange and blinks (in steps) until the meter is full again.
--
-- The slots come from your build (Loadout.BuildOf / Loadout.Slots: weapon, magic, element,
-- secondary, race), rebuilt when it changes: today 1 (the sword's 1), 2 / 3 / 4 / R / G (the Lotus
-- Fungus; their names follow your meter stage, G's border lights up at a full meter), Q (Wind's push
-- / pull), RMB (the dagger), Ctrl (the Moth's lantern). Only a Lotus build shows the meter. Above HP sits the Lotus meter: three segments (stages at 40 / 80),
-- blinking cyan in the stage 3 form.
-- Your own statuses (DRAFTED / INFESTED) sit right of the HP bar, with a thin build-up strip under
-- it. On the right of the screen, the COMBO counter: hits and damage of the combo you're doing on
-- someone (their ComboHits / ComboDamage), yellow past the normal damage budget, red past the stage 3
-- one (CombatConfig Budget*).
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
ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatClient")
local CombatClient = require(ReplicatedStorage.Combat.CombatClient)
local Loadout = require(ReplicatedStorage.Combat.Loadout)
local Moves = require(ReplicatedStorage.Combat.Moves)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local CombatRemotes = require(ReplicatedStorage.Combat.CombatRemotes)
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
local LOTUS_FILL = Color3.fromRGB(15, 45, 54)
local LOTUS_TEXT = Color3.fromRGB(16, 152, 168)
local LOTUS_FORM = Color3.fromRGB(16, 152, 168)
local BURNOUT_FILL = Color3.fromRGB(230, 120, 30)
local BURNOUT_TEXT = Color3.fromRGB(255, 200, 150)
local DASH_FILL = Color3.fromRGB(235, 235, 235)
local MOTH_FILL = Color3.fromRGB(80, 200, 255)
local RECHARGE_FILL = Color3.fromRGB(120, 120, 126)
local CHARGE_FILL = Color3.fromRGB(80, 200, 255)

local SLOT = 62 -- slot size (px at 720p)
local SLOT_GAP = 8
local BAR_W, BAR_H = 150, 16
local HALF_GAP = 6
local HALF_W, HALF_H = (BAR_W - HALF_GAP) / 2, 9

local MAX_SLOTS = 10 -- the slot row is sized for this many

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
column.Size = UDim2.fromOffset(MAX_SLOTS * (SLOT + SLOT_GAP), 170)
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

-- Your build-up (how close you are to the opponent's element status): a thin strip under HP.
local buildupStrip = Instance.new("Frame")
buildupStrip.Name = "Buildup"
buildupStrip.AnchorPoint = Vector2.new(0, 1)
buildupStrip.Position = UDim2.fromScale(0, 1)
buildupStrip.Size = UDim2.fromOffset(0, 3)
buildupStrip.BackgroundColor3 = Color3.fromRGB(215, 235, 240)
buildupStrip.BorderSizePixel = 0
buildupStrip.ZIndex = 4
buildupStrip.Parent = hpBar.back
-- Your statuses, right of the HP bar.
local statusText = text(column, "Statuses", "", 12)
statusText.AnchorPoint = Vector2.new(0, 1)
statusText.Position = UDim2.new(0.5, BAR_W / 2 + 6, 1, -(HALF_H + 12 + 5 + BAR_H + 6))
statusText.Size = UDim2.fromOffset(140, BAR_H)
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.RichText = true

-- The combo counter (right of the screen).
local comboFrame = Instance.new("Frame")
comboFrame.Name = "Combo"
comboFrame.AnchorPoint = Vector2.new(1, 0.5)
comboFrame.Position = UDim2.new(1, -30, 0.45, 0)
comboFrame.Size = UDim2.fromOffset(160, 60)
comboFrame.BackgroundTransparency = 1
comboFrame.Visible = false
comboFrame.Parent = gui
local comboHits = text(comboFrame, "Hits", "", 30)
comboHits.Size = UDim2.new(1, 0, 0, 32)
comboHits.TextXAlignment = Enum.TextXAlignment.Right
local comboDamage = text(comboFrame, "Damage", "", 16)
comboDamage.Position = UDim2.fromOffset(0, 34)
comboDamage.Size = UDim2.new(1, 0, 0, 18)
comboDamage.TextXAlignment = Enum.TextXAlignment.Right
local COMBO_SHOW = 1.5 -- seconds it stays after the combo's last hit

-- Who you last hit, and when (from the server's hit effects).
local comboTarget: Model? = nil
local comboAt = -math.huge
CombatRemotes.Get().Fx.OnClientEvent:Connect(function(info: { [string]: any })
	if info.type == "Hit" and info.attacker == player.Character and typeof(info.target) == "Instance" and info.target:IsA("Model") then
		comboTarget = info.target
		comboAt = os.clock()
	end
end)

-- The Lotus meter, above HP: three segments (stage 1 / 2 / 3 at 40 / 80), the stage on the left.
local lotusBar = bar("Lotus", BAR_W, BAR_H, LOTUS_FILL, "L1", LOTUS_TEXT)
lotusBar.back.AnchorPoint = Vector2.new(0.5, 1)
lotusBar.back.Position = UDim2.new(0.5, 0, 1, -(HALF_H + 12 + 5 + BAR_H + 6 + BAR_H + 6))
lotusBar.back.Parent = column
for _, share in { CombatConfig.Stage2At / CombatConfig.LotusMax, CombatConfig.Stage3At / CombatConfig.LotusMax } do
	local tick = Instance.new("Frame")
	tick.Name = "StageMark"
	tick.AnchorPoint = Vector2.new(0.5, 0)
	tick.Position = UDim2.fromScale(share, 0)
	tick.Size = UDim2.new(0, 2, 1, 0)
	tick.BackgroundColor3 = Color3.new(0, 0, 0)
	tick.BorderSizePixel = 0
	tick.ZIndex = 2
	tick.Parent = lotusBar.back
end

local BARS_TOP = HALF_H + 12 + 5 + BAR_H + 6 + BAR_H + 6 + BAR_H + 8

-- Skill slots.
local slotRow = Instance.new("Frame")
slotRow.Name = "Slots"
slotRow.AnchorPoint = Vector2.new(0.5, 1)
slotRow.Position = UDim2.new(0.5, 0, 1, -BARS_TOP)
slotRow.Size = UDim2.fromOffset(MAX_SLOTS * (SLOT + SLOT_GAP) - SLOT_GAP, SLOT + 20)
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
local specs: { Loadout.HudSlot } = {}

local function makeSlot(i: number, spec: Loadout.HudSlot): Slot
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

	local name = text(holder, "SkillName", spec.names[1], 13)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, SLOT + 2)
	name.Size = UDim2.fromOffset(SLOT + SLOT_GAP + 20, 16)
	name.TextWrapped = false

	return {
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

local function block(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- The Moth slot's icon: a tiny lantern (cap, glowing core, base). Returns its core.
local function lanternIcon(slot: Slot): Frame
	local icon = Instance.new("Frame")
	icon.Name = "LanternIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.52)
	icon.Size = UDim2.fromOffset(22, 30)
	icon.BackgroundTransparency = 1
	icon.Parent = slot.box
	slot.icon.Visible = false
	block(icon, 8, 0, 6, 3, Color3.fromRGB(40, 70, 76)) -- handle
	block(icon, 3, 3, 16, 4, Color3.fromRGB(24, 48, 54)) -- cap
	local lanternCore = block(icon, 5, 7, 12, 16, MOTH_FILL)
	block(icon, 3, 23, 16, 4, Color3.fromRGB(24, 48, 54)) -- base
	return lanternCore
end

-- The race slot (Ctrl) and its lantern core, if the build has a Moth.
local raceSlot: Slot? = nil
local core: Frame? = nil
local builtFor = ""

-- (Re)builds the slot row for a build.
local function buildSlots(build: Loadout.Build)
	for _, slot in slots do
		slot.root:Destroy()
	end
	table.clear(slots)
	specs = Loadout.Slots(build)
	for i, spec in specs do
		slots[spec.key] = makeSlot(i, spec)
	end
	raceSlot = slots.Ctrl
	core = if raceSlot and build.Race == "Moth" then lanternIcon(raceSlot) else nil
end

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

-- Each cooldown group's full length (seconds), for the slot shade.
local cooldownTotal: { [string]: number } = {}
for _, move in Moves.All() do
	if move.Cooldown > 0 then
		cooldownTotal[move.CooldownGroup] = move.Cooldown
	end
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
	local burnout = character:GetAttribute("Burnout") == true
	-- Blink in steps (4 per second) while burnt out.
	local blink = burnout and math.floor(os.clock() * 4) % 2 == 0
	spBar.fill.BackgroundColor3 = if burnout then (if blink then BURNOUT_TEXT else BURNOUT_FILL) else SP_FILL
	if spBar.right then
		spBar.right.Text = if burnout then "OUT" else "SP"
		spBar.right.TextColor3 = if burnout then BURNOUT_TEXT else SP_TEXT
	end
	if spBar.left then
		spBar.left.Text = if burnout then "BURNOUT" else string.format("%d/%d", math.floor(spValue + 0.5), spTop)
	end

	-- Your build-up and statuses.
	local buildup = character:GetAttribute("Buildup")
	buildupStrip.Size = UDim2.new(math.clamp((if typeof(buildup) == "number" then buildup else 0) / CombatConfig.BuildupMax, 0, 1), 0, 0, 3)
	local statuses = {}
	if character:GetAttribute("Drafted") == true then
		table.insert(statuses, '<font color="#D7EBF0">DRAFTED</font>')
	end
	if character:GetAttribute("Infested") == true then
		table.insert(statuses, '<font color="#1098A8">INFESTED</font>')
	end
	statusText.Text = table.concat(statuses, "  ")

	-- The combo you're doing: its hits and damage (the target's ComboHits / ComboDamage).
	local target = comboTarget
	local showCombo = false
	if target and target.Parent and os.clock() - comboAt < COMBO_SHOW then
		local hits = target:GetAttribute("ComboHits")
		local damage = target:GetAttribute("ComboDamage")
		if typeof(hits) == "number" and hits >= 2 and typeof(damage) == "number" then
			showCombo = true
			comboHits.Text = string.format("%d HITS", hits)
			comboDamage.Text = string.format("%.1f DMG", damage)
			comboDamage.TextColor3 = if damage > CombatConfig.BudgetStage3 then Color3.fromRGB(255, 90, 80)
				elseif damage > CombatConfig.BudgetNormal then Color3.fromRGB(245, 205, 48)
				else WHITE
		end
	end
	comboFrame.Visible = showCombo

	-- The build: rebuild the slots when it changes.
	local build = Loadout.BuildOf(character)
	local key = table.concat({ build.Weapon, build.Secondary, build.Magic, build.Element, build.Race }, "/")
	if key ~= builtFor then
		builtFor = key
		buildSlots(build)
	end
	local magic = Loadout.Items[build.Magic]
	lotusBar.back.Visible = magic ~= nil and magic.meter == "Lotus"

	-- The Lotus meter and the slot names of the current stage.
	local meter = character:GetAttribute("Lotus")
	local stage = character:GetAttribute("LotusStage")
	local form = character:GetAttribute("LotusForm") == true
	local meterValue = if typeof(meter) == "number" then meter else 0
	local stageValue = if typeof(stage) == "number" then stage else 1
	setFill(lotusBar, meterValue / CombatConfig.LotusMax)
	local glow = form and math.floor(os.clock() * 4) % 2 == 0
	lotusBar.fill.BackgroundColor3 = if glow then LOTUS_FORM else LOTUS_FILL
	if lotusBar.left then
		lotusBar.left.Text = if form then "FORM" else string.format("%d/%d", math.floor(meterValue + 0.5), CombatConfig.LotusMax)
	end
	if lotusBar.right then
		lotusBar.right.Text = "L" .. stageValue
	end
	for _, spec in specs do
		-- One name per stage (Lotus), else the one name.
		slots[spec.key].name.Text = spec.names[math.clamp(stageValue, 1, #spec.names)]
	end
	local formSlot = if magic and magic.meter == "Lotus" then slots.G else nil
	if formSlot then
		local formReady = meterValue >= CombatConfig.LotusMax and not form
		formSlot.boxStroke.Color = if formReady then LOTUS_TEXT else SLOT_BORDER
		formSlot.boxStroke.Thickness = if formReady then 2 else 1
	end

	-- Weapon / secondary / magic cooldowns.
	local combat = CombatClient.Get(character)
	for _, spec in specs do
		local group = spec.cooldown
		if group then
			local slot = slots[spec.key]
			local left = if combat then combat:GetCooldown(group) else 0
			local total = if combat and left > 0 then combat:GetCooldownTotal(group) else (cooldownTotal[group] or 1)
			slot.shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
			slot.timer.Text = if left > 0 then formatSeconds(left) else ""
			local ready = left <= 0
			if ready and not slot.ready then
				pop(slot.box)
			end
			slot.ready = ready
		end
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
	local charging = false
	if moth and isMoth and raceSlot and core then
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
		local out = state ~= "Hip" and state ~= "Charging"
		raceSlot.name.Text = if out and state ~= "Returning" then "Recall" else "Lantern"
		-- No throwing yet: knocked down, or just back in hand.
		local knock = moth:GetKnockLockout()
		local lockout = moth:GetThrowLockout()
		if lockout > 0 then
			local lockTotal = if knock > 0 then Config.LanternKnockLockout else Config.LanternGrabCooldown
			raceSlot.shade.Size = UDim2.fromScale(1, math.clamp(lockout / math.max(lockTotal, 1e-3), 0, 1))
			raceSlot.timer.Text = formatSeconds(lockout)
		else
			raceSlot.shade.Size = UDim2.fromScale(1, 0)
			raceSlot.timer.Text = ""
		end
		raceSlot.status.Text = if flight == "Free" then "FLYING"
			elseif state == "Thrown" then "THROWN"
			elseif state == "Suspended" then (if moth:InsideLight() then "HOLD SPACE" else "LIT")
			elseif state == "Dropped" then (if knock > 0 then "KNOCKED" else "PICK UP")
			elseif state == "Returning" then "RETURNING"
			else ""
		core.BackgroundColor3 = if out then Color3.fromRGB(40, 70, 76) else MOTH_FILL
		raceSlot.boxStroke.Color = if charging or flight then MOTH_FILL else SLOT_BORDER
		raceSlot.boxStroke.Thickness = if charging or flight then 2 else 1
		if charging then
			setFill(chargeBar, moth:GetCharge())
		end
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
