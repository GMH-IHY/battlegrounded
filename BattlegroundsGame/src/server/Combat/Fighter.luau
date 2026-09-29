--!strict
-- Fighter (ModuleScript)
-- Location: ServerScriptService > Combat > Fighter
--
-- The server's record of one character in a fight (a player or a training dummy): its state
-- machine, the move it's running, blocking and parrying, stamina and burnout, cooldowns, the M1
-- chain, the combo it's taking, status build-up. The server owns all of it; clients only ask
-- (CombatServer) and animate. HitResolver decides what a hit does; this module keeps the state.
--
-- States ("CombatState" attribute):
--   Idle        free to act
--   Blocking    guard up (F held, BlockStartup frames after the press)
--   Attacking   running a move (its phase is the move's frame math, Moves.PhaseAt)
--   Stunned     hit stun (can't act); a held F becomes a block the frame it ends
--   Blockstun   blocked a hit: guard stays up, can't act
--   Parried     your attack got parried
--   Launched    sent up by a launcher: helpless for LaunchStun frames, then free in the air
--   Knockdown   knocked down and flying until landing
--   Downed      on the floor for GetUpFrames (invincible at first); Shift = tech roll
--   TechRoll    rolling out of a knockdown (invincible)
-- Every frame (Step) the timers run, a move's active frames look for targets, stamina refills,
-- build-up drains, and the attributes clients read are published.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local Moves = require(Combat:WaitForChild("Moves"))
local Loadout = require(Combat:WaitForChild("Loadout"))

type Move = Moves.Move

export type State = "Idle" | "Blocking" | "Attacking" | "Stunned" | "Blockstun" | "Parried" | "Launched" | "Knockdown" | "Downed" | "TechRoll" | "Dead"

-- States where you can't act (the "Stunned" attribute clients lock their controls on).
local LOCKED: { [string]: boolean } = {
	Stunned = true,
	Blockstun = true,
	Parried = true,
	Launched = true,
	Knockdown = true,
	Downed = true,
	TechRoll = true,
	Dead = true,
}
-- Being hit in these states continues the combo.
local IN_COMBO: { [string]: boolean } = {
	Stunned = true,
	Launched = true,
	Knockdown = true,
	Downed = true,
}

local FRAME = 1 / Config.FPS

export type Run = {
	move: Move,
	seq: number,
	elapsed: number, -- seconds into the move, not counting hit pause
	pauseUntil: number,
	lastFrame: number, -- the last frame already processed
	hitTargets: { [Model]: boolean },
	result: string?, -- "Hit" / "Counter" / "Block" / "Armour" once it touched someone
	hitConfirmed: boolean, -- landed a real hit (cancels open up)
	armour: number,
}

export type Combo = {
	hits: number,
	launches: number,
	afterLinker: boolean,
	damage: number,
}

export type Hooks = {
	-- Tell the owning client (or the dummy controller) to react: stun, knockback, block, parried...
	react: (fighter: Fighter, info: { [string]: any }) -> (),
	-- Tell the attacker's client how its move went.
	result: (fighter: Fighter, seq: number, result: string, hitstop: number, advantage: number?) -> (),
	-- Effects for everyone.
	fx: (info: { [string]: any }) -> (),
	-- Every other fighter, for hit detection.
	all: () -> { Fighter },
	fighterOf: (model: Model) -> Fighter?,
	resolve: (attacker: Fighter, target: Fighter, frame: number, lastActive: boolean) -> string?,
}

local Fighter = {}
Fighter.__index = Fighter

type Data = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	isDummy: boolean,
	hooks: Hooks,

	state: State,
	stateUntil: number,
	run: Run?,
	queued: { moveId: string, seq: number }?,
	cooldowns: { [string]: number },
	chain: number,
	chainEndedAt: number,

	blockHeld: boolean,
	blockPressedAt: number,
	parryUntil: number,
	parryLockUntil: number,

	stamina: number,
	burnout: boolean,
	lastSpend: number,
	spendWindow: { { at: number, amount: number } },

	combo: Combo,
	knockSince: number,
	downExtra: number,
	invulnerableUntil: number,
	lastHitAt: number,

	element: string,
	buildup: number,
	buildupAt: number,
	buildupLockUntil: number,
	draftedUntil: number,

	castParams: RaycastParams,
	published: { [string]: any },
	lastStep: number,
	lastResult: string,
	lastAdvantage: number?,
}

export type Fighter = typeof(setmetatable({} :: Data, Fighter))

function Fighter.new(character: Model, player: Player?, hooks: Hooks): Fighter
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.FilterDescendantsInstances = { character }
	castParams.RespectCanCollide = true
	local element = character:GetAttribute("Element")
	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		player = player,
		isDummy = player == nil,
		hooks = hooks,

		state = "Idle" :: State,
		stateUntil = 0,
		run = nil,
		queued = nil,
		cooldowns = {},
		chain = 0,
		chainEndedAt = -math.huge,

		blockHeld = false,
		blockPressedAt = -math.huge,
		parryUntil = 0,
		parryLockUntil = 0,

		stamina = Config.StaminaMax,
		burnout = false,
		lastSpend = -math.huge,
		spendWindow = {},

		combo = { hits = 0, launches = 0, afterLinker = false, damage = 0 },
		knockSince = 0,
		downExtra = 0,
		invulnerableUntil = 0,
		lastHitAt = -math.huge,

		element = if typeof(element) == "string" then element else "Wind",
		buildup = 0,
		buildupAt = -math.huge,
		buildupLockUntil = 0,
		draftedUntil = 0,

		castParams = castParams,
		published = {},
		lastStep = os.clock(),
		lastResult = "",
		lastAdvantage = nil,
	} :: Data, Fighter)
	humanoid.MaxHealth = Config.MaxHealth
	humanoid.Health = Config.MaxHealth
	self:_publish()
	return self
