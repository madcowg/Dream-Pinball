--!strict

-- Spinner (spec section 9): a flat paddle free to rotate about a horizontal
-- axle running across the ball's lane (local Right at Origin). The ball
-- physically spins the paddle on contact -- HingeConstraint with
-- ActuatorType = None (or a weak Motor damper if MotorDampingTorque is set),
-- no scripted rotation. SpinnerController (Runtime/) reads angular velocity to
-- detect and score a spin; this module only builds the geometry/mechanism.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local SpinnerGenerator = {}

export type SpinnerConfig = {
	PaddleWidth: number?,
	PaddleHeight: number?,
	PaddleThickness: number?,
	PaddleDensity: number?,
	BracketHeight: number?,
	MotorDampingTorque: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	-- Stamped as a "PointValue" attribute if set -- see BumperGenerator's
	-- Config for why this isn't defaulted here.
	PointValue: number?,
}

local DEFAULT_PADDLE_WIDTH_STUDS = 3
-- Was 1.5 -- exactly the ball's own diameter, with zero vertical margin.
-- Any small placement/alignment slop meant the ball's top or bottom edge
-- could clip past the paddle without solid contact ("the ball can't go
-- through" -- it was going through). 2.5 leaves real clearance above and
-- below a 1.5-stud ball regardless of exact placement height.
local DEFAULT_PADDLE_HEIGHT_STUDS = 2.5
-- Was 0.15 -- a blade that thin is exactly the kind of collider a fast ball
-- can tunnel through in a single physics step (the same failure mode
-- documented for thin flippers in CabinetGameplay.luau -- "crossed the
-- collision volume too fast to register"). Thicker gives the physics solver
-- more room to actually resolve the contact before the ball passes through.
local DEFAULT_PADDLE_THICKNESS_STUDS = 0.4
-- Was 2 -- lighter paddle needs less of a hit to start spinning ("looser in
-- its engagement"), and with ActuatorType.None (free-spinning, no damping by
-- default) a lighter paddle also reads a light touch as a bigger angular
-- velocity change, making SpinnerController's threshold easier to cross.
local DEFAULT_PADDLE_DENSITY = 1.2
local DEFAULT_BRACKET_HEIGHT_STUDS = 1

local function validateConfig(config: SpinnerConfig)
	local widthOk, widthErr =
		GeometryValidator.ValidatePositive(config.PaddleWidth or DEFAULT_PADDLE_WIDTH_STUDS, "PaddleWidth")
	local heightOk, heightErr =
		GeometryValidator.ValidatePositive(config.PaddleHeight or DEFAULT_PADDLE_HEIGHT_STUDS, "PaddleHeight")

	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = heightOk, err = heightErr },
	}, "SpinnerGenerator.Generate")
end

export type SpinnerAsset = Types.GeneratedAsset & {
	Paddle: BasePart,
	Hinge: HingeConstraint,
}

function SpinnerGenerator.Generate(options: Types.GenerateOptions<SpinnerConfig>): SpinnerAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Spinner"
	local paddleWidth = config.PaddleWidth or DEFAULT_PADDLE_WIDTH_STUDS
	local paddleHeight = config.PaddleHeight or DEFAULT_PADDLE_HEIGHT_STUDS
	local paddleThickness = config.PaddleThickness or DEFAULT_PADDLE_THICKNESS_STUDS
	local bracketHeight = config.BracketHeight or DEFAULT_BRACKET_HEIGHT_STUDS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Spinner",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local axleHalfSpan = (paddleWidth / 2) + 0.3

	-- Static axle: a thin cylinder spanning both brackets, purely structural.
	local axle = PrimitiveFactory.CreatePart({
		Name = "Axle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(paddleWidth + 0.6, paddleThickness * 2, paddleThickness * 2),
		CFrame = CFrame.fromMatrix(origin.Position, origin.RightVector, origin.UpVector),
		Role = "Mechanism",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Mechanism,
		CollisionGroup = config.CollisionGroup,
	})
	axle.Anchored = true
	axle.CanCollide = false

	-- Two support brackets, one on each side of the paddle.
	for _, sign in ipairs({ -1, 1 }) do
		local bracket = PrimitiveFactory.CreatePart({
			Name = string.format("Bracket_%d", sign),
			Size = Vector3.new(0.3, bracketHeight, 0.3),
			CFrame = (origin + origin.RightVector * axleHalfSpan * sign) * CFrame.new(0, -bracketHeight / 2, 0),
			Role = "Mechanism",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Mechanism,
			CollisionGroup = config.CollisionGroup,
		})
		bracket.Anchored = true
	end

	-- Anchored hinge base (Attachment0 side) coincides with the axle.
	local hingeBase = Instance.new("Attachment")
	hingeBase.Name = "SpinnerHingeBase"
	hingeBase.CFrame = CFrame.new()
	hingeBase.Axis = Vector3.new(1, 0, 0)
	hingeBase.SecondaryAxis = Vector3.new(0, 1, 0)
	hingeBase.Parent = axle

	-- Paddle: unanchored Mechanism part, free to rotate about local X (Right).
	local paddle = PrimitiveFactory.CreatePart({
		Name = "Paddle",
		Size = Vector3.new(paddleWidth, paddleHeight, paddleThickness),
		CFrame = origin,
		Role = "Mechanism",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Mechanism,
		CollisionGroup = config.CollisionGroup,
	})
	paddle.CustomPhysicalProperties =
		PhysicalProperties.new(config.PaddleDensity or DEFAULT_PADDLE_DENSITY, 0.3, 0.2, 1, 1)

	local paddleAttachment = Instance.new("Attachment")
	paddleAttachment.Name = "SpinnerHingePaddle"
	paddleAttachment.CFrame = CFrame.new()
	paddleAttachment.Axis = Vector3.new(1, 0, 0)
	paddleAttachment.SecondaryAxis = Vector3.new(0, 1, 0)
	paddleAttachment.Parent = paddle

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "SpinnerHinge"
	hinge.Attachment0 = hingeBase
	hinge.Attachment1 = paddleAttachment
	hinge.LimitsEnabled = false

	local dampingTorque = config.MotorDampingTorque
	if dampingTorque ~= nil and dampingTorque > 0 then
		hinge.ActuatorType = Enum.ActuatorType.Motor
		hinge.AngularVelocity = 0
		hinge.MotorMaxTorque = dampingTorque
	else
		hinge.ActuatorType = Enum.ActuatorType.None
	end

	hinge.Parent = hierarchy.Folders.Mechanism

	if config.PointValue ~= nil then
		hierarchy.Model:SetAttribute(Constants.POINT_VALUE_ATTRIBUTE, config.PointValue)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Paddle = paddle,
		Hinge = hinge,
	}
end

return SpinnerGenerator
