--!strict
-- StudioAnimationMirror (Script)
-- Location: ServerScriptService > StudioAnimationMirror
--
-- Studio only. Players can't see ServerStorage, where the Animation Editor saves animations,
-- so at the start of every playtest this copies the rig's saved KeyframeSequences into
-- ReplicatedStorage. Unpublished animations then play in playtests with your latest edits.
-- Does nothing on a live server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if not RunService:IsStudio() then
	return
end

ReplicatedStorage:WaitForChild("Movement"):WaitForChild("AnimationConfig")
local Config = require(ReplicatedStorage.Movement.AnimationConfig)

local folder = Instance.new("Folder")
folder.Name = Config.StudioAnimationsFolder

local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
local rigSaves = saves and saves:FindFirstChild(Config.StudioRigName)
if rigSaves then
	for _, child in rigSaves:GetChildren() do
		if child:IsA("KeyframeSequence") then
			child:Clone().Parent = folder
		end
	end
else
	warn(`[StudioAnimationMirror] ServerStorage > RBX_ANIMSAVES > {Config.StudioRigName} not found.`)
end

folder.Parent = ReplicatedStorage
