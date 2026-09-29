--!strict
-- Loadout (ModuleScript)
-- Location: ReplicatedStorage > Combat > Loadout
--
-- Which move a key press picks. The attacker's client picks (it knows whether you're running,
-- airborne or holding Space); the server checks the pick is one this key could make.
-- Until the loadout menu exists every fighter carries the first build: Sword + Dagger.
--
--   M1   chain position 1-3 (Chain): ground M1 1 / 2 / 3, or the launcher for 3 with Space held;
--        in the air M1 1 / 2 / the spike. Running (or a front dash) starts with the lunge instead.
--   M2   the dagger: the stab, or the air slash in the air.
--   One  the sword's 1, or the air 1.

local Loadout = {}

export type Context = {
	air: boolean,
	running: boolean,
	spaceHeld: boolean,
	chain: number, -- the chain position this press would be (1-3)
}

export type Build = { Weapon: string, Secondary: string }

Loadout.Default = { Weapon = "Sword", Secondary = "Dagger" } :: Build

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
	end
	return nil
end

-- Could pressing `slot` ever pick `moveId` (the server's check of a client's pick)?
function Loadout.CanPick(slot: string, moveId: string): boolean
	for _, air in { false, true } do
		for _, running in { false, true } do
			for _, spaceHeld in { false, true } do
				for chain = 1, 3 do
					if Loadout.Pick(slot, { air = air, running = running, spaceHeld = spaceHeld, chain = chain }) == moveId then
						return true
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
