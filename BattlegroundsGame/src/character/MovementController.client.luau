--!strict
-- MovementController (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > MovementController
--
-- Reads player input and feeds it to this character's CharacterMotor and Dash.
-- Double-tap W: run. Space: jump; in the air press it again (or keep holding it) while moving
-- into and along a wall to wall hop; press it right before landing from a high fall to roll.
-- Sprinting into obstacles vaults / climbs / slides automatically (AutoParkour). Shift: dash.
-- M1: during a front dash the dash punch; during a side / back dash, late in a landing roll or in a
-- Moth flight it cuts straight into a swing, keeping your momentum; otherwise a swing (M1Preview, the
-- placeholder sword M1 until the combat system exists).
-- Left Ctrl: race special (Moth: tap = wing flight, hold = charge + throw the lantern, press while it's in
-- the air = suspend it, hold with it away = fly to it / to a tagged opponent). Race specials spend Stamina.
-- Tab: shift lock (ShiftLock script).
-- A fresh copy runs every time the character spawns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("CharacterMotor")
movementFolder:WaitForChild("MovementConfig")
movementFolder:WaitForChild("Dash")
movementFolder:WaitForChild("WallHop")
movementFolder:WaitForChild("LandingRoll")
movementFolder:WaitForChild("AutoParkour")
movementFolder:WaitForChild("Stamina")
movementFolder:WaitForChild("Lantern")
movementFolder:WaitForChild("Sfx")
movementFolder:WaitForChild("Controls")
local combatFolder = ReplicatedStorage:WaitForChild("Combat")
combatFolder:WaitForChild("M1Preview")

local CharacterMotor = require(ReplicatedStorage.Movement.CharacterMotor)
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local Dash = require(ReplicatedStorage.Movement.Dash)
local WallHop = require(ReplicatedStorage.Movement.WallHop)
local LandingRoll = require(ReplicatedStorage.Movement.LandingRoll)
local AutoParkour = require(ReplicatedStorage.Movement.AutoParkour)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local Lantern = require(ReplicatedStorage.Movement.Lantern)
local Sfx = require(ReplicatedStorage.Movement.Sfx)
local Controls = require(ReplicatedStorage.Movement.Controls)
local M1Preview = require(ReplicatedStorage.Combat.M1Preview)

local DASH_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}
local RACE_SPECIAL_KEY = Enum.KeyCode.LeftControl

local character = script.Parent
assert(character and character:IsA("Model"), "MovementController must be in StarterCharacterScripts")

local motor = CharacterMotor.new(character)
local forwardHeld = false
local dash = Dash.new(character, motor, function()
	return forwardHeld
end)
-- Each movement is blocked while another one owns the body. Parkour is created last but looked
-- up lazily, so the earlier ones can check it too.
local parkour: AutoParkour.AutoParkour? = nil
local function parkourBusy(): boolean
	return parkour ~= nil and parkour:IsBusy()
end
-- Race specials (Moth lantern flight) own the body too; looked up lazily like parkour.
local raceSpecial: Lantern.Lantern? = nil
local function raceSpecialBusy(): boolean
	return raceSpecial ~= nil and raceSpecial:IsBusy()
end
local wallHop = WallHop.new(character, motor, function()
	return dash:IsBusy() or parkourBusy() or raceSpecialBusy()
end)
local landingRoll = LandingRoll.new(character, motor, function()
	return dash:IsBusy() or wallHop:IsRunning() or parkourBusy() or raceSpecialBusy()
end)
local autoParkour = AutoParkour.new(character, motor, function()
	-- A front dash doesn't block parkour: parkour takes it over (see the dash hook below). Nor
	-- does a wall run: a ledge in reach during it gets grabbed (wall run hook).
	return (dash:IsBusy() and not dash:IsFrontDashing()) or landingRoll:IsRolling() or raceSpecialBusy()
end)
local stamina = Stamina.new(character, motor)
local moth = Lantern.new(character, motor, stamina, function()
	return dash:IsBusy() or wallHop:IsRunning() or parkourBusy() or landingRoll:IsRolling()
end)
raceSpecial = moth
local m1 = M1Preview.new(character, motor)
autoParkour:SetWallRunHook({
	isRunning = function()
		return wallHop:IsRunning()
	end,
	handOff = function()
		wallHop:Cancel()
	end,
})
autoParkour:SetDashHook({
	isDashing = function()
		return dash:IsFrontDashing()
	end,
	velocity = function()
		return dash:GetCurrentVelocity()
	end,
	handOff = function()
		dash:HandOff()
	end,
})
parkour = autoParkour
local connections: { RBXScriptConnection } = {}
local lastForwardTap = -math.huge
local lastDeniedAt = -math.huge

