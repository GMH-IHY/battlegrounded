--!strict
-- Flow suite: moves chaining into each other. Jump buffers (Space near the end of a vault / climb /
-- slide / dash jumps the moment it ends), dash-jumps keeping the dash's speed, a front dash handing
-- its speed to a vault, the slide-jump, and extra speed bleeding off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)

type Context = Harness.Context

local RUN = Config.RunSpeed
local LANE = Vector3.new(0, 4, -40)
local BACKWARD = -Vector3.zAxis

-- A quick Space tap that doesn't wait (it lifts 0.08 s later on its own).
local function tapJump(t: Context)
	t:press("Jump")
	task.delay(0.08, function()
		if t.jumpHeld then
			t:release("Jump")
		end
	end)
end

-- Runs `direction` from `start`; presses Space `pressAt` seconds into the move `busy` watches (nil =
-- never). Returns (a jump came out within 0.7 s after the move ended, how long the move lasted).
local function buffered(t: Context, start: Vector3, direction: Vector3, busy: () -> boolean, pressAt: number?, dashIt: boolean?): (boolean, number)
	t:teleport(start, direction)
	t:aimCamera(direction)
	t:move(direction, not dashIt)
	if dashIt then
		t:frame()
		t:press("Dash")
	end
	local t0 = os.clock()
	local startedAt: number?, endedAt: number? = nil, nil
	local pressed, jumped = false, false
	while os.clock() - t0 < 3 do
		t.humanoid:Move(direction, false)
		local now = os.clock()
		local isBusy = busy()
		if isBusy and not startedAt then
			startedAt = now
		end
		if startedAt and not endedAt and not isBusy then
			endedAt = now
		end
		if startedAt and pressAt and not pressed and isBusy and now - startedAt >= pressAt then
			tapJump(t)
			pressed = true
		end
		if endedAt then
			jumped = jumped or t.root.AssemblyLinearVelocity.Y > 30
			if now - endedAt > 0.7 then
				break
			end
		end
		t:frame()
	end
	t:stop()
	t:grounded(3)
	t:wait(0.2)
	return jumped, if startedAt and endedAt then endedAt - startedAt else -1
end

-- After a jump starts: (flat distance in the air, speed just after takeoff, speed at landing).
local function airDistance(t: Context, direction: Vector3): (number, number, number)
	local start = t.root.Position
	t:waitFor(function()
		return t.motor:GetMode() == "Air"
	end, 0.6)
	local takeoff, landing, sampled = 0, 0, false
	local t0 = os.clock()
	while t.motor:GetMode() ~= "Ground" and os.clock() - t0 < 3 do
		t.humanoid:Move(direction, false)
		if not sampled and os.clock() - t0 > 0.05 then
			takeoff = t:flatSpeed()
			sampled = true
		end
		landing = t:flatSpeed()
		t:frame()
	end
	return ((t.root.Position - start) * Vector3.new(1, 0, 1)).Magnitude, takeoff, landing
end

