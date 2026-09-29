--!strict
-- CombatServer (Script)
-- Location: ServerScriptService > CombatServer
--
-- Runs combat. The server owns every hit, resource and cooldown (docs/DesignPlan.md):
--   * a Fighter (Combat > Fighter) for every player character and every training dummy
--   * the combat remotes (ReplicatedStorage > Remotes > Combat, see CombatRemotes)
--   * every frame: each fighter's timers, moves, hitboxes (HitResolver), stamina, build-up
--   * gives every character the sword and dagger (WeaponModels) until the loadout menu exists
-- Clients only ask: "start this move", "F is down", "tech roll", "I spent stamina".
--
-- Studio only: the Debug remote (test panel helpers) and hitbox broadcasting
-- (ReplicatedStorage attribute "CombatShowHitboxes", toggled by the hitbox viewer, F5).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatRemotes = require(Combat:WaitForChild("CombatRemotes"))
local WeaponModels = require(Combat:WaitForChild("WeaponModels"))
local FighterCollision = require(Combat:WaitForChild("FighterCollision"))
local Config = require(Combat:WaitForChild("CombatConfig"))

local ServerCombat = script.Parent:WaitForChild("Combat")
local Fighter = require(ServerCombat:WaitForChild("Fighter"))
local HitResolver = require(ServerCombat:WaitForChild("HitResolver"))
local Dummies = require(ServerCombat:WaitForChild("Dummies"))

type Fighter = Fighter.Fighter

local remotes = CombatRemotes.Create()
local fighters: { [Model]: Fighter } = {}
local dummyByModel: { [Model]: Dummies.Dummy } = {}

local function reject(player: Player, why: string)
	if IS_STUDIO then
		warn(string.format("[Combat] %s: %s", player.Name, why))
	end
end

local hooks: Fighter.Hooks = {
	react = function(fighter: Fighter, info: { [string]: any })
		local player = fighter.player
		if player then
			remotes.Hit:FireClient(player, info)
		else
			local dummy = dummyByModel[fighter.character]
			if dummy then
				dummy.reactions:React(info)
			end
		end
	end,
	result = function(fighter: Fighter, seq: number, result: string, hitstop: number, advantage: number?)
		local player = fighter.player
		if player then
			remotes.Result:FireClient(player, seq, result, hitstop, advantage)
		end
	end,
	fx = function(info: { [string]: any })
		if info.type == "Hitbox" then
			if IS_STUDIO and ReplicatedStorage:GetAttribute("CombatShowHitboxes") == true then
				remotes.Fx:FireAllClients(info)
			end
			return
		end
		remotes.Fx:FireAllClients(info)
	end,
	all = function(): { Fighter }
		local out = {}
		for _, fighter in fighters do
			table.insert(out, fighter)
		end
		return out
	end,
	fighterOf = function(model: Model): Fighter?
		return fighters[model]
	end,
	resolve = HitResolver.Resolve,
}

local function register(model: Model, fighter: Fighter)
	fighters[model] = fighter
end

-- PLAYERS -------------------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Right Arm", 10)
	character:WaitForChild("Left Arm", 10)
	character:WaitForChild("Torso", 10)
	if not character.Parent then
		return
	end
	if character:GetAttribute("Element") == nil then
		character:SetAttribute("Element", "Wind")
	end
	local ok, err = pcall(WeaponModels.Attach, character)
	if not ok then
		warn("[Combat] couldn't attach the weapons: " .. tostring(err))
	end
	FighterCollision.Apply(character)
	fighters[character] = Fighter.new(character, player, hooks)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			fighters[character] = nil
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end

local function fighterOfPlayer(player: Player): Fighter?
	local character = player.Character
	return if character then fighters[character] else nil
end

-- REMOTES -------------------------------------------------------------------------------------

remotes.Move.OnServerEvent:Connect(function(player: Player, moveId: unknown, seq: unknown)
	if typeof(moveId) ~= "string" or typeof(seq) ~= "number" or #moveId > 40 then
		return
	end
	local fighter = fighterOfPlayer(player)
	if not fighter then
		return
	end
	local why = fighter:RequestMove(moveId, seq)
	if why ~= "" and why ~= "queue" then
		reject(player, string.format("%s refused: %s", moveId, why))
		remotes.Result:FireClient(player, seq, "Reject", 0)
	end
end)

