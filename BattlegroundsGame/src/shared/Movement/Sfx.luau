--!strict
-- Sfx (ModuleScript)
-- Location: ReplicatedStorage > Movement > Sfx
--
-- Plays the movement / Moth sounds from SoundConfig on a character (3D, at its HumanoidRootPart).
-- Movement runs on the owner's client, so the owner plays each sound right away and tells the server
-- (remotes MovementSfx / MovementSfxLoop, created by SfxServer), which passes it on to every other
-- player; their SfxReceiver script plays it on that character with Sfx.PlayRemote / LoopRemote.
--
--   Sfx.Play(character, name, { speed?, volume?, at? })     one-shot (at = a world position)
--   Sfx.Loop(character, name, on, { speed?, volume?, on? }) start / stop a looped sound
--                                                            (on = "Lantern": follows the lantern)
--   Sfx.SetLoop(character, name, speed?, volume?)           change a running loop (throttled relay)
--
-- A name with no asset Id yet uses a Sound in ReplicatedStorage > Sounds named like it OR like its
-- source file (e.g. "universeDash", which is what importing the audio folder in Studio makes), otherwise
-- it's skipped quietly (one warning per name in Studio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SoundConfig = require(script.Parent.SoundConfig)

local Sfx = {}

export type Options = {
	speed: number?,
	volume: number?,
	at: Vector3?,
	on: string?,
	parent: Instance?,
}

type LoopState = {
	sound: Sound,
	baseVolume: number,
	baseSpeed: number,
	sentSpeed: number,
	sentVolume: number,
	lastSent: number,
}

local IS_SERVER = RunService:IsServer()
local LOOP_RELAY_INTERVAL = 0.25 -- seconds between loop speed / volume updates sent to others
local LOOP_RELAY_CHANGE = 0.08 -- ...and only when they changed at least this much

local warned: { [string]: boolean } = {}
local loops: { [Model]: { [string]: LoopState } } = setmetatable({}, { __mode = "k" }) :: any

local function remote(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return if folder then folder:FindFirstChild(name) else nil
end

-- The SoundId / volume / speed to use for `name`, or nil if it has no sound yet.
local function resolve(name: string): (string?, number, number)
	local entry = SoundConfig[name]
	if not entry then
		return nil, 0, 1
	end
	local speed = entry.Speed or 1
	if entry.Id ~= "" then
		return entry.Id, entry.Volume, speed
	end
	-- ReplicatedStorage > Sounds: a Sound named like the entry (its own volume / speed win), or
	-- named like the source file without extension (what Studio's bulk import + Insert creates, e.g.
	-- "universeDash"; SoundConfig's volume / speed are used then).
	local folder = ReplicatedStorage:FindFirstChild("Sounds")
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Sound") and template.SoundId ~= "" then
		return template.SoundId, template.Volume, template.PlaybackSpeed
	end
	local stem = string.match(entry.File, "^(.-)%.[^.]+$") or entry.File
	local byFile = folder and folder:FindFirstChild(stem, true)
	if byFile and byFile:IsA("Sound") and byFile.SoundId ~= "" then
		return byFile.SoundId, entry.Volume, speed
	end
	if not warned[name] and RunService:IsStudio() then
		warned[name] = true
		warn(string.format("[Sfx] no sound for %q yet (SoundConfig Id empty, no ReplicatedStorage.Sounds.%s)", name, name))
	end
	return nil, 0, 1
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where a sound attaches: `opts.parent`, the character's lantern (opts.on == "Lantern"), else the root.
local function holderFor(character: Model, opts: Options?): Instance?
	if opts and opts.parent then
		return opts.parent
	end
	if opts and opts.on == "Lantern" then
		local lantern = character:FindFirstChild("Lantern")
		if lantern and lantern:IsA("Model") and lantern.PrimaryPart then
			return lantern.PrimaryPart
		end
	end
	return rootOf(character)
end

local function makeSound(name: string, id: string, volume: number, speed: number, looped: boolean): Sound
	local entry = SoundConfig[name]
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = if entry and entry.Range then entry.Range else 70
	return sound
end

-- LOCAL PLAYBACK (no relay) ------------------------------------------------------------

local function playOneShot(character: Model, name: string, opts: Options?)
	local id, baseVolume, baseSpeed = resolve(name)
	if not id then
		return
	end
	local entry = SoundConfig[name]
	local vary = entry and entry.Vary or 0
	local speed = baseSpeed * (if opts and opts.speed then opts.speed else 1)
	if vary > 0 then
		speed *= 1 + (math.random() * 2 - 1) * vary
	end
	local volume = baseVolume * (if opts and opts.volume then opts.volume else 1)
	local sound = makeSound(name, id, volume, speed, false)
	local at = opts and opts.at
	local holder: Instance?
	local attachment: Attachment? = nil
	if at then
		local a = Instance.new("Attachment")
		a.Name = "SfxPoint"
		a.WorldPosition = at
		a.Parent = Workspace.Terrain
		attachment = a
		holder = a
	else
		holder = holderFor(character, opts)
	end
	if not holder then
		sound:Destroy()
		return
	end
	sound.Parent = holder
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
		if attachment then
			attachment:Destroy()
		end
	end)
	-- Safety net in case Ended never fires (asset failed to load).
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end)
end

