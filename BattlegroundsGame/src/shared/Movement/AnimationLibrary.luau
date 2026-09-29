--!strict
-- AnimationLibrary (ModuleScript)
-- Location: ReplicatedStorage > Movement > AnimationLibrary
--
-- Turns an animation name into an Animation object. Uses the published ID from
-- AnimationConfig when there is one; otherwise, in Studio only, registers the KeyframeSequence
-- of that name (copied into ReplicatedStorage by StudioAnimationMirror) as a temporary ID.

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

local function normalize(id: string): string
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

local function studioId(name: string): string?
	local folder = ReplicatedStorage:WaitForChild(Config.StudioAnimationsFolder, 10)
	if not folder then
		warnOnce(name, "No published ID for " .. name .. " and the Studio animation copies never arrived.")
		return nil
	end
	local sequence = folder:FindFirstChild(name)
	if not sequence or not sequence:IsA("KeyframeSequence") then
		warnOnce(
			name,
			`No published ID for {name}, and no KeyframeSequence named {name} in ServerStorage > RBX_ANIMSAVES > {Config.StudioRigName}.`
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

-- Returns the Animation for `name`, or nil (with a warning) if it isn't available.
function AnimationLibrary.Get(name: string): Animation?
	local cached = cache[name]
	if cached then
		return cached
	end

	local id = Config.Ids[name]
	local animationId: string?
	if id and id ~= "" then
		animationId = normalize(id)
	elseif RunService:IsStudio() then
		animationId = studioId(name)
	else
		warnOnce(name, `No published ID for {name}. Fill it in in AnimationConfig.`)
	end
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