local tests: { Harness.Test } = {
	{
		name = "Jump buffers at the end of moves",
		run = function(t)
			t:block("ParkourTestLedge", Vector3.new(12, 6, 12), CFrame.new(-80, 3, -60))
			local function parkourBusy(): boolean
				return t.parkour:IsBusy()
			end
			local function dashBusy(): boolean
				return t.dash:IsBusy()
			end
			local v, vt = buffered(t, Vector3.new(0, 4, 18), Vector3.zAxis, parkourBusy, 0.08)
			t:check("Space near the end of a vault jumps on landing", v, string.format("vault lasted %.2fs", vt))
			t:check("a vault with no press doesn't jump", not (buffered(t, Vector3.new(0, 4, 18), Vector3.zAxis, parkourBusy, nil)))
			local c = buffered(t, Vector3.new(-80, 4, -80), Vector3.zAxis, parkourBusy, 0.3)
			t:check("Space near the end of a climb jumps on top", c)
			t:check("Space near the end of a slide jumps as you stand", (buffered(t, Vector3.new(0, 4, 58), Vector3.zAxis, parkourBusy, 0.35)))
			t:check("Space early in a slide queues a slide-jump", (buffered(t, Vector3.new(0, 4, 58), Vector3.zAxis, parkourBusy, 0.03)))
			t:waitDashReady()
			local d = buffered(t, LANE, BACKWARD, dashBusy, Config.FrontDashTime - 0.15, true)
			t:check("Space near the end of a dash jumps right after", d)
			t:waitDashReady()
			local de, det = buffered(t, LANE, BACKWARD, dashBusy, 0.03, true)
			t:check("Space early in a dash dash-jumps", de and det < Config.FrontDashTime - 0.2, string.format("dash lasted %.2fs", det))
		end,
	},
	{
		name = "Dash-jump keeps the dash's speed",
		run = function(t)
			t:teleport(LANE, BACKWARD)
			t:aimCamera(BACKWARD)
			t:move(BACKWARD, true)
			t:wait(1)
			tapJump(t)
			local runJump, runTakeoff = airDistance(t, BACKWARD)
			t:stop()
			t:waitDashReady()
			t:teleport(LANE, BACKWARD)
			t:aimCamera(BACKWARD)
			t:move(BACKWARD, true)
			t:frame()
			t:press("Dash")
			t:wait(0.15)
			tapJump(t)
			local dashJump, takeoff, landing = airDistance(t, BACKWARD)
			t:check("dash-jump takeoff is dash speed (capped)",
				t.dash:GetLastEndReason() == "jump" and takeoff > RUN + 10 and takeoff <= Config.MomentumMaxSpeed + 3,
				string.format("ended by %s, takeoff %.1f (running jump %.1f)", t.dash:GetLastEndReason(), takeoff, runTakeoff))
			t:check("it carries farther than a running jump", dashJump > runJump + 5,
				string.format("%.1f vs %.1f studs", dashJump, runJump))
			t:check("extra speed bleeds off slowly in the air", landing < takeoff and landing > RUN,
				string.format("takeoff %.1f -> landing %.1f", takeoff, landing))
			local settled = 0
			t:waitFor(function()
				return false
			end, 1.5, function()
				t:move(BACKWARD, true)
				settled = t:flatSpeed()
			end)
			t:near("on the ground it settles back to run speed", settled, RUN, 1.5)
		end,
	},
	{
		name = "Dash-jump variants",
		run = function(t)
			t:waitDashReady()
			t:teleport(LANE, BACKWARD)
			t:aimCamera(BACKWARD)
			t:move(BACKWARD, true)
			t:frame()
			t:press("Dash")
			tapJump(t)
			local _, instant = airDistance(t, BACKWARD)
			t:check("Space the instant a dash starts dash-jumps", t.dash:GetLastEndReason() == "jump" and instant > RUN + 10,
				string.format("takeoff %.1f", instant))
			t:stop()
			t:waitDashReady()
			t:teleport(LANE, BACKWARD)
			t:aimCamera(BACKWARD)
			local sideways = Vector3.new(-BACKWARD.Z, 0, BACKWARD.X)
			t:move(sideways, false)
			t:frame()
			t:press("Dash")
			t:wait(0.1)
			tapJump(t)
			local _, side = airDistance(t, sideways)
			t:check("a side dash dash-jumps", t.dash:GetLastEndReason() == "jump" and side > RUN, string.format("takeoff %.1f", side))
			t:stop()
			-- Off the JumpBox's edge (top y 4, ends at z 48), Space just after leaving it.
			t:waitDashReady()
			t:teleport(Vector3.new(-30, 8, 42), Vector3.zAxis)
			t:aimCamera(Vector3.zAxis)
			t:move(Vector3.zAxis, true)
			t:frame()
			t:press("Dash")
			t:waitFor(function()
				return t.humanoid.FloorMaterial == Enum.Material.Air
			end, 0.5)
			t:wait(0.05)
			local offAt = t.root.Position.Y
			tapJump(t)
			local rose = 0
			t:waitFor(function()
				return false
			end, 0.4, function()
				rose = math.max(rose, t.root.Position.Y - offAt)
			end)
			t:check("dashing off a ledge, Space just after still dash-jumps", t.dash:GetLastEndReason() == "jump" and rose > 3,
				string.format("rose %.1f after the edge", rose))
		end,
	},
	{
		name = "Front dash into a box vaults it at dash speed; slide-jump keeps slide speed",
		run = function(t)
			t:waitDashReady()
			t:teleport(Vector3.new(0, 4, 26), Vector3.zAxis)
			t:aimCamera(Vector3.zAxis)
			local vaults = t.parkour:GetCount("Vault")
			t:move(Vector3.zAxis, true)
			t:frame()
			t:press("Dash")
			local afterVault, sawVault = 0, false
			t:waitFor(function()
				return afterVault > 0
			end, 1.5, function()
				t:move(Vector3.zAxis, true)
				if t.parkour:IsBusy() then
					sawVault = true
				elseif sawVault then
					afterVault = t:flatSpeed()
				end
			end)
			t:check("dash hands its speed to the vault",
				t.parkour:GetCount("Vault") > vaults and t.dash:GetLastEndReason() == "move" and afterVault > RUN + 5 and afterVault <= Config.MomentumMaxSpeed + 3,
				string.format("ended by %s, speed after %.1f", t.dash:GetLastEndReason(), afterVault))
			t:stop()
			t:teleport(Vector3.new(0, 4, 60), Vector3.zAxis)
			local pressed, slideSeen = false, false
			local jumpedSpeed = -1
			local airSince: number? = nil
			t:waitFor(function()
				return jumpedSpeed >= 0
			end, 2.5, function()
				t:move(Vector3.zAxis, true)
				if t.parkour:IsBusy() and t.parkour:GetAction() == "Slide" then
					slideSeen = true
					if not pressed then
						tapJump(t)
						pressed = true
					end
				end
				if slideSeen and not t.parkour:IsBusy() and t.motor:GetMode() == "Air" then
					airSince = airSince or os.clock()
					if os.clock() - (airSince :: number) > 0.05 then
						jumpedSpeed = if t.root.AssemblyLinearVelocity.Y > 5 then t:flatSpeed() else 0
					end
				end
			end)
			local slideEnd = t.parkour:GetLastEndSpeed()
			t:check("slide-jump jumps out keeping slide speed", jumpedSpeed > 0 and jumpedSpeed >= slideEnd - 2,
				string.format("slide ended at %.1f, jumped at %.1f", slideEnd, jumpedSpeed))
		end,
	},
}

return {
	name = "Flow",
	description = "Jump buffers, dash-jumps, momentum hand-offs",
	tests = tests,
}
