--!strict

-- PinballKit entry point: aggregates every submodule behind one require for
-- convenience (Command Bar bootstraps, the demo layout, README examples).
-- Individual modules can still be required directly by path when only one is
-- needed -- this file adds nothing beyond the references below.

local PinballKit = {}

PinballKit.Scale = require(script.Scale)
PinballKit.Constants = require(script.Constants)
PinballKit.Types = require(script.Types)

PinballKit.Validation = {
	GeometryValidator = require(script.Validation.GeometryValidator),
	AssetValidator = require(script.Validation.AssetValidator),
	LowerPlayfieldValidator = require(script.Validation.LowerPlayfieldValidator),
}

PinballKit.Geometry = {
	ArcMath = require(script.Geometry.ArcMath),
	PathFrames = require(script.Geometry.PathFrames),
	PathBuilder = require(script.Geometry.PathBuilder),
	PrimitiveFactory = require(script.Geometry.PrimitiveFactory),
	ProfileSweep = require(script.Geometry.ProfileSweep),
	MirrorTransform = require(script.Geometry.MirrorTransform),
	LanePath = require(script.Geometry.LanePath),
	GuideRailBuilder = require(script.Geometry.GuideRailBuilder),
	FlipperGeometry = require(script.Geometry.FlipperGeometry),
}

PinballKit.Generators = {
	RailGenerator = require(script.Generators.RailGenerator),
	RampGenerator = require(script.Generators.RampGenerator),
	SpinnerGenerator = require(script.Generators.SpinnerGenerator),
	BumperGenerator = require(script.Generators.BumperGenerator),
	SlingshotGenerator = require(script.Generators.SlingshotGenerator),
	TargetGenerator = require(script.Generators.TargetGenerator),
	LightGenerator = require(script.Generators.LightGenerator),
	ButtonGenerator = require(script.Generators.ButtonGenerator),
	BallGenerator = require(script.Generators.BallGenerator),
	FlipperGenerator = require(script.Generators.FlipperGenerator),
	RoutingGenerator = require(script.Generators.RoutingGenerator),
	CaptiveGenerator = require(script.Generators.CaptiveGenerator),
	ObstacleGenerator = require(script.Generators.ObstacleGenerator),
	LaneGenerator = require(script.Generators.LaneGenerator),
	InlaneOutlaneGenerator = require(script.Generators.InlaneOutlaneGenerator),
	LowerPlayfieldGenerator = require(script.Generators.LowerPlayfieldGenerator),
}

PinballKit.Presets = require(script.Presets)

PinballKit.Runtime = {
	ComponentRegistry = require(script.Runtime.ComponentRegistry),
	SpinnerController = require(script.Runtime.SpinnerController),
	BumperController = require(script.Runtime.BumperController),
	SlingshotController = require(script.Runtime.SlingshotController),
	TargetController = require(script.Runtime.TargetController),
	LightController = require(script.Runtime.LightController),
	ButtonController = require(script.Runtime.ButtonController),
	FlipperController = require(script.Runtime.FlipperController),
	StandupTargetController = require(script.Runtime.StandupTargetController),
	DropTargetController = require(script.Runtime.DropTargetController),
	RoutingController = require(script.Runtime.RoutingController),
	CaptiveController = require(script.Runtime.CaptiveController),
	RolloverController = require(script.Runtime.RolloverController),
	LaneSwitchController = require(script.Runtime.LaneSwitchController),
	LowerPlayfieldController = require(script.Runtime.LowerPlayfieldController),
}

-- Demo/GenerateLowerPlayfieldTest require their leaf dependencies directly
-- (not this aggregator) to avoid a circular require: these lines only work
-- because the cycle runs the other way, never back through here.
PinballKit.Demo = require(script.Demo.DemoLayout)
PinballKit.LowerPlayfieldTest = require(script.Demo.GenerateLowerPlayfieldTest)

return PinballKit
