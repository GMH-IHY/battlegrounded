--!strict
-- AnimationConfig (ModuleScript)
-- Location: ReplicatedStorage > Movement > AnimationConfig
--
-- Which animation plays for each movement, and how its playback speed follows your speed.
--
-- ANIMATIONS ARE LOCAL (nothing is published for now): every name below plays the KeyframeSequence
-- of the same name from ServerStorage > RBX_ANIMSAVES > AnimRig_R6 (tools/animations/build.py
-- writes them there; StudioAnimationMirror copies them where clients can read them), so any edit
-- you save in the Animation Editor shows up the next time you press Play. Roblox only plays
-- unpublished animations in Studio, so they don't play on a live server.

local AnimationConfig = {
	-- Every animation the game plays (tests check this list against tools/animations/catalog.py).
	Names = {
		Idle = true,
		WalkForward = true,
		Sprint = true,
		Jump = true,
		Fall = true,
		Climb = true,
		-- Transitions Animate plays between the loops above.
		WalkStart = true,
		SprintStart = true,
		SprintTurn = true,
		LandLight = true,
		LandRun = true,
		DashForward = true,
		DashLeft = true,
		DashRight = true,
		DashBack = true,
		-- Played by WallHop by which side the wall is on (Right = wall on your right).
		WallRunRight = true,
		WallRunLeft = true,
		WallHopRight = true,
		WallHopLeft = true,
		-- Optional: played by LandingRoll if it exists.
		LandingRoll = true,
		-- Optional: played by AutoParkour if they exist ("Vault" also plays for a step-up).
		Vault = true,
		LedgeClimb = true,
		Slide = true,
		-- Moth race (Lantern): wings rest loop, flights, lantern.
		MothWings = true,
		MothWingFlight = true,
		MothFly = true,
		LanternCharge = true,
		LanternThrow = true,
		LanternSuspend = true,
		-- Sword (ReplicatedStorage > Combat > MoveSets > Sword): the M1 chain, launcher, lunge, 1, air moves.
		M1Swing1 = true,
		M1Swing2 = true,
		M1Swing3 = true,
		SwordLauncher = true,
		SwordLunge = true,
		SwordOne = true,
		SwordAirSlash1 = true,
		SwordAirSlash2 = true,
		SwordAirSpike = true,
		SwordAirOne = true,
		-- Dagger (MoveSets > Dagger).
		DaggerStab = true,
		DaggerAirSlash = true,
		-- Defence.
		BlockHold = true,
		BlockImpact = true,
		Parry = true,
		Parried = true,
		-- Hit reactions (CombatReactions).
		HitStun1 = true,
		HitStun2 = true,
		HitAir = true,
		Knockback = true,
		Launched = true,
		Downed = true,
		GetUp = true,
		TechRoll = true,
		-- Wind (MoveSets > Wind): the Q push and pull.
		WindPush = true,
		WindPull = true,
		-- Lotus Fungus (MoveSets > Lotus): the fungus arm, being held, being consumed.
		LotusStab = true,
		LotusStrand = true,
		LotusHeavyStab = true,
		LotusImpale = true,
		LotusSporeFlick = true,
		LotusSporeFan = true,
		LotusBeam = true,
		LotusGrab = true,
		LotusFeast = true,
		LotusHeld = true,
		LotusHeal = true,
		LotusRipOut = true,
		LotusForm = true,
		LotusConsumed = true,
	} :: { [string]: boolean },

	-- Where the local animations are read from.
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
