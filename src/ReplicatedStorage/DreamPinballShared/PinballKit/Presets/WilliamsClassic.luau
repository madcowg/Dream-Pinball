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
	OutwardImpulse = 45,
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

return WilliamsClassic
