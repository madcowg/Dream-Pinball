--!strict

-- In-lane / out-lane divider walls flanking the flippers -- explicitly called
-- out as NOT YET IMPLEMENTED in architecture.md's "Flipper baseline" section
-- (see the reference image noted there, Typical_pinball_machine.png). Plain
-- static wall geometry, straight or curved, swept along a path exactly like
-- RampGenerator's side rails.
--
-- Height/thickness deliberately do NOT match CabinetBuilder.luau's boundary
-- walls (an earlier version of this file did, and it read as an oversized
-- slab floating above the playfield, not a lane guide) -- a real in-lane/
-- out-lane divider is a low, thin plastic guide rail, not a structural
-- boundary wall. Sized off Scale.BALL_DIAMETER_STUDS instead, the same way
-- every rail/tunnel generator's clearance is (spec section 4): just tall
-- enough that the ball can't hop over it, not an arbitrary borrowed height.
-- CustomPhysicalProperties still matches CabinetBuilder's walls, so the
-- *bounce feel* is consistent even though the *size* isn't.
--
-- Each divider also carries one programmable rollover trigger + a small lit
-- indicator (a LightGenerator "Bar" insert standing in for a printed arrow
-- graphic -- PinballKit has no texture/decal asset pipeline to draw an actual
-- arrow with). Runtime/LaneController.luau wires the trigger to a caller-
-- supplied callback (points, extra ball, saved ball, or nothing) rather than
-- hardcoding a behavior here, since what a rollover does changes per level.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local PathBuilder = require(script.Parent.Parent.Geometry.PathBuilder)
local LightGenerator = require(script.Parent.LightGenerator)
local Constants = require(script.Parent.Parent.Constants)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local LaneGenerator = {}

local DEFAULT_WALL_THICKNESS = 0.3
-- 1.5x ball diameter: enough to stop the ball hopping over at normal lane
-- speed without reading as a full-height boundary wall.
local DEFAULT_WALL_HEIGHT = Scale.BALL_DIAMETER_STUDS * 1.5
local WALL_PHYSICAL_PROPERTIES = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)

-- Lateral span of the rollover trigger and indicator light. An ESTIMATE --
-- there's no live geometry here to size it against the actual inlane/outlane
-- channel width, unlike Height/Thickness above (which are anchored to the
-- ball's own diameter). Widen/narrow per cabinet via Config.TriggerWidth.
local DEFAULT_TRIGGER_WIDTH = 3
-- How far along the divider (0 = start/bottom, 1 = end/top) the trigger
-- sits. 0.3 puts it in the lower third, roughly where a real inlane rollover
-- switch sits relative to the flipper -- also an estimate.
local DEFAULT_TRIGGER_FRACTION_ALONG_PATH = 0.3
local DEFAULT_ARROW_ON_COLOR = Color3.fromRGB(255, 220, 80)
local DEFAULT_ARROW_OFF_COLOR = Color3.fromRGB(60, 55, 40)

export type LaneDividerConfig = {
	Path: PathBuilder.PathSpec,
	Height: number?,
	Thickness: number?,
	Quality: Types.Quality?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	IncludeTrigger: boolean?,
	TriggerWidth: number?,
	TriggerFractionAlongPath: number?,
	TriggerArrowOnColor: Color3?,
	TriggerArrowOffColor: Color3?,
}

local function validateConfig(config: LaneDividerConfig)
	local height = config.Height or DEFAULT_WALL_HEIGHT
	local thickness = config.Thickness or DEFAULT_WALL_THICKNESS
	local triggerWidth = config.TriggerWidth or DEFAULT_TRIGGER_WIDTH
	local heightOk, heightErr = GeometryValidator.ValidatePositive(height, "Height")
	local thicknessOk, thicknessErr = GeometryValidator.ValidatePositive(thickness, "Thickness")
	local triggerWidthOk, triggerWidthErr = GeometryValidator.ValidatePositive(triggerWidth, "TriggerWidth")
	GeometryValidator.AssertAll({
		{ ok = heightOk, err = heightErr },
		{ ok = thicknessOk, err = thicknessErr },
		{ ok = triggerWidthOk, err = triggerWidthErr },
	}, "LaneGenerator.GenerateDivider")

	local triggerFraction = config.TriggerFractionAlongPath or DEFAULT_TRIGGER_FRACTION_ALONG_PATH
	if triggerFraction < 0 or triggerFraction > 1 then
		error(string.format("LaneGenerator.GenerateDivider: TriggerFractionAlongPath must be between 0 and 1, got %.4f", triggerFraction), 0)
	end
end

export type LaneDividerAsset = Types.GeneratedAsset & {
	Segments: { BasePart },
	Trigger: BasePart?,
	TriggerLight: LightGenerator.LightAsset?,
}

function LaneGenerator.GenerateDivider(options: Types.GenerateOptions<LaneDividerConfig>): LaneDividerAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "LaneDivider"
	local height = config.Height or DEFAULT_WALL_HEIGHT
	local thickness = config.Thickness or DEFAULT_WALL_THICKNESS
	local includeTrigger = config.IncludeTrigger ~= false

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

	local trigger: BasePart? = nil
	local triggerLight: LightGenerator.LightAsset? = nil

	if includeTrigger and #path.Samples > 0 then
		local triggerWidth = config.TriggerWidth or DEFAULT_TRIGGER_WIDTH
		local triggerFraction = config.TriggerFractionAlongPath or DEFAULT_TRIGGER_FRACTION_ALONG_PATH
		local sampleIndex = math.clamp(math.round(triggerFraction * (#path.Samples - 1)) + 1, 1, #path.Samples)
		local sample = path.Samples[sampleIndex]

		-- Thin plane straddling the divider, at ball-center height, spanning
		-- TriggerWidth so it catches a ball passing on either side of the
		-- wall -- see DEFAULT_TRIGGER_WIDTH's comment on why that width is an
		-- estimate.
		local triggerCenter = sample.Position + sample.Up * (Scale.BALL_DIAMETER_STUDS / 2)
		trigger = PrimitiveFactory.CreatePart({
			Name = "Trigger",
			Size = Vector3.new(triggerWidth, Scale.BALL_DIAMETER_STUDS, 0.3),
			CFrame = CFrame.fromMatrix(triggerCenter, sample.Right, sample.Up, -sample.Tangent),
			Role = "Trigger",
			Material = Enum.Material.SmoothPlastic,
			Color = config.Color or BrickColor.new("Really black"),
			Parent = hierarchy.Folders.Triggers,
		})
		trigger.Transparency = 1

		-- Small lit rectangle standing in for a printed arrow-graphic insert
		-- (see header comment) -- flush on the surface, right at the trigger,
		-- so a lit trigger reads as "this one currently does something."
		triggerLight = LightGenerator.Generate({
			Name = "TriggerArrow",
			Origin = CFrame.fromMatrix(sample.Position + sample.Up * 0.05, sample.Right, sample.Up),
			Parent = hierarchy.Folders.Lights,
			Config = {
				Shape = "Bar",
				Width = 0.6,
				Length = 1.2,
				OnColor = config.TriggerArrowOnColor or DEFAULT_ARROW_ON_COLOR,
				OffColor = config.TriggerArrowOffColor or DEFAULT_ARROW_OFF_COLOR,
			},
		})
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {},
		Segments = segments,
		Trigger = trigger,
		TriggerLight = triggerLight,
	}
end

return LaneGenerator
