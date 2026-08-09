--!strict

-- Playfield insert lights, bars, and rings (spec section 9): a flat,
-- non-colliding insert part (round disc, rectangle, bar, or a true circular
-- ring built from arced segments) plus an optional PointLight/SurfaceLight.
-- LightController (Runtime/) owns on/off/pulse/blink state; this module only
-- builds geometry.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local LightGenerator = {}

export type InsertShape = "Round" | "Rectangle" | "Bar" | "Ring"

export type LightConfig = {
	Shape: InsertShape,
	Diameter: number?,
	RingThickness: number?,
	RingSegments: number?,
	Width: number?,
	Length: number?,
	Thickness: number?,
	OnColor: Color3?,
	OffColor: Color3?,
	Brightness: number?,
	LightRange: number?,
	UseSurfaceLight: boolean?,
	IncludeLightInstance: boolean?,
	Material: Enum.Material?,
	CollisionGroup: string?,
}

local DEFAULT_DIAMETER_STUDS = 1.5
local DEFAULT_RING_THICKNESS_STUDS = 0.3
local DEFAULT_RING_SEGMENTS = 16
local DEFAULT_WIDTH_STUDS = 1
local DEFAULT_LENGTH_STUDS = 3
local DEFAULT_THICKNESS_STUDS = 0.1
local DEFAULT_ON_COLOR = Color3.fromRGB(255, 220, 80)
local DEFAULT_OFF_COLOR = Color3.fromRGB(60, 55, 40)
local DEFAULT_BRIGHTNESS = 2
local DEFAULT_LIGHT_RANGE = 6

local function validateConfig(config: LightConfig)
	if config.Shape ~= "Round" and config.Shape ~= "Rectangle" and config.Shape ~= "Bar" and config.Shape ~= "Ring" then
		error(string.format('LightGenerator.Generate: Shape must be "Round", "Rectangle", "Bar", or "Ring", got %s', tostring(config.Shape)), 0)
	end
end

export type LightAsset = Types.GeneratedAsset & {
	InsertParts: { BasePart },
	Light: (PointLight | SurfaceLight)?,
}

local function buildRingSegments(
	center: Vector3,
	right: Vector3,
	up: Vector3,
	look: Vector3,
	outerRadius: number,
	innerRadius: number,
	thickness: number,
	segmentCount: number,
	material: Enum.Material?,
	color: BrickColor?,
	parent: Folder
): { BasePart }
	local parts: { BasePart } = {}
	local midRadius = (outerRadius + innerRadius) / 2
	local radialThickness = outerRadius - innerRadius
	local angleStep = (2 * math.pi) / segmentCount
	local overlapAngle = angleStep * 0.15

	for index = 0, segmentCount - 1 do
		local angle = index * angleStep
		local radialDir = (right * math.cos(angle)) + (look * math.sin(angle))
		local tangentDir = (-right * math.sin(angle)) + (look * math.cos(angle))

		local chordLength = 2 * midRadius * math.sin((angleStep + overlapAngle) / 2)
		local position = center + (radialDir * midRadius)

		local part = PrimitiveFactory.CreatePart({
			Name = string.format("RingSegment_%d", index),
			Size = Vector3.new(chordLength, thickness, radialThickness),
			CFrame = CFrame.fromMatrix(position, tangentDir, up),
			Role = "Visual",
			Material = material,
			Color = color,
			Parent = parent,
		})

		table.insert(parts, part)
	end

	return parts
end

function LightGenerator.Generate(options: Types.GenerateOptions<LightConfig>): LightAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or ("Light" .. config.Shape)
	local thickness = config.Thickness or DEFAULT_THICKNESS_STUDS
	local offColor = config.OffColor or DEFAULT_OFF_COLOR

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Light" .. config.Shape,
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local insertColor = BrickColor.new(offColor)
	local insertParts: { BasePart } = {}

	if config.Shape == "Round" then
		local diameter = config.Diameter or DEFAULT_DIAMETER_STUDS
		local ok, err = GeometryValidator.ValidatePositive(diameter, "Diameter")
		if not ok then
			error(err, 0)
		end

		table.insert(
			insertParts,
			PrimitiveFactory.CreatePart({
				Name = "Insert",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(thickness, diameter, diameter),
				CFrame = CFrame.fromMatrix(origin.Position, origin.UpVector, origin.RightVector),
				Role = "Visual",
				Material = config.Material or Enum.Material.Neon,
				Color = insertColor,
				Parent = hierarchy.Folders.Lights,
			})
		)
	elseif config.Shape == "Rectangle" or config.Shape == "Bar" then
		local width = config.Width or (config.Shape == "Bar" and DEFAULT_WIDTH_STUDS or DEFAULT_DIAMETER_STUDS)
		local length = config.Length or (config.Shape == "Bar" and DEFAULT_LENGTH_STUDS or DEFAULT_DIAMETER_STUDS)
		local widthOk, widthErr = GeometryValidator.ValidatePositive(width, "Width")
		local lengthOk, lengthErr = GeometryValidator.ValidatePositive(length, "Length")
		GeometryValidator.AssertAll({
			{ ok = widthOk, err = widthErr },
			{ ok = lengthOk, err = lengthErr },
		}, "LightGenerator.Generate")

		table.insert(
			insertParts,
			PrimitiveFactory.CreatePart({
				Name = "Insert",
				Size = Vector3.new(width, thickness, length),
				CFrame = CFrame.fromMatrix(origin.Position, origin.RightVector, origin.UpVector),
				Role = "Visual",
				Material = config.Material or Enum.Material.Neon,
				Color = insertColor,
				Parent = hierarchy.Folders.Lights,
			})
		)
	else
		-- Ring
		local diameter = config.Diameter or DEFAULT_DIAMETER_STUDS
		local ringThickness = config.RingThickness or DEFAULT_RING_THICKNESS_STUDS
		local segments = config.RingSegments or DEFAULT_RING_SEGMENTS
		local outerRadius = diameter / 2
		local innerRadius = math.max(0.05, outerRadius - ringThickness)

		insertParts = buildRingSegments(
			origin.Position,
			origin.RightVector,
			origin.UpVector,
			origin.LookVector,
			outerRadius,
			innerRadius,
			thickness,
			segments,
			config.Material or Enum.Material.Neon,
			insertColor,
			hierarchy.Folders.Lights
		)
	end

	local light: (PointLight | SurfaceLight)? = nil
	if config.IncludeLightInstance ~= false then
		local holder = insertParts[1]
		if config.UseSurfaceLight then
			local surfaceLight = Instance.new("SurfaceLight")
			surfaceLight.Name = "InsertLight"
			surfaceLight.Color = config.OnColor or DEFAULT_ON_COLOR
			surfaceLight.Brightness = config.Brightness or DEFAULT_BRIGHTNESS
			surfaceLight.Range = config.LightRange or DEFAULT_LIGHT_RANGE
			surfaceLight.Face = Enum.NormalId.Top
			surfaceLight.Enabled = false
			surfaceLight.Parent = holder
			light = surfaceLight
		else
			local pointLight = Instance.new("PointLight")
			pointLight.Name = "InsertLight"
			pointLight.Color = config.OnColor or DEFAULT_ON_COLOR
			pointLight.Brightness = config.Brightness or DEFAULT_BRIGHTNESS
			pointLight.Range = config.LightRange or DEFAULT_LIGHT_RANGE
			pointLight.Enabled = false
			pointLight.Parent = holder
			light = pointLight
		end
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		InsertParts = insertParts,
		Light = light,
	}
end

return LightGenerator
