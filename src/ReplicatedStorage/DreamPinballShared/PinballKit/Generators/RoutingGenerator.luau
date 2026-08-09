--!strict

-- One-way gates and diverters (ball-routing obstacles): both are a hinged
-- flap on a Servo-actuated HingeConstraint, differing only in torque/limits/
-- who drives them.
--   - Gate: LowerAngle = 0 is a hard mechanical stop (blocks that direction
--     entirely); a weak ServoMaxTorque acts as the return spring, so a ball
--     rolling in from the open side physically overpowers it, swings the gate
--     open up to UpperAngle, then the spring pulls it shut again once the
--     ball's through. This is a real bounded-torque physics interaction, not
--     a scripted animation -- the ball genuinely has to push it.
--   - Diverter: a strong, script-driven Servo with no incidental "give" --
--     RoutingController.SetDiverted commands it between two fixed positions
--     to steer the ball down one of two paths on purpose.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local RoutingGenerator = {}

export type FlapAsset = Types.GeneratedAsset & {
	Flap: BasePart,
	Hinge: HingeConstraint,
}

local function buildFlap(
	options: { Origin: CFrame, Width: number, Height: number, Thickness: number, Material: Enum.Material?, Color: BrickColor?, CollisionGroup: string? },
	mechanismFolder: Folder
): (BasePart, Attachment, Attachment)
	local origin = options.Origin
	local restCFrame = origin * CFrame.new(0, options.Height / 2, 0)

	local anchor = PrimitiveFactory.CreatePart({
		Name = "FlapAnchor",
		Size = Vector3.new(options.Width * 0.8, 0.2, 0.2),
		CFrame = origin,
		Role = "Mechanism",
		Material = options.Material,
		Color = options.Color,
		Parent = mechanismFolder,
		CollisionGroup = options.CollisionGroup,
	})
	anchor.Anchored = true
	anchor.CanCollide = false

	local flap = PrimitiveFactory.CreatePart({
		Name = "Flap",
		Size = Vector3.new(options.Width, options.Height, options.Thickness),
		CFrame = restCFrame,
		Role = "Mechanism",
		Material = options.Material,
		Color = options.Color,
		Parent = mechanismFolder,
		CollisionGroup = options.CollisionGroup,
	})

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Axis = Vector3.new(1, 0, 0)
	anchorAttachment.SecondaryAxis = Vector3.new(0, 1, 0)
	anchorAttachment.Parent = anchor

	local flapAttachment = Instance.new("Attachment")
	flapAttachment.Position = Vector3.new(0, -options.Height / 2, 0)
	flapAttachment.Axis = Vector3.new(1, 0, 0)
	flapAttachment.SecondaryAxis = Vector3.new(0, 1, 0)
	flapAttachment.Parent = flap

	return flap, anchorAttachment, flapAttachment
end

--------------------------------------------------------------------------------
-- One-way gate
--------------------------------------------------------------------------------

export type GateConfig = {
	Width: number?,
	Height: number?,
	Thickness: number?,
	OpenAngleDegrees: number?,
	ReturnSpringTorque: number?,
	ReturnSpeed: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_GATE_WIDTH = 2
local DEFAULT_GATE_HEIGHT = 2
local DEFAULT_GATE_THICKNESS = 0.15
local DEFAULT_OPEN_ANGLE_DEGREES = 75
local DEFAULT_RETURN_SPRING_TORQUE = 15
local DEFAULT_RETURN_SPEED = 6

function RoutingGenerator.GenerateGate(options: Types.GenerateOptions<GateConfig>): FlapAsset
	local config = options.Config
	local width = config.Width or DEFAULT_GATE_WIDTH
	local height = config.Height or DEFAULT_GATE_HEIGHT

	local widthOk, widthErr = GeometryValidator.ValidatePositive(width, "Width")
	local heightOk, heightErr = GeometryValidator.ValidatePositive(height, "Height")
	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = heightOk, err = heightErr },
	}, "RoutingGenerator.GenerateGate")

	local name = options.Name or "OneWayGate"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "OneWayGate",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	local flap, anchorAttachment, flapAttachment = buildFlap({
		Origin = options.Origin,
		Width = width,
		Height = height,
		Thickness = config.Thickness or DEFAULT_GATE_THICKNESS,
		Material = config.Material,
		Color = config.Color,
		CollisionGroup = config.CollisionGroup,
	}, hierarchy.Folders.Mechanism)

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "GateHinge"
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = flapAttachment
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.LimitsEnabled = true
	hinge.LowerAngle = 0 -- hard stop: cannot swing past closed the other way
	hinge.UpperAngle = config.OpenAngleDegrees or DEFAULT_OPEN_ANGLE_DEGREES
	hinge.TargetAngle = 0
	hinge.AngularSpeed = config.ReturnSpeed or DEFAULT_RETURN_SPEED
	hinge.ServoMaxTorque = config.ReturnSpringTorque or DEFAULT_RETURN_SPRING_TORQUE
	hinge.Parent = flap.Parent

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Flap = flap,
		Hinge = hinge,
	}
end

--------------------------------------------------------------------------------
-- Diverter
--------------------------------------------------------------------------------

export type DiverterConfig = {
	Width: number?,
	Height: number?,
	Thickness: number?,
	DivertedAngleDegrees: number?,
	ServoSpeed: number?,
	ServoMaxTorque: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_DIVERTER_WIDTH = 2.5
local DEFAULT_DIVERTER_HEIGHT = 2
local DEFAULT_DIVERTER_THICKNESS = 0.2
local DEFAULT_DIVERTED_ANGLE_DEGREES = 45
local DEFAULT_DIVERTER_SERVO_SPEED = 10
local DEFAULT_DIVERTER_SERVO_TORQUE = 600

function RoutingGenerator.GenerateDiverter(options: Types.GenerateOptions<DiverterConfig>): FlapAsset
	local config = options.Config
	local width = config.Width or DEFAULT_DIVERTER_WIDTH
	local height = config.Height or DEFAULT_DIVERTER_HEIGHT

	local widthOk, widthErr = GeometryValidator.ValidatePositive(width, "Width")
	local heightOk, heightErr = GeometryValidator.ValidatePositive(height, "Height")
	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = heightOk, err = heightErr },
	}, "RoutingGenerator.GenerateDiverter")

	local name = options.Name or "Diverter"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Diverter",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	local flap, anchorAttachment, flapAttachment = buildFlap({
		Origin = options.Origin,
		Width = width,
		Height = height,
		Thickness = config.Thickness or DEFAULT_DIVERTER_THICKNESS,
		Material = config.Material,
		Color = config.Color,
		CollisionGroup = config.CollisionGroup,
	}, hierarchy.Folders.Mechanism)

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "DiverterHinge"
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = flapAttachment
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.LimitsEnabled = true
	hinge.LowerAngle = 0
	hinge.UpperAngle = config.DivertedAngleDegrees or DEFAULT_DIVERTED_ANGLE_DEGREES
	hinge.TargetAngle = 0
	hinge.AngularSpeed = config.ServoSpeed or DEFAULT_DIVERTER_SERVO_SPEED
	hinge.ServoMaxTorque = config.ServoMaxTorque or DEFAULT_DIVERTER_SERVO_TORQUE
	hinge.Parent = flap.Parent

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Flap = flap,
		Hinge = hinge,
	}
end

return RoutingGenerator
