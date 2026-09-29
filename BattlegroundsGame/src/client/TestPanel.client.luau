--!strict
-- TestPanel (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > TestPanel
--
-- Studio only. F4 during Play opens the test panel: "Run all" runs every suite except the slow
-- ones, or pick a single suite. The tests take over your character (don't touch the keyboard);
-- results appear as each test finishes, and are printed to Output too. "Stop" ends the run after
-- the current test. The suites live in StarterPlayerScripts > Tests > Suites (see Tests > Harness).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local testsFolder = script.Parent:WaitForChild("Tests")
local Harness = require(testsFolder:WaitForChild("Harness"))
local suitesFolder = testsFolder:WaitForChild("Suites")

local TOGGLE_KEY = Enum.KeyCode.F4
-- In the order they run. Slow suites are left out of "Run all".
local ORDER = { "Animation", "Basics", "Dash", "Attacks", "Combat", "Landing", "WallHop", "Parkour", "Flow", "Truss", "Moth", "Performance", "ParkourSweep" }
local SLOW: { [string]: boolean } = { ParkourSweep = true }

local suites: { Harness.Suite } = {}
for _, name in ORDER do
	local module = suitesFolder:WaitForChild(name, 5)
	if module and module:IsA("ModuleScript") then
		table.insert(suites, (require :: any)(module))
	else
		warn("[Tests] suite missing: " .. name)
	end
end

-- UI ----------------------------------------------------------------------------------------------

local GREEN, RED, GREY = "#6BE36B", "#FF6060", "#A8A8A8"

local gui = Instance.new("ScreenGui")
gui.Name = "TestPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Enabled = false

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, 50)
panel.Size = UDim2.fromOffset(760, 520)
panel.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local buttons = Instance.new("Frame")
buttons.Size = UDim2.new(0, 170, 1, 0)
buttons.BackgroundTransparency = 1
buttons.Parent = panel
local buttonList = Instance.new("UIListLayout")
buttonList.Padding = UDim.new(0, 4)
buttonList.Parent = buttons
local buttonPadding = Instance.new("UIPadding")
buttonPadding.PaddingTop = UDim.new(0, 8)
buttonPadding.PaddingLeft = UDim.new(0, 8)
buttonPadding.PaddingRight = UDim.new(0, 8)
buttonPadding.Parent = buttons

local summary = Instance.new("TextLabel")
summary.Position = UDim2.fromOffset(180, 8)
summary.Size = UDim2.new(1, -190, 0, 22)
summary.BackgroundTransparency = 1
summary.Font = Enum.Font.Code
summary.TextSize = 15
summary.TextColor3 = Color3.new(1, 1, 1)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.RichText = true
summary.Text = "Pick a suite, or Run all. Don't touch the keyboard while it runs."
summary.Parent = panel

local results = Instance.new("ScrollingFrame")
results.Position = UDim2.fromOffset(180, 36)
results.Size = UDim2.new(1, -190, 1, -46)
results.BackgroundTransparency = 1
results.BorderSizePixel = 0
results.ScrollBarThickness = 6
results.AutomaticCanvasSize = Enum.AutomaticSize.Y
results.CanvasSize = UDim2.new()
results.Parent = panel
local resultList = Instance.new("UIListLayout")
resultList.Padding = UDim.new(0, 2)
resultList.Parent = results

gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local lineCount = 0
local function line(text: string)
	lineCount += 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = lineCount
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.RichText = true
	label.Text = text
	label.Parent = results
	results.CanvasPosition = Vector2.new(0, math.huge)
	print("[Tests] " .. (string.gsub(text, "<[^>]+>", "")))
end

local function color(text: string, hex: string): string
	return string.format('<font color="%s">%s</font>', hex, text)
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- RUNNING -----------------------------------------------------------------------------------------

local running = false
local stopRequested = false
local passedTests, failedTests = 0, 0
local failures: { string } = {}

local function report(result: Harness.Result)
	local tag = if result.passed then color("PASS", GREEN) else color("FAIL", RED)
	line(string.format("%s <b>%s / %s</b> %s", tag, escape(result.suite), escape(result.test), color(string.format("(%.1fs)", result.seconds), GREY)))
	for _, check in result.checks do
		local mark = if check.passed then color("  ok ", GREEN) else color("  X  ", RED)
		line(mark .. escape(check.name) .. (if check.detail ~= "" then color(" — " .. escape(check.detail), GREY) else ""))
	end
	for _, text in result.logs do
		line(color("  · " .. escape(text), GREY))
	end
	if result.error then
		line(color("  error: " .. escape(result.error), RED))
	end
	if result.passed then
		passedTests += 1
	else
		failedTests += 1
		table.insert(failures, result.suite .. " / " .. result.test)
	end
	summary.Text = string.format("Running... %s passed, %s failed", color(tostring(passedTests), GREEN), color(tostring(failedTests), RED))
end

local function run(selected: { Harness.Suite })
	if running then
		return
	end
	running = true
	stopRequested = false
	passedTests, failedTests = 0, 0
	table.clear(failures)
	for _, child in results:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local started = os.clock()
	Harness.run(selected, report, function()
		return stopRequested
	end)
	running = false
	local verdict = if failedTests == 0 then color("ALL PASSED", GREEN) else color(string.format("%d FAILED", failedTests), RED)
	summary.Text = string.format("%s — %d passed, %d failed in %.0fs%s", verdict, passedTests, failedTests, os.clock() - started,
		if stopRequested then " (stopped)" else "")
	if #failures > 0 then
		line(color("Failed: " .. escape(table.concat(failures, ", ")), RED))
	end
end

local function button(text: string, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = Color3.fromRGB(44, 44, 50)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = buttons
	b.Activated:Connect(onClick)
end

button("Run all", function()
	local quick = {}
	for _, suite in suites do
		if not SLOW[suite.name] then
			table.insert(quick, suite)
		end
	end
	task.spawn(run, quick)
end)
for _, suite in suites do
	button(suite.name .. (if SLOW[suite.name] then " (slow)" else ""), function()
		task.spawn(run, { suite })
	end)
end
button("Stop", function()
	stopRequested = true
end)
button("Close (F4)", function()
	gui.Enabled = false
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.KeyCode == TOGGLE_KEY then
		gui.Enabled = not gui.Enabled
	end
end)
