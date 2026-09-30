--!strict
-- Stamina (ModuleScript)
-- Location: ReplicatedStorage > Movement > Stamina
--
-- Your side of the stamina meter (the Drive gauge). The SERVER owns the meter (CombatServer:
-- refill, blocking costs, parry gains, overdraw and burnout; numbers in CombatConfig) and
-- publishes it as the character attributes "Stamina", "StaminaMax" and "Burnout". This module lets
-- client-side moves (race specials, Left Ctrl) spend it without waiting: a spend is sent to the
-- server and counted locally until the server's value has caught up.
--
-- Overdraw: while you're not burnt out, a move still comes out with too little stamina, and the
-- meter drops to 0 = burnout. In burnout nothing that costs stamina works (CanSpend is false) until
-- the meter is full again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.MovementConfig)
local CharacterMotor = require(script.Parent.CharacterMotor)

local Stamina = {}
Stamina.__index = Stamina

-- A local spend is assumed to have reached the server's number after this long (seconds).
local PENDING_TIME = 0.35
-- Continuous drains (flight) are sent in batches at this rate (per second).
local FLUSH_RATE = 10

type Pending = { at: number, amount: number }

type StaminaData = {
	character: Model,
	motor: CharacterMotor.CharacterMotor,
	pending: { Pending },
	unsent: number,
	lastFlush: number,
	remote: RemoteEvent?,
	connection: RBXScriptConnection?,
}

export type Stamina = typeof(setmetatable({} :: StaminaData, Stamina))

local active: { [Model]: Stamina } = {}

local function findRemote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local combat = remotes and remotes:FindFirstChild("Combat")
	local remote = combat and combat:FindFirstChild("Stamina")
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

function Stamina.new(character: Model, motor: CharacterMotor.CharacterMotor): Stamina
	local self = setmetatable({
		character = character,
		motor = motor,
		pending = {},
		unsent = 0,
		lastFlush = 0,
		remote = findRemote(),
		connection = nil :: RBXScriptConnection?,
	}, Stamina)
	self.connection = RunService.Heartbeat:Connect(function()
		self:_flush(false)
	end)
	active[character] = self
	return self
end

function Stamina.Get(character: Model): Stamina?
	return active[character]
end

function Stamina._server(self: Stamina): number
	local value = self.character:GetAttribute("Stamina")
	return if typeof(value) == "number" then value else self:GetMax()
end

-- The meter as you should see it: the server's value minus your spends it hasn't counted yet.
function Stamina.GetValue(self: Stamina): number
	local now = os.clock()
	local owed = self.unsent
	for i = #self.pending, 1, -1 do
		local entry = self.pending[i]
		if now - entry.at > PENDING_TIME then
			table.remove(self.pending, i)
		else
			owed += entry.amount
		end
	end
	return math.max(self:_server() - owed, 0)
end

function Stamina.GetMax(self: Stamina): number
	local value = self.character:GetAttribute("StaminaMax")
	return if typeof(value) == "number" then value else Config.StaminaMax
end

function Stamina.IsBurnout(self: Stamina): boolean
	return self.character:GetAttribute("Burnout") == true
end

-- Could a stamina move come out now? (Overdraw: any stamina left, and not burnt out.)
function Stamina.CanSpend(self: Stamina, _amount: number?): boolean
	return not self:IsBurnout() and self:GetValue() > 0
end

function Stamina.Has(self: Stamina, amount: number): boolean
	return not self:IsBurnout() and self:GetValue() >= amount
end

function Stamina._send(self: Stamina, amount: number)
	if amount <= 0 then
		return
	end
	local remote = self.remote or findRemote()
	self.remote = remote
	if remote then
		remote:FireServer(amount)
	end
	table.insert(self.pending, { at = os.clock(), amount = amount })
end

function Stamina._flush(self: Stamina, force: boolean)
	if self.unsent <= 0 then
		return
	end
	local now = os.clock()
	if force or now - self.lastFlush >= 1 / FLUSH_RATE then
		self.lastFlush = now
		local amount = self.unsent
		self.unsent = 0
		self:_send(amount)
	end
end

-- Spends `amount` (overdraw allowed). Returns false only when burnt out.
function Stamina.TrySpend(self: Stamina, amount: number): boolean
	if not self:CanSpend(amount) then
		return false
	end
	self:_send(amount)
	return true
end

-- Continuous spending (held abilities): returns false once there's nothing left (or burnout).
function Stamina.Drain(self: Stamina, amount: number): boolean
	if self:IsBurnout() or self:GetValue() <= 0 then
		return false
	end
	self.unsent += amount
	self:_flush(false)
	return self:GetValue() > 0
end

-- Test / debug helper (Studio): asks the server to set the meter.
function Stamina.Set(self: Stamina, value: number)
	table.clear(self.pending)
	self.unsent = 0
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local combat = remotes and remotes:FindFirstChild("Combat")
	local debug = combat and combat:FindFirstChild("Debug")
	if debug and debug:IsA("RemoteFunction") then
		debug:InvokeServer("SetStamina", value)
	end
end

function Stamina.Destroy(self: Stamina)
	self:_flush(true)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	if rawequal(active[self.character], self) then
		active[self.character] = nil
	end
end

return Stamina