local function setLoopLocal(character: Model, name: string, on: boolean, opts: Options?): LoopState?
	local byName = loops[character]
	local current = byName and byName[name]
	if not on then
		if current then
			current.sound:Destroy()
			if byName then
				byName[name] = nil
			end
		end
		return nil
	end
	if current and current.sound.Parent then
		-- Already playing: just apply the new speed / volume.
		if opts and opts.speed then
			current.sound.PlaybackSpeed = current.baseSpeed * opts.speed
		end
		if opts and opts.volume then
			current.sound.Volume = current.baseVolume * opts.volume
		end
		return current
	end
	local id, baseVolume, baseSpeed = resolve(name)
	if not id then
		return nil
	end
	local holder = holderFor(character, opts)
	if not holder then
		return nil
	end
	local speed = baseSpeed * (if opts and opts.speed then opts.speed else 1)
	local volume = baseVolume * (if opts and opts.volume then opts.volume else 1)
	-- A "loop" whose SoundConfig entry isn't Looped plays once but can still be cut off (charge sound).
	local entry = SoundConfig[name]
	local sound = makeSound(name, id, volume, speed, entry ~= nil and entry.Looped == true)
	sound.Parent = holder
	sound:Play()
	local state: LoopState = {
		sound = sound,
		baseVolume = baseVolume,
		baseSpeed = baseSpeed,
		sentSpeed = if opts and opts.speed then opts.speed else 1,
		sentVolume = if opts and opts.volume then opts.volume else 1,
		lastSent = os.clock(),
	}
	if not byName then
		byName = {}
		loops[character] = byName
	end
	(byName :: { [string]: LoopState })[name] = state
	return state
end

-- RELAY -----------------------------------------------------------------------------------

local function isMine(character: Model): boolean
	if IS_SERVER then
		return false
	end
	local player = Players.LocalPlayer
	return player ~= nil and player.Character == character
end

local function relayOneShot(character: Model, name: string, opts: Options?)
	if not isMine(character) then
		return
	end
	local r = remote("MovementSfx")
	if r and r:IsA("UnreliableRemoteEvent") then
		r:FireServer(name, opts and opts.speed or 1, opts and opts.volume or 1, opts and opts.at or nil)
	end
end

local function relayLoop(character: Model, name: string, on: boolean, speed: number, volume: number, target: string?)
	if not isMine(character) then
		return
	end
	local r = remote("MovementSfxLoop")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, on, speed, volume, target)
	end
end

-- PUBLIC ------------------------------------------------------------------------------------

function Sfx.Play(character: Model, name: string, opts: Options?)
	playOneShot(character, name, opts)
	relayOneShot(character, name, opts)
end

-- Plays one of several names at random (e.g. two swing sounds).
function Sfx.PlayAny(character: Model, names: { string }, opts: Options?)
	Sfx.Play(character, names[math.random(1, #names)], opts)
end

function Sfx.Loop(character: Model, name: string, on: boolean, opts: Options?)
	local byName = loops[character]
	local was = byName ~= nil and byName[name] ~= nil
	setLoopLocal(character, name, on, opts)
	-- Tell others about on/off changes (speed changes go through SetLoop).
	if on ~= was then
		relayLoop(character, name, on, opts and opts.speed or 1, opts and opts.volume or 1, opts and opts.on)
	end
end

function Sfx.IsLooping(character: Model, name: string): boolean
	local byName = loops[character]
	return byName ~= nil and byName[name] ~= nil
end

-- Changes a running loop's speed / volume (multipliers on the SoundConfig values).
function Sfx.SetLoop(character: Model, name: string, speed: number?, volume: number?)
	local byName = loops[character]
	local state = byName and byName[name]
	if not state then
		return
	end
	if speed then
		state.sound.PlaybackSpeed = state.baseSpeed * speed
	end
	if volume then
		state.sound.Volume = state.baseVolume * volume
	end
	local now = os.clock()
	local s = speed or state.sentSpeed
	local v = volume or state.sentVolume
	if
		now - state.lastSent >= LOOP_RELAY_INTERVAL
		and (math.abs(s - state.sentSpeed) >= LOOP_RELAY_CHANGE or math.abs(v - state.sentVolume) >= LOOP_RELAY_CHANGE)
	then
		state.lastSent = now
		state.sentSpeed = s
		state.sentVolume = v
		relayLoop(character, name, true, s, v, nil)
	end
end

-- Stops every loop on a character (death, respawn).
function Sfx.StopAll(character: Model)
	local byName = loops[character]
	if not byName then
		return
	end
	for name in byName do
		Sfx.Loop(character, name, false)
	end
end

-- Used by SfxReceiver for sounds other players' clients reported (no relay back).
function Sfx.PlayRemote(character: Model, name: string, speed: number, volume: number, at: Vector3?)
	playOneShot(character, name, { speed = speed, volume = volume, at = at })
end

function Sfx.LoopRemote(character: Model, name: string, on: boolean, speed: number, volume: number, target: string?)
	setLoopLocal(character, name, on, { speed = speed, volume = volume, on = target })
end

return Sfx
