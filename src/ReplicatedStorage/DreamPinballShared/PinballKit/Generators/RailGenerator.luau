--!strict

-- Wire rails, U-shaped half-pipe rails, and macaroni tunnels (spec section 8).
-- All three are the same "sweep a circular profile along a path" operation
-- from ProfileSweep -- only CoverageDegrees (180 vs 360) and whether the
-- surface is solid panels (rail/tunnel) or thin cylinders (wire) differ.
--
-- This module implements the U-shaped half-pipe (spec's highest-priority
-- geometry item, per implementation order stage 3). Wire rails and the
-- macaroni tunnel are added alongside it in the following stages, through the
-- same GenerateUHalfPipe-style API shape.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local ProfileSweep = require(script.Parent.Parent.Geometry.ProfileSweep)
local PathBuilder = require(script.Parent.Parent.Geometry.PathBuilder)
local PathFrames = require(script.Parent.Parent.Geometry.PathFrames)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local RailGenerator = {}

export type UHalfPipeConfig = {
	Path: PathBuilder.PathSpec,
	InnerDiameter: number?,
	PanelThickness: number?,
	ProfilePanelCount: number?,
	Quality: Types.Quality?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local UHALF_PIPE_COVERAGE_DEGREES = 180

local function validateConfig(config: UHalfPipeConfig)
	local innerDiameter = config.InnerDiameter or Scale.DEFAULT_INNER_DIAMETER_STUDS
	local innerOk, innerErr = Scale.ValidateInnerDiameter(innerDiameter)

	GeometryValidator.AssertAll({
		{ ok = innerOk, err = innerErr },
	}, "RailGenerator.GenerateUHalfPipe")
end

-- Creates an Attachment on a small invisible anchor Part inside the
-- Attachments folder, positioned at `cframe`. Anchor parts move correctly with
-- the model via Model:PivotTo/SetPrimaryPartCFrame (both reposition every
-- descendant part regardless of anchoring), which plain Attachments parented
-- to a Folder would not.
local function createPlacementAttachment(attachmentsFolder: Folder, name: string, cframe: CFrame): Attachment
	local anchorPart = Instance.new("Part")
	anchorPart.Name = name
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame = cframe
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.Transparency = 1
	anchorPart.Parent = attachmentsFolder

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = anchorPart

	return attachment
end

function RailGenerator.GenerateUHalfPipe(options: Types.GenerateOptions<UHalfPipeConfig>): Types.GeneratedAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "UHalfPipeRail"
	local innerDiameter = config.InnerDiameter or Scale.DEFAULT_INNER_DIAMETER_STUDS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "UHalfPipeRail",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local path = PathBuilder.Build(options.Origin, config.Path)

	ProfileSweep.Sweep({
		Path = path,
		InnerDiameterStart = innerDiameter,
		CoverageDegrees = UHALF_PIPE_COVERAGE_DEGREES,
		PanelThickness = config.PanelThickness,
		ProfilePanelCount = config.ProfilePanelCount,
		Quality = config.Quality,
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
		Material = config.Material,
		Color = config.Color,
		NamePrefix = "TroughPanel",
	})

	local entryAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "EntryAttachment", path.StartCFrame)
	local exitAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "ExitAttachment", path.EndCFrame)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {
			Entry = entryAttachment,
			Exit = exitAttachment,
		},
	}
end

--------------------------------------------------------------------------------
-- Macaroni tunnel: same ProfileSweep at 360-degree coverage, plus optional
-- flared entrance/exit transitions and an optional occupancy trigger.
--------------------------------------------------------------------------------

local MACARONI_COVERAGE_DEGREES = 360
local DEFAULT_FLARE_DIAMETER_MULTIPLIER = 1.4

export type MacaroniTunnelConfig = {
	Path: PathBuilder.PathSpec,
	InnerDiameter: number?,
	PanelThickness: number?,
	ProfilePanelCount: number?,
	Quality: Types.Quality?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	EntranceFlareLength: number?,
	ExitFlareLength: number?,
	FlareDiameterMultiplier: number?,
	IncludeOccupancyTrigger: boolean?,
}

