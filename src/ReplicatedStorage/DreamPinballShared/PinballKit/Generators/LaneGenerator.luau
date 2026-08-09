--!strict

-- In-lane / out-lane divider walls flanking the flippers -- explicitly called
-- out as NOT YET IMPLEMENTED in architecture.md's "Flipper baseline" section
-- (see the reference image noted there, Typical_pinball_machine.png). Plain
-- static wall geometry, straight or curved, swept along a path exactly like
-- RampGenerator's side rails -- and tuned to CabinetBuilder.luau's own wall
-- constants (WALL_THICKNESS, WALL_HEIGHT, elasticity) so a lane divider
-- placed next to a CabinetBuilder-built table looks and feels like the same
-- wall, not a visibly different PinballKit part bolted on.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local PathBuilder = require(script.Parent.Parent.Geometry.PathBuilder)
local Constants = require(script.Parent.Parent.Constants)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local LaneGenerator = {}

-- Matches CabinetBuilder.luau's private WALL_THICKNESS/WALL_HEIGHT and every
-- wall's CustomPhysicalProperties(2, 0.3, 0.65, 1, 1) exactly.
local DEFAULT_WALL_THICKNESS = 1.5
local DEFAULT_WALL_HEIGHT = 4
local WALL_PHYSICAL_PROPERTIES = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)

export type LaneDividerConfig = {
	Path: PathBuilder.PathSpec,
	Height: number?,
	Thickness: number?,
	Quality: Types.Quality?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local function validateConfig(config: LaneDividerConfig)
	local height = config.Height or DEFAULT_WALL_HEIGHT
	local thickness = config.Thickness or DEFAULT_WALL_THICKNESS
	local heightOk, heightErr = GeometryValidator.ValidatePositive(height, "Height")
	local thicknessOk, thicknessErr = GeometryValidator.ValidatePositive(thickness, "Thickness")
	GeometryValidator.AssertAll({
		{ ok = heightOk, err = heightErr },
		{ ok = thicknessOk, err = thicknessErr },
	}, "LaneGenerator.GenerateDivider")
end

export type LaneDividerAsset = Types.GeneratedAsset & {
	Segments: { BasePart },
}

function LaneGenerator.GenerateDivider(options: Types.GenerateOptions<LaneDividerConfig>): LaneDividerAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "LaneDivider"
	local height = config.Height or DEFAULT_WALL_HEIGHT
	local thickness = config.Thickness or DEFAULT_WALL_THICKNESS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "LaneDivider",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local path = PathBuilder.Build(options.Origin, config.Path)
	local overlap = Constants.DEFAULT_SEGMENT_OVERLAP_STUDS
	local segments: { BasePart } = {}

	for segmentIndex = 1, #path.Samples - 1 do
		local startSample = path.Samples[segmentIndex]
		local endSample = path.Samples[segmentIndex + 1]
		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local midpointPosition = (startSample.Position + endSample.Position) / 2
		local up = startSample.Up
		local right = startSample.Right
		local tangent = startSample.Tangent

		local wallCenter = midpointPosition + (up * (height / 2))
		local wallCFrame = CFrame.fromMatrix(wallCenter, right, up, -tangent)

		local segment = PrimitiveFactory.CreatePart({
			Name = string.format("LaneWall_%d", segmentIndex),
			Size = Vector3.new(thickness, height, segmentLength + overlap),
			CFrame = wallCFrame,
			Role = "Collider",
			Material = config.Material or Enum.Material.Metal,
			Color = config.Color or BrickColor.new("Really black"),
			Parent = hierarchy.Folders.Colliders,
			CollisionGroup = config.CollisionGroup,
		})
		segment.CustomPhysicalProperties = WALL_PHYSICAL_PROPERTIES

		table.insert(segments, segment)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Segments = segments,
	}
end

return LaneGenerator
