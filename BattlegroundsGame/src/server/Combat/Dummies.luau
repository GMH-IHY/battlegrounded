--!strict
-- Dummies (ModuleScript)
-- Location: ServerScriptService > Combat > Dummies
--
-- Training dummies: R6 fighters the server runs itself (its own physics and animations), in
-- Workspace > TrainingDummies. Each has a mode (attribute "DummyMode"; the Studio test panel can
-- change it):
--   Stand          takes hits
--   Block          always blocking
--   BlockAfterHit  blocks as soon as it can after being hit: it shows the M1 gap (M1 2 gets
--                  blocked) and that a blocked M1 3 is your turn to lose
--   Parry          parries anything it sees coming (one try per parry lockout)
--   Attack         walks nothing, but swings the M1 chain at anyone close, over and over
-- Health comes back DummyResetTime seconds after the last hit; they never die. A label over each
-- shows its mode, state and the last combo (hits, damage).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("CombatConfig"))
local CombatBody = require(Combat:WaitForChild("CombatBody"))
local CombatAnimator = require(Combat:WaitForChild("CombatAnimator"))
local Reactions = require(Combat:WaitForChild("Reactions"))
local WeaponModels = require(Combat:WaitForChild("WeaponModels"))
local FighterCollision = require(Combat:WaitForChild("FighterCollision"))
local Fighter = require(script.Parent:WaitForChild("Fighter"))

type Fighter = Fighter.Fighter

local FRAME = 1 / Config.FPS

export type Dummy = {
	name: string,
	home: CFrame,
	model: Model,
	fighter: Fighter,
	body: CombatBody.CombatBody,
	anim: CombatAnimator.CombatAnimator,
	reactions: Reactions.Reactions,
	label: TextLabel,
	lastRun: string?,
	nextAttack: number,
	chainLeft: number,
	parryRelease: number,
	shownHits: number,
	shownDamage: number,
}

local Dummies = {}

-- name -> (mode, position). They face -X, toward someone walking in from the course.
local LAYOUT = {
	{ name = "DummyStand", mode = "Stand", position = Vector3.new(80, 3, 40) },
	{ name = "DummyBlock", mode = "Block", position = Vector3.new(80, 3, 52) },
	{ name = "DummyBlockAfterHit", mode = "BlockAfterHit", position = Vector3.new(80, 3, 64) },
	{ name = "DummyParry", mode = "Parry", position = Vector3.new(80, 3, 76) },
	{ name = "DummyAttack", mode = "Attack", position = Vector3.new(80, 3, 88) },
}
Dummies.Modes = { "Stand", "Block", "BlockAfterHit", "Parry", "Attack" }

local COLORS = {
	Head = Color3.fromRGB(196, 170, 120),
	Torso = Color3.fromRGB(150, 118, 78),
	Limbs = Color3.fromRGB(176, 146, 100),
}

local list: { Dummy } = {}
local folder: Folder? = nil

local function build(name: string, cframe: CFrame): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = COLORS.Head
	description.TorsoColor = COLORS.Torso
	description.LeftArmColor = COLORS.Limbs
	description.RightArmColor = COLORS.Limbs
	description.LeftLegColor = COLORS.Limbs
	description.RightLegColor = COLORS.Limbs
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = false
	model:PivotTo(cframe)
	model:SetAttribute("Race", "None")
	model:SetAttribute("Element", "Wind")
	return model
end

local function makeLabel(model: Model): TextLabel
	local head = model:FindFirstChild("Head") :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "DummyLabel"
	gui.Size = UDim2.fromOffset(220, 44)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = head
	return label
end

function Dummies.Spawn(hooks: Fighter.Hooks, register: (Model, Fighter) -> ()): { Dummy }
	local holder = Instance.new("Folder")
	holder.Name = "TrainingDummies"
	holder.Parent = Workspace
	folder = holder
	for _, spec in LAYOUT do
		local home = CFrame.lookAlong(spec.position, -Vector3.xAxis)
		local model = build(spec.name, home)
		model:SetAttribute("DummyMode", spec.mode)
		model.Parent = holder
		WeaponModels.Attach(model)
		FighterCollision.Apply(model)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		root:SetNetworkOwner(nil)
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		local fighter = Fighter.new(model, nil, hooks)
		local body = CombatBody.new(model, nil)
		local anim = CombatAnimator.new(humanoid)
		local dummy: Dummy = {
			name = spec.name,
			home = home,
			model = model,
			fighter = fighter,
			body = body,
			anim = anim,
			reactions = Reactions.new(model, body, anim),
			label = makeLabel(model),
			lastRun = nil,
			nextAttack = 0,
			chainLeft = 0,
			parryRelease = 0,
			shownHits = 0,
			shownDamage = 0,
		}
		table.insert(list, dummy)
		register(model, fighter)
	end
	return list
end

function Dummies.Get(name: string): Dummy?
	for _, dummy in list do
		if dummy.name == name then
			return dummy
		end
	end
	return nil
end

function Dummies.All(): { Dummy }
	return list
end

