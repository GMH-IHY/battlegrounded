--!strict
-- MovementController (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > MovementController
--
-- Reads player input and feeds it to this character's CharacterMotor and Dash.
-- Double-tap W: run. Space: jump; in the air press it again (or keep holding it) while moving
-- into and along a wall to wall hop; press it right before landing from a high fall to roll.
-- Sprinting into obstacles vaults / climbs / slides automatically (AutoParkour). Shift: dash.
-- Combat keys go to CombatClient (the server decides the hits): M1 (left click), M2 (right click,
-- the dagger), 1 (the sword's 1), F (hold = block, press = parry try), and the Lotus Fungus: 2 / 3 / 4
-- (stab / spore / grab of your meter stage), R (hold = heal, tap = rip out), G (the stage 3 form).
-- An attack during a side / back
-- dash, late in a landing roll or in a Moth flight cuts straight into it, keeping your momentum; a
-- front dash's (or a run's) M1 is the lunge. While the server has you stunned nothing moves you;
-- Shift while knocked down is a tech roll.
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
combatFolder:WaitForChild("CombatClient")

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
local CombatClient = require(ReplicatedStorage.Combat.CombatClient)

local DASH_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
}
local RACE_SPECIAL_KEY = Enum.KeyCode.LeftControl
local BLOCK_KEY = Enum.KeyCode.F
local ONE_KEY = Enum.KeyCode.One
-- The magic system's keys (the Lotus Fungus): 2 / 3 / 4, R, G.
local MAGIC_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Two] = "Two",
	[Enum.KeyCode.Three] = "Three",
	[Enum.KeyCode.Four] = "Four",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.G] = "G",
}

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
-- Getting hit (or starting an attack) stops whatever movement move is running.
local combat = CombatClient.new(character, motor, {
	interruptMovement = function()
		if dash:IsBusy() then
			dash:Cancel()
		end
		landingRoll:Cancel()
		wallHop:Cancel()
		if autoParkour:IsBusy() then
			autoParkour:Cancel()
		end
		moth:CancelCharge()
		moth:Cancel()
	end,
})
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

-- An attack key: what it does depends on what the body is doing (see the header).
local function pressAttack(slot: string)
	if combat:IsLocked() then
		return
	end
	if moth:CancelCharge() or moth:OnM1() then
		combat:Press(slot)
		return
	end
	if dash:IsFrontDashing() then
		-- A front dash's M1 is the running lunge (other attacks just cut the dash).
		dash:CancelIntoAttack(true)
		combat:Press(slot, slot == "M1")
		return
	end
	if dash:CancelIntoAttack() or landingRoll:CancelIntoAttack() then
		combat:Press(slot)
		return
	end
	if dash:IsBusy() or landingRoll:IsRolling() or wallHop:IsRunning() or parkourBusy() then
		return
	end
	combat:Press(slot)
end

local function pressM1()
	pressAttack("M1")
end

local function pressM2()
	pressAttack("M2")
end

local function pressOne()
	pressAttack("One")
end

-- The Lotus keys (2 / 3 / 4 / G). R also needs its release (heal channel / rip-out tap).
local function magicPress(slot: string): () -> ()
	return function()
		pressAttack(slot)
	end
end

local function releaseR()
	combat:Release("R")
end

local function pressBlock()
	combat:SetBlock(true)
end

local function releaseBlock()
	combat:SetBlock(false)
end

local function pressDash()
	if combat:PressDash() then
		return -- a tech roll, or stunned
	end
	moth:CancelCharge()
	local started = dash:Request()
	if started and combat:IsAttacking() then
		combat:Cancel() -- dashing out of an attack's recovery
	end
	if not started and dash:GetCooldownRemaining() > 0.15 then
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
	motor:SetJumpHeld(true) -- kept even while stunned: Space held picks the launcher
	if combat:IsLocked() then
		return
	end
	if combat:TryJumpCancel() then
		return -- the launcher's follow-up jump
	end
	moth:CancelCharge()
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
			if not combat:IsLocked() then
				moth:Press()
			end
		end,
		Forward = pressForward,
		M1 = pressM1,
		M2 = pressM2,
		One = pressOne,
		Block = pressBlock,
		Two = magicPress("Two"),
		Three = magicPress("Three"),
		Four = magicPress("Four"),
		R = magicPress("R"),
		G = magicPress("G"),
	},
	release = {
		Jump = releaseJump,
		Dash = nothing,
		Race = function()
			moth:Release()
		end,
		Forward = releaseForward,
		M1 = nothing,
		M2 = nothing,
		One = nothing,
		Block = releaseBlock,
		Two = nothing,
		Three = nothing,
		Four = nothing,
		R = releaseR,
		G = nothing,
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
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			pressM2()
		elseif input.KeyCode == ONE_KEY then
			pressOne()
		elseif MAGIC_KEYS[input.KeyCode] then
			pressAttack(MAGIC_KEYS[input.KeyCode])
		elseif input.KeyCode == BLOCK_KEY then
			pressBlock()
		elseif DASH_KEYS[input.KeyCode] then
			pressDash()
		elseif input.KeyCode == RACE_SPECIAL_KEY then
			if not combat:IsLocked() then
				moth:Press()
			end
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
		elseif input.KeyCode == BLOCK_KEY then
			releaseBlock()
		elseif input.KeyCode == Enum.KeyCode.R then
			releaseR()
		end
	end)
)

table.insert(
	connections,
	UserInputService.WindowFocusReleased:Connect(function()
		releaseForward()
		releaseJump()
		releaseBlock()
		releaseR()
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
	combat:Destroy()
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
