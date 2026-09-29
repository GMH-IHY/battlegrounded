--!strict
-- RaceServer (Script)
-- Location: ServerScriptService > RaceServer
--
-- Gives every character its race until the loadout menu exists: the attribute "Race" (on the
-- player and on each character) is MovementConfig.DefaultRace. The client movement reads it (the
-- Moth's Left Ctrl flutter only works when Race is "Moth").
-- Moths also get their wings and antennae (MothParts, built from parts) and their lantern
-- (LanternServer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local movementFolder = ReplicatedStorage:WaitForChild("Movement")
movementFolder:WaitForChild("MovementConfig")
movementFolder:WaitForChild("MothParts")
local Config = require(ReplicatedStorage.Movement.MovementConfig)
local MothParts = require(ReplicatedStorage.Movement.MothParts)

local function onCharacter(player: Player, character: Model)
	local race = player:GetAttribute("Race")
	if typeof(race) ~= "string" then
		race = Config.DefaultRace
		player:SetAttribute("Race", race)
	end
	character:SetAttribute("Race", race)

	if race == "Moth" then
		character:WaitForChild("Torso", 5)
		character:WaitForChild("Head", 5)
		local ok, err = pcall(MothParts.Attach, character)
		if not ok then
			warn("[RaceServer] Couldn't attach the Moth wings: " .. tostring(err))
		end
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end
