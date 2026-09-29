--!strict
-- HitResolver (ModuleScript)
-- Location: ServerScriptService > Combat > HitResolver
--
-- What happens when an attacker's active hitbox touches a target (docs/DesignPlan.md, "Combat core").
-- In order:
--   invincible target (get-up, tech roll)          nothing (it may still hit on a later active frame)
--   parry window open, facing the hit              PARRY: the attacker is stuck ParryStun frames, the
--                                                  defender gets stamina and build-up on the attacker
--   guard up, facing the hit, blockable move       BLOCK: stamina drain (overdraw = burnout, burnout =
--                                                  chip damage), blockstun sized so the attacker ends
--                                                  at the move's OnBlock advantage, pushback
--   armour left on the target's move               ARMOUR: damage, no stun
--   otherwise                                      HIT: counter-hit if the target was starting a move;
--                                                  combo count, shrinking stun, damage scaling, juggle
--                                                  limit, Drafted, knockback / launch / spike
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

local function applyDamage(target: Fighter, amount: number)
	local humanoid = target.humanoid
	local floor = if target.isDummy then 1 else 0
	humanoid.Health = math.max(humanoid.Health - amount, floor)
end

function HitResolver.Resolve(attacker: Fighter, target: Fighter, frame: number, lastActive: boolean): string?
	local run = attacker.run
	if not run then
		return nil
	end
	local move = run.move
	local now = os.clock()
	if target.state == "Dead" or target:IsInvulnerable(now) then
		return nil
	end
	local fromFront = target:FacingDot(attacker.root.Position) > -0.05
	local hitPoint = target.root.Position:Lerp(attacker.root.Position, 0.35) + Vector3.new(0, 0.5, 0)
	local away = flat(target.root.Position - attacker.root.Position)
	if away == Vector3.zero then
		away = flat(attacker.root.CFrame.LookVector)
	end
	local push = flat(attacker.root.CFrame.LookVector)
	-- Plain strings (the type checker narrows the Guard union wrongly across these checks).
	local guard: string = move.Guard
	local parryable = guard ~= "Unparryable"
	local blockable = guard == "Normal"

	-- PARRY ------------------------------------------------------------------------------------
	if target:ParryOpen(now) and fromFront and parryable then
		target:ConsumeParry()
		target:GainStamina(Config.ParryStaminaGain)
		local status = attacker:AddBuildup(Config.BuildupParry, target.element)
		attacker:Interrupt()
		attacker:SetState("Parried", Config.ParryStun * FRAME)
		attacker.lastResult = "Parried"
		target.lastResult = "Parry"
		attacker.hooks.result(attacker, run.seq, "Parried", 0)
		attacker.hooks.react(attacker, { kind = "Parried", stun = Config.ParryStun * FRAME, hitstop = 0, attacker = target.character })
		target.hooks.react(target, { kind = "Parry", attacker = attacker.character })
		attacker.hooks.fx({ type = "Parry", attacker = attacker.character, target = target.character, position = hitPoint, move = move.Id })
		if status then
			attacker.hooks.fx({ type = "Status", target = attacker.character, status = status })
		end
		return "Parry"
	end

	-- BLOCK ------------------------------------------------------------------------------------
	if target:GuardUp() and fromFront and blockable then
		if move.CrossUp and not lastActive then
			return nil -- decided on the last active frame: it may still get behind the guard
		end
		local chip = if target.burnout then move.Damage * Config.BurnoutChip else 0
		target:DrainStamina(move.Damage * Config.BlockStaminaPerDamage)
		if chip > 0 then
			applyDamage(target, chip)
		end
		local hitstop = Config.BlockHitstop * FRAME
		local blockstun = math.max(attacker:FramesLeft(frame) + move.OnBlock, 1)
		target:Interrupt()
		target:SetState("Blockstun", hitstop + blockstun * FRAME)
		attacker:PauseMove(hitstop)
		run.result = run.result or "Block"
		attacker.lastResult = "Block"
		attacker.lastAdvantage = move.OnBlock
		target.lastResult = "Blocked"
		attacker.hooks.result(attacker, run.seq, "Block", hitstop, move.OnBlock)
		target.hooks.react(target, {
			kind = "Block",
			stun = blockstun * FRAME,
			hitstop = hitstop,
			velocity = push * (Config.BlockPushback * 2 / 0.15),
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
	if targetRun and targetRun.armour > 0 and (targetPhase == "Startup" or targetPhase == "Active") then
		targetRun.armour -= 1
		applyDamage(target, move.Damage)
		local hitstop = move.Hitstop * FRAME
		attacker:PauseMove(hitstop)
		target:PauseMove(hitstop)
		run.result = run.result or "Armour"
		attacker.lastResult = "Armour"
		attacker.hooks.result(attacker, run.seq, "Armour", hitstop)
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
	combo.damage += damage
	applyDamage(target, damage)
	target.lastHitAt = now

	local hitstop = move.Hitstop * FRAME
	attacker:PauseMove(hitstop)
	run.result = if counter then "Counter" else "Hit"
	run.hitConfirmed = true
	attacker.lastResult = run.result :: string
	target.lastResult = "Hit"

	local onHit = move.OnHit
	local kind: string = onHit.Kind
	local info: { [string]: any } = {
		kind = kind,
		hitstop = hitstop,
		attacker = attacker.character,
		counter = counter,
		damage = damage,
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
		local stun = onHit.Stun + (if counter then Config.CounterHitStun else 0) - Config.StunDecay * (combo.hits - 1)
		stun = math.max(stun, Config.MinStun)
		target:Interrupt()
		target:SetState("Stunned", hitstop + stun * FRAME)
		info.stun = stun * FRAME
		info.hang = onHit.Hang or not grounded and move.Air
		info.velocity = push * (onHit.Knockback * 2 / 0.15)
		info.push = 0.15
		attacker.lastAdvantage = stun - attacker:FramesLeft(frame)
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
	end

	local status = target:AddBuildup(if counter then math.max(move.Buildup, Config.BuildupCounterHit) else move.Buildup, attacker.element)

	attacker.hooks.result(attacker, run.seq, run.result :: string, hitstop, attacker.lastAdvantage)
	target.hooks.react(target, info)
	attacker.hooks.fx({
		type = "Hit",
		attacker = attacker.character,
		target = target.character,
		position = hitPoint,
		hitstop = hitstop,
		counter = counter,
		damage = damage,
		kind = kind,
		move = move.Id,
		combo = combo.hits,
	})
	if status then
		attacker.hooks.fx({ type = "Status", target = target.character, status = status })
	end
	return run.result
end

return HitResolver
