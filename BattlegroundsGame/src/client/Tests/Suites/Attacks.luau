--!strict
-- Attacks suite (movement into attacks, on your own client): the M1 chain and its timings, clicks
-- during a swing queueing the next, which move each key picks (running = lunge, Space held on hit 3 =
-- launcher, air chain, dagger, 1), a side / back dash cutting straight into a swing with its
-- momentum, a front dash's M1 being the lunge, a landing roll cutting into a swing late, no dashing
-- out of a wind-up (but out of a recovery), and slowed walking. Hits are the Combat suite's job.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

type Context = Harness.Context

local LANE = Vector3.new(-40, 4, -120)
local FRAME = 1 / 60

local function waitIdle(t: Context)
	t:waitFor(function()
		return t.combat:GetPhase() == "Idle"
	end, 2)
end

local tests: { Harness.Test } = {
	{
		name = "M1 chain: 3 swings, then it starts over",
		run = function(t)
			t:teleport(LANE, Vector3.zAxis)
			local order = {}
			for _ = 1, 4 do
				t:press("M1")
				table.insert(order, t.combat:GetIndex())
				waitIdle(t)
			end
			t:check("swings 1, 2, 3, then 1 again", table.concat(order, ",") == "1,2,3,1", table.concat(order, ","))
			t:wait(CombatConfig.ChainWindow + 0.1)
			t:press("M1")
			t:check("a pause longer than the chain window starts over at 1", t.combat:GetIndex() == 1)
			waitIdle(t)
		end,
	},
	{
		name = "M1 timings and queueing",
		run = function(t)
			t:teleport(LANE, Vector3.zAxis)
			local record = t:recordAttribute("AttackPhase")
			local started = os.clock()
			t:press("M1")
			local activeAt = 0
			t:waitFor(function()
				return t.combat:GetPhase() == "Idle"
			end, 1, function()
				if t.combat:GetPhase() == "Active" and activeAt == 0 then
					activeAt = os.clock() - started
				end
			end)
			local total = os.clock() - started
			local phases = table.concat(record(), " > ")
			t:check("phases in order", phases == "- > Startup > Active > Recovery > -", phases)
			t:near("the hit comes out after 5 frames", activeAt, 5 * FRAME, 2 * FRAME)
			t:near("a whiffed M1 lasts 18 frames", total, 18 * FRAME, 3 * FRAME)
			t:press("M1")
			t:wait(0.05)
			t:press("M1") -- during the first swing: queued
			local first = t.combat:GetIndex()
			t:waitFor(function()
				return t.combat:GetIndex() ~= first
			end, 1)
			t:check("a click during a swing queues the next one", t.combat:GetIndex() == first + 1,
				string.format("swing %d then %d", first, t.combat:GetIndex()))
			waitIdle(t)
		end,
	},
	{
		name = "Which move each key picks",
		run = function(t)
			t:teleport(LANE, Vector3.zAxis)
			t:press("M1")
			t:check("M1 standing = M1 1", t.combat:GetMoveId() == "Sword.M1_1", tostring(t.combat:GetMoveId()))
			waitIdle(t)
			t:press("M1")
			waitIdle(t)
			t.motor:SetJumpHeld(true)
			t:press("M1")
			t:check("hit 3 with Space held = the launcher", t.combat:GetMoveId() == "Sword.Launcher", tostring(t.combat:GetMoveId()))
			t.motor:SetJumpHeld(false)
			waitIdle(t)
			t:wait(CombatConfig.ChainWindow + 0.1)

			t:teleport(LANE, Vector3.zAxis)
			t:move(Vector3.zAxis, true)
			t:wait(0.8)
			t:press("M1")
			t:check("running M1 = the lunge", t.combat:GetMoveId() == "Sword.Lunge", tostring(t.combat:GetMoveId()))
			t:stop()
			waitIdle(t)

			t:teleport(LANE, Vector3.zAxis)
			t:press("M2")
			t:check("right click = the dagger stab", t.combat:GetMoveId() == "Dagger.Stab", tostring(t.combat:GetMoveId()))
			waitIdle(t)
			t:press("One")
			t:check("1 = the sword's 1", t.combat:GetMoveId() == "Sword.One", tostring(t.combat:GetMoveId()))
			waitIdle(t)
			t:press("One")
			t:check("1 again inside its cooldown: nothing", t.combat:GetMoveId() == nil)

			t:teleport(LANE, Vector3.zAxis)
			t:press("Jump")
			t:waitFor(function()
				return t.motor:GetMode() == "Air"
			end, 0.5)
			t:release("Jump")
			t:wait(0.12)
			t:press("M1")
			t:check("M1 in the air = air M1 1", t.combat:GetMoveId() == "Sword.AirM1_1", tostring(t.combat:GetMoveId()))
			local y0 = t.root.Position.Y
			t:wait(0.15)
			t:check("an air move keeps you up while it plays", math.abs(t.root.Position.Y - y0) < 1,
				string.format("moved %.2f studs vertically", t.root.Position.Y - y0))
			waitIdle(t)
			t:grounded(3)
		end,
	},
	{
		name = "Side and back dashes cut into a swing, keeping momentum",
		run = function(t)
			local cases = {
				{ label = "side dash (A)", keys = Vector3.xAxis },
				{ label = "back dash (S)", keys = -Vector3.zAxis },
			}
			for _, case in cases do
				t:waitDashReady()
				t:teleport(LANE, Vector3.zAxis)
				t:aimCamera(Vector3.zAxis)
				t.humanoid:Move(case.keys, false)
				t:frame()
				t:press("Dash")
				t:wait(0.08)
				local dashSpeed = t:flatSpeed()
				t:press("M1")
				local reason = t.dash:GetLastEndReason()
				local phase = t.combat:GetPhase()
				t:frame()
				local carried = t:flatSpeed()
				t:check(case.label .. ": the dash ends on the click and the swing starts that frame",
					not t.dash:IsBusy() and reason == "attack" and phase == "Startup", string.format("dash ended by %s, swing %s", reason, phase))
				t:check(case.label .. ": you slide into the swing", carried > Config.WalkSpeed,
					string.format("%.1f studs/s right after (dash was %.1f)", carried, dashSpeed))
				t:stop()
				waitIdle(t)
			end
		end,
	},
	{
		name = "A front dash's M1 is the lunge",
		run = function(t)
			t:waitDashReady()
			t:teleport(LANE, Vector3.zAxis)
			t:aimCamera(Vector3.zAxis)
			t:frame()
			local start = t.root.Position
			t:press("Dash")
			t:wait(0.1)
			t:press("M1")
			t:check("front dash + click = the lunge", t.combat:GetMoveId() == "Sword.Lunge" and not t.dash:IsBusy(),
				string.format("move %s, dash %s", tostring(t.combat:GetMoveId()), t.dash:GetPhase()))
			waitIdle(t)
			local travelled = ((t.root.Position - start) * Vector3.new(1, 0, 1)).Magnitude
			t:check("it lunges well past a plain dash", travelled > Config.FrontDashDistance * 0.6,
				string.format("%.1f studs in all", travelled))
		end,
	},
	{
		name = "A landing roll cuts into a swing late, not early",
		run = function(t)
			local function rollAndClick(after: number): (boolean, string)
				t:teleport(Vector3.new(-100, 4, -100), Vector3.zAxis)
				local restY = t.root.Position.Y
				t.root.CFrame += Vector3.new(0, 20, 0)
				local pressed = false
				t:waitFor(function()
					return t.roll:IsRolling()
				end, 4, function()
					local vy = -t.root.AssemblyLinearVelocity.Y
					if not pressed and vy > 1 and t.root.Position.Y - restY <= vy * 0.08 + 0.3 then
						t:press("Jump")
						pressed = true
					end
				end)
				if t.jumpHeld then
					t:release("Jump")
				end
				local rolled = t.roll:IsRolling()
				t:wait(after)
				t:press("M1")
				local phase = t.combat:GetPhase()
				local stillRolling = t.roll:IsRolling()
				t:waitFor(function()
					return not t.roll:IsRolling() and t.combat:GetPhase() == "Idle"
				end, 2)
				return rolled and not stillRolling, phase
			end
			local cut, phase = rollAndClick(Config.RollAttackCancelTime + 0.03)
			t:check("late in the roll: it ends and the swing starts", cut and phase == "Startup", "swing " .. phase)
			local early, earlyPhase = rollAndClick(0.03)
			t:check("early in the roll: nothing", not early and earlyPhase == "Idle", "swing " .. earlyPhase)
		end,
	},
	{
		name = "No dashing out of a wind-up or hit, but out of a recovery; walking slows while swinging",
		run = function(t)
			t:waitDashReady()
			t:teleport(LANE, Vector3.zAxis)
			t:press("M1")
			local blocked = not t.dash:Request()
			t:check("no dash during startup", blocked)
			t:waitFor(function()
				return t.combat:GetPhase() == "Recovery"
			end, 1)
			t:press("Dash")
			t:check("a dash in the recovery cancels the swing", t.dash:IsBusy() and t.combat:GetPhase() == "Idle",
				string.format("dash %s, swing %s", t.dash:GetPhase(), t.combat:GetPhase()))
			t:waitFor(function()
				return not t.dash:IsBusy()
			end, 2)
			t:move(Vector3.zAxis, false)
			t:wait(0.4)
			t:press("M1")
			t:wait(0.22) -- past the swing's small step forward
			local slowed = t:flatSpeed()
			t:near("walking while swinging", slowed, Config.WalkSpeed * CombatConfig.AttackMoveSpeedScale, 1.5)
			waitIdle(t)
			t:wait(0.3)
			t:near("walking again after the swing", t:flatSpeed(), Config.WalkSpeed, 0.6)
		end,
	},
}

return {
	name = "Attacks",
	description = "M1 chain, key picks, movement cancels into attacks",
	tests = tests,
}
