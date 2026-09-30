--!strict
-- CombatConfig (ModuleScript)
-- Location: ReplicatedStorage > Combat > CombatConfig
--
-- The global combat rules (docs/MoveData.md, "Global rules" and "Stamina"). Frame counts are at
-- 60 per second. Each move's own numbers live in MoveSets (Sword, Dagger).

local CombatConfig = {
	FPS = 60,

	MaxHealth = 100,

	-- BLOCK AND PARRY (F) ----------------------------------------------------------------------
	-- Holding F blocks from this many frames after the press. A press during stun is kept: you
	-- block the moment the stun ends. Blocking only covers the front half (the attacker must be
	-- in front of you).
	BlockStartup = 1,
	-- Each press of F while you can act opens a parry window. A hit landing in it is parried.
	ParryWindow = 6,
	-- A window that ends without parrying anything means no new window for this many frames
	-- (holding F still blocks), so mashing F doesn't parry.
	ParryWhiffLockout = 20,
	-- Extra window for the defender's ping (seconds, capped): the press left their machine that
	-- much earlier than the server saw it.
	ParryPingAllowance = 0.05,
	-- Your attack got parried: you're stuck this long (frames), the defender is free at once.
	ParryStun = 20,
	-- Walking speed while blocking (share of walk speed).
	BlockMoveSpeedScale = 0.4,
	-- How far a blocked hit pushes the blocker back (studs).
	BlockPushback = 2.5,

	-- HITS ---------------------------------------------------------------------------------------
	-- A hit on someone in the startup or active frames of their own move.
	CounterHitStun = 8,
	CounterHitDamage = 1.2,
	-- Each hit after the first in a combo takes this much off the stun (frames), down to MinStun.
	StunDecay = 2,
	MinStun = 6,
	-- Damage scaling: from the ScalingFrom-th hit of a combo, x ScalingPerHit per hit, never
	-- below ScalingMin. Moves after a linker (sword 1) do x AfterLinker.
	ScalingFrom = 4,
	ScalingPerHit = 0.85,
	ScalingMin = 0.4,
	AfterLinker = 0.8,
	-- Hit pause (frames): both characters freeze on a hit so it lands. Moves can set their own.
	Hitstop = 4,
	BlockHitstop = 3,
	-- Every hitbox is this much bigger on each side on the server (small lag compensation).
	HitboxPad = 0.75,

	-- KNOCKDOWNS ---------------------------------------------------------------------------------
	-- One launch per combo; any later launch is a normal knockdown.
	LaunchesPerCombo = 1,
	-- A launched target is helpless this long (frames), then can act again in the air.
	LaunchStun = 50,
	-- On the floor after a knockdown lands (frames), invincible for the first GetUpInvincible.
	-- Dash (Shift) on the floor = tech roll: TechRollFrames of invincible roll, then you're up.
	GetUpFrames = 30,
	GetUpInvincible = 10,
	TechRollFrames = 14,
	TechRollSpeed = 36, -- studs/s
	-- A knockdown ends at the latest this long after the hit (frames), landed or not.
	MaxAirborne = 240,
	-- The first frames after a knockdown hit never count as landing (the target leaves the floor).
	MinAirborne = 8,

	-- STAMINA (the Drive gauge) --------------------------------------------------------------------
	StaminaMax = 100,
	-- Refill per second, after StaminaRegenDelay seconds without spending.
	StaminaRegenDelay = 0.9,
	StaminaRegenGround = 15,
	StaminaRegenAir = 6,
	-- Blocking a hit costs damage x this.
	BlockStaminaPerDamage = 2.5,
	ParryStaminaGain = 10,
	-- Burnout: after overdrawing. No stamina actions; blocked hits deal this share as chip damage;
	-- refills this much faster; ends only when the meter is full again.
	BurnoutChip = 0.25,
	BurnoutRegenScale = 1.25,
	-- Stamina a client may spend per second through the Stamina remote (race mobility). Anything
	-- beyond is ignored.
	StaminaSpendRateLimit = 120,

	-- DAMAGE BUDGET (docs/DesignPlan.md): a normal confirm does about 15-20, the best stage 3 confirm
	-- at most 35, anything with an ultimate at most 45 (of 100 HP). The HUD's combo counter turns
	-- yellow / red past these; tools/combo.py checks the example routes against them.
	BudgetNormal = 20,
	BudgetStage3 = 35,
	BudgetMax = 45,

	-- STATUS BUILD-UP ------------------------------------------------------------------------------
	-- Each fighter has a bar for the element of whoever builds it. Winning exchanges fill it.
	BuildupMax = 100,
	BuildupParry = 40,
	BuildupCounterHit = 35,
	-- Drains this much per second once nobody has landed an M1 or Q on them for BuildupDrainDelay.
	BuildupDrain = 15,
	BuildupDrainDelay = 2,
	-- After a status triggers, the bar can't fill for this long (seconds).
	BuildupLockout = 6,
	-- Wind's status. Drafted: the next launch goes x DraftedLaunchScale as high, or the next
	-- knockdown keeps you down DraftedDownFrames longer. Lasts DraftedTime seconds or until used.
	DraftedTime = 5,
	DraftedLaunchScale = 1.5,
	DraftedDownFrames = 36,

	-- M1 CHAIN -------------------------------------------------------------------------------------
	-- After an M1 ends, the next click continues the chain within this long (seconds); later, the
	-- chain starts over. After the third hit it always starts over.
	ChainWindow = 0.6,
	-- Walking speed while attacking (share of walk speed).
	AttackMoveSpeedScale = 0.45,
	-- A request that arrives this many frames before the current move ends is kept and started
	-- the moment it can (the server's view of timing is a little behind the attacker's).
	ServerBuffer = 8,
	-- The server aims a move's hitbox where the attacker's client swung (its soft lock turns you
	-- before the server sees it), if that's within this many degrees of where the server sees them
	-- facing.
	AimTrust = 75,
	-- Input buffer: a key pressed while you can't act yet (a move still playing, stunned, blockstun)
	-- is kept this many frames and comes out the first frame you can, so presses a little early
	-- (or before the server confirmed a hit to cancel from) aren't lost.
	InputBuffer = 10,
	-- Soft lock: an attack started with an opponent within this range and this angle of where you
	-- face turns you toward them.
	AimAssistRange = 12,
	AimAssistAngle = 70,

	-- LOTUS FUNGUS (docs/MoveData.md) -------------------------------------------------------------
	LotusMax = 100,
	-- Stage 2 from this much meter, stage 3 from Stage3At.
	Stage2At = 40,
	Stage3At = 80,
	-- Taking damage feeds the fungus: meter per HP lost.
	LotusPerDamage = 0.5,
	-- R held: the heal channel. A full channel (its Active frames) gives HealHealth and HealMeter;
	-- letting go early gives the share you channelled. Letting go within RipOutFrames of pressing is a
	-- tap: rip it out instead (-RipOutHealth, -RipOutMeter).
	HealHealth = 6,
	HealMeter = 20,
	RipOutFrames = 10,
	RipOutHealth = 10,
	RipOutMeter = 25,
	-- At stage 3 (or in the form) you take this much more damage.
	Stage3DamageTaken = 1.25,
	-- Missing a stage 3 move: HP lost (never feeds the meter) and a stagger (frames).
	WhiffHealth = 8,
	WhiffStagger = 20,
	-- G: the stage 3 form lasts this long (seconds); stage 3 moves cost no meter meanwhile. After it the
	-- meter is FormMeterAfter.
	FormTime = 8,
	FormMeterAfter = 20,
	-- Follow-ups: a Lotus move started this soon (seconds) after a different Lotus key landed a hit gets
	-- its FollowUpStun / FollowUpReach bonus.
	FollowUpWindow = 1,
	-- Infested (the stage 2 spores): the next Lotus move (not a spore) that hits their block wraps them
	-- in growth: knocked down WrapFrames. Lasts InfestedTime seconds or until used.
	InfestedTime = 6,
	WrapFrames = 60,
	-- The impale finds an airborne opponent in front within this range (studs).
	ImpaleRange = 25,
	-- How far below the target the impale looks for the floor its growth erupts from (studs).
	ImpaleFloorSearch = 40,

	-- TRAINING DUMMIES -------------------------------------------------------------------------------
	-- Health comes back this long after the last hit (seconds).
	DummyResetTime = 3,
}

return CombatConfig
