--!strict
-- Dash suite: the four directions and their distances, dashing into obstacles never launching you,
-- and the cooldown. (A front dash's M1, the lunge, is in the Attacks suite.) Keys go through
-- Controls (Shift) with the camera aimed like a player's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local LANE = Vector3.new(60, 4, -40)
local FORWARD = Vector3.zAxis
local RIGHT = Vector3.new(-1, 0, 0) -- right of a character looking +Z

-- Dashes from a standstill at `position` looking along `look`, holding `keys` (world direction).
-- Returns (started, flat movement, animations seen).
local function trial(t: Context, position: Vector3, look: Vector3, keys: Vector3): (boolean, Vector3, { [string]: boolean })
	t:teleport(position, look)
	t:aimCamera(look)
	t:waitDashReady()
	t.humanoid:Move(keys, false)
	t:frame()
	local start = t.root.Position
	t:press("Dash")
	local started = t.dash:IsBusy()
	local seen: { [string]: boolean } = {}
	local animator = t.humanoid:FindFirstChildOfClass("Animator")
	local t0 = os.clock()
	while os.clock() - t0 < 1.3 do
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				seen[if track.Animation then track.Animation.Name else "?"] = true
			end
		end
		t:frame()
	end
	t:stop()
	return started, (t.root.Position - start) * Vector3.new(1, 0, 1), seen
end

type Case = { name: string, keys: Vector3, want: number, anim: string, axis: Vector3 }
local CASES: { Case } = {
	{ name = "no keys -> front", keys = Vector3.zero, want = Config.FrontDashDistance, anim = "DashForward", axis = FORWARD },
	{ name = "W -> front", keys = FORWARD, want = Config.FrontDashDistance, anim = "DashForward", axis = FORWARD },
	{ name = "D -> right", keys = RIGHT, want = Config.SideDashDistance, anim = "DashRight", axis = RIGHT },
	{ name = "A -> left", keys = -RIGHT, want = Config.SideDashDistance, anim = "DashLeft", axis = -RIGHT },
	{ name = "S -> back", keys = -FORWARD, want = Config.SideDashDistance, anim = "DashBack", axis = -FORWARD },
	{ name = "W+A -> front", keys = (FORWARD - RIGHT).Unit, want = Config.FrontDashDistance, anim = "DashForward", axis = FORWARD },
	{ name = "S+D -> back", keys = (-FORWARD + RIGHT).Unit, want = Config.SideDashDistance, anim = "DashBack", axis = -FORWARD },
}

local tests: { Harness.Test } = {
	{
		name = "Directions, distances and animations",
		run = function(t)
			for _, case in CASES do
				local started, moved, seen = trial(t, LANE, FORWARD, case.keys)
				local distance = t.dash:GetLastDistance()
				local off = if moved.Magnitude > 0.1
					then math.deg(math.acos(math.clamp(moved.Unit:Dot(case.axis), -1, 1)))
					else 180
				t:check(case.name, started and math.abs(distance - case.want) <= 1 and seen[case.anim] == true and off < 4,
					string.format("%.2f studs (want %.1f), anim %s, %.1f deg off its axis", distance, case.want,
						if seen[case.anim] then "ok" else "MISSING", off))
			end
		end,
	},
	{
		name = "Dashing into obstacles never launches you",
		run = function(t)
			type Obstacle = { name: string, from: Vector3, look: Vector3, keys: Vector3, maxRise: number }
			local obstacles: { Obstacle } = {
				{ name = "vault box (vaults it)", from = Vector3.new(0, 4, 30), look = FORWARD, keys = Vector3.zero, maxRise = 3 + 1.2 },
				{ name = "jump box (steps up)", from = Vector3.new(-30, 4, 24), look = FORWARD, keys = Vector3.zero, maxRise = 4 + 1.2 },
				{ name = "tall wall", from = Vector3.new(22, 4, 56), look = Vector3.xAxis, keys = Vector3.zero, maxRise = 1.2 },
				{ name = "tall wall, diagonal", from = Vector3.new(24, 4, 46), look = Vector3.new(1, 0, 1).Unit, keys = Vector3.zero, maxRise = 1.2 },
				{ name = "vault box, side dash", from = Vector3.new(-12, 4, 40), look = -FORWARD, keys = Vector3.xAxis, maxRise = 1.2 },
			}
			for _, obstacle in obstacles do
				t:teleport(obstacle.from, obstacle.look)
				t:aimCamera(obstacle.look)
				t:waitDashReady()
				t.humanoid:Move(obstacle.keys, false)
				t:frame()
				local startY = t.root.Position.Y
				local maxY = startY
				t:press("Dash")
				-- Watch the highest point for a second (the condition never ends it early).
				t:waitFor(function()
					return false
				end, 1, function()
					maxY = math.max(maxY, t.root.Position.Y)
				end)
				t:check(obstacle.name, maxY - startY < obstacle.maxRise,
					string.format("rose %.2f (max %.1f), dash ended: %s", maxY - startY, obstacle.maxRise, t.dash:GetLastEndReason()))
				t:stop()
			end
		end,
	},
	{
		name = "Cooldown",
		run = function(t)
			t:teleport(LANE, FORWARD)
			t:aimCamera(FORWARD)
			t:waitDashReady()
			t:press("Dash")
			local first = t.dash:IsBusy()
			t:wait(Config.DashCooldown - 0.3)
			local early = t.dash:Request()
			t:wait(0.35)
			local after = t.dash:Request()
			t:check("one dash, then the cooldown", first and not early and after,
				string.format("first %s, at %.1fs %s, at %.1fs %s", tostring(first), Config.DashCooldown - 0.3,
					tostring(early), Config.DashCooldown + 0.05, tostring(after)))
		end,
	},
}

return {
	name = "Dash",
	description = "Directions, distances, obstacles, cooldown",
	tests = tests,
}
