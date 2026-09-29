--!strict
-- Basics suite: walking and running speeds, exact jump heights, walls never holding you up, the
-- jump box and 9-stud ledge, fall gravity and terminal velocity, and speeds by health.
-- Uses the MovementTestCourse (tall wall x 33..35, z 32..80; blue jump box x -38..-22, z 32..48,
-- 4 high; red ledge 9 high at z 64..80) and open baseplate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local OPEN_AREA = Vector3.new(140, 4, -140)
local TOLERANCE = 0.35

local function spreadOk(values: { number }, want: number): boolean
	for _, v in values do
		if math.abs(v - want) > TOLERANCE then
			return false
		end
	end
	return #values > 0
end

local function list(values: { number }): string
	local parts = {}
	for _, v in values do
		table.insert(parts, string.format("%.2f", v))
	end
	return table.concat(parts, " ")
end

local function jumpHeights(t: Context, direction: Vector3, sprint: boolean, count: number): { number }
	t:teleport(OPEN_AREA, Vector3.zAxis)
	t:move(direction, sprint)
	t:wait(if sprint then 0.6 else 0.2)
	local heights = {}
	for _ = 1, count do
		table.insert(heights, t:jumpOnce().height)
		t:wait(0.15) -- let the Humanoid settle so every jump starts from the ground
	end
	return heights
end

-- Tall wall: jump into it. It must never hold you up in the air.
local function wallCase(t: Context, direction: Vector3, sprint: boolean, pushFirst: boolean)
	local start = Vector3.new(33 - 10 * direction.X, 4, 56 - 10 * direction.Z)
	t:teleport(start, direction)
	t:move(direction, sprint)
	t:wait(if pushFirst then 1 else 0.15)
	local stats = t:jumpOnce(4)
	t:check("never held up by the wall", stats.hang < 0.1 and stats.airtime < 1.2,
		string.format("airtime %.2fs, hanging %.2fs", stats.airtime, stats.hang))
end

local function speedScaleAt(share: number): number
	local full = math.clamp(Config.HealthSpeedFullAbove, 1e-3, 1)
	return Config.LowHealthSpeedScale + (1 - Config.LowHealthSpeedScale) * math.clamp(share / full, 0, 1)
end

-- Average ground speed over the last `measure` seconds of moving +Z for `total` seconds.
local function moveFor(t: Context, sprint: boolean, total: number, measure: number): number
	local sum, count = 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < total do
		t:move(Vector3.zAxis, sprint)
		if os.clock() - t0 > total - measure and t.motor:GetMode() == "Ground" then
			sum += t:flatSpeed()
			count += 1
		end
		t:frame()
	end
	return if count > 0 then sum / count else 0
end

