--!strict
-- Lotus suite: the Lotus Fungus against the training dummies, checked against the server
-- (docs/MoveData.md, "Lotus Fungus"). The meter and its stages (damage feeds it, the growth shows the
-- stage), every 2 / 3 / 4 variant, stage 3 costs and the whiff penalty, spores blocked from any
-- side, Infested and the wrap, the beam, the grabs (blocked / unblockable / uninterruptible), the
-- heal channel and the rip-out, the impale, the form, taking more damage at stage 3, follow-ups.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Combat.CombatConfig)
local Moves = require(ReplicatedStorage.Combat.Moves)

type Context = Harness.Context

local function health(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.Health else 0
end

local function meter(t: Context): number
	local value = t:server().lotus
	return if typeof(value) == "number" then value else -1
end

local function setMeter(t: Context, value: number)
	t:debug("SetLotus", value)
	t:wait(0.05)
end

local function fresh(t: Context)
	t:debug("ClearCooldowns")
	t.combat:ResetForTest()
end

local function waitIdle(t: Context, timeout: number?)
	t:waitFor(function()
		return t.combat:GetPhase() == "Idle"
	end, timeout or 3)
end

local function waitState(model: Model, state: string, timeout: number, t: Context): boolean
	return t:waitAttribute(model, "CombatState", state, timeout)
end

local function damageOf(id: string): number
	local move = Moves.Get(id)
	return if move then move.Damage else 0
end

-- Presses `action`, returns the server's answer (or "").
local function press(t: Context, action: any, timeout: number?): string
	t.combat.lastResult = ""
	t:press(action)
	t:waitFor(function()
		return t.combat:GetLastResult() ~= ""
	end, timeout or 0.8)
	return t.combat:GetLastResult()
end

local tests: { Harness.Test } = {
	{
		name = "The meter: stages, the growth, and damage feeding it",
		run = function(t)
			setMeter(t, 0)
			t:check("stage 1 at 0", t.character:GetAttribute("LotusStage") == 1)
			local fungus = t.character:FindFirstChild("Fungus")
			local function shown(): number
				local count = 0
				if fungus then
					for _, p in fungus:GetChildren() do
						if p:IsA("BasePart") and p.Transparency < 1 then
							count += 1
						end
					end
				end
				return count
			end
			local s1 = shown()
			setMeter(t, Config.Stage2At + 5)
			t:check("stage 2 from Stage2At", t.character:GetAttribute("LotusStage") == 2)
			local s2 = shown()
			setMeter(t, Config.Stage3At + 5)
			t:check("stage 3 from Stage3At", t.character:GetAttribute("LotusStage") == 3)
			local s3 = shown()
			t:check("the growth spreads with the stage", s1 > 0 and s2 > s1 and s3 > s2, string.format("%d / %d / %d pieces", s1, s2, s3))

			setMeter(t, 0)
			local dummy = t:dummy("DummyAttack", "Stand")
			t:faceDummy(dummy, 3.2)
			local hp0 = t.humanoid.Health
			t:debug("DummyMove", "DummyAttack", "Sword.M1_1")
			t:waitFor(function()
				return t.humanoid.Health < hp0
			end, 1)
			t:wait(0.1)
			local lost = hp0 - t.humanoid.Health
			t:near("taking damage feeds the meter (LotusPerDamage per HP)", meter(t), lost * Config.LotusPerDamage, 0.3)
			t:wait(0.6)
		end,
	},
	{
		name = "At stage 3 you take more damage",
		run = function(t)
			setMeter(t, Config.Stage3At + 10)
			local dummy = t:dummy("DummyAttack", "Stand")
			t:faceDummy(dummy, 3.2)
			local hp0 = t.humanoid.Health
			t:debug("DummyMove", "DummyAttack", "Sword.M1_1")
			t:waitFor(function()
				return t.humanoid.Health < hp0
			end, 1)
			t:near("x Stage3DamageTaken", hp0 - t.humanoid.Health, damageOf("Sword.M1_1") * Config.Stage3DamageTaken, 0.05)
			t:wait(0.6)
		end,
	},
	{
		name = "2 at stage 1: the strand stab hits and feeds the meter",
		run = function(t)
			setMeter(t, 0)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 5)
			local before = health(dummy)
			local result = press(t, "Two")
			t:check("it hits from 5 studs", result == "Hit", result)
			t:wait(0.1)
			t:near("its damage", before - health(dummy), damageOf("Lotus.Stab1"), 0.01)
			t:near("+10 meter on hit", meter(t), 10, 0.5)
			waitIdle(t)
		end,
	},
	{
		name = "2 at stage 2: the ground strand launches, through a block",
		run = function(t)
			setMeter(t, Config.Stage2At + 5)
			local dummy = t:dummy("DummyBlock", "Block")
			t:faceDummy(dummy, 10)
			t:press("Two")
			t:check("the move is the ground strand", t.combat:GetMoveId() == "Lotus.Strand2", tostring(t.combat:GetMoveId()))
			t:check("it launches them even blocking (unblockable)", waitState(dummy, "Launched", 1.5, t),
				tostring(dummy:GetAttribute("CombatState")))
			waitIdle(t)
		end,
	},
	{
		name = "2 at stage 3: costs meter, and a miss consumes you",
		run = function(t)
			setMeter(t, Config.Stage3At + 10)
			t:teleport(Vector3.new(-40, 4, -150), Vector3.zAxis)
			local hp0 = t.humanoid.Health
			local record = t:recordAttribute("CombatState")
			t:press("Two")
			t:check("the heavy stab", t.combat:GetMoveId() == "Lotus.Stab3", tostring(t.combat:GetMoveId()))
			t:wait(0.1)
			local move = Moves.Get("Lotus.Stab3")
			t:near("it cost its meter", meter(t), Config.Stage3At + 10 - (if move then move.MeterCost else 0), 0.5)
			t:waitFor(function()
				return t.humanoid.Health < hp0
			end, 2)
			t:near("the miss costs WhiffHealth", hp0 - t.humanoid.Health, Config.WhiffHealth, 0.01)
			t:wait(0.2)
			local states = table.concat(record(), " > ")
			t:check("and staggers you", string.find(states, "Stunned") ~= nil, states)
			t:near("which doesn't feed the meter", meter(t), Config.Stage3At + 10 - (if move then move.MeterCost else 0), 0.5)
			t:wait(0.5)
		end,
	},
	{
		name = "3: spores are blocked from any side; the fan Infests; a Lotus hit on the block wraps",
		run = function(t)
			setMeter(t, 0)
			local blocker = t:dummy("DummyBlock", "Block")
			t:faceDummy(blocker, -14) -- behind it
			local result = press(t, "Three", 1.2)
			t:check("a spore from behind is still blocked", result == "Block", result)
			waitIdle(t)

			fresh(t)
			setMeter(t, Config.Stage2At + 5)
			local target = t:dummy("DummyStand")
			t:faceDummy(target, 12)
			t:press("Three")
			t:check("the fan", t.combat:GetMoveId() == "Lotus.Spore2", tostring(t.combat:GetMoveId()))
			t:check("it Infests", t:waitAttribute(target, "Infested", true, 1.5))
			waitIdle(t)

			fresh(t)
			setMeter(t, 0)
			t:debug("DummyMode", "DummyStand", "Block")
			t:faceDummy(target, 5)
			t:wait(0.2)
			t:press("Two")
			t:check("a Lotus stab on their block wraps them (down)", waitState(target, "Downed", 1.2, t),
				tostring(target:GetAttribute("CombatState")))
			t:check("and uses Infested up", target:GetAttribute("Infested") ~= true)
			waitIdle(t)
		end,
	},
	{
		name = "3 at stage 3: the beam, through a block, knocks down",
		run = function(t)
			setMeter(t, Config.Stage3At + 15)
			local dummy = t:dummy("DummyBlock", "Block")
			t:faceDummy(dummy, 25)
			t:press("Three")
			t:check("the beam", t.combat:GetMoveId() == "Lotus.Beam3", tostring(t.combat:GetMoveId()))
			t:check("it knocks them down even blocking", waitState(dummy, "Knockdown", 1.5, t) or waitState(dummy, "Downed", 0.5, t),
				tostring(dummy:GetAttribute("CombatState")))
			waitIdle(t)
		end,
	},
	{
		name = "4: grabs (blocked = nothing; stage 2 unblockable, meter to 80; stage 3 can't be interrupted)",
		run = function(t)
			setMeter(t, 0)
			local blocker = t:dummy("DummyBlock", "Block")
			t:faceDummy(blocker, 3)
			local result = press(t, "Four")
			t:check("a blocked stage 1 grab", result == "Block", result)
			t:check("does nothing to them", blocker:GetAttribute("CombatState") ~= "Held", tostring(blocker:GetAttribute("CombatState")))
			waitIdle(t)

			fresh(t)
			setMeter(t, Config.Stage2At + 5)
			t:faceDummy(blocker, 3)
			local caught = press(t, "Four")
			t:check("the stage 2 grab goes through the block", caught == "Hit", caught)
			t:check("they're held", waitState(blocker, "Held", 0.5, t), tostring(blocker:GetAttribute("CombatState")))
			local move = Moves.Get("Lotus.Grab2")
			t:near("the meter jumps to SetMeter", meter(t), if move and move.SetMeter then move.SetMeter else 80, 0.5)
			waitIdle(t)
			t:wait(1)

			fresh(t)
			setMeter(t, Config.Stage3At + 15)
			local attacker = t:dummy("DummyAttack", "Stand")
			t:faceDummy(attacker, 3)
			t:press("Four")
			t:debug("DummyMove", "DummyAttack", "Sword.M1_1")
			t:wait(0.15)
			t:check("hit during its startup, the stage 3 grab keeps going", t:server().state == "Attacking", tostring(t:server().state))
			t:check("and catches them", waitState(attacker, "Held", 0.6, t), tostring(attacker:GetAttribute("CombatState")))
			waitIdle(t)
			t:wait(1)
		end,
	},
	{
		name = "R: hold to heal (feeds the meter), tap to rip it out",
		run = function(t)
			setMeter(t, 30)
			t:debug("SetHealth", 50)
			t:wait(0.1)
			t:press("R")
			t:check("holding R is the heal", t.combat:GetMoveId() == "Lotus.Heal", tostring(t.combat:GetMoveId()))
			t:wait(1.2)
			t:release("R")
			t:wait(0.3)
			t:near("a full channel heals HealHealth", t.humanoid.Health, 50 + Config.HealHealth, 0.6)
			t:near("and feeds HealMeter", meter(t), 30 + Config.HealMeter, 1)
			waitIdle(t)

			fresh(t)
			setMeter(t, 60)
			local hp0 = t.humanoid.Health
			t:press("R")
			t:wait(0.05)
			t:release("R")
			t:check("a tap is the rip-out", t.combat:GetMoveId() == "Lotus.RipOut", tostring(t.combat:GetMoveId()))
			t:wait(0.5)
			t:near("it costs RipOutHealth", hp0 - t.humanoid.Health, Config.RipOutHealth, 0.1)
			t:near("and RipOutMeter", meter(t), 60 - Config.RipOutMeter, 0.5)
			waitIdle(t)
		end,
	},
	{
		name = "2 against an airborne opponent: the impale",
		run = function(t)
			setMeter(t, 0)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 8)
			t:debug("LaunchDummy", "DummyStand", 12)
			t:wait(0.2)
			t:press("Two")
			t:check("the stab becomes the impale", t.combat:GetMoveId() == "Lotus.Impale1", tostring(t.combat:GetMoveId()))
			t:check("growth from the ground catches them", waitState(dummy, "Held", 1, t), tostring(dummy:GetAttribute("CombatState")))
			t:check("then drops them", waitState(dummy, "Knockdown", 1, t) or waitState(dummy, "Downed", 0.5, t))
			waitIdle(t)
		end,
	},
	{
		name = "Follow-ups: a spore right after a stab hit gets its bonus",
		run = function(t)
			setMeter(t, 0)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 5)
			local stab = press(t, "Two")
			t:check("the stab hits", stab == "Hit", stab)
			waitIdle(t)
			t:press("Three")
			t:wait(0.03)
			t:check("the spore counts as a follow-up", t:server().followUp == true)
			waitIdle(t)
		end,
	},
	{
		name = "G: the form at a full meter (free stage 3), meter to 20 after",
		run = function(t)
			setMeter(t, 50)
			t:press("G")
			t:check("not below a full meter", t.combat:GetMoveId() == nil)
			setMeter(t, Config.LotusMax)
			t:press("G")
			t:check("at a full meter it starts", t.combat:GetMoveId() == "Lotus.Form")
			t:check("the form", t:waitAttribute(t.character, "LotusForm", true, 1.5))
			waitIdle(t)
			t:teleport(Vector3.new(-40, 4, -150), Vector3.zAxis)
			local before = meter(t)
			t:press("Two")
			t:wait(0.1)
			t:near("stage 3 moves cost nothing in the form", meter(t), before, 0.5)
			t:check("it ends", t:waitAttribute(t.character, "LotusForm", false, Config.FormTime + 1))
			t:near("with the meter at FormMeterAfter", meter(t), Config.FormMeterAfter, 0.5)
		end,
	},
}

return {
	name = "Lotus",
	description = "Meter and stages, 2 / 3 / 4 variants, R, G, Infested, costs and misses",
	tests = tests,
}
