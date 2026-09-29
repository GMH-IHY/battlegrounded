--!strict
-- Animation suite: every animation in AnimationConfig loads, and the locomotion transitions play
-- in the right order (read from the character attribute "LocoAnim" that Animate keeps): start
-- running, skid to a stop, turn around, and nothing popping through Idle in between.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local AnimationConfig = require(ReplicatedStorage.Movement.AnimationConfig)
local AnimationLibrary = require(ReplicatedStorage.Movement.AnimationLibrary)

type Context = Harness.Context

local OPEN = Vector3.new(120, 4, -60)

local function sequence(record: () -> { string }): string
	return table.concat(record(), " > ")
end

local tests: { Harness.Test } = {
	{
		name = "Every animation loads",
		run = function(t)
			local missing = {}
			local count = 0
			for name in AnimationConfig.Ids do
				count += 1
				if not AnimationLibrary.Get(name) then
					table.insert(missing, name)
				end
			end
			table.sort(missing)
			t:check("all of AnimationConfig.Ids", #missing == 0,
				if #missing == 0 then string.format("%d animations", count) else "missing: " .. table.concat(missing, ", "))
		end,
	},
	{
		name = "Start, stop and turn clips",
		run = function(t)
			t:teleport(OPEN, Vector3.zAxis)
			local record = t:recordAttribute("LocoAnim")
			t:move(Vector3.zAxis, true)
			t:wait(0.8)
			local start = sequence(record)
			t:check("standing -> running plays SprintStart, then Sprint", string.find(start, "Idle > SprintStart > Sprint") ~= nil, start)

			record = t:recordAttribute("LocoAnim")
			t:move(Vector3.zero, false)
			t:wait(0.6)
			local stop = sequence(record)
			t:check("running -> stopping plays the SprintStop skid, then Idle", string.find(stop, "Sprint > SprintStop > Idle") ~= nil, stop)

			t:move(Vector3.zAxis, true)
			t:wait(0.8)
			record = t:recordAttribute("LocoAnim")
			t:move(-Vector3.zAxis, true)
			t:wait(0.5)
			local turn = sequence(record)
			t:check("turning around at speed plays SprintTurn", string.find(turn, "SprintTurn") ~= nil, turn)
			t:stop()

			t:teleport(OPEN, Vector3.zAxis)
			record = t:recordAttribute("LocoAnim")
			t:move(Vector3.zAxis, false)
			t:wait(0.4)
			local walk = sequence(record)
			t:check("standing -> walking plays WalkStart, then the walk", string.find(walk, "Idle > WalkStart > WalkForward") ~= nil, walk)
		end,
	},
	{
		name = "Moving again cuts a stop clip short",
		run = function(t)
			t:teleport(OPEN, Vector3.zAxis)
			t:move(Vector3.zAxis, true)
			t:wait(0.8)
			local record = t:recordAttribute("LocoAnim")
			t:move(Vector3.zero, false)
			t:wait(0.08)
			t:move(Vector3.zAxis, false)
			t:wait(0.3)
			local seq = sequence(record)
			-- Straight into walking (WalkStart or the walk itself), never back through Idle first.
			t:check("SprintStop gives way to walking straight away", string.find(seq, "SprintStop > Walk") ~= nil, seq)
		end,
	},
}

return {
	name = "Animation",
	description = "Every animation loads; start / stop / turn / landing clips in order",
	tests = tests,
}
