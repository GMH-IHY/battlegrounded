--!strict
-- HitResolver (ModuleScript)
-- Location: ServerScriptService > Combat > HitResolver
--
-- What happens when an attacker's active hitbox, or one of its projectiles, touches a target
-- (docs/DesignPlan.md, "Combat core"; docs/MoveData.md). In order:
--   invincible target (get-up, tech roll)          nothing (it may still hit on a later active frame)
--   parry window open, facing the hit              PARRY: the attacker is stuck ParryStun frames (a
--                                                  projectile just dies), the defender gets stamina and
--                                                  build-up on the attacker
--   guard up, facing the hit, blockable move       BLOCK: stamina drain (overdraw = burnout, burnout =
--                                                  chip damage), blockstun sized so the attacker ends at
--                                                  the move's OnBlock advantage, pushback. A blocked grab
--                                                  does nothing. A Lotus move hitting an Infested
--                                                  target's block WRAPS them (knocked down).
--   armour on the target's move                    ARMOUR: damage, no stun (hyper armour: any number of
--                                                  hits during its startup)
--   otherwise                                      HIT: counter-hit if the target was starting a move (a
--                                                  heal channel counts); combo count, shrinking stun,
--                                                  damage scaling, juggle limit, Drafted, Lotus meter,
--                                                  statuses, knockback / launch / spike / grab / impale
-- Both characters freeze for the hit pause, and the move's own clock stops meanwhile, so the
-- frame advantage stays what the move data says.
-- Returns what happened ("Hit", "Counter", "Block", "Parry", "Armour") or nil when nothing did.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local Fighter = require(script.Parent:WaitForChild("Fighter"))

type Fighter = Fighter.Fighter

local FRAME = 1 / Config.FPS
local HIT_ANIMS = { "HitStun1", "HitStun2" }

local HitResolver = {}

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- Launch speed for a height, under the place's gravity.
local function riseSpeed(height: number): number
	return math.sqrt(2 * Workspace.Gravity * math.max(height, 0))
end

function HitResolver.Scale(combo: Fighter.Combo): number
	local scale = 1
	if combo.hits >= Config.ScalingFrom then
		scale = math.max(Config.ScalingPerHit ^ (combo.hits - Config.ScalingFrom + 1), Config.ScalingMin)
	end
	if combo.afterLinker then
		scale *= Config.AfterLinker
	end
	return scale
end

-- The attacker's move this hit belongs to, if it's still running (projectiles can outlive it).
local function liveRun(attacker: Fighter, hit: Fighter.Hit): Fighter.Run?
	local run = attacker.run
	if run and run.seq == hit.seq and run.move == hit.move then
		return run
	end
	return nil
end