local function validateTunnelConfig(config: MacaroniTunnelConfig)
	local innerDiameter = config.InnerDiameter or Scale.DEFAULT_INNER_DIAMETER_STUDS
	local innerOk, innerErr = Scale.ValidateInnerDiameter(innerDiameter)

	local flareOk, flareErr = true, nil
	if config.EntranceFlareLength ~= nil then
		flareOk, flareErr = GeometryValidator.ValidatePositive(config.EntranceFlareLength, "EntranceFlareLength")
	end

	local exitFlareOk, exitFlareErr = true, nil
	if config.ExitFlareLength ~= nil then
		exitFlareOk, exitFlareErr = GeometryValidator.ValidatePositive(config.ExitFlareLength, "ExitFlareLength")
	end

	GeometryValidator.AssertAll({
		{ ok = innerOk, err = innerErr },
		{ ok = flareOk, err = flareErr },
		{ ok = exitFlareOk, err = exitFlareErr },
	}, "RailGenerator.GenerateMacaroniTunnel")
end

-- One coarse, non-colliding trigger box per main-path segment, sized to sit
-- just inside the tunnel bore. Approximate on curved paths (each box is
-- straight), which is acceptable for an occupancy sensor that never contacts
-- the ball physically.
local function buildOccupancyTriggers(path: PathFrames.PathResult, innerDiameter: number, parent: Folder, collisionGroup: string?)
	local samples = path.Samples
	local boreSize = innerDiameter * 0.95

	for segmentIndex = 1, #samples - 1 do
		local startSample = samples[segmentIndex]
		local endSample = samples[segmentIndex + 1]
		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local midpointPosition = (startSample.Position + endSample.Position) / 2
		local rotationOnly = startSample.CFrame - startSample.Position

		PrimitiveFactory.CreatePart({
			Name = string.format("OccupancyTrigger_%d", segmentIndex),
			Size = Vector3.new(boreSize, boreSize, segmentLength),
			CFrame = CFrame.new(midpointPosition) * rotationOnly,
			Role = "Trigger",
			Parent = parent,
			CollisionGroup = collisionGroup,
		})
	end
end

function RailGenerator.GenerateMacaroniTunnel(options: Types.GenerateOptions<MacaroniTunnelConfig>): Types.GeneratedAsset
	local config = options.Config
	validateTunnelConfig(config)

	local name = options.Name or "MacaroniTunnel"
	local innerDiameter = config.InnerDiameter or Scale.DEFAULT_INNER_DIAMETER_STUDS
	local flareMultiplier = config.FlareDiameterMultiplier or DEFAULT_FLARE_DIAMETER_MULTIPLIER

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "MacaroniTunnel",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local mainPath = PathBuilder.Build(options.Origin, config.Path)

	local function sweepSection(path: PathFrames.PathResult, innerDiameterStart: number, innerDiameterEnd: number, namePrefix: string)
		ProfileSweep.Sweep({
			Path = path,
			InnerDiameterStart = innerDiameterStart,
			InnerDiameterEnd = innerDiameterEnd,
			CoverageDegrees = MACARONI_COVERAGE_DEGREES,
			NamePrefix = namePrefix,
			PanelThickness = config.PanelThickness,
			ProfilePanelCount = config.ProfilePanelCount,
			Quality = config.Quality,
			Parent = hierarchy.Folders.Colliders,
			CollisionGroup = config.CollisionGroup,
			Material = config.Material,
			Color = config.Color,
		})
	end

	sweepSection(mainPath, innerDiameter, innerDiameter, "TunnelPanel")

	local entryCFrame = mainPath.StartCFrame
	local exitCFrame = mainPath.EndCFrame

	local entranceFlareLength = config.EntranceFlareLength
	if entranceFlareLength ~= nil and entranceFlareLength > 0 then
		local flareStartCFrame = mainPath.StartCFrame * CFrame.new(0, 0, entranceFlareLength)
		local flarePath = PathFrames.BuildStraightPath(flareStartCFrame, entranceFlareLength, { Quality = config.Quality })

		sweepSection(flarePath, innerDiameter * flareMultiplier, innerDiameter, "TunnelEntranceFlare")

		entryCFrame = flarePath.StartCFrame
	end

	local exitFlareLength = config.ExitFlareLength
	if exitFlareLength ~= nil and exitFlareLength > 0 then
		local flarePath = PathFrames.BuildStraightPath(mainPath.EndCFrame, exitFlareLength, { Quality = config.Quality })

		sweepSection(flarePath, innerDiameter, innerDiameter * flareMultiplier, "TunnelExitFlare")

		exitCFrame = flarePath.EndCFrame
	end

	if config.IncludeOccupancyTrigger then
		buildOccupancyTriggers(mainPath, innerDiameter, hierarchy.Folders.Triggers, config.CollisionGroup)
	end

	local entryAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "EntryAttachment", entryCFrame)
	local exitAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "ExitAttachment", exitCFrame)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {
			Entry = entryAttachment,
			Exit = exitAttachment,
		},
	}
end

