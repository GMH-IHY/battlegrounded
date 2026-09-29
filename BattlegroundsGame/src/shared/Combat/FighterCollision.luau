--!strict
-- FighterCollision (ModuleScript)
-- Location: ReplicatedStorage > Combat > FighterCollision
--
-- Puts every part of a character in the "Fighters" collision group (registered by the
-- CollisionGroups script): fighters pass through each other but not through the world. Parts
-- added later (colliders movement creates) join too. A part another system moved to its own group
-- (the parkour slide) is left alone.

local PhysicsService = game:GetService("PhysicsService")

local GROUP = "Fighters"

local FighterCollision = {}

local function join(part: Instance)
	if part:IsA("BasePart") and part.CollisionGroup == "Default" then
		part.CollisionGroup = GROUP
	end
end

function FighterCollision.Apply(character: Model)
	local ok, registered = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(GROUP)
	end)
	if not (ok and registered) then
		return
	end
	for _, descendant in character:GetDescendants() do
		join(descendant)
	end
	character.DescendantAdded:Connect(join)
end

return FighterCollision
