--!strict
-- SoundConfig (ModuleScript)
-- Location: ReplicatedStorage > Movement > SoundConfig
--
-- Every sound, by name. Code only ever plays these names (through Sfx), so swapping a sound is a
-- one-line change here.
-- SOUNDS ARE LOCAL (nothing is published for now): they're Sound objects in the place, in
-- ReplicatedStorage > Sounds. Sfx finds each one there by its name here (e.g. "Dash") or by its
-- file name without the extension (e.g. "universeDash", which is what importing the audio folder
-- into Studio creates), so importing the audio folder once is enough. A missing one is skipped
-- quietly; in Studio the server lists every missing file once at the start of a playtest.
--   File     = the source audio file (Downloads\audio).
--   Volume   = base volume. Speed = base PlaybackSpeed. Looped = plays until stopped.
--   Vary     = random +- PlaybackSpeed each play so repeats don't sound identical.
--   Range    = RollOffMaxDistance (studs) other players can hear it from.

export type Entry = {
	File: string,
	Volume: number,
	Speed: number?,
	Looped: boolean?,
	Vary: number?,
	Range: number?,
}

local S: { [string]: Entry } = {
	-- BASIC MOVEMENT --------------------------------------------------------------
	Footsteps = { File = "universeFootStepLoop.ogg", Volume = 0.45, Looped = true, Range = 60 },
	Jump = { File = "universeJump.wav", Volume = 0.5, Vary = 0.05 },
	Land = { File = "universeLand.wav", Volume = 0.55, Vary = 0.05 },
	FallWind = { File = "universeFalling.ogg", Volume = 0.6, Looped = true, Range = 50 },

	-- DASH ------------------------------------------------------------------------
	Dash = { File = "universeDash.ogg", Volume = 0.7, Vary = 0.06, Range = 90 },

	-- COMBAT (move data picks the swing / hit sound: MoveSets Fx.Swing / Fx.Hit) --------------
	SwordSwing = { File = "universeSwoosh.ogg", Volume = 0.6, Speed = 1.25, Vary = 0.08, Range = 80 },
	SwordSwingHeavy = { File = "universeHeavySwing.ogg", Volume = 0.7, Vary = 0.06, Range = 90 },
	SwordHit = { File = "universeClash2.ogg", Volume = 0.75, Speed = 1.15, Vary = 0.06, Range = 100 },
	SwordHitHeavy = { File = "universeClash.ogg", Volume = 0.85, Vary = 0.05, Range = 110 },
	DaggerSwing = { File = "universeSwoosh.ogg", Volume = 0.5, Speed = 1.6, Vary = 0.08, Range = 70 },
	DaggerHit = { File = "universeClash2.ogg", Volume = 0.6, Speed = 1.5, Vary = 0.06, Range = 90 },
	CounterHit = { File = "universeHeavySwing2.ogg", Volume = 0.6, Speed = 0.7, Range = 100 },
	Block = { File = "universeClash.ogg", Volume = 0.6, Speed = 1.5, Vary = 0.05, Range = 90 },
	Parry = { File = "sparkles.ogg", Volume = 0.9, Speed = 1.3, Range = 120 },

	-- LOTUS FUNGUS (placeholders from the existing files until it has its own sounds) ------------
	FungusSwing = { File = "universeSwoosh.ogg", Volume = 0.55, Speed = 0.8, Vary = 0.08, Range = 80 },
	FungusHeavy = { File = "universeHeavySwing.ogg", Volume = 0.7, Speed = 0.75, Vary = 0.05, Range = 90 },
	FungusHit = { File = "ProjectileLand.ogg", Volume = 0.7, Speed = 1.2, Vary = 0.06, Range = 100 },
	FungusHitHeavy = { File = "ProjectileLand.ogg", Volume = 0.9, Speed = 0.85, Vary = 0.05, Range = 110 },
	FungusFeast = { File = "projectileLinkLand.ogg", Volume = 0.8, Speed = 0.8, Range = 100 },
	SporeThrow = { File = "projectileFire.ogg", Volume = 0.6, Speed = 1.3, Vary = 0.06, Range = 90 },
	SporeHit = { File = "ProjectileLand.ogg", Volume = 0.6, Speed = 1.5, Vary = 0.06, Range = 90 },
	BeamFire = { File = "heavenlyProjectileCharge.ogg", Volume = 0.8, Speed = 0.7, Range = 140 },
	FungusHeal = { File = "sparkles.ogg", Volume = 0.6, Speed = 0.7, Range = 60 },
	FungusRip = { File = "projectileLinkFire.ogg", Volume = 0.8, Speed = 0.7, Range = 80 },
	FungusForm = { File = "heavenlyProjectileCharge.ogg", Volume = 0.9, Speed = 0.5, Range = 160 },

	-- WIND (placeholders from the existing files) -----------------------------------------------
	WindGust = { File = "universeBigSwoosh.ogg", Volume = 0.7, Speed = 0.8, Vary = 0.05, Range = 100 },
	WindHit = { File = "universeSwoosh.ogg", Volume = 0.7, Speed = 0.6, Vary = 0.05, Range = 90 },

	-- PARKOUR ---------------------------------------------------------------------
	WallRun = { File = "universeFootStepLoop.ogg", Volume = 0.55, Speed = 2.0, Looped = true, Range = 60 },
	WallKick = { File = "universeSwoosh.ogg", Volume = 0.75, Vary = 0.05, Range = 80 },
	Roll = { File = "universeSwoosh.ogg", Volume = 0.6, Speed = 0.8, Vary = 0.04 },
	Vault = { File = "universeSwoosh.ogg", Volume = 0.55, Speed = 1.15, Vary = 0.05 },
	LedgeGrab = { File = "universeLand.wav", Volume = 0.35, Speed = 1.35, Vary = 0.05 },
	Slide = { File = "universeBigSwoosh.ogg", Volume = 0.5, Speed = 0.9, Vary = 0.04 },

	-- STAMINA ---------------------------------------------------------------------
	Burnout = { File = "burnoutLoop.ogg", Volume = 0.6, Looped = true, Range = 30 },
	BurnoutRecover = { File = "burnoutRecover.ogg", Volume = 0.6, Range = 30 },
	StaminaFull = { File = "oneStaminaGaugeFill.ogg", Volume = 0.35, Range = 20 },
	Denied = { File = "universeCooldownSoNo.ogg", Volume = 0.6, Range = 20 },

	-- MOTH ------------------------------------------------------------------------
	WingFlight = { File = "universeBigSwoosh.ogg", Volume = 0.7, Speed = 1.1, Vary = 0.05, Range = 90 },
	WingFlap = { File = "curtainsMove.ogg", Volume = 0.6, Speed = 1.3, Looped = true, Range = 80 },
	WingStop = { File = "curtainStop.ogg", Volume = 0.7, Range = 60 },
	LanternCharge = { File = "heavenlyProjectileCharge.ogg", Volume = 0.6, Range = 60 },
	LanternThrow = { File = "projectileFire.ogg", Volume = 0.75, Vary = 0.05, Range = 100 },
	LanternTravel = { File = "heavenlyProjectileTravel.ogg", Volume = 0.5, Looped = true, Range = 70 },
	LanternImpact = { File = "ProjectileLand.ogg", Volume = 0.8, Vary = 0.04, Range = 120 },
	LanternSuspend = { File = "sparkles.ogg", Volume = 0.7, Range = 100 },
	LanternHit = { File = "projectileLinkLand.ogg", Volume = 0.8, Range = 110 },
	LanternGrab = { File = "projectileLinkFire.ogg", Volume = 0.5, Speed = 1.2, Range = 50 },
	TagFlight = { File = "projectileFireSeeker.ogg", Volume = 0.75, Range = 100 },

}

return S
