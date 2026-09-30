--!strict
-- Projectiles (ModuleScript)
-- Location: ServerScriptService > Combat > Projectiles
--
-- Shots that fly on their own once a move fires them (Move.Projectile): the Lotus spores and the
-- stage 2 ground strand. The server moves each one every frame, stops it at walls, and hands any
-- fighter it touches to HitResolver (one target per shot). Clients draw them from two Fx messages
-- (CombatFx): "Projectile" when it's fired (start, direction, speed, range) and "ProjectileEnd".
--
--   Count shots spread evenly over Spread degrees, Speed studs/s, gone after Range studs.
--   Ground = it runs along the floor (following it up and down) and only hits people on the floor
--   or lying on it; it stops where the floor ends.

local Workspace = game:GetService("Workspace")

local Fighter = require(script.Parent:WaitForChild("Fighter"))

type Fighter = Fighter.Fighter

type Shot = {
	id: number,
	owner: Fighter,
	hit: Fighter.Hit,
	position: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	travelled: number,
	radius: number,
	ground: boolean,
}

local Projectiles = {}

local shots: { Shot } = {}
local nextId = 0
local FLOOR_REACH = 8 -- a ground shot looks this far up / down for the floor ahead

local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in { "TrainingDummies", "CombatFx", "MovementFx", "HitboxViewer" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- A ray that ignores characters (they're hit by the overlap check, not stopped at).
local function castWorld(origin: Vector3, direction: Vector3, params: RaycastParams): RaycastResult?
	for _ = 1, 4 do
		local result = Workspace:Raycast(origin, direction, params)
		if not result or not isCharacterPart(result.Instance) then
			return result
		end
		local list = params.FilterDescendantsInstances
		table.insert(list, result.Instance)
		params.FilterDescendantsInstances = list
	end
	return nil
end

-- Fires `run`'s move from `owner`.
function Projectiles.Fire(owner: Fighter, run: Fighter.Run)
	local move = run.move
	local spec = move.Projectile
	if not spec then
		return
	end
	local look = owner.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.zAxis
	local params = worldParams()
	for i = 1, spec.Count do
		local angle = if spec.Count > 1 then -spec.Spread / 2 + spec.Spread * (i - 1) / (spec.Count - 1) else 0
		local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(flatLook)
		local start
		if spec.Ground then
			local floor = castWorld(owner.root.Position + flatLook * 1.5, Vector3.new(0, -FLOOR_REACH, 0), params)
			start = if floor then floor.Position + Vector3.new(0, 0.5, 0) else owner.root.Position - Vector3.new(0, 2.5, 0)
		else
			-- From the left hand, a little out in front.
			start = owner.root.CFrame * Vector3.new(-1, 0.4, -1.5)
		end
		nextId += 1
		local shot: Shot = {
			id = nextId,
			owner = owner,
			hit = {
				move = move,
				seq = run.seq,
				run = nil,
				frame = -1,
				lastActive = true,
				origin = start,
				direction = direction,
				projectile = true,
				followUp = run.followUp,
			},
			position = start,
			direction = direction,
			speed = spec.Speed,
			range = spec.Range,
			travelled = 0,
			radius = spec.Radius,
			ground = spec.Ground,
		}
		table.insert(shots, shot)
		run.projectiles += 1
		owner.hooks.fx({
			type = "Projectile",
			id = shot.id,
			attacker = owner.character,
			move = move.Id,
			position = start,
			direction = direction,
			speed = spec.Speed,
			range = spec.Range,
			ground = spec.Ground,
		})
	end
end

local function finish(index: number, shot: Shot)
	table.remove(shots, index)
	shot.owner:ProjectileDone(shot.hit.seq)
	shot.owner.hooks.fx({ type = "ProjectileEnd", id = shot.id, position = shot.position })
end

-- Wind: every shot inside the box that `by` doesn't own turns to fly where `by` faces (flat), with
-- its range restarted, and becomes `by`'s (it can hit its old owner now).
function Projectiles.Redirect(by: Fighter, cframe: CFrame, size: Vector3)
	local look = by.root.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z)
	direction = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.zAxis
	local half = size / 2
	for _, shot in shots do
		local owner = shot.owner
		if owner ~= by and owner.character ~= by.character then
			local p = cframe:PointToObjectSpace(shot.position)
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y + 1.5 and math.abs(p.Z) <= half.Z then
				owner:ProjectileDone(shot.hit.seq)
				shot.owner = by
				shot.direction = direction
				shot.travelled = 0
				-- Hits now count as the redirector's, with no follow-up bonus and no live move behind them.
				shot.hit = table.clone(shot.hit)
				shot.hit.seq = -shot.id
				shot.hit.followUp = false
				shot.hit.direction = direction
				by.hooks.fx({
					type = "Projectile",
					id = shot.id,
					attacker = by.character,
					move = shot.hit.move.Id,
					position = shot.position,
					direction = direction,
					speed = shot.speed,
					range = shot.range,
					ground = shot.ground,
					redirected = true,
				})
			end
		end
	end
end

-- Every frame.
function Projectiles.Step(dt: number)
	if #shots == 0 then
		return
	end
	local params = worldParams()
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local owner = shot.owner
		local stepLength = math.min(shot.speed * dt, shot.range - shot.travelled)
		local nextPosition = shot.position + shot.direction * stepLength
		local stopped = false
		if shot.ground then
			-- Follow the floor: look for it around the next spot; no floor (or a wall) ends it.
			local floor = castWorld(nextPosition + Vector3.new(0, FLOOR_REACH / 2, 0), Vector3.new(0, -FLOOR_REACH, 0), params)
			if floor then
				nextPosition = floor.Position + Vector3.new(0, 0.5, 0)
			else
				stopped = true
			end
		else
			local wall = castWorld(shot.position, nextPosition - shot.position, params)
			if wall then
				nextPosition = wall.Position
				stopped = true
			end
		end
		shot.travelled += stepLength
		shot.position = nextPosition
		shot.hit.origin = nextPosition

		-- Who it touches.
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		local others: { Instance } = {}
		for _, other in owner.hooks.all() do
			if other.character ~= owner.character and other.humanoid.Health > 0 then
				table.insert(others, other.character)
			end
		end
		overlap.FilterDescendantsInstances = others
		local centre = if shot.ground then nextPosition + Vector3.new(0, 1.5, 0) else nextPosition
		owner.hooks.sweep(owner, CFrame.new(centre), Vector3.one * (shot.radius * 2 + 1), shot.hit.move)
		local done = false
		for _, part in Workspace:GetPartBoundsInRadius(centre, shot.radius + 0.5, overlap) do
			local model = part:FindFirstAncestorOfClass("Model")
			while model and not model:FindFirstChildOfClass("Humanoid") do
				model = model:FindFirstAncestorOfClass("Model")
			end
			local target = if model then owner.hooks.fighterOf(model) else nil
			if target then
				local onFloor = target:Grounded() or target.state == "Downed"
				if not shot.ground or onFloor then
					if owner.hooks.resolve(owner, target, shot.hit) then
						done = true
						break
					end
				end
			end
		end
		if done or stopped or shot.travelled >= shot.range then
			finish(i, shot)
		end
	end
end

return Projectiles
