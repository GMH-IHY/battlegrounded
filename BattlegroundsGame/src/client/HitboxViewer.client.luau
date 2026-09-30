--!strict
-- HitboxViewer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > HitboxViewer
--
-- Studio only. Settings menu (gear) > Debug > Hitbox view shows the SERVER's attack hitboxes (the boxes that actually decide hits, with
-- their lag padding): red while the box touches someone, orange otherwise, each shown for a
-- few frames. It asks the server to broadcast them (CombatServer, "CombatShowHitboxes").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))
local CombatRemotes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatRemotes"))

local SHOW_TIME = 0.1

local remotes = CombatRemotes.Get()
local shown = false

local folder = Instance.new("Folder")
folder.Name = "HitboxViewer"
folder.Parent = Workspace

SettingsMenu.AddToggle("Debug", "Hitbox view (server)", false, function(on: boolean)
	shown = on
	if not shown then
		folder:ClearAllChildren()
	end
	remotes.Debug:InvokeServer("ShowHitboxes", shown)
end)

remotes.Fx.OnClientEvent:Connect(function(info: { [string]: any })
	if not shown or info.type ~= "Hitbox" or typeof(info.cframe) ~= "CFrame" or typeof(info.size) ~= "Vector3" then
		return
	end
	local box = Instance.new("Part")
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Material = Enum.Material.ForceField
	box.Color = if info.hit then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(255, 150, 40)
	box.Transparency = 0.3
	box.CFrame = info.cframe
	box.Size = info.size
	box.Parent = folder
	task.delay(SHOW_TIME, function()
		box:Destroy()
	end)
end)
