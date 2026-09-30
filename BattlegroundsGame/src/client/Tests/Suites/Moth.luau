--!strict
-- Moth suite (docs/MoveData.md, "Moth"): the paper wings on the character, Left Ctrl (tap = wing
-- burst, hold = charge + throw, press with the lantern out = recall), the thrown lantern hanging where
-- it was aimed (no damage), flight by holding Space in the air inside your own light (ended by
-- letting go, leaving the light, or M1), and the lantern knocked down by a training dummy's attack.
-- Ctrl goes through Controls ("Race"), Space through "Jump".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Harness = require(script.Parent.Parent.Harness)
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local MothPartsData = require(ReplicatedStorage.Movement.MothPartsData)

type Context = Harness.Context

local BASE = Vector3.new(140, 4, -140)
local INWARD = Vector3.new(-1, 0, 1).Unit -- toward the middle of the map, so flights stay over it

local function aim(t: Context, direction: Vector3)
	local d = direction.Unit
	t.camera.CameraType = Enum.CameraType.Scriptable
	t.camera.CFrame = CFrame.lookAt(t.root.Position - d * 10, t.root.Position - d * 10 + d)
end

local function tapCtrl(t: Context)
	t:press("Race")
	task.wait(0.03)
	t:release("Race")
end

local function holdCtrl(t: Context, extra: number?)
	t:press("Race")
	task.wait(Config.LanternTapTime + (extra or 0.05))
end

local function asMoth(t: Context)
	t.character:SetAttribute("Race", "Moth")
	t.lantern:ResetForTest()
	t.stamina:Set(t.stamina:GetMax())
end

-- In the air inside a hanging lantern's light, holding Space: returns the flight that started.
local function flyInLight(t: Context, lanternAt: Vector3, from: Vector3): string?
	t.lantern:PlaceForTest(lanternAt, "Suspended")
	t:teleport(from, INWARD)
	aim(t, INWARD + Vector3.new(0, 0.4, 0))
	t:wait(0.05)
	t:press("Jump")
	t:waitFor(function()
		return t.lantern:GetFlight() ~= nil
	end, Config.FlyHoldDelay + 0.4)
	return t.lantern:GetFlight()
end

