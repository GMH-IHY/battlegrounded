--!strict
-- CollisionGroups (Script)
-- Location: ServerScriptService > CollisionGroups
--
-- Registers the collision groups movement and combat use. Groups can only be registered on the
-- server; clients then put their own character's parts in them.
--   Fighters: every character's body (players and training dummies; CombatServer and CombatClient
--   put the parts in it). Fighters don't collide with each other, so you can walk and lunge
--   through people (the lunge can get behind a block); they still collide with the world.
--   ParkourSlideBody: the normal body parts while sliding (AutoParkour). Collides with nothing;
--   the character's low SlideCollider does the colliding instead.

local PhysicsService = game:GetService("PhysicsService")

local FIGHTERS = "Fighters"
local SLIDE_GROUP = "ParkourSlideBody"

if not PhysicsService:IsCollisionGroupRegistered(FIGHTERS) then
	PhysicsService:RegisterCollisionGroup(FIGHTERS)
end
PhysicsService:CollisionGroupSetCollidable(FIGHTERS, FIGHTERS, false)

if not PhysicsService:IsCollisionGroupRegistered(SLIDE_GROUP) then
	PhysicsService:RegisterCollisionGroup(SLIDE_GROUP)
end
for _, group in PhysicsService:GetRegisteredCollisionGroups() do
	PhysicsService:CollisionGroupSetCollidable(SLIDE_GROUP, group.name, false)
end
