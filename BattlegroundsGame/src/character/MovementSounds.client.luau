--!strict
-- MovementSounds (LocalScript)
-- Location: StarterPlayer > StarterCharacterScripts > MovementSounds
--
-- Your character's movement sounds that follow its state: footsteps (speed-matched), fall wind,
-- jump / land, wall run, dash, roll, vault / climb / slide, Moth flights and the lantern, stamina
-- burnout. One-off hits that only the movement code knows about (wall kick, dash punch hit, lantern
-- impact / hit) are played by those modules directly. Everything goes through Sfx, which also sends
-- it to the other players. Sounds: SoundConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local movement = ReplicatedStorage:WaitForChild("Movement")
movement:WaitForChild("Sfx")
movement:WaitForChild("MovementConfig")
local Sfx = require(ReplicatedStorage.Movement.Sfx)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart

-- Footsteps: the loop has 4 steps in 1.57 s (~2.5 steps/s) at speed 1.
local STEP_SPEED_REF = 16 -- studs/s that match PlaybackSpeed 1
local STEP_MIN_SPEED = 2 -- slower than this = no steps
-- Fall wind fades in from this fall speed and is full at +FALL_WIND_RANGE.
local FALL_WIND_START = 45
local FALL_WIND_RANGE = 55
-- Landings: quieter than this fall speed make no land sound; full volume at LAND_FULL.
local LAND_MIN = 14
local LAND_FULL = 75
-- Stamina: burnout when it hits 0, recovered at this much; "full" chime only after dipping below this.
local BURNOUT_RECOVER_AT = 25
local FULL_CHIME_BELOW = 60

local connections: { RBXScriptConnection } = {}
local lastFallSpeed = 0 -- downward speed last frame (landing loudness)

local function attr(name: string): any
	return character:GetAttribute(name)
end

-- Another move owns the body (no footsteps / fall wind of our own then).
local function busy(): boolean
	return attr("Dashing") == true
		or attr("Rolling") == true
		or attr("WallRunning") == true
		or attr("Parkour") ~= nil
		or attr("Flying") ~= nil
end

-- FOOTSTEPS + FALL WIND (every frame) --------------------------------------------------

table.insert(
	connections,
	RunService.Heartbeat:Connect(function()
		if humanoid.Health <= 0 then
			return
		end
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z).Magnitude
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local state = humanoid:GetState()
		local climbing = state == Enum.HumanoidStateType.Climbing

		local stepping = grounded and not climbing and flat > STEP_MIN_SPEED and not busy()
		if stepping then
			local speed = math.clamp(flat / STEP_SPEED_REF, 0.75, 1.9)
			local volume = math.clamp(0.55 + flat / 60, 0.6, 1)
			if Sfx.IsLooping(character, "Footsteps") then
				Sfx.SetLoop(character, "Footsteps", speed, volume)
			else
				Sfx.Loop(character, "Footsteps", true, { speed = speed, volume = volume })
			end
		elseif Sfx.IsLooping(character, "Footsteps") then
			Sfx.Loop(character, "Footsteps", false)
		end

		local falling = -v.Y
		local windOn = not grounded and falling > FALL_WIND_START and attr("Flying") == nil
		if windOn then
			local volume = math.clamp((falling - FALL_WIND_START) / FALL_WIND_RANGE, 0.1, 1)
			if Sfx.IsLooping(character, "FallWind") then
				Sfx.SetLoop(character, "FallWind", nil, volume)
			else
				Sfx.Loop(character, "FallWind", true, { volume = volume })
			end
		elseif Sfx.IsLooping(character, "FallWind") then
			Sfx.Loop(character, "FallWind", false)
		end

		if not grounded then
			lastFallSpeed = math.max(falling, 0)
		end
	end)
)

-- JUMP / LAND ---------------------------------------------------------------------------------

