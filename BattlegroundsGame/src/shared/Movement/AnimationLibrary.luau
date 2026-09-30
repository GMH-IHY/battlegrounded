--!strict
-- AnimationLibrary (ModuleScript)
-- Location: ReplicatedStorage > Movement > AnimationLibrary
--
-- Turns an animation name into an Animation object. Animations are local for now (nothing is
-- published): it registers the KeyframeSequence of that name (copied into ReplicatedStorage by
-- StudioAnimationMirror) as a temporary ID. That only works in Studio.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.AnimationConfig)

local AnimationLibrary = {}

local cache: { [string]: Animation } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(name: string, message: string)
	if not warned[name] then
		warned[name] = true
		warn("[AnimationLibrary] " .. message)
	end
end

local function studioId(name: string): string?
	local folder = ReplicatedStorage:WaitForChild(Config.StudioAnimationsFolder, 10)
	if not folder then
		warnOnce(name, "The local animation copies never arrived (StudioAnimationMirror), so " .. name .. " can't play.")
		return nil
	end
	local sequence = folder:FindFirstChild(name)
	if not sequence or not sequence:IsA("KeyframeSequence") then
		warnOnce(
			name,
			`No KeyframeSequence named {name} in ServerStorage > RBX_ANIMSAVES > {Config.StudioRigName} (run tools/animations/build.py).`
		)
		return nil
	end
	local ok, result = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)
	if not ok then
		warnOnce(name, `Couldn't register the Studio copy of {name}: {result}`)
		return nil
	end
	return result
end

-- True if `name` can play here (its local copy is there).
function AnimationLibrary.Exists(name: string): boolean
	if cache[name] then
		return true
	end
	if not RunService:IsStudio() then
		return false
	end
	local folder = ReplicatedStorage:FindFirstChild(Config.StudioAnimationsFolder)
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

-- Returns the Animation for `name`, or nil (with a warning) if it isn't available.
function AnimationLibrary.Get(name: string): Animation?
	local cached = cache[name]
	if cached then
		return cached
	end
	if not RunService:IsStudio() then
		warnOnce("live", "Animations are local (Studio only) for now: nothing plays on a live server.")
		return nil
	end
	local animationId = studioId(name)
	if not animationId then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	cache[name] = animation
	return animation
end

return AnimationLibrary
