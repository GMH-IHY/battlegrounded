--!strict
-- Fighter (ModuleScript)
-- Location: ServerScriptService > Combat > Fighter
--
-- The server's record of one character in a fight (a player or a training dummy): its state
-- machine, the move it's running, blocking and parrying, stamina and burnout, cooldowns, the M1
-- chain, the combo it's taking, status build-up, and the Lotus Fungus (meter, stages, the form,
-- Infested). The server owns all of it; clients only ask (CombatServer) and animate. HitResolver
-- decides what a hit does; Projectiles flies the shots; this module keeps the state.
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
--   Held        caught by a grab or an impale: held still, then thrown / dropped (heldThrow)
-- Every frame (Step) the timers run, a move's active frames look for targets, stamina refills,
-- build-up drains, and the attributes clients read are published.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local Moves = require(Combat:WaitForChild("Moves"))
local Loadout = require(Combat:WaitForChild("Loadout"))
local FungusParts = require(Combat:WaitForChild("FungusParts"))

export type Move = Moves.Move

export type State =
	"Idle"
	| "Blocking"
	| "Attacking"
	| "Stunned"
	| "Blockstun"
	| "Parried"
	| "Launched"
	| "Knockdown"
	| "Downed"
	| "TechRoll"
	| "Held"
	| "Dead"