-- Back to full health, home, neutral.
function Dummies.Reset(dummy: Dummy)
	local fighter = dummy.fighter
	fighter:Interrupt()
	fighter:SetState("Idle")
	fighter:SetBlock(false)
	fighter.combo = { hits = 0, launches = 0, afterLinker = false, damage = 0 }
	fighter:SetStamina(Config.StaminaMax)
	fighter.buildup = 0
	fighter.draftedUntil = 0
	fighter.parryLockUntil = 0
	dummy.body:Release()
	dummy.anim:Stop()
	dummy.shownHits, dummy.shownDamage = 0, 0
	dummy.chainLeft = 0
	dummy.nextAttack = os.clock() + 0.5
	fighter.humanoid.Health = fighter.humanoid.MaxHealth
	dummy.model:PivotTo(dummy.home)
	fighter.root.AssemblyLinearVelocity = Vector3.zero
end

-- The nearest living player character within `range`, and its fighter.
local function nearestPlayer(dummy: Dummy, range: number, fighterOf: (Model) -> Fighter?): Fighter?
	local best: Fighter? = nil
	local bestDistance = range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local other = if character then fighterOf(character) else nil
		if other and other.humanoid.Health > 0 then
			local distance = (other.root.Position - dummy.fighter.root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function think(dummy: Dummy, now: number, fighterOf: (Model) -> Fighter?)
	local fighter = dummy.fighter
	local mode = dummy.model:GetAttribute("DummyMode")
	if mode == "Block" then
		fighter:SetBlock(true)
	elseif mode == "BlockAfterHit" then
		fighter:SetBlock(now - fighter.lastHitAt < 1.2)
	elseif mode == "Parry" then
		if fighter.blockHeld and now >= dummy.parryRelease then
			fighter:SetBlock(false)
		end
		if not fighter.blockHeld and not fighter:IsLocked() then
			-- Someone near is about to hit: press F so the window covers their first active frame.
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local other = if character then fighterOf(character) else nil
				local run = other and other.run
				if other and run and (other.root.Position - fighter.root.Position).Magnitude < 14 then
					local untilActive = run.move.Startup - other:MoveFrame()
					if untilActive >= 0 and untilActive <= 3 then
						fighter:SetBlock(true)
						dummy.parryRelease = now + 8 * FRAME
						break
					end
				end
			end
		end
	elseif mode == "Attack" then
		fighter:SetBlock(false)
		local target = nearestPlayer(dummy, 9, fighterOf)
		if target and fighter.state == "Idle" and now >= dummy.nextAttack then
			local toward = target.root.Position - fighter.root.Position
			local flat = Vector3.new(toward.X, 0, toward.Z)
			if flat.Magnitude > 0.1 then
				fighter.root.CFrame = CFrame.lookAlong(fighter.root.Position, flat.Unit)
			end
			if dummy.chainLeft <= 0 then
				dummy.chainLeft = 3
			end
			local chain = 4 - dummy.chainLeft
			local id = if chain == 1 then "Sword.M1_1" elseif chain == 2 then "Sword.M1_2" else "Sword.M1_3"
			if fighter:RequestMove(id, 0) == "" then
				dummy.chainLeft -= 1
				dummy.nextAttack = if dummy.chainLeft <= 0 then now + 1.6 else now
			else
				dummy.chainLeft = 0
			end
		end
	else
		fighter:SetBlock(false)
	end
end

-- Every frame, after the fighters stepped.
function Dummies.Step(now: number, fighterOf: (Model) -> Fighter?)
	for _, dummy in list do
		local fighter = dummy.fighter
		think(dummy, now, fighterOf)
		-- Play the move the server started for it.
		local run = fighter.run
		if run then
			local key = run.move.Id .. ":" .. tostring(run)
			if dummy.lastRun ~= key then
				dummy.lastRun = key
				dummy.anim:Play(run.move.Animation)
				-- The move's step forward (players' clients do this for themselves).
				local step = run.move.Motion.Step
				if step > 0 then
					local seconds = math.max(run.move.Startup, 1) * FRAME
					local look = fighter.root.CFrame.LookVector
					dummy.body:Push(Vector3.new(look.X, 0, look.Z).Unit * (step / seconds), seconds)
				end
			end
		else
			dummy.lastRun = nil
		end
		if fighter.combo.hits > 0 then
			dummy.shownHits, dummy.shownDamage = fighter.combo.hits, fighter.combo.damage
		end
		-- Heal up a while after the last hit.
		if now - fighter.lastHitAt > Config.DummyResetTime and fighter.humanoid.Health < fighter.humanoid.MaxHealth
			and not fighter:IsLocked()
		then
			fighter.humanoid.Health = fighter.humanoid.MaxHealth
		end
		-- Knocked far away: back home once it's free again.
		if fighter.state == "Idle" and (fighter.root.Position - dummy.home.Position).Magnitude > 40 then
			Dummies.Reset(dummy)
		end
		local mode = dummy.model:GetAttribute("DummyMode")
		dummy.label.Text = string.format("%s  [%s]\ncombo %d hits  %.1f dmg  HP %d", tostring(mode), fighter.state,
			dummy.shownHits, dummy.shownDamage, math.floor(fighter.humanoid.Health + 0.5))
	end
end

function Dummies.Folder(): Folder?
	return folder
end

return Dummies
