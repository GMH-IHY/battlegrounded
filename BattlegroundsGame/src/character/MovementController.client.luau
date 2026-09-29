--!strict
-- MovementController (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > MovementController
--
-- Reads player input and feeds it to this character's CharacterMotor and Dash.
-- Double-tap W: run. Space: jump; in the air press it again (or keep holding it) while moving
-- into and along a wall to wall hop; press it right before landing from a high fall to roll.
-- Sprinting into obstacles vaults / climbs / slides automatically (AutoParkour). Shift: dash. M1 during a front dash: dash punch.
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

local CharacterMotor = require(ReplicatedStorage.Movement.CharacterMotor)
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local Dash = require(ReplicatedStorage.Movement.Dash)
local WallHop = require(ReplicatedStorage.Movement.WallHop)
local LandingRoll = require(ReplicatedStorage.Movement.LandingRoll)
local AutoParkour = require(ReplicatedStorage.Movement.AutoParkour)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local Lantern = require(ReplicatedStorage.Movement.Lantern)
local Sfx = require(ReplicatedStorage.Movement.Sfx)

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

table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- selene: allow(if_same_then_else) -- order matters: each call only runs if the one before said no
			if moth:CancelCharge() then
				character:SetAttribute("M1RequestedAt", os.clock())
			elseif moth:OnM1() then
				-- M1 cancels a Moth flight and throws an M1 right away. The M1 system doesn't exist yet:
				-- it should listen for this attribute (or replace this call).
				character:SetAttribute("M1RequestedAt", os.clock())
			else
				dash:Punch()
			end
		elseif DASH_KEYS[input.KeyCode] then
			moth:CancelCharge()
			if not dash:Request() and dash:GetCooldownRemaining() > 0.15 then
				-- Pressed while it's still recharging: a short "no" (not spammable).
				local now = os.clock()
				if now - lastDeniedAt > 0.5 then
					lastDeniedAt = now
					Sfx.Play(character, "Denied", { volume = 0.7 })
				end
			end
		elseif input.KeyCode == RACE_SPECIAL_KEY then
			moth:Press()
		elseif input.KeyCode == Enum.KeyCode.W then
			forwardHeld = true
			local now = os.clock()
			if now - lastForwardTap <= Config.DoubleTapWindow then
				motor:SetSprinting(true)
			end
			lastForwardTap = now
		elseif input.KeyCode == Enum.KeyCode.Space then
			moth:CancelCharge()
			motor:SetJumpHeld(true)
			local madeJump = motor:RequestJump()
			wallHop:OnJumpPressed(madeJump)
			landingRoll:OnJumpPressed(madeJump)
			-- Pressed near the end of a dash or parkour move: jump right as it ends.
			dash:OnJumpPressed()
			autoParkour:OnJumpPressed()
		end
	end)
)

-- Releases are handled even when "gameProcessed" so a key can't get stuck (e.g. opening chat).
table.insert(
	connections,
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.W then
			forwardHeld = false
			motor:SetSprinting(false)
		elseif input.KeyCode == Enum.KeyCode.Space then
			motor:SetJumpHeld(false)
		elseif input.KeyCode == RACE_SPECIAL_KEY then
			moth:Release()
		end
	end)
)

table.insert(
	connections,
	UserInputService.WindowFocusReleased:Connect(function()
		forwardHeld = false
		motor:SetSprinting(false)
		motor:SetJumpHeld(false)
		moth:Release()
	end)
)

-- CLEANUP --------------------------------------------------------------------

local function cleanup()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
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
