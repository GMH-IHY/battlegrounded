--!strict
-- Attacks suite (movement into attacks, with the placeholder M1 until the combat system exists):
-- the 3-hit chain and its timings, clicks during a swing queueing the next, a side / back dash
-- cutting straight into a swing with its momentum, a front dash's click being the dash punch, a
-- landing roll cutting into a swing late, no dashing out of a wind-up, and slowed walking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local LANE = Vector3.new(-40, 4, -120)
local FRAME = 1 / 60

local function waitIdle(t: Context)
	t:waitFor(function()
		return t.m1:GetPhase() == "Idle"
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
				table.insert(order, t.m1:GetIndex())
				waitIdle(t)
			end
			t:check("swings 1, 2, 3, then 1 again", table.concat(order, ",") == "1,2,3,1", table.concat(order, ","))
			t:wait(0.7)
			t:press("M1")
			t:check("a pause longer than the chain window starts over at 1", t.m1:GetIndex() == 1)
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
			local activeAt, recoveryAt = 0, 0
			t:waitFor(function()
				return t.m1:GetPhase() == "Idle"
			end, 1, function()
				local phase = t.m1:GetPhase()
				if phase == "Active" and activeAt == 0 then
					activeAt = os.clock() - started
				elseif phase == "Recovery" and recoveryAt == 0 then
					recoveryAt = os.clock() - started
				end
			end)
			local total = os.clock() - started
			local phases = table.concat(record(), " > ")
			t:check("phases in order", phases == "- > Startup > Active > Recovery > -", phases)
			t:near("hit comes out after 5 frames", activeAt, 5 * FRAME, 2 * FRAME)
			t:near("swing lasts 18 frames", total, 18 * FRAME, 3 * FRAME)
			t:press("M1")
			t:wait(0.05)
			t:press("M1") -- during the first swing: queued
			local first = t.m1:GetIndex()
			t:waitFor(function()
				return t.m1:GetIndex() ~= first
			end, 1)
			t:check("a click during a swing queues the next one", t.m1:GetIndex() == first + 1,
				string.format("swing %d then %d", first, t.m1:GetIndex()))
			waitIdle(t)
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
				local phase = t.m1:GetPhase()
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
		name = "A front dash's click is the dash punch; the punch can't be cancelled",
		run = function(t)
			t:waitDashReady()
			t:teleport(LANE, Vector3.zAxis)
			t:aimCamera(Vector3.zAxis)
			t:frame()
			t:press("Dash")
			t:wait(0.1)
			t:press("M1")
			t:check("front dash + click = dash punch", t.dash:GetPhase() == "Punch" and t.m1:GetPhase() == "Idle",
				string.format("dash %s, swing %s", t.dash:GetPhase(), t.m1:GetPhase()))
			t:wait(0.1)
			t:press("M1")
			t:check("clicking during the punch does nothing", t.dash:GetPhase() == "Punch" and t.m1:GetPhase() == "Idle")
			t:waitFor(function()
				return not t.dash:IsBusy()
			end, 2)
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
				local phase = t.m1:GetPhase()
				local stillRolling = t.roll:IsRolling()
				t:waitFor(function()
					return not t.roll:IsRolling() and t.m1:GetPhase() == "Idle"
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
		name = "No dashing out of a wind-up or hit; walking slows while swinging",
		run = function(t)
			t:waitDashReady()
			t:teleport(LANE, Vector3.zAxis)
			t:press("M1")
			local blocked = not t.dash:Request()
			t:check("no dash during startup", blocked)
			waitIdle(t)
			t:move(Vector3.zAxis, false)
			t:wait(0.4)
			t:press("M1")
			t:wait(0.1)
			local slowed = t:flatSpeed()
			t:near("walking while swinging", slowed, Config.WalkSpeed * Config.AttackMoveSpeedScale, 1)
			waitIdle(t)
			t:wait(0.3)
			t:near("walking again after the swing", t:flatSpeed(), Config.WalkSpeed, 0.6)
		end,
	},
}

return {
	name = "Attacks",
	description = "Placeholder M1 chain, movement cancels into swings",
	tests = tests,
}
