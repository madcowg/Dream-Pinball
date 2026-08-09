--!strict

-- Captive-ball pocket: a floor + circular rim that physically contains a
-- ball, plus an occupancy trigger for CaptiveController to detect "the ball
-- has settled" before kicking it back out. Both a kickout hole/VUK (tall rim,
-- mostly-vertical kick) and a ball trough/drain feed (short rim, mostly-
-- horizontal kick toward the plunger lane) are the SAME mechanism -- capture,
-- pause, kick -- just different config, so one generator covers both rather
-- than duplicating near-identical geometry twice.
--
-- Rim construction reuses the same "panels arranged around a circle" idea as
-- ProfileSweep/LightGenerator's ring insert, oriented as vertical walls
-- instead of a flat cross-section or a flat marker -- a fourth appearance of
-- this pattern; worth factoring into a shared helper if a fifth shows up.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local CaptiveGenerator = {}

export type CaptivePocketConfig = {
	Radius: number?,
	RimHeight: number?,
	RimThickness: number?,
	RimSegments: number?,
	FloorThickness: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local DEFAULT_RADIUS = 1.6
local DEFAULT_RIM_HEIGHT = 1.2
local DEFAULT_RIM_THICKNESS = 0.25
local DEFAULT_RIM_SEGMENTS = 10
local DEFAULT_FLOOR_THICKNESS = 0.3

local function validateConfig(config: CaptivePocketConfig)
	local radius = config.Radius or DEFAULT_RADIUS
	local ok, err = GeometryValidator.ValidatePositive(radius, "Radius")
	GeometryValidator.AssertAll({ { ok = ok, err = err } }, "CaptiveGenerator.GeneratePocket")

	if radius * 2 < Scale.BALL_DIAMETER_STUDS then
		error(
			string.format(
				"CaptiveGenerator.GeneratePocket: Radius %.4f studs is too small to hold a %.4f-stud ball",
				radius,
				Scale.BALL_DIAMETER_STUDS
			),
			0
		)
	end
end

export type CaptivePocketAsset = Types.GeneratedAsset & {
	Floor: BasePart,
	OccupancyTrigger: BasePart,
}

function CaptiveGenerator.GeneratePocket(options: Types.GenerateOptions<CaptivePocketConfig>): CaptivePocketAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "CaptivePocket"
	local radius = config.Radius or DEFAULT_RADIUS
	local rimHeight = config.RimHeight or DEFAULT_RIM_HEIGHT
	local rimThickness = config.RimThickness or DEFAULT_RIM_THICKNESS
	local rimSegments = config.RimSegments or DEFAULT_RIM_SEGMENTS
	local floorThickness = config.FloorThickness or DEFAULT_FLOOR_THICKNESS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "CaptivePocket",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local up = origin.UpVector
	local right = origin.RightVector
	local look = origin.LookVector

	local floor = PrimitiveFactory.CreatePart({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(floorThickness, radius * 2, radius * 2),
		CFrame = CFrame.fromMatrix(origin.Position, up, right),
		Role = "Collider",
		Material = config.Material,
		Color = config.Color,
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})

	local angleStep = (2 * math.pi) / rimSegments
	local overlapAngle = angleStep * 0.2
	local rimRadius = radius + (rimThickness / 2)
	local rimCenterHeight = origin.Position + (up * (rimHeight / 2))

	for index = 0, rimSegments - 1 do
		local angle = index * angleStep
		local radialDir = (right * math.cos(angle)) + (look * math.sin(angle))
		local tangentDir = (-right * math.sin(angle)) + (look * math.cos(angle))

		local chordLength = 2 * rimRadius * math.sin((angleStep + overlapAngle) / 2)
		local position = rimCenterHeight + (radialDir * rimRadius)

		PrimitiveFactory.CreatePart({
			Name = string.format("RimSegment_%d", index),
			Size = Vector3.new(chordLength, rimHeight, rimThickness),
			CFrame = CFrame.fromMatrix(position, tangentDir, up),
			Role = "Collider",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Colliders,
			CollisionGroup = config.CollisionGroup,
		})
	end

	local occupancyTrigger = PrimitiveFactory.CreatePart({
		Name = "OccupancyTrigger",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(Scale.BALL_DIAMETER_STUDS, radius * 1.6, radius * 1.6),
		CFrame = CFrame.fromMatrix(origin.Position + (up * (Scale.BALL_DIAMETER_STUDS / 2)), up, right),
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
		Floor = floor,
		OccupancyTrigger = occupancyTrigger,
	}
end

return CaptiveGenerator
