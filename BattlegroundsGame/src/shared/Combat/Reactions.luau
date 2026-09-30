--!strict
-- Reactions (ModuleScript)
-- Location: ReplicatedStorage > Combat > Reactions
--
-- How a character reacts to what the server says happened to it: the hit stun flinch, being
-- pushed back, hanging in the air, launched, knocked down, spiked, blocking a hit, parrying,
-- getting parried, lying on the floor and getting up, and the Lotus ones: held by a grab or an
-- impale, wrapped in growth (Infested), consumed by your own missed stage 3 move. It runs where the character's physics and
-- animations are owned: the player's own client (CombatClient) or the server for a dummy.
--
--   reactions:React(info)   the server's Hit message (HitResolver builds it)
-- It also follows the character's "CombatState" and "Guard" attributes (set by the server): the
-- block pose while the guard is up, Downed / GetUp / TechRoll, and letting go of the body when a
-- stun ends.
-- Every reaction first holds still for the hit pause (info.hitstop), then moves.

local CombatBody = require(script.Parent.CombatBody)
local CombatAnimator = require(script.Parent.CombatAnimator)

local Reactions = {}
Reactions.__index = Reactions

-- Reaction animations that end when the stun ends.
local STUN_ANIMS = { "HitStun1", "HitStun2", "HitAir", "BlockImpact", "Parried", "Launched", "LotusHeld", "LotusConsumed" }

type Data = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	body: CombatBody.CombatBody,
	anim: CombatAnimator.CombatAnimator,
	version: number,
	lastState: string,
	connections: { RBXScriptConnection },
	-- Called when a reaction starts (the owner cancels its own move, dash, etc.).
	onInterrupt: (() -> ())?,
}

export type Reactions = typeof(setmetatable({} :: Data, Reactions))

function Reactions.new(character: Model, body: CombatBody.CombatBody, anim: CombatAnimator.CombatAnimator, onInterrupt: (() -> ())?): Reactions
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		body = body,
		anim = anim,
		version = 0,
		lastState = "Idle",
		connections = {},
		onInterrupt = onInterrupt,
	} :: Data, Reactions)
	table.insert(self.connections, character:GetAttributeChangedSignal("CombatState"):Connect(function()
		self:_onState()
	end))
	table.insert(self.connections, character:GetAttributeChangedSignal("Guard"):Connect(function()
		self.anim:Hold("BlockHold", character:GetAttribute("Guard") == true)
	end))
	return self
end

local function airborne(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
end

-- After the hit pause, unless a newer reaction replaced this one.
function Reactions._after(self: Reactions, seconds: number, fn: () -> ())
	local version = self.version
	if seconds <= 0 then
		fn()
		return
	end
	task.delay(seconds, function()
		if self.version == version then
			fn()
		end
	end)
end

function Reactions.React(self: Reactions, info: { [string]: any })
	local kind = info.kind
	local hitstop = if typeof(info.hitstop) == "number" then info.hitstop else 0
	local velocity: Vector3 = if typeof(info.velocity) == "Vector3" then info.velocity else Vector3.zero
	if kind == "Parry" then
		self.anim:Play("Parry")
		return
	end
	if kind == "Armour" then
		self.anim:Freeze(hitstop)
		return
	end
	self.version += 1
	if self.onInterrupt then
		self.onInterrupt()
	end
	local body = self.body
	-- Hold still through the hit pause.
	if hitstop > 0 then
		body:Hang(hitstop)
	end

	if kind == "Stun" then
		-- Forced (Wind's push / pull): carried along even in the air, never left hanging.
		local hang = info.forced ~= true and (info.hang == true or airborne(self.humanoid))
		self.anim:Play(if hang then "HitAir" else (if typeof(info.anim) == "string" then info.anim else "HitStun1"))
		self.anim:Freeze(hitstop)
		local stun = if typeof(info.stun) == "number" then info.stun else 0.25
		self:_after(hitstop, function()
			if hang then
				body:Hang(stun, Vector3.new(velocity.X, 0, velocity.Z) * 0.15)
			else
				body:Push(velocity, if typeof(info.push) == "number" then info.push else 0.15, true)
			end
		end)
	elseif kind == "Block" then
		self.anim:Hold("BlockHold", true)
		self.anim:Play("BlockImpact")
		self:_after(hitstop, function()
			body:Push(velocity, if typeof(info.push) == "number" then info.push else 0.15, true)
		end)
	elseif kind == "Parried" then
		self.anim:Play("Parried")
		body:Push(-self.root.CFrame.LookVector * 10, 0.2, true)
	elseif kind == "Launch" then
		self.anim:Play("Launched")
		self.anim:Freeze(hitstop)
		local stun = if typeof(info.stun) == "number" then info.stun else 0.8
		self:_after(hitstop, function()
			-- Straight up, and no steering while helpless (the flat velocity is held at 0).
			body:Launch(velocity, stun)
		end)
	elseif kind == "Knockdown" or kind == "Spike" then
		self.anim:Play("Knockback")
		self.anim:Freeze(hitstop)
		self:_after(hitstop, function()
			body:Launch(velocity, 0.05)
			-- Keep flying the same way until the landing (the server says Downed).
			body:Push(Vector3.new(velocity.X, 0, velocity.Z), 3)
		end)
	elseif kind == "Downed" then
		self.anim:Freeze(hitstop)
	elseif kind == "Held" then
		-- Caught by a grab or an impale: held still until the server throws / drops them.
		self.anim:Play("LotusHeld")
		local hold = if typeof(info.stun) == "number" then info.stun else 0.5
		self:_after(hitstop, function()
			body:Hang(hold)
		end)
	elseif kind == "Wrapped" then
		-- Infested and caught blocking a Lotus move: wrapped in growth, down on the spot.
		body:Release()
		self.anim:Play("Downed")
	elseif kind == "Consumed" then
		-- Your own stage 3 move missed: the fungus bites back.
		body:Release()
		self.anim:Play("LotusConsumed")
	end
end

-- Follows the server's state for the character.
function Reactions._onState(self: Reactions)
	local state = self.character:GetAttribute("CombatState")
	local was = self.lastState
	self.lastState = if typeof(state) == "string" then state else "Idle"
	if state == "Downed" then
		self.body:Release()
		self.anim:Play("Downed")
	elseif state == "TechRoll" then
		self.anim:Play("TechRoll")
	elseif state == "Idle" or state == "Blocking" or state == "Attacking" then
		if was == "Downed" then
			self.anim:Play("GetUp")
		elseif was ~= "TechRoll" then
			for _, name in STUN_ANIMS do
				self.anim:StopMove(name)
			end
		end
		if was == "Stunned" or was == "Launched" or was == "Parried" or was == "Blockstun" or was == "Knockdown" or was == "Held" then
			self.body:Release()
		end
	end
end

function Reactions.Destroy(self: Reactions)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
end

return Reactions
