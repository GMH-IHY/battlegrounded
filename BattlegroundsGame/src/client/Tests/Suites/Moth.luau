--!strict
-- Moth suite: the paper wings on the character, Left Ctrl (tap = wing flight, hold = charge +
-- throw, press in the air = suspend, hold with the lantern away = fly inside its light or to a
-- tagged opponent), M1 ending a flight, the throw landing where the preview said, and hits on the
-- DashTestDummy. Ctrl goes through Controls ("Race").

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
		name = "Wing flight (tap)",
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
				and t.m1:GetPhase() ~= "Idle", string.format("ended by %s after %.1f studs, swing %s", t.lantern:GetLastFlightEnd(), short, t.m1:GetPhase()))
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
		name = "Charge, throw, suspend, fly in the light, grab",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			aim(t, Vector3.new(INWARD.X, 0.1, INWARD.Z))
			t.lantern:SetAimForTest(t.root.Position + INWARD * 40 + Vector3.new(0, 8, 0))
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
			tapCtrl(t)
			local p0 = t.lantern:GetPosition()
			t:wait(0.8)
			t:check("press while it's in the air suspends it", t.lantern:GetState() == "Suspended" and (t.lantern:GetPosition() - p0).Magnitude < 0.05,
				"state " .. t.lantern:GetState())
			t.stamina:Set(t.stamina:GetMax())
			local lanternAt = t.lantern:GetPosition()
			aim(t, (t.root.Position - lanternAt) * Vector3.new(1, 0, 1) + Vector3.new(0, 2, 0))
			holdCtrl(t)
			local kind = t.lantern:GetFlight()
			local farthest = 0
			t:waitFor(function()
				return false
			end, 1.5, function()
				farthest = math.max(farthest, (t.root.Position - lanternAt).Magnitude)
			end)
			t:check("hold inside the light: free flight that can't leave the light", kind == "Free" and farthest <= Config.LanternLightRadius + 1.5,
				string.format("flight %s, farthest %.1f (radius %d)", tostring(kind), farthest, Config.LanternLightRadius))
			local speedBefore = 0
			t:waitFor(function()
				return t.lantern:GetState() == "Hip"
			end, 3, function()
				aim(t, t.lantern:GetPosition() - t.root.Position)
				speedBefore = t.root.AssemblyLinearVelocity.Magnitude
			end)
			local speedAfter = t.root.AssemblyLinearVelocity.Magnitude
			t:release("Race")
			t:check("flying into the lantern grabs it with a burst", t.lantern:GetState() == "Hip" and t.lantern:GetLastFlightEnd() == "grab" and speedAfter > speedBefore + 10,
				string.format("speed %.0f -> %.0f", speedBefore, speedAfter))
			holdCtrl(t)
			local blocked = t.lantern:GetState() ~= "Charging"
			t:release("Race")
			t:check("just grabbed: no throw during LanternGrabCooldown", blocked)
			t:check("a quick hold throws slowly", weak < Config.LanternThrowSpeedMin + 25, string.format("%.0f", weak))
			t:grounded(8)
		end,
	},
	{
		name = "No flight outside the light; lying lantern; walking into it",
		run = function(t)
			asMoth(t)
			t:teleport(BASE, INWARD)
			t.lantern:PlaceForTest(BASE + Vector3.new(0, 8, -(Config.LanternLightRadius + 10)), "Suspended")
			holdCtrl(t)
			local outside = t.lantern:GetFlight()
			t:release("Race")
			t:check("outside its light: no flight", outside == nil, t.lantern:GetLastInfo())
			t.lantern:PlaceForTest(BASE + Vector3.new(0, 8, -5), "Suspended")
			t:teleport(BASE + Vector3.new(0, 8, -5), INWARD)
			holdCtrl(t)
			local started = t.lantern:GetFlight() == "Free"
			t:teleport(BASE + Vector3.new(0, 8, -(Config.LanternLightRadius + 5)), INWARD)
			t:wait(0.05)
			local ended = t.lantern:GetFlight() == nil and t.lantern:GetLastFlightEnd() == "left_light"
			t:release("Race")
			t:check("leaving the light stops the flight", started and ended, t.lantern:GetLastInfo())
			t.lantern:PlaceForTest(BASE + INWARD * 10 + Vector3.new(0, -3.5, 0), "Dropped")
			holdCtrl(t)
			local lying = t.lantern:GetFlight()
			t:release("Race")
			t:check("lantern lying somewhere: no flight", lying == nil)
			t:teleport(BASE + INWARD * 9, INWARD)
			t:waitFor(function()
				return t.lantern:GetState() == "Hip"
			end, 1)
			t:check("walking into it puts it back on the hip", t.lantern:GetState() == "Hip")
		end,
	},
	{
		name = "The throw lands on the preview ring; hits and tags",
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
			local miss = if predicted and landed then (landed - predicted).Magnitude else math.huge
			t:check("lands where the preview ring is", miss < 1, string.format("%.2f studs apart", miss))
			t:check("its first impact flashes", t.lantern:HasBurst())
			t.lantern:SetAimForTest(nil)

			local dummy = Workspace:FindFirstChild("DashTestDummy")
			local dummyRoot = dummy and dummy:FindFirstChild("HumanoidRootPart")
			local dummyHumanoid = dummy and dummy:FindFirstChildOfClass("Humanoid")
			if not (dummy and dummy:IsA("Model") and dummyRoot and dummyRoot:IsA("BasePart") and dummyHumanoid) then
				t:log("no DashTestDummy in Workspace: hit checks skipped")
				return
			end
			t.lantern:ResetForTest()
			t:teleport(dummyRoot.Position + Vector3.new(0, 1, 24), -Vector3.zAxis)
			local hp0 = dummyHumanoid.Health
			aim(t, dummyRoot.Position - t.lantern:GetPosition())
			t.lantern:SetAimForTest(dummyRoot.Position)
			holdCtrl(t, Config.LanternChargeTime)
			t:release("Race")
			local strong = t.lantern:GetLastThrowSpeed()
			t:waitFor(function()
				return t.lantern:GetTagTarget() ~= nil
			end, 1.5)
			local tagged = t.lantern:GetTagTarget()
			t:near("full charge throws at LanternThrowSpeedMax", strong, Config.LanternThrowSpeedMax, 3)
			t:check("a hit tags them and deals LanternDamage", tagged == dummy and math.abs((hp0 - dummyHumanoid.Health) - Config.LanternDamage) < 0.01,
				string.format("health %.0f -> %.0f", hp0, dummyHumanoid.Health))
			t.stamina:Set(t.stamina:GetMax())
			holdCtrl(t)
			local kind = t.lantern:GetFlight()
			t:waitFor(function()
				return t.lantern:GetFlight() == nil
			end, 2)
			t:release("Race")
			local gap = (dummyRoot.Position - t.root.Position).Magnitude
			t:check("hold while they're tagged flies you to them", kind == "Tag" and gap < Config.TagFlyStopDistance + 1.5,
				string.format("flight %s, %.1f studs from them", tostring(kind), gap))
			t.lantern:SetAimForTest(nil)
			t.lantern:ResetForTest()
		end,
	},
}

return {
	name = "Moth",
	description = "Paper wings, wing flight, lantern throw / suspend / flight / tag",
	tests = tests,
}
