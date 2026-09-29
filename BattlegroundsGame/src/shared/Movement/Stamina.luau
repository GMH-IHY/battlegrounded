--!strict
-- Stamina (ModuleScript)
-- Location: ReplicatedStorage > Movement > Stamina
--
-- One stamina meter per character, shared by every race: each race's special (Left Ctrl) spends it
-- its own way (the Moth's flutter first). Runs on the client next to CharacterMotor, like the rest
-- of movement. It regenerates after StaminaRegenDelay seconds without spending, faster on the
-- ground than in the air. The current value is mirrored to the character attribute "Stamina"
-- (and "StaminaMax") for the HUD.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.MovementConfig)
local CharacterMotor = require(script.Parent.CharacterMotor)

local Stamina = {}
Stamina.__index = Stamina

type StaminaData = {
	character: Model,
	motor: CharacterMotor.CharacterMotor,
	value: number,
	lastSpend: number,
	shown: number,
	connection: RBXScriptConnection?,
}

export type Stamina = typeof(setmetatable({} :: StaminaData, Stamina))

local active: { [Model]: Stamina } = {}

function Stamina.new(character: Model, motor: CharacterMotor.CharacterMotor): Stamina
	local self = setmetatable({
		character = character,
		motor = motor,
		value = Config.StaminaMax,
		lastSpend = -math.huge,
		shown = -1,
		connection = nil,
	}, Stamina)
	self.connection = RunService.PreSimulation:Connect(function(dt: number)
		self:_step(dt)
	end)
	character:SetAttribute("StaminaMax", Config.StaminaMax)
	self:_publish()
	active[character] = self
	return self
end

function Stamina.Get(character: Model): Stamina?
	return active[character]
end

function Stamina.GetValue(self: Stamina): number
	return self.value
end

function Stamina.GetMax(self: Stamina): number
	return Config.StaminaMax
end

function Stamina.Has(self: Stamina, amount: number): boolean
	return self.value >= amount
end

-- Spends `amount` if there's enough; returns whether it was spent.
function Stamina.TrySpend(self: Stamina, amount: number): boolean
	if self.value < amount then
		return false
	end
	self.value -= amount
	self.lastSpend = os.clock()
	self:_publish()
	return true
end

-- Continuous spending (held abilities): takes up to `amount`, returns false once it's empty.
function Stamina.Drain(self: Stamina, amount: number): boolean
	if self.value <= 0 then
		return false
	end
	self.value = math.max(self.value - amount, 0)
	self.lastSpend = os.clock()
	self:_publish()
	return self.value > 0
end

-- Test / debug helper.
function Stamina.Set(self: Stamina, value: number)
	self.value = math.clamp(value, 0, Config.StaminaMax)
	self:_publish()
end

function Stamina._step(self: Stamina, dt: number)
	if self.value >= Config.StaminaMax then
		return
	end
	if os.clock() - self.lastSpend < Config.StaminaRegenDelay then
		return
	end
	local rate = if self.motor:GetMode() == "Air" then Config.StaminaRegenAir else Config.StaminaRegenGround
	self.value = math.min(self.value + rate * dt, Config.StaminaMax)
	self:_publish()
end

function Stamina._publish(self: Stamina)
	-- Only whole-number changes touch the attribute (the HUD doesn't need more).
	local rounded = math.floor(self.value + 0.5)
	if rounded ~= self.shown then
		self.shown = rounded
		self.character:SetAttribute("Stamina", rounded)
	end
end

function Stamina.Destroy(self: Stamina)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	if active[self.character] == self then
		active[self.character] = nil
	end
end

return Stamina
