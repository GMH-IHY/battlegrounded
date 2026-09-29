--!strict
-- Landing suite: the landing roll (when it happens, distance by fall height, momentum and aiming,
-- rolling off ledges and into walls, the roll-jump), long falls without a roll leaving you free
-- to act at once (there's no landing lag), plus the landing clips.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local OPEN = Vector3.new(-100, 4, -100)

type Drop = {
	rolled: boolean,
	rollDistance: number,
	rollDirection: Vector3,
	endSpeed: number,
	rise: number,
	jumpedAfter: boolean,
	fall: number,
	info: string,
}

-- Drops the character `height` studs above `ground` with `horizontal` speed.
-- style: "late" = Space ~0.08 s before touchdown; "early" = ~0.5 s before; "none"; "hold" = late and
-- kept held; "rolljump" = late + a fresh press near the end of the roll. `keys`: held during the drop.
local function drop(t: Context, ground: Vector3, height: number, horizontal: Vector3, style: string, keys: Vector3?): Drop
	t:teleport(ground, if horizontal.Magnitude > 0.1 then horizontal.Unit else Vector3.zAxis)
	local restY = t.root.Position.Y
	local rollsBefore = t.roll:GetTotalRolls()
	local move = keys or (if horizontal.Magnitude > 0.1 then horizontal.Unit else Vector3.zero)
	t.root.CFrame += Vector3.new(0, height, 0)
	t.root.AssemblyLinearVelocity = horizontal
	local pressed, released, boosted = false, false, false
	local pressAt = 0
	local t0 = os.clock()
	while t.motor:GetMode() ~= "Ground" or os.clock() - t0 < 0.15 do
		if os.clock() - t0 > 6 then
			break
		end
		t.humanoid:Move(move, false)
		-- Give the fall its speed once airborne (the teleport's ground frame would cap it).
		if not boosted and t.motor:GetMode() == "Air" then
			boosted = true
			t.root.AssemblyLinearVelocity = Vector3.new(horizontal.X, t.root.AssemblyLinearVelocity.Y, horizontal.Z)
			t.motor:ApplyMomentum(horizontal)
		end
		local vy = -t.root.AssemblyLinearVelocity.Y
		local above = t.root.Position.Y - restY
		local lead = if style == "early" then 0.5 elseif style == "none" then -1 else 0.08
		if not pressed and lead > 0 and vy > 1 and above <= vy * lead + 0.3 then
			t:press("Jump")
			pressed, pressAt = true, os.clock()
		end
		if pressed and not released and style ~= "hold" and os.clock() - pressAt > 0.08 then
			t:release("Jump")
			released = true
		end
		t:frame()
	end
	local landY, landPos = t.root.Position.Y, t.root.Position
	local rolled = t.roll:GetTotalRolls() > rollsBefore
	local maxY = landY
	local freshPressed = false
	local t1 = os.clock()
	while t.roll:IsRolling() and os.clock() - t1 < 2 do
		t.humanoid:Move(move, false)
		if pressed and not released and style ~= "hold" and os.clock() - pressAt > 0.08 then
			t:release("Jump")
			released = true
		end
		if style == "rolljump" and not freshPressed and os.clock() - t1 > Config.LandingRollTime - 0.1 then
			t:release("Jump")
			t:press("Jump")
			freshPressed = true
		end
		maxY = math.max(maxY, t.root.Position.Y)
		t:frame()
	end
	local offset = (t.root.Position - landPos) * Vector3.new(1, 0, 1)
	local endSpeed = t:flatSpeed()
	local jumpedAfter = false
	local t2 = os.clock()
	while os.clock() - t2 < 0.5 do
		t.humanoid:Move(move, false)
		if style == "hold" and os.clock() - pressAt > 1.2 and t.jumpHeld then
			t:release("Jump")
		end
		if style == "rolljump" and os.clock() - t2 > 0.1 and t.jumpHeld then
			t:release("Jump")
		end
		if t.motor:GetMode() == "Air" and t.root.Position.Y > landY + 1 then
			jumpedAfter = true
		end
		maxY = math.max(maxY, t.root.Position.Y)
		t:frame()
	end
	t:stop()
	t:waitFor(function()
		return t.motor:GetMode() == "Ground" and not t.roll:IsRolling()
	end, 4)
	return {
		rolled = rolled,
		rollDistance = offset.Magnitude,
		rollDirection = if offset.Magnitude > 0.5 then offset.Unit else Vector3.zero,
		endSpeed = endSpeed,
		rise = maxY - landY,
		jumpedAfter = jumpedAfter,
		fall = t.roll:GetLastFall(),
		info = t.roll:GetLastInfo(),
	}
end

local function bonus(fall: number): number
	return math.min(Config.LandingRollBaseDistance + (fall - Config.LandingRollMinFall) * Config.LandingRollDistancePerStud,
		Config.LandingRollMaxBonus)
end

local tests: { Harness.Test } = {
	{
		name = "When the roll happens",
		run = function(t)
			local a = drop(t, OPEN, 20, Vector3.zero, "late")
			t:check("drop 20 + press right before landing rolls", a.rolled and math.abs(a.rollDistance - bonus(a.fall)) < 2,
				string.format("%.1f studs (want %.1f), fall %.1f", a.rollDistance, bonus(a.fall), a.fall))
			t:check("no press: no roll", not drop(t, OPEN, 20, Vector3.zero, "none").rolled)
			local c = drop(t, OPEN, 20, Vector3.zero, "early")
			t:check("press too early: no roll", not c.rolled, c.info)
			local d = drop(t, OPEN, Config.JumpHeight - 0.5, Vector3.zero, "late")
			t:check("short fall + press: a buffered jump instead", not d.rolled and d.jumpedAfter, d.info)
			local e = drop(t, OPEN, 40, Vector3.zero, "late")
			t:check("higher fall rolls farther", e.rolled and e.rollDistance > a.rollDistance + 2,
				string.format("fall %.1f -> %.1f studs (vs %.1f)", e.fall, e.rollDistance, a.rollDistance))
		end,
	},
	{
		name = "Momentum, aiming and the roll-jump",
		run = function(t)
			local run = Config.RunSpeed
			local f = drop(t, OPEN, 20, Vector3.zAxis * run, "late")
			local want = run * Config.LandingRollTime + bonus(f.fall)
			t:check("momentum kept through the roll", f.rolled and f.endSpeed > run - 4 and math.abs(f.rollDistance - want) < 4,
				string.format("end speed %.1f, rolled %.1f (want ~%.1f)", f.endSpeed, f.rollDistance, want))
			local g = drop(t, OPEN, 20, Vector3.zero, "hold")
			t:check("holding Space through the roll doesn't jump", g.rolled and not g.jumpedAfter and g.rise < 1.5,
				string.format("jumped %s, rose %.1f", tostring(g.jumpedAfter), g.rise))
			local h = drop(t, OPEN, 20, Vector3.zAxis * 10, "rolljump")
			t:check("a fresh press at the end of the roll jumps out", h.rolled and h.jumpedAfter)
			local side = drop(t, OPEN, 20, Vector3.zAxis * run, "late", Vector3.xAxis)
			t:check("holding D rolls sideways", side.rolled and side.rollDirection:Dot(Vector3.xAxis) > 0.9,
				string.format("direction (%.2f, %.2f)", side.rollDirection.X, side.rollDirection.Z))
			local back = drop(t, OPEN, 20, Vector3.zAxis * run, "late", -Vector3.zAxis)
			t:check("rolling back against momentum keeps part of it",
				back.rolled and back.rollDirection:Dot(-Vector3.zAxis) > 0.9 and back.endSpeed > run * Config.LandingRollTurnKeep - 3,
				string.format("end speed %.1f", back.endSpeed))
		end,
	},
	{
		name = "Rolling off ledges and into walls",
		run = function(t)
			local box = drop(t, Vector3.new(-36, 8, 40), 16, Vector3.xAxis * 14, "late")
			t:check("rolling off a ledge ends the roll and keeps speed", box.rolled and box.endSpeed > 10,
				string.format("speed leaving %.1f", box.endSpeed))
			local wall = drop(t, Vector3.new(24, 4, 50), 20, Vector3.xAxis * 8, "late")
			t:check("rolling into a wall doesn't launch", wall.rolled and wall.rise < 1.5, string.format("rose %.1f", wall.rise))
		end,
	},
	{
		name = "A long fall without a roll: no landing lag",
		run = function(t)
			t:waitDashReady()
			t:teleport(OPEN, Vector3.zAxis)
			local record = t:recordAttribute("LocoAnim")
			t.root.CFrame += Vector3.new(0, 30, 0)
			t:grounded(6)
			t:frame()
			local dashed = t.dash:Request()
			t:check("you can dash straight away", dashed)
			t:waitFor(function()
				return not t.dash:IsBusy()
			end, 2)
			local jump = t:jumpOnce()
			t:check("and jump", jump.height > Config.JumpHeight * 0.7, string.format("%.1f studs", jump.height))
			local anims = table.concat(record(), " > ")
			t:check("no heavy landing clip", string.find(anims, "LandHeavy") == nil, anims)
		end,
	},
	{
		name = "Landing clips",
		run = function(t)
			t:teleport(OPEN, Vector3.zAxis)
			local record = t:recordAttribute("LocoAnim")
			t:jumpOnce()
			t:wait(0.3)
			local standing = table.concat(record(), " > ")
			t:check("standing jump lands with LandLight", string.find(standing, "Fall > LandLight") ~= nil
				or string.find(standing, "Jump > LandLight") ~= nil, standing)
			t:teleport(OPEN, Vector3.zAxis)
			t:move(Vector3.zAxis, true)
			t:wait(0.8)
			record = t:recordAttribute("LocoAnim")
			t:jumpOnce()
			t:wait(0.3)
			local running = table.concat(record(), " > ")
			t:check("running jump lands with LandRun, then back to Sprint", string.find(running, "LandRun > Sprint") ~= nil, running)
		end,
	},
	{
		name = "No dash during a roll",
		run = function(t)
			t:teleport(OPEN, Vector3.zAxis)
			local restY = t.root.Position.Y
			t.root.CFrame += Vector3.new(0, 20, 0)
			local dashed, sawRoll, pressed = false, false, false
			t:waitFor(function()
				return sawRoll and not t.roll:IsRolling()
			end, 4, function()
				local vy = -t.root.AssemblyLinearVelocity.Y
				if not pressed and vy > 1 and t.root.Position.Y - restY <= vy * 0.08 + 0.3 then
					t:press("Jump")
					pressed = true
				end
				if t.roll:IsRolling() then
					sawRoll = true
					if t.jumpHeld then
						t:release("Jump")
					end
					dashed = dashed or t.dash:Request()
				end
			end)
			t:check("rolled, and no dash started during it", sawRoll and not dashed)
		end,
	},
}

return {
	name = "Landing",
	description = "Landing roll, long falls, landing clips",
	tests = tests,
}
