--!strict
-- CombatClient (ModuleScript)
-- Location: ReplicatedStorage > Combat > CombatClient
--
-- Your own character's side of combat, on your client (MovementController creates it). The
-- server decides every hit (CombatServer); this module makes pressing a key feel instant:
--   * picks the move a key makes right now (Loadout: chain position, air, running, Space held),
--     plays it, moves you with it (step, lunge, hanging in the air), and asks the server to run it
--   * clicking during a swing queues the next M1; a move that hit can cancel into its follow-ups
--     (M1 / dagger -> 1), and the launcher's recovery can be jumped out of (JumpCancel)
--   * F: block while held, a fresh press is also a parry try (the server times the window)
--   * reacts to the server: a refused move stops; a hit pauses the swing (hit pause); getting hit,
--     blocking, being parried or knocked down plays out through Reactions
--   * while the server says you're stunned ("Stunned" attribute) you can't move, jump or act;
--     Shift while downed is a tech roll
-- The move's phase is mirrored to the attribute "AttackPhase" (Startup / Active / Recovery) that
-- Dash reads (no dashing out of a wind-up or a hit), and "LocalMove" (CombatFx draws your own
-- slashes from it without waiting for the server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Movement = ReplicatedStorage:WaitForChild("Movement")
local CharacterMotor = require(Movement:WaitForChild("CharacterMotor"))
local MovementConfig = require(Movement:WaitForChild("MovementConfig"))
local Sfx = require(Movement:WaitForChild("Sfx"))

local Config = require(script.Parent.CombatConfig)
local Moves = require(script.Parent.Moves)
local Loadout = require(script.Parent.Loadout)
local CombatBody = require(script.Parent.CombatBody)
local CombatAnimator = require(script.Parent.CombatAnimator)
local CombatRemotes = require(script.Parent.CombatRemotes)
local Reactions = require(script.Parent.Reactions)
local WeaponModels = require(script.Parent.WeaponModels)
local FighterCollision = require(script.Parent.FighterCollision)

type Move = Moves.Move

local FRAME = 1 / Config.FPS

export type Phase = "Idle" | "Startup" | "Active" | "Recovery"

export type Hooks = {
	-- Stop whatever movement move is running (getting hit, a move cancelling a dash).
	interruptMovement: () -> (),
}

type Current = {
	move: Move,
	seq: number,
	elapsed: number,
	pauseUntil: number,
	result: string?,
	queued: string?,
	phase: Phase,
	look: Vector3,
}

local CombatClient = {}
CombatClient.__index = CombatClient

type Data = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	hooks: Hooks,
	body: CombatBody.CombatBody,
	anim: CombatAnimator.CombatAnimator,
	reactions: Reactions.Reactions,
	remotes: CombatRemotes.Remotes,
	connections: { RBXScriptConnection },

	seq: number,
	current: Current?,
	chain: number,
	chainEndedAt: number,
	cooldowns: { [string]: number },
	blockHeld: boolean,
	locked: boolean,
	swings: number,
	lastResult: string,
	lastMove: string,
	lastAdvantage: number?,
	destroyed: boolean,
}

export type CombatClient = typeof(setmetatable({} :: Data, CombatClient))

local active: { [Model]: CombatClient } = {}

function CombatClient.new(character: Model, motor: CharacterMotor.CharacterMotor, hooks: Hooks): CombatClient
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local body = CombatBody.new(character, motor)
	local anim = CombatAnimator.new(humanoid)
	local self: CombatClient
	local reactions = Reactions.new(character, body, anim, function()
		self:_interrupted()
	end)
	self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		hooks = hooks,
		body = body,
		anim = anim,
		reactions = reactions,
		remotes = CombatRemotes.Get(),
		connections = {},

		seq = 0,
		current = nil,
		chain = 0,
		chainEndedAt = -math.huge,
		cooldowns = {},
		blockHeld = false,
		locked = false,
		swings = 0,
		lastResult = "",
		lastMove = "",
		lastAdvantage = nil,
		destroyed = false,
	} :: Data, CombatClient)

	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt: number)
		self:_step(dt)
	end))
	table.insert(self.connections, self.remotes.Result.OnClientEvent:Connect(function(seq: number, result: string, hitstop: number, advantage: number?)
		if result ~= "Reject" then
			self.lastAdvantage = advantage
		end
		self:_onResult(seq, result, hitstop)
	end))
	table.insert(self.connections, self.remotes.Hit.OnClientEvent:Connect(function(info: { [string]: any })
		self.reactions:React(info)
	end))
	table.insert(self.connections, character:GetAttributeChangedSignal("Stunned"):Connect(function()
		self:_updateLock()
	end))
	active[character] = self
	-- Your own client simulates your body, so its parts (and colliders movement adds) need the
	-- group here too: fighters pass through each other.
	FighterCollision.Apply(character)
	self:_updateLock()
	return self
