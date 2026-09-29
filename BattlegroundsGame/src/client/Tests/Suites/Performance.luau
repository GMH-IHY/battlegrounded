--!strict
-- Performance suite: frame times and each movement system's cost per frame (Perf) while standing,
-- sprinting in the open, sprinting along a wall, pressed against a too-tall ledge (parkour keeps
-- checking) and whipping the camera around. Fails if movement scripts cost more than
-- SCRIPT_BUDGET_MS per frame; the numbers are in the test's log either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Harness = require(script.Parent.Parent.Harness)
local Perf = require(ReplicatedStorage.Movement.Perf)

type Context = Harness.Context

local SCRIPT_BUDGET_MS = 1.0

local function scenario(t: Context, name: string, duration: number, start: Vector3?, facing: Vector3?, keys: Vector3?, sprint: boolean, each: ((number) -> ())?)
	if start and facing then
		t:teleport(start, facing)
		t:wait(0.3)
	end
	local frames: { number } = {}
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		table.insert(frames, dt)
		if each then
			each(dt)
		end
	end)
	Perf.reset()
	Perf.enabled = true
	t:waitFor(function()
		return false
	end, duration, function()
		if keys then
			t:move(keys, sprint)
		end
	end)
	Perf.enabled = false
	connection:Disconnect()
	t:stop()
	local totals, counts = Perf.snapshot()
	local n = math.max(#frames, 1)
	table.sort(frames)
	local sum = 0
	for _, dt in frames do
		sum += dt
	end
	local scriptTotal = 0
	local parts = {}
	for system, seconds in totals do
		scriptTotal += seconds
		table.insert(parts, string.format("%s %.3f", system, seconds * 1000 / n))
	end
	table.sort(parts)
	local perFrame = scriptTotal * 1000 / n
	t:log(string.format("%s: %.0f fps avg, 95%% under %.1f ms, worst %.1f ms; parkour rays %.0f/frame",
		name, n / math.max(sum, 1e-6), (frames[math.max(1, math.floor(n * 0.95))] or 0) * 1000, (frames[n] or 0) * 1000,
		(counts["AutoParkour rays"] or 0) / n))
	t:log("  " .. table.concat(parts, ", "))
	t:check(name .. ": movement scripts under budget", perFrame <= SCRIPT_BUDGET_MS,
		string.format("%.3f ms/frame (budget %.1f)", perFrame, SCRIPT_BUDGET_MS))
end

local tests: { Harness.Test } = {
	{
		name = "Movement script cost per frame",
		run = function(t)
			scenario(t, "standing still", 2, Vector3.new(0, 4, -40), -Vector3.zAxis, nil, false)
			scenario(t, "sprinting in the open", 2, Vector3.new(0, 4, -20), -Vector3.zAxis, -Vector3.zAxis, true)
			local along = Vector3.new(math.sin(math.rad(20)), 0, math.cos(math.rad(20)))
			scenario(t, "sprinting along a wall", 1.6, Vector3.new(31.5, 4, 34), Vector3.zAxis, along, true)
			scenario(t, "pressed against a too-tall ledge", 2, Vector3.new(-30, 4, 60), Vector3.zAxis, Vector3.zAxis, true)
			t:teleport(Vector3.new(-100, 4, -100), Vector3.zAxis)
			t.camera.CameraType = Enum.CameraType.Scriptable
			local elapsed, lastFlick = 0, 0
			scenario(t, "whipping the camera around", 2, nil, nil, Vector3.zAxis, true, function(dt: number)
				elapsed += dt
				local turn = math.rad(180) * dt
				if elapsed - lastFlick >= 0.25 then
					lastFlick = elapsed
					turn += math.rad(120)
				end
				local c = t.camera.CFrame
				t.camera.CFrame = CFrame.new(c.Position) * CFrame.Angles(0, turn, 0) * c.Rotation
			end)
		end,
	},
}

return {
	name = "Performance",
	description = "Frame times and movement script cost per frame",
	tests = tests,
}
