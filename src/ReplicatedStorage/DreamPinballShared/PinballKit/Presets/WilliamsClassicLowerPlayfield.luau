--!strict

-- Default configuration for the new lower-playfield family (spec sections
-- 2-3). A separate preset family from WilliamsClassic.luau on purpose --
-- WilliamsClassic.Flipper/.Slingshot/.LaneDivider stay exactly as they are
-- (still used elsewhere, e.g. the Demo and any future WilliamsCabinet-style
-- work) and are not touched here.
--
-- Dimension sourcing (spec section 3):
--   * Flipper length (3in / 4.2353 studs) -- ReferencedPart (standard
--     Williams/Bally "Flipper Bat 3 Inch"), via Scale.STUDS_PER_INCH.
--   * Slingshot rubber cross-section (0.1875in / 0.2647 studs) --
--     ReferencedPart (spec's reference table).
--   * Inlane/outlane clear width (1.85 studs), center drain width (1.85
--     studs), minimum lane/gap width (1.70 studs), flipper stroke (50
--     degrees) -- GameplayDefault, per spec section 2's own framing.
--   * Everything else (colors, post triangle, layout offsets) --
--     GameplayDefault, freely tunable per cabinet.

local FlipperGenerator = require(script.Parent.Parent.Generators.FlipperGenerator)
local SlingshotGenerator = require(script.Parent.Parent.Generators.SlingshotGenerator)
local InlaneOutlaneGenerator = require(script.Parent.Parent.Generators.InlaneOutlaneGenerator)
local LowerPlayfieldGenerator = require(script.Parent.Parent.Generators.LowerPlayfieldGenerator)

local WilliamsClassicLowerPlayfield = {}

local METAL = Enum.Material.Metal
local CLOUDY_GREY = BrickColor.new("Cloudy grey")
local STUDS_PER_INCH = 1.5 / 1.0625

-- Side is intentionally a placeholder (overridden per-instance by
-- LowerPlayfieldGenerator, same convention as WilliamsClassic.Flipper).
WilliamsClassicLowerPlayfield.Flipper = {
	Side = "Left",
	FlipperSize = Vector3.new(3 * STUDS_PER_INCH, 0.9, 1.6),
	RestAngleDegrees = -30,
	UpAngleDegrees = 50,
	ColliderMode = "SegmentedCapsule",
	RootRadius = 0.55,
	TipRadius = 0.4,
	ColliderOverlap = 0.2,
	MotorTorquePerMass = 3400,
	Density = 4.5,
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("Institutional white"),
	RubberColor = Color3.fromRGB(35, 35, 35),
	ShaftMaterial = Enum.Material.Metal,
} :: FlipperGenerator.FlipperConfig

WilliamsClassicLowerPlayfield.FlipperRuntime = {
	MotorSpeed = 16,
}

WilliamsClassicLowerPlayfield.Slingshot = {
	Width = 3,
	Depth = 2,
	Height = 2,
	-- A reasonable default triangle footprint (GameplayDefault) -- override
	-- per cabinet; validated non-degenerate/sufficiently spaced by
	-- SlingshotGenerator itself.
	PostPositions = { Vector2.new(0, 0), Vector2.new(2.6, 0), Vector2.new(1.3, 2.2) },
	ActiveSegmentIndex = 1,
	RubberCrossSectionStuds = 0.1875 * STUDS_PER_INCH,
	PostRadius = 0.25,
	PostHeight = 1.6,
	IncludeLights = true,
	LightColor = Color3.fromRGB(255, 220, 80),
	Material = METAL,
	Color = CLOUDY_GREY,
	PlasticColor = Color3.fromRGB(240, 240, 230),
	PlasticTransparency = 0.15,
} :: SlingshotGenerator.SlingshotConfig

WilliamsClassicLowerPlayfield.SlingshotRuntime = {
	OutwardImpulse = 50,
	CooldownSeconds = 0.15,
}

-- Path is overridden per-instance by LowerPlayfieldGenerator (Length solved
-- from the composed layout) -- the value here only satisfies the Config
-- type for direct/standalone use of InlaneOutlaneGenerator.
WilliamsClassicLowerPlayfield.Lanes = {
	Side = "Left",
	Path = { PathType = "Straight", Length = 10 },
	InlaneClearWidth = 1.85,
	OutlaneClearWidth = 1.85,
	MinimumClearance = 1.70,
	GuideHeight = 2.25,
	GuideThickness = 0.3,
	Material = METAL,
	Color = CLOUDY_GREY,
	RolloverEnabled = true,
	RolloverCooldown = 0.10,
	InlaneLightEnabled = true,
	OutlaneLightEnabled = true,
	OutlaneKickbackAttachment = false,
} :: InlaneOutlaneGenerator.InlaneOutlaneConfig

WilliamsClassicLowerPlayfield.LowerPlayfield = {
	Flipper = WilliamsClassicLowerPlayfield.Flipper,
	Slingshot = WilliamsClassicLowerPlayfield.Slingshot,
	Lanes = WilliamsClassicLowerPlayfield.Lanes,
	DesiredCenterDrainWidth = 1.85,
	MinimumCenterDrainWidth = 1.70,
	FlipperForwardOffset = 4,
	SlingshotForwardOffset = 6,
	SlingshotLateralOffset = 1,
	LaneTailPastOrigin = 4,
} :: LowerPlayfieldGenerator.LowerPlayfieldConfig

WilliamsClassicLowerPlayfield.LowerPlayfieldRuntime = {
	FlipperMotorSpeed = 16,
	SlingshotOutwardImpulse = 50,
	SlingshotCooldownSeconds = 0.15,
	LaneCooldownSeconds = 0.10,
}

return WilliamsClassicLowerPlayfield
