--!strict
-- CollisionGroups (Script)
-- Location: ServerScriptService > CollisionGroups
--
-- Registers the collision groups movement code uses. Groups can only be registered on the
-- server; clients then put their own character's parts in them.
--   ParkourSlideBody: the normal body parts while sliding (AutoParkour). Collides with nothing;
--   the character's low SlideCollider does the colliding instead.

local PhysicsService = game:GetService("PhysicsService")

local SLIDE_GROUP = "ParkourSlideBody"

if not PhysicsService:IsCollisionGroupRegistered(SLIDE_GROUP) then
	PhysicsService:RegisterCollisionGroup(SLIDE_GROUP)
end
for _, group in PhysicsService:GetRegisteredCollisionGroups() do
	PhysicsService:CollisionGroupSetCollidable(SLIDE_GROUP, group.name, false)
end
