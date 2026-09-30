--!strict
-- Combat suite: real fights against the training dummies, checked against the server's own state
-- (docs/DesignPlan.md "Combat core", docs/MoveData.md). Hits and damage, the 3-hit chain knocking
-- down and the get-up, the M1 gap (a buffered block stops M1 2), parries, blocking from behind,
-- counter-hits, burnout chip damage, the dagger -> 1 link and 1's cooldown, damage scaling,
-- server-owned stamina (overdraw, burnout, refill), and getting hit yourself: locked controls,
-- knockdown, tech roll.
--
-- The dummies stand at x = 80 facing -X (CombatServer / Dummies); t:dummy() resets one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Combat.CombatConfig)
local Moves = require(ReplicatedStorage.Combat.Moves)
local MovementConfig = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local RANGE = 3.2 -- studs in front of a dummy to stand for M1s

local function health(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.Health else 0
end

local function waitIdle(t: Context)
	t:waitFor(function()
		return t.combat:GetPhase() == "Idle"
	end, 2)
end

-- Presses `action` and waits until the server has answered the move (or `timeout`).
local function swing(t: Context, action: any, timeout: number?): string
	t.combat.lastResult = ""
	t:press(action)
	t:waitFor(function()
		return t.combat:GetLastResult() ~= ""
	end, timeout or 0.5)
	return t.combat:GetLastResult()
end

local function moveDamage(id: string): number
	local move = Moves.Get(id)
	return if move then move.Damage else 0
end

local tests: { Harness.Test } = {
	{
		name = "An M1 hits a standing dummy",
		run = function(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, RANGE)
			local before = health(dummy)
			local result = swing(t, "M1")
			t:check("the server says it hit", result == "Hit", result)
			t:wait(0.1)
			t:near("M1 1 damage", before - health(dummy), moveDamage("Sword.M1_1"), 0.01)
			local state = t:server(dummy).state
			t:check("the dummy is in hit stun", state == "Stunned", tostring(state))
			waitIdle(t)
			t:wait(0.5)
			t:check("the stun ends", t:server(dummy).state == "Idle", tostring(t:server(dummy).state))
		end,
	},
	{
		name = "The 3-hit chain knocks down, then the dummy gets up",
		run = function(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, RANGE)
			local record = t:recordAttributeOn(dummy, "CombatState")
			local before = health(dummy)
			t:press("M1")
			t:wait(0.1)
			t:press("M1")
			t:wait(0.25)
			t:press("M1")
			t:waitFor(function()
				return dummy:GetAttribute("CombatState") == "Downed"
			end, 2)
			local total = moveDamage("Sword.M1_1") + moveDamage("Sword.M1_2") + moveDamage("Sword.M1_3")
			t:near("three hits of damage", before - health(dummy), total, 0.01)
			t:waitFor(function()
				return dummy:GetAttribute("CombatState") == "Idle"
			end, 2)
			local states = table.concat(record(), " > ")
			t:check("stun, stun, knocked down, on the floor, up", string.find(states, "Knockdown > Downed > Idle") ~= nil, states)
		end,
	},
	{
		name = "The M1 gap: a block held through the stun stops M1 2",
		run = function(t)
			local dummy = t:dummy("DummyBlockAfterHit", "BlockAfterHit")
			t:faceDummy(dummy, RANGE)
			local first = swing(t, "M1")
			t:check("M1 1 hits", first == "Hit", first)
			waitIdle(t)
			local staminaBefore = t:server(dummy).stamina
			local second = swing(t, "M1")
			t:check("M1 2 is blocked (the block started in the gap)", second == "Block", second)
			t:wait(0.1)
			local drained = staminaBefore - t:server(dummy).stamina
			t:near("blocking cost damage x BlockStaminaPerDamage", drained,
				moveDamage("Sword.M1_2") * Config.BlockStaminaPerDamage, 1)
			waitIdle(t)
		end,
	},
	{
		name = "Blocking only covers the front",
		run = function(t)
			local dummy = t:dummy("DummyBlock", "Block")
			t:faceDummy(dummy, RANGE)
			t:wait(0.1)
			t:check("from the front: blocked", swing(t, "M1") == "Block", t.combat:GetLastResult())
			waitIdle(t)
			t:wait(0.7)
			t.combat:ResetForTest()
			t:faceDummy(dummy, -RANGE) -- behind it
			t:check("from behind: it hits", swing(t, "M1") == "Hit", t.combat:GetLastResult())
			waitIdle(t)
		end,
	},
	{
		name = "Parry: the attacker is stuck, the defender gains stamina",
		run = function(t)
			local dummy = t:dummy("DummyParry", "Parry")
			t:faceDummy(dummy, RANGE)
			t:debug("DummyStamina", "DummyParry", 50)
			local result = swing(t, "M1")
			t:check("the swing is parried", result == "Parried", result)
			t:wait(0.05)
			local mine = t:server()
			t:check("you're stuck in the parried state", mine.state == "Parried" and t.combat:IsLocked(),
				string.format("server %s, locked %s", tostring(mine.state), tostring(t.combat:IsLocked())))
			t:near("the dummy gained ParryStaminaGain", t:server(dummy).stamina, 50 + Config.ParryStaminaGain, 1.5)
			t:wait(Config.ParryStun / 60 + 0.2)
			t:check("then you're free again", not t.combat:IsLocked())
		end,
	},
	{
		name = "Counter-hit: hitting a move's startup stuns longer and hurts more",
		run = function(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, RANGE)
			local before = health(dummy)
			t:debug("DummyMove", "DummyStand", "Sword.One") -- 12 frames of startup
			local result = swing(t, "M1")
			t:check("the server calls it a counter-hit", result == "Counter", result)
			t:wait(0.1)
			t:near("counter-hit damage", before - health(dummy), moveDamage("Sword.M1_1") * Config.CounterHitDamage, 0.11)
			waitIdle(t)
		end,
	},
	{
		name = "Burnout: blocking overdraws, then blocked hits chip",
		run = function(t)
			local dummy = t:dummy("DummyBlock", "Block")
			t:faceDummy(dummy, RANGE)
			t:debug("DummyStamina", "DummyBlock", 3)
			swing(t, "M1")
			t:wait(0.1)
			t:check("the block overdrew: burnout", dummy:GetAttribute("Burnout") == true, tostring(dummy:GetAttribute("Burnout")))
			waitIdle(t)
			local before = health(dummy)
			local result = swing(t, "M1")
			t:wait(0.1)
			t:check("still blocked", result == "Block", result)
			t:near("chip damage in burnout", before - health(dummy), moveDamage("Sword.M1_2") * Config.BurnoutChip, 0.06)
			waitIdle(t)
		end,
	},
	{
		name = "Dagger -> 1 links, and 1 has a cooldown",
		run = function(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 2.6)
			local stab = swing(t, "M2")
			t:check("the stab hits", stab == "Hit", stab)
			local one = swing(t, "One", 0.8)
			t:check("1 cancels out of it and hits", one == "Hit", one)
			t:wait(0.1)
			local combo = t:server(dummy).comboHits
			t:check("both hits are one combo", combo == 2, tostring(combo))
			waitIdle(t)
			t:wait(0.6)
			t:press("One")
			t:check("1 again at once: on cooldown", t.combat:GetMoveId() == nil, tostring(t.combat:GetMoveId()))
		end,
	},
	{
		name = "Input buffer: an early 1 still cancels; a key late in a move comes out after it",
		run = function(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 2.6)
			t:debug("ClearCooldowns")
			t.combat:ResetForTest()
			-- 1 pressed during the stab's startup, long before the server confirms the hit.
			t.combat.lastResult = ""
			t:press("M2")
			t:press("One")
			t:waitFor(function()
				return t.combat:GetMoveId() == "Sword.One"
			end, 1)
			t:check("the early 1 comes out as the cancel", t.combat:GetMoveId() == "Sword.One", tostring(t.combat:GetMoveId()))
			waitIdle(t)
			t:wait(0.4)
			-- A dagger press in an M1's recovery (a whiff, so no cancel): it comes out right after.
			t:teleport(dummy:GetPivot().Position + Vector3.new(-30, 1, 0), Vector3.new(-1, 0, 0))
			t:debug("ClearCooldowns")
			t.combat:ResetForTest()
			t:press("M1")
			t:waitFor(function()
				return t.combat:GetPhase() == "Recovery"
			end, 1)
			t:wait(4 / 60) -- well inside the buffer window before the M1 ends
			t:press("M2")
			local dagger = t:waitFor(function()
				return t.combat:GetMoveId() == "Dagger.Stab"
			end, 0.6)
			t:check("pressed during recovery, starts when the M1 ends", dagger, tostring(t.combat:GetMoveId()))
			waitIdle(t)
		end,
	},
	{
		name = "Damage scaling",
		run = function(t)
			local scaling = t:debug("Scaling")
			t:check("the server answered", typeof(scaling) == "table")
			if typeof(scaling) ~= "table" then
				return
			end
			local plain, linked = scaling.plain, scaling.linked
			t:near("hits 1-3 are full damage", plain[3], 1, 1e-6)
			t:near("hit 4 is x ScalingPerHit", plain[4], Config.ScalingPerHit, 1e-6)
			t:near("hit 5 is x ScalingPerHit^2", plain[5], Config.ScalingPerHit ^ 2, 1e-6)
			t:near("never below ScalingMin", plain[10], math.max(Config.ScalingPerHit ^ 7, Config.ScalingMin), 1e-6)
			t:near("after a linker x AfterLinker", linked[2], Config.AfterLinker, 1e-6)
		end,
	},
	{
		name = "Stamina is the server's: overdraw, burnout, refill",
		run = function(t)
			if not t.lantern:IsMoth() then
				t:log("not a Moth: skipped")
				t:check("skipped", true)
				return
			end
			t:teleport(Vector3.new(-40, 4, -150), Vector3.zAxis)
			t.stamina:Set(10)
			t:wait(0.3)
			t:tap("Race") -- a wing burst costs more than 10: it still comes out (overdraw)
			t:wait(0.3)
			t:waitFor(function()
				return t.character:GetAttribute("Burnout") == true
			end, 1)
			t:check("and burns you out", t.character:GetAttribute("Burnout") == true)
			t:check("no stamina moves in burnout", not t.stamina:CanSpend())
			local refill = MovementConfig.StaminaMax / (Config.StaminaRegenGround * Config.BurnoutRegenScale)
			local started = os.clock()
			t:waitFor(function()
				return t.character:GetAttribute("Burnout") ~= true
			end, Config.StaminaRegenDelay + refill + 3)
			local took = os.clock() - started
			t:check("burnout ends only at a full meter", t.character:GetAttribute("Burnout") ~= true and t.stamina:GetValue() >= MovementConfig.StaminaMax - 1,
				string.format("%.1f s, stamina %d", took, t.stamina:GetValue()))
			t:near("refill time (burnout rate)", took, Config.StaminaRegenDelay + refill, 1.5)
		end,
	},
	{
		name = "Getting hit: locked controls, knockdown, tech roll",
		run = function(t)
			local dummy = t:dummy("DummyAttack", "Stand")
			t:faceDummy(dummy, RANGE)
			local record = t:recordAttribute("CombatState")
			t:debug("DummyMove", "DummyAttack", "Sword.M1_1")
			t:waitFor(function()
				return t.character:GetAttribute("Stunned") == true
			end, 1)
			t:check("you're stunned", t.combat:IsLocked())
			t:check("no dash while stunned", not t.dash:Request())
			t:press("M1")
			t:check("no attack while stunned", t.combat:GetMoveId() == nil)
			t:waitFor(function()
				return not t.combat:IsLocked()
			end, 1)
			-- The chain's third hit knocks you down.
			t:debug("DummyMove", "DummyAttack", "Sword.M1_2")
			t:wait(0.35)
			t:debug("DummyMove", "DummyAttack", "Sword.M1_3")
			t:waitFor(function()
				return t.character:GetAttribute("CombatState") == "Downed"
			end, 3)
			t:check("knocked down, then on the floor", t.character:GetAttribute("CombatState") == "Downed",
				table.concat(record(), " > "))
			t:check("invincible at first on the floor", t.character:GetAttribute("Invulnerable") == true)
			t:press("Dash")
			t:waitFor(function()
				return t.character:GetAttribute("CombatState") == "TechRoll"
			end, 0.5)
			t:check("Shift on the floor = tech roll", t.character:GetAttribute("CombatState") == "TechRoll",
				tostring(t.character:GetAttribute("CombatState")))
			t:waitFor(function()
				return not t.combat:IsLocked()
			end, 1)
			t:check("then you're up", not t.combat:IsLocked())
			t:debug("ResetDummy", "DummyAttack")
		end,
	},
}

return {
	name = "Combat",
	description = "Hits, chain, block, parry, counter-hit, burnout, links, scaling, stamina, knockdown",
	tests = tests,
}
