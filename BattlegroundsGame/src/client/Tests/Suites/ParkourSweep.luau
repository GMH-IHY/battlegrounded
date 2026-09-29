--!strict
-- Parkour sweep (slow, ~3 minutes): many approaches at four obstacles (the 9-stud ledge, a 6-stud
-- ledge, the JumpBox, the VaultBox): straight, angled, strafing along the face, strafe-then-turn,
-- jumping at it, walking diagonally, the corner point from the front and the side; each at the
-- middle, near the corner and past it. Only runs that end BAD fail: hanging in the air, inside
-- geometry, flung, or retrying in a loop. Every run's outcome is in the test's log.

local Workspace = game:GetService("Workspace")

local Harness = require(script.Parent.Parent.Harness)

type Context = Harness.Context

type Target = { name: string, faceZ: number, xMin: number, xMax: number, top: number }
local TARGETS: { Target } = {
	{ name = "9-high", faceZ = 64, xMin = -38, xMax = -22, top = 9 },
	{ name = "6-high", faceZ = -66, xMin = -86, xMax = -74, top = 6 },
	{ name = "4-box", faceZ = 32, xMin = -38, xMax = -22, top = 4 },
	{ name = "vault-box", faceZ = 39, xMin = -6, xMax = 6, top = 3 },
}

local function dir(degrees: number): Vector3
	local r = math.rad(degrees)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

type Segment = { t: number, keys: Vector3, sprint: boolean, jump: boolean? }
type Style = { name: string, back: number, segments: { Segment }, vertex: string? }
local STYLES: { Style } = {
	{ name = "sprint straight", back = 12, segments = { { t = 1.6, keys = dir(0), sprint = true } } },
	{ name = "sprint 40deg", back = 12, segments = { { t = 1.6, keys = dir(40), sprint = true } } },
	{ name = "strafe along face (W+D)", back = 1.2, segments = { { t = 1.6, keys = dir(55), sprint = true } } },
	{ name = "strafe then turn in", back = 1.2, segments = { { t = 0.6, keys = dir(88), sprint = true }, { t = 1.0, keys = dir(30), sprint = true } } },
	{ name = "jump at it", back = 6, segments = { { t = 0.12, keys = dir(0), sprint = false }, { t = 1.6, keys = dir(0), sprint = false, jump = true } } },
	{ name = "walk diagonal", back = 3, segments = { { t = 1.6, keys = dir(45), sprint = false } } },
	{ name = "corner point from the front", back = 7, vertex = "inside", segments = { { t = 1.4, keys = dir(45), sprint = true } } },
	{ name = "corner point from the side", back = 7, vertex = "outside", segments = { { t = 1.4, keys = dir(-45), sprint = true } } },
}

local function parkourCount(t: Context): number
	local n = 0
	for _, name in { "Vault", "StepUp", "Climb", "Slide" } do
		n += t.parkour:GetCount(name)
	end
	return n
end

local function sweep(t: Context, target: Target)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { t.character }
	overlap.RespectCanCollide = true
	local bad, runs = 0, 0
	for _, style in STYLES do
		local offsets = {
			{ label = "middle", x = (target.xMin + target.xMax) / 2 },
			{ label = "near corner", x = target.xMax - 0.6 },
			{ label = "past corner", x = target.xMax + 0.8 },
		}
		for _, offset in offsets do
			local label, x = offset.label, offset.x
			if style.vertex and label ~= "middle" then
				continue
			end
			runs += 1
			local start = Vector3.new(x, 4, target.faceZ - style.back)
			if style.vertex == "inside" then
				start = Vector3.new(target.xMax - style.back, 4, target.faceZ - style.back)
			elseif style.vertex == "outside" then
				start = Vector3.new(target.xMax + style.back, 4, target.faceZ - style.back)
			end
			t:teleport(start, Vector3.zAxis)
			local before = parkourCount(t)
			local maxY = t.root.Position.Y
			local hang = 0
			for _, segment in style.segments do
				if segment.jump then
					t:press("Jump")
				end
				local t0 = os.clock()
				while os.clock() - t0 < segment.t do
					t:move(segment.keys, segment.sprint)
					if segment.jump and t.jumpHeld and os.clock() - t0 > 0.05 then
						t:release("Jump")
					end
					maxY = math.max(maxY, t.root.Position.Y)
					if t.motor:GetMode() == "Air" and t.root.AssemblyLinearVelocity.Magnitude < 0.8 then
						hang += 1 / 60
					end
					t:frame()
				end
			end
			t:stop()
			t:wait(0.6)
			local actions = parkourCount(t) - before
			local info = t.parkour:GetLastInfo()
			local problems: { string } = {}
			if actions > 1 and (string.find(info, "blocked") or string.find(info, "snagged")) then
				table.insert(problems, string.format("%d moves, retrying (%s)", actions, info))
			elseif actions > 0 and (string.find(info, "blocked") or string.find(info, "snagged")) then
				table.insert(problems, "move got " .. info)
			end
			if t.motor:GetMode() ~= "Ground" then
				table.insert(problems, "not on the ground after (" .. t.motor:GetMode() .. ")")
			end
			if hang > 0.3 then
				table.insert(problems, string.format("hung in the air %.1fs", hang))
			end
			if #Workspace:GetPartBoundsInBox(t.root.CFrame, Vector3.new(1.2, 1.6, 0.6), overlap) > 0 then
				table.insert(problems, "root inside geometry")
			end
			if maxY > target.top + 3 + 8 then
				table.insert(problems, string.format("flung to y %.1f", maxY))
			end
			local outcome = if actions == 0 then "none" else string.format("%d move(s), %s", actions, info)
			if #problems > 0 then
				bad += 1
				t:check(string.format("%s / %s", style.name, label), false, table.concat(problems, "; ") .. " (" .. outcome .. ")")
			else
				t:log(string.format("ok %s / %s: %s", style.name, label, outcome))
			end
		end
	end
	t:check(string.format("%d runs, none stuck / hanging / flung / looping", runs), bad == 0, string.format("%d bad", bad))
end

local tests: { Harness.Test } = {}
for _, target in TARGETS do
	table.insert(tests, {
		name = target.name,
		run = function(t: Context)
			if target.name == "6-high" then
				t:block("ParkourTestLedge", Vector3.new(12, 6, 12), CFrame.new(-80, 3, -60))
			end
			sweep(t, target)
		end,
	})
end

return {
	name = "ParkourSweep",
	description = "Slow: edge-case approaches at four obstacles",
	tests = tests,
}
