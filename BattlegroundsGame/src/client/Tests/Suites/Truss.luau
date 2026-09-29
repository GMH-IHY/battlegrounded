--!strict
-- Truss suite, on the course's FallTowerTruss (x -61..-59, z -1..1, 80 tall): the same climbing
-- speed however you get on, real jumps off it, no snapping back on, grabbing only on purpose, and
-- jump spam never beating climbing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local CLIMBING = Enum.HumanoidStateType.Climbing

-- Average upward speed over `measure` seconds of climbing, after `settle` seconds on the truss.
local function climbSpeed(t: Context, settle: number, measure: number, timeout: number): number
	local sum, count = 0, 0
	local onSince: number? = nil
	t:waitFor(function()
		return onSince ~= nil and os.clock() - onSince >= settle + measure
	end, timeout, function()
		t.humanoid:Move(Vector3.zAxis, false)
		if t.humanoid:GetState() == CLIMBING then
			onSince = onSince or os.clock()
			if os.clock() - (onSince :: number) >= settle then
				sum += t.root.AssemblyLinearVelocity.Y
				count += 1
			end
		end
	end)
	return if count > 0 then sum / count else 0
end

local function tapJump(t: Context)
	t:press("Jump")
	task.delay(0.1, function()
		if t.jumpHeld then
			t:release("Jump")
		end
	end)
end

-- Whether the Humanoid grabs a truss (Climbing) within `duration` while `each` runs every frame.
local function grabsDuring(t: Context, duration: number, each: () -> ()): boolean
	return t:waitFor(function()
		return t.humanoid:GetState() == CLIMBING
	end, duration, each)
end

local tests: { Harness.Test } = {
	{
		name = "Same climbing speed however you get on",
		run = function(t)
			local want = Config.TrussClimbSpeed * t.motor:GetHealthSpeedScale()
			local tolerance = want * 0.2
			t:teleport(Vector3.new(-60, 4, -4), Vector3.zAxis)
			t:near("walking in", climbSpeed(t, 0.3, 0.5, 3), want, tolerance)
			t:teleport(Vector3.new(-60, 4, -16), Vector3.zAxis)
			t.motor:SetSprinting(true)
			t:near("sprinting in", climbSpeed(t, 0.3, 0.5, 3), want, tolerance)
			t.motor:SetSprinting(false)
			t:teleport(Vector3.new(-60, 4, -5), Vector3.zAxis)
			t.humanoid:Move(Vector3.zAxis, false)
			tapJump(t)
			t:near("grabbed mid-jump", climbSpeed(t, 0.3, 0.5, 3), want, tolerance)
			t:wait(0.6)
			local before = t.root.Position.Y
			t:stop()
			tapJump(t)
			local rose = 0
			t:waitFor(function()
				return false
			end, 0.35, function()
				rose = math.max(rose, t.root.Position.Y - before)
			end)
			t:check("jumping off high up is a real jump", rose > 2, string.format("rose %.1f", rose))
			t:near("getting back on after jumping off still climbs", climbSpeed(t, 0.3, 0.5, 3), want, tolerance)
		end,
	},
	{
		name = "No snapping back on; grabbing only on purpose",
		run = function(t)
			t:teleport(Vector3.new(-60, 4, -4), Vector3.zAxis)
			climbSpeed(t, 0.6, 0.1, 3)
			tapJump(t)
			local jumpedAt = os.clock()
			local snapped: number? = nil
			t:waitFor(function()
				return snapped ~= nil
			end, 1.2, function()
				t.humanoid:Move(Vector3.zAxis, false)
				if t.humanoid:GetState() == CLIMBING and os.clock() - jumpedAt > 0.05 then
					snapped = os.clock() - jumpedAt
				end
			end)
			t:check("after jumping off you can't snap straight back on", snapped == nil or (snapped :: number) >= Config.TrussRegrabDelay - 0.05,
				if snapped then string.format("grabbed again after %.2fs", snapped) else "not grabbed again")
			t:stop()
			t:grounded(4)

			t:teleport(Vector3.new(-60, 4, -2.3), Vector3.xAxis)
			t.root.CFrame += Vector3.new(0, 30, 0)
			t:check("falling past it with no keys doesn't grab", not grabsDuring(t, 1.2, function()
				t.humanoid:Move(Vector3.zero, false)
			end))
			t:grounded(3)
			t:teleport(Vector3.new(-68, 4, -2.2), Vector3.xAxis)
			t.motor:SetSprinting(true)
			t:check("running along it doesn't grab", not grabsDuring(t, 1.0, function()
				t.humanoid:Move(Vector3.xAxis, false)
			end))
			t:stop()
			t:waitDashReady()
			t:teleport(Vector3.new(-72, 4, -2.2), Vector3.xAxis)
			t:aimCamera(Vector3.xAxis)
			t.humanoid:Move(Vector3.xAxis, false)
			t:frame()
			t:press("Dash")
			t:check("dashing past it doesn't grab", not grabsDuring(t, 0.7, function() end))
			t:stop()
			t:teleport(Vector3.new(-60, 4, -4), Vector3.zAxis)
			climbSpeed(t, 0.6, 0.1, 3)
			tapJump(t)
			t:waitFor(function()
				return t.humanoid:GetState() ~= CLIMBING
			end, 0.5)
			t:check("jumping off and steering away never re-grabs", not grabsDuring(t, 1.5, function()
				t.humanoid:Move(-Vector3.zAxis, false)
			end))
		end,
	},
	{
		name = "Jump spam climbs no faster than climbing",
		run = function(t)
			local want = Config.TrussClimbSpeed * t.motor:GetHealthSpeedScale()
			t:teleport(Vector3.new(-60, 4, -4), Vector3.zAxis)
			climbSpeed(t, 0.5, 0.1, 3)
			local startY = t.root.Position.Y
			local lastPress = 0
			t:waitFor(function()
				return false
			end, 2.5, function()
				t.humanoid:Move(Vector3.zAxis, false)
				if os.clock() - lastPress > 0.15 then
					tapJump(t)
					lastPress = os.clock()
				end
			end)
			local gain = t.root.Position.Y - startY
			t:check("spamming jump", gain < want * 2.5 * 0.5, string.format("gained %.1f in 2.5 s (climbing gains %.1f)", gain, want * 2.5))
		end,
	},
}

return {
	name = "Truss",
	description = "Climb speed, jumping off, deliberate grabs",
	tests = tests,
}