end

function CombatClient.Get(character: Model): CombatClient?
	return active[character]
end

-- INFO ---------------------------------------------------------------------------------------

function CombatClient.IsLocked(self: CombatClient): boolean
	return self.locked
end

function CombatClient.IsAttacking(self: CombatClient): boolean
	return self.current ~= nil
end

function CombatClient.GetPhase(self: CombatClient): Phase
	local current = self.current
	return if current then current.phase else "Idle"
end

function CombatClient.GetMoveId(self: CombatClient): string?
	local current = self.current
	return if current then current.move.Id else nil
end

-- The chain position of the M1 playing (or the last one).
function CombatClient.GetIndex(self: CombatClient): number
	local current = self.current
	if current and current.move.Chain > 0 then
		return current.move.Chain
	end
	return self.chain
end

function CombatClient.GetSwingCount(self: CombatClient): number
	return self.swings
end

function CombatClient.GetLastResult(self: CombatClient): string
	return self.lastResult
end

function CombatClient.GetLastMove(self: CombatClient): string
	return self.lastMove
end

-- Frame advantage of your last move that hit or was blocked (nil for knockdowns / launches).
function CombatClient.GetLastAdvantage(self: CombatClient): number?
	return self.lastAdvantage
end

function CombatClient.GetFrame(self: CombatClient): number
	local current = self.current
	return if current then math.floor(current.elapsed / FRAME + 1e-6) else -1
end

function CombatClient.GetCooldown(self: CombatClient, group: string): number
	local ready = self.cooldowns[group]
	return if ready then math.max(ready - os.clock(), 0) else 0
end

function CombatClient.IsBlocking(self: CombatClient): boolean
	return self.blockHeld
end

-- PICKING A MOVE ------------------------------------------------------------------------------

function CombatClient._context(self: CombatClient, lunge: boolean?): Loadout.Context
	local now = os.clock()
	local current = self.current
	local chain
	if current and current.move.Chain > 0 then
		chain = if current.move.Chain < 3 then current.move.Chain + 1 else 1
	else
		chain = Loadout.NextChain(self.chain, now - self.chainEndedAt, Config.ChainWindow)
	end
	local mode = self.motor:GetMode()
	local air = mode == "Air"
		or (mode ~= "Ground" and self.humanoid.FloorMaterial == Enum.Material.Air)
	local speed = Vector3.new(self.root.AssemblyLinearVelocity.X, 0, self.root.AssemblyLinearVelocity.Z).Magnitude
	local running = lunge == true or (self.motor:IsSprinting() and speed > MovementConfig.WalkSpeed * 1.2)
	return { air = air, running = running and not air, spaceHeld = self.motor:IsJumpHeld(), chain = chain }
end

-- A key press: "M1", "M2" or "One". lunge = came from a front dash (the running M1).
-- Returns whether something started or was queued.
function CombatClient.Press(self: CombatClient, slot: string, lunge: boolean?): boolean
	if self.destroyed or self.locked or self.humanoid.Health <= 0 then
		return false
	end
	if self.blockHeld then
		return false
	end
	local ctx = self:_context(lunge)
	local id = Loadout.Pick(slot, ctx)
	local move = if id then Moves.Get(id) else nil
	if not move then
		return false
	end
	local current = self.current
	if current then
		local landed = current.result == "Hit" or current.result == "Counter"
		local cancel = landed and table.find(current.move.CancelInto, move.Id) ~= nil
		if not cancel then
			if slot == "M1" and current.move.Chain > 0 and current.move.Chain < 3 and move.Chain > 0 then
				current.queued = "M1"
				return true
			end
			return false
		end
	end
	if self:GetCooldown(move.CooldownGroup) > 0 then
		Sfx.Play(self.character, "Denied", { volume = 0.7 })
		return false
	end
	self:_start(move)
	return true
end