-- INPUT ----------------------------------------------------------------------
-- Every key is a named action (Controls), so the in-Studio tests press the same code the keyboard does.

-- M1: what a click does depends on what the body is doing (see the header).
local function pressM1()
	if moth:CancelCharge() or moth:OnM1() then
		m1:Request()
		return
	end
	if dash:IsFrontDashing() then
		dash:Punch()
		return
	end
	if dash:CancelIntoAttack() or landingRoll:CancelIntoAttack() then
		m1:Request()
		return
	end
	if dash:IsBusy() or landingRoll:IsRolling() or wallHop:IsRunning() or parkourBusy() then
		return
	end
	m1:Request()
end

local function pressDash()
	moth:CancelCharge()
	if not dash:Request() and dash:GetCooldownRemaining() > 0.15 then
		-- Pressed while it's still recharging: a short "no" (not spammable).
		local now = os.clock()
		if now - lastDeniedAt > 0.5 then
			lastDeniedAt = now
			Sfx.Play(character, "Denied", { volume = 0.7 })
		end
	end
end

local function pressForward()
	forwardHeld = true
	local now = os.clock()
	if now - lastForwardTap <= Config.DoubleTapWindow then
		motor:SetSprinting(true)
	end
	lastForwardTap = now
end

local function releaseForward()
	forwardHeld = false
	motor:SetSprinting(false)
end

local function pressJump()
	moth:CancelCharge()
	motor:SetJumpHeld(true)
	local madeJump = motor:RequestJump()
	wallHop:OnJumpPressed(madeJump)
	landingRoll:OnJumpPressed(madeJump)
	-- Pressed near the end of a dash or parkour move: jump right as it ends.
	dash:OnJumpPressed()
	autoParkour:OnJumpPressed()
end

local function releaseJump()
	motor:SetJumpHeld(false)
end

local function nothing() end

Controls.Register(character, {
	press = {
		Jump = pressJump,
		Dash = pressDash,
		Race = function()
			moth:Press()
		end,
		Forward = pressForward,
		M1 = pressM1,
	},
	release = {
		Jump = releaseJump,
		Dash = nothing,
		Race = function()
			moth:Release()
		end,
		Forward = releaseForward,
		M1 = nothing,
	},
})

table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressM1()
		elseif DASH_KEYS[input.KeyCode] then
			pressDash()
		elseif input.KeyCode == RACE_SPECIAL_KEY then
			moth:Press()
		elseif input.KeyCode == Enum.KeyCode.W then
			pressForward()
		elseif input.KeyCode == Enum.KeyCode.Space then
			pressJump()
		end
	end)
)

-- Releases are handled even when "gameProcessed" so a key can't get stuck (e.g. opening chat).
table.insert(
	connections,
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.W then
			releaseForward()
		elseif input.KeyCode == Enum.KeyCode.Space then
			releaseJump()
		elseif input.KeyCode == RACE_SPECIAL_KEY then
			moth:Release()
		end
	end)
)

table.insert(
	connections,
	UserInputService.WindowFocusReleased:Connect(function()
		releaseForward()
		releaseJump()
		moth:Release()
	end)
)

-- CLEANUP --------------------------------------------------------------------

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	Controls.Unregister(character)
	m1:Destroy()
	moth:Destroy()
	stamina:Destroy()
	autoParkour:Destroy()
	landingRoll:Destroy()
	wallHop:Destroy()
	dash:Destroy()
	motor:Destroy()
end

script.Destroying:Connect(cleanup)
local humanoid = character:FindFirstChildOfClass("Humanoid")
if humanoid then
	humanoid.Died:Connect(cleanup)
end
