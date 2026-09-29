--!strict
-- Dagger (ModuleScript)
-- Location: ReplicatedStorage > Combat > MoveSets > Dagger
--
-- The first secondary weapon (right click): a dagger drawn from the left hip for each move.
-- The stab comes out a frame faster than an M1 and cancels into the sword's 1 on hit; in the air it's
-- a quick slash that cancels into the air 1. Both share one cooldown.
-- (docs/MoveData.md, "Dagger")

local MoveTypes = require(script.Parent.Parent.MoveTypes)

local Define = MoveTypes.Define

return {
	Define({
		Id = "Dagger.Stab",
		Name = "Dagger stab",
		Slot = "M2",
		Weapon = "Dagger",
		Animation = "DaggerStab",
		Startup = 4,
		Active = 2,
		Recovery = 12,
		Damage = 2,
		Hitbox = { Size = Vector3.new(3, 4, 4), Forward = 2.5 },
		OnHit = { Kind = "Stun", Stun = 16, Knockback = 1 },
		OnBlock = -2,
		Cooldown = 2.5,
		CooldownGroup = "Dagger",
		CancelInto = { "Sword.One" },
		Buildup = 15,
		Hitstop = 3,
		Motion = { Step = 1 },
		Fx = { Arc = "Stab", Hand = "Left", Swing = "DaggerSwing", Hit = "DaggerHit" },
	}),
	Define({
		Id = "Dagger.AirSlash",
		Name = "Dagger air slash",
		Slot = "M2",
		Weapon = "Dagger",
		Animation = "DaggerAirSlash",
		Startup = 4,
		Active = 2,
		Recovery = 10,
		Damage = 2,
		Hitbox = { Size = Vector3.new(4, 4, 4), Forward = 2.5 },
		OnHit = { Kind = "Stun", Stun = 16, Hang = true },
		OnBlock = -2,
		Air = true,
		Cooldown = 2.5,
		CooldownGroup = "Dagger",
		CancelInto = { "Sword.AirOne" },
		Buildup = 15,
		Hitstop = 3,
		Fx = { Arc = "Flat", Hand = "Left", Swing = "DaggerSwing", Hit = "DaggerHit" },
	}),
}
