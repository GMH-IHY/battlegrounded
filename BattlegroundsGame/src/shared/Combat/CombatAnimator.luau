--!strict
-- CombatAnimator (ModuleScript)
-- Location: ReplicatedStorage > Combat > CombatAnimator
--
-- Plays one character's combat animations (attacks, block, parry, hit reactions) on its
-- Animator. Used where the character's animations are owned: the player's own client
-- (CombatClient) or the server for a training dummy. Everything snaps (fade 0), like the rest.
--
--   anim:Play(name, speed?)   stops the combat animation playing, plays `name` from the start
--   anim:Hold(name, on)       a looped pose layered under the others (BlockHold)
--   anim:Stop()               stops everything this module started
--   anim:Freeze(seconds)      hit pause: every playing track holds still, then carries on

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationLibrary = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("AnimationLibrary"))

local CombatAnimator = {}
CombatAnimator.__index = CombatAnimator

type Data = {
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	current: string?,
	holds: { [string]: boolean },
	frozenUntil: number,
	frozen: { [AnimationTrack]: number },
}

export type CombatAnimator = typeof(setmetatable({} :: Data, CombatAnimator))

function CombatAnimator.new(humanoid: Humanoid): CombatAnimator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	assert(animator, "CombatAnimator: no Animator")
	return setmetatable({
		animator = animator,
		tracks = {},
		current = nil,
		holds = {},
		frozenUntil = 0,
		frozen = {},
	} :: Data, CombatAnimator)
end

function CombatAnimator._track(self: CombatAnimator, name: string): AnimationTrack?
	local track = self.tracks[name]
	if track then
		return track
	end
	local animation = AnimationLibrary.Get(name)
	if not animation then
		return nil
	end
	local loaded = self.animator:LoadAnimation(animation)
	loaded.Priority = Enum.AnimationPriority.Action
	self.tracks[name] = loaded
	return loaded
end

function CombatAnimator.Play(self: CombatAnimator, name: string, speed: number?): AnimationTrack?
	local current = self.current
	if current and current ~= name then
		local old = self.tracks[current]
		if old and old.IsPlaying then
			old:Stop(0)
		end
	end
	local track = self:_track(name)
	self.current = name
	if track then
		track:Play(0, 1, speed or 1)
		-- Starting over from the first frame even when it was already playing.
		track.TimePosition = 0
	end
	return track
end

function CombatAnimator.GetCurrent(self: CombatAnimator): string?
	local current = self.current
	if current then
		local track = self.tracks[current]
		if track and track.IsPlaying then
			return current
		end
	end
	return nil
end

-- Stops `name` if it's the one playing (or anything, with no name).
function CombatAnimator.StopMove(self: CombatAnimator, name: string?)
	local current = self.current
	if current and (name == nil or name == current) then
		local track = self.tracks[current]
		if track and track.IsPlaying then
			track:Stop(0)
		end
		self.current = nil
	end
end

function CombatAnimator.Hold(self: CombatAnimator, name: string, on: boolean)
	if (self.holds[name] == true) == on then
		return
	end
	self.holds[name] = on
	local track = self:_track(name)
	if not track then
		return
	end
	if on then
		track.Looped = true
		track:Play(0, 1, 1)
	else
		track:Stop(0)
	end
end

function CombatAnimator.Stop(self: CombatAnimator)
	for name, track in self.tracks do
		if track.IsPlaying then
			track:Stop(0)
		end
		self.holds[name] = nil
	end
	self.current = nil
end

-- Hit pause: holds every playing animation on this character for `seconds`.
function CombatAnimator.Freeze(self: CombatAnimator, seconds: number)
	local now = os.clock()
	self.frozenUntil = math.max(self.frozenUntil, now + seconds)
	for _, track in self.animator:GetPlayingAnimationTracks() do
		if self.frozen[track] == nil and track.Speed ~= 0 then
			self.frozen[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
	task.delay(seconds, function()
		if os.clock() + 1e-3 < self.frozenUntil then
			return
		end
		for track, speed in self.frozen do
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end
		table.clear(self.frozen)
	end)
end

return CombatAnimator
