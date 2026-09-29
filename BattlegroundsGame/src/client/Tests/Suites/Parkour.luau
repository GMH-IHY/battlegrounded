--!strict
-- Auto parkour suite: sprinting into the course's VaultBox (3 high), JumpBox (4 high), MantleLedge
-- (9 high), a 6-stud ledge (made here), SlideGap and TallWall; angles and corners; a wall hop into a
-- ledge grab; no dash during a slide.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local ACTIONS = { "Vault", "StepUp", "Climb", "Slide" }
local RUN = Config.RunSpeed

type Run = {
	counts: { [string]: number },
	final: Vector3,
	maxY: number,
	speedAfter: number,
	yAfter: number,
	startMode: string,
	dashDuring: boolean,
	standingAfter: boolean,
	headingAfter: number, -- degrees, 0 = +Z, + = toward +X, 0.1 s after the move
	maxTurn: number, -- biggest one-frame facing change during a move (degrees)
}

local function angled(degrees: number): Vector3
	local r = math.rad(degrees)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

-- A 6-stud ledge in hand reach from the ground: x -86..-74, z -66..-54, top at y 6.
local function sixStudLedge(t: Context)
	t:block("ParkourTestLedge", Vector3.new(12, 6, 12), CFrame.new(-80, 3, -60))
end

local function sprintAt(t: Context, start: Vector3, direction: Vector3, duration: number, sprint: boolean, jumpAt: number?): Run
	t:teleport(start, direction)
	local before: { [string]: number } = {}
	for _, name in ACTIONS do
		before[name] = t.parkour:GetCount(name)
	end
	local maxY = t.root.Position.Y
	local speedAfter, yAfter, headingAfter, maxTurn = -1, -math.huge, 0, 0
	local endedAt: number? = nil
	local lastYaw: number? = nil
	local wasBusy, jumped, dashDuring = false, false, false
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		t:move(direction, sprint)
		if jumpAt and not jumped and os.clock() - t0 >= jumpAt then
			t:press("Jump")
			jumped = true
		elseif jumped and t.jumpHeld then
			t:release("Jump")
		end
		local busy = t.parkour:IsBusy()
		if busy and t.parkour:GetAction() == "Slide" and not dashDuring then
			dashDuring = t.dash:Request()
		end
		if wasBusy and not busy then
			endedAt = os.clock()
		end
		if endedAt and speedAfter < 0 and os.clock() - endedAt >= 0.1 then
			local v = t.root.AssemblyLinearVelocity
			speedAfter = t:flatSpeed()
			yAfter = t.root.Position.Y
			headingAfter = math.deg(math.atan2(v.X, v.Z))
		end
		local look = t.root.CFrame.LookVector
		local yaw = math.deg(math.atan2(look.X, look.Z))
		if busy and lastYaw then
			maxTurn = math.max(maxTurn, math.abs((yaw - lastYaw + 180) % 360 - 180))
		end
		lastYaw = yaw
		wasBusy = busy
		maxY = math.max(maxY, t.root.Position.Y)
		t:frame()
	end
	local counts: { [string]: number } = {}
	for _, name in ACTIONS do
		counts[name] = t.parkour:GetCount(name) - before[name]
	end
	t:stop()
	t:waitFor(function()
		return not t.parkour:IsBusy() and t.motor:GetMode() == "Ground"
	end, 3)
	t:wait(0.2)
	return {
		counts = counts,
		final = t.root.Position,
		maxY = maxY,
		speedAfter = speedAfter,
		yAfter = yAfter,
		startMode = t.parkour:GetLastStartMode(),
		dashDuring = dashDuring,
		standingAfter = t.motor:GetMode() == "Ground",
		headingAfter = headingAfter,
		maxTurn = maxTurn,
	}
end

local function total(r: Run): number
	return r.counts.Vault + r.counts.StepUp + r.counts.Climb + r.counts.Slide
end

local function describe(t: Context, r: Run): string
	return string.format("V%d S%d C%d Sl%d, ended (%.0f, %.1f, %.0f), %s", r.counts.Vault, r.counts.StepUp, r.counts.Climb,
		r.counts.Slide, r.final.X, r.final.Y, r.final.Z, t.parkour:GetLastInfo())
end

-- Start point `back` studs in front of a face, angled so the body's middle meets it at hitX.
local function clipStart(hitX: number, faceZ: number, back: number, degrees: number): Vector3
	return Vector3.new(hitX - back * math.tan(math.rad(degrees)), 4, faceZ - back)
end

