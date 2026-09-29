--!strict
-- LanternPhysics (ModuleScript)
-- Location: ReplicatedStorage > Movement > LanternPhysics
--
-- The thrown lantern's flight, shared by everything that needs it so they always agree:
--   * the owner's throw preview (dots + ring) and the real throw (Lantern.luau) run the SAME fixed
--     steps, so the lantern lands where the ring is (unless someone walks into it);
--   * other players' clients (LanternViewer) replay the same arc from the throw's start values;
--   * the server uses the same numbers to check reports.
-- The flight is a plain projectile: launch velocity + constant gravity (Workspace.Gravity x
-- LanternThrowGravity). Positions are exact for constant gravity, so the step size only decides how
-- often we check for collisions, not where the lantern is.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)

local LanternPhysics = {}

LanternPhysics.STEP = 1 / 60
-- World collision size (radius) and how close to a character counts as a hit (radius, generous so
-- moving / jumping targets are fair to hit).
LanternPhysics.WORLD_RADIUS = 0.45
LanternPhysics.CHARACTER_RADIUS = 1.1

export type Hit = {
	kind: "World" | "Character",
	position: Vector3, -- where the lantern's centre is at the moment of contact
	normal: Vector3,
	instance: Instance,
	character: Model?,
}

function LanternPhysics.gravity(): number
	return Workspace.Gravity * Config.LanternThrowGravity
end

-- Position / velocity `t` seconds after launch.
function LanternPhysics.at(origin: Vector3, velocity: Vector3, gravity: number, t: number): (Vector3, Vector3)
	local pos = origin + velocity * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
	local vel = velocity - Vector3.new(0, gravity * t, 0)
	return pos, vel
end

-- Launch velocity with `speed` that passes through `target` (the flatter of the two arcs). If the
-- target is out of reach at that speed, throws at the angle that gets closest (max range toward it).
function LanternPhysics.solve(from: Vector3, target: Vector3, speed: number, gravity: number): Vector3
	local delta = target - from
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local dx = flat.Magnitude
	local dy = delta.Y
	if dx < 1e-3 then
		-- Straight up / down.
		return Vector3.new(0, if dy >= 0 then speed else -speed, 0)
	end
	local dir = flat / dx
	local v2 = speed * speed
	local disc = v2 * v2 - gravity * (gravity * dx * dx + 2 * dy * v2)
	local angle: number
	if disc >= 0 then
		angle = math.atan((v2 - math.sqrt(disc)) / (gravity * dx))
	else
		-- Out of reach: the max-range angle for a target at this slope.
		angle = math.pi / 4 + math.atan2(dy, dx) / 2
	end
	return dir * (speed * math.cos(angle)) + Vector3.new(0, speed * math.sin(angle), 0)
end

-- Every living character except `owner` (players and NPC dummies). Used as the Include list for
-- character hits and the Exclude list for world hits.
function LanternPhysics.characters(owner: Model?): { Model }
	local list: { Model } = {}
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local c = player.Character
		if c and c ~= owner and c.Parent then
			seen[c] = true
			table.insert(list, c)
		end
	end
	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child ~= owner and not seen[child] then
			local humanoid = child:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and child:FindFirstChild("HumanoidRootPart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

export type Casts = {
	world: RaycastParams,
	characters: RaycastParams?,
}

-- Cast params for a flight: the world (collidable parts only; characters, the owner and `extra`
-- ignored) and, if `hitCharacters`, the other characters.
function LanternPhysics.params(owner: Model?, extra: { Instance }?, hitCharacters: boolean): Casts
	local others = LanternPhysics.characters(owner)
	local ignore: { Instance } = {}
	if owner then
		table.insert(ignore, owner)
	end
	for _, c in others do
		table.insert(ignore, c)
	end
	if extra then
		for _, e in extra do
			table.insert(ignore, e)
		end
	end
	local world = RaycastParams.new()
	world.FilterType = Enum.RaycastFilterType.Exclude
	world.FilterDescendantsInstances = ignore
	world.RespectCanCollide = true
	local chars: RaycastParams? = nil
	if hitCharacters and #others > 0 then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		local include: { Instance } = {}
		for _, c in others do
			table.insert(include, c)
		end
		p.FilterDescendantsInstances = include
		p.RespectCanCollide = false
		chars = p
	end
	return { world = world, characters = chars }
end

local function characterOf(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end
LanternPhysics.characterOf = characterOf

-- What the lantern runs into moving from `from` by `delta` (nil = nothing). A living character that's
-- reached first wins over the world.
function LanternPhysics.cast(from: Vector3, delta: Vector3, casts: Casts): Hit?
	if delta.Magnitude < 1e-5 then
		return nil
	end
	local best: Hit? = nil
	local bestDist = math.huge
	local w = Workspace:Spherecast(from, LanternPhysics.WORLD_RADIUS, delta, casts.world)
	if w then
		bestDist = w.Distance
		best = {
			kind = "World",
			position = from + delta.Unit * w.Distance,
			normal = w.Normal,
			instance = w.Instance,
			character = nil,
		}
	end
	if casts.characters then
		local c = Workspace:Spherecast(from, LanternPhysics.CHARACTER_RADIUS, delta, casts.characters)
		if c and c.Distance <= bestDist then
			local who = characterOf(c.Instance)
			local humanoid = if who then who:FindFirstChildOfClass("Humanoid") else nil
			if who and humanoid and humanoid.Health > 0 then
				best = {
					kind = "Character",
					position = from + delta.Unit * c.Distance,
					normal = c.Normal,
					instance = c.Instance,
					character = who,
				}
			end
		end
	end
	return best
end

-- The whole predicted flight (for the preview): points every step until it hits something or
-- `maxTime` runs out. Returns (points, hit?).
function LanternPhysics.predict(
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	casts: Casts,
	maxTime: number
): ({ Vector3 }, Hit?)
	local points = { origin }
	local step = LanternPhysics.STEP
	local prev = origin
	local t = 0
	while t < maxTime do
		t += step
		local pos = LanternPhysics.at(origin, velocity, gravity, t)
		local hit = LanternPhysics.cast(prev, pos - prev, casts)
		if hit then
			table.insert(points, hit.position)
			return points, hit
		end
		table.insert(points, pos)
		prev = pos
	end
	return points, nil
end

-- True if nothing solid is between `a` and `b` (characters and `ignore` don't block).
function LanternPhysics.clearLine(a: Vector3, b: Vector3, casts: Casts): boolean
	return Workspace:Raycast(a, b - a, casts.world) == nil
end

return LanternPhysics