local tests: { Harness.Test } = {
	{
		name = "Walk and run speeds",
		run = function(t)
			t:teleport(OPEN_AREA, Vector3.zAxis)
			t:move(Vector3.zAxis, false)
			t:wait(0.8)
			t:near("walk speed", t.motor:GetHorizontalSpeed(), Config.WalkSpeed, 0.5)
			local start = os.clock()
			t:move(Vector3.zAxis, true)
			local reached = t:waitFor(function()
				return t.motor:GetHorizontalSpeed() >= Config.RunSpeed - 0.5
			end, 2)
			local ramp = os.clock() - start
			t:wait(0.5)
			t:check("run speed reached", reached, string.format("in %.2fs (want ~%.2f)", ramp, Config.RunAccelTime))
			t:near("run speed", t.motor:GetHorizontalSpeed(), Config.RunSpeed, 0.5)
		end,
	},
	{
		name = "Jump heights are exact (standing, walking, running, held)",
		run = function(t)
			local want = Config.JumpHeight
			local standing = jumpHeights(t, Vector3.zero, false, 4)
			t:check("standing", spreadOk(standing, want), list(standing))
			local walking = jumpHeights(t, Vector3.zAxis, false, 4)
			t:check("walking", spreadOk(walking, want), list(walking))
			local running = jumpHeights(t, Vector3.zAxis, true, 4)
			t:check("running", spreadOk(running, want), list(running))
			-- Held: the Humanoid re-jumps on every landing.
			t:teleport(OPEN_AREA, Vector3.zAxis)
			t:move(Vector3.zAxis, true)
			t:wait(0.6)
			t:press("Jump")
			local groundY = t.root.Position.Y
			local heights: { number } = {}
			local maxY, wasAir = groundY, false
			t:waitFor(function()
				return #heights >= 5
			end, 8, function()
				local inAir = t.motor:GetMode() == "Air"
				if inAir then
					maxY = math.max(maxY, t.root.Position.Y)
				elseif wasAir then
					table.insert(heights, maxY - groundY)
					maxY = groundY
				end
				wasAir = inAir
			end)
			t:release("Jump")
			t:check("held Space", #heights >= 5 and spreadOk(heights, want), list(heights))
		end,
	},
	{
		name = "Walls never hold you up",
		run = function(t)
			wallCase(t, Vector3.xAxis, true, false)
			wallCase(t, Vector3.xAxis, true, true)
			wallCase(t, Vector3.new(1, 0, 1).Unit, true, false)
			wallCase(t, Vector3.xAxis, false, false)
		end,
	},
	{
		name = "4-stud box reachable, 9-stud ledge grabbed without a fling",
		run = function(t)
			t:teleport(Vector3.new(-30, 4, 22), Vector3.zAxis)
			t:move(Vector3.zAxis, false)
			t:wait(0.3)
			t:jumpOnce(2)
			t:wait(0.3)
			t:check("on the 4-stud box", t.root.Position.Y > 6, string.format("ended at y %.1f", t.root.Position.Y))

			t:teleport(Vector3.new(-30, 4, 52), Vector3.zAxis)
			t:move(Vector3.zAxis, false)
			local highest = 0
			local t0 = os.clock()
			while os.clock() - t0 < 4 do
				local stats = t:jumpOnce(2)
				highest = math.max(highest, stats.maxY)
			end
			-- Standing on the ledge puts the root at 12; one more jump from there peaks at 19.2.
			t:check("scaled the 9-stud ledge", highest > 11.5, string.format("highest %.1f", highest))
			t:check("no fling", highest <= 12 + Config.JumpHeight + 0.6, string.format("highest %.1f", highest))
		end,
	},
	{
		name = "Fall gravity ramps up and caps at terminal velocity",
		run = function(t)
			t:stop()
			t.root.AssemblyLinearVelocity = Vector3.zero
			t.root.CFrame = CFrame.new(OPEN_AREA + Vector3.new(0, 300, 0))
			task.wait(0.1)
			local v1, t1 = t.root.AssemblyLinearVelocity.Y, os.clock()
			task.wait(0.2)
			local v2, t2 = t.root.AssemblyLinearVelocity.Y, os.clock()
			local measured = (v1 - v2) / (t2 - t1) / Workspace.Gravity
			local rampTime = math.max(Config.FallGravityRampTime, 1e-3)
			local function ramp(x: number): number
				return 1 + (Config.FallGravityMax - 1) * math.clamp(x / rampTime, 0, 1)
			end
			local expected = (ramp(0.1) + ramp(0.2) * 2 + ramp(0.3)) / 4
			t:near("gravity while ramping (x normal)", measured, expected, 0.15)
			local maxFall = 0
			t:waitFor(function()
				return t.motor:GetMode() ~= "Air"
			end, 8, function()
				maxFall = math.max(maxFall, -t.root.AssemblyLinearVelocity.Y)
			end)
			t:check("terminal velocity", maxFall <= Config.TerminalVelocity + 0.5 and maxFall >= Config.TerminalVelocity - 1,
				string.format("max fall %.2f (want %d)", maxFall, Config.TerminalVelocity))
		end,
	},
	{
		name = "Speeds scale with health",
		run = function(t)
			for _, share in { 1, 0.5, 0.1 } do
				local scale = speedScaleAt(share)
				t:setHealth(share)
				t:teleport(Vector3.new(-100, 4, -160), Vector3.zAxis)
				local walk = moveFor(t, false, 1.0, 0.4)
				t:stop()
				t:teleport(Vector3.new(-110, 4, -160), Vector3.zAxis)
				local run = moveFor(t, true, 1.4, 0.5)
				local jump = t:jumpOnce()
				t:stop()
				local label = string.format("%d%% HP", share * 100)
				t:near(label .. " walk", walk, Config.WalkSpeed * scale, 0.6)
				t:near(label .. " run", run, Config.RunSpeed * scale, 1)
				t:check(label .. " never faster in the air", jump.peakSpeed < Config.RunSpeed * scale + 1,
					string.format("air peak %.1f", jump.peakSpeed))
			end
			t:setHealth(1)
			t:teleport(Vector3.new(-130, 4, -160), Vector3.zAxis)
			moveFor(t, true, 1.2, 0.2)
			t:setHealth(0.1)
			local settled = moveFor(t, true, 0.6, 0.2)
			t:near("hit mid-run slows to the new run speed", settled, Config.RunSpeed * speedScaleAt(0.1), 1)
			t:setHealth(1)
			t:near("healing speeds back up", moveFor(t, true, 0.8, 0.2), Config.RunSpeed, 1)
		end,
	},
}

return {
	name = "Basics",
	description = "Speeds, jump heights, walls, ledges, falling, health speeds",
	tests = tests,
}
