--!strict

-- Pop bumper (spec section 9): base + body (real colliders, physically present
-- so the ball can never tunnel through), an outer skirt Trigger for early
-- radial activation detection (mimicking a real bumper's wider skirt), and a
-- decorative ring + cap (optional cap light). BumperController (Runtime/)
-- computes the outward/upward impulse and plays the compression animation;
-- this module only builds geometry.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local BumperGenerator = {}

export type BumperConfig = {
	BaseDiameter: number?,
	BaseHeight: number?,
	BodyDiameter: number?,
	BodyHeight: number?,
	CapHeight: number?,
	SkirtDiameter: number?,
	CapColor: BrickColor?,
	LightColor: Color3?,
	IncludeCapLight: boolean?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_BASE_DIAMETER_STUDS = 3.5
local DEFAULT_BASE_HEIGHT_STUDS = 0.3
local DEFAULT_BODY_DIAMETER_STUDS = 2.5
local DEFAULT_BODY_HEIGHT_STUDS = 1.2
local DEFAULT_CAP_HEIGHT_STUDS = 0.35
local DEFAULT_SKIRT_MARGIN_STUDS = 0.8

local function validateConfig(config: BumperConfig)
	local bodyOk, bodyErr =
		GeometryValidator.ValidatePositive(config.BodyDiameter or DEFAULT_BODY_DIAMETER_STUDS, "BodyDiameter")
	local baseOk, baseErr =
		GeometryValidator.ValidatePositive(config.BaseDiameter or DEFAULT_BASE_DIAMETER_STUDS, "BaseDiameter")

	GeometryValidator.AssertAll({
		{ ok = bodyOk, err = bodyErr },
		{ ok = baseOk, err = baseErr },
	}, "BumperGenerator.Generate")
end

export type BumperAsset = Types.GeneratedAsset & {
	Body: BasePart,
	SkirtTrigger: BasePart,
	Cap: BasePart,
	CapLight: PointLight?,
}

function BumperGenerator.Generate(options: Types.GenerateOptions<BumperConfig>): BumperAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Bumper"
	local baseDiameter = config.BaseDiameter or DEFAULT_BASE_DIAMETER_STUDS
	local baseHeight = config.BaseHeight or DEFAULT_BASE_HEIGHT_STUDS
	local bodyDiameter = config.BodyDiameter or DEFAULT_BODY_DIAMETER_STUDS
	local bodyHeight = config.BodyHeight or DEFAULT_BODY_HEIGHT_STUDS
	local capHeight = config.CapHeight or DEFAULT_CAP_HEIGHT_STUDS
	local skirtDiameter = config.SkirtDiameter or (bodyDiameter + DEFAULT_SKIRT_MARGIN_STUDS * 2)

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Bumper",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local up = origin.UpVector

	PrimitiveFactory.CreatePart({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(baseHeight, baseDiameter, baseDiameter),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (baseHeight / 2)), up, origin.RightVector),
		Role = "Collider",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})

	local body = PrimitiveFactory.CreatePart({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(bodyHeight, bodyDiameter, bodyDiameter),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (baseHeight + bodyHeight / 2)), up, origin.RightVector),
		Role = "Collider",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})

	-- Decorative ring band around the base of the body.
	PrimitiveFactory.CreatePart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, bodyDiameter + 0.15, bodyDiameter + 0.15),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (baseHeight + 0.15)), up, origin.RightVector),
		Role = "Visual",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Visuals,
	})

	local cap = PrimitiveFactory.CreatePart({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(capHeight, bodyDiameter - 0.3, bodyDiameter - 0.3),
		CFrame = CFrame.fromMatrix(
			origin.Position + (up * (baseHeight + bodyHeight + capHeight / 2)),
			up,
			origin.RightVector
		),
		Role = "Visual",
		Material = Enum.Material.SmoothPlastic,
		Color = config.CapColor or BrickColor.new("White"),
		Parent = hierarchy.Folders.Visuals,
	})

	local capLight: PointLight? = nil
	if config.IncludeCapLight then
		local light = Instance.new("PointLight")
		light.Name = "CapLight"
		light.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
		light.Brightness = 2
		light.Range = 8
		light.Enabled = false
		light.Parent = cap
		capLight = light
	end

	-- Outer skirt: a wide, short, non-colliding trigger for early radial
	-- activation detection -- CanQuery stays true so scripted proximity checks
	-- (e.g. nearest-bumper lookups) can still hit-test it if ever needed.
	local skirtTrigger = PrimitiveFactory.CreatePart({
		Name = "SkirtTrigger",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(bodyHeight, skirtDiameter, skirtDiameter),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (baseHeight + bodyHeight / 2)), up, origin.RightVector),
		Role = "Trigger",
		Parent = hierarchy.Folders.Triggers,
		CollisionGroup = config.CollisionGroup,
	})

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Body = body,
		SkirtTrigger = skirtTrigger,
		Cap = cap,
		CapLight = capLight,
	}
end

return BumperGenerator
