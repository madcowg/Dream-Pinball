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

return TargetGenerator