-- States where you can't act (the "Stunned" attribute clients lock their controls on).
local LOCKED: { [string]: boolean } = {
	Stunned = true,
	Blockstun = true,
	Parried = true,
	Launched = true,
	Knockdown = true,
	Downed = true,
	TechRoll = true,
	Held = true,
	Dead = true,
}
-- Being hit in these states continues the combo.
local IN_COMBO: { [string]: boolean } = {
	Stunned = true,
	Launched = true,
	Knockdown = true,
	Downed = true,
	Held = true,
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
	costPaid: number, -- meter this move cost (refunded by a stage 3 stab's counter-hit)
	followUp: boolean, -- started right after a different Lotus key hit (the move's FollowUp bonus)
	aimPoint: Vector3?, -- where a Targeted move erupts
	projectiles: number, -- shots still flying (a miss is only a miss once they're all gone)
}

-- What touched: a melee hitbox (run = the attacker's move) or a projectile.
export type Hit = {
	move: Move,
	seq: number,
	run: Run?,
	frame: number,
	lastActive: boolean,
	origin: Vector3, -- where the hit comes from (the attacker, or the projectile)
	direction: Vector3?, -- a projectile's flight direction
	projectile: boolean,
	followUp: boolean,
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
	resolve: (attacker: Fighter, target: Fighter, hit: Hit) -> string?,
	-- Fire a move's projectiles (Projectiles).
	shoot: (fighter: Fighter, run: Run) -> (),
	-- An active hitbox is out this frame: things that aren't fighters react to it (Wind turns
	-- projectiles around, any attack knocks down a Moth's lantern).
	sweep: (fighter: Fighter, cframe: CFrame, size: Vector3, move: Move) -> (),
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

	lotus: number,
	formUntil: number,
	formActive: boolean,
	infestedUntil: number,
	lastLotusHit: { slot: string, at: number }?,
	heldThrow: Vector3?,

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

		lotus = 0,
		formUntil = 0,
		formActive = false,
		infestedUntil = 0,
		lastLotusHit = nil,
		heldThrow = nil,

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

-- LOTUS ------------------------------------------------------------------------------------------

function Fighter.IsForm(self: Fighter): boolean
	return self.formActive
end

-- The meter's stage (1-3); the form is always stage 3.
function Fighter.LotusStage(self: Fighter): number
	if self.formActive or self.lotus >= Config.Stage3At then
		return 3
	elseif self.lotus >= Config.Stage2At then
		return 2
	end
	return 1
end

function Fighter.AddMeter(self: Fighter, amount: number)
	self.lotus = math.clamp(self.lotus + amount, 0, Config.LotusMax)
end

function Fighter.SetMeter(self: Fighter, value: number)
	self.lotus = math.clamp(value, 0, Config.LotusMax)
end

function Fighter.IsInfested(self: Fighter): boolean
	return os.clock() < self.infestedUntil
end

-- Takes `amount` HP (x Stage3DamageTaken at stage 3). feeds = the loss feeds the fungus (a hit taken;
-- not your own rip-out or a miss consuming you). Dummies never drop below 1. Returns the HP lost.
function Fighter.TakeDamage(self: Fighter, amount: number, feeds: boolean): number
	if amount <= 0 then
		return 0
	end
	if feeds and self:LotusStage() == 3 then
		amount *= Config.Stage3DamageTaken
	end
	local floor = if self.isDummy then 1 else 0
	local before = self.humanoid.Health
	self.humanoid.Health = math.max(before - amount, floor)
	local lost = before - self.humanoid.Health
	if feeds then
		self:AddMeter(lost * Config.LotusPerDamage)
	end
	return lost
end

function Fighter.Heal(self: Fighter, amount: number)
	self.humanoid.Health = math.min(self.humanoid.Health + amount, self.humanoid.MaxHealth)
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
	local channel = self.run
	if self.state == "Attacking" and channel and channel.move.Channel and table.find(channel.move.CancelInto, move.Id) then
		return "" -- a heal tap turning into the rip-out (they share a cooldown)
	end
	local ready = self.cooldowns[move.CooldownGroup]
	if ready and now < ready - 0.1 then
		return "cooldown"
	end
	if move.Magic == "Lotus" and move.Stage > 0 and move.Stage ~= self:LotusStage() then
		return "stage"
	end
	if move.Id == "Lotus.Form" and (self.lotus < Config.LotusMax or self.formActive) then
		return "meter not full"
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
			if run.move.Channel and table.find(run.move.CancelInto, move.Id) then
				return "" -- a heal tap turning into the rip-out
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
		costPaid = 0,
		followUp = false,
		aimPoint = nil,
		projectiles = 0,
	}
	local run = self.run :: Run
	-- Stage 3 moves spend meter (free in the form).
	if move.MeterCost > 0 and not self.formActive then
		run.costPaid = math.min(move.MeterCost, self.lotus)
		self:AddMeter(-move.MeterCost)
	end
	local last = self.lastLotusHit
	if move.Magic and last and last.slot ~= move.Slot and now - last.at <= Config.FollowUpWindow then
		run.followUp = true
	end
	if move.Targeted then
		run.aimPoint = self:_impaleAim()
		self.hooks.fx({ type = "Patch", attacker = self.character, position = run.aimPoint, seconds = move.Startup * FRAME, move = move.Id })
	end
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
	if run and run.move.WhiffPenalty and run.result == nil and run.projectiles <= 0 then
		self:Consume()
		return
	end
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
	local hasHitbox = move.OnHit.Kind ~= "None" and move.Projectile == nil
	for f = run.lastFrame + 1, frame do
		if f == activeStart then
			self:_activate(run)
			if self.run ~= run then
				return
			end
		end
		if hasHitbox and f >= activeStart and f <= activeEnd then
			self:_checkHits(f, f == activeEnd)
			if self.run ~= run then
				return -- parried out of it
			end
		end
		if move.Channel and f == activeEnd then
			self:EndChannel(true)
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
	local cframe
	if move.Targeted then
		local at = run.aimPoint or self.root.Position
		cframe = CFrame.new(at + Vector3.new(0, move.Hitbox.Size.Y / 2, 0))
	else
		local reach = if run.followUp then move.FollowUpReach else 0
		cframe = self.root.CFrame * CFrame.new(0, move.Hitbox.Up, -(move.Hitbox.Forward + reach / 2))
	end
	local size = move.Hitbox.Size + Vector3.one * (Config.HitboxPad * 2)
	if run.followUp and move.FollowUpReach > 0 then
		size += Vector3.new(0, 0, move.FollowUpReach)
	end
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
	self.hooks.sweep(self, cframe, size, move)
	self.hooks.fx({ type = "Hitbox", cframe = cframe, size = size, hit = next(found) ~= nil })
	for model in found do
		local target = self.hooks.fighterOf(model)
		if target and self.run == run then
			local outcome = self.hooks.resolve(self, target, {
				move = move,
				seq = run.seq,
				run = run,
				frame = frame,
				lastActive = lastActive,
				origin = self.root.Position,
				direction = nil,
				projectile = false,
				followUp = run.followUp,
			})
			if outcome then
				run.hitTargets[model] = true
			end
		end
	end
end

-- The move's first active frame: shots fly, the rip-out and the form happen.
function Fighter._activate(self: Fighter, run: Run)
	local move = run.move
	if move.Projectile then
		self.hooks.shoot(self, run)
	elseif move.Id == "Lotus.RipOut" then
		self:TakeDamage(Config.RipOutHealth, false)
		self:AddMeter(-Config.RipOutMeter)
		self.hooks.fx({ type = "Lotus", what = "RipOut", target = self.character, position = self.root.Position })
	elseif move.Id == "Lotus.Form" then
		self.formActive = true
		self.formUntil = os.clock() + Config.FormTime
		self.hooks.fx({ type = "Lotus", what = "Form", target = self.character, position = self.root.Position })
	end
end

-- The heal channel ends: `full` = it ran its whole length, otherwise R was let go (the share
-- channelled counts). The move goes on to its recovery.
function Fighter.EndChannel(self: Fighter, full: boolean)
	local run = self.run
	if not run or not run.move.Channel or run.result == "Channelled" then
		return
	end
	local move = run.move
	local channelled = math.clamp(self:MoveFrame() - move.Startup + 1, 0, move.Active)
	local share = if full then 1 else channelled / move.Active
	run.result = "Channelled"
	self:Heal(Config.HealHealth * share)
	self:AddMeter(Config.HealMeter * share)
	-- Skip to the recovery.
	run.elapsed = math.max(run.elapsed, (move.Startup + move.Active) * FRAME)
	run.lastFrame = math.max(run.lastFrame, move.Startup + move.Active - 1)
	self.hooks.fx({ type = "Lotus", what = "Heal", target = self.character, position = self.root.Position, share = share })
end

-- R let go.
function Fighter.ReleaseKey(self: Fighter, slot: string)
	local run = self.run
	if slot == "R" and run and run.move.Channel then
		self:EndChannel(false)
	end
end

-- A missed stage 3 move consumes you: HP that doesn't feed the meter, and a stagger.
function Fighter.Consume(self: Fighter)
	self:TakeDamage(Config.WhiffHealth, false)
	self:Interrupt()
	self:SetState("Stunned", Config.WhiffStagger * FRAME)
	self.hooks.react(self, { kind = "Consumed", stun = Config.WhiffStagger * FRAME, hitstop = 0 })
	self.hooks.fx({ type = "Lotus", what = "Consumed", target = self.character, position = self.root.Position })
end

-- A projectile of this fighter's finished (hit or gone).
function Fighter.ProjectileDone(self: Fighter, seq: number)
	local run = self.run
	if run and run.seq == seq then
		run.projectiles = math.max(run.projectiles - 1, 0)
	end
end

-- Where the impale erupts: the floor under the nearest airborne opponent in front within
-- ImpaleRange, else the floor ImpaleRange / 2 ahead.
function Fighter._impaleAim(self: Fighter): Vector3
	local look = self.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local best: Vector3? = nil
	local bestDistance = Config.ImpaleRange
	for _, other in self.hooks.all() do
		if other.character ~= self.character and other.humanoid.Health > 0 and not other:Grounded() then
			local offset = other.root.Position - self.root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude < bestDistance and (flat.Magnitude < 1 or flat.Unit:Dot(flatLook) > 0.3) then
				best, bestDistance = other.root.Position, flat.Magnitude
			end
		end
	end
	local above = best or (self.root.Position + flatLook * (Config.ImpaleRange / 2))
	local ground = Workspace:Raycast(above, Vector3.new(0, -Config.ImpaleFloorSearch, 0), self.castParams)
	return if ground then ground.Position else above - Vector3.new(0, 3, 0)
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
	if state == "Held" and now >= self.stateUntil then
		-- Thrown by the grab / dropped by the impale.
		local throw = self.heldThrow or Vector3.new(0, 20, 0)
		self.heldThrow = nil
		self:Knock("Knockdown")
		self.hooks.react(self, { kind = "Knockdown", velocity = throw, hitstop = 0 })
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
	if self.formActive and now >= self.formUntil then
		self.formActive = false
		self:SetMeter(Config.FormMeterAfter)
		self.hooks.fx({ type = "Lotus", what = "FormEnd", target = self.character, position = self.root.Position })
	end
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
	self:_set("Lotus", math.floor(self.lotus + 0.5))
	self:_set("LotusStage", self:LotusStage())
	if not self.isDummy then
		FungusParts.SetStage(self.character, self:LotusStage(), self.formActive)
	end
	self:_set("LotusForm", self.formActive)
	self:_set("Infested", now < self.infestedUntil)
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
		lotus = self.lotus,
		stage = self:LotusStage(),
		form = self.formActive,
		infested = self:IsInfested(),
		followUp = if run then run.followUp else false,
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