-- Space during a launcher that hit: jump straight up after them.
function CombatClient.TryJumpCancel(self: CombatClient): boolean
	local current = self.current
	if not current or not current.move.JumpCancel or current.phase ~= "Recovery" then
		return false
	end
	if current.result ~= "Hit" and current.result ~= "Counter" then
		return false
	end
	self:_finish(false)
	local height = current.move.OnHit.Launch * 0.9
	self.motor:AllowLaunch(1.5)
	self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local v = self.root.AssemblyLinearVelocity
	self.root.AssemblyLinearVelocity = Vector3.new(v.X, math.sqrt(2 * Workspace.Gravity * height), v.Z)
	return true
end

-- The nearest other fighter in front, for the soft lock.
function CombatClient._aimTarget(self: CombatClient): Vector3?
	local look = self.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local best: Vector3? = nil
	local bestDistance = Config.AimAssistRange
	local cosLimit = math.cos(math.rad(Config.AimAssistAngle))
	local candidates: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character ~= self.character then
			table.insert(candidates, player.Character)
		end
	end
	local dummies = Workspace:FindFirstChild("TrainingDummies")
	if dummies then
		for _, model in dummies:GetChildren() do
			if model:IsA("Model") then
				table.insert(candidates, model)
			end
		end
	end
	for _, model in candidates do
		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			local offset = root.Position - self.root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			if distance < bestDistance and distance > 0.5 and flat.Unit:Dot(flatLook) >= cosLimit then
				best, bestDistance = flat.Unit, distance
			end
		end
	end
	return best
end

function CombatClient._start(self: CombatClient, move: Move)
	local previous = self.current
	if previous then
		self:_finish(true)
	end
	self.hooks.interruptMovement()
	self.seq += 1
	self.swings += 1
	self.lastMove = move.Id
	self.lastResult = ""
	local look = self:_aimTarget() or Vector3.new(self.root.CFrame.LookVector.X, 0, self.root.CFrame.LookVector.Z).Unit
	self.current = {
		move = move,
		seq = self.seq,
		elapsed = 0,
		pauseUntil = 0,
		result = nil,
		queued = nil,
		phase = "Startup",
		look = look,
	}
	if move.Cooldown > 0 then
		self.cooldowns[move.CooldownGroup] = os.clock() + move.Cooldown
	end
	self.remotes.Move:FireServer(move.Id, self.seq)
	self.character:SetAttribute("AttackPhase", "Startup")
	self.character:SetAttribute("LocalMove", move.Id .. "#" .. self.seq)
	self.motor:SetSpeedScale("Attack", Config.AttackMoveSpeedScale)
	self.motor:SetJumpLock("Attack", true)
	self.body:Face(look)
	if move.Weapon == "Dagger" then
		WeaponModels.SetDaggerDrawn(self.character, true)
	end
	if move.Air then
		self.body:Hang(Moves.Total(move, true) * FRAME)
	elseif move.Motion.Step > 0 then
		local seconds = math.max(move.Startup, 1) * FRAME
		self.body:Push(look * (move.Motion.Step / seconds), seconds)
	elseif move.Motion.Lunge > 0 then
		-- Still sliding from the run while winding up.
		local seconds = move.Startup * FRAME
		self.body:Push(look * MovementConfig.RunSpeed, seconds, true)
	end
	self.anim:Play(move.Animation)
end

-- Ends the current move. interrupted = it didn't play out (a cancel, a hit, a refusal).
function CombatClient._finish(self: CombatClient, interrupted: boolean)
	local current = self.current
	if not current then
		return
	end
	self.current = nil
	local move = current.move
	if move.Chain > 0 then
		self.chain = if move.Chain >= 3 then 0 else move.Chain
		self.chainEndedAt = os.clock()
	elseif move.Id == "Sword.Lunge" then
		self.chain = 0
	end
	if interrupted then
		self.anim:StopMove(move.Animation)
	end
	if move.Weapon == "Dagger" then
		WeaponModels.SetDaggerDrawn(self.character, false)
	end
	self.character:SetAttribute("AttackPhase", nil)
	self.character:SetAttribute("LocalMove", nil)
	self.motor:SetSpeedScale("Attack", nil)
	self.motor:SetJumpLock("Attack", false)
	self.body:Face(nil)
	if not self.locked then
		self.body:Release()
	end
	if not interrupted and current.queued and not self.locked then
		self:Press(current.queued)
	end
