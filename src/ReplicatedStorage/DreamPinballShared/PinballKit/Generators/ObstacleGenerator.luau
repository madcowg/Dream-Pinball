--!strict

-- Passive obstacles: rubber bounce posts (no scoring, no controller -- just a
-- lively collider) and rollover lane switches (flat, non-colliding, the ball
-- rolls straight over it; Runtime/RolloverController.luau does the hit
-- detection).

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local ObstacleGenerator = {}

--------------------------------------------------------------------------------
-- Rubber bounce post
--------------------------------------------------------------------------------

export type RubberPostConfig = {
	Diameter: number?,
	Height: number?,
	Elasticity: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_POST_DIAMETER = 0.8
local DEFAULT_POST_HEIGHT = 1.5
-- Livelier than the standard wall/bumper elasticity (0.65) -- real rubber
-- posts are noticeably bouncier than a painted wood rail. GameplayDefault,
-- not measured from a specific part.
local DEFAULT_POST_ELASTICITY = 0.85

local function validatePositive(value: number, fieldName: string, context: string)
	local ok, err = GeometryValidator.ValidatePositive(value, fieldName)
	GeometryValidator.AssertAll({ { ok = ok, err = err } }, context)
end

export type RubberPostAsset = Types.GeneratedAsset & {
	Post: BasePart,
}

function ObstacleGenerator.GenerateRubberPost(options: Types.GenerateOptions<RubberPostConfig>): RubberPostAsset
	local config = options.Config
	local diameter = config.Diameter or DEFAULT_POST_DIAMETER
	local height = config.Height or DEFAULT_POST_HEIGHT
	validatePositive(diameter, "Diameter", "ObstacleGenerator.GenerateRubberPost")
	validatePositive(height, "Height", "ObstacleGenerator.GenerateRubberPost")

	local name = options.Name or "RubberPost"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "RubberPost",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local up = origin.UpVector

	local post = PrimitiveFactory.CreatePart({
		Name = "Post",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (height / 2)), up, origin.RightVector),
		Role = "Collider",
		Material = config.Material or Enum.Material.SmoothPlastic,
		Color = config.Color or BrickColor.new("Really black"),
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})
	post.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, config.Elasticity or DEFAULT_POST_ELASTICITY, 1, 1)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Post = post,
	}
end

--------------------------------------------------------------------------------
-- Rollover lane switch
--------------------------------------------------------------------------------

export type RolloverConfig = {
	Width: number?,
	Length: number?,
	IncludeLight: boolean?,
	LightColor: Color3?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	PointValue: number?,
}

local DEFAULT_ROLLOVER_WIDTH = 1.2
local DEFAULT_ROLLOVER_LENGTH = 1.8

export type RolloverAsset = Types.GeneratedAsset & {
	Switch: BasePart,
	Light: PointLight?,
}

function ObstacleGenerator.GenerateRollover(options: Types.GenerateOptions<RolloverConfig>): RolloverAsset
	local config = options.Config
	local width = config.Width or DEFAULT_ROLLOVER_WIDTH
	local length = config.Length or DEFAULT_ROLLOVER_LENGTH
	validatePositive(width, "Width", "ObstacleGenerator.GenerateRollover")
	validatePositive(length, "Length", "ObstacleGenerator.GenerateRollover")

	local name = options.Name or "RolloverSwitch"
	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "RolloverSwitch",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local switch = PrimitiveFactory.CreatePart({
		Name = "Switch",
		Size = Vector3.new(width, 0.05, length),
		CFrame = options.Origin,
		Role = "Trigger",
		Material = config.Material or Enum.Material.Neon,
		Color = config.Color or BrickColor.new("Institutional white"),
		Parent = hierarchy.Folders.Triggers,
		CollisionGroup = config.CollisionGroup,
	})

	local light: PointLight? = nil
	if config.IncludeLight then
		local newLight = Instance.new("PointLight")
		newLight.Name = "RolloverLight"
		newLight.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
		newLight.Brightness = 1.5
		newLight.Range = 4
		newLight.Enabled = false
		newLight.Parent = switch
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
		Switch = switch,
		Light = light,
	}
end

return ObstacleGenerator
