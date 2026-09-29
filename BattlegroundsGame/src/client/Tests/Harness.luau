--!strict
-- Harness (ModuleScript)
-- Location: StarterPlayer > StarterPlayerScripts > Tests > Harness
--
-- The in-Studio test runner. A suite is a ModuleScript in Tests > Suites returning
--   { name = "Dash", description = "...", tests = { { name = "...", run = function(t) ... end }, ... } }
-- Each test gets a Context `t` and makes any number of checks with t:check(name, passed, detail).
-- A test fails if a check fails or it errors; the next test runs either way.
--
-- Tests play the game the way a player does: keys go through Controls (the same functions the
-- keyboard calls), movement through Humanoid:Move with Roblox's own controls switched off, and
-- Space held means Humanoid.Jump every frame (what Roblox's control script does). Before every test
-- the character is reset: keys released, standing on the ground, full health and stamina, no
-- cooldowns, camera back to normal. Anything a test creates with t:temp() is removed after it.
--
-- Combat: the server owns fights, so combat tests read the server's state (t:server(model) returns
-- a Fighter snapshot) and drive the training dummies through the Studio Debug remote
-- (t:dummy(name, mode, cframe) puts one in place, t:debug(op, ...) for anything else).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Movement = ReplicatedStorage:WaitForChild("Movement")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local CharacterMotor = require(Movement:WaitForChild("CharacterMotor"))
local Dash = require(Movement:WaitForChild("Dash"))
local WallHop = require(Movement:WaitForChild("WallHop"))
local LandingRoll = require(Movement:WaitForChild("LandingRoll"))
local AutoParkour = require(Movement:WaitForChild("AutoParkour"))
local Lantern = require(Movement:WaitForChild("Lantern"))
local Stamina = require(Movement:WaitForChild("Stamina"))
local Controls = require(Movement:WaitForChild("Controls"))
local CombatClient = require(Combat:WaitForChild("CombatClient"))
local CombatRemotes = require(Combat:WaitForChild("CombatRemotes"))

local player = Players.LocalPlayer

export type Check = { name: string, passed: boolean, detail: string }
export type Result = {
	suite: string,
	test: string,
	checks: { Check },
	logs: { string },
	error: string?,
	seconds: number,
	passed: boolean,
}

export type JumpStats = { height: number, airtime: number, hang: number, maxY: number, peakSpeed: number }

local Context = {}
Context.__index = Context

type ContextData = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor,
	dash: Dash.Dash,
	hop: WallHop.WallHop,
	roll: LandingRoll.LandingRoll,
	parkour: AutoParkour.AutoParkour,
	lantern: Lantern.Lantern,
	stamina: Stamina.Stamina,
	combat: CombatClient.CombatClient,
	actions: Controls.Actions,
	camera: Camera,
	result: Result,
	jumpHeld: boolean,
	temps: { Instance },
	savedHealth: number,
}

export type Context = typeof(setmetatable({} :: ContextData, Context))
export type Test = { name: string, run: (Context) -> () }
export type Suite = { name: string, description: string, tests: { Test } }

local Harness = {}

-- CHECKS ---------------------------------------------------------------------------------------

function Context.check(self: Context, name: string, passed: boolean, detail: string?)
	table.insert(self.result.checks, { name = name, passed = passed, detail = detail or "" })
end

function Context.log(self: Context, text: string)
	table.insert(self.result.logs, text)
end

-- Makes a check that `value` is within `tolerance` of `want`, with both in the detail.
function Context.near(self: Context, name: string, value: number, want: number, tolerance: number, extra: string?)
	local detail = string.format("%.2f (want %.2f ± %.2f)", value, want, tolerance)
	if extra then
		detail ..= ", " .. extra
	end
	self:check(name, math.abs(value - want) <= tolerance, detail)
end

-- TIME ------------------------------------------------------------------------------------------

-- One frame. Space held = Humanoid.Jump every frame, like Roblox's control script.
function Context.frame(self: Context): number
	if self.jumpHeld then
		self.humanoid.Jump = true
	end
	return task.wait()
end

