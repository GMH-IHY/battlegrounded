--!strict
-- LanternViewer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > LanternViewer
--
-- Draws OTHER players' lanterns smoothly while they're out of hand. The server lantern (tag
-- "MothLantern") is only placed at the owner's reports (~20 a second), so here it's hidden and a
-- local copy is drawn instead:
--   Thrown    -> the arc is replayed from the throw's start values (LanternPhysics, same as the
--                owner), so it flies smoothly, up to ThrowStop (where it will hang) or whatever it
--                runs into first.
--   Suspended -> sits at the reported point with its light sphere.
--   Dropped / Returning -> follows the reported point, smoothed.
-- On the hip / in the hand the server lantern (welded to the character) shows as it is.
-- Also plays the flash where it starts hanging (attributes BurstAt / BurstId).
-- Your own lantern is drawn by Lantern.luau, not here.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("LanternFx")
local LanternPhysics = require(ReplicatedStorage.Movement.LanternPhysics)
local LanternFx = require(ReplicatedStorage.Movement.LanternFx)

local player = Players.LocalPlayer
local TAG = "MothLantern"
-- How fast the copy catches up with a reported position (per second, exponential).
local FOLLOW_RATE = 18
-- Farther than this from the report: jump there.
local SNAP_DISTANCE = 25

type View = {
	model: Model,
	copy: Model?,
	state: string,
	position: Vector3,
	velocity: Vector3,
	-- Replayed throw: where the replay is, and whether it ran into something.
	replayPos: Vector3?,
	replayStopped: boolean,
	throwStart: number,
	casts: any,
	castsAt: number,
	lastBurstId: number,
	connections: { RBXScriptConnection },
}

local views: { [Model]: View } = {}

local function isMine(model: Model): boolean
	return model:GetAttribute("OwnerUserId") == player.UserId
end

local function removeCopy(view: View)
	if view.copy then
		view.copy:Destroy()
		view.copy = nil
	end
	LanternFx.hideServer(view.model, false)
end

local function onState(view: View)
	local state = view.model:GetAttribute("State")
	view.state = if typeof(state) == "string" then state else "Hip"
	if view.state == "Hip" or view.state == "Charging" then
		removeCopy(view)
		return
	end
	local core = view.model.PrimaryPart
	if not view.copy then
		view.copy = LanternFx.makeCopy(view.model, "LanternView")
		view.position = if core then core.Position else view.position
	end
	LanternFx.hideServer(view.model, true)
	if view.state == "Thrown" then
		local start = view.model:GetAttribute("ThrowStart")
		view.throwStart = if typeof(start) == "number" then start else Workspace:GetServerTimeNow()
		view.replayPos = nil
		view.replayStopped = false
	end
	if view.copy then
		LanternFx.styleCopy(view.copy, view.state)
	end
end

local function onBurst(view: View)
	local id = view.model:GetAttribute("BurstId")
	local at = view.model:GetAttribute("BurstAt")
	if typeof(id) == "number" and id ~= view.lastBurstId then
		view.lastBurstId = id
		if typeof(at) == "Vector3" then
			LanternFx.burst(at)
		end
	end
end

local function add(model: Instance)
	if not model:IsA("Model") or views[model] or isMine(model) then
		return
	end
	local burstId = model:GetAttribute("BurstId")
	local view: View = {
		model = model,
		copy = nil,
		state = "Hip",
		position = if model.PrimaryPart then model.PrimaryPart.Position else Vector3.zero,
		velocity = Vector3.zero,
		replayPos = nil,
		replayStopped = false,
		throwStart = 0,
		casts = nil,
		castsAt = -math.huge,
		lastBurstId = if typeof(burstId) == "number" then burstId else 0,
		connections = {},
	}
	views[model] = view
	table.insert(view.connections, model:GetAttributeChangedSignal("State"):Connect(function()
		onState(view)
	end))
	table.insert(view.connections, model:GetAttributeChangedSignal("BurstId"):Connect(function()
		onBurst(view)
	end))
	onState(view)
end

local function remove(model: Instance)
	local view = if model:IsA("Model") then views[model :: Model] else nil
	if not view then
		return
	end
	for _, c in view.connections do
		c:Disconnect()
	end
	if view.copy then
		view.copy:Destroy()
	end
	views[view.model] = nil
end

-- The replayed arc at the current server time (stops at the first thing it runs into).
local function replay(view: View): (Vector3, Vector3)
	local model = view.model
	local origin = model:GetAttribute("ThrowOrigin")
	local velocity = model:GetAttribute("ThrowVelocity")
	local gravity = model:GetAttribute("ThrowGravity")
	if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" or typeof(gravity) ~= "number" then
		local core = model.PrimaryPart
		return if core then core.Position else view.position, Vector3.zero
	end
	local stop = model:GetAttribute("ThrowStop")
	local t = math.max(0, Workspace:GetServerTimeNow() - view.throwStart)
	if typeof(stop) == "number" then
		t = math.min(t, stop)
	end
	local pos, vel = LanternPhysics.at(origin, velocity, gravity, t)
	if view.replayStopped and view.replayPos then
		return view.replayPos, Vector3.zero
	end
	local from = view.replayPos or origin
	local casts = view.casts
	if not casts or os.clock() - view.castsAt > 0.25 then
		local ownerId = model:GetAttribute("OwnerUserId")
		local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
		local ignore: { Instance } = {}
		if view.copy then
			table.insert(ignore, view.copy)
		end
		table.insert(ignore, model)
		casts = LanternPhysics.params(if owner then owner.Character else nil, ignore, true)
		view.casts = casts
		view.castsAt = os.clock()
	end
	local hit = LanternPhysics.cast(from, pos - from, casts)
	if hit then
		view.replayStopped = true
		view.replayPos = hit.position
		return hit.position, Vector3.zero
	end
	view.replayPos = pos
	return pos, vel
end

RunService.RenderStepped:Connect(function(dt: number)
	for _, view in views do
		local copy = view.copy
		if copy then
			-- Keep the server copy hidden (the character's camera transparency code can reset it).
			local core = view.model.PrimaryPart
			if core and core.LocalTransparencyModifier < 1 then
				LanternFx.hideServer(view.model, true)
			end
			local target = if core then core.Position else view.position
			if view.state == "Thrown" then
				local pos, vel = replay(view)
				view.position = pos
				view.velocity = vel
			else
				local gap = target - view.position
				if gap.Magnitude > SNAP_DISTANCE then
					view.position = target
				else
					view.position += gap * (1 - math.exp(-FOLLOW_RATE * dt))
				end
				view.velocity = Vector3.zero
			end
			LanternFx.placeCopy(copy, LanternFx.pose(view.position, view.velocity, view.state == "Thrown"))
		end
	end
end)

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, model in CollectionService:GetTagged(TAG) do
	add(model)
end
