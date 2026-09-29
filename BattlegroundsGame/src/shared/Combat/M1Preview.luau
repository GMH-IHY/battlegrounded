--!strict
-- M1Preview (ModuleScript)
-- Location: ReplicatedStorage > Combat > M1Preview
--
-- PLACEHOLDER until the combat system (phase 2): the sword's 3-hit M1 chain on your own client,
-- with the real timings and animations but no hitbox, damage or server. It's here so movement can be
-- tuned against attacking: a side dash, a landing roll or a Moth flight cuts straight into a swing
-- (MovementController), and the swing slows your walk (AttackMoveSpeedScale).
--
-- Timings (docs/MoveData.md, 60 fps): M1 1 and 2 = startup 5, active 2, recovery 11 frames;
-- M1 3 = 7 / 3 / 18. Clicking during a swing queues the next one (it starts the moment the current
-- one's recovery ends); after the third, or ChainReset seconds without a swing, the chain restarts.
-- The phase is mirrored to the character attribute "AttackPhase" ("Startup" / "Active" / "Recovery"),
-- which Dash reads (no dashing out of a wind-up or a hit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = ReplicatedStorage:WaitForChild("Movement")
local AnimationLibrary = require(Movement:WaitForChild("AnimationLibrary"))
local CharacterMotor = require(Movement:WaitForChild("CharacterMotor"))
local Config = require(Movement:WaitForChild("MovementConfig"))

local FRAME = 1 / 60
local CHAIN_RESET = 0.6 -- seconds after a swing ends before the chain starts over

type Swing = { animation: string, startup: number, active: number, recovery: number }
local SWINGS: { Swing } = {
	{ animation = "M1Swing1", startup = 5 * FRAME, active = 2 * FRAME, recovery = 11 * FRAME },
	{ animation = "M1Swing2", startup = 5 * FRAME, active = 2 * FRAME, recovery = 11 * FRAME },
	{ animation = "M1Swing3", startup = 7 * FRAME, active = 3 * FRAME, recovery = 18 * FRAME },
}

export type Phase = "Idle" | "Startup" | "Active" | "Recovery"

local M1Preview = {}
M1Preview.__index = M1Preview

type Data = {
	character: Model,
	humanoid: Humanoid,
	motor: CharacterMotor.CharacterMotor,
	tracks: { AnimationTrack },
	connection: RBXScriptConnection?,
	phase: Phase,
	index: number, -- the swing playing (1..3)
	startedAt: number,
	endedAt: number,
	queued: boolean,
	swings: number, -- total swings started (tests)
}

export type M1Preview = typeof(setmetatable({} :: Data, M1Preview))

local active: { [Model]: M1Preview } = {}

function M1Preview.new(character: Model, motor: CharacterMotor.CharacterMotor): M1Preview
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	assert(animator, "M1Preview: no Animator")
	local tracks: { AnimationTrack } = {}
	for i, swing in SWINGS do
		local animation = AnimationLibrary.Get(swing.animation)
		if animation then
			local track = animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false
			tracks[i] = track
		end
	end
	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		motor = motor,
		tracks = tracks,
		connection = nil,
		phase = "Idle" :: Phase,
		index = 0,
		startedAt = 0,
		endedAt = -math.huge,
		queued = false,
		swings = 0,
	} :: Data, M1Preview)
	self.connection = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	active[character] = self
	return self
end

function M1Preview.Get(character: Model): M1Preview?
	return active[character]
end

function M1Preview.GetPhase(self: M1Preview): Phase
	return self.phase
end

function M1Preview.GetIndex(self: M1Preview): number
	return self.index
end

function M1Preview.GetSwingCount(self: M1Preview): number
	return self.swings
end

-- A click. Starts the next swing now, or queues it if one is playing. Returns whether it was taken.
function M1Preview.Request(self: M1Preview): boolean
	if self.humanoid.Health <= 0 or self.motor:IsLandingLag() then
		return false
	end
	if self.phase ~= "Idle" then
		self.queued = true
		return true
	end
	self:_start()
	return true
end

function M1Preview._setPhase(self: M1Preview, phase: Phase)
	self.phase = phase
	self.character:SetAttribute("AttackPhase", if phase == "Idle" then nil else phase)
end

function M1Preview._start(self: M1Preview)
	local now = os.clock()
	local continues = self.index > 0 and self.index < #SWINGS and now - self.endedAt <= CHAIN_RESET
	self.index = if continues then self.index + 1 else 1
	self.startedAt = now
	self.queued = false
	self.swings += 1
	self:_setPhase("Startup")
	self.motor:SetSpeedScale("Attack", Config.AttackMoveSpeedScale)
	for i, track in self.tracks do
		if i ~= self.index and track.IsPlaying then
			track:Stop(0)
		end
	end
	local track = self.tracks[self.index]
	if track then
		track:Play(0, 1, 1)
	end
end

function M1Preview._step(self: M1Preview)
	if self.phase == "Idle" then
		return
	end
	local swing = SWINGS[self.index]
	local elapsed = os.clock() - self.startedAt
	local activeAt = swing.startup
	local recoveryAt = activeAt + swing.active
	local endAt = recoveryAt + swing.recovery
	if elapsed >= endAt then
		self.endedAt = os.clock()
		self:_setPhase("Idle")
		self.motor:SetSpeedScale("Attack", nil)
		if self.queued then
			self:_start()
		end
	elseif elapsed >= recoveryAt then
		if self.phase ~= "Recovery" then
			self:_setPhase("Recovery")
		end
	elseif elapsed >= activeAt then
		if self.phase ~= "Active" then
			self:_setPhase("Active")
		end
	end
end

-- Stops the swing (getting hit, once combat exists).
function M1Preview.Cancel(self: M1Preview)
	for _, track in self.tracks do
		track:Stop(0)
	end
	self.queued = false
	self.endedAt = os.clock()
	self:_setPhase("Idle")
	self.motor:SetSpeedScale("Attack", nil)
end

function M1Preview.Destroy(self: M1Preview)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self:Cancel()
	if active[self.character] == self then
		active[self.character] = nil
	end
end

return M1Preview
