--!strict
-- AnimationConfig (ModuleScript)
-- Location: ReplicatedStorage > Movement > AnimationConfig
--
-- Which animation plays for each movement, and how its playback speed follows your speed.
--
-- PUBLISHED IDS: paste each animation's ID here after publishing it (either "rbxassetid://123"
-- or just the number). While an ID is empty, Studio playtests use the KeyframeSequence of the
-- same name from ServerStorage > RBX_ANIMSAVES > AnimRig_R6 instead, so any edit you save in
-- the Animation Editor shows up the next time you press Play. Those Studio copies only work in
-- Studio: a live server needs every ID filled in.

local AnimationConfig = {
	Ids = {
		Idle = "",
		WalkForward = "",
		Sprint = "",
		Jump = "",
		Fall = "",
		Climb = "",
		-- Transitions Animate plays between the loops above.
		WalkStart = "",
		SprintStart = "",
		SprintTurn = "",
		LandLight = "",
		LandRun = "",
		DashForward = "",
		DashLeft = "",
		DashRight = "",
		DashBack = "",
		-- Played by WallHop by which side the wall is on (Right = wall on your right).
		WallRunRight = "",
		WallRunLeft = "",
		WallHopRight = "",
		WallHopLeft = "",
		-- Optional: played by LandingRoll if it exists.
		LandingRoll = "",
		-- Optional: played by AutoParkour if they exist ("Vault" also plays for a step-up).
		Vault = "",
		LedgeClimb = "",
		Slide = "",
		-- Moth race (Lantern): wings rest loop, flights, lantern.
		MothWings = "",
		MothWingFlight = "",
		MothFly = "",
		LanternCharge = "",
		LanternThrow = "",
		LanternSuspend = "",
		-- Sword (ReplicatedStorage > Combat > MoveSets > Sword): the M1 chain, launcher, lunge, 1, air moves.
		M1Swing1 = "",
		M1Swing2 = "",
		M1Swing3 = "",
		SwordLauncher = "",
		SwordLunge = "",
		SwordOne = "",
		SwordAirSlash1 = "",
		SwordAirSlash2 = "",
		SwordAirSpike = "",
		SwordAirOne = "",
		-- Dagger (MoveSets > Dagger).
		DaggerStab = "",
		DaggerAirSlash = "",
		-- Defence.
		BlockHold = "",
		BlockImpact = "",
		Parry = "",
		Parried = "",
		-- Hit reactions (CombatReactions).
		HitStun1 = "",
		HitStun2 = "",
		HitAir = "",
		Knockback = "",
		Launched = "",
		Downed = "",
		GetUp = "",
		TechRoll = "",
		-- Lotus Fungus (MoveSets > Lotus): the fungus arm, being held, being consumed.
		LotusStab = "",
		LotusStrand = "",
		LotusHeavyStab = "",
		LotusImpale = "",
		LotusSporeFlick = "",
		LotusSporeFan = "",
		LotusBeam = "",
		LotusGrab = "",
		LotusFeast = "",
		LotusHeld = "",
		LotusHeal = "",
		LotusRipOut = "",
		LotusForm = "",
		LotusConsumed = "",
	} :: { [string]: string },

	-- Where Studio playtests read unpublished animations from.
	StudioRigName = "AnimRig_R6",
	StudioAnimationsFolder = "StudioAnimations",

	-- Crossfade between animations, in seconds. 0 = snap, to match the constant-easing style.
	FadeTime = 0,

	-- Ground speeds (studs/s) the animations were made for. At these speeds they play at
	-- normal rate; faster or slower movement speeds them up or slows them down.
	WalkAnimSpeed = 14,
	SprintAnimSpeed = 26,
	-- Climb speed (studs/s) that plays the climb at normal rate. Standing still on a truss
	-- freezes the climb pose; climbing down plays it backward.
	ClimbAnimSpeed = 10,
	MinPlaybackRate = 0.5,
	MaxPlaybackRate = 1.6,

	-- Below this ground speed you're standing still (Idle).
	IdleSpeed = 1,

	-- Short drops (stairs, small ledges) don't switch to Fall until you've been airborne this
	-- long, or you're falling faster than FallSpeedThreshold.
	FallDelay = 0.12,
	FallSpeedThreshold = 12,

	-- HEAD LOOK -------------------------------------------------------------
	-- The head turns a little toward where your camera points. Other players see it too.
	-- OFF at Isaac's request (Sep 26). Set to true to bring it back; everything below still works.
	-- It's meant to be subtle, and it moves in steps like the animations instead of gliding.
	HeadLookEnabled = false,
	-- Share of the camera's angle the head follows (1 = look straight where the camera looks).
	HeadYawScale = 0.3,
	HeadPitchScale = 0.3,
	-- Furthest the head turns left/right and up/down from the body, in degrees.
	HeadMaxYaw = 25,
	HeadMaxPitch = 12,
	-- The head jumps to a new angle at most this often (seconds), then holds it.
	-- Matches the ~0.1 s pose rate of the animations.
	HeadStepInterval = 0.12,
	-- Changes smaller than this (degrees) are ignored, so the head doesn't twitch.
	HeadMinStep = 2,
	-- How often your head direction is sent to the server (per second).
	HeadLookSendRate = 10,
}

return AnimationConfig
