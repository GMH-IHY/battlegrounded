--!strict
-- FxPieces (ModuleScript)
-- Location: ReplicatedStorage > Combat > FxPieces
--
-- Stepped effect parts for client effect scripts (LotusFx): a part goes through a list of steps
-- (CFrame / size / transparency), one per FX step (Rate per second), then disappears. Nothing
-- tweens: every change is a snap, like the animations (docs/art/ArtDirection.md). Parts are pooled.
--   FxPieces.Piece(color, steps, neon?, shape?)   start one; returns a handle
--   FxPieces.Stop(handle)                          end it at the next step
--   FxPieces.Rate                                   steps per second

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Step = { cframe: CFrame?, size: Vector3?, transparency: number? }

type Piece = { part: Part, steps: { Step }, index: number }
export type Handle = Piece

local FxPieces = {}
FxPieces.Rate = 20

local folder: Folder? = nil
local pool: { Part } = {}
local pieces: { Piece } = {}

local function holder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "FxPieces"
	created.Parent = Workspace
	folder = created
	return created
end

local function take(): Part
	local part = table.remove(pool)
	if part then
		return part
	end
	local fresh = Instance.new("Part")
	fresh.Anchored = true
	fresh.CanCollide = false
	fresh.CanQuery = false
	fresh.CanTouch = false
	fresh.CastShadow = false
	fresh.TopSurface = Enum.SurfaceType.Smooth
	fresh.BottomSurface = Enum.SurfaceType.Smooth
	return fresh
end

function FxPieces.Piece(color: Color3, steps: { Step }, neon: boolean?, shape: Enum.PartType?): Handle?
	if #steps == 0 then
		return nil
	end
	local part = take()
	part.Shape = shape or Enum.PartType.Block
	part.Color = color
	part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local first = steps[1]
	part.CFrame = first.cframe or CFrame.identity
	part.Size = first.size or Vector3.one
	part.Transparency = first.transparency or 0
	part.Parent = holder()
	local piece = { part = part, steps = steps, index = 1 }
	table.insert(pieces, piece)
	return piece
end

function FxPieces.Stop(handle: Handle)
	handle.index = #handle.steps
end

local function step()
	for i = #pieces, 1, -1 do
		local p = pieces[i]
		p.index += 1
		local s = p.steps[p.index]
		if not s then
			p.part.Parent = nil
			table.insert(pool, p.part)
			table.remove(pieces, i)
		else
			if s.cframe then
				p.part.CFrame = s.cframe
			end
			if s.size then
				p.part.Size = s.size
			end
			if s.transparency then
				p.part.Transparency = s.transparency
			end
		end
	end
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	local interval = 1 / FxPieces.Rate
	if accumulator >= interval then
		accumulator %= interval
		step()
	end
end)

return FxPieces