--------------------------------------------------------------------------------
-- Wire rails: single wire, two-wire guide, parallel rail, elevated wireform.
-- All four are the same underlying geometry (one or two thin cylinders swept
-- along a path) -- Kind picks wire count/spacing defaults, ElevationStuds
-- lifts the whole wireform above the path's nominal height.
--------------------------------------------------------------------------------

local DEFAULT_WIRE_DIAMETER_STUDS = 0.15
local DEFAULT_TWO_WIRE_SPACING_STUDS = 1.0
local DEFAULT_PARALLEL_SPACING_STUDS = 1.9

export type WireRailKind = "Single" | "TwoWire" | "Parallel"

export type WireRailConfig = {
	Path: PathBuilder.PathSpec,
	Kind: WireRailKind,
	WireDiameter: number?,
	WireSpacing: number?,
	ElevationStuds: number?,
	Quality: Types.Quality?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
}

local function validateWireRailConfig(config: WireRailConfig)
	local diameterOk, diameterErr =
		GeometryValidator.ValidatePositive(config.WireDiameter or DEFAULT_WIRE_DIAMETER_STUDS, "WireDiameter")

	GeometryValidator.AssertAll({
		{ ok = diameterOk, err = diameterErr },
	}, "RailGenerator.GenerateWireRail")
end

local function defaultWireSpacing(kind: WireRailKind): number
	if kind == "Parallel" then
		return DEFAULT_PARALLEL_SPACING_STUDS
	end
	return DEFAULT_TWO_WIRE_SPACING_STUDS
end

-- One overlapping cylinder segment per path sample-pair, offset from the path
-- centerline by `lateralOffset` (along Right) and `elevation` (along Up).
-- Cylinder parts run along their local X axis, so the path tangent is mapped
-- to vX in the CFrame the part is given.
local function buildWireSegments(
	path: PathFrames.PathResult,
	diameter: number,
	lateralOffset: number,
	elevation: number,
	parent: Folder,
	material: Enum.Material?,
	color: BrickColor?,
	collisionGroup: string?,
	namePrefix: string
)
	local samples = path.Samples
	local overlap = Constants.DEFAULT_SEGMENT_OVERLAP_STUDS

	for segmentIndex = 1, #samples - 1 do
		local startSample = samples[segmentIndex]
		local endSample = samples[segmentIndex + 1]
		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local midpointPosition = (startSample.Position + endSample.Position) / 2
			+ (startSample.Right * lateralOffset)
			+ (startSample.Up * elevation)

		PrimitiveFactory.CreatePart({
			Name = string.format("%s_%d", namePrefix, segmentIndex),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(segmentLength + overlap, diameter, diameter),
			-- 3-arg fromMatrix derives a proper right-handed third axis; a
			-- cylinder is rotationally symmetric about vX so the exact
			-- vY/vZ choice doesn't matter, only that the basis stays valid.
			CFrame = CFrame.fromMatrix(midpointPosition, startSample.Tangent, startSample.Right),
			Role = "Collider",
			Material = material,
			Color = color,
			Parent = parent,
			CollisionGroup = collisionGroup,
		})
	end
end

function RailGenerator.GenerateWireRail(options: Types.GenerateOptions<WireRailConfig>): Types.GeneratedAsset
	local config = options.Config
	validateWireRailConfig(config)

	local name = options.Name or "WireRail"
	local diameter = config.WireDiameter or DEFAULT_WIRE_DIAMETER_STUDS
	local elevation = config.ElevationStuds or 0
	local spacing = config.WireSpacing or defaultWireSpacing(config.Kind)

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "WireRail",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local path = PathBuilder.Build(options.Origin, config.Path)

	if config.Kind == "Single" then
		buildWireSegments(
			path,
			diameter,
			0,
			elevation,
			hierarchy.Folders.Colliders,
			config.Material,
			config.Color,
			config.CollisionGroup,
			"Wire"
		)
	else
		buildWireSegments(
			path,
			diameter,
			-spacing / 2,
			elevation,
			hierarchy.Folders.Colliders,
			config.Material,
			config.Color,
			config.CollisionGroup,
			"WireLeft"
		)
		buildWireSegments(
			path,
			diameter,
			spacing / 2,
			elevation,
			hierarchy.Folders.Colliders,
			config.Material,
			config.Color,
			config.CollisionGroup,
			"WireRight"
		)
	end

	local entryAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "EntryAttachment", path.StartCFrame)
	local exitAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "ExitAttachment", path.EndCFrame)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {
			Entry = entryAttachment,
			Exit = exitAttachment,
		},
	}
end

return RailGenerator