function Context.wait(self: Context, seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
		self:frame()
	end
end

-- Waits until `condition` is true (checked every frame), at most `timeout` seconds. `each` runs
-- every frame first (keep steering, sample something).
function Context.waitFor(self: Context, condition: () -> boolean, timeout: number, each: (() -> ())?): boolean
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		if each then
			each()
		end
		if condition() then
			return true
		end
		self:frame()
	end
	return condition()
end

function Context.grounded(self: Context, timeout: number?): boolean
	return self:waitFor(function()
		return self.motor:GetMode() == "Ground"
	end, timeout or 4)
end

-- INPUT -----------------------------------------------------------------------------------------

function Context.press(self: Context, action: Controls.ActionName)
	if action == "Jump" then
		self.jumpHeld = true
		self.humanoid.Jump = true
	end
	(self.actions.press :: any)[action]()
end

function Context.release(self: Context, action: Controls.ActionName)
	if action == "Jump" then
		self.jumpHeld = false
		self.humanoid.Jump = false
	end
	(self.actions.release :: any)[action]()
end

-- Press, hold for `hold` seconds (default a quick tap), release.
function Context.tap(self: Context, action: Controls.ActionName, hold: number?)
	self:press(action)
	self:wait(hold or 0.06)
	self:release(action)
end

-- Keys held, as a world direction (Humanoid:Move); sprint = the run toggle (double-tapped W).
function Context.move(self: Context, direction: Vector3, sprint: boolean?)
	self.motor:SetSprinting(sprint == true)
	self.humanoid:Move(direction, false)
end

function Context.stop(self: Context)
	self.motor:SetSprinting(false)
	self.humanoid:Move(Vector3.zero, false)
	if self.jumpHeld then
		self:release("Jump")
	end
	self.humanoid.Jump = false
end

-- PLACES ----------------------------------------------------------------------------------------

-- Puts the character at `position` facing `facing`, stopped and standing on the ground.
function Context.teleport(self: Context, position: Vector3, facing: Vector3)
	self:stop()
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.root.CFrame = CFrame.lookAt(position, position + facing)
	task.wait(0.1)
	self:grounded(3)
	task.wait(0.3)
end

-- A camera looking along `look` from behind the character (tests that aim with the camera).
function Context.aimCamera(self: Context, look: Vector3)
	self.camera.CameraType = Enum.CameraType.Scriptable
	local at = self.root.Position
	self.camera.CFrame = CFrame.lookAt(at - look.Unit * 12 + Vector3.new(0, 5, 0), at)
end

-- Anything given here is destroyed after the test.
function Context.temp(self: Context, instance: Instance)
	table.insert(self.temps, instance)
end

-- An anchored part for this test only.
function Context.block(self: Context, name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = Color3.fromRGB(120, 90, 200)
	part.Parent = Workspace
	self:temp(part)
	return part
end

-- MEASURING -------------------------------------------------------------------------------------

function Context.flatSpeed(self: Context): number
	local v = self.root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function Context.waitDashReady(self: Context)
	task.wait(self.dash:GetCooldownRemaining() + 0.05)
end

-- Sets health to a share of max for the rest of the test (restored afterwards).
function Context.setHealth(self: Context, share: number)
	self.humanoid.Health = self.humanoid.MaxHealth * share
end

-- Presses jump once (the keys set beforehand stay held) and watches the airtime.
function Context.jumpOnce(self: Context, timeout: number?): JumpStats
	local startY = self.root.Position.Y
	self:press("Jump")
	self:waitFor(function()
		return self.motor:GetMode() == "Air"
	end, 0.5)
	self:release("Jump")
	local start = os.clock()
	local maxY, hang, peakSpeed = startY, 0, 0
	while self.motor:GetMode() == "Air" and os.clock() - start < (timeout or 4) do
		local dt = self:frame()
		local velocity = self.root.AssemblyLinearVelocity
		maxY = math.max(maxY, self.root.Position.Y)
		peakSpeed = math.max(peakSpeed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
		-- A normal jump is over in well under a second. Hovering after that = stuck.
		if os.clock() - start > 0.7 and math.abs(velocity.Y) < 4 then
			hang += dt
		end
	end
	return { height = maxY - startY, airtime = os.clock() - start, hang = hang, maxY = maxY, peakSpeed = peakSpeed }
end

-- Records every change of the character attribute `name` (e.g. "LocoAnim") until the returned
-- function is called, which gives back the list of values in order (nil shows as "-").
function Context.recordAttribute(self: Context, name: string): () -> { string }
	return self:recordAttributeOn(self.character, name)
end

-- The same for any instance (a dummy's "CombatState").
function Context.recordAttributeOn(self: Context, instance: Instance, name: string): () -> { string }
	local seen: { string } = {}
	local function add()
		local value = instance:GetAttribute(name)
		table.insert(seen, if value == nil then "-" else tostring(value))
	end
	add()
	local connection = instance:GetAttributeChangedSignal(name):Connect(add)
	return function()
		connection:Disconnect()
		return seen
	end
end

-- COMBAT ----------------------------------------------------------------------------------------

-- The Studio Debug remote (CombatServer): test helpers on the server.
function Context.debug(self: Context, op: string, a: any?, b: any?): any
	return CombatRemotes.Get().Debug:InvokeServer(op, a, b)
end

-- The server's view of a fighter (yours by default): state, move, frame, stamina, combo...
function Context.server(self: Context, model: Model?): { [string]: any }
	local snapshot = self:debug("State", model or self.character)
	return if typeof(snapshot) == "table" then snapshot else {}
end

-- A training dummy by name (Workspace > TrainingDummies), reset to full health at `cframe`
-- (default: where it stands) in `mode`.
function Context.dummy(self: Context, name: string, mode: string?, cframe: CFrame?): Model
	local folder = Workspace:WaitForChild("TrainingDummies", 10)
	local model = folder and folder:WaitForChild(name, 10)
	assert(model and model:IsA("Model"), "no dummy " .. name)
	self:debug("ResetDummy", name, cframe)
	self:debug("DummyMode", name, mode or "Stand")
	task.wait(0.15)
	return model
end

-- Stands `studs` in front of a dummy, facing it.
function Context.faceDummy(self: Context, dummy: Model, studs: number)
	local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart
	local look = root.CFrame.LookVector
	local spot = root.Position + Vector3.new(look.X, 0, look.Z).Unit * studs + Vector3.new(0, 1, 0)
	self:teleport(spot, (root.Position - spot) * Vector3.new(1, 0, 1))
end

-- Waits until the attribute `name` on `model` equals `value`.
function Context.waitAttribute(self: Context, model: Instance, name: string, value: any, timeout: number): boolean
	return self:waitFor(function()
		return model:GetAttribute(name) == value
	end, timeout)
end

-- RUNNING ---------------------------------------------------------------------------------------

local function controlModule(): any?
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, playerModule = pcall((require :: any), module)
	return if ok then playerModule:GetControls() else nil
end

-- Everything a test needs, or nil + why not (character still spawning).
local function makeContext(result: Result): (Context?, string?)
	local character = player.Character
	if not character then
		return nil, "no character"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local motor = CharacterMotor.Get(character)
	local dash = Dash.Get(character)
	local hop = WallHop.Get(character)
	local roll = LandingRoll.Get(character)
	local parkour = AutoParkour.Get(character)
	local lantern = Lantern.Get(character)
	local stamina = Stamina.Get(character)
	local combat = CombatClient.Get(character)
	local actions = Controls.Get(character)
	local camera = Workspace.CurrentCamera
	if not (humanoid and root and root:IsA("BasePart") and motor and dash and hop and roll and parkour and lantern and stamina and combat and actions and camera) then
		return nil, "character's movement isn't ready yet"
	end
	local context = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		dash = dash,
		hop = hop,
		roll = roll,
		parkour = parkour,
		lantern = lantern,
		stamina = stamina,
		combat = combat,
		actions = actions,
		camera = camera,
		result = result,
		jumpHeld = false,
		temps = {},
		savedHealth = humanoid.Health,
	} :: ContextData, Context)
	return context, nil
end

local function reset(t: Context)
	t.actions.release.Jump()
	t.actions.release.Race()
	t.actions.release.Forward()
	t.actions.release.Block()
	t.jumpHeld = false
	t:stop()
	t.combat:ResetForTest()
	t:debug("Reset")
	t.camera.CameraType = Enum.CameraType.Custom
	t.humanoid.Health = t.humanoid.MaxHealth
	t.stamina:Set(t.stamina:GetMax())
end

local function cleanup(t: Context)
	for _, instance in t.temps do
		instance:Destroy()
	end
	table.clear(t.temps)
	reset(t)
	t.humanoid.Health = t.savedHealth
end

-- Runs one test; returns its result (never throws).
function Harness.runTest(suite: Suite, test: Test): Result
	local result: Result = {
		suite = suite.name,
		test = test.name,
		checks = {},
		logs = {},
		error = nil,
		seconds = 0,
		passed = false,
	}
	local t, why = makeContext(result)
	if not t then
		result.error = why
		return result
	end
	local started = os.clock()
	reset(t)
	local ok, err = xpcall(function()
		test.run(t)
	end, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	cleanup(t)
	result.seconds = os.clock() - started
	if not ok then
		result.error = tostring(err)
	end
	local allPassed = #result.checks > 0
	for _, check in result.checks do
		allPassed = allPassed and check.passed
	end
	result.passed = ok and allPassed
	return result
end

-- Runs suites in order. `onResult` gets each test's result as it finishes; `shouldStop` is asked
-- between tests. Roblox's controls are off while it runs.
function Harness.run(suites: { Suite }, onResult: (Result) -> (), shouldStop: () -> boolean)
	local controls = controlModule()
	if controls then
		controls:Disable()
	end
	for _, suite in suites do
		for _, test in suite.tests do
			if shouldStop() then
				break
			end
			onResult(Harness.runTest(suite, test))
		end
	end
	if controls then
		controls:Enable()
	end
	local t = makeContext({ suite = "", test = "", checks = {}, logs = {}, seconds = 0, passed = true })
	if t then
		t:teleport(Vector3.new(0, 4, 0), Vector3.zAxis)
	end
end

return Harness