local tests: { Harness.Test } = {
	{
		name = "Vault",
		run = function(t)
			local v = sprintAt(t, Vector3.new(0, 4, 18), Vector3.zAxis, 1.8, true)
			t:check("sprint into the VaultBox vaults and keeps speed", v.counts.Vault == 1 and v.final.Z > 45 and v.speedAfter > RUN * 0.8,
				describe(t, v) .. string.format(", speed after %.1f", v.speedAfter))
			local w = sprintAt(t, Vector3.new(0, 4, 30), Vector3.zAxis, 1.5, false)
			t:check("walking into it does NOT vault", total(w) == 0 and w.final.Z < 39, describe(t, w))
			local a50 = sprintAt(t, Vector3.new(-12, 4, 28), angled(50), 1.4, true)
			t:check("50 degrees off head-on vaults and keeps its line", a50.counts.Vault == 1 and a50.final.Z > 41 and math.abs(a50.headingAfter - 50) < 12,
				describe(t, a50) .. string.format(", heading after %.0f", a50.headingAfter))
			local a70 = sprintAt(t, Vector3.new(-12, 4, 35), angled(70), 1.2, true)
			t:check("70 degrees along it: nothing, or one vault over its far corner", total(a70) == 0 or (a70.counts.Vault == 1 and total(a70) == 1),
				describe(t, a70))
			t:setHealth(0.2)
			local low = sprintAt(t, Vector3.new(0, 4, 18), Vector3.zAxis, 1.8, true)
			t:check("still works at 20% HP", low.counts.Vault == 1 and low.final.Z > 45, describe(t, low))
		end,
	},
	{
		name = "Step-up and climbs",
		run = function(t)
			local st = sprintAt(t, Vector3.new(-30, 4, 14), Vector3.zAxis, 1.6, true)
			t:check("sprint into the JumpBox steps up onto it", st.counts.StepUp == 1 and st.yAfter > 6.3, describe(t, st))
			local c = sprintAt(t, Vector3.new(-30, 4, 51), Vector3.zAxis, 1.4, true)
			t:check("sprint into the 9-stud ledge (out of reach) does NOT climb", total(c) == 0 and c.final.Z < 64, describe(t, c))
			local ac = sprintAt(t, Vector3.new(-30, 4, 58), Vector3.zAxis, 1.8, false, 0.05)
			t:check("jumping at the 9-stud ledge grabs and scales it", ac.counts.Climb == 1 and ac.startMode == "Air" and ac.yAfter > 11.3,
				describe(t, ac))
			local acs = sprintAt(t, Vector3.new(-30, 4, 51), Vector3.zAxis, 1.8, true, 0.3)
			t:check("sprint + jump at it grabs and scales it", acs.counts.Climb == 1 and acs.yAfter > 11.3, describe(t, acs))
			sixStudLedge(t)
			local c6 = sprintAt(t, Vector3.new(-80, 4, -80), Vector3.zAxis, 1.6, true)
			t:check("sprint into a 6-stud ledge climbs it and comes out running", c6.counts.Climb == 1 and c6.yAfter > 8.3 and c6.speedAfter > RUN - 4,
				describe(t, c6))
			local c45 = sprintAt(t, Vector3.new(-87, 4, -78), angled(40), 1.6, true)
			t:check("40 degrees off, it climbs turning smoothly", c45.counts.Climb == 1 and c45.yAfter > 8.3 and c45.maxTurn < 25,
				describe(t, c45) .. string.format(", biggest turn %.0f deg", c45.maxTurn))
			local against = sprintAt(t, Vector3.new(-80, 4, -66.8), Vector3.zAxis, 1.2, true)
			t:check("pressed against it from a standstill climbs", against.counts.Climb == 1 and against.yAfter > 8.3, describe(t, against))
			local tall = sprintAt(t, Vector3.new(20, 4, 56), Vector3.xAxis, 1.4, true)
			t:check("sprint into the 24-high TallWall does nothing", total(tall) == 0 and tall.final.X < 33, describe(t, tall))
		end,
	},
	{
		name = "Corners",
		run = function(t)
			sixStudLedge(t)
			local vc = sprintAt(t, Vector3.new(-1, 4, 32), angled(45), 1.4, true)
			t:check("at the VaultBox's corner: vaults", vc.counts.Vault == 1, describe(t, vc))
			local sc = sprintAt(t, Vector3.new(-29, 4, 25), angled(45), 1.4, true)
			t:check("at the JumpBox's corner: steps up or vaults the corner", (sc.counts.StepUp == 1 and sc.yAfter > 6.3) or sc.counts.Vault == 1,
				describe(t, sc))
			local cc = sprintAt(t, Vector3.new(-81, 4, -73), angled(45), 1.4, true)
			t:check("at the 6-stud ledge's corner: climbs", cc.counts.Climb == 1 and cc.yAfter > 8.3, describe(t, cc))
			local jc = sprintAt(t, Vector3.new(-26, 4, 60), angled(45), 1.6, false, 0.05)
			t:check("jumping at the 9-stud ledge's corner: scales it", jc.counts.Climb == 1 and jc.yAfter > 11.3, describe(t, jc))
			local v70 = sprintAt(t, clipStart(5.4, 39, 6, 70), angled(70), 1.6, true)
			t:check("clipping the VaultBox's end at 70 degrees vaults over the corner", v70.counts.Vault == 1, describe(t, v70))
			local v78 = sprintAt(t, clipStart(5.6, 39, 5, 78), angled(78), 1.6, true)
			t:check("... at 78 degrees too", v78.counts.Vault == 1, describe(t, v78))
			local b70 = sprintAt(t, clipStart(-34, 32, 6, 70), angled(70), 1.6, true)
			t:check("brushing along the JumpBox at 70 degrees does NOT step up at its end", total(b70) == 0, describe(t, b70))
			local c70 = sprintAt(t, clipStart(-74.6, -66, 6, 70), angled(70), 1.6, true)
			t:check("clipping the 6-stud ledge's end at 70 degrees climbs it", c70.counts.Climb == 1 and c70.maxY > 8.5, describe(t, c70))
		end,
	},
	{
		name = "Slide",
		run = function(t)
			local sl = sprintAt(t, Vector3.new(0, 4, 58), Vector3.zAxis, 2.0, true)
			t:check("sprint into the SlideGap slides under and stands up, no fling",
				sl.counts.Slide == 1 and sl.final.Z > 86 and sl.standingAfter and sl.maxY < 3.6 and sl.final.Y > 2.6,
				describe(t, sl) .. string.format(", highest root %.1f", sl.maxY))
			t:check("no dash during a slide", sl.counts.Slide == 1 and not sl.dashDuring)
			t:waitDashReady()
			local still = sprintAt(t, Vector3.new(0, 4, 74.5), Vector3.zAxis, 1.5, true)
			t:check("slide from a standstill at the gap's edge", still.counts.Slide == 1 and still.final.Z > 86 and still.maxY < 3.6, describe(t, still))
			local slant = sprintAt(t, Vector3.new(-3, 4, 62), angled(20), 2.0, true)
			t:check("slide at an angle never flings", slant.counts.Slide == 1 and slant.maxY < 3.6 and slant.standingAfter, describe(t, slant))
			local walk = sprintAt(t, Vector3.new(0, 4, 66), Vector3.zAxis, 1.5, false)
			t:check("walking into the gap does NOT slide", total(walk) == 0 and walk.final.Z < 76, describe(t, walk))
		end,
	},
	{
		name = "Wall hop into a ledge grab",
		run = function(t)
			-- 15 high: too tall to grab from a jump (7.2 + reach 6.5), but a wall run carries you in reach.
			t:block("FlowTestWall", Vector3.new(8, 15, 30), CFrame.new(-127, 7.5, -105))
			t:teleport(Vector3.new(-134, 4, -118), Vector3.zAxis)
			t:aimCamera(Vector3.zAxis)
			t:frame()
			local climbs = t.parkour:GetCount("Climb")
			local hops = t.hop:GetTotalHops()
			t:press("Jump")
			local maxY = t.root.Position.Y
			t:waitFor(function()
				return false
			end, 2.2, function()
				t.humanoid:Move(Vector3.new(1, 0, 1).Unit, false)
				maxY = math.max(maxY, t.root.Position.Y)
			end)
			t:release("Jump")
			t:stop()
			t:check("hops, grabs the top and climbs on",
				t.parkour:GetCount("Climb") - climbs == 1 and t.parkour:GetLastStartMode() == "WallRun" and maxY > 17.5,
				string.format("%d hop(s), climb started from %s, highest %.1f (on top = 18)", t.hop:GetTotalHops() - hops,
					t.parkour:GetLastStartMode(), maxY))
			t:waitFor(function()
				return t.motor:GetMode() == "Ground" and not t.parkour:IsBusy()
			end, 4)
		end,
	},
}

return {
	name = "Parkour",
	description = "Vault, step-up, climbs, corners, slide, wall hop into a ledge",
	tests = tests,
}
