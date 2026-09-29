--!strict
-- LanternFx (ModuleScript)
-- Location: ReplicatedStorage > Movement > LanternFx
--
-- Client-side lantern visuals shared by the owner (Lantern.luau) and everyone else (LanternViewer):
-- a smooth local copy of a server lantern, its light sphere, and the impact burst.
-- The server lantern is never moved from the client (moving it while it's still welded to the
-- character drags the character with it); it's only hidden with LocalTransparencyModifier.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.MovementConfig)

local LanternFx = {}

LanternFx.GLOW = Color3.fromRGB(120, 240, 255)
LanternFx.CORE_OFF = Color3.fromRGB(46, 110, 118)

-- Hides / shows a server lantern (and its light sphere) on this client only.
function LanternFx.hideServer(model: Model, hidden: boolean)
	local value = if hidden then 1 else 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = value
		end
	end
	local ref = model:FindFirstChild("LightSphereRef")
	if ref and ref:IsA("ObjectValue") and ref.Value and ref.Value:IsA("BasePart") then
		ref.Value.LocalTransparencyModifier = value
	end
end

-- A local, anchored copy of a server lantern (no welds, not queryable) plus its own light sphere.
function LanternFx.makeCopy(model: Model, name: string): Model
	local copy = Instance.new("Model")
	copy.Name = name
	local core = model.PrimaryPart
	local coreCopy: BasePart? = nil
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local p = d:Clone()
			for _, j in p:GetChildren() do
				if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("Constraint") then
					j:Destroy()
				end
			end
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 0
			p.LocalTransparencyModifier = 0
			if core then
				-- Keep the pieces where they are relative to the core.
				p:SetAttribute("Offset", core.CFrame:ToObjectSpace(d.CFrame))
			end
			p.Parent = copy
			if d == core then
				coreCopy = p
			end
		end
	end
	if coreCopy then
		copy.PrimaryPart = coreCopy
	end
	local sphere = Instance.new("Part")
	sphere.Name = "LightSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.one * Config.LanternLightRadius * 2
	sphere.Color = LanternFx.GLOW
	sphere.Material = Enum.Material.ForceField
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Transparency = 1
	sphere.Parent = copy
	copy.Parent = Workspace
	return copy
end

-- Places a copy: `cf` for the core; the other pieces keep their offsets; the sphere is centred.
function LanternFx.placeCopy(copy: Model, cf: CFrame)
	for _, p in copy:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "LightSphere" then
				p.CFrame = CFrame.new(cf.Position)
			else
				local offset = p:GetAttribute("Offset")
				p.CFrame = if typeof(offset) == "CFrame" then cf * offset else cf
			end
		end
	end
end

-- Lit (glowing core) while thrown or hanging; the light sphere only while hanging.
function LanternFx.styleCopy(copy: Model, state: string)
	local lit = state == "Thrown" or state == "Suspended"
	local core = copy.PrimaryPart
	if core then
		core.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		core.Color = if lit then LanternFx.GLOW else LanternFx.CORE_OFF
	end
	local sphere = copy:FindFirstChild("LightSphere")
	if sphere and sphere:IsA("BasePart") then
		sphere.Transparency = if state == "Suspended" then 0.82 else 1
	end
end

-- The orientation for a copy at `position`: upright when still, nose along `velocity` while flying.
function LanternFx.pose(position: Vector3, velocity: Vector3?, flying: boolean): CFrame
	if flying and velocity and velocity.Magnitude > 1 then
		local look = velocity.Unit
		local up = if math.abs(look.Y) > 0.95 then Vector3.zAxis else Vector3.yAxis
		return CFrame.lookAt(position, position + look, up)
	end
	return CFrame.new(position)
end

-- The impact burst: a quick flash of the lantern's light (radius = LanternBurstRadius).
function LanternFx.burst(position: Vector3)
	local radius = Config.LanternBurstRadius
	local flash = Instance.new("Part")
	flash.Name = "LanternBurst"
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = LanternFx.GLOW
	flash.Size = Vector3.one
	flash.CFrame = CFrame.new(position)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Transparency = 0.3
	local light = Instance.new("PointLight")
	light.Color = LanternFx.GLOW
	light.Range = radius * 1.5
	light.Brightness = 4
	light.Parent = flash
	flash.Parent = Workspace.CurrentCamera or Workspace
	local duration = 0.3
	local start = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		flash.Size = Vector3.one * (radius * 2 * (0.3 + 0.7 * t))
		flash.Transparency = 0.3 + 0.7 * t
		light.Brightness = 4 * (1 - t)
		if t >= 1 then
			flash:Destroy()
			if connection then
				connection:Disconnect()
			end
		end
	end)
end

return LanternFx
