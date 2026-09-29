--!strict
-- MovementSelfTest (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > MovementSelfTest
--
-- Studio-only. F6 during Play runs only the dash test, F8 the wall hop test, F10 the landing
-- roll test (also: PlayerGui.MovementSelfTest.RunRollTest:Fire() from the command bar). Press F4 during Play to run an automatic movement test (F4 again hides the report): it takes over your
-- character, runs jump / wall / ledge / fall / speed checks on the test course, then shows
-- a PASS/FAIL report on screen and in Output.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("CharacterMotor")
movementFolder:WaitForChild("MovementConfig")
movementFolder:WaitForChild("Dash")
movementFolder:WaitForChild("WallHop")
movementFolder:WaitForChild("LandingRoll")
movementFolder:WaitForChild("AutoParkour")
movementFolder:WaitForChild("Lantern")
movementFolder:WaitForChild("Stamina")

local CharacterMotor = require(ReplicatedStorage.Movement.CharacterMotor)
local Dash = require(ReplicatedStorage.Movement.Dash)
local WallHop = require(ReplicatedStorage.Movement.WallHop)
local LandingRoll = require(ReplicatedStorage.Movement.LandingRoll)
local AutoParkour = require(ReplicatedStorage.Movement.AutoParkour)
local Lantern = require(ReplicatedStorage.Movement.Lantern)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local Perf = require(ReplicatedStorage.Movement.Perf)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

local RUN_KEY = Enum.KeyCode.F4
local DASH_TEST_KEY = Enum.KeyCode.F6
local WALL_TEST_KEY = Enum.KeyCode.F8
local ROLL_TEST_KEY = Enum.KeyCode.F10
local player = Players.LocalPlayer

-- Report UI -------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MovementSelfTest"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Enabled = false

local reportLabel = Instance.new("TextLabel")
reportLabel.AnchorPoint = Vector2.new(1, 0)
reportLabel.Position = UDim2.new(1, -10, 0, 50)
reportLabel.Size = UDim2.fromOffset(620, 470)
reportLabel.BackgroundColor3 = Color3.new(0, 0, 0)
reportLabel.BackgroundTransparency = 0.3
reportLabel.BorderSizePixel = 0
reportLabel.Font = Enum.Font.Code
reportLabel.TextSize = 14
reportLabel.TextColor3 = Color3.new(1, 1, 1)
reportLabel.TextXAlignment = Enum.TextXAlignment.Left
reportLabel.TextYAlignment = Enum.TextYAlignment.Top
reportLabel.TextWrapped = true
reportLabel.RichText = true
reportLabel.Text = ""
reportLabel.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local lines: { string } = {}

local function log(text: string)
	table.insert(lines, text)
	reportLabel.Text = table.concat(lines, "\n")
	print("[MovementSelfTest] " .. text:gsub("<[^>]+>", ""))
end

local function result(name: string, passed: boolean, detail: string)
	local tag = if passed then '<font color="#6BE36B">PASS</font>' else '<font color="#FF6060">FAIL</font>'
	log(string.format("%s %s: %s", tag, name, detail))
end

-- Helpers ---------------------------------------------------------------------

type Rig = {
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
}

local function getRig(): Rig?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local motor = CharacterMotor.Get(character)
	if not humanoid or not root or not root:IsA("BasePart") or not motor then
		return nil
	end
	return { humanoid = humanoid, root = root, motor = motor }
end

local function waitFor(condition: () -> boolean, timeout: number): boolean
	local start = os.clock()
	while os.clock() - start < timeout do
		if condition() then
			return true
		end
		task.wait()
	end
	return condition()
end

local function setMove(rig: Rig, direction: Vector3, sprint: boolean)
	rig.motor:SetSprinting(sprint)
	rig.humanoid:Move(direction, false)
end

local function stop(rig: Rig)
	setMove(rig, Vector3.zero, false)
	rig.humanoid.Jump = false
end

local function teleport(rig: Rig, position: Vector3, facing: Vector3)
	stop(rig)
	rig.root.AssemblyLinearVelocity = Vector3.zero
	rig.root.CFrame = CFrame.lookAt(position, position + facing)
	task.wait(0.1)
	waitFor(function()
		return rig.motor:GetMode() == "Ground"
	end, 3)
	task.wait(0.4)
end

type JumpStats = {
	height: number,
	airtime: number,
	hang: number,
	maxY: number,
	peakSpeed: number,
}

-- Presses jump once (the move direction set beforehand stays held) and watches the airtime.
local function jumpOnce(rig: Rig, timeout: number?): JumpStats
	local startY = rig.root.Position.Y
	rig.humanoid.Jump = true
	waitFor(function()
		return rig.motor:GetMode() == "Air"
	end, 0.5)
	rig.humanoid.Jump = false

	local start = os.clock()
	local maxY = startY
	local hang = 0
	local peakSpeed = 0
	local limit = timeout or 4
	while rig.motor:GetMode() == "Air" and os.clock() - start < limit do
		local dt = task.wait()
		local velocity = rig.root.AssemblyLinearVelocity
		maxY = math.max(maxY, rig.root.Position.Y)
		peakSpeed = math.max(peakSpeed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
		-- A normal jump is over in well under a second. Hovering after that = stuck.
		if os.clock() - start > 0.7 and math.abs(velocity.Y) < 4 then
			hang += dt
		end
	end
	return {
		height = maxY - startY,
		airtime = os.clock() - start,
		hang = hang,
		maxY = maxY,
		peakSpeed = peakSpeed,
	}
end

local function spread(values: { number }): (number, number)
	local low, high = math.huge, -math.huge
	for _, v in values do
		low = math.min(low, v)
		high = math.max(high, v)
	end
	return low, high
end

local function list(values: { number }): string
	local parts = {}
	for _, v in values do
		table.insert(parts, string.format("%.2f", v))
	end
	return table.concat(parts, " ")
end

-- Tests -------------------------------------------------------------------------

local OPEN_AREA = Vector3.new(140, 4, -140)
local TOLERANCE = 0.35

local function testSpeeds(rig: Rig)
	teleport(rig, OPEN_AREA, Vector3.zAxis)
	setMove(rig, Vector3.zAxis, false)
	task.wait(0.8)
	local walk = rig.motor:GetHorizontalSpeed()
	result("Walk speed", math.abs(walk - Config.WalkSpeed) < 0.5, string.format("%.2f (want %d)", walk, Config.WalkSpeed))

	local start = os.clock()
	setMove(rig, Vector3.zAxis, true)
	local reached = waitFor(function()
		return rig.motor:GetHorizontalSpeed() >= Config.RunSpeed - 0.5
	end, 2)
	local rampTime = os.clock() - start
	task.wait(0.5)
	local run = rig.motor:GetHorizontalSpeed()
	result(
		"Run speed",
		reached and math.abs(run - Config.RunSpeed) < 0.5,
		string.format("%.2f (want %d), reached in %.2fs (want ~%.2f)", run, Config.RunSpeed, rampTime, Config.RunAccelTime)
	)
	stop(rig)
end

local function testJumpHeights(rig: Rig, label: string, direction: Vector3, sprint: boolean, count: number)
	teleport(rig, OPEN_AREA, Vector3.zAxis)
	setMove(rig, direction, sprint)
	task.wait(if sprint then 0.6 else 0.2)
	local heights = {}
	for _ = 1, count do
		local stats = jumpOnce(rig)
		table.insert(heights, stats.height)
		task.wait(0.15) -- let the Humanoid settle so every jump starts from the ground
	end
	stop(rig)
	local low, high = spread(heights)
	local ok = math.abs(low - Config.JumpHeight) <= TOLERANCE and math.abs(high - Config.JumpHeight) <= TOLERANCE
	result(label, ok, string.format("%s (want %.1f)", list(heights), Config.JumpHeight))
end

local function testHeldJump(rig: Rig)
	teleport(rig, OPEN_AREA, Vector3.zAxis)
	setMove(rig, Vector3.zAxis, true)
	task.wait(0.6)
	-- Hold jump the whole time, like holding Space: the Humanoid re-jumps on every landing.
	rig.humanoid.Jump = true
	local groundY = rig.root.Position.Y
	local heights = {}
	local maxY = groundY
	local wasAir = false
	local start = os.clock()
	while #heights < 5 and os.clock() - start < 8 do
		rig.humanoid.Jump = true
		task.wait()
		local inAir = rig.motor:GetMode() == "Air"
		if inAir then
			maxY = math.max(maxY, rig.root.Position.Y)
		elseif wasAir then
			table.insert(heights, maxY - groundY)
			maxY = groundY
		end
		wasAir = inAir
	end
	stop(rig)
	local low, high = spread(heights)
	local ok = #heights >= 5 and math.abs(low - Config.JumpHeight) <= TOLERANCE and math.abs(high - Config.JumpHeight) <= TOLERANCE
	result("Held-jump heights", ok, string.format("%s (want %.1f)", list(heights), Config.JumpHeight))
end

-- Tall wall: x 33..35, y 0..24, z 32..80 in the test course.
local function testWall(rig: Rig, label: string, direction: Vector3, sprint: boolean, jumpAfterContact: boolean)
	local startPos = Vector3.new(33 - 10 * direction.X, 4, 56 - 10 * direction.Z)
	teleport(rig, startPos, direction)
	setMove(rig, direction, sprint)
	local stats: JumpStats
	if jumpAfterContact then
		task.wait(1) -- run into the wall and keep pushing
		stats = jumpOnce(rig, 4)
	else
		task.wait(0.15)
		stats = jumpOnce(rig, 4) -- jump early so we reach the wall mid-air
	end
	stop(rig)
	local ok = stats.hang < 0.1 and stats.airtime < 1.2
	result(label, ok, string.format("airtime %.2fs, hanging %.2fs", stats.airtime, stats.hang))
end

-- Red ledge: 9 high, x -38..-22, z 64..80. Standing on it puts the root at y ~12.
local function testLedge(rig: Rig)
	teleport(rig, Vector3.new(-30, 4, 52), Vector3.zAxis)
	-- Walking: sprinting into the ledge now climbs it (auto parkour; see the parkour test).
	setMove(rig, Vector3.zAxis, false)
	local highest = 0
	local fastestRise = 0
	local atHighest = ""
	local tracker = RunService.Heartbeat:Connect(function()
		local y = rig.root.Position.Y
		if y > highest then
			highest = y
			atHighest = string.format("z %.2f, %s", rig.root.Position.Z, rig.humanoid:GetState().Name)
		end
		fastestRise = math.max(fastestRise, rig.root.AssemblyLinearVelocity.Y)
	end)
	local start = os.clock()
	while os.clock() - start < 4 do
		jumpOnce(rig, 2)
	end
	tracker:Disconnect()
	stop(rig)
	-- Jumping at the 9-stud ledge grabs and scales it (auto parkour ledge grab). Standing on top
	-- puts the root at 12; one more jump from there peaks at 19.2. Anything higher is a fling.
	local onTop = highest > 11.5
	local flung = highest > 12 + Config.JumpHeight + 0.6
	result(
		"9-stud ledge: jumping at it grabs and scales it, no fling",
		onTop and not flung,
		string.format("ended y %.1f, highest %.1f (%s), rise %.1f", rig.root.Position.Y, highest, atHighest, fastestRise)
	)
end

-- Blue jump box: 4 high, x -38..-22, z 32..48.
local function testJumpBox(rig: Rig)
	teleport(rig, Vector3.new(-30, 4, 22), Vector3.zAxis)
	setMove(rig, Vector3.zAxis, false)
	task.wait(0.3)
	jumpOnce(rig, 2)
	task.wait(0.3)
	stop(rig)
	local onTop = rig.root.Position.Y > 6
	result("4-stud box reachable", onTop, string.format("ended at y %.1f", rig.root.Position.Y))
end

local function testFall(rig: Rig)
	stop(rig)
	rig.root.AssemblyLinearVelocity = Vector3.zero
	rig.root.CFrame = CFrame.new(OPEN_AREA + Vector3.new(0, 300, 0))
	task.wait(0.1)
	-- Effective gravity from 0.1 s to 0.3 s into the fall. The ramp goes from 1x to
	-- FallGravityMax over FallGravityRampTime, so compare against its average over that window.
	local v1, t1 = rig.root.AssemblyLinearVelocity.Y, os.clock()
	task.wait(0.2)
	local v2, t2 = rig.root.AssemblyLinearVelocity.Y, os.clock()
	local measured = (v1 - v2) / (t2 - t1) / workspace.Gravity
	local rampTime = math.max(Config.FallGravityRampTime, 1e-3)
	local function ramp(t: number): number
		return 1 + (Config.FallGravityMax - 1) * math.clamp(t / rampTime, 0, 1)
	end
	local expected = (ramp(0.1) + ramp(0.2) * 2 + ramp(0.3)) / 4
	result(
		"Fall gravity",
		math.abs(measured - expected) < 0.15,
		string.format("%.2fx (want ~%.2fx while ramping to %.1fx)", measured, expected, Config.FallGravityMax)
	)
	local maxFall = 0
	waitFor(function()
		maxFall = math.max(maxFall, -rig.root.AssemblyLinearVelocity.Y)
		return rig.motor:GetMode() ~= "Air"
	end, 8)
	local ok = maxFall <= Config.TerminalVelocity + 0.5 and maxFall >= Config.TerminalVelocity - 1
	result("Terminal velocity", ok, string.format("max fall %.2f (want %d)", maxFall, Config.TerminalVelocity))
end

-- Runner ------------------------------------------------------------------------

local running = false

local function getControls(): any?
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall((require :: any), module)
	if not ok then
		return nil
	end
	return playerModule:GetControls()
end

-- Records every airtime during the test so unexpectedly high jumps can be explained.
type Airtime = {
	startY: number,
	startZ: number,
	maxY: number,
	maxRise: number,
	frames: number,
	states: { [string]: boolean },
	liftFrames: number,
	groundFrames: number,
}

local function startAirtimeRecorder(rig: Rig): (() -> { Airtime }, () -> ())
	local records: { Airtime } = {}
	local current: Airtime? = nil
	local connection = RunService.Heartbeat:Connect(function()
		local mode = rig.motor:GetMode()
		local position = rig.root.Position
		local velocity = rig.root.AssemblyLinearVelocity
		if mode == "Air" then
			if not current then
				current = {
					startY = position.Y,
					startZ = position.Z,
					maxY = position.Y,
					maxRise = 0,
					frames = 0,
					states = {},
					liftFrames = 0,
					groundFrames = 0,
				}
			end
			local record = current :: Airtime
			record.frames += 1
			record.maxY = math.max(record.maxY, position.Y)
			record.maxRise = math.max(record.maxRise, velocity.Y)
			record.states[rig.humanoid:GetState().Name] = true
			local force = rig.root:FindFirstChild("MotorGravity")
			if force and force:IsA("VectorForce") and force.Force.Y > 0 then
				record.liftFrames += 1
			end
		elseif current then
			table.insert(records, current)
			current = nil
		end
	end)
	return function()
		return records
	end, function()
		connection:Disconnect()
	end
end

local function reportHighAirtimes(records: { Airtime })
	local count = 0
	for _, record in records do
		local height = record.maxY - record.startY
		if height > Config.JumpHeight + 1 then
			count += 1
			if count <= 4 then
				local names = {}
				for name in record.states do
					table.insert(names, name)
				end
				log(string.format(
					"  high airtime: +%.2f from y %.1f z %.1f, rise %.1f, %d frames, lift %d, states %s",
					height,
					record.startY,
					record.startZ,
					record.maxRise,
					record.frames,
					record.liftFrames,
					table.concat(names, "/")
				))
			end
		end
	end
	log(string.format("Airtimes recorded: %d, higher than a jump: %d", #records, count))
end

local function runAll()
	local rig = getRig()
	if not rig then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Movement self-test</b> (don't touch the keyboard)")

	local controls = getControls()
	if controls then
		controls:Disable()
	end

	local getRecords, stopRecorder = startAirtimeRecorder(rig)
	local ok, err = pcall(function()
		testSpeeds(rig)
		testJumpHeights(rig, "Standing jumps", Vector3.zero, false, 5)
		testJumpHeights(rig, "Walking jumps", Vector3.zAxis, false, 5)
		testJumpHeights(rig, "Running jumps", Vector3.zAxis, true, 5)
		testHeldJump(rig)
		testWall(rig, "Wall: run + jump into it", Vector3.xAxis, true, false)
		testWall(rig, "Wall: push, then jump", Vector3.xAxis, true, true)
		testWall(rig, "Wall: diagonal run + jump", Vector3.new(1, 0, 1).Unit, true, false)
		testWall(rig, "Wall: walk + jump into it", Vector3.xAxis, false, false)
		testJumpBox(rig)
		testLedge(rig)
		testFall(rig)
	end)
	stopRecorder()
	reportHighAirtimes(getRecords())
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end

	stop(rig)
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. F4 hides this report; F4 again re-runs the test.")
	running = false
end

-- Dash test (F6) -------------------------------------------------------------------

local function near(value: number, want: number, tolerance: number): boolean
	return math.abs(value - want) <= tolerance
end

local function runDashTest()
	local rig = getRig()
	local character = player.Character
	local dash = if character then Dash.Get(character) else nil
	if not rig or not dash then
		warn("[MovementSelfTest] Character or dash not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Dash test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local animator = rig.humanoid:FindFirstChildOfClass("Animator")

	-- Dashes from a standstill at `position` facing `look`, holding `move` (world direction).
	local function trial(position: Vector3, look: Vector3, move: Vector3, punchAt: number?): (boolean, number, { [string]: boolean }, boolean, Vector3)
		teleport(rig, position, look)
		task.wait(math.max(dash:GetCooldownRemaining(), 0) + 0.05)
		local start = rig.root.Position
		local ok = dash:Request(move, look)
		local seen: { [string]: boolean } = {}
		local punched = false
		local t0 = os.clock()
		while os.clock() - t0 < 1.3 do
			if punchAt and not punched and os.clock() - t0 >= punchAt then
				punched = dash:Punch()
			end
			if animator then
				for _, track in animator:GetPlayingAnimationTracks() do
					seen[track.Animation and track.Animation.Name or "?"] = true
				end
			end
			task.wait()
		end
		local moved = (rig.root.Position - start) * Vector3.new(1, 0, 1)
		return ok, moved.Magnitude, seen, punched, moved
	end

	local ok, err = pcall(function()
		local lane = Vector3.new(60, 4, -40)
		local forward = Vector3.zAxis
		local right = Vector3.new(-1, 0, 0) -- right of a character looking +Z
		type Case = { name: string, move: Vector3, want: number, anim: string }
		local cases: { Case } = {
			{ name = "Front dash (no keys)", move = Vector3.zero, want = Config.FrontDashDistance, anim = "DashForward" },
			{ name = "Front dash (W)", move = forward, want = Config.FrontDashDistance, anim = "DashForward" },
			{ name = "Side dash right (D)", move = right, want = Config.SideDashDistance, anim = "DashRight" },
			{ name = "Side dash left (A)", move = -right, want = Config.SideDashDistance, anim = "DashLeft" },
			{ name = "Back dash (S)", move = -forward, want = Config.SideDashDistance, anim = "DashBack" },
			{ name = "W+A -> front", move = (forward - right).Unit, want = Config.FrontDashDistance, anim = "DashForward" },
			{ name = "W+D -> front", move = (forward + right).Unit, want = Config.FrontDashDistance, anim = "DashForward" },
			{ name = "S+A -> back", move = (-forward - right).Unit, want = Config.SideDashDistance, anim = "DashBack" },
			{ name = "S+D -> back", move = (-forward + right).Unit, want = Config.SideDashDistance, anim = "DashBack" },
		}
		for _, case in cases do
			local name, move, want, anim = case.name, case.move, case.want, case.anim
			local started, _, seen, _, moved = trial(lane, forward, move, nil)
			-- Held keys carry walking speed past the dash end, so measure the dash itself.
			local distance = dash:GetLastDistance()
			-- It must go straight along one axis (no diagonal dashes).
			local expected = if anim == "DashForward" then forward
				elseif anim == "DashBack" then -forward
				elseif anim == "DashRight" then right
				else -right
			local offAxis = if moved.Magnitude > 0.1
				then math.deg(math.acos(math.clamp(moved.Unit:Dot(expected), -1, 1)))
				else 180
			result(
				name,
				started and near(distance, want, 1) and seen[anim] == true and offAxis < 4,
				string.format("%.2f studs (want %.1f), anim %s, %.1f deg off its axis", distance, want,
					if seen[anim] then "ok" else "MISSING", offAxis)
			)
		end

		-- Punches at the test dummy (80, 3, 40), approached along +X.
		local _, _, seenFar, punchedFar = trial(Vector3.new(70, 4, 40), Vector3.xAxis, Vector3.zero, 0.14)
		local far = dash:GetLastPunchResult()
		result("Dash punch, late (stun)", punchedFar and far == "stun" and seenFar.DashPunch == true,
			string.format("result %s, anim %s", far, if seenFar.DashPunch then "ok" else "MISSING"))
		local _, _, _, punchedNear = trial(Vector3.new(76, 4, 40), Vector3.xAxis, Vector3.zero, 0)
		local near = dash:GetLastPunchResult()
		result("Dash punch, early (ragdoll)", punchedNear and near == "ragdoll", "result " .. near)
		local _, missMoved, _, punchedMiss = trial(lane, forward, Vector3.zero, 0.2)
		result("Dash punch, whiff", punchedMiss and dash:GetLastPunchResult() == "miss",
			string.format("result %s, slid %.1f studs", dash:GetLastPunchResult(), missMoved))
		local _, lungeMoved = trial(lane, forward, Vector3.zero, Config.FrontDashTime - 0.08)
		result("Punch at dash end still lunges", lungeMoved > Config.FrontDashDistance + 2,
			string.format("%.1f studs total", lungeMoved))

		-- Dashing into obstacles must never launch you. A FRONT dash into something vaultable /
		-- step-up-able hands over to auto parkour (keeping dash speed): then it may rise over the
		-- obstacle (maxRise), but no higher.
		type Obstacle = { name: string, from: Vector3, look: Vector3, move: Vector3, maxRise: number }
		local obstacles: { Obstacle } = {
			{ name = "vault box (3 high): vaults it", from = Vector3.new(0, 4, 30), look = forward, move = Vector3.zero, maxRise = 3 + 1.2 },
			{ name = "jump box (4 high): steps up", from = Vector3.new(-30, 4, 24), look = forward, move = Vector3.zero, maxRise = 4 + 1.2 },
			{ name = "tall wall", from = Vector3.new(22, 4, 56), look = Vector3.xAxis, move = Vector3.zero, maxRise = 1.2 },
			{ name = "tall wall, diagonal", from = Vector3.new(24, 4, 46), look = Vector3.new(1, 0, 1).Unit, move = Vector3.zero, maxRise = 1.2 },
			{ name = "vault box, side dash", from = Vector3.new(-12, 4, 40), look = -Vector3.zAxis, move = Vector3.new(1, 0, 0), maxRise = 1.2 },
		}
		for _, obstacle in obstacles do
			teleport(rig, obstacle.from, obstacle.look)
			task.wait(dash:GetCooldownRemaining() + 0.05)
			local startY = rig.root.Position.Y
			local maxY = startY
			dash:Request(obstacle.move, obstacle.look)
			local t0 = os.clock()
			while os.clock() - t0 < 1 do
				maxY = math.max(maxY, rig.root.Position.Y)
				task.wait()
			end
			local rise = maxY - startY
			result("Dash into " .. obstacle.name, rise < obstacle.maxRise,
				string.format("rose %.2f studs (max %.1f), dash ended: %s", rise, obstacle.maxRise, dash:GetLastEndReason()))
		end

		-- Cooldown.
		teleport(rig, lane, forward)
		task.wait(dash:GetCooldownRemaining() + 0.05)
		local first = dash:Request(Vector3.zero, forward)
		task.wait(Config.DashCooldown - 0.3)
		local early = dash:Request(Vector3.zero, forward)
		task.wait(0.35)
		local after = dash:Request(Vector3.zero, forward)
		result("Cooldown", first and not early and after,
			string.format("first %s, at %.1fs %s, at %.1fs %s", tostring(first), Config.DashCooldown - 0.3,
				tostring(early), Config.DashCooldown + 0.05, tostring(after)))
		task.wait(1)
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. F6 hides this report.")
	running = false
end

-- Wall hop test (F8) ----------------------------------------------------------------
-- Uses the course's tall wall (x 33..35, z 32..80, 24 high) and the zig-zag alley (Workspace >
-- WallHopAlley: walls at x = 100 and x = 114, z 28..92; built here if the place doesn't have it).
-- Space is simulated the way MovementController does it (motor:RequestJump + hop:OnJumpPressed).

local ALLEY_LEFT_X, ALLEY_RIGHT_X = 100, 114

local function ensureAlley()
	if Workspace:FindFirstChild("WallHopAlley") then
		return
	end
	local model = Instance.new("Model")
	model.Name = "WallHopAlley"
	for _, x in { ALLEY_LEFT_X, ALLEY_RIGHT_X } do
		local wall = Instance.new("Part")
		wall.Name = "AlleyWall"
		wall.Anchored = true
		wall.Size = Vector3.new(2, 30, 64)
		wall.Position = Vector3.new(x, 15, 60)
		wall.Color = Color3.fromRGB(99, 95, 98)
		wall.Parent = model
	end
	model.Parent = Workspace
end

local function runWallTest()
	local rig = getRig()
	local character = player.Character
	local hop = if character then WallHop.Get(character) else nil
	if not rig or not hop then
		warn("[MovementSelfTest] Character or wall hop not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Wall hop test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		local function pressSpace()
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			hop:OnJumpPressed(rig.motor:RequestJump())
		end
		local function releaseSpace()
			rig.motor:SetJumpHeld(false)
			rig.humanoid.Jump = false
		end
		local function land(timeout: number)
			releaseSpace()
			stop(rig)
			waitFor(function()
				return rig.motor:GetMode() == "Ground"
			end, timeout)
			task.wait(0.1)
		end

		-- style: "hold" = Space held from the jump; "tap" = a quick jump only; "airpress" = a quick
		-- jump, then Space pressed again in the air at 0.3 s.
		-- The wall hop reads the keys relative to the camera, so the test aims the camera: looking
		-- +Z, world (1,0,1) is W+A and world (0,0,1) is W alone.
		local camera = Workspace.CurrentCamera
		local function aimCamera(look: Vector3)
			camera.CameraType = Enum.CameraType.Scriptable
			local at = rig.root.Position
			camera.CFrame = CFrame.lookAt(at - look.Unit * 12 + Vector3.new(0, 5, 0), at)
		end
		local function attempt(style: string, move: Vector3, duration: number, start: Vector3?, look: Vector3?): (number, number, number)
			teleport(rig, start or Vector3.new(30, 4, 40), Vector3.zAxis)
			aimCamera(look or Vector3.zAxis)
			task.wait(0.1)
			local before = hop:GetTotalHops()
			local startY = rig.root.Position.Y
			local startZ = rig.root.Position.Z
			local maxY = startY
			pressSpace()
			local t0 = os.clock()
			local released, pressedAgain = false, false
			while os.clock() - t0 < duration do
				local t = os.clock() - t0
				if style ~= "hold" and not released and t > 0.08 then
					releaseSpace()
					released = true
				end
				if style == "airpress" and not pressedAgain and t > 0.3 then
					pressSpace()
					pressedAgain = true
				end
				if pressedAgain and t > 0.38 then
					releaseSpace()
				end
				rig.humanoid:Move(move, false)
				maxY = math.max(maxY, rig.root.Position.Y)
				task.wait()
			end
			land(4)
			return hop:GetTotalHops() - before, maxY - startY, rig.root.Position.Z - startZ
		end

		local into = Vector3.new(1, 0, 1).Unit -- wall is at +X, run along +Z
		local tapped = attempt("tap", into, 1.2)
		result("Just jumping into the wall (tap) does NOT hop", tapped == 0,
			string.format("%d hop(s), reason: %s", tapped, hop:GetLastFailure()))
		local hops, rise, along = attempt("hold", into, 1.6)
		result("Jump + HOLD Space into + along the wall hops", hops >= 1 and rise > Config.JumpHeight + 2,
			string.format("%d hop(s), rose %.1f studs (a jump is %.1f), moved %.1f along", hops, rise, Config.JumpHeight, along))
		local pressed, pressRise = attempt("airpress", into, 1.6)
		result("Jump, then PRESS Space in the air hops", pressed == 1 and pressRise > Config.JumpHeight + 2,
			string.format("%d hop(s) (one press = one hop), rose %.1f studs", pressed, pressRise))
		-- W alone with the camera at 45 degrees to the wall: the body moves into AND along the wall,
		-- but the keys aren't W+A / W+D, so no hop.
		local wOnly = attempt("hold", into, 1.2, nil, into)
		result("W alone at an angle to the wall does NOT hop", wOnly == 0,
			string.format("%d hop(s), reason: %s", wOnly, hop:GetLastFailure()))
		local parallel = attempt("hold", Vector3.zAxis, 1.2)
		result("Running parallel (W only) does NOT hop", parallel == 0, string.format("%d hop(s)", parallel))
		local straight = attempt("hold", Vector3.xAxis, 1.2)
		result("Running straight into the wall does NOT hop", straight == 0, string.format("%d hop(s)", straight))
		local noWall = attempt("hold", -Vector3.xAxis, 1.2)
		result("Moving away does NOT hop", noWall == 0, string.format("%d hop(s)", noWall))
		-- Input into + along toward -Z: the run must go -Z (the way the input points), never +Z.
		local backHops, _, backAlong = attempt("hold", Vector3.new(1, 0, -1).Unit, 1.2, nil, -Vector3.zAxis)
		result("Hop goes the way the input points", backHops >= 1 and backAlong < -3,
			string.format("%d hop(s), moved %.1f along Z (want negative)", backHops, backAlong))
		-- Near the end of the wall (it ends at z = 80): no hop that would run straight off it.
		local endHops = attempt("hold", into, 0.5, Vector3.new(30, 4, 78.5))
		result("No hop at the very end of the wall", endHops == 0,
			string.format("%d hop(s), last reason: %s", endHops, hop:GetLastFailure()))

		-- Hops allowed by health.
		local maxHealth = rig.humanoid.MaxHealth
		local saved = rig.humanoid.Health
		local counts = {}
		for _, share in { 1, 0.5, 0.2 } do
			rig.humanoid.Health = maxHealth * share
			table.insert(counts, hop:GetMaxHops())
		end
		rig.humanoid.Health = saved
		result("Hops by health (100% / 50% / 20%)",
			counts[1] == Config.WallHopsHigh and counts[2] == Config.WallHopsMid and counts[3] == Config.WallHopsLow,
			string.format("%d / %d / %d", counts[1], counts[2], counts[3]))

		-- Chaining up one wall: Space held, keys kept into it.
		local chained, chainRise = attempt("hold", into, 3)
		result("Chain hops up one wall", chained >= 2 and chained <= Config.WallHopsHigh,
			string.format("%d hops (max %d), highest point +%.1f studs", chained, Config.WallHopsHigh, chainRise))

		-- Zig-zag across the alley with Space held. `switchAt`: when to turn the keys toward the
		-- other wall, in seconds after a hop starts (a negative value = that long AFTER the kick).
		ensureAlley()
		local toRight = Vector3.new(1, 0, 1).Unit
		local toLeft = Vector3.new(-1, 0, 1).Unit
		-- Three hops carry you ~65 studs along and ~34 up; the alley is 64 long and 30 tall, so
		-- the third hop can pass over / beyond it. Temporary walls z 28..140, 60 tall.
		local extension = Instance.new("Model")
		extension.Name = "AlleyTestExtension"
		for _, x in { ALLEY_LEFT_X, ALLEY_RIGHT_X } do
			local wall = Instance.new("Part")
			wall.Anchored = true
			wall.Size = Vector3.new(2, 60, 112)
			wall.Position = Vector3.new(x, 30, 84)
			wall.Parent = extension
		end
		extension.Parent = Workspace
		local zigTrace: { string } = {}
		local lastTraceAt: number? = nil
		local function zigzag(switchAt: number): (number, string, number)
			table.clear(zigTrace)
			lastTraceAt = nil
			teleport(rig, Vector3.new(109, 4, 32), Vector3.zAxis)
			aimCamera(Vector3.zAxis)
			task.wait(0.1)
			local before = hop:GetTotalHops()
			local startY = rig.root.Position.Y
			local maxY = startY
			local sides = ""
			local move = toRight
			local seen = 0
			local hopAt, kickAt = 0, 0
			local wasRunning = false
			pressSpace()
			local t0 = os.clock()
			while os.clock() - t0 < 4 do
				local now = os.clock()
				local total = hop:GetTotalHops() - before
				local onWall = hop:IsRunning()
				if total > seen then
					seen = total
					hopAt = now
					sides ..= if rig.root.Position.X > (ALLEY_LEFT_X + ALLEY_RIGHT_X) / 2 then "R" else "L"
				end
				if wasRunning and not onWall then
					kickAt = now
				end
				wasRunning = onWall
				-- Turn toward the other wall once, after each hop.
				local side = string.sub(sides, -1)
				local wantAway = if side == "R" then toLeft elseif side == "L" then toRight else move
				if move ~= wantAway then
					local ready = if switchAt >= 0 then now - hopAt >= switchAt else (not onWall and kickAt > hopAt and now - kickAt >= -switchAt)
					if ready then
						move = wantAway
					end
				end
				rig.humanoid:Move(move, false)
				maxY = math.max(maxY, rig.root.Position.Y)
				if seen >= 2 and #zigTrace < 14 and now - (lastTraceAt or 0) >= 0.06 then
					lastTraceAt = now
					local v = rig.root.AssemblyLinearVelocity
					table.insert(zigTrace, string.format("%.2f x%.1f vx%.0f %s%s", now - hopAt, rig.root.Position.X, v.X, if onWall then "W" else "a", if move == toRight then ">" else "<"))
				end
				if rig.motor:GetMode() == "Ground" and now - t0 > 0.5 then
					break
				end
				task.wait()
			end
			land(5)
			return hop:GetTotalHops() - before, sides, maxY - startY
		end
		local function alternates(sides: string): boolean
			for i = 2, #sides do
				if string.sub(sides, i, i) == string.sub(sides, i - 1, i - 1) then
					return false
				end
			end
			return true
		end
		local early, earlySides, earlyRise = zigzag(0.08)
		result("Zig-zag: switch keys mid-run (leap)", early == Config.WallHopsHigh and alternates(earlySides),
			string.format("%d hops, walls %s, highest +%.1f", early, earlySides, earlyRise))
		local late, lateSides, lateRise = zigzag(-0.1)
		result("Zig-zag: switch keys 0.1 s AFTER the kick", late == Config.WallHopsHigh and alternates(lateSides),
			string.format("%d hops, walls %s, highest +%.1f", late, lateSides, lateRise))
		local timed, timedSides = zigzag(Config.WallRunTime + 0.02)
		extension:Destroy()
		result("Zig-zag: switch keys right at the kick", timed == Config.WallHopsHigh and alternates(timedSides),
			string.format("%d hops, walls %s; last no-hop reason: %s\n  after hop 2: %s", timed, timedSides, hop:GetLastFailure(), table.concat(zigTrace, " | ")))
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. F8 hides this report.")
	running = false
end


-- Landing roll test (F10) ------------------------------------------------------------
-- Drops the character from set heights over open baseplate (and onto the course's JumpBox /
-- beside TallWall), pressing Space the way MovementController does.

local function runRollTest()
	local rig = getRig()
	local character = player.Character
	local roll = if character then LandingRoll.Get(character) else nil
	local hop = if character then WallHop.Get(character) else nil
	local dash = if character then Dash.Get(character) else nil
	if not rig or not roll or not hop or not dash then
		warn("[MovementSelfTest] Character or landing roll not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Landing roll test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		-- Like the real controls: while Space is held, Humanoid.Jump is set every frame.
		local spaceHeld = false
		local function pressSpace()
			spaceHeld = true
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			local made = rig.motor:RequestJump()
			hop:OnJumpPressed(made)
			roll:OnJumpPressed(made)
		end
		local function releaseSpace()
			spaceHeld = false
			rig.motor:SetJumpHeld(false)
			rig.humanoid.Jump = false
		end
		local function frame()
			if spaceHeld then
				rig.humanoid.Jump = true
			end
			task.wait()
		end

		type Drop = {
			rolled: boolean,
			rollDistance: number, -- flat distance covered during the roll
			rollDirection: Vector3, -- flat direction of the roll
			endSpeed: number, -- flat speed right after the roll
			rise: number, -- highest point after touching down, above the landing height
			jumpedAfter: boolean, -- left the ground again within 0.5 s after the landing / roll
			info: string,
			fall: number,
		}

		-- style: "late" = press ~0.08 s before touchdown; "early" = ~0.5 s before; "none";
		-- "hold" = late press, kept held for 1.2 s; "rolljump" = late press + a fresh press near the
		-- end of the roll.
		-- `keys`: what the keys hold during the fall and roll (default: the fall direction).
		local function drop(ground: Vector3, height: number, horizontal: Vector3, style: string, keys: Vector3?): Drop
			teleport(rig, ground, if horizontal.Magnitude > 0.1 then horizontal.Unit else Vector3.zAxis)
			local restY = rig.root.Position.Y
			local rollsBefore = roll:GetTotalRolls()
			local move = keys or (if horizontal.Magnitude > 0.1 then horizontal.Unit else Vector3.zero)
			rig.root.CFrame = rig.root.CFrame + Vector3.new(0, height, 0)
			rig.root.AssemblyLinearVelocity = horizontal
			local pressed = false
			local released = false
			local pressAt = 0
			local boosted = false
			local t0 = os.clock()
			-- Fall.
			while rig.motor:GetMode() ~= "Ground" or os.clock() - t0 < 0.15 do
				if os.clock() - t0 > 6 then
					break
				end
				rig.humanoid:Move(move, false)
				-- Give the fall its horizontal speed once the motor is in the air (the teleport's
				-- ground frame would otherwise cap it at walk speed).
				if not boosted and rig.motor:GetMode() == "Air" then
					boosted = true
					local vy = rig.root.AssemblyLinearVelocity.Y
					rig.root.AssemblyLinearVelocity = Vector3.new(horizontal.X, vy, horizontal.Z)
					rig.motor:ApplyMomentum(horizontal)
				end
				local vy = -rig.root.AssemblyLinearVelocity.Y
				local above = rig.root.Position.Y - restY
				local lead = if style == "early" then 0.5 elseif style == "none" then -1 else 0.08
				if not pressed and lead > 0 and vy > 1 and above <= vy * lead + 0.3 then
					pressSpace()
					pressed = true
					pressAt = os.clock()
				end
				if pressed and not released and style ~= "hold" and os.clock() - pressAt > 0.08 then
					releaseSpace()
					released = true
				end
				frame()
			end
			local landY = rig.root.Position.Y
			local landPos = rig.root.Position
			local rolled = roll:GetTotalRolls() > rollsBefore
			local maxY = landY
			local jumpedAfter = false
			local freshPressed = false
			local t1 = os.clock()
			-- Roll (if any).
			while roll:IsRolling() and os.clock() - t1 < 2 do
				rig.humanoid:Move(move, false)
				if pressed and not released and style ~= "hold" and os.clock() - pressAt > 0.08 then
					releaseSpace()
					released = true
				end
				if style == "rolljump" and not freshPressed and os.clock() - t1 > Config.LandingRollTime - 0.1 then
					releaseSpace()
					pressSpace()
					freshPressed = true
				end
				maxY = math.max(maxY, rig.root.Position.Y)
				frame()
			end
			local rollOffset = Vector3.new(rig.root.Position.X, 0, rig.root.Position.Z) - Vector3.new(landPos.X, 0, landPos.Z)
			local rollDistance = rollOffset.Magnitude
			local rollDirection = if rollDistance > 0.5 then rollOffset.Unit else Vector3.zero
			local v = rig.root.AssemblyLinearVelocity
			local endSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
			-- Afterwards.
			local t2 = os.clock()
			while os.clock() - t2 < 0.5 do
				rig.humanoid:Move(move, false)
				if style == "hold" and os.clock() - pressAt > 1.2 then
					releaseSpace()
				end
				if style == "rolljump" and os.clock() - t2 > 0.1 then
					releaseSpace()
				end
				if rig.motor:GetMode() == "Air" and rig.root.Position.Y > landY + 1 then
					jumpedAfter = true
				end
				maxY = math.max(maxY, rig.root.Position.Y)
				frame()
			end
			releaseSpace()
			stop(rig)
			waitFor(function()
				return rig.motor:GetMode() == "Ground" and not roll:IsRolling()
			end, 4)
			return {
				rolled = rolled,
				rollDistance = rollDistance,
				rollDirection = rollDirection,
				endSpeed = endSpeed,
				rise = maxY - landY,
				jumpedAfter = jumpedAfter,
				info = roll:GetLastInfo(),
				fall = roll:GetLastFall(),
			}
		end

		local open = Vector3.new(-100, 4, -100)
		local function expectedBonus(fall: number): number
			return math.min(Config.LandingRollBaseDistance + (fall - Config.LandingRollMinFall) * Config.LandingRollDistancePerStud, Config.LandingRollMaxBonus)
		end

		local a = drop(open, 20, Vector3.zero, "late")
		result("Drop 20 + press right before landing rolls", a.rolled and math.abs(a.rollDistance - expectedBonus(a.fall)) < 2,
			string.format("rolled %s, %.1f studs (want %.1f), fall %.1f", tostring(a.rolled), a.rollDistance, expectedBonus(a.fall), a.fall))
		local b = drop(open, 20, Vector3.zero, "none")
		result("Drop 20, no press: no roll", not b.rolled, string.format("rolled %s (%s)", tostring(b.rolled), b.info))
		local c = drop(open, 20, Vector3.zero, "early")
		result("Drop 20, press too early: no roll", not c.rolled, string.format("rolled %s (%s)", tostring(c.rolled), c.info))
		local d = drop(open, Config.JumpHeight - 0.5, Vector3.zero, "late")
		result("Short fall + press: no roll, normal buffered jump", not d.rolled and d.jumpedAfter,
			string.format("rolled %s, jumped again %s (%s)", tostring(d.rolled), tostring(d.jumpedAfter), d.info))
		local e = drop(open, 40, Vector3.zero, "late")
		result("Higher fall rolls farther", e.rolled and e.rollDistance > a.rollDistance + 2,
			string.format("fall %.1f -> %.1f studs (vs %.1f from %.1f)", e.fall, e.rollDistance, a.rollDistance, a.fall))
		local runSpeed = Config.RunSpeed
		local f = drop(open, 20, Vector3.zAxis * runSpeed, "late")
		local wantF = runSpeed * Config.LandingRollTime + expectedBonus(f.fall)
		result("Momentum kept through the roll", f.rolled and f.endSpeed > runSpeed - 4 and math.abs(f.rollDistance - wantF) < 4,
			string.format("end speed %.1f (landed at %d), rolled %.1f studs (want ~%.1f)", f.endSpeed, runSpeed, f.rollDistance, wantF))
		local g = drop(open, 20, Vector3.zero, "hold")
		result("Holding Space through the roll doesn't jump", g.rolled and not g.jumpedAfter and g.rise < 1.5,
			string.format("rolled %s, jumped %s, rose %.1f", tostring(g.rolled), tostring(g.jumpedAfter), g.rise))
		local h = drop(open, 20, Vector3.zAxis * 10, "rolljump")
		result("Fresh press at the end of the roll jumps out", h.rolled and h.jumpedAfter,
			string.format("rolled %s, jumped %s", tostring(h.rolled), tostring(h.jumpedAfter)))

		-- Aiming: the roll goes where the keys point, else where the camera looks, redirecting
		-- the landing speed.
		local side = drop(open, 20, Vector3.zAxis * runSpeed, "late", Vector3.xAxis)
		-- (Holding D in the air also steers the fall, so the exact landing speed varies: compare with
		-- a standing roll from the same height.)
		result("Holding D (sideways to your momentum) rolls sideways, keeping speed", side.rolled and side.rollDirection:Dot(Vector3.xAxis) > 0.9 and side.rollDistance > a.rollDistance + 4,
			string.format("roll direction (%.2f, %.2f), rolled %.1f studs (standing roll %.1f)", side.rollDirection.X, side.rollDirection.Z, side.rollDistance, a.rollDistance))
		local camera = workspace.CurrentCamera
		local oldType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAlong(open + Vector3.new(0, 10, 0), -Vector3.xAxis)
		local look = drop(open, 20, Vector3.zAxis * runSpeed, "late", Vector3.zero)
		camera.CameraType = oldType
		result("No keys: rolls where the camera looks", look.rolled and look.rollDirection:Dot(-Vector3.xAxis) > 0.9,
			string.format("camera looks -X, roll direction (%.2f, %.2f), end speed %.1f", look.rollDirection.X, look.rollDirection.Z, look.endSpeed))
		local back = drop(open, 20, Vector3.zAxis * runSpeed, "late", -Vector3.zAxis)
		result("Rolling back against your momentum keeps part of it", back.rolled and back.rollDirection:Dot(-Vector3.zAxis) > 0.9 and back.endSpeed > runSpeed * Config.LandingRollTurnKeep - 3,
			string.format("roll direction (%.2f, %.2f), end speed %.1f (keeps %.0f%%)", back.rollDirection.X, back.rollDirection.Z, back.endSpeed, Config.LandingRollTurnKeep * 100))

		-- Roll off the JumpBox's +X edge (top at y = 4, x -38..-22): the roll ends in the air.
		local box = drop(Vector3.new(-36, 8, 40), 16, Vector3.xAxis * 14, "late")
		result("Rolling off a ledge ends the roll and keeps speed", box.rolled and box.endSpeed > 10,
			string.format("rolled %s, speed leaving %.1f", tostring(box.rolled), box.endSpeed))
		-- Roll into TallWall (x 33..35): no climbing or launching.
		local wall = drop(Vector3.new(24, 4, 50), 20, Vector3.xAxis * 8, "late")
		result("Rolling into a wall doesn't launch", wall.rolled and wall.rise < 1.5,
			string.format("rolled %s, rose %.1f, moved %.1f", tostring(wall.rolled), wall.rise, wall.rollDistance))

		-- No dash during a roll.
		teleport(rig, open, Vector3.zAxis)
		local restY = rig.root.Position.Y
		rig.root.CFrame = rig.root.CFrame + Vector3.new(0, 20, 0)
		local dashed = false
		local sawRoll = false
		local t0 = os.clock()
		local pressed = false
		while os.clock() - t0 < 4 do
			local vy = -rig.root.AssemblyLinearVelocity.Y
			if not pressed and vy > 1 and rig.root.Position.Y - restY <= vy * 0.08 + 0.3 then
				pressSpace()
				pressed = true
			end
			if roll:IsRolling() then
				sawRoll = true
				releaseSpace()
				dashed = dashed or dash:Request()
			elseif sawRoll then
				break
			end
			frame()
		end
		releaseSpace()
		result("No dash during a roll", sawRoll and not dashed, string.format("rolled %s, dash started %s", tostring(sawRoll), tostring(dashed)))
		task.wait(Config.DashCooldown)
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. F10 hides this report.")
	running = false
end

-- Health speed test (command bar: PlayerGui.MovementSelfTest.RunSpeedTest:Fire()) ------------
-- Walk / run / jump at different health levels on open baseplate and compare with the config.

local function runSpeedTest()
	local rig = getRig()
	if not rig then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Health speed test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local maxHealth = rig.humanoid.MaxHealth
	local savedHealth = rig.humanoid.Health
	local ok, err = pcall(function()
		local function scaleAt(share: number): number
			local full = math.clamp(Config.HealthSpeedFullAbove, 1e-3, 1)
			return Config.LowHealthSpeedScale + (1 - Config.LowHealthSpeedScale) * math.clamp(share / full, 0, 1)
		end
		local function flatSpeed(): number
			local v = rig.root.AssemblyLinearVelocity
			return Vector3.new(v.X, 0, v.Z).Magnitude
		end
		-- Average ground speed over the last `measure` seconds of moving for `total` seconds.
		local function moveFor(sprint: boolean, total: number, measure: number): number
			local sum, count = 0, 0
			local t0 = os.clock()
			while os.clock() - t0 < total do
				setMove(rig, Vector3.zAxis, sprint)
				if os.clock() - t0 > total - measure and rig.motor:GetMode() == "Ground" then
					sum += flatSpeed()
					count += 1
				end
				task.wait()
			end
			return if count > 0 then sum / count else 0
		end

		for _, share in { 1, 0.5, 0.1 } do
			local scale = scaleAt(share)
			rig.humanoid.Health = maxHealth * share
			teleport(rig, Vector3.new(-100, 4, -160), Vector3.zAxis)
			local walk = moveFor(false, 1.0, 0.4)
			stop(rig)
			task.wait(0.3)
			teleport(rig, Vector3.new(-110, 4, -160), Vector3.zAxis)
			local run = moveFor(true, 1.4, 0.5)
			-- Jump while running: never faster in the air than on the ground.
			local jump = jumpOnce(rig)
			stop(rig)
			local wantWalk = Config.WalkSpeed * scale
			local wantRun = Config.RunSpeed * scale
			result(string.format("%d%% HP speeds (x%.2f)", share * 100, scale),
				math.abs(walk - wantWalk) < 0.6 and math.abs(run - wantRun) < 1 and jump.peakSpeed < wantRun + 1,
				string.format("walk %.1f (want %.1f), run %.1f (want %.1f), air peak %.1f", walk, wantWalk, run, wantRun, jump.peakSpeed))
			-- Standing jump + steering: air steering speed is scaled too.
			teleport(rig, Vector3.new(-120, 4, -160), Vector3.zAxis)
			setMove(rig, Vector3.zAxis, false)
			rig.humanoid.Jump = true
			local airPeak = 0
			local t0 = os.clock()
			task.wait(0.05)
			rig.humanoid.Jump = false
			while os.clock() - t0 < 0.9 do
				if rig.motor:GetMode() == "Air" then
					airPeak = math.max(airPeak, flatSpeed())
				end
				task.wait()
			end
			stop(rig)
			local wantAir = math.max(Config.AirMinSpeed, Config.WalkSpeed) * scale
			result(string.format("%d%% HP jump + steer", share * 100), airPeak < wantAir + 0.8,
				string.format("air peak %.1f (limit %.1f)", airPeak, wantAir))
		end

		-- Hit while running: slows down to the new run speed smoothly; healing speeds back up.
		rig.humanoid.Health = maxHealth
		teleport(rig, Vector3.new(-130, 4, -160), Vector3.zAxis)
		moveFor(true, 1.2, 0.2)
		rig.humanoid.Health = maxHealth * 0.1
		local after = moveFor(true, 0.05, 0.05)
		local settled = moveFor(true, 0.6, 0.2)
		local low = Config.RunSpeed * scaleAt(0.1)
		result("Taking damage mid-run slows you to the new run speed", math.abs(settled - low) < 1,
			string.format("right after %.1f, settled %.1f (want %.1f)", after, settled, low))
		rig.humanoid.Health = maxHealth
		local healed = moveFor(true, 0.8, 0.2)
		result("Healing speeds you back up", math.abs(healed - Config.RunSpeed) < 1,
			string.format("%.1f (want %.1f)", healed, Config.RunSpeed))
		stop(rig)
	end)
	rig.humanoid.Health = savedHealth
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunSpeedTest again to hide this report.")
	running = false
end

local speedEvent = Instance.new("BindableEvent")
speedEvent.Name = "RunSpeedTest"
speedEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runSpeedTest)
	end
end)
speedEvent.Parent = gui

-- A 6-stud ledge (in hand reach from the ground) for the parkour tests; built here if the place
-- doesn't have one. x -86..-74, z -66..-54, top at y 6.
local SWEEP_LEDGE_CENTER = Vector3.new(-80, 3, -60)
local SWEEP_LEDGE_SIZE = Vector3.new(12, 6, 12)
local function ensureSweepLedge()
	if Workspace:FindFirstChild("ParkourTestLedge") then
		return
	end
	local ledge = Instance.new("Part")
	ledge.Name = "ParkourTestLedge"
	ledge.Anchored = true
	ledge.Size = SWEEP_LEDGE_SIZE
	ledge.Position = SWEEP_LEDGE_CENTER
	ledge.Color = Color3.fromRGB(120, 90, 200)
	ledge.Parent = Workspace
end

-- Auto parkour test (command bar: PlayerGui.MovementSelfTest.RunParkourTest:Fire()) ----------
-- Sprints into the course's VaultBox (3 high, 2 deep), JumpBox (4 high, 16 deep), MantleLedge
-- (9 high), SlideGap (3-stud gap under a roof) and TallWall (24 high).

local function runParkourTest()
	local rig = getRig()
	local character = player.Character
	local parkour = if character then AutoParkour.Get(character) else nil
	local dash = if character then Dash.Get(character) else nil
	if not rig or not parkour or not dash then
		warn("[MovementSelfTest] Character or parkour not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Auto parkour test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local maxHealth = rig.humanoid.MaxHealth
	local savedHealth = rig.humanoid.Health
	local ok, err = pcall(function()
		type Run = {
			counts: { [string]: number },
			finalPosition: Vector3,
			maxY: number,
			minSlideY: number,
			speedAfter: number,
			yAfter: number, -- root height 0.1 s after the action finished
			startMode: string,
			info: string,
			dashDuring: boolean,
			standingAfter: boolean,
			headingAfter: number, -- degrees, direction of travel 0.1 s after the action (0 = +Z, + = toward +X)
			maxTurn: number, -- biggest change in facing in one frame while an action ran (degrees)
		}
		local ACTIONS = { "Vault", "StepUp", "Climb", "Slide" }
		local function sprintAt(start: Vector3, direction: Vector3, duration: number, sprint: boolean, jumpAfter: number?): Run
			teleport(rig, start, direction)
			-- Sprinting from a standstill (the keys alone need a double-tap).
			rig.motor:SetSprinting(sprint)
			local before: { [string]: number } = {}
			for _, name in ACTIONS do
				before[name] = parkour:GetCount(name)
			end
			local maxY = rig.root.Position.Y
			local minSlideY = math.huge
			local speedAfter = -1
			local yAfter = -math.huge
			local endedAt: number? = nil
			local headingAfter = 0
			local maxTurn = 0
			local lastYaw: number? = nil
			local wasBusy = false
			local jumped = false
			local dashDuring = false
			local t0 = os.clock()
			while os.clock() - t0 < duration do
				local t = os.clock() - t0
				setMove(rig, direction, sprint)
				if jumpAfter and not jumped and t >= jumpAfter then
					rig.humanoid.Jump = true
					jumped = true
				elseif jumped then
					rig.humanoid.Jump = false
				end
				local busy = parkour:IsBusy()
				if busy and parkour:GetAction() == "Slide" then
					minSlideY = math.min(minSlideY, rig.root.Position.Y)
					if not dashDuring then
						dashDuring = dash:Request()
					end
				end
				if wasBusy and not busy then
					endedAt = os.clock()
				end
				if endedAt and speedAfter < 0 and os.clock() - endedAt >= 0.1 then
					local v = rig.root.AssemblyLinearVelocity
					speedAfter = Vector3.new(v.X, 0, v.Z).Magnitude
					yAfter = rig.root.Position.Y
					headingAfter = math.deg(math.atan2(v.X, v.Z))
				end
				local look = rig.root.CFrame.LookVector
				local yaw = math.deg(math.atan2(look.X, look.Z))
				if busy and lastYaw then
					maxTurn = math.max(maxTurn, math.abs((yaw - lastYaw + 180) % 360 - 180))
				end
				lastYaw = yaw
				wasBusy = busy
				maxY = math.max(maxY, rig.root.Position.Y)
				task.wait()
			end
			local counts: { [string]: number } = {}
			for _, name in ACTIONS do
				counts[name] = parkour:GetCount(name) - before[name]
			end
			stop(rig)
			waitFor(function()
				return not parkour:IsBusy() and rig.motor:GetMode() == "Ground"
			end, 3)
			task.wait(0.2)
			return {
				counts = counts,
				finalPosition = rig.root.Position,
				maxY = maxY,
				minSlideY = minSlideY,
				speedAfter = speedAfter,
				yAfter = yAfter,
				startMode = parkour:GetLastStartMode(),
				info = parkour:GetLastInfo(),
				dashDuring = dashDuring,
				standingAfter = not rig.humanoid.PlatformStand and rig.motor:GetMode() == "Ground",
				headingAfter = headingAfter,
				maxTurn = maxTurn,
			}
		end
		local function total(r: Run): number
			return r.counts.Vault + r.counts.StepUp + r.counts.Climb + r.counts.Slide
		end
		local function describe(r: Run): string
			return string.format("V%d S%d C%d Sl%d, ended at (%.0f, %.1f, %.0f), %s",
				r.counts.Vault, r.counts.StepUp, r.counts.Climb, r.counts.Slide,
				r.finalPosition.X, r.finalPosition.Y, r.finalPosition.Z, r.info)
		end
		local run = Config.RunSpeed

		local v = sprintAt(Vector3.new(0, 4, 18), Vector3.zAxis, 1.8, true)
		result("Sprint into VaultBox vaults and keeps speed", v.counts.Vault == 1 and v.finalPosition.Z > 45 and v.speedAfter > run * 0.8,
			string.format("%s, speed after %.1f", describe(v), v.speedAfter))
		local w = sprintAt(Vector3.new(0, 4, 30), Vector3.zAxis, 1.5, false)
		result("Walking into VaultBox does NOT vault", total(w) == 0 and w.finalPosition.Z < 39, describe(w))
		local function angled(degrees: number): Vector3
			local r = math.rad(degrees)
			return Vector3.new(math.sin(r), 0, math.cos(r))
		end
		local a50 = sprintAt(Vector3.new(-12, 4, 28), angled(50), 1.4, true)
		result("Sprinting at it 50 degrees off head-on vaults and keeps its line", a50.counts.Vault == 1 and a50.finalPosition.Z > 41 and math.abs(a50.headingAfter - 50) < 12,
			string.format("%s, heading after %.0f deg (came in at 50; straight over would be 0)", describe(a50), a50.headingAfter))
		local a70 = sprintAt(Vector3.new(-12, 4, 35), angled(70), 1.2, true)
		-- Sliding along the short (12-stud) VaultBox and reaching its end after ~3 studs is on the
		-- boundary between brushing and clipping its corner (CORNER_SLIDE_GRACE 3): either outcome is
		-- fine, but it must never do anything else (step-up, climb) or more than one move.
		result("70 degrees along the VaultBox: nothing, or one vault over its far corner", total(a70) == 0 or (a70.counts.Vault == 1 and total(a70) == 1),
			describe(a70) .. " [" .. parkour:GetCornerDebug() .. "]")
		local st = sprintAt(Vector3.new(-30, 4, 14), Vector3.zAxis, 1.6, true)
		result("Sprint into JumpBox steps up onto it", st.counts.StepUp == 1 and st.yAfter > 6.3,
			string.format("%s, height after %.1f (top of box +3 = 7)", describe(st), st.yAfter))
		local c = sprintAt(Vector3.new(-30, 4, 51), Vector3.zAxis, 1.4, true)
		result("Sprint into MantleLedge (9 high, out of reach) does NOT climb", total(c) == 0 and c.finalPosition.Z < 64, describe(c))
		local ac = sprintAt(Vector3.new(-30, 4, 58), Vector3.zAxis, 1.8, false, 0.05)
		result("Jump at MantleLedge (keys on it, walking) grabs and scales it", ac.counts.Climb == 1 and ac.startMode == "Air" and ac.yAfter > 11.3,
			string.format("%s, started in %s, height after %.1f", describe(ac), ac.startMode, ac.yAfter))
		local acs = sprintAt(Vector3.new(-30, 4, 51), Vector3.zAxis, 1.8, true, 0.3)
		result("Sprint + jump at MantleLedge grabs and scales it", acs.counts.Climb == 1 and acs.yAfter > 11.3,
			string.format("%s, height after %.1f", describe(acs), acs.yAfter))
		ensureSweepLedge()
		local c6 = sprintAt(Vector3.new(-80, 4, -80), Vector3.zAxis, 1.6, true)
		result("Sprint into a 6-stud ledge (in reach) climbs it and comes out running", c6.counts.Climb == 1 and c6.yAfter > 8.3 and c6.speedAfter > run - 4,
			string.format("%s, height after %.1f (ledge +3 = 9), speed after %.1f (run %d)", describe(c6), c6.yAfter, c6.speedAfter, run))
		local c45 = sprintAt(Vector3.new(-87, 4, -78), angled(40), 1.6, true)
		result("Sprinting at the 6-stud ledge 40 degrees off climbs, turning smoothly", c45.counts.Climb == 1 and c45.yAfter > 8.3 and c45.maxTurn < 25,
			string.format("%s, height after %.1f, biggest turn in one frame %.0f deg (a snap would be ~40)", describe(c45), c45.yAfter, c45.maxTurn))
		local against = sprintAt(Vector3.new(-80, 4, -66.8), Vector3.zAxis, 1.2, true)
		result("Pressed against the 6-stud ledge from a standstill climbs", against.counts.Climb == 1 and against.yAfter > 8.3,
			string.format("%s, height after %.1f", describe(against), against.yAfter))
		-- Corners: aim straight at an obstacle's corner point (45 degrees) and still get the move.
		local function atCorner(cornerX: number, faceZ: number, back: number): Vector3
			return Vector3.new(cornerX - back, 4, faceZ - back)
		end
		local vc = sprintAt(atCorner(6, 39, 7), angled(45), 1.4, true)
		result("Sprinting at the VaultBox's corner vaults it", vc.counts.Vault == 1, describe(vc))
		local sc = sprintAt(atCorner(-22, 32, 7), angled(45), 1.4, true)
		-- Diagonally at the corner the line through the box is short: vaulting over the corner or
		-- stepping up onto it are both right.
		result("Sprinting at the JumpBox's corner steps up onto it or vaults its corner", (sc.counts.StepUp == 1 and sc.yAfter > 6.3) or sc.counts.Vault == 1,
			string.format("%s, height after %.1f", describe(sc), sc.yAfter))
		local cc = sprintAt(atCorner(-74, -66, 7), angled(45), 1.4, true)
		result("Sprinting at the 6-stud ledge's corner climbs it", cc.counts.Climb == 1 and cc.yAfter > 8.3,
			string.format("%s, height after %.1f", describe(cc), cc.yAfter))
		local jc = sprintAt(atCorner(-22, 64, 4), angled(45), 1.6, false, 0.05)
		result("Jumping at the 9-stud ledge's corner grabs and scales it", jc.counts.Climb == 1 and jc.yAfter > 11.3,
			string.format("%s, height after %.1f", describe(jc), jc.yAfter))
		-- Clipping a corner at a steep angle (past ParkourMaxAngle): go over the corner the way the
		-- keys point instead of sliding off it. Middle of the body aimed 0.6 in from the end.
		local function clipStart(hitX: number, faceZ: number, back: number, degrees: number): Vector3
			return Vector3.new(hitX - back * math.tan(math.rad(degrees)), 4, faceZ - back)
		end
		local function cornerDescribe(r: Run): string
			return describe(r) .. " [" .. parkour:GetCornerDebug() .. "]"
		end
		local v70 = sprintAt(clipStart(5.4, 39, 6, 70), angled(70), 1.6, true)
		result("Clipping the VaultBox's end at 70 degrees vaults over the corner", v70.counts.Vault == 1, cornerDescribe(v70))
		local v78 = sprintAt(clipStart(5.6, 39, 5, 78), angled(78), 1.6, true)
		result("Clipping the VaultBox's end at 78 degrees vaults over the corner", v78.counts.Vault == 1, cornerDescribe(v78))
		local b70 = sprintAt(clipStart(-34, 32, 6, 70), angled(70), 1.6, true)
		result("Brushing along the JumpBox at 70 degrees does NOT step up at its end", total(b70) == 0, cornerDescribe(b70))
		local c70 = sprintAt(clipStart(-74.6, -66, 6, 70), angled(70), 1.6, true)
		result("Clipping the 6-stud ledge's end at 70 degrees climbs it", c70.counts.Climb == 1 and c70.maxY > 8.5,
			string.format("%s, highest %.1f (on top = 9)", cornerDescribe(c70), c70.maxY))
		local j65 = sprintAt(clipStart(-22.6, 64, 2.6, 65), angled(65), 1.8, false, 0.05)
		result("Jumping at the 9-stud ledge's end at 65 degrees grabs and scales it", j65.counts.Climb == 1 and j65.yAfter > 11.3,
			string.format("%s, height after %.1f", cornerDescribe(j65), j65.yAfter))
		-- Wall hop into a ledge grab: a 15-high wall (x -131 face) is too tall to grab from a jump
		-- (7.2 + reach 6.5 = 13.7), but the wall run carries you within reach of its top.
		do
			local hop = if player.Character then WallHop.Get(player.Character) else nil
			local wall = Instance.new("Part")
			wall.Name = "FlowTestWall"
			wall.Anchored = true
			wall.Size = Vector3.new(8, 15, 30)
			wall.CFrame = CFrame.new(-127, 7.5, -105)
			wall.Parent = Workspace
			local camera = Workspace.CurrentCamera
			local oldType = camera.CameraType
			teleport(rig, Vector3.new(-134, 4, -118), Vector3.zAxis)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(rig.root.Position - Vector3.zAxis * 12 + Vector3.new(0, 5, 0), rig.root.Position)
			task.wait(0.15)
			local climbsBefore = parkour:GetCount("Climb")
			local hopsBefore = if hop then hop:GetTotalHops() else 0
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			if hop then
				hop:OnJumpPressed(rig.motor:RequestJump())
			end
			local into = Vector3.new(1, 0, 1).Unit
			local maxY = rig.root.Position.Y
			local t0 = os.clock()
			while os.clock() - t0 < 2.2 do
				rig.humanoid:Move(into, false)
				maxY = math.max(maxY, rig.root.Position.Y)
				task.wait()
			end
			rig.motor:SetJumpHeld(false)
			rig.humanoid.Jump = false
			stop(rig)
			camera.CameraType = oldType
			local grabbed = parkour:GetCount("Climb") - climbsBefore
			local hops = if hop then hop:GetTotalHops() - hopsBefore else 0
			result("Wall hop up a too-tall-to-jump wall grabs its top and climbs on", grabbed == 1 and parkour:GetLastStartMode() == "WallRun" and maxY > 17.5,
				string.format("%d hop(s), %d climb(s) started from %s, highest %.1f (on top = 18), %s", hops, grabbed, parkour:GetLastStartMode(), maxY, parkour:GetLastInfo()))
			wall:Destroy()
			waitFor(function()
				return rig.motor:GetMode() == "Ground" and not parkour:IsBusy()
			end, 4)
		end
		local tall = sprintAt(Vector3.new(20, 4, 56), Vector3.xAxis, 1.4, true)
		result("Sprint into TallWall (24 high) does nothing", total(tall) == 0 and tall.finalPosition.X < 33, describe(tall))
		local sl = sprintAt(Vector3.new(0, 4, 58), Vector3.zAxis, 2.0, true)
		result("Sprint into SlideGap slides under and stands up, no fling", sl.counts.Slide == 1 and sl.finalPosition.Z > 86 and sl.standingAfter and sl.maxY < 3.6 and sl.finalPosition.Y > 2.6,
			string.format("%s, highest root %.1f (standing 3.0)", describe(sl), sl.maxY))
		result("No dash during a slide", sl.counts.Slide == 1 and not sl.dashDuring, string.format("dash started %s", tostring(sl.dashDuring)))
		task.wait(Config.DashCooldown)
		local still = sprintAt(Vector3.new(0, 4, 74.5), Vector3.zAxis, 1.5, true)
		result("Slide from a standstill at the gap's edge", still.counts.Slide == 1 and still.finalPosition.Z > 86 and still.maxY < 3.6,
			string.format("%s, highest root %.1f", describe(still), still.maxY))
		local slant = sprintAt(Vector3.new(-3, 4, 62), angled(20), 2.0, true)
		result("Slide at an angle (into the side wall) never flings", slant.counts.Slide == 1 and slant.maxY < 3.6 and slant.standingAfter,
			string.format("%s, highest root %.1f", describe(slant), slant.maxY))
		local ws = sprintAt(Vector3.new(0, 4, 66), Vector3.zAxis, 1.5, false)
		result("Walking into SlideGap does NOT slide", total(ws) == 0 and ws.finalPosition.Z < 76, describe(ws))
		rig.humanoid.Health = maxHealth * 0.2
		local low = sprintAt(Vector3.new(0, 4, 18), Vector3.zAxis, 1.8, true)
		rig.humanoid.Health = maxHealth
		result("Vault still works at 20% HP", low.counts.Vault == 1 and low.finalPosition.Z > 45, describe(low))
	end)
	rig.humanoid.Health = savedHealth
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunParkourTest again to hide this report.")
	running = false
end

-- One sprint at a course obstacle, for watching it (command bar):
-- PlayerGui.MovementSelfTest.ParkourDemo:Fire("Slide")  -- or "Vault", "StepUp", "Climb"
local DEMOS: { [string]: { Vector3 } } = {
	Vault = { Vector3.new(0, 4, 24), Vector3.zAxis },
	StepUp = { Vector3.new(-30, 4, 20), Vector3.zAxis },
	Climb = { Vector3.new(-30, 4, 55), Vector3.zAxis },
	Slide = { Vector3.new(0, 4, 64), Vector3.zAxis },
}
local demoEvent = Instance.new("BindableEvent")
demoEvent.Name = "ParkourDemo"
demoEvent.Event:Connect(function(name: string)
	local demo = DEMOS[name]
	local rig = getRig()
	if running or not demo or not rig then
		return
	end
	running = true
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	teleport(rig, demo[1], demo[2])
	local t0 = os.clock()
	while os.clock() - t0 < 1.4 do
		setMove(rig, demo[2], true)
		task.wait()
	end
	stop(rig)
	if controls then
		controls:Enable()
	end
	running = false
end)
demoEvent.Parent = gui


-- Jump buffer test (command bar: PlayerGui.MovementSelfTest.RunBufferTest:Fire()) ------------
-- Space pressed near the end of a vault / climb / slide / dash must jump as soon as it ends;
-- pressed early in the move it must not.

local function runBufferTest()
	local rig = getRig()
	local character = player.Character
	local parkour = if character then AutoParkour.Get(character) else nil
	local dash = if character then Dash.Get(character) else nil
	local hop = if character then WallHop.Get(character) else nil
	local roll = if character then LandingRoll.Get(character) else nil
	if not rig or not parkour or not dash or not hop or not roll then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Jump buffer test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		ensureSweepLedge()
		local function pressSpace()
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			local made = rig.motor:RequestJump()
			hop:OnJumpPressed(made)
			roll:OnJumpPressed(made)
			dash:OnJumpPressed()
			parkour:OnJumpPressed()
			task.delay(0.08, function()
				rig.motor:SetJumpHeld(false)
				rig.humanoid.Jump = false
			end)
		end

		-- Runs toward `direction` from `start`. `busy` says whether the move is running; Space is
		-- pressed `pressAt` seconds after it starts (nil = never). Returns whether a jump came out
		-- within 0.7 s after the move ended, and how long the move lasted.
		local function attempt(start: Vector3, direction: Vector3, busy: () -> boolean, pressAt: number?, dashIt: boolean?): (boolean, number, boolean)
			teleport(rig, start, direction)
			rig.motor:SetSprinting(not dashIt)
			local t0 = os.clock()
			local startedAt: number? = nil
			local endedAt: number? = nil
			local pressed = false
			local jumped = false
			if dashIt then
				rig.humanoid:Move(direction, false)
				task.wait()
				dash:Request(direction, direction)
			end
			while os.clock() - t0 < 3 do
				rig.humanoid:Move(direction, false)
				local now = os.clock()
				local isBusy = busy()
				if isBusy and not startedAt then
					startedAt = now
				end
				if startedAt and not endedAt and not isBusy then
					endedAt = now
				end
				if startedAt and pressAt and not pressed and now - startedAt >= pressAt and isBusy then
					pressSpace()
					pressed = true
				end
				if endedAt then
					if rig.root.AssemblyLinearVelocity.Y > 30 then
						jumped = true
					end
					if now - endedAt > 0.7 then
						break
					end
				end
				task.wait()
			end
			stop(rig)
			waitFor(function()
				return rig.motor:GetMode() == "Ground"
			end, 3)
			task.wait(0.2)
			local lasted = if startedAt and endedAt then endedAt - startedAt else -1
			return jumped, lasted, pressed
		end
		local function parkourBusy(): boolean
			return parkour:IsBusy()
		end
		local function dashBusy(): boolean
			return dash:IsBusy()
		end

		local v, vt = attempt(Vector3.new(0, 4, 18), Vector3.zAxis, parkourBusy, 0.08)
		result("Space near the end of a vault jumps on landing", v, string.format("jumped %s (vault lasted %.2fs, pressed at 0.08s)", tostring(v), vt))
		local vn = attempt(Vector3.new(0, 4, 18), Vector3.zAxis, parkourBusy, nil)
		result("A vault with no press doesn't jump", not vn, string.format("jumped %s", tostring(vn)))
		local c, ct = attempt(Vector3.new(-80, 4, -80), Vector3.zAxis, parkourBusy, 0.3)
		result("Space near the end of a climb jumps on top", c, string.format("jumped %s (climb lasted %.2fs)", tostring(c), ct))
		local sl, st = attempt(Vector3.new(0, 4, 58), Vector3.zAxis, parkourBusy, 0.35)
		result("Space near the end of a slide jumps as you stand up", sl, string.format("jumped %s (slide lasted %.2fs, pressed at 0.35s)", tostring(sl), st))
		local se, set = attempt(Vector3.new(0, 4, 58), Vector3.zAxis, parkourBusy, 0.03)
		-- Momentum: Space any time in a slide queues a slide-jump out of it.
		result("Space early in a slide queues a slide-jump", se, string.format("jumped %s (slide lasted %.2fs, pressed at 0.03s)", tostring(se), set))
		task.wait(Config.DashCooldown)
		local d, dt = attempt(Vector3.new(0, 4, -60), -Vector3.zAxis, dashBusy, Config.FrontDashTime - 0.15, true)
		result("Space near the end of a dash jumps right after", d, string.format("jumped %s (dash lasted %.2fs)", tostring(d), dt))
		task.wait(Config.DashCooldown)
		local de, det = attempt(Vector3.new(0, 4, -60), -Vector3.zAxis, dashBusy, 0.03, true)
		-- Momentum: Space early in a dash is a dash-jump (ends the dash in a jump that keeps its speed).
		result("Space early in a dash dash-jumps", de and det < Config.FrontDashTime - 0.2, string.format("jumped %s (dash lasted %.2fs)", tostring(de), det))
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunBufferTest again to hide this report.")
	running = false
end

local bufferEvent = Instance.new("BindableEvent")
bufferEvent.Name = "RunBufferTest"
bufferEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runBufferTest)
	end
end)
bufferEvent.Parent = gui


-- Truss test (command bar: PlayerGui.MovementSelfTest.RunTrussTest:Fire()) --------------------
-- The course's FallTowerTruss (x -61..-59, z -1..1, 80 tall): climbing speed must be the same
-- walking in, sprinting in, grabbing it mid-jump, and after jumping off and grabbing it again.

local function runTrussTest()
	local rig = getRig()
	if not rig then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Truss test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		local want = Config.TrussClimbSpeed * rig.motor:GetHealthSpeedScale()
		local climbing = Enum.HumanoidStateType.Climbing
		-- Average upward speed over `measure` seconds of climbing (after `settle` on the truss).
		local function climbSpeed(settle: number, measure: number, timeout: number): number
			local t0 = os.clock()
			local sum, count = 0, 0
			local onSince: number? = nil
			while os.clock() - t0 < timeout do
				rig.humanoid:Move(Vector3.zAxis, false)
				if rig.humanoid:GetState() == climbing then
					onSince = onSince or os.clock()
					local on = os.clock() - (onSince :: number)
					if on >= settle then
						sum += rig.root.AssemblyLinearVelocity.Y
						count += 1
						if on >= settle + measure then
							break
						end
					end
				end
				task.wait()
			end
			return if count > 0 then sum / count else 0
		end
		local function press()
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			rig.motor:RequestJump()
			task.delay(0.1, function()
				rig.motor:SetJumpHeld(false)
				rig.humanoid.Jump = false
			end)
		end
		local function near(value: number): boolean
			return math.abs(value - want) <= want * 0.2
		end

		teleport(rig, Vector3.new(-60, 4, -4), Vector3.zAxis)
		rig.motor:SetSprinting(false)
		local walked = climbSpeed(0.3, 0.5, 3)
		result("Walking into the truss climbs at the climb speed", near(walked), string.format("%.1f studs/s (want %.1f)", walked, want))
		stop(rig)

		teleport(rig, Vector3.new(-60, 4, -16), Vector3.zAxis)
		rig.motor:SetSprinting(true)
		local sprinted = climbSpeed(0.3, 0.5, 3)
		rig.motor:SetSprinting(false)
		result("Sprinting into the truss climbs at the SAME speed", near(sprinted), string.format("%.1f studs/s (want %.1f)", sprinted, want))
		stop(rig)

		teleport(rig, Vector3.new(-60, 4, -5), Vector3.zAxis)
		rig.humanoid:Move(Vector3.zAxis, false)
		press()
		local grabbed = climbSpeed(0.3, 0.5, 3)
		result("Jumping into the truss and grabbing it mid-air climbs at the same speed", near(grabbed), string.format("%.1f studs/s (want %.1f)", grabbed, want))

		-- Now on the truss: climb a bit, jump off, and steer back onto it.
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			rig.humanoid:Move(Vector3.zAxis, false)
			task.wait()
		end
		local beforeJump = rig.root.Position.Y
		stop(rig)
		press()
		local rose = 0
		local t1 = os.clock()
		while os.clock() - t1 < 0.35 do
			rose = math.max(rose, rig.root.Position.Y - beforeJump)
			task.wait()
		end
		result("Jumping off the truss high up is a real jump", rose > 2, string.format("rose %.1f studs after jumping off", rose))
		local regrabbed = climbSpeed(0.3, 0.5, 3)
		result("Getting back on after jumping off still climbs (not stuck)", near(regrabbed), string.format("%.1f studs/s (want %.1f)", regrabbed, want))

		-- No snapping straight back on after jumping off.
		t0 = os.clock()
		while os.clock() - t0 < 0.3 do
			rig.humanoid:Move(Vector3.zAxis, false)
			task.wait()
		end
		press()
		local snappedAt: number? = nil
		local jumpedAt = os.clock()
		while os.clock() - jumpedAt < 1.2 do
			rig.humanoid:Move(Vector3.zAxis, false)
			if rig.humanoid:GetState() == climbing and os.clock() - jumpedAt > 0.05 then
				snappedAt = os.clock() - jumpedAt
				break
			end
			task.wait()
		end
		result("After jumping off you can't snap straight back on", snappedAt == nil or snappedAt >= Config.TrussRegrabDelay - 0.05,
			if snappedAt then string.format("grabbed again after %.2fs (min %.2f)", snappedAt, Config.TrussRegrabDelay) else "not grabbed again within 1.2 s")
		stop(rig)

		-- Grabbing is deliberate (FallTowerTruss: x -61..-59, z -1..1). Watch for the Climbing
		-- state while doing things next to it without steering into it.
		local function grabsDuring(duration: number, each: () -> ()): boolean
			local t = os.clock()
			while os.clock() - t < duration do
				each()
				if rig.humanoid:GetState() == climbing then
					return true
				end
				task.wait()
			end
			return false
		end
		-- Falling right past its face with no keys.
		teleport(rig, Vector3.new(-60, 4, -2.3), Vector3.xAxis)
		rig.root.CFrame = rig.root.CFrame + Vector3.new(0, 30, 0)
		local fellGrab = grabsDuring(1.2, function()
			rig.humanoid:Move(Vector3.zero, false)
		end)
		result("Falling past a truss (no keys) doesn't grab it", not fellGrab, if fellGrab then "grabbed it" else "fell past")
		waitFor(function()
			return rig.motor:GetMode() == "Ground"
		end, 3)
		-- Running along it, brushing its face.
		teleport(rig, Vector3.new(-68, 4, -2.2), Vector3.xAxis)
		rig.motor:SetSprinting(true)
		local brushGrab = grabsDuring(1.0, function()
			rig.humanoid:Move(Vector3.xAxis, false)
		end)
		rig.motor:SetSprinting(false)
		stop(rig)
		result("Running along a truss (brushing past) doesn't grab it", not brushGrab, if brushGrab then "grabbed it" else "ran past")
		-- Dashing past it.
		local character = player.Character
		local dash = if character then Dash.Get(character) else nil
		if dash then
			task.wait(dash:GetCooldownRemaining() + 0.05)
			teleport(rig, Vector3.new(-72, 4, -2.2), Vector3.xAxis)
			task.wait(0.2)
			dash:Request(Vector3.xAxis, Vector3.xAxis)
			local dashGrab = grabsDuring(0.7, function() end)
			stop(rig)
			result("Dashing past a truss doesn't grab it", not dashGrab, if dashGrab then "grabbed it mid-dash" else "dashed past")
		end
		-- Climb up, jump off, then steer AWAY: never back on.
		teleport(rig, Vector3.new(-60, 4, -4), Vector3.zAxis)
		climbSpeed(0.6, 0.1, 3)
		press()
		-- Wait until the jump has actually taken you off the truss.
		waitFor(function()
			return rig.humanoid:GetState() ~= climbing
		end, 0.5)
		local awayGrab = grabsDuring(1.5, function()
			rig.humanoid:Move(-Vector3.zAxis, false)
		end)
		result("Jumping off and steering away never re-grabs", not awayGrab, if awayGrab then "grabbed it again" else "stayed off")
		waitFor(function()
			return rig.motor:GetMode() == "Ground"
		end, 4)

		-- Jump spam vs plain climbing, 2.5 s each, from the same height.
		teleport(rig, Vector3.new(-60, 4, -4), Vector3.zAxis)
		climbSpeed(0.5, 0.1, 3)
		local startY = rig.root.Position.Y
		t0 = os.clock()
		local lastPress = 0
		while os.clock() - t0 < 2.5 do
			rig.humanoid:Move(Vector3.zAxis, false)
			if os.clock() - lastPress > 0.15 then
				press()
				lastPress = os.clock()
			end
			task.wait()
		end
		local spamGain = rig.root.Position.Y - startY
		stop(rig)
		result("Spamming jump on a truss climbs no faster than climbing", spamGain < want * 2.5 * 0.5,
			string.format("gained %.1f studs in 2.5 s (climbing gains %.1f)", spamGain, want * 2.5))
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunTrussTest again to hide this report.")
	running = false
end

local trussEvent = Instance.new("BindableEvent")
trussEvent.Name = "RunTrussTest"
trussEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runTrussTest)
	end
end)
trussEvent.Parent = gui


-- Momentum test (command bar: PlayerGui.MovementSelfTest.RunMomentumTest:Fire()) ---------------
-- Dash-jump keeps the dash's speed; a front dash hands its speed to a vault; a slide-jump keeps
-- the slide's speed; extra speed bleeds off in the air and on the ground.

local function runMomentumTest()
	local rig = getRig()
	local character = player.Character
	local dash = if character then Dash.Get(character) else nil
	local parkour = if character then AutoParkour.Get(character) else nil
	local hop = if character then WallHop.Get(character) else nil
	local roll = if character then LandingRoll.Get(character) else nil
	if not rig or not dash or not parkour or not hop or not roll then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Momentum test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		local function flatSpeed(): number
			local v = rig.root.AssemblyLinearVelocity
			return Vector3.new(v.X, 0, v.Z).Magnitude
		end
		local function pressSpace()
			rig.motor:SetJumpHeld(true)
			rig.humanoid.Jump = true
			local made = rig.motor:RequestJump()
			hop:OnJumpPressed(made)
			roll:OnJumpPressed(made)
			dash:OnJumpPressed()
			parkour:OnJumpPressed()
			task.delay(0.08, function()
				rig.motor:SetJumpHeld(false)
				rig.humanoid.Jump = false
			end)
		end
		local lane = Vector3.new(0, 4, -40)
		local dir = -Vector3.zAxis
		local run = Config.RunSpeed

		-- Plain running jump, for comparison: distance covered in the air.
		local function airDistance(): (number, number, number)
			local startPos = rig.root.Position
			local takeoffSpeed = 0
			local landingSpeed = 0
			waitFor(function()
				return rig.motor:GetMode() == "Air"
			end, 0.6)
			local t0 = os.clock()
			local sampled = false
			while rig.motor:GetMode() ~= "Ground" and os.clock() - t0 < 3 do
				rig.humanoid:Move(dir, false)
				if not sampled and os.clock() - t0 > 0.05 then
					takeoffSpeed = flatSpeed()
					sampled = true
				end
				landingSpeed = flatSpeed()
				task.wait()
			end
			local flat = rig.root.Position - startPos
			return Vector3.new(flat.X, 0, flat.Z).Magnitude, takeoffSpeed, landingSpeed
		end

		teleport(rig, lane, dir)
		local t0 = os.clock()
		while os.clock() - t0 < 1 do
			setMove(rig, dir, true)
			task.wait()
		end
		pressSpace()
		local runJump, runTakeoff = airDistance()
		stop(rig)

		-- Dash-jump: Space 0.15 s into a front dash.
		task.wait(dash:GetCooldownRemaining() + 0.05)
		teleport(rig, lane, dir)
		setMove(rig, dir, true)
		dash:Request(dir, dir)
		task.wait(0.15)
		pressSpace()
		local dashJump, dashTakeoff, dashLanding = airDistance()
		local reason = dash:GetLastEndReason()
		result("Dash-jump keeps the dash's speed", reason == "jump" and dashTakeoff > run + 10 and dashTakeoff <= Config.MomentumMaxSpeed + 3,
			string.format("dash ended by %s, takeoff speed %.1f (running jump %.1f)", reason, dashTakeoff, runTakeoff))
		result("Dash-jump carries farther than a running jump", dashJump > runJump + 5,
			string.format("%.1f studs in the air (running jump %.1f)", dashJump, runJump))
		result("Extra speed bleeds off slowly in the air", dashLanding < dashTakeoff and dashLanding > run,
			string.format("takeoff %.1f -> landing %.1f (run %d)", dashTakeoff, dashLanding, run))
		-- Then on the ground it settles back to run speed.
		local t1 = os.clock()
		local settled = 0
		while os.clock() - t1 < 1.5 do
			setMove(rig, dir, true)
			settled = flatSpeed()
			task.wait()
		end
		result("On the ground it settles back to run speed", math.abs(settled - run) < 1.5, string.format("%.1f after 1.5 s (run %d)", settled, run))
		stop(rig)

		-- Space the very frame the dash starts: dash-jumps right away.
		task.wait(dash:GetCooldownRemaining() + 0.05)
		teleport(rig, lane, dir)
		setMove(rig, dir, true)
		dash:Request(dir, dir)
		pressSpace()
		local _, instantTakeoff = airDistance()
		result("Space the instant a dash starts dash-jumps", dash:GetLastEndReason() == "jump" and instantTakeoff > run + 10,
			string.format("dash ended by %s, takeoff %.1f", dash:GetLastEndReason(), instantTakeoff))
		stop(rig)

		-- Side dash: dash-jumps too.
		task.wait(dash:GetCooldownRemaining() + 0.05)
		teleport(rig, lane, dir)
		local sideways = Vector3.new(-dir.Z, 0, dir.X)
		setMove(rig, sideways, false)
		dash:Request(sideways, dir)
		task.wait(0.1)
		pressSpace()
		local _, sideTakeoff = airDistance()
		result("Side dash dash-jumps", dash:GetLastEndReason() == "jump" and sideTakeoff > run,
			string.format("dash ended by %s, takeoff %.1f", dash:GetLastEndReason(), sideTakeoff))
		stop(rig)

		-- Dash off a ledge (the JumpBox top, y 4, ends at z 48), Space just after leaving it.
		task.wait(dash:GetCooldownRemaining() + 0.05)
		teleport(rig, Vector3.new(-30, 8, 42), Vector3.zAxis)
		task.wait(0.2)
		setMove(rig, Vector3.zAxis, true)
		dash:Request(Vector3.zAxis, Vector3.zAxis)
		local tl = os.clock()
		while rig.humanoid.FloorMaterial ~= Enum.Material.Air and os.clock() - tl < 0.5 do
			task.wait()
		end
		task.wait(0.05)
		local offAt = rig.root.Position.Y
		pressSpace()
		local rose = 0
		local tr = os.clock()
		while os.clock() - tr < 0.4 do
			rose = math.max(rose, rig.root.Position.Y - offAt)
			task.wait()
		end
		result("Dashing off a ledge, Space just after still dash-jumps", dash:GetLastEndReason() == "jump" and rose > 3,
			string.format("dash ended by %s, rose %.1f after leaving the edge", dash:GetLastEndReason(), rose))
		stop(rig)
		waitFor(function()
			return rig.motor:GetMode() == "Ground"
		end, 3)

		-- Front dash into the VaultBox: parkour takes over with dash speed.
		task.wait(dash:GetCooldownRemaining() + 0.05)
		teleport(rig, Vector3.new(0, 4, 26), Vector3.zAxis)
		local vaultsBefore = parkour:GetCount("Vault")
		setMove(rig, Vector3.zAxis, true)
		dash:Request(Vector3.zAxis, Vector3.zAxis)
		local afterVault = 0
		local t2 = os.clock()
		local sawVault = false
		while os.clock() - t2 < 1.5 do
			setMove(rig, Vector3.zAxis, true)
			if parkour:IsBusy() then
				sawVault = true
			elseif sawVault and afterVault == 0 then
				task.wait(0.05)
				afterVault = flatSpeed()
			end
			task.wait()
		end
		stop(rig)
		result("Front dash into a box vaults it at dash speed (capped)", parkour:GetCount("Vault") > vaultsBefore and dash:GetLastEndReason() == "move" and afterVault > run + 5 and afterVault <= Config.MomentumMaxSpeed + 3,
			string.format("dash ended by %s, speed after the vault %.1f (run %d)", dash:GetLastEndReason(), afterVault, run))

		-- Slide-jump: Space while under the roof jumps as soon as you clear it, with slide speed.
		teleport(rig, Vector3.new(0, 4, 60), Vector3.zAxis)
		local t3 = os.clock()
		local pressed = false
		local jumpedSpeed = -1
		local slideSeen = false
		local airSince: number? = nil
		local endAt: number? = nil
		local trace: { string } = {}
		while os.clock() - t3 < 2.5 do
			setMove(rig, Vector3.zAxis, true)
			if parkour:IsBusy() and parkour:GetAction() == "Slide" then
				slideSeen = true
				if not pressed then
					pressSpace()
					pressed = true
				end
			end
			if slideSeen and not parkour:IsBusy() and #trace < 12 then
				endAt = endAt or os.clock()
				table.insert(trace, string.format("%.2f %s/%s v%.0f w%.0f", os.clock() - (endAt :: number), rig.motor:GetMode(), rig.humanoid:GetState().Name, flatSpeed(), rig.humanoid.WalkSpeed))
			end
			-- Sample like the dash-jump: a moment after the motor goes airborne.
			if slideSeen and not parkour:IsBusy() and rig.motor:GetMode() == "Air" and jumpedSpeed < 0 then
				airSince = airSince or os.clock()
				if os.clock() - (airSince :: number) > 0.05 then
					jumpedSpeed = if rig.root.AssemblyLinearVelocity.Y > 5 then flatSpeed() else 0
				end
			end
			task.wait()
		end
		stop(rig)
		local slideEnd = parkour:GetLastEndSpeed()
		result("Slide-jump jumps out as soon as you clear the roof, keeping slide speed", jumpedSpeed > 0 and jumpedSpeed >= slideEnd - 2,
			string.format("slide ended at %.1f, jumped at %.1f studs/s\n  %s", slideEnd, jumpedSpeed, table.concat(trace, " | ")))
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunMomentumTest again to hide this report.")
	running = false
end

local momentumEvent = Instance.new("BindableEvent")
momentumEvent.Name = "RunMomentumTest"
momentumEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runMomentumTest)
	end
end)
momentumEvent.Parent = gui

-- Performance test (command bar: PlayerGui.MovementSelfTest.RunPerfTest:Fire()) -------------
-- Frame times and each movement system's cost per frame: standing still, sprinting in the
-- open, sprinting along a wall, and pressed against a too-tall ledge (parkour keeps checking).
local function runPerfTest()
	local rig = getRig()
	if not rig then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Performance test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local ok, err = pcall(function()
		local camera = workspace.CurrentCamera
		local UserGameSettings = UserSettings():GetService("UserGameSettings")
		-- Camera flicks: every 0.25 s snap the view 120 degrees, alternating direction, turning
		-- 180 deg/s in between (like whipping the mouse around). `lockState` also puts the game
		-- in shift-lock state (what Roblox's shift lock sets: mouse locked to the centre, the
		-- character turned to face the camera).
		local flicking = false
		local lockState = false
		local flickTime = 0
		local lastFlick = 0
		RunService:BindToRenderStep("PerfTestFlick", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
			if lockState then
				UserGameSettings.RotationType = Enum.RotationType.CameraRelative
			end
			if not flicking then
				return
			end
			flickTime += dt
			local turn = math.rad(180) * dt
			if flickTime - lastFlick >= 0.25 then
				lastFlick = flickTime
				turn += math.rad(120)
			end
			local sign = if math.floor(flickTime / 0.5) % 2 == 0 then 1 else -1
			local c = camera.CFrame
			camera.CFrame = CFrame.new(c.Position) * CFrame.Angles(0, turn * sign, 0) * c.Rotation
		end)
		local function scenario(name: string, duration: number, start: Vector3?, facing: Vector3?, keys: Vector3?, sprint: boolean)
			if start and facing then
				teleport(rig, start, facing)
				task.wait(0.3)
			end
			local frames: { number } = {}
			local connection = RunService.RenderStepped:Connect(function(dt: number)
				table.insert(frames, dt)
			end)
			Perf.reset()
			Perf.enabled = true
			local t0 = os.clock()
			while os.clock() - t0 < duration do
				if keys then
					setMove(rig, keys, sprint)
				end
				task.wait()
			end
			Perf.enabled = false
			connection:Disconnect()
			stop(rig)
			local totals, counts = Perf.snapshot()
			local n = math.max(#frames, 1)
			table.sort(frames)
			local sum = 0
			for _, dt in frames do
				sum += dt
			end
			local avg = sum / n
			local p95 = frames[math.max(1, math.floor(n * 0.95))] or 0
			local worst = frames[n] or 0
			local parts = {}
			local scriptTotal = 0
			for system, seconds in totals do
				scriptTotal += seconds
				table.insert(parts, string.format("%s %.3f", system, seconds * 1000 / n))
			end
			table.sort(parts)
			log(string.format("<b>%s</b>: %.0f fps avg (%.1f ms), 95%% of frames under %.1f ms, worst %.1f ms", name, 1 / avg, avg * 1000, p95 * 1000, worst * 1000))
			log(string.format("  movement scripts %.3f ms/frame: %s", scriptTotal * 1000 / n, table.concat(parts, ", ")))
			local rays = counts["AutoParkour rays"] or 0
			log(string.format("  parkour raycasts %.0f per frame", rays / n))
		end
		scenario("Standing still", 3, Vector3.new(0, 4, -40), -Vector3.zAxis, nil, false)
		scenario("Sprinting in the open", 3, Vector3.new(0, 4, -20), -Vector3.zAxis, -Vector3.zAxis, true)
		-- TallWall: x 33..35, z 32..80. Keys 20 degrees into it, so you slide along it.
		local along = Vector3.new(math.sin(math.rad(20)), 0, math.cos(math.rad(20)))
		scenario("Sprinting along a wall", 1.6, Vector3.new(31.5, 4, 34), Vector3.zAxis, along, true)
		-- MantleLedge (9 high) face at z 64: pressed against it, parkour keeps finding it too tall.
		scenario("Pressed against a too-tall ledge", 2, Vector3.new(-30, 4, 60), Vector3.zAxis, Vector3.zAxis, true)
		teleport(rig, Vector3.new(-100, 4, -100), Vector3.zAxis)
		task.wait(0.3)
		flicking = true
		scenario("Flicking the camera (no shift lock)", 3, nil, nil, nil, false)
		lockState = true
		scenario("Flicking the camera in shift lock", 3, nil, nil, nil, false)
		scenario("Flicking in shift lock while running", 3, nil, nil, Vector3.new(0, 0, 1), true)
		-- Same, with HeadLook (turns the head toward the camera) switched off, to see its share.
		local headLook = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("HeadLook")
		if headLook and headLook:IsA("LocalScript") then
			headLook.Disabled = true
			scenario("Flicking in shift lock, HeadLook off", 3, nil, nil, nil, false)
			headLook.Disabled = false
		end
		flicking = false
		lockState = false
		UserGameSettings.RotationType = Enum.RotationType.MovementRelative
	end)
	Perf.enabled = false
	RunService:UnbindFromRenderStep("PerfTestFlick")
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunPerfTest again to hide this report.")
	running = false
end

local perfEvent = Instance.new("BindableEvent")
perfEvent.Name = "RunPerfTest"
perfEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runPerfTest)
	end
end)
perfEvent.Parent = gui

-- Parkour edge-case sweep (command bar: PlayerGui.MovementSelfTest.RunParkourSweep:Fire()) ---
-- Runs many approaches at three obstacles (MantleLedge 9 high, the 6-stud test ledge, JumpBox 4
-- high): straight, angled, pressed against the face strafing toward the corner, strafe-then-turn,
-- jumping at it, walking diagonally; each at the middle, near the corner and past the corner.
-- Reports only runs that end BAD: hanging in the air, inside geometry, flung, or looping.

local function runParkourSweep(only: string?)
	local rig = getRig()
	local character = player.Character
	local parkour = if character then AutoParkour.Get(character) else nil
	if not rig or not parkour or not character then
		warn("[MovementSelfTest] Character or parkour not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Parkour edge-case sweep</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local camera = Workspace.CurrentCamera
	local ok, err = pcall(function()
		ensureSweepLedge()
		type Target = { name: string, faceZ: number, xMin: number, xMax: number, top: number }
		local targets: { Target } = {
			{ name = "9-high", faceZ = 64, xMin = -38, xMax = -22, top = 9 },
			{ name = "6-high", faceZ = -66, xMin = -86, xMax = -74, top = 6 },
			{ name = "4-box", faceZ = 32, xMin = -38, xMax = -22, top = 4 },
			{ name = "vault-box", faceZ = 39, xMin = -6, xMax = 6, top = 3 },
		}
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { character }
		overlapParams.RespectCanCollide = true

		local function dir(degrees: number): Vector3
			local r = math.rad(degrees)
			return Vector3.new(math.sin(r), 0, math.cos(r))
		end
		-- style -> { start distance from face, [time, keys, sprint, jump] segments }
		type Segment = { t: number, keys: Vector3, sprint: boolean, jump: boolean? }
		-- vertex = aim at the obstacle's corner point instead of using the three offsets:
		-- "inside" comes from in front of the face, "outside" from beyond the side.
		type Style = { name: string, back: number, segments: { Segment }, vertex: string? }
		local styles: { Style } = {
			{ name = "sprint straight", back = 12, segments = { { t = 1.6, keys = dir(0), sprint = true } } },
			{ name = "sprint 40deg", back = 12, segments = { { t = 1.6, keys = dir(40), sprint = true } } },
			{ name = "strafe along face (W+D)", back = 1.2, segments = { { t = 1.6, keys = dir(55), sprint = true } } },
			{ name = "strafe then turn in", back = 1.2, segments = { { t = 0.6, keys = dir(88), sprint = true }, { t = 1.0, keys = dir(30), sprint = true } } },
			{ name = "jump at it", back = 6, segments = { { t = 0.12, keys = dir(0), sprint = false }, { t = 1.6, keys = dir(0), sprint = false, jump = true } } },
			{ name = "walk diagonal", back = 3, segments = { { t = 1.6, keys = dir(45), sprint = false } } },
			{ name = "corner point from the front", back = 7, vertex = "inside", segments = { { t = 1.4, keys = dir(45), sprint = true } } },
			{ name = "corner point from the side", back = 7, vertex = "outside", segments = { { t = 1.4, keys = dir(-45), sprint = true } } },
		}
		local bad = 0
		local runs = 0
		local summary: { [string]: number } = {}
		for _, target in targets do
			if only and target.name ~= only then
				continue
			end
			local offsets = {
				{ label = "middle", x = (target.xMin + target.xMax) / 2 },
				{ label = "near corner", x = target.xMax - 0.6 },
				{ label = "past corner", x = target.xMax + 0.8 },
			}
			for _, style in styles do
				for _, offset in offsets do
					if style.vertex and offset.label ~= "middle" then
						continue
					end
					runs += 1
					local start = Vector3.new(offset.x, 4, target.faceZ - style.back)
					if style.vertex == "inside" then
						start = Vector3.new(target.xMax - style.back, 4, target.faceZ - style.back)
					elseif style.vertex == "outside" then
						start = Vector3.new(target.xMax + style.back, 4, target.faceZ - style.back)
					end
					teleport(rig, start, Vector3.zAxis)
					if camera then
						camera.CameraType = Enum.CameraType.Scriptable
						camera.CFrame = CFrame.lookAt(start + Vector3.new(0, 6, -14), start + Vector3.new(0, 2, 8))
					end
					local before = 0
					for _, name in { "Vault", "StepUp", "Climb", "Slide" } do
						before += parkour:GetCount(name)
					end
					local maxY = rig.root.Position.Y
					local hangFor = 0
					for _, segment in style.segments do
						rig.motor:SetSprinting(segment.sprint)
						if segment.jump then
							rig.humanoid.Jump = true
						end
						local t0 = os.clock()
						while os.clock() - t0 < segment.t do
							rig.humanoid:Move(segment.keys, false)
							if segment.jump and os.clock() - t0 > 0.05 then
								rig.humanoid.Jump = false
							end
							maxY = math.max(maxY, rig.root.Position.Y)
							local v = rig.root.AssemblyLinearVelocity
							if rig.motor:GetMode() == "Air" and v.Magnitude < 0.8 then
								hangFor += 1 / 60
							end
							task.wait()
						end
					end
					stop(rig)
					task.wait(0.6)
					local after = 0
					for _, name in { "Vault", "StepUp", "Climb", "Slide" } do
						after += parkour:GetCount(name)
					end
					local actions = after - before
					local mode = rig.motor:GetMode()
					local inside = #Workspace:GetPartBoundsInBox(rig.root.CFrame, Vector3.new(1.2, 1.6, 0.6), overlapParams) > 0
					local problems: { string } = {}
					local info = parkour:GetLastInfo()
					if actions > 1 and (string.find(info, "blocked") or string.find(info, "snagged")) then
						table.insert(problems, string.format("%d parkour moves, retrying (%s)", actions, info))
					elseif actions > 0 and (string.find(info, "blocked") or string.find(info, "snagged")) then
						table.insert(problems, "move got " .. info)
					end
					if mode ~= "Ground" then
						table.insert(problems, "not on the ground after (" .. mode .. ", " .. rig.humanoid:GetState().Name .. ")")
					end
					if hangFor > 0.3 then
						table.insert(problems, string.format("hung in the air %.1fs", hangFor))
					end
					if inside then
						table.insert(problems, "root inside geometry")
					end
					if maxY > target.top + 3 + 8 then
						table.insert(problems, string.format("flung to y %.1f", maxY))
					end
					local outcome = if actions == 0 then "none" else string.format("%d move(s), %s [%s]", actions, parkour:GetLastInfo(), parkour:GetLastDetail())
					local key = target.name .. " / " .. style.name .. " / " .. offset.label
					summary[key] = (summary[key] or 0)
					if #problems > 0 then
						bad += 1
						log(string.format('<font color="#FF6060">BAD</font> %s / %s / %s: %s (%s, ended y %.1f)',
							target.name, style.name, offset.label, table.concat(problems, "; "), outcome, rig.root.Position.Y))
					else
						print(string.format("[Sweep] ok %s / %s / %s: %s, ended (%.1f, %.1f, %.1f)", target.name, style.name, offset.label, outcome,
							rig.root.Position.X, rig.root.Position.Y, rig.root.Position.Z))
					end
				end
			end
		end
		result("Parkour sweep: no stuck / hanging / flung / looping runs", bad == 0, string.format("%d bad of %d runs (each run's outcome is in Output)", bad, runs))
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunParkourSweep again to hide this report.")
	running = false
end

local sweepEvent = Instance.new("BindableEvent")
sweepEvent.Name = "RunParkourSweep"
-- Optional argument: only one target ("9-high", "6-high" or "4-box").
sweepEvent.Event:Connect(function(only: string?)
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runParkourSweep, only)
	end
end)
sweepEvent.Parent = gui

local parkourEvent = Instance.new("BindableEvent")
parkourEvent.Name = "RunParkourTest"
parkourEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runParkourTest)
	end
end)
parkourEvent.Parent = gui

