--!strict
-- MothParts: rigs the imported Moth race meshes (MothRace.glb) onto an R6 character.
-- Setup: Studio > Import 3D > MothRace.glb, then move the imported model into ReplicatedStorage and name it "MothRace".
-- Use on the SERVER:  require(path.MothParts).Attach(character)
--
-- Joints (for the Animation Editor):
--   Torso > RightForewing / LeftForewing / RightHindwing / LeftHindwing / Collar   (Motor6D, pivots at the wing roots)
--   Head  > RightAntenna / LeftAntenna                                          (Motor6D, pivots at the antenna roots)
--   Each "...Glow" mesh (Neon) is welded to its wing / antenna.
-- Motor axes: wings rotate in the wing's own frame (X = out along the wing, Y = up the wing, Z = wing normal),
-- so rotating around Y flaps and around Z raises / lowers.
--
-- The 3D Importer may change axes or units, so Attach compares where the importer put each mesh with where it was
-- modelled, finds the importer's rotation (any of the 24 axis-aligned ones) and scale, and undoes them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HEAD_OFFSET = CFrame.new(0, -1.5, 0) -- torso-local -> head-local (R6)
local GLOW_COLOR = Color3.fromRGB(41, 223, 235)

type Piece = {
	Name: string,
	Center: Vector3, -- bounding-box centre as modelled (torso-local studs)
	Size: Vector3, -- bounding-box size in studs
	Attach: string, -- "Torso" / "Head" / another piece's name (welds)
	Joint: string, -- "Motor6D" / "Weld"
	Hinge: CFrame?, -- joint pivot + axes (torso-local)
	Glow: boolean?,
}

local PIECES: { Piece } = {
	{ Name = "RightForewing", Center = Vector3.new(2.0988, 1.3898, 1.3669), Size = Vector3.new(3.9414, 3.0449, 1.7010), Attach = "Torso", Joint = "Motor6D", Hinge = CFrame.new(0.25000, 0.45000, 0.62000, 0.92493, -0.06468, -0.37461, 0.06976, 0.99756, 0.00000, 0.37369, -0.02613, 0.92718) },
	{ Name = "RightForewingGlow", Center = Vector3.new(2.8644, 1.6997, 1.6763), Size = Vector3.new(0.7566, 0.7981, 0.4919), Attach = "RightForewing", Joint = "Weld", Glow = true },
	{ Name = "LeftForewing", Center = Vector3.new(-2.0988, 1.3898, 1.3669), Size = Vector3.new(3.9414, 3.0449, 1.7010), Attach = "Torso", Joint = "Motor6D", Hinge = CFrame.new(-0.25000, 0.45000, 0.62000, 0.92493, 0.06468, 0.37461, -0.06976, 0.99756, 0.00000, -0.37369, -0.02613, 0.92718) },
	{ Name = "LeftForewingGlow", Center = Vector3.new(-2.8644, 1.6997, 1.6763), Size = Vector3.new(0.7566, 0.7981, 0.4919), Attach = "LeftForewing", Joint = "Weld", Glow = true },
	{ Name = "RightHindwing", Center = Vector3.new(1.4464, -1.4246, 1.3508), Size = Vector3.new(2.5578, 2.6984, 1.5576), Attach = "Torso", Joint = "Motor6D", Hinge = CFrame.new(0.25000, -0.20000, 0.66000, 0.86128, 0.09052, -0.50000, -0.10453, 0.99452, 0.00000, 0.49726, 0.05226, 0.86603) },
	{ Name = "RightHindwingGlow", Center = Vector3.new(1.6010, -1.6209, 1.4400), Size = Vector3.new(0.7846, 0.8354, 0.5915), Attach = "RightHindwing", Joint = "Weld", Glow = true },
	{ Name = "LeftHindwing", Center = Vector3.new(-1.4464, -1.4246, 1.3508), Size = Vector3.new(2.5578, 2.6984, 1.5576), Attach = "Torso", Joint = "Motor6D", Hinge = CFrame.new(-0.25000, -0.20000, 0.66000, 0.86128, -0.09052, 0.50000, 0.10453, 0.99452, 0.00000, -0.49726, 0.05226, 0.86603) },
	{ Name = "LeftHindwingGlow", Center = Vector3.new(-1.6010, -1.6209, 1.4400), Size = Vector3.new(0.7846, 0.8354, 0.5915), Attach = "LeftHindwing", Joint = "Weld", Glow = true },
	{ Name = "RightAntenna", Center = Vector3.new(0.7583, 2.8561, -0.1200), Size = Vector3.new(1.0433, 1.7416, 0.2895), Attach = "Head", Joint = "Motor6D", Hinge = CFrame.new(0.30000, 2.00000, -0.20000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000) },
	{ Name = "RightAntennaGlow", Center = Vector3.new(1.1100, 3.7600, -0.0200), Size = Vector3.new(0.3000, 0.3600, 0.3000), Attach = "RightAntenna", Joint = "Weld", Glow = true },
	{ Name = "LeftAntenna", Center = Vector3.new(-0.7583, 2.8561, -0.1200), Size = Vector3.new(1.0433, 1.7416, 0.2895), Attach = "Head", Joint = "Motor6D", Hinge = CFrame.new(-0.30000, 2.00000, -0.20000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000, 0.00000, 0.00000, 0.00000, 1.00000) },
	{ Name = "LeftAntennaGlow", Center = Vector3.new(-1.1100, 3.7600, -0.0200), Size = Vector3.new(0.3000, 0.3600, 0.3000), Attach = "LeftAntenna", Joint = "Weld", Glow = true },
}

