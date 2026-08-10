--!strict

-- Non-scale constants shared by every PinballKit generator, runtime controller,
-- and validator: the generated-model contract (spec section 6), quality-level
-- geometry targets (spec section 8), and default Williams-classic materials
-- (spec section 10). Ball/inch/stud scale lives in Scale.luau, not here.

local Types = require(script.Parent.Types)

local Constants = {}

Constants.LIBRARY_VERSION = "0.2.0"
Constants.GENERATED_BY = "PinballKit"

-- Root container every generator parents its models into by default (spec
-- section 12). Callers may override via GenerateOptions.Parent.
Constants.DEFAULT_CONTAINER_NAME = "GeneratedPinballAssets"

-- Standard generated-model hierarchy (spec section 6). Root is not listed here:
-- it is the model's PrimaryPart, not a folder.
Constants.STANDARD_HIERARCHY_FOLDERS = {
	"Visuals",
	"Colliders",
	"Triggers",
	"Mechanism",
	"Lights",
	"Attachments",
}

-- Exact attribute keys applied to every generated asset's root Model.
Constants.ASSET_ATTRIBUTES = {
	PinballAsset = "PinballAsset",
	AssetType = "AssetType",
	AssetVersion = "AssetVersion",
	PresetName = "PresetName",
	BallDiameter = "BallDiameter",
	GeneratedBy = "GeneratedBy",
	GenerationId = "GenerationId",
}

-- Attribute key scoring-capable generators (Bumper, Slingshot, Spinner,
-- Standup/DropTarget, Rollover) stamp onto their root Model when
-- Config.PointValue is set. Game-integration code (e.g. CabinetGameplay.luau)
-- reads this instead of hardcoding one flat score-per-hit constant, so each
-- placed instance can award a different amount -- previously a single global
-- placeholder value applied identically everywhere.
Constants.POINT_VALUE_ATTRIBUTE = "PointValue"

-- Longitudinal collider overlap along the direction of travel (spec section 8).
Constants.SEGMENT_OVERLAP_MIN_STUDS = 0.05
Constants.SEGMENT_OVERLAP_MAX_STUDS = 0.1
Constants.DEFAULT_SEGMENT_OVERLAP_STUDS = 0.075

-- Per-quality path/profile resolution targets. Gameplay-tuned defaults, not
-- Williams hardware values -- tune freely as generators are built and tested.
export type QualitySegmentParams = {
	MaxSegmentLength: number,
	MaxSagittaError: number,
	ProfileSegments: number,
}

local qualitySegmentParams: { [Types.Quality]: QualitySegmentParams } = {
	Low = { MaxSegmentLength = 2, MaxSagittaError = 0.15, ProfileSegments = 6 },
	Medium = { MaxSegmentLength = 1, MaxSagittaError = 0.05, ProfileSegments = 10 },
	High = { MaxSegmentLength = 0.5, MaxSagittaError = 0.02, ProfileSegments = 16 },
}
Constants.QUALITY_SEGMENT_PARAMS = qualitySegmentParams

local defaultQuality: Types.Quality = "Medium"
Constants.DEFAULT_QUALITY = defaultQuality

-- Default Williams-classic appearance (spec section 10). Configurable per asset.
Constants.DEFAULT_METAL_MATERIAL = Enum.Material.Metal
Constants.DEFAULT_METAL_COLOR = BrickColor.new("Cloudy grey")
Constants.DEFAULT_BASE_MATERIAL = Enum.Material.SmoothPlastic
Constants.DEFAULT_BASE_COLOR = BrickColor.new("Really black")

return Constants
