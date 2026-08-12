--!strict

-- Inlane/outlane pair flanking one side of the lower playfield (spec section
-- 9): ONE shared divider rail (built via GuideRailBuilder -- the same wall-
-- segment math LaneGenerator.GenerateDivider uses) plus two independent
-- rollover triggers offset from it. The inlane's OUTER boundary (a
-- slingshot's own outer edge) and the outlane's OUTER boundary (the
-- cabinet's own wall) are external references this generator does NOT
-- build -- per spec's "do not hand-place unrelated rectangular walls," each
-- generator owns only its own component.
--
-- Convention: along the divider Path's own direction of travel, the INLANE
-- sits on the +Right side and the OUTLANE sits on the -Right side. The
-- caller (typically LowerPlayfieldGenerator) is responsible for orienting
-- Origin/Path so +Right actually points toward the slingshot/inward for
-- whichever physical side this is -- mirror the Path itself for the other
-- side via MirrorTransform, don't flip this convention per-instance.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local PathBuilder = require(script.Parent.Parent.Geometry.PathBuilder)
local LanePath = require(script.Parent.Parent.Geometry.LanePath)
local GuideRailBuilder = require(script.Parent.Parent.Geometry.GuideRailBuilder)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local LightGenerator = require(script.Parent.LightGenerator)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local InlaneOutlaneGenerator = {}

export type Side = MirrorTransform.Side

-- Gameplay-tuned defaults (spec section 2) -- not Williams factory dimensions.
local DEFAULT_INLANE_CLEAR_WIDTH_STUDS = 1.85
local DEFAULT_OUTLANE_CLEAR_WIDTH_STUDS = 1.85
local DEFAULT_MINIMUM_CLEARANCE_STUDS = 1.70
local DEFAULT_GUIDE_HEIGHT_STUDS = Scale.BALL_DIAMETER_STUDS * 1.5
local DEFAULT_GUIDE_THICKNESS_STUDS = 0.3
local DEFAULT_ROLLOVER_WIDTH_STUDS = 1.2
local DEFAULT_TRIGGER_FRACTION_ALONG_PATH = 0.5
local DEFAULT_INLANE_LIGHT_ON_COLOR = Color3.fromRGB(120, 220, 255)
local DEFAULT_INLANE_LIGHT_OFF_COLOR = Color3.fromRGB(40, 55, 60)
local DEFAULT_OUTLANE_LIGHT_ON_COLOR = Color3.fromRGB(255, 90, 60)
local DEFAULT_OUTLANE_LIGHT_OFF_COLOR = Color3.fromRGB(60, 40, 35)

export type InlaneOutlaneConfig = {
	Side: Side,
	-- Centerline the shared divider rail follows.
	Path: PathBuilder.PathSpec,
	InlaneClearWidth: number?,
	OutlaneClearWidth: number?,
	-- Absolute floor; never actually goes below Scale.DEFAULT_INNER_DIAMETER_STUDS
	-- (1.70 studs) even if a smaller value is passed here.
	MinimumClearance: number?,
	GuideHeight: number?,
	GuideThickness: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	RolloverEnabled: boolean?,
	RolloverWidth: number?,
	RolloverCooldown: number?,
	TriggerFractionAlongPath: number?,
	InlaneLightEnabled: boolean?,
	OutlaneLightEnabled: boolean?,
	-- Placeholder attachment point only, disabled by default -- spec section
	-- 9: "include a disabled-by-default kickback attachment point." No
	-- kickback mechanism is built here.
	OutlaneKickbackAttachment: boolean?,
}

local function validateConfig(config: InlaneOutlaneConfig)
	local minimum = math.max(config.MinimumClearance or DEFAULT_MINIMUM_CLEARANCE_STUDS, Scale.DEFAULT_INNER_DIAMETER_STUDS)
	local inlaneWidth = config.InlaneClearWidth or DEFAULT_INLANE_CLEAR_WIDTH_STUDS
	local outlaneWidth = config.OutlaneClearWidth or DEFAULT_OUTLANE_CLEAR_WIDTH_STUDS

	local inlaneOk, inlaneErr = LanePath.ValidateClearWidth(inlaneWidth, minimum, "InlaneClearWidth")
	local outlaneOk, outlaneErr = LanePath.ValidateClearWidth(outlaneWidth, minimum, "OutlaneClearWidth")
	local heightOk, heightErr = GeometryValidator.ValidatePositive(config.GuideHeight or DEFAULT_GUIDE_HEIGHT_STUDS, "GuideHeight")
	local thicknessOk, thicknessErr = GeometryValidator.ValidatePositive(config.GuideThickness or DEFAULT_GUIDE_THICKNESS_STUDS, "GuideThickness")

	GeometryValidator.AssertAll({
		{ ok = inlaneOk, err = inlaneErr },
		{ ok = outlaneOk, err = outlaneErr },
		{ ok = heightOk, err = heightErr },
		{ ok = thicknessOk, err = thicknessErr },
	}, "InlaneOutlaneGenerator.Generate")
end

export type InlaneOutlaneAsset = Types.GeneratedAsset & {
	Side: Side,
	DividerSegments: { BasePart },
	InlaneTrigger: BasePart?,
	OutlaneTrigger: BasePart?,
	InlaneLight: LightGenerator.LightAsset?,
	OutlaneLight: LightGenerator.LightAsset?,
	KickbackAttachment: Attachment?,
	EndCFrame: CFrame,
	InlaneClearWidth: number,
	OutlaneClearWidth: number,
}

function InlaneOutlaneGenerator.Generate(options: Types.GenerateOptions<InlaneOutlaneConfig>): InlaneOutlaneAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or (config.Side .. "InlaneOutlane")
	local inlaneWidth = config.InlaneClearWidth or DEFAULT_INLANE_CLEAR_WIDTH_STUDS
	local outlaneWidth = config.OutlaneClearWidth or DEFAULT_OUTLANE_CLEAR_WIDTH_STUDS
	local guideHeight = config.GuideHeight or DEFAULT_GUIDE_HEIGHT_STUDS
	local guideThickness = config.GuideThickness or DEFAULT_GUIDE_THICKNESS_STUDS
	local rolloverEnabled = config.RolloverEnabled ~= false
	local rolloverWidth = config.RolloverWidth or DEFAULT_ROLLOVER_WIDTH_STUDS
	local triggerFraction = config.TriggerFractionAlongPath or DEFAULT_TRIGGER_FRACTION_ALONG_PATH

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "InlaneOutlane",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local path = PathBuilder.Build(options.Origin, config.Path)
	local dividerResult = GuideRailBuilder.BuildWallSegments(path, {
		Height = guideHeight,
		Thickness = guideThickness,
		Material = config.Material or Enum.Material.Metal,
		Color = config.Color or BrickColor.new("Cloudy grey"),
		CollisionGroup = config.CollisionGroup,
		RoundedEndCaps = true,
		SegmentNamePrefix = "DividerWall",
	}, hierarchy.Folders.Colliders)

	local sampleIndex = math.clamp(math.round(triggerFraction * (#path.Samples - 1)) + 1, 1, #path.Samples)
	local sample = path.Samples[sampleIndex]

	local inlaneTrigger: BasePart? = nil
	local outlaneTrigger: BasePart? = nil
	local inlaneLight: LightGenerator.LightAsset? = nil
	local outlaneLight: LightGenerator.LightAsset? = nil

	if rolloverEnabled then
		local inlaneCenter = sample.Position + (sample.Right * (inlaneWidth / 2)) + (sample.Up * (Scale.BALL_DIAMETER_STUDS / 2))
		inlaneTrigger = PrimitiveFactory.CreatePart({
			Name = "InlaneTrigger",
			Size = Vector3.new(rolloverWidth, Scale.BALL_DIAMETER_STUDS, 0.3),
			CFrame = CFrame.fromMatrix(inlaneCenter, sample.Right, sample.Up, -sample.Tangent),
			Role = "Trigger",
			Parent = hierarchy.Folders.Triggers,
		})
		inlaneTrigger.Transparency = 1

		local outlaneCenter = sample.Position - (sample.Right * (outlaneWidth / 2)) + (sample.Up * (Scale.BALL_DIAMETER_STUDS / 2))
		outlaneTrigger = PrimitiveFactory.CreatePart({
			Name = "OutlaneTrigger",
			Size = Vector3.new(rolloverWidth, Scale.BALL_DIAMETER_STUDS, 0.3),
			CFrame = CFrame.fromMatrix(outlaneCenter, sample.Right, sample.Up, -sample.Tangent),
			Role = "Trigger",
			Parent = hierarchy.Folders.Triggers,
		})
		outlaneTrigger.Transparency = 1

		if config.InlaneLightEnabled ~= false then
			inlaneLight = LightGenerator.Generate({
				Name = "InlaneLight",
				Origin = CFrame.fromMatrix(inlaneCenter + (sample.Up * 0.05), sample.Right, sample.Up),
				Parent = hierarchy.Folders.Lights,
				Config = {
					Shape = "Bar",
					Width = 0.5,
					Length = 1.0,
					OnColor = DEFAULT_INLANE_LIGHT_ON_COLOR,
					OffColor = DEFAULT_INLANE_LIGHT_OFF_COLOR,
				},
			})
		end

		if config.OutlaneLightEnabled ~= false then
			outlaneLight = LightGenerator.Generate({
				Name = "OutlaneLight",
				Origin = CFrame.fromMatrix(outlaneCenter + (sample.Up * 0.05), sample.Right, sample.Up),
				Parent = hierarchy.Folders.Lights,
				Config = {
					Shape = "Bar",
					Width = 0.5,
					Length = 1.0,
					OnColor = DEFAULT_OUTLANE_LIGHT_ON_COLOR,
					OffColor = DEFAULT_OUTLANE_LIGHT_OFF_COLOR,
				},
			})
		end
	end

	local attachments: { [string]: Attachment } = {}
	local kickbackAttachment: Attachment? = nil
	if config.OutlaneKickbackAttachment and #path.Samples > 0 then
		local endSample = path.Samples[1]
		local kickbackPosition = endSample.Position - (endSample.Right * (outlaneWidth / 2))
		local attachment = Instance.new("Attachment")
		attachment.Name = "OutlaneKickback"
		attachment.CFrame = CFrame.fromMatrix(kickbackPosition, endSample.Right, endSample.Up, -endSample.Tangent)
		attachment.Parent = hierarchy.Root
		kickbackAttachment = attachment
		attachments.OutlaneKickback = attachment
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = attachments,
		Side = config.Side,
		DividerSegments = dividerResult.Segments,
		InlaneTrigger = inlaneTrigger,
		OutlaneTrigger = outlaneTrigger,
		InlaneLight = inlaneLight,
		OutlaneLight = outlaneLight,
		KickbackAttachment = kickbackAttachment,
		EndCFrame = path.EndCFrame,
		InlaneClearWidth = inlaneWidth,
		OutlaneClearWidth = outlaneWidth,
	}
end

return InlaneOutlaneGenerator
