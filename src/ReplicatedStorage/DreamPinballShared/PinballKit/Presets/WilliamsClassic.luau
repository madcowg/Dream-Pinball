--!strict

-- Default configuration values for every PinballKit asset family, styled after
-- classic Williams-era metal/black/white cabinet parts (spec sections 10, 13).
--
-- Dimension sourcing (spec section 3 -- do not claim Williams-hardware
-- accuracy without a citation):
--   * Ball diameter (1.5 studs / 1.0625in) -- ReferencedPart: the industry-
--     common 1-1/16in pinball size used across most manufacturers, converted
--     through Scale.luau. This is the only dimension in this preset backed by
--     a real-world reference.
--   * Every other dimension below (paddle/bumper/slingshot/target/ramp/
--     insert/button sizes, impulse strengths, cooldowns, colors) is a
--     GameplayDefault: a reasonable starting point chosen for this project,
--     not measured from a specific Williams manual, drawing, or part. Treat
--     every one of them as freely tunable per cabinet.
--
-- Every preset below is cast (`:: SomeGenerator.SomeConfig`) to its
-- generator's Config type. This isn't decorative: without it, string-literal
-- fields (Shape, Kind, SideRailType, Direction) widen to plain `string` when
-- written without a contextual type, which fails strict type-checking
-- wherever the preset is later passed as that generator's typed Config
-- argument.

local RailGenerator = require(script.Parent.Parent.Generators.RailGenerator)
local RampGenerator = require(script.Parent.Parent.Generators.RampGenerator)
local SpinnerGenerator = require(script.Parent.Parent.Generators.SpinnerGenerator)
local BumperGenerator = require(script.Parent.Parent.Generators.BumperGenerator)
local SlingshotGenerator = require(script.Parent.Parent.Generators.SlingshotGenerator)
local TargetGenerator = require(script.Parent.Parent.Generators.TargetGenerator)
local LightGenerator = require(script.Parent.Parent.Generators.LightGenerator)
local ButtonGenerator = require(script.Parent.Parent.Generators.ButtonGenerator)
local FlipperGenerator = require(script.Parent.Parent.Generators.FlipperGenerator)
local RoutingGenerator = require(script.Parent.Parent.Generators.RoutingGenerator)
local CaptiveGenerator = require(script.Parent.Parent.Generators.CaptiveGenerator)
local ObstacleGenerator = require(script.Parent.Parent.Generators.ObstacleGenerator)
local LaneGenerator = require(script.Parent.Parent.Generators.LaneGenerator)

local WilliamsClassic = {}

local METAL = Enum.Material.Metal
local CLOUDY_GREY = BrickColor.new("Cloudy grey")