end

-- INFO ------------------------------------------------------------------------------------------

function Fighter.IsLocked(self: Fighter): boolean
	return LOCKED[self.state] == true
end

function Fighter.IsInCombo(self: Fighter): boolean
	return IN_COMBO[self.state] == true
end

function Fighter.GuardUp(self: Fighter): boolean
	return self.state == "Blocking" or self.state == "Blockstun"
end

function Fighter.IsInvulnerable(self: Fighter, now: number): boolean
	return now < self.invulnerableUntil
end

-- Can this fighter parry right now (a window open, and free to act)?
function Fighter.ParryOpen(self: Fighter, now: number): boolean
	return now <= self.parryUntil and (self.state == "Idle" or self.state == "Blocking")
end

-- The frame the current move is on (or -1).
function Fighter.MoveFrame(self: Fighter): number
	local run = self.run
	return if run then math.floor(run.elapsed / FRAME + 1e-6) else -1
end

function Fighter.MovePhase(self: Fighter): string
	local run = self.run
	if not run then
		return "None"
	end
	return Moves.PhaseAt(run.move, self:MoveFrame(), not run.hitConfirmed and run.result == nil)
end

-- Frames left in the current move after `frame` (0 when none).
function Fighter.FramesLeft(self: Fighter, frame: number): number
	local run = self.run
	if not run then
		return 0
	end
	return math.max(Moves.Total(run.move, false) - frame - 1, 0)
end

