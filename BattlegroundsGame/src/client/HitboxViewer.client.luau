--!strict
-- HitboxViewer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > HitboxViewer
--
-- Studio only. F5 shows the SERVER's attack hitboxes (the boxes that actually decide hits, with
-- their lag padding): red while the box touches someone, orange otherwise, each shown for a
-- few frames. It asks the server to broadcast them (CombatServer, "CombatShowHitboxes").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local CombatRemotes = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatRemotes"))

local TOGGLE_KEY = Enum.KeyCode.F5
local SHOW_TIME = 0.1

local remotes = CombatRemotes.Get()
local shown = false

local folder = Instance.new("Folder")
folder.Name = "HitboxViewer"
folder.Parent = Workspace

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= TOGGLE_KEY then
		return
	end
	shown = not shown
	remotes.Debug:InvokeServer("ShowHitboxes", shown)
	if not shown then
		folder:ClearAllChildren()
	end
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