local function toggleRollTest()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runRollTest)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.KeyCode == ROLL_TEST_KEY then
		toggleRollTest()
	end
end)

-- Lantern test (command bar: PlayerGui.MovementSelfTest.RunLanternTest:Fire()) ---------------------
-- Moth Left Ctrl: tap = wing flight, hold = charge + throw, press in the air = suspend, hold with the
-- lantern away = fly (inside its light / to a tagged opponent), M1 cancels flights.

local function runLanternTest()
	local rig = getRig()
	local character = player.Character
	local lantern = if character then Lantern.Get(character) else nil
	local stamina = if character then Stamina.Get(character) else nil
	local dash = if character then Dash.Get(character) else nil
	local camera = Workspace.CurrentCamera
	if not rig or not character or not lantern or not stamina or not dash or not camera then
		warn("[MovementSelfTest] Character not ready")
		return
	end
	running = true
	table.clear(lines)
	gui.Enabled = true
	log("<b>Lantern test</b> (don't touch the keyboard)")
	local controls = getControls()
	if controls then
		controls:Disable()
	end
	local originalRace = character:GetAttribute("Race")
	local originalCameraType = camera.CameraType
	local ok, err = pcall(function()
		character:SetAttribute("Race", "Moth")
		lantern:ResetForTest()
		camera.CameraType = Enum.CameraType.Scriptable
		local function aim(dir: Vector3)
			local d = dir.Unit
			camera.CFrame = CFrame.lookAt(rig.root.Position - d * 10, rig.root.Position - d * 10 + d)
		end
		local function tap()
			lantern:Press()
			task.wait(0.03)
			lantern:Release()
		end
		local function hold(extra: number?)
			lantern:Press()
			task.wait(Config.LanternTapTime + (extra or 0.05))
		end
		local function release()
			lantern:Release()
		end
		local function grounded()
			waitFor(function()
				return rig.motor:GetMode() == "Ground"
			end, 8)
		end
		local base = Vector3.new(140, 4, -140)
		local fwd = -Vector3.zAxis
		-- Toward the map's middle from `base`, so flights never leave the baseplate.
		local inward = Vector3.new(-1, 0, 1).Unit

		-- Lantern on the hip.
		teleport(rig, base, inward)
		task.wait(0.3)
		local serverLantern = character:FindFirstChild("Lantern")
		local core = serverLantern and serverLantern:IsA("Model") and serverLantern.PrimaryPart
		local torso = character:FindFirstChild("Torso") :: BasePart
		local hipLocal = if core then torso.CFrame:PointToObjectSpace(core.Position) else Vector3.zero
		result("The lantern sits on the right hip, not glowing", core ~= nil and hipLocal.X > 0.8 and hipLocal.Y < -0.5 and core.Material ~= Enum.Material.Neon,
			string.format("torso-local %.1f, %.1f, %.1f, material %s", hipLocal.X, hipLocal.Y, hipLocal.Z, if core then core.Material.Name else "-"))
		local wings = character:FindFirstChild("MothWings")
		local wingMotor = torso:FindFirstChild("RightForewing")
		result("Moth wings are on the character, on Motor6Ds", wings ~= nil and wingMotor ~= nil and wingMotor:IsA("Motor6D"),
			string.format("wings %s, RightForewing motor %s", tostring(wings ~= nil), tostring(wingMotor ~= nil)))

		-- Not a Moth: nothing.
		character:SetAttribute("Race", "")
		tap()
		result("Not a Moth: tap does nothing", lantern:GetFlight() == nil and lantern:GetState() == "Hip", lantern:GetLastInfo())
		character:SetAttribute("Race", "Moth")

		-- Tap: wing flight ~25 studs where the camera looks, then momentum.
		stamina:Set(100)
		local dir = (inward + Vector3.new(0, 0.3, 0)).Unit
		aim(dir)
		local start = rig.root.Position
		tap()
		local kind = lantern:GetFlight()
		waitFor(function()
			return lantern:GetFlight() == nil
		end, 1)
		local flown = rig.root.Position - start
		local after = rig.root.AssemblyLinearVelocity.Magnitude
		result("Tap: wing flight covers ~WingFlightDistance where the camera looks", kind == "Wings" and math.abs(flown.Magnitude - Config.WingFlightDistance) < 3 and flown.Unit:Dot(dir) > 0.95,
			string.format("flight %s, %.1f studs (want %d), dot %.2f", tostring(kind), flown.Magnitude, Config.WingFlightDistance, if flown.Magnitude > 0 then flown.Unit:Dot(dir) else 0))
		local flightSpeed = Config.WingFlightDistance / Config.WingFlightTime
		result("It costs WingFlightCost stamina and keeps some momentum", math.abs((100 - stamina:GetValue()) - Config.WingFlightCost) < 1 and after > flightSpeed * Config.WingFlightKeep * 0.6,
			string.format("stamina %d, speed after %.1f (flight %.0f)", stamina:GetValue(), after, flightSpeed))
		grounded()

		-- M1 cancels a wing flight early.
		teleport(rig, base, inward)
		stamina:Set(100)
		aim(dir)
		start = rig.root.Position
		tap()
		task.wait(0.1)
		local cancelled = lantern:OnM1()
		local short = (rig.root.Position - start).Magnitude
		result("M1 cancels the flight early", cancelled and lantern:GetLastFlightEnd() == "m1" and short < Config.WingFlightDistance * 0.6,
			string.format("ended by %s after %.1f studs", lantern:GetLastFlightEnd(), short))
		grounded()
		local dashedDuring: boolean? = nil
		teleport(rig, base, inward)
		stamina:Set(100)
		aim(dir)
		task.wait(Config.WingFlightCooldown)
		tap()
		task.wait(0.05)
		dashedDuring = dash:Request(inward, inward)
		result("No dash while flying", dashedDuring == false, "dash request -> " .. tostring(dashedDuring))
		grounded()

		-- Hold: charge in hand; release throws. Longer hold = faster.
		teleport(rig, base, inward)
		aim(Vector3.new(inward.X, 0.1, inward.Z))
		lantern:SetAimForTest(rig.root.Position + inward * 40 + Vector3.new(0, 8, 0))
		hold(0)
		local charging = lantern:GetState() == "Charging"
		task.wait(0.2)
		local mountedHand = core and (core.Position - (character:FindFirstChild("Right Arm") :: BasePart).Position).Magnitude < 2.5
		local previewFolder = camera:FindFirstChild("LanternThrowPreview")
		local shownDots = 0
		if previewFolder then
			for _, d in previewFolder:GetChildren() do
				if d:IsA("BasePart") and d.Name ~= "Target" and d.Transparency < 1 then
					shownDots += 1
				end
			end
		end
		local hud = player.PlayerGui:FindFirstChild("Hud")
		local column = hud and hud:FindFirstChild("Column")
		local chargeArea = column and column:FindFirstChild("Charge")
		local crosshair = hud and hud:FindFirstChild("Crosshair")
		local barShown = chargeArea ~= nil and (chargeArea :: Frame).Visible
		local crossShown = crosshair ~= nil and (crosshair :: Frame).Visible
		local facing = Vector3.new(rig.root.CFrame.LookVector.X, 0, rig.root.CFrame.LookVector.Z).Unit:Dot(Vector3.new(inward.X, 0, inward.Z).Unit)
		result("While charging: throw path, HUD charge bar + crosshair, body faces the aim", shownDots >= 5 and barShown and crossShown and facing > 0.9,
			string.format("%d path dots, charge bar %s, crosshair %s, facing dot %.2f", shownDots, tostring(barShown), tostring(crossShown), facing))
		local beforeThrow = rig.root.Position
		release()
		result("Releasing hides the path", camera:FindFirstChild("LanternThrowPreview") == nil, "")
		local weak = lantern:GetLastThrowSpeed()
		result("Hold takes it in hand and charges; release throws", charging and lantern:GetState() == "Thrown" and mountedHand == true,
			string.format("charging %s, in hand %s, state after release %s", tostring(charging), tostring(mountedHand), lantern:GetState()))
		-- Press while it's in the air: suspended in place.
		task.wait(0.25)
		local moved = (rig.root.Position - beforeThrow).Magnitude
		result("Throwing doesn't move you (no fling)", moved < 0.6, string.format("moved %.2f studs in 0.25 s", moved))
		lantern:Press()
		task.wait(0.03)
		lantern:Release()
		local p0 = lantern:GetPosition()
		task.wait(0.8)
		result("Press while it's in the air suspends it", lantern:GetState() == "Suspended" and (lantern:GetPosition() - p0).Magnitude < 0.05,
			string.format("state %s", lantern:GetState()))
		-- Free flight inside its light; can't leave the light.
		stamina:Set(100)
		local lanternPos = lantern:GetPosition()
		aim((rig.root.Position - lanternPos) * Vector3.new(1, 0, 1) + Vector3.new(0, 2, 0))
		hold()
		local freeKind = lantern:GetFlight()
		local farthest = 0
		local t0 = os.clock()
		while os.clock() - t0 < 1.5 do
			farthest = math.max(farthest, (rig.root.Position - lanternPos).Magnitude)
			task.wait()
		end
		result("Hold inside the light: free flight that can't leave the light", freeKind == "Free" and farthest <= Config.LanternLightRadius + 1.5,
			string.format("flight %s, farthest %.1f from the lantern (radius %d)", tostring(freeKind), farthest, Config.LanternLightRadius))
		-- Fly into the lantern: grab + burst.
		local tg = os.clock()
		local speedBefore = 0
		while lantern:GetState() ~= "Hip" and os.clock() - tg < 3 do
			aim(lantern:GetPosition() - rig.root.Position)
			speedBefore = rig.root.AssemblyLinearVelocity.Magnitude
			task.wait()
		end
		local speedAfter = rig.root.AssemblyLinearVelocity.Magnitude
		release()
		result("Flying into the lantern grabs it with a burst of speed", lantern:GetState() == "Hip" and lantern:GetLastFlightEnd() == "grab" and speedAfter > speedBefore + 10,
			string.format("state %s, ended by %s, speed %.0f -> %.0f", lantern:GetState(), lantern:GetLastFlightEnd(), speedBefore, speedAfter))
		hold()
		local blocked = lantern:GetState() ~= "Charging"
		release()
		result("Just grabbed: can't throw during LanternGrabCooldown", blocked, lantern:GetLastInfo())
		result("Charge makes throws faster", weak < Config.LanternThrowSpeedMin + 25, string.format("quick hold threw at %.0f (min %d, max %d)", weak, Config.LanternThrowSpeedMin, Config.LanternThrowSpeedMax))
		grounded()

		-- Hanging lantern out of reach: no flight. Lying lantern: no flight; walk into it grabs it.
		lantern:ResetForTest()
		teleport(rig, base, inward)
		lantern:PlaceForTest(base + Vector3.new(0, 8, -(Config.LanternLightRadius + 10)), "Suspended")
		hold()
		local outside = lantern:GetFlight()
		release()
		result("Outside its light: no flight", outside == nil, lantern:GetLastInfo())

		-- Leaving the light during flight terminates flight immediately.
		lantern:PlaceForTest(base + Vector3.new(0, 8, -5), "Suspended")
		teleport(rig, base + Vector3.new(0, 8, -5), inward)
		hold()
		local startedFlight = lantern:GetFlight() == "Free"
		teleport(rig, base + Vector3.new(0, 8, -(Config.LanternLightRadius + 5)), inward)
		task.wait(0.05)
		local endedFlight = lantern:GetFlight() == nil and lantern:GetLastFlightEnd() == "left_light"
		release()
		result("Leaving lantern light radius stops flight", startedFlight and endedFlight, lantern:GetLastInfo())

		lantern:PlaceForTest(base + inward * 10 + Vector3.new(0, -3.5, 0), "Dropped")
		hold()
		local lying = lantern:GetFlight()
		release()
		result("Lantern lying somewhere: no flight", lying == nil, lantern:GetLastInfo())
		teleport(rig, base + inward * 9, inward)
		waitFor(function()
			return lantern:GetState() == "Hip"
		end, 1)
		result("Walking into it puts it back on the hip", lantern:GetState() == "Hip", lantern:GetLastInfo())

		-- The preview is the real flight: a throw lands where the ring said.
		lantern:ResetForTest()
		teleport(rig, base, inward)
		task.wait(0.4)
		local floorPoint = rig.root.Position + inward * 30 + Vector3.new(0, -6, 0)
		local floorHit = Workspace:Raycast(floorPoint + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0))
		if floorHit then
			floorPoint = floorHit.Position
		end
		aim(Vector3.new(inward.X, -0.3, inward.Z))
		lantern:SetAimForTest(floorPoint)
		local predicted = lantern:PredictForTest(0.5)
		lantern:ThrowForTest(nil, 0.5)
		waitFor(function()
			return lantern:GetLastLanding() ~= nil
		end, 3)
		local landed = lantern:GetLastLanding()
		local miss = if predicted and landed then (landed - predicted).Magnitude else math.huge
		result("The throw lands where the preview ring is", miss < 1, string.format("predicted %s, landed %s, %.2f apart",
			if predicted then string.format("%.1f, %.1f, %.1f", predicted.X, predicted.Y, predicted.Z) else "-",
			if landed then string.format("%.1f, %.1f, %.1f", landed.X, landed.Y, landed.Z) else "-", miss))
		result("Its first impact flashes", lantern:HasBurst(), lantern:GetLastInfo())

		-- Full charge throw at the dummy: faster, hits, tags (with a visible mark), bounces back; hold flies to them.
		lantern:ResetForTest()
		local dummy = Workspace:FindFirstChild("DashTestDummy")
		local dummyRoot = dummy and dummy:FindFirstChild("HumanoidRootPart")
		local dummyHumanoid = dummy and dummy:FindFirstChildOfClass("Humanoid")
		if dummy and dummy:IsA("Model") and dummyRoot and dummyRoot:IsA("BasePart") and dummyHumanoid then
			-- The impact flash tags someone nearby it can see, without damage.
			teleport(rig, dummyRoot.Position + Vector3.new(0, 1, 24), fwd)
			task.wait(0.3)
			local nearDummy = dummyRoot.Position + Vector3.new(0, 0, 6)
			local nearHit = Workspace:Raycast(nearDummy + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0))
			if nearHit then
				nearDummy = nearHit.Position
			end
			local hpBurst = dummyHumanoid.Health
			local tagBefore = (dummy:GetAttribute("LanternTagUntil") :: number?) or 0
			lantern:SetAimForTest(nearDummy)
			lantern:ThrowForTest(nil, 0.3)
			waitFor(function()
				return lantern:GetLastLanding() ~= nil
			end, 3)
			task.wait(0.4)
			local tagAfter = (dummy:GetAttribute("LanternTagUntil") :: number?) or 0
			local flashTagged = table.find(lantern:GetBurstTagged(), dummy) ~= nil
			result("The impact flash tags someone close by, no damage", flashTagged and tagAfter > tagBefore and dummyHumanoid.Health == hpBurst,
				string.format("flash tagged %s, server tag %s, health %.0f -> %.0f", tostring(flashTagged), tostring(tagAfter > tagBefore), hpBurst, dummyHumanoid.Health))
			lantern:ResetForTest()
			task.wait(0.3)
			teleport(rig, dummyRoot.Position + Vector3.new(0, 1, 24), fwd)
			local hp0 = dummyHumanoid.Health
			aim(dummyRoot.Position - lantern:GetPosition())
			lantern:SetAimForTest(dummyRoot.Position)
			hold(Config.LanternChargeTime)
			release()
			local strong = lantern:GetLastThrowSpeed()
			waitFor(function()
				return lantern:GetTagTarget() ~= nil
			end, 1.5)
			local tagged = lantern:GetTagTarget()
			task.wait(0.15)
			local bouncedTo = lantern:GetPosition()
			task.wait(0.5)
			result("Full charge throws at LanternThrowSpeedMax", math.abs(strong - Config.LanternThrowSpeedMax) < 3, string.format("%.0f", strong))
			result("A hit tags them, deals LanternDamage and marks them", tagged == dummy and math.abs((hp0 - dummyHumanoid.Health) - Config.LanternDamage) < 0.01 and dummy:FindFirstChild("LanternTagMark") ~= nil,
				string.format("tagged %s, health %.0f -> %.0f, mark %s", if tagged then tagged.Name else "nobody", hp0, dummyHumanoid.Health, tostring(dummy:FindFirstChild("LanternTagMark") ~= nil)))
			result("The lantern bounces back toward you", bouncedTo.Z > dummyRoot.Position.Z + 1, string.format("%.1f studs back", bouncedTo.Z - dummyRoot.Position.Z))
			stamina:Set(100)
			hold()
			local tagKind = lantern:GetFlight()
			waitFor(function()
				return lantern:GetFlight() == nil
			end, 2)
			release()
			local gap = (dummyRoot.Position - rig.root.Position).Magnitude
			result("Hold while they're tagged flies you straight to them", tagKind == "Tag" and lantern:GetLastFlightEnd() == "arrived" and gap < Config.TagFlyStopDistance + 1.5,
				string.format("flight %s, ended by %s, %.1f studs from them", tostring(tagKind), lantern:GetLastFlightEnd(), gap))
		else
			log("  (no DashTestDummy in Workspace: hit tests skipped)")
		end
	end)
	if not ok then
		log('<font color="#FF6060">Test crashed: ' .. tostring(err) .. "</font>")
	end
	lantern:SetAimForTest(nil)
	lantern:ResetForTest()
	camera.CameraType = originalCameraType
	character:SetAttribute("Race", originalRace)
	stamina:Set(stamina:GetMax())
	if controls then
		controls:Enable()
	end
	teleport(rig, Vector3.new(0, 4, 0), Vector3.zAxis)
	log("Done. Fire RunLanternTest again to hide this report.")
	running = false
