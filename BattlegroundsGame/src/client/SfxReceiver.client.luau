--!strict
-- SfxReceiver (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > SfxReceiver
--
-- Plays the movement sounds OTHER players' clients reported (SfxServer passes them on) on their
-- characters. Your own sounds are played directly by your movement code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local movement = ReplicatedStorage:WaitForChild("Movement")
movement:WaitForChild("Sfx")
local Sfx = require(ReplicatedStorage.Movement.Sfx)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local oneShot = remotes:WaitForChild("MovementSfx") :: UnreliableRemoteEvent
local loop = remotes:WaitForChild("MovementSfxLoop") :: RemoteEvent

oneShot.OnClientEvent:Connect(function(character: Model?, name: string, speed: number, volume: number, at: Vector3?)
	if character and character.Parent then
		Sfx.PlayRemote(character, name, speed, volume, at)
	end
end)

loop.OnClientEvent:Connect(function(character: Model?, name: string, on: boolean, speed: number, volume: number, target: string?)
	if character and character.Parent then
		Sfx.LoopRemote(character, name, on, speed, volume, target)
	end
end)
