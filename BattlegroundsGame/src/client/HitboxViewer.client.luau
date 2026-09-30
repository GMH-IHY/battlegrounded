--!strict
-- HitboxViewer (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > HitboxViewer
--
-- Studio only. Settings menu (gear) > Debug > Hitbox view shows attack hitboxes:
--   blue    YOUR move's hitbox on its active frames, drawn at once from the move data (what your
--           client expects; no waiting for the server)
--   orange  the SERVER's hitbox (the one that decides hits, with its lag padding) and projectiles
--   red     a server hitbox that touched someone
-- Each server box stays up for SHOW_TIME so even a 2-frame hit is easy to see. The server only
-- sends its boxes while the view is on (CombatServer, "CombatShowHitboxes").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatRemotes = require(Combat:WaitForChild("CombatRemotes"))
local Moves = require(Combat:WaitForChild("Moves"))
local SettingsMenu = require(script.Parent:WaitForChild("SettingsMenu"))

local SHOW_TIME = 0.3
local SERVER_COLOR = Color3.fromRGB(255, 150, 40)
local HIT_COLOR = Color3.fromRGB(255, 40, 40)
local LOCAL_COLOR = Color3.fromRGB(60, 150, 255)

local player = Players.LocalPlayer
local remotes = CombatRemotes.Get()
local shown = false

local folder = Instance.new("Folder")
folder.Name = "HitboxViewer"
folder.Parent = Workspace

local function box(color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = transparency
	local outline = Instance.new("SelectionBox")
	outline.Adornee = part
	outline.Color3 = color
	outline.LineThickness = 0.04
	outline.SurfaceTransparency = 1
	outline.Parent = part
	return part
end

-- Your own move's hitbox, following you on its active frames.
local localBox = box(LOCAL_COLOR, 0.7)
localBox.Name = "LocalHitbox"

RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local value = character and character:GetAttribute("LocalMove")
	local id = if typeof(value) == "string" then string.match(value, "^([^#]+)") else nil
	local move = if id then Moves.Get(id) else nil
	local visible = shown and character ~= nil and root ~= nil and root:IsA("BasePart") and move ~= nil
		and move.Projectile == nil and not move.Targeted and move.OnHit.Kind ~= "None"
		and character:GetAttribute("AttackPhase") == "Active"
	if visible and move and root and root:IsA("BasePart") then
		localBox.Size = move.Hitbox.Size
		localBox.CFrame = Moves.HitboxCFrame(move, root.CFrame)
		localBox.Parent = folder
	else
		localBox.Parent = nil
	end
end)

SettingsMenu.AddToggle("Debug", "Hitbox view", false, function(on: boolean)
	shown = on
	if not shown then
		folder:ClearAllChildren()
		localBox.Parent = nil
	end
	remotes.Debug:InvokeServer("ShowHitboxes", shown)
end)

remotes.Fx.OnClientEvent:Connect(function(info: { [string]: any })
	if not shown or info.type ~= "Hitbox" or typeof(info.cframe) ~= "CFrame" or typeof(info.size) ~= "Vector3" then
		return
	end
	local part = box(if info.hit then HIT_COLOR else SERVER_COLOR, if info.hit then 0.45 else 0.75)
	part.CFrame = info.cframe
	part.Size = info.size
	part.Parent = folder
	task.delay(SHOW_TIME, function()
		part:Destroy()
	end)
end)
