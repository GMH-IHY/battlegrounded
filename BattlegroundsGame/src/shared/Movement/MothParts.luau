--!strict
-- MothParts (ModuleScript)
-- Location: ReplicatedStorage > Movement > MothParts
--
-- Builds the Moth race's wings and antennae out of parts (data: MothPartsData) and rigs them onto
-- an R6 character. Call on the SERVER so everyone sees them:  MothParts.Attach(character)
--
-- Each wing / antenna is an invisible bone on a Motor6D, so animations move them like limbs:
--   Torso > RightForewing / LeftForewing / RightHindwing / LeftHindwing
--   Head  > RightAntenna / LeftAntenna
-- Wing bones use the wing's own frame: rotating around Y swings the wing (+ forward, - folds it
-- back), around Z raises / lowers the tip. The left side is mirrored (same numbers, opposite sign).
-- All pieces are massless and never collide, so they don't change movement or hitboxes.

local Data = require(script.Parent.MothPartsData)

local MothParts = {}

local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function quiet(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

function MothParts.Detach(character: Model)
	local old = character:FindFirstChild("MothWings")
	if old then
		old:Destroy()
	end
	for _, joint in Data.Joints do
		for _, parentName in { "Torso", "Head" } do
			local parent = character:FindFirstChild(parentName)
			local motor = parent and parent:FindFirstChild(joint.Name)
			if motor and motor:IsA("Motor6D") then
				motor:Destroy()
			end
		end
	end
end

function MothParts.Attach(character: Model): Model
	MothParts.Detach(character)
	local model = Instance.new("Model")
	model.Name = "MothWings"

	local bones: { [string]: BasePart } = {}
	for _, joint in Data.Joints do
		local part0 = character:FindFirstChild(joint.Part0)
		assert(part0 and part0:IsA("BasePart"), "MothParts: character has no " .. joint.Part0)
		local bone = Instance.new("Part")
		bone.Name = joint.Name
		bone.Size = Vector3.new(0.2, 0.2, 0.2)
		bone.Transparency = 1
		quiet(bone)
		bone.CFrame = part0.CFrame * joint.C0
		bone.Parent = model
		local motor = Instance.new("Motor6D")
		motor.Name = joint.Name
		motor.Part0 = part0
		motor.Part1 = bone
		motor.C0 = joint.C0
		motor.Parent = part0 -- like the other R6 joints, so the Animator finds it
		bones[joint.Name] = bone
	end

	for _, spec in Data.Parts do
		local bone = bones[spec.Bone]
		local part: BasePart
		if spec.Class == "WedgePart" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			p.Shape = SHAPES[spec.Shape] or Enum.PartType.Block
			part = p
		end
		part.Name = spec.Name
		part.Size = spec.Size
		part.Color = spec.Color
		part.Material = spec.Material
		quiet(part)
		if spec.Texture ~= "" then
			-- The paper image on both faces of a wing plate, stretched once across it.
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local texture = Instance.new("Texture")
				texture.Texture = spec.Texture
				texture.Face = face
				texture.StudsPerTileU = spec.Size.X
				texture.StudsPerTileV = spec.Size.Y
				texture.Parent = part
			end
		end
		part.CFrame = bone.CFrame * spec.CFrame
		local weld = Instance.new("Weld")
		weld.Part0 = bone
		weld.Part1 = part
		weld.C0 = spec.CFrame
		weld.Parent = part
		part.Parent = model
	end

	model.Parent = character
	return model
end

return MothParts
