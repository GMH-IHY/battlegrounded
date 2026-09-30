--!strict
-- Loadout (ModuleScript)
-- Location: ReplicatedStorage > Combat > Loadout
--
-- Which move a key press picks. The attacker's client picks (it knows whether you're running,
-- airborne or holding Space); the server checks the pick is one this key could make.
-- Until the loadout menu exists every fighter carries the first build: Sword + Dagger + Lotus Fungus
-- + Wind.
--
--   M1   chain position 1-3 (Chain): ground M1 1 / 2 / 3, or the launcher for 3 with Space held;
--        in the air M1 1 / 2 / the spike. Running (or a front dash) starts with the lunge instead.
--   M2   the dagger: the stab, or the air slash in the air.
--   One  the sword's 1, or the air 1.
--   Two / Three / Four   the Lotus stab / spore / grab of your meter stage (the form counts as
--        stage 3); the stab becomes the impale against an airborne opponent in front (stages 1, 3).
--   R    hold = the heal channel; a quick tap = rip out (rip = true).
--   G    the stage 3 form.
--   Q    Wind: the pull with S held (back = true), else the push.

local Loadout = {}

export type Context = {
	air: boolean,
	running: boolean,
	spaceHeld: boolean,
	chain: number, -- the chain position this press would be (1-3)
	stage: number?, -- Lotus meter stage (1-3)
	targetAirborne: boolean?, -- an airborne opponent in front, within the impale's range
	rip: boolean?, -- R was tapped, not held
	back: boolean?, -- S held (moving away from where you face)
}

export type Build = { Weapon: string, Secondary: string, Magic: string, Element: string }

Loadout.Default = { Weapon = "Sword", Secondary = "Dagger", Magic = "Lotus", Element = "Wind" } :: Build

local STAB = { "Lotus.Stab1", "Lotus.Strand2", "Lotus.Stab3" }
local IMPALE: { [number]: string } = { [1] = "Lotus.Impale1", [3] = "Lotus.Impale3" }
local SPORE = { "Lotus.Spore1", "Lotus.Spore2", "Lotus.Beam3" }
local GRAB = { "Lotus.Grab1", "Lotus.Grab2", "Lotus.Grab3" }

local M1_GROUND = { "Sword.M1_1", "Sword.M1_2", "Sword.M1_3" }
local M1_AIR = { "Sword.AirM1_1", "Sword.AirM1_2", "Sword.AirSpike" }

-- The move id for pressing `slot` in this situation, or nil.
function Loadout.Pick(slot: string, ctx: Context): string?
	if slot == "M1" then
		local chain = math.clamp(ctx.chain, 1, 3)
		if ctx.air then
			return M1_AIR[chain]
		end
		if ctx.running and chain == 1 then
			return "Sword.Lunge"
		end
		if chain == 3 and ctx.spaceHeld then
			return "Sword.Launcher"
		end
		return M1_GROUND[chain]
	elseif slot == "M2" then
		return if ctx.air then "Dagger.AirSlash" else "Dagger.Stab"
	elseif slot == "One" then
		return if ctx.air then "Sword.AirOne" else "Sword.One"
	elseif slot == "Q" then
		return if ctx.back then "Wind.Pull" else "Wind.Push"
	end
	local stage = math.clamp(ctx.stage or 1, 1, 3)
	if slot == "Two" then
		if ctx.targetAirborne and IMPALE[stage] then
			return IMPALE[stage]
		end
		return STAB[stage]
	elseif slot == "Three" then
		return SPORE[stage]
	elseif slot == "Four" then
		return GRAB[stage]
	elseif slot == "R" then
		return if ctx.rip then "Lotus.RipOut" else "Lotus.Heal"
	elseif slot == "G" then
		return "Lotus.Form"
	end
	return nil
end

-- Could pressing `slot` ever pick `moveId` (the server's check of a client's pick)?
function Loadout.CanPick(slot: string, moveId: string): boolean
	for _, air in { false, true } do
		for _, running in { false, true } do
			for _, spaceHeld in { false, true } do
				for chain = 1, 3 do
					for stage = 1, 3 do
						for _, flag in { false, true } do
							local ctx = {
								air = air,
								running = running,
								spaceHeld = spaceHeld,
								chain = chain,
								stage = stage,
								targetAirborne = flag,
								rip = flag,
								back = flag,
							}
							if Loadout.Pick(slot, ctx) == moveId then
								return true
							end
						end
					end
				end
			end
		end
	end
	return false
end

-- The chain position of the next M1: the one after `last` if the chain is still open.
function Loadout.NextChain(last: number, sinceEnd: number, window: number): number
	if last >= 1 and last < 3 and sinceEnd <= window then
		return last + 1
	end
	return 1
end

return Loadout