WilliamsClassic.URail = {
	InnerDiameter = 1.7,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: RailGenerator.UHalfPipeConfig

WilliamsClassic.MacaroniTunnel = {
	InnerDiameter = 1.7,
	EntranceFlareLength = 1.5,
	ExitFlareLength = 1.5,
	IncludeOccupancyTrigger = true,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: RailGenerator.MacaroniTunnelConfig

WilliamsClassic.WireRail = {
	Kind = "Single",
	WireDiameter = 0.15,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: RailGenerator.WireRailConfig

WilliamsClassic.Ramp = {
	Width = 4,
	Length = 10,
	Thickness = 0.4,
	SideRailType = "Wall",
	SideRailHeight = 1.2,
	EntryTransitionLength = 2,
	ExitTransitionLength = 2,
	SurfaceMaterial = Enum.Material.SmoothPlastic,
	SurfaceColor = BrickColor.new("Institutional white"),
} :: RampGenerator.RampConfig

WilliamsClassic.Spinner = {
	PaddleWidth = 3,
	PaddleHeight = 1.5,
	PaddleThickness = 0.15,
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("Bright red"),
} :: SpinnerGenerator.SpinnerConfig

WilliamsClassic.SpinnerRuntime = {
	ScoreThresholdRadPerSecond = 8,
	CooldownSeconds = 0.3,
}

WilliamsClassic.PopBumper = {
	BaseDiameter = 3.5,
	BodyDiameter = 2.5,
	BodyHeight = 1.2,
	CapColor = BrickColor.new("White"),
	LightColor = Color3.fromRGB(255, 60, 40),
	IncludeCapLight = true,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: BumperGenerator.BumperConfig

WilliamsClassic.PopBumperRuntime = {
	-- Matches GameplayTuning.BUMPER_KICK_STRENGTH (this project's existing
	-- bumper kick, not a value invented independently for PinballKit).
	OutwardImpulse = 30,
	UpwardImpulse = 6,
	CooldownSeconds = 0.15,
}

WilliamsClassic.Slingshot = {
	Width = 3,
	Depth = 2,
	Height = 2,
	IncludeLights = true,
	LightColor = Color3.fromRGB(255, 220, 80),
	Material = METAL,
	Color = CLOUDY_GREY,
} :: SlingshotGenerator.SlingshotConfig

WilliamsClassic.SlingshotRuntime = {
	OutwardImpulse = 50,
	CooldownSeconds = 0.15,
}

WilliamsClassic.HideawayTarget = {
	Width = 1.5,
	Height = 1.5,
	Thickness = 0.3,
	IncludeLight = true,
	LightColor = Color3.fromRGB(255, 255, 255),
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("White"),
} :: TargetGenerator.TargetConfig

WilliamsClassic.HideawayTargetRuntime = {
	AutoResetDelaySeconds = 3,
	CooldownSeconds = 0.5,
}

WilliamsClassic.RoundInsert = {
	Shape = "Round",
	Diameter = 1.5,
	OnColor = Color3.fromRGB(255, 220, 80),
	OffColor = Color3.fromRGB(60, 55, 40),
} :: LightGenerator.LightConfig

WilliamsClassic.BarInsert = {
	Shape = "Bar",
	Width = 1,
	Length = 3,
	OnColor = Color3.fromRGB(80, 200, 255),
	OffColor = Color3.fromRGB(40, 50, 60),
} :: LightGenerator.LightConfig

WilliamsClassic.RingInsert = {
	Shape = "Ring",
	Diameter = 2,
	RingThickness = 0.3,
	OnColor = Color3.fromRGB(255, 90, 200),
	OffColor = Color3.fromRGB(55, 40, 50),
} :: LightGenerator.LightConfig

WilliamsClassic.CabinetButton = {
	ActionText = "Press",
	OnColor = Color3.fromRGB(255, 60, 40),
	OffColor = Color3.fromRGB(40, 20, 20),
	IncludeLight = true,
	Material = METAL,
	Color = BrickColor.new("Really black"),
} :: ButtonGenerator.ButtonConfig

WilliamsClassic.CabinetButtonRuntime = {
	DebounceSeconds = 0.4,
}

-- Flipper: FlipperSize/RestAngleDegrees/UpAngleDegrees still match
-- CabinetLayouts.SHARED_FLIPPER_CONFIG (the shape/range of motion wasn't the
-- problem). Density/MotorTorquePerMass are deliberately heavier/stronger than
-- that locked baseline -- live playtesting found the baseline flippers
-- under-hit the ball; see FlipperGenerator.luau's header comment for the
-- reasoning. Side is intentionally omitted (per-instance, not shareable) --
-- pass it via Presets.Extend, along with CollisionGroup.
WilliamsClassic.Flipper = {
	Side = "Left",
	FlipperSize = Vector3.new(7.5, 1.25, 2.5),
	RestAngleDegrees = -45,
	UpAngleDegrees = 45,
	MotorTorquePerMass = 3400,
	Density = 4.5,
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("Bright red"),
} :: FlipperGenerator.FlipperConfig

-- MotorSpeed: ~33% faster than GameplayTuning.FLIPPER_MOTOR_SPEED (12) for
-- the same reason -- see FlipperController.luau.
WilliamsClassic.FlipperRuntime = {
	MotorSpeed = 16,
}

-- Ball: matches CabinetDesignsTest.server.luau's LaunchBall exactly (density
-- 2.75 / friction 0.35 / elasticity 0.65) -- see BallGenerator.luau's header
-- comment on the ongoing PhysicsTestRig investigation into this tuning.
WilliamsClassic.Ball = {
	Density = 2.75,
	Friction = 0.35,
	Elasticity = 0.65,
	Color = Color3.fromRGB(220, 220, 60),
}

WilliamsClassic.StandupTarget = {
	Width = 1.2,
	Height = 1.5,
	Thickness = 0.2,
	IncludeLight = true,
	LightColor = Color3.fromRGB(255, 255, 255),
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("White"),
} :: TargetGenerator.StandupTargetConfig

WilliamsClassic.StandupTargetRuntime = {
	CooldownSeconds = 0.3,
}

WilliamsClassic.DropTargetBank = {
	TargetCount = 3,
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("White"),
} :: TargetGenerator.DropTargetBankConfig

WilliamsClassic.DropTargetBankRuntime = {
	DownAngleDegrees = 80,
	CooldownSeconds = 0.2,
}

WilliamsClassic.Gate = {
	Material = METAL,
	Color = CLOUDY_GREY,
} :: RoutingGenerator.GateConfig

WilliamsClassic.Diverter = {
	Material = METAL,
	Color = CLOUDY_GREY,
} :: RoutingGenerator.DiverterConfig

WilliamsClassic.KickoutHole = {
	Radius = 1.6,
	RimHeight = 1.4,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: CaptiveGenerator.CaptivePocketConfig

WilliamsClassic.KickoutHoleRuntime = {
	CaptureDelaySeconds = 0.6,
	KickStrength = 55,
	KickDirectionLocal = Vector3.new(0, 1, 0.3),
}

WilliamsClassic.BallTrough = {
	Radius = 1.7,
	RimHeight = 0.8,
	Material = METAL,
	Color = CLOUDY_GREY,
} :: CaptiveGenerator.CaptivePocketConfig

WilliamsClassic.BallTroughRuntime = {
	CaptureDelaySeconds = 0.4,
	KickStrength = 35,
	KickDirectionLocal = Vector3.new(0, 0.3, 1),
}

WilliamsClassic.RubberPost = {
	Material = Enum.Material.SmoothPlastic,
	Color = BrickColor.new("Really black"),
} :: ObstacleGenerator.RubberPostConfig

WilliamsClassic.Rollover = {
	IncludeLight = true,
	LightColor = Color3.fromRGB(255, 255, 255),
	Color = BrickColor.new("Institutional white"),
} :: ObstacleGenerator.RolloverConfig

WilliamsClassic.RolloverRuntime = {
	CooldownSeconds = 0.5,
}

WilliamsClassic.LaneDivider = {
	Material = METAL,
	Color = BrickColor.new("Really black"),
} :: LaneGenerator.LaneDividerConfig

return WilliamsClassic
