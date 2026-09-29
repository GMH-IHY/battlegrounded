--!strict
-- MoveTypes (ModuleScript)
-- Location: ReplicatedStorage > Combat > MoveTypes
--
-- The shape of a move's data (MoveSets > Sword, Dagger, ...). Frames are at 60 per second.
--
--   Startup / Active / Recovery   frames before the first active frame / with the hitbox out /
--                                 after it. WhiffRecovery (optional) replaces Recovery on a miss.
--   Hitbox                        Size in studs, centred Forward studs in front of the root and Up
--                                 studs above it. It follows the attacker.
--   OnHit                         Kind: Stun (Stun frames; Hang = the target hangs in the air),
--                                 Knockdown (knocked back Knockback studs), Launch (sent Launch studs
--                                 up), Spike (driven into the floor). Knockback on a Stun = pushback.
--   OnBlock                       frame advantage when blocked (+ = the attacker acts first).
--   Guard                         Normal, Unblockable (yellow flash: parry it) or Unparryable (blue
--                                 flash: can't be blocked or parried, dash out of the way).
--   Air                           only in the air; the attacker hangs while it plays.
--   Chain                         its place in the M1 chain (1-3), 0 for anything else.
--   CancelInto                    moves this one can cancel into once it has hit.
--   JumpCancel                    once it has hit, its recovery can be cut by jumping into an air move
--                                 (the launcher's follow-up).
--   Linker                        moves after it in the combo do x AfterLinker damage (CombatConfig).
--   CrossUp                       a front block only counts on its last active frame, so it can get
--                                 behind a blocker before it's decided (the lunge).
--   Motion                        Step studs forward over the startup, Lunge studs over the active
--                                 frames (the attacker's own client moves them).
--   Buildup                       status build-up on the target when it hits.
--   Fx                            the slash drawn on the active frames (CombatFx).

export type Guard = "Normal" | "Unblockable" | "Unparryable"
export type HitKind = "Stun" | "Knockdown" | "Launch" | "Spike"
export type Slot = "M1" | "M2" | "One"
export type Arc = "Flat" | "Backhand" | "Overhead" | "Rising" | "Thrust" | "Diagonal" | "Stab"

export type Hitbox = { Size: Vector3, Forward: number, Up: number }
export type OnHit = { Kind: HitKind, Stun: number, Knockback: number, Launch: number, Hang: boolean }
export type Motion = { Step: number, Lunge: number }
export type Fx = { Arc: Arc, Hand: "Right" | "Left", Swing: string, Hit: string }

export type Move = {
	Id: string,
	Name: string,
	Slot: Slot,
	Weapon: string,
	Animation: string,
	Startup: number,
	Active: number,
	Recovery: number,
	WhiffRecovery: number?,
	Damage: number,
	Hitbox: Hitbox,
	OnHit: OnHit,
	OnBlock: number,
	Guard: Guard,
	Air: boolean,
	Chain: number,
	Cooldown: number,
	CooldownGroup: string,
	CancelInto: { string },
	JumpCancel: boolean,
	Linker: boolean,
	CrossUp: boolean,
	Armour: number,
	Buildup: number,
	Hitstop: number,
	Motion: Motion,
	Fx: Fx,
}

local MoveTypes = {}

-- Fills in the defaults, so a move set lists only what's special about each move.
function MoveTypes.Define(t: { [string]: any }): Move
	local onHit = t.OnHit or {}
	local motion = t.Motion or {}
	local fx = t.Fx or {}
	local move: Move = {
		Id = t.Id,
		Name = t.Name or t.Id,
		Slot = t.Slot,
		Weapon = t.Weapon,
		Animation = t.Animation,
		Startup = t.Startup,
		Active = t.Active,
		Recovery = t.Recovery,
		WhiffRecovery = t.WhiffRecovery,
		Damage = t.Damage,
		Hitbox = { Size = t.Hitbox.Size, Forward = t.Hitbox.Forward, Up = t.Hitbox.Up or 0 },
		OnHit = {
			Kind = onHit.Kind or "Stun",
			Stun = onHit.Stun or 0,
			Knockback = onHit.Knockback or 0,
			Launch = onHit.Launch or 0,
			Hang = onHit.Hang == true,
		},
		OnBlock = t.OnBlock or 0,
		Guard = t.Guard or "Normal",
		Air = t.Air == true,
		Chain = t.Chain or 0,
		Cooldown = t.Cooldown or 0,
		CooldownGroup = t.CooldownGroup or t.Id,
		CancelInto = t.CancelInto or {},
		JumpCancel = t.JumpCancel == true,
		Linker = t.Linker == true,
		CrossUp = t.CrossUp == true,
		Armour = t.Armour or 0,
		Buildup = t.Buildup or 0,
		Hitstop = t.Hitstop or 4,
		Motion = { Step = motion.Step or 0, Lunge = motion.Lunge or 0 },
		Fx = {
			Arc = fx.Arc or "Flat",
			Hand = fx.Hand or "Right",
			Swing = fx.Swing or "SwordSwing",
			Hit = fx.Hit or "SwordHit",
		},
	}
	assert(move.Id and move.Slot and move.Animation and move.Startup and move.Damage, "MoveTypes.Define: incomplete move")
	return move
end

return MoveTypes
