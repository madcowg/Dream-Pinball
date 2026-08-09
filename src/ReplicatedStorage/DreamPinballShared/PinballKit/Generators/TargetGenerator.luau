--!strict

-- Hideaway/retractable target (spec section 9): a single Mechanism part that
-- is simultaneously the visual and the ball-contact collider -- when
-- TargetController retracts it, the SAME instance moves along
-- TravelDirection and its CanCollide is cleared, so there is never a leftover
-- invisible blocking collider at the raised position (spec's explicit
-- requirement). This module only builds the geometry; TargetController
-- (Runtime/) owns the state machine and tweening.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local TargetGenerator = {}

export type TargetConfig = {
	Width: number?,
	Height: number?,
	Thickness: number?,
	TravelDistance: number?,
	TravelDirectionLocal: Vector3?,
	IncludeLight: boolean?,
	LightColor: Color3?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	-- Stamped as a "PointValue" attribute if set -- see BumperGenerator's
	-- Config for why this isn't defaulted here.
	PointValue: number?,
}

local DEFAULT_WIDTH_STUDS = 1.5
local DEFAULT_HEIGHT_STUDS = 1.5
local DEFAULT_THICKNESS_STUDS = 0.3

local function validateConfig(config: TargetConfig)
	local widthOk, widthErr = GeometryValidator.ValidatePositive(config.Width or DEFAULT_WIDTH_STUDS, "Width")
	local heightOk, heightErr = GeometryValidator.ValidatePositive(config.Height or DEFAULT_HEIGHT_STUDS, "Height")

	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = heightOk, err = heightErr },
	}, "TargetGenerator.Generate")
end

export type TargetAsset = Types.GeneratedAsset & {
	TargetFace: BasePart,
	RaisedCFrame: CFrame,
	TravelDirectionWorld: Vector3,
	TravelDistance: number,
	Light: PointLight?,
}

function TargetGenerator.Generate(options: Types.GenerateOptions<TargetConfig>): TargetAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "HideawayTarget"
	local width = config.Width or DEFAULT_WIDTH_STUDS
	local height = config.Height or DEFAULT_HEIGHT_STUDS
	local thickness = config.Thickness or DEFAULT_THICKNESS_STUDS
	local travelDistance = config.TravelDistance or height
	local travelDirectionLocal = config.TravelDirectionLocal or Vector3.new(0, -1, 0)

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "HideawayTarget",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local raisedCFrame = origin * CFrame.new(0, height / 2, 0)

	local targetFace = PrimitiveFactory.CreatePart({
		Name = "TargetFace",
		Size = Vector3.new(width, height, thickness),
		CFrame = raisedCFrame,
		Role = "Mechanism",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Mechanism,
		CollisionGroup = config.CollisionGroup,
	})
	targetFace.Anchored = true

	local travelDirectionWorld = origin:VectorToWorldSpace(travelDirectionLocal).Unit

	local light: PointLight? = nil
	if config.IncludeLight then
		local newLight = Instance.new("PointLight")
		newLight.Name = "TargetLight"
		newLight.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
		newLight.Brightness = 1.5
		newLight.Range = 6
		newLight.Enabled = false
		newLight.Parent = targetFace
		light = newLight
	end

	if config.PointValue ~= nil then
		hierarchy.Model:SetAttribute(Constants.POINT_VALUE_ATTRIBUTE, config.PointValue)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		TargetFace = targetFace,
		RaisedCFrame = raisedCFrame,
		TravelDirectionWorld = travelDirectionWorld,
		TravelDistance = travelDistance,
		Light = light,
	}
end

--------------------------------------------------------------------------------
-- Standup target: fixed, always up, no travel -- just a static collider that
-- registers a hit. Simpler than the hideaway target above (no state machine,
-- no CanCollide toggling) since nothing ever moves or retracts.
--------------------------------------------------------------------------------

export type StandupTargetConfig = {
	Width: number?,
	Height: number?,
	Thickness: number?,
	IncludeLight: boolean?,
	LightColor: Color3?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	PointValue: number?,
}

export type StandupTargetAsset = Types.GeneratedAsset & {
	TargetFace: BasePart,
	Light: PointLight?,
}

function TargetGenerator.GenerateStandup(options: Types.GenerateOptions<StandupTargetConfig>): StandupTargetAsset
	local config = options.Config
	local width = config.Width or DEFAULT_WIDTH_STUDS
	local height = config.Height or DEFAULT_HEIGHT_STUDS
	local thickness = config.Thickness or DEFAULT_THICKNESS_STUDS

	local widthOk, widthErr = GeometryValidator.ValidatePositive(width, "Width")
	local heightOk, heightErr = GeometryValidator.ValidatePositive(height, "Height")
	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = heightOk, err = heightErr },
	}, "TargetGenerator.GenerateStandup")

	local name = options.Name or "StandupTarget"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "StandupTarget",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local targetFace = PrimitiveFactory.CreatePart({
		Name = "TargetFace",
		Size = Vector3.new(width, height, thickness),
		CFrame = options.Origin,
		Role = "Collider",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})

	local light: PointLight? = nil
	if config.IncludeLight then
		local newLight = Instance.new("PointLight")
		newLight.Name = "TargetLight"
		newLight.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
		newLight.Brightness = 1.5
		newLight.Range = 6
		newLight.Enabled = false
		newLight.Parent = targetFace
		light = newLight
	end

	if config.PointValue ~= nil then
		hierarchy.Model:SetAttribute(Constants.POINT_VALUE_ATTRIBUTE, config.PointValue)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		TargetFace = targetFace,
		Light = light,
	}
end