local MothParts = {}

local function rotations(): { CFrame }
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis, -Vector3.xAxis, -Vector3.yAxis, -Vector3.zAxis }
	local out = {}
	for _, x in axes do
		for _, y in axes do
			if math.abs(x:Dot(y)) < 0.5 then
				table.insert(out, CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y)))
			end
		end
	end
	return out -- 24 proper rotations
end

-- Finds the importer transform: imported = cI + s * R * (modelled - cM)
local function fitImport(parts: { [string]: BasePart })
	local mine, imp = {}, {}
	for _, piece in PIECES do
		local part = parts[piece.Name]
		if part then
			table.insert(mine, piece.Center)
			table.insert(imp, part.Position)
		end
	end
	assert(#mine >= 3, "MothParts: fewer than 3 meshes found in ReplicatedStorage.MothRace")
	local cM, cI = Vector3.zero, Vector3.zero
	for i = 1, #mine do
		cM += mine[i]
		cI += imp[i]
	end
	cM /= #mine
	cI /= #imp
	local sm, si = 0, 0
	for i = 1, #mine do
		sm += (mine[i] - cM).Magnitude ^ 2
		si += (imp[i] - cI).Magnitude ^ 2
	end
	local s = math.sqrt(si / sm)
	local best, bestErr = CFrame.identity, math.huge
	for _, r in rotations() do
		local err = 0
		for i = 1, #mine do
			err += ((imp[i] - cI) - r:VectorToWorldSpace(mine[i] - cM) * s).Magnitude ^ 2
		end
		if err < bestErr then
			best, bestErr = r, err
		end
	end
	return cM, cI, s, best
end

local function source(): Instance
	local model = ReplicatedStorage:FindFirstChild("MothRace")
	assert(model, "MothParts: import MothRace.glb and put the model in ReplicatedStorage as \"MothRace\"")
	return model
end

function MothParts.Detach(character: Model)
	local old = character:FindFirstChild("MothRace")
	if old then
		old:Destroy()
	end
end

function MothParts.Attach(character: Model): Folder
	MothParts.Detach(character)
	local src = source():Clone()
	-- the importer may wrap each mesh in its own Model with the same name, so look for the part itself
	local byName: { [string]: BasePart } = {}
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") and not byName[d.Name] then
			byName[d.Name] = d
		end
	end
	local parts: { [string]: BasePart } = {}
	for _, piece in PIECES do
		local p = byName[piece.Name]
		if p then
			parts[piece.Name] = p
		else
			warn("MothParts: missing mesh " .. piece.Name)
		end
	end
	local cM, cI, s, r = fitImport(parts)
	local rInv = r:Inverse()

	-- each mesh's own frame, expressed in modelled (torso-local) coordinates
	local frames: { [string]: CFrame } = {}
	for name, part in parts do
		local pos = cM + rInv:VectorToWorldSpace((part.Position - cI) / s)
		frames[name] = CFrame.new(pos) * (rInv * part.CFrame.Rotation)
		part.Size /= s
	end

	local folder = Instance.new("Folder")
	folder.Name = "MothRace"
	for _, piece in PIECES do
		local part = parts[piece.Name]
		if not part then
			continue
		end
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		if piece.Glow then
			part.Material = Enum.Material.Neon
			part.Color = GLOW_COLOR
			if part:IsA("MeshPart") then
				part.TextureID = ""
			end
			local sa = part:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
		end
		local frame = frames[piece.Name]
		if piece.Joint == "Motor6D" then
			local target = character:FindFirstChild(piece.Attach)
			assert(target and target:IsA("BasePart"), "MothParts: character has no " .. piece.Attach)
			local hinge = piece.Hinge :: CFrame
			local motor = Instance.new("Motor6D")
			motor.Name = piece.Name
			motor.C0 = if piece.Attach == "Head" then HEAD_OFFSET * hinge else hinge
			motor.C1 = frame:Inverse() * hinge
			motor.Part0 = target
			motor.Part1 = part
			motor.Parent = target
		else
			local owner = parts[piece.Attach]
			local weld = Instance.new("Weld")
			weld.Name = piece.Name .. "Weld"
			weld.Part0 = owner
			weld.Part1 = part
			weld.C0 = frames[piece.Attach]:Inverse() * frame
			weld.Parent = part
		end
		part.Parent = folder
	end
	src:Destroy()
	folder.Parent = character
	return folder
end

return MothParts
