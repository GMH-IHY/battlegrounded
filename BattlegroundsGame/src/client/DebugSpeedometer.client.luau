--!strict
-- DebugSpeedometer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > DebugSpeedometer
--
-- On-screen speed counter for checking movement against MovementConfig, plus combat frame data
-- (the move you're in, its frame and phase, what your last move did and its frame advantage).
-- Settings menu (gear) > Debug > Speedometer hides/shows it. Turn it off with MovementConfig.DebugSpeedometer = false.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("CharacterMotor")
movementFolder:WaitForChild("MovementConfig")
movementFolder:WaitForChild("Dash")
movementFolder:WaitForChild("WallHop")
movementFolder:WaitForChild("LandingRoll")
movementFolder:WaitForChild("AutoParkour")
movementFolder:WaitForChild("Lantern")
movementFolder:WaitForChild("Stamina")

local CharacterMotor = require(ReplicatedStorage.Movement.CharacterMotor)
local Dash = require(ReplicatedStorage.Movement.Dash)
local WallHop = require(ReplicatedStorage.Movement.WallHop)
local LandingRoll = require(ReplicatedStorage.Movement.LandingRoll)
local AutoParkour = require(ReplicatedStorage.Movement.AutoParkour)
local Lantern = require(ReplicatedStorage.Movement.Lantern)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local Perf = require(ReplicatedStorage.Movement.Perf)
ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatClient")
local CombatClient = require(ReplicatedStorage.Combat.CombatClient)

if not Config.DebugSpeedometer then
	return
end

local REFRESH_INTERVAL = 1 / 15 -- text updates per second (peaks are still tracked every frame)
local ON_TARGET_TOLERANCE = 0.5

local GREEN = "#6BE36B"
local YELLOW = "#F5CD30"
local RED = "#FF6060"
local GREY = "#BBBBBB"

local player = Players.LocalPlayer

-- UI (classic look: dark translucent box, bold Arial) -------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DebugSpeedometer"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0, 1)
frame.Position = UDim2.new(0, 10, 1, -10)
frame.Size = UDim2.fromOffset(460, 240)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BackgroundTransparency = 0.45
frame.BorderSizePixel = 0
frame.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingTop = UDim.new(0, 6)
padding.Parent = frame

local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.ArialBold
label.TextSize = 14
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0.6
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.RichText = true
label.Text = "Waiting for character..."
label.Parent = frame

gui.Parent = player:WaitForChild("PlayerGui")

SettingsMenu.AddToggle("Debug", "Speedometer + frame data", true, function(on: boolean)
	gui.Enabled = on
end)

-- Tracking -------------------------------------------------------------------

local lastMode = ""
local takeoffY = 0
local apexY = 0
local airPeakSpeed = 0
local airMaxFall = 0

local lastJumpHeight = 0
local lastAirPeakSpeed = 0
local lastMaxFall = 0

local refreshTimer = 0

local function colour(text: string, hex: string): string
	return string.format('<font color="%s">%s</font>', hex, text)
end

local function onFrame(dt: number)
	local character = player.Character
	local motor = if character then CharacterMotor.Get(character) else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not motor or not humanoid or not root or not root:IsA("BasePart") then
		label.Text = "Waiting for character..."
		lastMode = ""
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local mode = motor:GetMode()

	-- Airtime tracking: jump height, speed carried, fastest fall.
	if mode == "Air" and lastMode ~= "Air" then
		takeoffY = root.Position.Y
		apexY = takeoffY
		airPeakSpeed = horizontal
		airMaxFall = 0
	elseif mode == "Air" then
		apexY = math.max(apexY, root.Position.Y)
		airPeakSpeed = math.max(airPeakSpeed, horizontal)
		airMaxFall = math.max(airMaxFall, -velocity.Y)
	elseif lastMode == "Air" then
		lastJumpHeight = apexY - takeoffY
		lastAirPeakSpeed = airPeakSpeed
		lastMaxFall = airMaxFall
	end
	lastMode = mode

	refreshTimer += dt
	if refreshTimer < REFRESH_INTERVAL then
		return
	end
	refreshTimer = 0

	-- Speed line, coloured against the target speed while on the ground.
	local target = motor:GetTargetSpeed()
	local moving = humanoid.MoveDirection.Magnitude > 0.01
	local speedText = string.format("%.1f", horizontal)
	local targetText
	if mode == "Ground" and moving then
		local gap = math.abs(horizontal - target)
		local hex = if gap <= ON_TARGET_TOLERANCE then GREEN elseif gap <= 3 then YELLOW else RED
		speedText = colour(speedText, hex)
		targetText = string.format("/ %.1f %s", target, if motor:IsSprinting() then "(run)" else "(walk)")
	else
		targetText = colour("/ -", GREY)
	end

	local fallText = string.format("%.1f", if mode == "Air" then airMaxFall else lastMaxFall)
	local fallMax = math.max(airMaxFall, lastMaxFall)
	if fallMax > Config.TerminalVelocity + 1 then
		fallText = colour(fallText, RED)
	end

	local dash = if character then Dash.Get(character) else nil
	local dashText = "Dash: -"
	if dash then
		local cooldown = dash:GetCooldownRemaining()
		local state = if dash:IsBusy()
			then colour(dash:GetPhase() .. " " .. dash:GetKind(), YELLOW)
			elseif cooldown > 0 then colour(string.format("%.1fs", cooldown), RED)
			else colour("ready", GREEN)
		dashText = string.format("Dash: %s   last %.1f studs", state, dash:GetLastDistance())
	end

	-- Frame data: the move you're in (frame / phase), what the last one did, its advantage.
	local combat = if character then CombatClient.Get(character) else nil
	local combatText = "Combat: -"
	if combat and character then
		local combatState = tostring(character:GetAttribute("CombatState") or "-")
		local moveId = combat:GetMoveId()
		local moveText = if moveId
			then colour(string.format("%s  f%d %s", moveId, combat:GetFrame(), combat:GetPhase()), YELLOW)
			else "-"
		local advantage = combat:GetLastAdvantage()
		local advText = if advantage == nil then ""
			else colour(string.format("  %+d", advantage), if advantage >= 0 then GREEN else RED)
		combatText = string.format("Combat: %s   %s   last %s %s%s", combatState, moveText, combat:GetLastMove(),
			combat:GetLastResult(), advText)
	end

	local hop = if character then WallHop.Get(character) else nil
	local hopText = "Wall hops: -"
	if hop then
		hopText = string.format(
			"Wall hops: %d / %d left%s",
			hop:GetHopsLeft(),
			hop:GetMaxHops(),
			if hop:IsRunning() then "   " .. colour("wall run", YELLOW)
				elseif hop:GetLastFailure() ~= "" then "   " .. colour(hop:GetLastFailure(), GREY)
				else ""
		)
	end

	local roll = if character then LandingRoll.Get(character) else nil
	local rollText = "Roll: -"
	if roll then
		local info = roll:GetLastInfo()
		rollText = "Roll: "
			.. (if roll:IsRolling() then colour("rolling", YELLOW)
				elseif info ~= "" then colour(info, GREY)
				else "-")
	end

	local parkour = if character then AutoParkour.Get(character) else nil
	local parkourText = "Parkour: -"
	if parkour then
		local info = parkour:GetLastInfo()
		parkourText = "Parkour: "
			.. (if parkour:IsBusy() then colour(parkour:GetAction(), YELLOW)
				elseif info ~= "" then colour(info, GREY)
				else "-")
	end

	local stamina = if character then Stamina.Get(character) else nil
	local staminaText = if stamina
		then string.format("Stamina: %d / %d%s", math.floor(stamina:GetValue() + 0.5), stamina:GetMax(),
			if stamina:IsBurnout() then "  " .. colour("BURNOUT", RED) else "")
		else "Stamina: -"
	local lantern = if character then Lantern.Get(character) else nil
	local lanternText = "Lantern: -"
	if lantern and lantern:IsMoth() then
		local flight = lantern:GetFlight()
		local tag = lantern:GetTagTarget()
		local extra = if lantern:GetState() == "Charging"
			then string.format(" %d%%", math.floor(lantern:GetCharge() * 100 + 0.5))
			elseif lantern:GetGrabCooldown() > 0 then string.format(" (throw in %.1fs)", lantern:GetGrabCooldown())
			else ""
		lanternText = string.format("Lantern: %s%s%s", lantern:GetState(), if lantern:IsResting() then " (lying)" else "", extra)
			.. (if tag then colour("  tagged " .. tag.Name, YELLOW) else "")
			.. "\n"
			.. (if flight
				then colour(string.format("Flying %s  %.0f studs/s  turn %.0f deg/s", flight, lantern:GetSpeed(), lantern:GetTurnRate()), YELLOW)
				else "Fly: " .. colour(if lantern:GetLastInfo() ~= "" then lantern:GetLastInfo() else "-", GREY))
	elseif character then
		lanternText = "Race: " .. tostring(character:GetAttribute("Race") or "-")
	end

	local rig = if humanoid.RigType == Enum.HumanoidRigType.R6 then colour("R6", GREEN) else colour("R15", RED)

	label.Text = table.concat({
		string.format("Speed: %s %s", speedText, targetText),
		string.format("Vertical: %.1f", velocity.Y),
		string.format(
			"Mode: %s   Sprint: %s   HP speed: %s",
			mode,
			if motor:IsSprinting() then "yes" else "no",
			if motor:GetHealthSpeedScale() < 0.999
				then colour(string.format("x%.2f", motor:GetHealthSpeedScale()), YELLOW)
				else "x1"
		),
		string.format("Last jump: %.2f / %.1f studs", lastJumpHeight, Config.JumpHeight),
		string.format("Air peak speed: %.1f", if mode == "Air" then airPeakSpeed else lastAirPeakSpeed),
		string.format("Fall speed: %s / %d max", fallText, Config.TerminalVelocity),
		dashText,
		hopText,
		rollText,
		parkourText,
		staminaText,
		combatText,
		lanternText,
		string.format("Rig: %s", rig),
		colour("Settings (gear, top right) > Debug to hide", GREY),
	}, "\n")
end

RunService.RenderStepped:Connect(function(dt: number)
	if Perf.enabled then
		local t0 = os.clock()
		onFrame(dt)
		Perf.add("Debug overlay", os.clock() - t0)
	else
		onFrame(dt)
	end
end)