--------------------------------------------------------------------------------
-- Drop target bank: 3-5 targets in a row, each hinged along its bottom edge.
-- Each target is a real HingeConstraint (Servo actuator, so it drives to a
-- commanded angle under a bounded torque/speed rather than snapping) --
-- DropTargetController decides when a touch counts as a knockdown and drives
-- TargetAngle to DownAngleDegrees; driving there physically pushes the ball
-- out of the way along the way, a real physics interaction rather than a
-- position tween. Bank-level and per-target reset both just drive
-- TargetAngle back to 0.
--------------------------------------------------------------------------------

export type DropTargetBankConfig = {
	TargetCount: number?,
	TargetWidth: number?,
	TargetHeight: number?,
	TargetThickness: number?,
	Spacing: number?,
	DownAngleDegrees: number?,
	ServoSpeed: number?,
	ServoMaxTorque: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	-- Awarded per individual target knocked down; stamped once on the bank's
	-- root Model (DropTargetController reads it per-hit, not per-target).
	PointValue: number?,
}

local DEFAULT_DROP_TARGET_COUNT = 3
local DEFAULT_DROP_TARGET_WIDTH = 1.4
local DEFAULT_DROP_TARGET_HEIGHT = 1.5
local DEFAULT_DROP_TARGET_THICKNESS = 0.25
local DEFAULT_DROP_TARGET_SPACING = 0.3
local DEFAULT_DOWN_ANGLE_DEGREES = 80
local DEFAULT_SERVO_SPEED = 8
local DEFAULT_SERVO_MAX_TORQUE = 400

export type DropTargetBankAsset = Types.GeneratedAsset & {
	Targets: { BasePart },
	Hinges: { HingeConstraint },
}

function TargetGenerator.GenerateDropBank(options: Types.GenerateOptions<DropTargetBankConfig>): DropTargetBankAsset
	local config = options.Config
	local targetCount = config.TargetCount or DEFAULT_DROP_TARGET_COUNT
	local targetWidth = config.TargetWidth or DEFAULT_DROP_TARGET_WIDTH
	local targetHeight = config.TargetHeight or DEFAULT_DROP_TARGET_HEIGHT
	local targetThickness = config.TargetThickness or DEFAULT_DROP_TARGET_THICKNESS
	local spacing = config.Spacing or DEFAULT_DROP_TARGET_SPACING

	local countOk, countErr = GeometryValidator.ValidatePositive(targetCount, "TargetCount")
	local widthOk, widthErr = GeometryValidator.ValidatePositive(targetWidth, "TargetWidth")
	GeometryValidator.AssertAll({
		{ ok = countOk, err = countErr },
		{ ok = widthOk, err = widthErr },
	}, "TargetGenerator.GenerateDropBank")

	local name = options.Name or "DropTargetBank"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "DropTargetBank",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local step = targetWidth + spacing
	local startOffset = -((targetCount - 1) * step) / 2

	local targets: { BasePart } = {}
	local hinges: { HingeConstraint } = {}

	for index = 1, targetCount do
		local centerOffset = startOffset + (index - 1) * step
		local restCFrame = origin * CFrame.new(centerOffset, 0, 0)

		-- Static anchor bracket at the target's bottom edge.
		local anchor = PrimitiveFactory.CreatePart({
			Name = string.format("DropTargetAnchor_%d", index),
			Size = Vector3.new(targetWidth * 0.8, 0.2, 0.2),
			CFrame = restCFrame * CFrame.new(0, -targetHeight / 2, 0),
			Role = "Mechanism",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Mechanism,
			CollisionGroup = config.CollisionGroup,
		})
		anchor.Anchored = true
		anchor.CanCollide = false

		local target = PrimitiveFactory.CreatePart({
			Name = string.format("DropTarget_%d", index),
			Size = Vector3.new(targetWidth, targetHeight, targetThickness),
			CFrame = restCFrame,
			Role = "Mechanism",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Mechanism,
			CollisionGroup = config.CollisionGroup,
		})

		local anchorAttachment = Instance.new("Attachment")
		anchorAttachment.Position = Vector3.new(0, targetHeight / 2, 0)
		anchorAttachment.Axis = Vector3.new(1, 0, 0)
		anchorAttachment.SecondaryAxis = Vector3.new(0, 1, 0)
		anchorAttachment.Parent = anchor

		local targetAttachment = Instance.new("Attachment")
		targetAttachment.Position = Vector3.new(0, -targetHeight / 2, 0)
		targetAttachment.Axis = Vector3.new(1, 0, 0)
		targetAttachment.SecondaryAxis = Vector3.new(0, 1, 0)
		targetAttachment.Parent = target

		local hinge = Instance.new("HingeConstraint")
		hinge.Name = string.format("DropTargetHinge_%d", index)
		hinge.Attachment0 = anchorAttachment
		hinge.Attachment1 = targetAttachment
		hinge.ActuatorType = Enum.ActuatorType.Servo
		hinge.LimitsEnabled = true
		hinge.LowerAngle = 0
		hinge.UpperAngle = config.DownAngleDegrees or DEFAULT_DOWN_ANGLE_DEGREES
		hinge.TargetAngle = 0
		hinge.AngularSpeed = config.ServoSpeed or DEFAULT_SERVO_SPEED
		hinge.ServoMaxTorque = config.ServoMaxTorque or DEFAULT_SERVO_MAX_TORQUE
		hinge.Parent = anchor

		table.insert(targets, target)
		table.insert(hinges, hinge)
	end

	if config.PointValue ~= nil then
		hierarchy.Model:SetAttribute(Constants.POINT_VALUE_ATTRIBUTE, config.PointValue)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Targets = targets,
		Hinges = hinges,
	}
end

return TargetGenerator