function HitResolver.Resolve(attacker: Fighter, target: Fighter, hit: Fighter.Hit): string?
	local move = hit.move
	local run = liveRun(attacker, hit)
	if not hit.projectile and not run then
		return nil
	end
	local now = os.clock()
	if target.state == "Dead" or target:IsInvulnerable(now) then
		return nil
	end
	-- Plain strings (the type checker narrows the Guard union wrongly across these checks).
	local guard: string = move.Guard
	local parryable = guard ~= "Unparryable"
	local blockable = guard == "Normal"
	local fromFront = move.AnyBlockSide or target:FacingDot(hit.origin) > -0.05
	local hitPoint = target.root.Position:Lerp(hit.origin, 0.35) + Vector3.new(0, 0.5, 0)
	local away = flat(target.root.Position - hit.origin)
	if away == Vector3.zero then
		away = flat(attacker.root.CFrame.LookVector)
	end
	local push = if hit.direction then flat(hit.direction) else flat(attacker.root.CFrame.LookVector)
	local isSpore = move.Fx.Arc == "Spore"

	-- PARRY ------------------------------------------------------------------------------------
	if target:ParryOpen(now) and fromFront and parryable then
		target:ConsumeParry()
		target:GainStamina(Config.ParryStaminaGain)
		local status = attacker:AddBuildup(Config.BuildupParry, target.element)
		target.lastResult = "Parry"
		attacker.lastResult = "Parried"
		if not hit.projectile then
			attacker:Interrupt()
			attacker:SetState("Parried", Config.ParryStun * FRAME)
			attacker.hooks.react(attacker, { kind = "Parried", stun = Config.ParryStun * FRAME, hitstop = 0, attacker = target.character })
		end
		attacker.hooks.result(attacker, hit.seq, "Parried", 0)
		target.hooks.react(target, { kind = "Parry", attacker = attacker.character })
		attacker.hooks.fx({ type = "Parry", attacker = attacker.character, target = target.character, position = hitPoint, move = move.Id })
		if status then
			attacker.hooks.fx({ type = "Status", target = attacker.character, status = status })
		end
		return "Parry"
	end

	-- BLOCK ------------------------------------------------------------------------------------
	if target:GuardUp() and fromFront and blockable then
		if move.CrossUp and not hit.lastActive then
			return nil -- decided on the last active frame: it may still get behind the guard
		end
		if move.Grab then
			-- A blocked grab does nothing: the attacker is left in its long recovery.
			if run then
				run.result = run.result or "Block"
			end
			attacker.lastResult = "Block"
			attacker.hooks.result(attacker, hit.seq, "Block", 0)
			attacker.hooks.fx({ type = "Block", attacker = attacker.character, target = target.character, position = hitPoint, hitstop = 0, move = move.Id })
			return "Block"
		end
		if move.Magic == "Lotus" and not isSpore and target:IsInfested() then
			-- Infested: the growth wraps them instead.
			target.infestedUntil = 0
			target:TakeDamage(move.Damage, true)
			target:Interrupt()
			target:SetState("Downed", Config.WrapFrames * FRAME)
			target.invulnerableUntil = 0
			if run then
				run.result = "Hit"
				run.hitConfirmed = true
			end
			attacker.lastResult = "Hit"
			attacker.hooks.result(attacker, hit.seq, "Hit", 0)
			target.hooks.react(target, { kind = "Wrapped", stun = Config.WrapFrames * FRAME, hitstop = 0, attacker = attacker.character })
			attacker.hooks.fx({ type = "Lotus", what = "Wrap", attacker = attacker.character, target = target.character, position = target.root.Position })
			return "Hit"
		end
		local chip = if target.burnout then move.Damage * Config.BurnoutChip else 0
		target:DrainStamina(move.Damage * Config.BlockStaminaPerDamage)
		if chip > 0 then
			target:TakeDamage(chip, false)
		end
		local hitstop = Config.BlockHitstop * FRAME
		local blockstun = if run
			then math.max(attacker:FramesLeft(hit.frame >= 0 and hit.frame or attacker:MoveFrame()) + move.OnBlock, 1)
			else move.BlockStun
		target:Interrupt()
		target:SetState("Blockstun", hitstop + blockstun * FRAME)
		if run then
			attacker:PauseMove(hitstop)
			run.result = run.result or "Block"
		end
		attacker.lastResult = "Block"
		attacker.lastAdvantage = move.OnBlock
		target.lastResult = "Blocked"
		local pushback = if move.BlockPush > 0 then move.BlockPush else Config.BlockPushback
		attacker.hooks.result(attacker, hit.seq, "Block", hitstop, move.OnBlock)
		target.hooks.react(target, {
			kind = "Block",
			stun = blockstun * FRAME,
			hitstop = hitstop,
			velocity = push * (pushback * 2 / 0.15),
			push = 0.15,
			chip = chip,
			burnout = target.burnout,
			attacker = attacker.character,
		})
		attacker.hooks.fx({
			type = "Block",
			attacker = attacker.character,
			target = target.character,
			position = hitPoint,
			hitstop = hitstop,
			chip = chip,
			move = move.Id,
		})
		return "Block"
	end

	-- ARMOUR -----------------------------------------------------------------------------------
	local targetRun = target.run
	local targetPhase = target:MovePhase()
	local armoured = targetRun ~= nil
		and (
			(targetRun.armour > 0 and (targetPhase == "Startup" or targetPhase == "Active"))
			or (targetRun.move.HyperArmour and targetPhase == "Startup")
		)
	if targetRun and armoured then
		if not targetRun.move.HyperArmour then
			targetRun.armour -= 1
		end
		target:TakeDamage(move.Damage, true)
		local hitstop = move.Hitstop * FRAME
		if run then
			attacker:PauseMove(hitstop)
			run.result = run.result or "Armour"
		end
		target:PauseMove(hitstop)
		attacker.lastResult = "Armour"
		attacker.hooks.result(attacker, hit.seq, "Armour", hitstop)
		target.hooks.react(target, { kind = "Armour", hitstop = hitstop, attacker = attacker.character })
		attacker.hooks.fx({ type = "Armour", attacker = attacker.character, target = target.character, position = hitPoint, hitstop = hitstop, move = move.Id })
		return "Armour"
	end

	-- HIT --------------------------------------------------------------------------------------
	local counter = target.state == "Attacking" and (targetPhase == "Startup" or targetPhase == "Active")
	local grounded = target:Grounded()
	if not target:IsInCombo() then
		target.combo = { hits = 0, launches = 0, afterLinker = false, damage = 0 }
	end
	local combo = target.combo
	combo.hits += 1
	local damage = move.Damage * HitResolver.Scale(combo) * (if counter then Config.CounterHitDamage else 1)
	damage = math.floor(damage * 10 + 0.5) / 10
	if move.Linker then
		combo.afterLinker = true
	end
	local dealt = target:TakeDamage(damage, true)
	combo.damage += dealt
	target.lastHitAt = now

	local hitstop = move.Hitstop * FRAME
	local result = if counter then "Counter" else "Hit"
	if run then
		attacker:PauseMove(hitstop)
		run.result = result
		run.hitConfirmed = true
	end
	attacker.lastResult = result
	target.lastResult = "Hit"

	-- Lotus: the meter, follow-ups, statuses.
	if move.Magic == "Lotus" then
		local slot: string = move.Slot
		attacker.lastLotusHit = { slot = slot, at = now }
		if move.MeterGain > 0 then
			attacker:AddMeter(move.MeterGain)
		end
		if move.SetMeter then
			attacker:SetMeter(move.SetMeter)
		end
		if counter and move.RefundOnCounter and run and run.costPaid > 0 then
			attacker:AddMeter(run.costPaid)
		end
	end
	if move.Status == "Infested" then
		target.infestedUntil = now + Config.InfestedTime
		attacker.hooks.fx({ type = "Status", target = target.character, status = "Infested" })
	end

	local onHit = move.OnHit
	local kind: string = onHit.Kind
	local info: { [string]: any } = {
		kind = kind,
		hitstop = hitstop,
		attacker = attacker.character,
		counter = counter,
		damage = dealt,
		anim = HIT_ANIMS[(combo.hits - 1) % #HIT_ANIMS + 1],
	}
	local downed = target.state == "Downed"
	if downed then
		-- On the floor: the hit lands (down slams are allowed as often as you like) but they stay
		-- down, and the get-up clock keeps running, so it can't loop.
		kind = "Downed"
		info.kind = kind
		attacker.lastAdvantage = nil
	elseif kind == "Launch" and combo.launches >= Config.LaunchesPerCombo then
		kind = "Knockdown" -- juggle limit: a second launch is a plain knockdown
		info.kind = kind
		info.juggled = true
	end

	if kind == "Stun" then
		local stun
		if counter and move.CounterStun then
			stun = move.CounterStun
		else
			stun = onHit.Stun + (if counter then Config.CounterHitStun else 0)
		end
		if hit.followUp then
			stun += move.FollowUpStun
		end
		stun = math.max(stun - Config.StunDecay * (combo.hits - 1), Config.MinStun)
		target:Interrupt()
		target:SetState("Stunned", hitstop + stun * FRAME)
		info.stun = stun * FRAME
		info.hang = onHit.Hang or not grounded and move.Air
		info.velocity = push * (onHit.Knockback * 2 / 0.15)
		info.push = 0.15
		attacker.lastAdvantage = if run then stun - attacker:FramesLeft(if hit.frame >= 0 then hit.frame else attacker:MoveFrame()) else nil
	elseif kind == "Launch" then
		combo.launches += 1
		local height = onHit.Launch
		if target:IsDrafted() then
			height *= Config.DraftedLaunchScale
			target:UseDrafted()
			info.drafted = true
		end
		target:Knock("Launched", hitstop + Config.LaunchStun * FRAME)
		info.velocity = Vector3.new(0, riseSpeed(height), 0)
		info.stun = Config.LaunchStun * FRAME
		attacker.lastAdvantage = nil
	elseif kind == "Knockdown" or kind == "Spike" then
		local extra = 0
		if target:IsDrafted() then
			extra = Config.DraftedDownFrames
			target:UseDrafted()
			info.drafted = true
		end
		target:Knock("Knockdown", nil, extra)
		target.knockSince = now + hitstop
		if kind == "Spike" then
			info.velocity = Vector3.new(0, -110, 0) + push * 8
		else
			local distance = if onHit.Knockback > 0 then onHit.Knockback else 10
			info.velocity = away * (distance / 0.42) + Vector3.new(0, 34, 0)
		end
		attacker.lastAdvantage = nil
	elseif kind == "Grab" or kind == "Impale" then
		-- Held still (a grab's feast, an impale's spike), then thrown / dropped: a knockdown.
		local frames, throw
		local grab = move.Grab
		if grab then
			frames = grab.Hold
			throw = away * (grab.Throw / 0.42) + Vector3.new(0, 30, 0)
		else
			frames = move.HeldFrames
			throw = away * (math.max(onHit.Knockback, 2) / 0.42) + Vector3.new(0, 10, 0)
		end
		target:Interrupt()
		target:SetState("Held", hitstop + frames * FRAME)
		target.heldThrow = throw
		info.kind = "Held"
		info.stun = frames * FRAME
		info.how = kind
		attacker.lastAdvantage = nil
	end

	local status = target:AddBuildup(if counter then math.max(move.Buildup, Config.BuildupCounterHit) else move.Buildup, attacker.element)

	attacker.hooks.result(attacker, hit.seq, result, if run then hitstop else 0, attacker.lastAdvantage)
	target.hooks.react(target, info)
	attacker.hooks.fx({
		type = "Hit",
		attacker = attacker.character,
		target = target.character,
		position = hitPoint,
		hitstop = hitstop,
		counter = counter,
		damage = dealt,
		kind = kind,
		move = move.Id,
		combo = combo.hits,
	})
	if status then
		attacker.hooks.fx({ type = "Status", target = target.character, status = status })
	end
	return result
end

return HitResolver