table.insert(
	connections,
	humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Jumping then
			if attr("Parkour") == nil and attr("Rolling") ~= true then
				Sfx.Play(character, "Jump")
			end
		elseif new == Enum.HumanoidStateType.Landed then
			local fall = lastFallSpeed
			lastFallSpeed = 0
			if fall < LAND_MIN then
				return
			end
			-- The landing roll decides on this same touchdown: give it a frame, it has its own sound.
			task.defer(function()
				if attr("Rolling") == true or attr("Parkour") ~= nil then
					return
				end
				local t = math.clamp((fall - LAND_MIN) / (LAND_FULL - LAND_MIN), 0, 1)
				Sfx.Play(character, "Land", { volume = 0.35 + 0.65 * t, speed = 1.1 - 0.15 * t })
			end)
		end
	end)
)

-- STATE CHANGES (attributes written by the movement modules) -------------------------------

local function watch(name: string, fn: (value: any, old: any) -> ())
	local old = attr(name)
	table.insert(
		connections,
		character:GetAttributeChangedSignal(name):Connect(function()
			local value = attr(name)
			local was = old
			old = value
			fn(value, was)
		end)
	)
end

watch("Dashing", function(value)
	if value == true then
		Sfx.Play(character, "Dash")
	end
end)

watch("DashKind", function(value)
	if value == "Punch" then
		Sfx.PlayAny(character, { "DashPunchSwing", "DashPunchSwing2" })
	end
end)

watch("WallRunning", function(value)
	if value == true then
		Sfx.Play(character, "Land", { volume = 0.3, speed = 1.3 }) -- feet hit the wall
		Sfx.Loop(character, "WallRun", true)
	else
		Sfx.Loop(character, "WallRun", false)
	end
end)

watch("Rolling", function(value)
	if value == true then
		Sfx.Play(character, "Land", { volume = 0.4, speed = 1.15 })
		Sfx.Play(character, "Roll")
	end
end)

watch("Parkour", function(value)
	if value == "Vault" or value == "StepUp" then
		Sfx.Play(character, "Vault")
	elseif value == "Climb" then
		Sfx.Play(character, "LedgeGrab")
	elseif value == "Slide" then
		Sfx.Play(character, "Slide")
	end
end)

watch("Flying", function(value, old)
	if value == "Wings" then
		Sfx.Play(character, "WingFlight")
	elseif value == "Free" or value == "Tag" then
		if value == "Tag" then
			Sfx.Play(character, "TagFlight")
		end
		Sfx.Loop(character, "WingFlap", true)
	end
	if value ~= "Free" and value ~= "Tag" and (old == "Free" or old == "Tag") then
		Sfx.Loop(character, "WingFlap", false)
		Sfx.Play(character, "WingStop")
	end
end)

watch("LanternState", function(value, old)
	if value == "Charging" then
		Sfx.Loop(character, "LanternCharge", true)
	elseif old == "Charging" then
		Sfx.Loop(character, "LanternCharge", false)
	end
	if value == "Thrown" then
		Sfx.Play(character, "LanternThrow")
	elseif value == "Suspended" then
		Sfx.Play(character, "LanternSuspend")
	elseif value == "Hip" and old ~= nil and old ~= "Charging" and old ~= "Hip" then
		Sfx.Play(character, "LanternGrab")
	end
end)

-- The lantern's flight hum follows the lantern itself (Lantern.luau starts / stops it).

local burnedOut = false
local dipped = false
watch("Stamina", function(value)
	if typeof(value) ~= "number" then
		return
	end
	local max = attr("StaminaMax")
	local full = if typeof(max) == "number" then max else Config.StaminaMax
	if value <= 0 and not burnedOut then
		burnedOut = true
		Sfx.Loop(character, "Burnout", true)
	elseif burnedOut and value >= BURNOUT_RECOVER_AT then
		burnedOut = false
		Sfx.Loop(character, "Burnout", false)
		Sfx.Play(character, "BurnoutRecover")
	end
	if value < FULL_CHIME_BELOW then
		dipped = true
	elseif dipped and value >= full then
		dipped = false
		Sfx.Play(character, "StaminaFull")
	end
end)

-- CLEANUP ------------------------------------------------------------------------------------

local function cleanup()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	Sfx.StopAll(character)
end

humanoid.Died:Connect(cleanup)
script.Destroying:Connect(cleanup)