end

local lanternEvent = Instance.new("BindableEvent")
lanternEvent.Name = "RunLanternTest"
lanternEvent.Event:Connect(function()
	if running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runLanternTest)
	end
end)
lanternEvent.Parent = gui

-- Visual check (command bar: PlayerGui.MovementSelfTest.HoldLanternCharge:Fire(6)): puts the lantern
-- back on the hip and holds Ctrl for that many seconds, aiming with the real cursor, then throws.
local holdChargeEvent = Instance.new("BindableEvent")
holdChargeEvent.Name = "HoldLanternCharge"
holdChargeEvent.Event:Connect(function(seconds: number?)
	local character = player.Character
	local lantern = if character then Lantern.Get(character) else nil
	if not lantern or running then
		return
	end
	lantern:ResetForTest()
	task.wait(0.3)
	lantern:Press()
	task.wait(seconds or 5)
	lantern:Release()
end)
holdChargeEvent.Parent = gui


local rollEvent = Instance.new("BindableEvent")
rollEvent.Name = "RunRollTest"
rollEvent.Event:Connect(toggleRollTest)
rollEvent.Parent = gui

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.KeyCode ~= WALL_TEST_KEY or running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runWallTest)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.KeyCode ~= DASH_TEST_KEY or running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false
	else
		task.spawn(runDashTest)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode ~= RUN_KEY or running then
		return
	end
	if gui.Enabled then
		gui.Enabled = false -- F4 with the report showing hides it
	else
		task.spawn(runAll)
	end
end)
