--!strict
-- Wind suite: the element's Q against the training dummies, checked against the server
-- (docs/MoveData.md, "Wind"). Q pushes (30 studs, a stagger, not a knockdown), S + Q pulls (to 5
-- studs in front, +5 so an M1 links), both still move a blocker without damage, add build-up toward
-- Drafted, and turn a projectile around so it hits whoever threw it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Combat.CombatConfig)
local Moves = require(ReplicatedStorage.Combat.Moves)

type Context = Harness.Context

local function health(model: Model): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.Health else 0
end

local function rootOf(model: Model): BasePart
	return model:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function fresh(t: Context)
	t:debug("ClearCooldowns")
	t.combat:ResetForTest()
	t.combat:SetBackForTest(nil)
end

local function waitIdle(t: Context, timeout: number?)
	t:waitFor(function()
		return t.combat:GetPhase() == "Idle"
	end, timeout or 3)
end

-- Presses Q (pull = S held), returns the server's answer (or "").
local function q(t: Context, pull: boolean): string
	t.combat:SetBackForTest(pull)
	t.combat.lastResult = ""
	t:press("Q")
	t:waitFor(function()
		return t.combat:GetLastResult() ~= ""
	end, 0.8)
	t.combat:SetBackForTest(nil)
	return t.combat:GetLastResult()
end

local function flatGap(a: BasePart, b: BasePart): number
	local d = a.Position - b.Position
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

local PUSH = Moves.Get("Wind.Push")
local PULL = Moves.Get("Wind.Pull")

local tests: { Harness.Test } = {
	{
		name = "Q pushes: 30 studs, a stagger, not a knockdown",
		run = function(t)
			fresh(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 5)
			local before = flatGap(rootOf(dummy), t.root)
			local hp = health(dummy)
			local result = q(t, false)
			local state = t:server(dummy).state
			t:wait(0.6)
			local after = flatGap(rootOf(dummy), t.root)
			t:check("Q is the push", t.combat:GetLastMove() == "Wind.Push", tostring(t.combat:GetLastMove()))
			t:check("it hits and staggers (no knockdown)", result == "Hit" and state == "Stunned", string.format("%s, state %s", result, tostring(state)))
			t:near("carried about 30 studs farther away", after - before, PUSH and PUSH.OnHit.Knockback or 30, 6)
			t:near("deals its damage", hp - health(dummy), PUSH and PUSH.Damage or 3, 0.5)
			waitIdle(t)
		end,
	},
	{
		name = "S + Q pulls to 5 studs in front, and an M1 links",
		run = function(t)
			fresh(t)
			local dummy = t:dummy("DummyStand")
			t:faceDummy(dummy, 14)
			local result = q(t, true)
			t:check("S + Q is the pull", t.combat:GetLastMove() == "Wind.Pull" and result == "Hit", tostring(t.combat:GetLastMove()) .. " " .. result)
			local advantage = t:server().lastAdvantage
			t:wait(0.4)
			t:near("pulled to about 5 studs in front", flatGap(rootOf(dummy), t.root), PULL and PULL.OnHit.Knockback or 5, 2)
			t:check("plus frames on hit (+5 at the first active frame)", typeof(advantage) == "number" and advantage > 0, tostring(advantage))
			-- Pull again, then M1 as soon as you can: still in the same combo.
			waitIdle(t)
			t:debug("ClearCooldowns")
			t:debug("ResetDummy", "DummyStand")
			t:wait(0.1)
			t:faceDummy(dummy, 14)
			q(t, true)
			t:press("M1")
			t.combat.lastResult = ""
			t:waitFor(function()
				return t.combat:GetLastMove() == "Sword.M1_1" and t.combat:GetLastResult() ~= ""
			end, 1.5)
			local combo = t:server(dummy).comboHits
			t:check("the M1 after it links (2 hits in the combo)", t.combat:GetLastResult() == "Hit" and combo == 2,
				string.format("M1 %s, combo %s", t.combat:GetLastResult(), tostring(combo)))
			waitIdle(t)
		end,
	},
	{
		name = "A blocker is still moved, with no damage",
		run = function(t)
			fresh(t)
			local dummy = t:dummy("DummyBlock", "Block")
			t:faceDummy(dummy, 5)
			t:wait(0.2)
			local before = flatGap(rootOf(dummy), t.root)
			local hp = health(dummy)
			local result = q(t, false)
			t:wait(0.6)
			local after = flatGap(rootOf(dummy), t.root)
			t:check("blocked", result == "Block", result)
			t:check("pushed anyway", after - before > 15, string.format("%.1f -> %.1f studs", before, after))
			t:near("no damage (no chip either)", hp - health(dummy), 0, 0.01)
			waitIdle(t)
		end,
	},
	{
		name = "Four Q hits fill build-up: Drafted; the next launch goes higher",
		run = function(t)
			fresh(t)
			local dummy = t:dummy("DummyStand")
			local hits = 0
			for _ = 1, 4 do
				t:debug("ClearCooldowns")
				t:debug("ResetDummy", "DummyStand")
				t:wait(0.1)
				t:faceDummy(dummy, 5)
				if q(t, false) == "Hit" then
					hits += 1
				end
				waitIdle(t)
			end
			local snapshot = t:server(dummy)
			t:check("4 x 25 build-up = Drafted", hits == 4 and snapshot.drafted == true,
				string.format("%d hits, build-up %s, drafted %s", hits, tostring(snapshot.buildup), tostring(snapshot.drafted)))
			t:log(string.format("Drafted: next launch x%.1f, or +%d frames down", Config.DraftedLaunchScale, Config.DraftedDownFrames))
		end,
	},
	{
		name = "Q turns a spore around: it hits the one who threw it",
		run = function(t)
			fresh(t)
			local dummy = t:dummy("DummyStand")
			t:debug("DummyLotus", "DummyStand", 0)
			t:faceDummy(dummy, 20)
			t:wait(0.2)
			local myHp = t.humanoid.Health
			local hp = health(dummy)
			t:debug("DummyMove", "DummyStand", "Lotus.Spore1")
			q(t, false)
			t:wait(1)
			t:check("you weren't hit", t.humanoid.Health >= myHp - 0.01, string.format("%.0f -> %.0f", myHp, t.humanoid.Health))
			t:check("the spore came back and hit the dummy", hp - health(dummy) > 0.5, string.format("dummy %.0f -> %.0f", hp, health(dummy)))
			waitIdle(t)
		end,
	},
}

return {
	name = "Wind",
	description = "Q push / pull, blockers moved, Drafted, projectiles turned around",
	tests = tests,
}