remotes.Block.OnServerEvent:Connect(function(player: Player, held: unknown)
	local fighter = fighterOfPlayer(player)
	if fighter and typeof(held) == "boolean" then
		fighter:SetBlock(held)
	end
end)

remotes.Tech.OnServerEvent:Connect(function(player: Player)
	local fighter = fighterOfPlayer(player)
	if fighter then
		fighter:TechRoll()
	end
end)

remotes.Stamina.OnServerEvent:Connect(function(player: Player, amount: unknown)
	local fighter = fighterOfPlayer(player)
	if fighter and typeof(amount) == "number" and amount > 0 and amount <= Config.StaminaMax then
		fighter:SpendStamina(amount)
	end
end)

-- Studio test helpers (the in-Studio test panel). Does nothing on a live server.
remotes.Debug.OnServerInvoke = function(player: Player, op: unknown, a: unknown, b: unknown): any
	if not IS_STUDIO or typeof(op) ~= "string" then
		return nil
	end
	local own = fighterOfPlayer(player)
	local function dummyNamed(name: unknown): Dummies.Dummy?
		return if typeof(name) == "string" then Dummies.Get(name) else nil
	end
	if op == "State" then
		local model = if typeof(a) == "Instance" and a:IsA("Model") then a else player.Character
		local fighter = if model then fighters[model] else nil
		return if fighter then fighter:Snapshot() else nil
	elseif op == "SetStamina" and own and typeof(a) == "number" then
		own:SetStamina(a)
	elseif op == "SetHealth" and own and typeof(a) == "number" then
		own.humanoid.Health = math.clamp(a, 1, own.humanoid.MaxHealth)
	elseif op == "ClearCooldowns" and own then
		table.clear(own.cooldowns)
		own.chain = 0
	elseif op == "Reset" and own then
		own:Interrupt()
		own:SetState("Idle")
		own:SetStamina(Config.StaminaMax)
		table.clear(own.cooldowns)
		own.chain = 0
		own.buildup = 0
		own.draftedUntil = 0
		own.parryLockUntil = 0
		own.humanoid.Health = own.humanoid.MaxHealth
	elseif op == "DummyMode" then
		local dummy = dummyNamed(a)
		if dummy and typeof(b) == "string" and table.find(Dummies.Modes, b) then
			dummy.model:SetAttribute("DummyMode", b)
			dummy.fighter:SetBlock(false)
			return true
		end
	elseif op == "ResetDummy" then
		local dummy = dummyNamed(a)
		if dummy then
			Dummies.Reset(dummy)
			if typeof(b) == "CFrame" then
				dummy.model:PivotTo(b)
			end
			return true
		end
	elseif op == "DummyMove" then
		local dummy = dummyNamed(a)
		if dummy and typeof(b) == "string" then
			return dummy.fighter:RequestMove(b, 0)
		end
	elseif op == "DummyBlock" then
		local dummy = dummyNamed(a)
		if dummy and typeof(b) == "boolean" then
			dummy.fighter:SetBlock(b)
			return true
		end
	elseif op == "DummyStamina" then
		local dummy = dummyNamed(a)
		if dummy and typeof(b) == "number" then
			dummy.fighter:SetStamina(b)
			return true
		end
	elseif op == "Scaling" then
		-- Damage scale by combo hit number (1-10), without and with a linker earlier in the combo.
		local plain, linked = {}, {}
		for hits = 1, 10 do
			plain[hits] = HitResolver.Scale({ hits = hits, launches = 0, afterLinker = false, damage = 0 })
			linked[hits] = HitResolver.Scale({ hits = hits, launches = 0, afterLinker = true, damage = 0 })
		end
		return { plain = plain, linked = linked }
	elseif op == "ShowHitboxes" then
		ReplicatedStorage:SetAttribute("CombatShowHitboxes", a == true)
		return true
	end
	return nil
end

-- DUMMIES -------------------------------------------------------------------------------------

for _, dummy in Dummies.Spawn(hooks, register) do
	dummyByModel[dummy.model] = dummy
end

-- EVERY FRAME ---------------------------------------------------------------------------------

local function fighterOf(model: Model): Fighter?
	return fighters[model]
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, fighter in fighters do
		if model.Parent then
			fighter:Step(now)
		end
	end
	Dummies.Step(now, fighterOf)
end)
