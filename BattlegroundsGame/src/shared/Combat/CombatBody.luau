--!strict
-- CombatBody (ModuleScript)
-- Location: ReplicatedStorage > Combat > CombatBody
--
-- Moves a character's body for combat: pushback, knockback, launches, hanging in the air, an
-- attacker's step and lunge, the tech roll. It must run where the character's physics is owned:
-- the player's own client (CombatClient) or the server for a training dummy.
--
--   body:Push(velocity, duration, decay?)  hold a flat velocity for `duration` seconds (gravity
--                                          still acts); decay = it slows to 0 over the time
--   body:Hang(duration, velocity?)         hold the whole velocity (default: still, so you float)
--   body:Launch(velocity)                  throw the body (gravity takes over at once)
--   body:Face(direction?)                  hold the facing (nil lets go)
--   body:Release()                         stop everything now
--
-- While it holds the body, the CharacterMotor (if any) is suspended under its own key and the
-- Humanoid doesn't auto-rotate. When it lets go the motor picks up the body's velocity.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterMotor = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("CharacterMotor"))

local SUSPEND_KEY = "Combat"

type Mode = "None" | "Plane" | "Vector"

local CombatBody = {}
CombatBody.__index = CombatBody

type Data = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	motor: CharacterMotor.CharacterMotor?,
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	connection: RBXScriptConnection?,
	mode: Mode,
	target: Vector3,
	startedAt: number,
	endsAt: number,
	decay: boolean,
	facing: boolean,
	destroyed: boolean,
}

export type CombatBody = typeof(setmetatable({} :: Data, CombatBody))

function CombatBody.new(character: Model, motor: CharacterMotor.CharacterMotor?): CombatBody
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatBodyAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CombatVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = math.huge
	velocity.Enabled = false
	velocity.Parent = root

	local align = Instance.new("AlignOrientation")
	align.Name = "CombatFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		root = root,
		motor = motor,
		attachment = attachment,
		velocity = velocity,
		align = align,
		connection = nil,
		mode = "None" :: Mode,
		target = Vector3.zero,
		startedAt = 0,
		endsAt = 0,
		decay = false,
		facing = false,
		destroyed = false,
	} :: Data, CombatBody)
	self.connection = RunService.PreSimulation:Connect(function()
		self:_step()
	end)
	return self
end

function CombatBody.IsActive(self: CombatBody): boolean
	return self.mode ~= "None"
end

function CombatBody._take(self: CombatBody)
	if self.motor then
		self.motor:Suspend(SUSPEND_KEY)
	end
	self.humanoid.AutoRotate = false
end

function CombatBody._letGo(self: CombatBody)
	if self.motor then
		self.motor:ApplyMomentum(self.root.AssemblyLinearVelocity)
		self.motor:Resume(SUSPEND_KEY)
	end
	if not self.facing then
		self.humanoid.AutoRotate = true
	end
end

function CombatBody.Push(self: CombatBody, flat: Vector3, duration: number, decay: boolean?)
	flat = Vector3.new(flat.X, 0, flat.Z)
	self.mode = "Plane"
	self.target = flat
	self.decay = decay == true
	self.startedAt = os.clock()
	self.endsAt = self.startedAt + duration
	self.velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	self.velocity.PrimaryTangentAxis = Vector3.xAxis
	self.velocity.SecondaryTangentAxis = Vector3.zAxis
	self.velocity.PlaneVelocity = Vector2.new(flat.X, flat.Z)
	self.velocity.Enabled = true
	self:_take()
end

function CombatBody.Hang(self: CombatBody, duration: number, velocity: Vector3?)
	local v = velocity or Vector3.zero
	self.mode = "Vector"
	self.target = v
	self.decay = false
	self.startedAt = os.clock()
	self.endsAt = self.startedAt + duration
	self.velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	self.velocity.VectorVelocity = v
	self.velocity.Enabled = true
	self.root.AssemblyLinearVelocity = v
	self:_take()
end

-- Throws the body: the flat part is held for `hold` seconds (so the Humanoid's ground friction
-- can't eat it on the first frames), the vertical part is left to gravity.
function CombatBody.Launch(self: CombatBody, velocity: Vector3, hold: number?)
	if self.motor then
		self.motor:AllowLaunch(1.5)
	end
	-- Off the floor first, or the Humanoid's floor snap swallows the upward speed.
	if velocity.Y > 0 then
		self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	self.root.AssemblyLinearVelocity = velocity
	self:Push(Vector3.new(velocity.X, 0, velocity.Z), hold or 0.1)
end

function CombatBody.Face(self: CombatBody, direction: Vector3?)
	if direction and Vector3.new(direction.X, 0, direction.Z).Magnitude > 1e-3 then
		local flat = Vector3.new(direction.X, 0, direction.Z).Unit
		self.align.CFrame = CFrame.lookAlong(Vector3.zero, flat)
		self.align.Enabled = true
		self.facing = true
		self.humanoid.AutoRotate = false
		-- Snap the body round now (a soft lock-on shouldn't be a slow turn).
		local position = self.root.Position
		self.root.CFrame = CFrame.lookAlong(position, flat)
	else
		self.align.Enabled = false
		self.facing = false
		if self.mode == "None" then
			self.humanoid.AutoRotate = true
		end
	end
end

function CombatBody.Release(self: CombatBody)
	if self.mode == "None" then
		return
	end
	self.mode = "None"
	self.velocity.Enabled = false
	self:_letGo()
end

function CombatBody._step(self: CombatBody)
	if self.mode == "None" or self.destroyed then
		return
	end
	local now = os.clock()
	if now >= self.endsAt then
		self:Release()
		return
	end
	if self.mode == "Plane" and self.decay then
		local share = 1 - (now - self.startedAt) / math.max(self.endsAt - self.startedAt, 1e-3)
		local v = self.target * math.max(share, 0)
		self.velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
	end
end

function CombatBody.Destroy(self: CombatBody)
	if self.destroyed then
		return
	end
	self:Release()
	self.destroyed = true
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.velocity:Destroy()
	self.align:Destroy()
	self.attachment:Destroy()
end

return CombatBody