end

-- Stops the move (a dash out of its recovery).
function CombatClient.Cancel(self: CombatClient)
	self:_finish(true)
end

function CombatClient._interrupted(self: CombatClient)
	self:_finish(true)
	self.hooks.interruptMovement()
end

-- EVERY FRAME ------------------------------------------------------------------------------

function CombatClient._step(self: CombatClient, dt: number)
	local current = self.current
	if not current or self.destroyed then
		return
	end
	if os.clock() < current.pauseUntil then
		return
	end
	current.elapsed += dt
	local move = current.move
	local frame = math.floor(current.elapsed / FRAME + 1e-6)
	local whiff = current.result == nil
	local phase = Moves.PhaseAt(move, frame, whiff)
	if phase == "Done" then
		self:_finish(false)
		return
	end
	if phase ~= current.phase then
		current.phase = phase :: Phase
		self.character:SetAttribute("AttackPhase", phase)
		if phase == "Active" then
			Sfx.Play(self.character, move.Fx.Swing, { volume = 0.8 })
			if move.Motion.Lunge > 0 then
				local seconds = move.Active * FRAME
				self.body:Push(current.look * (move.Motion.Lunge / seconds), seconds)
			end
		end
	end
end

function CombatClient._onResult(self: CombatClient, seq: number, result: string, hitstop: number)
	local current = self.current
	if not current or current.seq ~= seq then
		if result ~= "Reject" then
			self.lastResult = result
		end
		return
	end
	if result == "Reject" then
		self.lastResult = "Reject"
		self.cooldowns[current.move.CooldownGroup] = nil
		self:_finish(true)
		return
	end
	self.lastResult = result
	current.result = current.result or result
	if hitstop > 0 then
		current.pauseUntil = os.clock() + hitstop
		self.anim:Freeze(hitstop)
	end
end

-- STUN -------------------------------------------------------------------------------------

function CombatClient._updateLock(self: CombatClient)
	local locked = self.character:GetAttribute("Stunned") == true
	if locked == self.locked then
		return
	end
	self.locked = locked
	self.motor:SetSpeedScale("Stun", if locked then 0 else nil)
	self.motor:SetJumpLock("Stun", locked)
	if locked then
		self:_finish(true)
	end
	self:_updateBlockMovement()
end

-- BLOCK ------------------------------------------------------------------------------------

function CombatClient._updateBlockMovement(self: CombatClient)
	local blocking = self.blockHeld and not self.locked
	self.motor:SetSpeedScale("Block", if blocking then Config.BlockMoveSpeedScale else nil)
	self.motor:SetJumpLock("Block", blocking)
	if blocking then
		self.motor:SetSprinting(false)
	end
end

function CombatClient.SetBlock(self: CombatClient, held: boolean)
	if held == self.blockHeld or self.destroyed then
		return
	end
	self.blockHeld = held
	self.remotes.Block:FireServer(held)
	if held and not self.locked and not self.current then
		self.anim:Hold("BlockHold", true)
	elseif not held then
		self.anim:Hold("BlockHold", false)
	end
	self:_updateBlockMovement()
end

-- Shift. Returns true when combat used it (tech roll, or stunned: no dash).
function CombatClient.PressDash(self: CombatClient): boolean
	local state = self.character:GetAttribute("CombatState")
	if state == "Downed" then
		self.remotes.Tech:FireServer()
		local move = self.humanoid.MoveDirection
		local look = self.root.CFrame.LookVector
		local direction = if move.Magnitude > 0.1 then move.Unit else -Vector3.new(look.X, 0, look.Z).Unit
		self.body:Push(direction * Config.TechRollSpeed, Config.TechRollFrames * FRAME)
		return true
	end
	return self.locked
end

-- Tests: no cooldowns, chain back to the start.
function CombatClient.ResetForTest(self: CombatClient)
	self:_finish(true)
	table.clear(self.cooldowns)
	self.chain = 0
	self.chainEndedAt = -math.huge
	self.lastResult = ""
	self.lastAdvantage = nil
end

function CombatClient.Destroy(self: CombatClient)
	if self.destroyed then
		return
	end
	self:_finish(true)
	self.destroyed = true
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.reactions:Destroy()
	self.body:Destroy()
	self.anim:Stop()
	if active[self.character] == self then
		active[self.character] = nil
	end
end

return CombatClient
