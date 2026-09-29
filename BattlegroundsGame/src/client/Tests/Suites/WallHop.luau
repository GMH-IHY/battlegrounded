--!strict
-- Wall hop suite: when a hop happens (held / pressed Space, W+A / W+D into and along the wall) and
-- when it must not (a tap, W alone, parallel, straight in, away, the wall's very end), hops by
-- health, chaining up one wall, and zig-zagging an alley. Uses the tall wall (x 33..35, z 32..80,
-- 24 high) and Workspace > WallHopAlley (walls at x 100 and 114; made here if it's missing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local INTO = Vector3.new(1, 0, 1).Unit -- wall at +X, running along +Z
local ALLEY_LEFT_X, ALLEY_RIGHT_X = 100, 114

-- style: "hold" = Space held from the jump; "tap" = a quick jump only; "airpress" = a quick jump,
-- then Space pressed again in the air at 0.3 s. Returns (hops, rise, movement along Z).
local function attempt(t: Context, style: string, keys: Vector3, duration: number, start: Vector3?, look: Vector3?): (number, number, number)
	t:teleport(start or Vector3.new(30, 4, 40), Vector3.zAxis)
	t:aimCamera(look or Vector3.zAxis)
	t:frame()
	local before = t.hop:GetTotalHops()
	local startY, startZ = t.root.Position.Y, t.root.Position.Z
	local maxY = startY
	t:press("Jump")
	local released, pressedAgain = false, false
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		local since = os.clock() - t0
		if style ~= "hold" and not released and since > 0.08 then
			t:release("Jump")
			released = true
		end
		if style == "airpress" and not pressedAgain and since > 0.3 then
			t:press("Jump")
			pressedAgain = true
		end
		if pressedAgain and since > 0.38 and t.jumpHeld then
			t:release("Jump")
		end
		t.humanoid:Move(keys, false)
		maxY = math.max(maxY, t.root.Position.Y)
		t:frame()
	end
	t:stop()
	t:grounded(4)
	return t.hop:GetTotalHops() - before, maxY - startY, t.root.Position.Z - startZ
end

local function ensureAlley(t: Context)
	if Workspace:FindFirstChild("WallHopAlley") then
		return
	end
	for _, x in { ALLEY_LEFT_X, ALLEY_RIGHT_X } do
		t:block("AlleyWall", Vector3.new(2, 30, 64), CFrame.new(x, 15, 60))
	end
end

local function alternates(sides: string): boolean
	for i = 2, #sides do
		if string.sub(sides, i, i) == string.sub(sides, i - 1, i - 1) then
			return false
		end
	end
	return #sides > 0
end

-- Zig-zag across the alley with Space held. switchAt: seconds after a hop starts to turn the keys
-- toward the other wall (negative = that long AFTER the kick). Returns (hops, walls in order, rise).
local function zigzag(t: Context, switchAt: number): (number, string, number)
	local toRight, toLeft = Vector3.new(1, 0, 1).Unit, Vector3.new(-1, 0, 1).Unit
	t:teleport(Vector3.new(109, 4, 32), Vector3.zAxis)
	t:aimCamera(Vector3.zAxis)
	t:frame()
	local before = t.hop:GetTotalHops()
	local startY = t.root.Position.Y
	local maxY = startY
	local sides, keys, seen = "", toRight, 0
	local hopAt, kickAt, wasRunning = 0, 0, false
	t:press("Jump")
	local t0 = os.clock()
	while os.clock() - t0 < 4 do
		local now = os.clock()
		local total = t.hop:GetTotalHops() - before
		local onWall = t.hop:IsRunning()
		if total > seen then
			seen = total
			hopAt = now
			sides ..= if t.root.Position.X > (ALLEY_LEFT_X + ALLEY_RIGHT_X) / 2 then "R" else "L"
		end
		if wasRunning and not onWall then
			kickAt = now
		end
		wasRunning = onWall
		local side = string.sub(sides, -1)
		local away = if side == "R" then toLeft elseif side == "L" then toRight else keys
		if keys ~= away then
			local ready = if switchAt >= 0
				then now - hopAt >= switchAt
				else (not onWall and kickAt > hopAt and now - kickAt >= -switchAt)
			if ready then
				keys = away
			end
		end
		t.humanoid:Move(keys, false)
		maxY = math.max(maxY, t.root.Position.Y)
		if t.motor:GetMode() == "Ground" and now - t0 > 0.5 then
			break
		end
		t:frame()
	end
	t:stop()
	t:grounded(5)
	return t.hop:GetTotalHops() - before, sides, maxY - startY
end

local tests: { Harness.Test } = {
	{
		name = "When a hop happens",
		run = function(t)
			local hops, rise, along = attempt(t, "hold", INTO, 1.6)
			t:check("jump + HOLD Space into and along the wall hops", hops >= 1 and rise > Config.JumpHeight + 2,
				string.format("%d hop(s), rose %.1f, moved %.1f along", hops, rise, along))
			local pressed, pressRise = attempt(t, "airpress", INTO, 1.6)
			t:check("jump, then PRESS Space in the air hops once", pressed == 1 and pressRise > Config.JumpHeight + 2,
				string.format("%d hop(s), rose %.1f", pressed, pressRise))
			local backHops, _, backAlong = attempt(t, "hold", Vector3.new(1, 0, -1).Unit, 1.2, nil, -Vector3.zAxis)
			t:check("the hop goes the way the keys point", backHops >= 1 and backAlong < -3,
				string.format("%d hop(s), moved %.1f along Z (want negative)", backHops, backAlong))
		end,
	},
	{
		name = "When a hop must not happen",
		run = function(t)
			local tapped = attempt(t, "tap", INTO, 1.2)
			t:check("a tap jump into the wall", tapped == 0, string.format("%d hop(s): %s", tapped, t.hop:GetLastFailure()))
			local wOnly = attempt(t, "hold", INTO, 1.2, nil, INTO)
			t:check("W alone at an angle to the wall", wOnly == 0, string.format("%d hop(s): %s", wOnly, t.hop:GetLastFailure()))
			t:check("running parallel", attempt(t, "hold", Vector3.zAxis, 1.2) == 0)
			t:check("running straight in", attempt(t, "hold", Vector3.xAxis, 1.2) == 0)
			t:check("moving away", attempt(t, "hold", -Vector3.xAxis, 1.2) == 0)
			local atEnd = attempt(t, "hold", INTO, 0.5, Vector3.new(30, 4, 78.5))
			t:check("at the very end of the wall", atEnd == 0, string.format("%d hop(s): %s", atEnd, t.hop:GetLastFailure()))
		end,
	},
	{
		name = "Hops by health, chaining up one wall",
		run = function(t)
			local counts = {}
			for _, share in { 1, 0.5, 0.2 } do
				t:setHealth(share)
				table.insert(counts, t.hop:GetMaxHops())
			end
			t:setHealth(1)
			t:check("hops at 100% / 50% / 20% HP",
				counts[1] == Config.WallHopsHigh and counts[2] == Config.WallHopsMid and counts[3] == Config.WallHopsLow,
				string.format("%d / %d / %d", counts[1], counts[2], counts[3]))
			local chained, chainRise = attempt(t, "hold", INTO, 3)
			t:check("chain hops up one wall", chained >= 2 and chained <= Config.WallHopsHigh,
				string.format("%d hops (max %d), highest +%.1f", chained, Config.WallHopsHigh, chainRise))
		end,
	},
	{
		name = "Zig-zag across an alley",
		run = function(t)
			ensureAlley(t)
			-- Three hops carry you ~65 studs along and ~34 up: taller, longer walls for this test.
			for _, x in { ALLEY_LEFT_X, ALLEY_RIGHT_X } do
				t:block("AlleyTestExtension", Vector3.new(2, 60, 112), CFrame.new(x, 30, 84))
			end
			local cases = {
				{ label = "switch keys mid-run (leap)", switchAt = 0.08 },
				{ label = "switch keys 0.1 s after the kick", switchAt = -0.1 },
				{ label = "switch keys right at the kick", switchAt = Config.WallRunTime + 0.02 },
			}
			for _, case in cases do
				local hops, sides, rise = zigzag(t, case.switchAt)
				t:check(case.label, hops == Config.WallHopsHigh and alternates(sides),
					string.format("%d hops, walls %s, highest +%.1f", hops, sides, rise))
			end
		end,
	},
}

return {
	name = "WallHop",
	description = "When hops happen and don't, health, chaining, zig-zag",
	tests = tests,
}
