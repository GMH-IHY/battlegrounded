--!strict
-- Wind (ModuleScript)
-- Location: ReplicatedStorage > Combat > MoveSets > Wind
--
-- The Wind element's Q (docs/MoveData.md, "Wind"). Q (forward, sideways or standing) pushes, Q with
-- S held pulls; they share one cooldown. Both are a cone of wind (a 10 x 6 x 18 box in front) that
-- staggers without knocking down, still moves a blocker (no damage then), turns projectiles inside
-- it around (Redirect), and adds build-up toward Drafted (Wind's status: CombatConfig).

local MoveTypes = require(script.Parent.Parent.MoveTypes)

local Define = MoveTypes.Define

-- Shared by both.
local function wind(t: { [string]: any }): MoveTypes.Move
	t.Element = "Wind"
	t.Weapon = "Wind"
	t.Slot = "Q"
	t.CooldownGroup = "Wind.Q"
	t.Redirect = true
	t.Fx.Hand = "Left"
	t.Fx.Swing = "WindGust"
	t.Fx.Hit = "WindHit"
	return Define(t)
end

return {
	wind({
		Id = "Wind.Push",
		Name = "Push (Q)",
		Animation = "WindPush",
		Startup = 10,
		Active = 6,
		Recovery = 18,
		Damage = 3,
		Hitbox = { Size = Vector3.new(10, 6, 18), Forward = 9.5 }, -- the cone, as a box
		-- +1 at the first active frame, but they're 30 studs away: it makes space, it doesn't combo.
		OnHit = { Kind = "Push", Stun = 24, Knockback = 30 },
		OnBlock = -2, -- still carried by the wind, no damage
		Cooldown = 8,
		Buildup = 25,
		Fx = { Arc = "Gust" },
	}),
	wind({
		Id = "Wind.Pull",
		Name = "Pull (S + Q)",
		Animation = "WindPull",
		Startup = 10,
		Active = 6,
		Recovery = 18,
		Damage = 3,
		Hitbox = { Size = Vector3.new(10, 6, 18), Forward = 9.5 }, -- the cone, as a box
		-- Pulled to 5 studs in front of you, +5: an M1 links.
		OnHit = { Kind = "Pull", Stun = 28, Knockback = 5 },
		OnBlock = -2, -- still carried by the wind, no damage
		Cooldown = 8,
		Buildup = 25,
		Fx = { Arc = "Draw" },
	}),
}