-- Standing on something (the server's own look: a ray down from the root)?
function Fighter.Grounded(self: Fighter): boolean
	local velocity = self.root.AssemblyLinearVelocity
	if velocity.Y > 2 then
		return false
	end
	local reach = self.humanoid.HipHeight + self.root.Size.Y / 2 + 1.6
	return Workspace:Raycast(self.root.Position, Vector3.new(0, -reach, 0), self.castParams) ~= nil
end

function Fighter.FacingDot(self: Fighter, from: Vector3): number
	local look = self.root.CFrame.LookVector
	local toward = from - self.root.Position
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatToward = Vector3.new(toward.X, 0, toward.Z)
	if flatLook.Magnitude < 1e-3 or flatToward.Magnitude < 1e-3 then
		return 1
	end
	return flatLook.Unit:Dot(flatToward.Unit)
end

-- STATE ------------------------------------------------------------------------------------------

function Fighter.SetState(self: Fighter, state: State, seconds: number?)
	self.state = state
	self.stateUntil = if seconds then os.clock() + seconds else 0
end

-- Ends whatever move is running (hit out of it, parried, died).
function Fighter.Interrupt(self: Fighter)
	self.run = nil
	self.queued = nil
end

-- The state to go back to when a timer ends.
function Fighter._neutral(self: Fighter)
	if self.humanoid.Health <= 0 then
		self:SetState("Dead")
	elseif self.blockHeld and os.clock() - self.blockPressedAt >= Config.BlockStartup * FRAME then
		self:SetState("Blocking")
	else
		self:SetState("Idle")
	end
end

-- MOVES ------------------------------------------------------------------------------------------

-- Why a move can't start right now ("" = it can).
function Fighter.CanStart(self: Fighter, move: Move, now: number): string
	if self.humanoid.Health <= 0 then
		return "dead"
	end
	local ready = self.cooldowns[move.CooldownGroup]
	if ready and now < ready - 0.1 then
		return "cooldown"
	end
	if move.Chain > 1 then
		local current = self.run
		local fromRun = current ~= nil and current.move.Chain == move.Chain - 1
		local fromChain = self.chain == move.Chain - 1 and now - self.chainEndedAt <= Config.ChainWindow + 0.15
		if not (fromRun or fromChain) then
			return "chain"
		end
	end
	if self.state == "Idle" then
		return ""
	end
	if self.state == "Attacking" then
		local run = self.run
		if run then
			if run.hitConfirmed and table.find(run.move.CancelInto, move.Id) then
				return "" -- cancel on hit
			end
			if run.hitConfirmed and run.move.JumpCancel and move.Air then
				return "" -- the launcher's jump follow-up
			end
			local left = self:FramesLeft(self:MoveFrame())
			if left <= Config.ServerBuffer then
				return "queue"
			end
		end
		return "busy"
	end
	return "state " .. self.state
end

-- Starts `moveId` (the client already picked it). Returns "" or why not; "queue" = kept and started
-- when the current move ends.
function Fighter.RequestMove(self: Fighter, moveId: string, seq: number): string
	local move = Moves.Get(moveId)
	if not move then
		return "unknown move"
	end
	if not Loadout.CanPick(move.Slot, move.Id) then
		return "not in loadout"
	end
	local now = os.clock()
	local why = self:CanStart(move, now)
	if why == "queue" then
		self.queued = { moveId = moveId, seq = seq }
		return "queue"
	end
	if why ~= "" then
		return why
	end
	self:_start(move, seq, now)
	return ""
end

function Fighter._start(self: Fighter, move: Move, seq: number, now: number)
	local previous = self.run
	if previous and previous.move.Chain > 0 then
		self.chain = previous.move.Chain
		self.chainEndedAt = now
	end
	self.run = {
		move = move,
		seq = seq,
		elapsed = 0,
		pauseUntil = 0,
		lastFrame = -1,
		hitTargets = {},
		result = nil,
		hitConfirmed = false,
		armour = move.Armour,
	}
	self.queued = nil
	self.parryUntil = 0
	if move.Cooldown > 0 then
		self.cooldowns[move.CooldownGroup] = now + move.Cooldown
	end
	if move.Chain > 0 then
		self.chain = move.Chain
		self.chainEndedAt = math.huge -- running
	end
	self:SetState("Attacking")
	self.character:SetAttribute("Move", move.Id .. "#" .. seq)
end

function Fighter._endRun(self: Fighter)
	local run = self.run
	self.run = nil
	if run and run.move.Chain > 0 then
		self.chain = if run.move.Chain >= 3 then 0 else run.move.Chain
		self.chainEndedAt = os.clock()
	elseif run and run.move.Id == "Sword.Lunge" then
		self.chain = 0
	end
	if self.state == "Attacking" then
		self:_neutral()
	end
	local queued = self.queued
	self.queued = nil
	if queued then
		local why = if self.state == "Idle" then self:RequestMove(queued.moveId, queued.seq) else "state " .. self.state
		if why ~= "" and why ~= "queue" then
			-- The client already started it: tell it to stop.
			self.hooks.result(self, queued.seq, "Reject", 0)
		end
	end
end

-- Pauses the running move for `seconds` (hit pause).
function Fighter.PauseMove(self: Fighter, seconds: number)
	local run = self.run
	if run then
		run.pauseUntil = math.max(run.pauseUntil, os.clock() + seconds)
	end
end

function Fighter._stepMove(self: Fighter, now: number, dt: number)
	local run = self.run
	if not run then
		return
	end
	if now < run.pauseUntil then
		return
	end
	run.elapsed += dt
	local frame = self:MoveFrame()
	local move = run.move
	local whiff = run.result == nil
	local total = Moves.Total(move, whiff)
	-- Every frame between the last processed one and this one (a slow server frame can skip one).
	local activeStart, activeEnd = move.Startup, move.Startup + move.Active - 1
	for f = run.lastFrame + 1, frame do
		if f >= activeStart and f <= activeEnd then
			self:_checkHits(f, f == activeEnd)
			if self.run ~= run then
				return -- parried out of it
			end
		end
	end
	run.lastFrame = frame
	if frame >= total then
		self:_endRun()
	end
end

function Fighter._checkHits(self: Fighter, frame: number, lastActive: boolean)
	local run = self.run
	if not run then
		return
	end
	local move = run.move
	local cframe = Moves.HitboxCFrame(move, self.root.CFrame)
	local size = move.Hitbox.Size + Vector3.one * (Config.HitboxPad * 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local others: { Instance } = {}
	for _, other in self.hooks.all() do
		if other.character ~= self.character and other.humanoid.Health > 0 then
			table.insert(others, other.character)
		end
	end
	params.FilterDescendantsInstances = others
	local found: { [Model]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInBox(cframe, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and not found[model] and not run.hitTargets[model] then
			found[model] = true
		end
	end
	self.hooks.fx({ type = "Hitbox", cframe = cframe, size = size, hit = next(found) ~= nil })
	for model in found do
		local target = self.hooks.fighterOf(model)
		if target and self.run == run then
			local outcome = self.hooks.resolve(self, target, frame, lastActive)
			if outcome then
				run.hitTargets[model] = true
			end
		end
	end
end

-- BLOCK AND PARRY ------------------------------------------------------------------------------

function Fighter.SetBlock(self: Fighter, held: boolean)
	local now = os.clock()
	if held == self.blockHeld then
		return
	end
	self.blockHeld = held
	if held then
		self.blockPressedAt = now
		-- A fresh press while free to act opens a parry window (unless a whiffed one locked it out).
		if (self.state == "Idle" or self.state == "Blocking") and now >= self.parryLockUntil then
			local ping = 0
			local player = self.player
			if player then
				ping = math.min(player:GetNetworkPing(), Config.ParryPingAllowance)
			end
			self.parryUntil = now + Config.ParryWindow * FRAME + ping
		end
		if self.state == "Idle" and Config.BlockStartup <= 0 then
			self:SetState("Blocking")
		end
	else
		if self.state == "Blocking" then
			self:SetState("Idle")
		end
	end
end

-- A parry landed: the window is used up (no whiff lockout).
function Fighter.ConsumeParry(self: Fighter)
	self.parryUntil = 0
end

-- STAMINA ------------------------------------------------------------------------------------------

-- Takes `amount` even if there isn't enough (overdraw): at 0 you're in burnout.
function Fighter.DrainStamina(self: Fighter, amount: number)
	if amount <= 0 then
		return
	end
	self.stamina -= amount
	self.lastSpend = os.clock()
	if self.stamina <= 0 then
		self.stamina = 0
		self.burnout = true
	end
end

-- A voluntary spend (race mobility, from the client). Nothing in burnout; limited per second.
function Fighter.SpendStamina(self: Fighter, amount: number): boolean
	if self.burnout or amount <= 0 or amount ~= amount then
		return false
	end
	local now = os.clock()
	local recent = 0
	for i = #self.spendWindow, 1, -1 do
		local entry = self.spendWindow[i]
		if now - entry.at > 1 then
			table.remove(self.spendWindow, i)
		else
			recent += entry.amount
		end
	end
	if recent + amount > Config.StaminaSpendRateLimit then
		return false
	end
	table.insert(self.spendWindow, { at = now, amount = amount })
	self:DrainStamina(amount)
	return true
end

function Fighter.GainStamina(self: Fighter, amount: number)
	self.stamina = math.min(self.stamina + amount, Config.StaminaMax)
end

function Fighter.SetStamina(self: Fighter, value: number)
	self.stamina = math.clamp(value, 0, Config.StaminaMax)
	self.burnout = self.stamina <= 0
	self.lastSpend = os.clock() -- counts as a change: the refill waits its delay
end

function Fighter._stepStamina(self: Fighter, now: number, dt: number)
	if self.stamina >= Config.StaminaMax then
		self.stamina = Config.StaminaMax
		self.burnout = false
		return
	end
	if now - self.lastSpend < Config.StaminaRegenDelay then
		return
	end
	local rate = if self:Grounded() then Config.StaminaRegenGround else Config.StaminaRegenAir
	if self.burnout then
		rate *= Config.BurnoutRegenScale
	end
	self.stamina = math.min(self.stamina + rate * dt, Config.StaminaMax)
	if self.stamina >= Config.StaminaMax then
		self.burnout = false
	end
end

-- STATUS BUILD-UP --------------------------------------------------------------------------------

-- Adds build-up from an attacker whose element is `element`. Returns the status that triggered, if any.
function Fighter.AddBuildup(self: Fighter, amount: number, element: string): string?
	local now = os.clock()
	if amount <= 0 or now < self.buildupLockUntil then
		return nil
	end
	self.buildup = math.min(self.buildup + amount, Config.BuildupMax)
	self.buildupAt = now
	if self.buildup < Config.BuildupMax then
		return nil
	end
	self.buildup = 0
	self.buildupLockUntil = now + Config.BuildupLockout
	if element == "Wind" then
		self.draftedUntil = now + Config.DraftedTime
		return "Drafted"
	end
	return nil
end

function Fighter.IsDrafted(self: Fighter): boolean
	return os.clock() < self.draftedUntil
end

function Fighter.UseDrafted(self: Fighter)
	self.draftedUntil = 0
end

function Fighter._stepBuildup(self: Fighter, now: number, dt: number)
	if self.buildup > 0 and now - self.buildupAt > Config.BuildupDrainDelay then
		self.buildup = math.max(self.buildup - Config.BuildupDrain * dt, 0)
	end
end

-- KNOCKDOWNS -------------------------------------------------------------------------------------

function Fighter.Knock(self: Fighter, state: State, seconds: number?, downExtraFrames: number?)
	self:Interrupt()
	self:SetState(state, seconds)
	self.knockSince = os.clock()
	self.downExtra = downExtraFrames or 0
end

-- Shift while downed: roll out.
function Fighter.TechRoll(self: Fighter): boolean
	if self.state ~= "Downed" then
		return false
	end
	local seconds = Config.TechRollFrames * FRAME
	self:SetState("TechRoll", seconds)
	self.invulnerableUntil = os.clock() + seconds
	return true
end

function Fighter._stepTimers(self: Fighter, now: number)
	local state = self.state
	if state == "Dead" then
		return
	end
	if self.humanoid.Health <= 0 then
		self:Interrupt()
		self:SetState("Dead")
		return
	end
	if state == "Knockdown" then
		local airborne = now - self.knockSince
		local landed = airborne >= Config.MinAirborne * FRAME and self:Grounded()
		if landed or airborne >= Config.MaxAirborne * FRAME then
			local frames = Config.GetUpFrames + self.downExtra
			self:SetState("Downed", frames * FRAME)
			self.invulnerableUntil = now + Config.GetUpInvincible * FRAME
		end
		return
	end
	if (state == "Stunned" or state == "Blockstun" or state == "Parried" or state == "Launched" or state == "Downed" or state == "TechRoll")
		and now >= self.stateUntil
	then
		if state ~= "Blockstun" then
			self.combo = { hits = 0, launches = 0, afterLinker = false, damage = 0 }
		end
		self:_neutral()
		return
	end
	if state == "Idle" and self.blockHeld and now - self.blockPressedAt >= Config.BlockStartup * FRAME then
		self:SetState("Blocking")
	elseif state == "Blocking" and not self.blockHeld then
		self:SetState("Idle")
	end
	-- A parry window that ran out without a parry: no new window for a while.
	if self.parryUntil > 0 and now > self.parryUntil then
		self.parryLockUntil = self.parryUntil + Config.ParryWhiffLockout * FRAME
		self.parryUntil = 0
	end
end

-- EVERY FRAME ------------------------------------------------------------------------------------

function Fighter.Step(self: Fighter, now: number)
	local dt = math.min(now - self.lastStep, 0.1)
	self.lastStep = now
	self:_stepTimers(now)
	if self.state == "Attacking" then
		self:_stepMove(now, dt)
	elseif self.run then
		self.run = nil
	end
	if self.state ~= "Attacking" and self.character:GetAttribute("Move") ~= nil then
		self.character:SetAttribute("Move", nil)
	end
	self:_stepStamina(now, dt)
	self:_stepBuildup(now, dt)
	self:_publish()
end

function Fighter._set(self: Fighter, name: string, value: any)
	if self.published[name] ~= value then
		self.published[name] = value
		self.character:SetAttribute(name, value)
	end
end

function Fighter._publish(self: Fighter)
	local now = os.clock()
	self:_set("CombatState", self.state)
	self:_set("Stunned", self:IsLocked())
	self:_set("Guard", self:GuardUp())
	self:_set("Stamina", math.floor(self.stamina + 0.5))
	self:_set("StaminaMax", Config.StaminaMax)
	self:_set("Burnout", self.burnout)
	self:_set("Buildup", math.floor(self.buildup + 0.5))
	self:_set("Drafted", now < self.draftedUntil)
	self:_set("Invulnerable", now < self.invulnerableUntil)
	self:_set("ComboHits", self.combo.hits)
	self:_set("ComboDamage", math.floor(self.combo.damage * 10 + 0.5) / 10)
	for group, ready in self.cooldowns do
		-- Attribute names allow letters, digits and _ only: "Sword.One" -> "Cooldown_Sword_One".
		-- The value is the server clock (Workspace:GetServerTimeNow) when it's ready again.
		local left = ready - now
		self:_set("Cooldown_" .. string.gsub(group, "%W", "_"), if left > 0 then Workspace:GetServerTimeNow() + left else nil)
	end
end

-- A snapshot for the Studio test panel.
function Fighter.Snapshot(self: Fighter): { [string]: any }
	local run = self.run
	return {
		state = self.state,
		move = if run then run.move.Id else nil,
		frame = self:MoveFrame(),
		phase = self:MovePhase(),
		stamina = self.stamina,
		burnout = self.burnout,
		health = self.humanoid.Health,
		comboHits = self.combo.hits,
		comboDamage = self.combo.damage,
		launches = self.combo.launches,
		buildup = self.buildup,
		drafted = self:IsDrafted(),
		chain = self.chain,
		blockHeld = self.blockHeld,
		parryOpen = self:ParryOpen(os.clock()),
		invulnerable = self:IsInvulnerable(os.clock()),
		lastResult = self.lastResult,
		lastAdvantage = self.lastAdvantage,
	}
end

return Fighter
