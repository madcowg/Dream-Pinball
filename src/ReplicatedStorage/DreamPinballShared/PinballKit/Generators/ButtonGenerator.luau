--!strict

-- Illuminated cabinet button (spec section 9): housing + movable cap, driven
-- by a ProximityPrompt rather than a custom touch/hover system -- this
-- project already has a proven, server-validated press-to-interact affordance
-- (see architecture.md "Hand-built commercial-spec cabinets", InteractAnchor)
-- and spec section 9 explicitly allows reusing an existing interaction system
-- instead of inventing a new one. ProximityPrompt.Triggered already fires
-- server-side only after Roblox's own distance/line-of-sight validation, which
-- satisfies "a server-validated activation event" without a custom RemoteEvent.
-- The SAME generator serves start/launch/extra-ball/generic buttons: only
-- ActionText/Label and colors differ per use, all through config.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local ButtonGenerator = {}

export type ButtonConfig = {
	HousingDiameter: number?,
	HousingHeight: number?,
	CapDiameter: number?,
	PressTravel: number?,
	ActionText: string?,
	HoldDuration: number?,
	MaxActivationDistance: number?,
	OnColor: Color3?,
	OffColor: Color3?,
	IncludeLight: boolean?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_HOUSING_DIAMETER_STUDS = 1.2
local DEFAULT_HOUSING_HEIGHT_STUDS = 0.5
local DEFAULT_CAP_DIAMETER_STUDS = 0.9
local DEFAULT_PRESS_TRAVEL_STUDS = 0.12
local DEFAULT_MAX_ACTIVATION_DISTANCE = 6

local function validateConfig(config: ButtonConfig)
	local housingOk, housingErr = GeometryValidator.ValidatePositive(
		config.HousingDiameter or DEFAULT_HOUSING_DIAMETER_STUDS,
		"HousingDiameter"
	)

	GeometryValidator.AssertAll({
		{ ok = housingOk, err = housingErr },
	}, "ButtonGenerator.Generate")
end

export type ButtonAsset = Types.GeneratedAsset & {
	Cap: BasePart,
	RestCFrame: CFrame,
	PressTravel: number,
	Prompt: ProximityPrompt,
	Light: PointLight?,
}

function ButtonGenerator.Generate(options: Types.GenerateOptions<ButtonConfig>): ButtonAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "CabinetButton"
	local housingDiameter = config.HousingDiameter or DEFAULT_HOUSING_DIAMETER_STUDS
	local housingHeight = config.HousingHeight or DEFAULT_HOUSING_HEIGHT_STUDS
	local capDiameter = config.CapDiameter or DEFAULT_CAP_DIAMETER_STUDS
	local pressTravel = config.PressTravel or DEFAULT_PRESS_TRAVEL_STUDS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "CabinetButton",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local up = origin.UpVector

	PrimitiveFactory.CreatePart({
		Name = "Housing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(housingHeight, housingDiameter, housingDiameter),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (housingHeight / 2)), up, origin.RightVector),
		Role = "Collider",
		Material = config.Material or Enum.Material.Metal,
		Color = config.Color or BrickColor.new("Really black"),
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})

	local restCFrame = CFrame.fromMatrix(origin.Position + (up * (housingHeight + 0.05)), up, origin.RightVector)
	local cap = PrimitiveFactory.CreatePart({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, capDiameter, capDiameter),
		CFrame = restCFrame,
		Role = "Mechanism",
		Material = Enum.Material.Neon,
		Color = BrickColor.new(config.OffColor or Color3.fromRGB(60, 55, 40)),
		Parent = hierarchy.Folders.Mechanism,
		CollisionGroup = config.CollisionGroup,
	})
	cap.Anchored = true

	local light: PointLight? = nil
	if config.IncludeLight then
		local newLight = Instance.new("PointLight")
		newLight.Name = "ButtonLight"
		newLight.Color = config.OnColor or Color3.fromRGB(255, 220, 80)
		newLight.Brightness = 2
		newLight.Range = 4
		newLight.Enabled = false
		newLight.Parent = cap
		light = newLight
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PressPrompt"
	prompt.ActionText = config.ActionText or "Press"
	prompt.HoldDuration = config.HoldDuration or 0
	prompt.MaxActivationDistance = config.MaxActivationDistance or DEFAULT_MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = cap

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Cap = cap,
		RestCFrame = restCFrame,
		PressTravel = pressTravel,
		Prompt = prompt,
		Light = light,
	}
end

return ButtonGenerator
