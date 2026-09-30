--!strict
-- SoundConfig (ModuleScript)
-- Location: ReplicatedStorage > Movement > SoundConfig
--
-- Every movement / Moth sound, by name. Code only ever plays these names (through Sfx), so swapping
-- a sound is a one-line change here.
--   File     = the source file in Downloads\audio (for reference / re-uploading).
--   Id       = the uploaded audio asset ("rbxassetid://123"). While it's empty, Sfx looks for a Sound
--              with the same name in ReplicatedStorage > Sounds instead (handy for testing), and if
--              there isn't one the sound is silently skipped (warns once in Studio).
--   Volume   = base volume. Speed = base PlaybackSpeed. Looped = plays until stopped.
--   Vary     = random +- PlaybackSpeed each play so repeats don't sound identical.
--   Range    = RollOffMaxDistance (studs) other players can hear it from.

export type Entry = {
	File: string,
	Id: string,
	Volume: number,
	Speed: number?,
	Looped: boolean?,
	Vary: number?,
	Range: number?,
}

local S: { [string]: Entry } = {
	-- BASIC MOVEMENT --------------------------------------------------------------
	Footsteps = { File = "universeFootStepLoop.ogg", Id = "", Volume = 0.45, Looped = true, Range = 60 },
	Jump = { File = "universeJump.wav", Id = "", Volume = 0.5, Vary = 0.05 },
	Land = { File = "universeLand.wav", Id = "", Volume = 0.55, Vary = 0.05 },
	FallWind = { File = "universeFalling.ogg", Id = "", Volume = 0.6, Looped = true, Range = 50 },

	-- DASH ------------------------------------------------------------------------
	Dash = { File = "universeDash.ogg", Id = "", Volume = 0.7, Vary = 0.06, Range = 90 },

	-- COMBAT (move data picks the swing / hit sound: MoveSets Fx.Swing / Fx.Hit) --------------
	SwordSwing = { File = "universeSwoosh.ogg", Id = "", Volume = 0.6, Speed = 1.25, Vary = 0.08, Range = 80 },
	SwordSwingHeavy = { File = "universeHeavySwing.ogg", Id = "", Volume = 0.7, Vary = 0.06, Range = 90 },
	SwordHit = { File = "universeClash2.ogg", Id = "", Volume = 0.75, Speed = 1.15, Vary = 0.06, Range = 100 },
	SwordHitHeavy = { File = "universeClash.ogg", Id = "", Volume = 0.85, Vary = 0.05, Range = 110 },
	DaggerSwing = { File = "universeSwoosh.ogg", Id = "", Volume = 0.5, Speed = 1.6, Vary = 0.08, Range = 70 },
	DaggerHit = { File = "universeClash2.ogg", Id = "", Volume = 0.6, Speed = 1.5, Vary = 0.06, Range = 90 },
	CounterHit = { File = "universeHeavySwing2.ogg", Id = "", Volume = 0.6, Speed = 0.7, Range = 100 },
	Block = { File = "universeClash.ogg", Id = "", Volume = 0.6, Speed = 1.5, Vary = 0.05, Range = 90 },
	Parry = { File = "sparkles.ogg", Id = "", Volume = 0.9, Speed = 1.3, Range = 120 },

	-- LOTUS FUNGUS (placeholders from the existing files until it has its own sounds) ------------
	FungusSwing = { File = "universeSwoosh.ogg", Id = "", Volume = 0.55, Speed = 0.8, Vary = 0.08, Range = 80 },
	FungusHeavy = { File = "universeHeavySwing.ogg", Id = "", Volume = 0.7, Speed = 0.75, Vary = 0.05, Range = 90 },
	FungusHit = { File = "ProjectileLand.ogg", Id = "", Volume = 0.7, Speed = 1.2, Vary = 0.06, Range = 100 },
	FungusHitHeavy = { File = "ProjectileLand.ogg", Id = "", Volume = 0.9, Speed = 0.85, Vary = 0.05, Range = 110 },
	FungusFeast = { File = "projectileLinkLand.ogg", Id = "", Volume = 0.8, Speed = 0.8, Range = 100 },
	SporeThrow = { File = "projectileFire.ogg", Id = "", Volume = 0.6, Speed = 1.3, Vary = 0.06, Range = 90 },
	SporeHit = { File = "ProjectileLand.ogg", Id = "", Volume = 0.6, Speed = 1.5, Vary = 0.06, Range = 90 },
	BeamFire = { File = "heavenlyProjectileCharge.ogg", Id = "", Volume = 0.8, Speed = 0.7, Range = 140 },
	FungusHeal = { File = "sparkles.ogg", Id = "", Volume = 0.6, Speed = 0.7, Range = 60 },
	FungusRip = { File = "projectileLinkFire.ogg", Id = "", Volume = 0.8, Speed = 0.7, Range = 80 },
	FungusForm = { File = "heavenlyProjectileCharge.ogg", Id = "", Volume = 0.9, Speed = 0.5, Range = 160 },

	-- WIND (placeholders from the existing files) -----------------------------------------------
	WindGust = { File = "universeBigSwoosh.ogg", Id = "", Volume = 0.7, Speed = 0.8, Vary = 0.05, Range = 100 },
	WindHit = { File = "universeSwoosh.ogg", Id = "", Volume = 0.7, Speed = 0.6, Vary = 0.05, Range = 90 },

	-- PARKOUR ---------------------------------------------------------------------
	WallRun = { File = "universeFootStepLoop.ogg", Id = "", Volume = 0.55, Speed = 2.0, Looped = true, Range = 60 },
	WallKick = { File = "universeSwoosh.ogg", Id = "", Volume = 0.75, Vary = 0.05, Range = 80 },
	Roll = { File = "universeSwoosh.ogg", Id = "", Volume = 0.6, Speed = 0.8, Vary = 0.04 },
	Vault = { File = "universeSwoosh.ogg", Id = "", Volume = 0.55, Speed = 1.15, Vary = 0.05 },
	LedgeGrab = { File = "universeLand.wav", Id = "", Volume = 0.35, Speed = 1.35, Vary = 0.05 },
	Slide = { File = "universeBigSwoosh.ogg", Id = "", Volume = 0.5, Speed = 0.9, Vary = 0.04 },

	-- STAMINA ---------------------------------------------------------------------
	Burnout = { File = "burnoutLoop.ogg", Id = "", Volume = 0.6, Looped = true, Range = 30 },
	BurnoutRecover = { File = "burnoutRecover.ogg", Id = "", Volume = 0.6, Range = 30 },
	StaminaFull = { File = "oneStaminaGaugeFill.ogg", Id = "", Volume = 0.35, Range = 20 },
	Denied = { File = "universeCooldownSoNo.ogg", Id = "", Volume = 0.6, Range = 20 },

	-- MOTH ------------------------------------------------------------------------
	WingFlight = { File = "universeBigSwoosh.ogg", Id = "", Volume = 0.7, Speed = 1.1, Vary = 0.05, Range = 90 },
	WingFlap = { File = "curtainsMove.ogg", Id = "", Volume = 0.6, Speed = 1.3, Looped = true, Range = 80 },
	WingStop = { File = "curtainStop.ogg", Id = "", Volume = 0.7, Range = 60 },
	LanternCharge = { File = "heavenlyProjectileCharge.ogg", Id = "", Volume = 0.6, Range = 60 },
	LanternThrow = { File = "projectileFire.ogg", Id = "", Volume = 0.75, Vary = 0.05, Range = 100 },
	LanternTravel = { File = "heavenlyProjectileTravel.ogg", Id = "", Volume = 0.5, Looped = true, Range = 70 },
	LanternImpact = { File = "ProjectileLand.ogg", Id = "", Volume = 0.8, Vary = 0.04, Range = 120 },
	LanternSuspend = { File = "sparkles.ogg", Id = "", Volume = 0.7, Range = 100 },
	LanternHit = { File = "projectileLinkLand.ogg", Id = "", Volume = 0.8, Range = 110 },
	LanternGrab = { File = "projectileLinkFire.ogg", Id = "", Volume = 0.5, Speed = 1.2, Range = 50 },
	TagFlight = { File = "projectileFireSeeker.ogg", Id = "", Volume = 0.75, Range = 100 },

}

return S