local tests: { Harness.Test } = {
	{
		name = "Paper wings and the lantern on the character",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			local wings = t.character:FindFirstChild("MothWings")
			local visible = 0
			if wings then
				for _, part in wings:GetChildren() do
					if part:IsA("BasePart") and part.Transparency < 1 then
						visible += 1
					end
				end
			end
			t:check("wings built from MothPartsData", wings ~= nil and visible == #MothPartsData.Parts,
				string.format("%d visible parts (data has %d)", visible, #MothPartsData.Parts))
			local torso = t.character:FindFirstChild("Torso") :: BasePart
			local motor = torso:FindFirstChild("RightForewing")
			t:check("wing bones are Motor6Ds (animations move them)", motor ~= nil and motor:IsA("Motor6D"))
			local lantern = t.character:FindFirstChild("Lantern")
			local core = if lantern and lantern:IsA("Model") then lantern.PrimaryPart else nil
			local hip = if core then torso.CFrame:PointToObjectSpace(core.Position) else Vector3.zero
			t:check("the lantern sits on the right hip, not glowing", core ~= nil and hip.X > 0.8 and hip.Y < -0.5 and core.Material ~= Enum.Material.Neon,
				string.format("torso-local %.1f, %.1f, %.1f", hip.X, hip.Y, hip.Z))
			t.character:SetAttribute("Race", "")
			tapCtrl(t)
			t:check("not a Moth: Ctrl does nothing", t.lantern:GetFlight() == nil and t.lantern:GetState() == "Hip", t.lantern:GetLastInfo())
			t.character:SetAttribute("Race", "Moth")
		end,
	},
	{
		name = "Wing burst (tap)",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			local direction = (INWARD + Vector3.new(0, 0.3, 0)).Unit
			aim(t, direction)
			local start = t.root.Position
			tapCtrl(t)
			local kind = t.lantern:GetFlight()
			t:waitFor(function()
				return t.lantern:GetFlight() == nil
			end, 1)
			local flown = t.root.Position - start
			local after = t.root.AssemblyLinearVelocity.Magnitude
			t:check("covers WingFlightDistance where the camera looks",
				kind == "Wings" and math.abs(flown.Magnitude - Config.WingFlightDistance) < 3 and flown.Unit:Dot(direction) > 0.95,
				string.format("flight %s, %.1f studs (want %d)", tostring(kind), flown.Magnitude, Config.WingFlightDistance))
			local flightSpeed = Config.WingFlightDistance / Config.WingFlightTime
			t:check("costs WingFlightCost stamina and keeps some momentum",
				math.abs((t.stamina:GetMax() - t.stamina:GetValue()) - Config.WingFlightCost) < 1 and after > flightSpeed * Config.WingFlightKeep * 0.6,
				string.format("stamina %d, speed after %.1f", t.stamina:GetValue(), after))
			t:grounded(8)
			t:teleport(BASE, INWARD)
			t.stamina:Set(t.stamina:GetMax())
			aim(t, direction)
			start = t.root.Position
			t:wait(Config.WingFlightCooldown)
			tapCtrl(t)
			t:wait(0.1)
			t:press("M1")
			local short = (t.root.Position - start).Magnitude
			t:check("M1 ends the flight early and swings", t.lantern:GetLastFlightEnd() == "m1" and short < Config.WingFlightDistance * 0.6
				and t.combat:GetPhase() ~= "Idle", string.format("ended by %s after %.1f studs, swing %s", t.lantern:GetLastFlightEnd(), short, t.combat:GetPhase()))
			t:grounded(8)
			t:teleport(BASE, INWARD)
			t.stamina:Set(t.stamina:GetMax())
			aim(t, direction)
			t:wait(Config.WingFlightCooldown)
			tapCtrl(t)
			t:wait(0.05)
			t:check("no dash while flying", not t.dash:Request())
		end,
	},
	{
		name = "Charge, throw: it hangs where aimed, no damage; Ctrl recalls it",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			aim(t, Vector3.new(INWARD.X, 0.1, INWARD.Z))
			local target = t.root.Position + INWARD * 25 + Vector3.new(0, 8, 0)
			t.lantern:SetAimForTest(target)
			holdCtrl(t, 0)
			local charging = t.lantern:GetState() == "Charging"
			t:wait(0.2)
			local preview = t.camera:FindFirstChild("LanternThrowPreview")
			local dots = 0
			if preview then
				for _, d in preview:GetChildren() do
					if d:IsA("BasePart") and d.Name ~= "Target" and d.Transparency < 1 then
						dots += 1
					end
				end
			end
			local look = t.root.CFrame.LookVector
			local facing = Vector3.new(look.X, 0, look.Z).Unit:Dot(INWARD)
			t:check("while charging: throw path shown, body faces the aim", charging and dots >= 5 and facing > 0.9,
				string.format("%d path dots, facing dot %.2f", dots, facing))
			local before = t.root.Position
			t:release("Race")
			t:check("release throws and hides the path", t.lantern:GetState() == "Thrown" and t.camera:FindFirstChild("LanternThrowPreview") == nil)
			local weak = t.lantern:GetLastThrowSpeed()
			t:wait(0.25)
			t:check("throwing doesn't move you", (t.root.Position - before).Magnitude < 0.6)
			t:waitFor(function()
				return t.lantern:GetState() == "Suspended"
			end, 2)
			local hangAt = t.lantern:GetPosition()
			t:check("it stops at the aimed point and hangs there", t.lantern:GetState() == "Suspended" and (hangAt - target).Magnitude < 2,
				string.format("state %s, %.1f studs from the aim", t.lantern:GetState(), (hangAt - target).Magnitude))
			t:wait(0.5)
			t:check("it stays put while it hangs", t.lantern:GetState() == "Suspended" and (t.lantern:GetPosition() - hangAt).Magnitude < 0.05)
			t:check("a quick hold throws slowly", weak < Config.LanternThrowSpeedMin + 25, string.format("%.0f", weak))
			tapCtrl(t)
			local recalled = t.lantern:GetState() == "Returning"
			t:waitFor(function()
				return t.lantern:GetState() == "Hip"
			end, 2)
			t:check("Ctrl with it out recalls it: it flies back to the hand", recalled and t.lantern:GetState() == "Hip",
				"state " .. t.lantern:GetState())
			holdCtrl(t)
			local blocked = t.lantern:GetState() ~= "Charging"
			t:release("Race")
			t:check("just caught: no throw during LanternGrabCooldown", blocked)
			t.lantern:SetAimForTest(nil)
		end,
	},
	{
		name = "After LanternSuspendTime it comes back by itself",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			t.lantern:PlaceForTest(BASE + INWARD * 12 + Vector3.new(0, 6, 0), "Suspended")
			t:wait(Config.LanternSuspendTime - 0.5)
			local still = t.lantern:GetState() == "Suspended"
			t:waitFor(function()
				return t.lantern:GetState() == "Hip"
			end, 2)
			t:check("hangs the whole time, then returns to the hip", still and t.lantern:GetState() == "Hip", "state " .. t.lantern:GetState())
		end,
	},
	{
		name = "Hold Space in the air inside your light: fly; letting go ends it",
		run = function(t)
			asMoth(t)
			local lanternAt = BASE + Vector3.new(0, 12, 0)
			local kind = flyInLight(t, lanternAt, BASE + Vector3.new(0, 10, 4))
			local sp0 = t.stamina:GetValue()
			t:wait(1)
			local drained = sp0 - t.stamina:GetValue()
			t:check("holding Space in the air inside the light flies", kind == "Free", tostring(kind) .. ": " .. t.lantern:GetLastInfo())
			t:near("drains FlyDrain stamina a second", drained, Config.FlyDrain, 4)
			t:release("Jump")
			t:wait(0.05)
			t:check("letting go of Space ends it", t.lantern:GetFlight() == nil and t.lantern:GetLastFlightEnd() == "released",
				t.lantern:GetLastFlightEnd())
			t:grounded(8)

			-- Leaving the light ends it.
			asMoth(t)
			kind = flyInLight(t, lanternAt, BASE + Vector3.new(0, 10, 4))
			t:teleport(lanternAt + Vector3.new(0, 0, Config.LanternLightRadius + 5), INWARD)
			t:wait(0.05)
			t:release("Jump")
			t:check("leaving the light ends it", kind == "Free" and t.lantern:GetLastFlightEnd() == "left_light", t.lantern:GetLastFlightEnd())
			t:grounded(8)

			-- M1 ends it (and swings).
			asMoth(t)
			kind = flyInLight(t, lanternAt, BASE + Vector3.new(0, 10, 4))
			t:press("M1")
			t:release("Jump")
			t:check("M1 ends it and swings", kind == "Free" and t.lantern:GetLastFlightEnd() == "m1" and t.combat:GetPhase() ~= "Idle",
				string.format("%s, swing %s", t.lantern:GetLastFlightEnd(), t.combat:GetPhase()))
			t:grounded(8)

			-- Outside the light: nothing.
			asMoth(t)
			t.lantern:PlaceForTest(BASE + Vector3.new(0, 8, -(Config.LanternLightRadius + 10)), "Suspended")
			t:teleport(BASE + Vector3.new(0, 10, 0), INWARD)
			t:wait(0.05)
			t:press("Jump")
			t:wait(Config.FlyHoldDelay + 0.2)
			local outside = t.lantern:GetFlight()
			t:release("Jump")
			t:check("outside the light: no flight", outside == nil, t.lantern:GetLastInfo())
			t:grounded(8)
			t.lantern:ResetForTest()
		end,
	},
	{
		name = "The throw hangs on the preview ring; a dummy's attack knocks it down",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			t:wait(0.4)
			local floor = t.root.Position + INWARD * 30 + Vector3.new(0, -6, 0)
			local hit = Workspace:Raycast(floor + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0))
			if hit then
				floor = hit.Position
			end
			aim(t, Vector3.new(INWARD.X, -0.3, INWARD.Z))
			t.lantern:SetAimForTest(floor)
			local predicted = t.lantern:PredictForTest(0.5)
			t.lantern:ThrowForTest(nil, 0.5)
			t:waitFor(function()
				return t.lantern:GetLastLanding() ~= nil
			end, 3)
			local landed = t.lantern:GetLastLanding()
			local miss = if landed then (landed - predicted).Magnitude else math.huge
			t:check("hangs where the preview ring is", miss < 1, string.format("%.2f studs apart", miss))
			t.lantern:SetAimForTest(nil)

			-- A thrown lantern hitting someone: no damage, it just hangs there.
			local dummy = t:dummy("DummyStand")
			local dummyRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart
			local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
			t.lantern:ResetForTest()
			t:teleport(dummyRoot.Position + dummyRoot.CFrame.LookVector * 20 + Vector3.new(0, 1, 0), -dummyRoot.CFrame.LookVector)
			local hp0 = dummyHumanoid.Health
			aim(t, dummyRoot.Position - t.lantern:GetPosition())
			t.lantern:SetAimForTest(dummyRoot.Position)
			holdCtrl(t, Config.LanternChargeTime)
			t:release("Race")
			local strong = t.lantern:GetLastThrowSpeed()
			t:waitFor(function()
				return t.lantern:GetState() == "Suspended"
			end, 1.5)
			t:near("full charge throws at LanternThrowSpeedMax", strong, Config.LanternThrowSpeedMax, 3)
			t:check("hitting someone does no damage; it hangs", t.lantern:GetState() == "Suspended" and math.abs(hp0 - dummyHumanoid.Health) < 0.01,
				string.format("state %s, health %.0f -> %.0f", t.lantern:GetState(), hp0, dummyHumanoid.Health))
			t.lantern:SetAimForTest(nil)

			-- Knocked down: the dummy swings at it.
			t.lantern:ResetForTest()
			t.lantern:PlaceForTest(dummyRoot.Position + dummyRoot.CFrame.LookVector * 3 + Vector3.new(0, 0.5, 0), "Suspended")
			t:wait(0.3) -- the server places it
			t:debug("DummyMove", "DummyStand", "Sword.M1_1")
			t:waitFor(function()
				return t.lantern:GetState() == "Dropped"
			end, 1)
			t:check("an attack touching it knocks it down", t.lantern:GetState() == "Dropped", "state " .. t.lantern:GetState())
			t:near("and it can't be thrown for LanternKnockLockout", t.lantern:GetKnockLockout(), Config.LanternKnockLockout, 1)
			tapCtrl(t)
			t:waitFor(function()
				return t.lantern:GetState() == "Hip"
			end, 2)
			holdCtrl(t)
			local refused = t.lantern:GetState() ~= "Charging"
			t:release("Race")
			t:check("recalled, but still no throw while knocked down", t.lantern:GetState() == "Hip" and refused, t.lantern:GetLastInfo())
			t.lantern:ResetForTest()
		end,
	},
}

return {
	name = "Moth",
	description = "Paper wings, wing burst, lantern throw / hang / recall / knock-down, flight in your light",
	tests = tests,
}
