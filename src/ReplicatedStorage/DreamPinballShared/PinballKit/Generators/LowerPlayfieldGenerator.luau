--!strict

-- Composes one canonical Left lower-playfield side (flipper, slingshot,
-- inlane/outlane) and mirrors it for Right (spec section 6/16). Every piece
-- is generated through its own standalone generator -- this module only
-- solves layout (flipper pivot spacing for the desired center-drain gap,
-- slingshot/lane placement relative to it) and assembles the result.
--
-- Scope note: this builds a straight-lane approximation of the reference
-- layout (spec section 3's diagram), not the exact curved-lead-in topology
-- the WilliamsCabinet-specific migration doc explores for one hand-built
-- cabinet. That curve is a real, documented refinement for later -- this
-- generator is deliberately generic (works for any Origin, not tied to any
-- one cabinet's markers) and gameplay-tuned defaults are called out as such,
-- matching spec section 2's own sourcing rule.
--
-- Origin convention (spec section 4): local +X right, +Y playfield normal,
-- +Z uphill, -Z downfield/toward the drain -- derived entirely from the
-- supplied Origin CFrame, never a hardcoded world axis.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local FlipperGeometry = require(script.Parent.Parent.Geometry.FlipperGeometry)
local FlipperGenerator = require(script.Parent.FlipperGenerator)
local SlingshotGenerator = require(script.Parent.SlingshotGenerator)
local InlaneOutlaneGenerator = require(script.Parent.InlaneOutlaneGenerator)
local Constants = require(script.Parent.Parent.Constants)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local LowerPlayfieldGenerator = {}

-- Gameplay-tuned layout defaults (spec section 2) -- not Williams factory
-- dimensions. All tunable per instance.
local DEFAULT_DESIRED_CENTER_DRAIN_WIDTH_STUDS = 1.85
local DEFAULT_MINIMUM_CENTER_DRAIN_WIDTH_STUDS = 1.70
local DEFAULT_FLIPPER_FORWARD_OFFSET_STUDS = 4
local DEFAULT_SLINGSHOT_FORWARD_OFFSET_STUDS = 6
local DEFAULT_SLINGSHOT_LATERAL_OFFSET_STUDS = 1
local DEFAULT_LANE_TAIL_PAST_ORIGIN_STUDS = 4
local DEFAULT_FLIPPER_LENGTH_STUDS = 4.2353 -- 3 real inches, see Scale.STUDS_PER_INCH
local DEFAULT_REST_ANGLE_DEGREES = -30
local DEFAULT_TIP_RADIUS_STUDS = 0.45
local DEFAULT_DRAIN_DOWNFIELD_OFFSET_STUDS = 1
local DEFAULT_DRAIN_HEIGHT_STUDS = Scale.BALL_DIAMETER_STUDS * 2

export type LowerPlayfieldConfig = {
	-- Side is overridden internally per side on all three of these; pass the
	-- shared/left-canonical values here (matching how WilliamsClassic.Flipper
	-- omits Side too).
	Flipper: FlipperGenerator.FlipperConfig,
	Slingshot: SlingshotGenerator.SlingshotConfig,
	Lanes: InlaneOutlaneGenerator.InlaneOutlaneConfig,

	DesiredCenterDrainWidth: number?,
	MinimumCenterDrainWidth: number?,
	FlipperForwardOffset: number?,
	SlingshotForwardOffset: number?,
	SlingshotLateralOffset: number?,
	LaneTailPastOrigin: number?,
	Debug: boolean?,
}

local function cloneWithOverrides(base: any, overrides: { [string]: any }): any
	local result = table.clone(base)
	for key, value in pairs(overrides) do
		result[key] = value
	end
	return result
end

local function validateConfig(config: LowerPlayfieldConfig)
	local desiredGap = config.DesiredCenterDrainWidth or DEFAULT_DESIRED_CENTER_DRAIN_WIDTH_STUDS
	local minimumGap = math.max(config.MinimumCenterDrainWidth or DEFAULT_MINIMUM_CENTER_DRAIN_WIDTH_STUDS, Scale.DEFAULT_INNER_DIAMETER_STUDS)

	local desiredOk, desiredErr = GeometryValidator.ValidatePositive(desiredGap, "DesiredCenterDrainWidth")
	GeometryValidator.AssertAll({ { ok = desiredOk, err = desiredErr } }, "LowerPlayfieldGenerator.Generate")

	if desiredGap < minimumGap then
		error(
			string.format(
				"LowerPlayfieldGenerator.Generate: DesiredCenterDrainWidth (%.4f) is below MinimumCenterDrainWidth (%.4f)",
				desiredGap,
				minimumGap
			),
			0
		)
	end

	if config.Flipper.FlipperSize == nil then
		error("LowerPlayfieldGenerator.Generate: Config.Flipper.FlipperSize is required (composition solves pivot spacing from it)", 0)
	end
end

export type LowerPlayfieldSideAsset = {
	Flipper: FlipperGenerator.FlipperAsset,
	Slingshot: SlingshotGenerator.SlingshotAsset,
	Lanes: InlaneOutlaneGenerator.InlaneOutlaneAsset,
}

export type LowerPlayfieldAsset = Types.GeneratedAsset & {
	Left: LowerPlayfieldSideAsset,
	Right: LowerPlayfieldSideAsset,
	CenterDrainTrigger: BasePart,
	RestingTipGap: number,
	PivotOffsetX: number,
}

function LowerPlayfieldGenerator.Generate(options: Types.GenerateOptions<LowerPlayfieldConfig>): LowerPlayfieldAsset
	local config = options.Config
	validateConfig(config)

	local origin = options.Origin
	local name = options.Name or "LowerPlayfieldAssembly"

	local flipperBase = config.Flipper
	local flipperLength = (flipperBase.FlipperSize :: Vector3).X
	local restAngleDegrees = flipperBase.RestAngleDegrees or DEFAULT_REST_ANGLE_DEGREES
	local tipRadius = flipperBase.TipRadius or DEFAULT_TIP_RADIUS_STUDS
	local desiredGap = config.DesiredCenterDrainWidth or DEFAULT_DESIRED_CENTER_DRAIN_WIDTH_STUDS

	local pivotOffsetX = FlipperGeometry.SolvePivotOffsetForCenterGap(desiredGap, flipperLength, restAngleDegrees, tipRadius)

	local flipperForwardOffset = config.FlipperForwardOffset or DEFAULT_FLIPPER_FORWARD_OFFSET_STUDS
	local slingshotForwardOffset = config.SlingshotForwardOffset or DEFAULT_SLINGSHOT_FORWARD_OFFSET_STUDS
	local slingshotLateralOffset = config.SlingshotLateralOffset or DEFAULT_SLINGSHOT_LATERAL_OFFSET_STUDS
	local laneTailPastOrigin = config.LaneTailPastOrigin or DEFAULT_LANE_TAIL_PAST_ORIGIN_STUDS

	local slingshotOuterX = pivotOffsetX + slingshotLateralOffset
	local slingshotZ = flipperForwardOffset + slingshotForwardOffset

	-- Self-check (spec section 16): the slingshot must sit outside the
	-- flipper's swept envelope. Conservative bounding-radius check (the
	-- slingshot's own footprint, not exact post geometry) -- widen
	-- SlingshotLateralOffset/SlingshotForwardOffset if this fires.
	local slingshotWidth = config.Slingshot.Width or 3
	local slingshotDepth = config.Slingshot.Depth or 2
	local leftFlipperGeomForCheck: FlipperGeometry.FlipperGeometryConfig = {
		Side = "Left",
		PivotLocal = Vector3.new(-pivotOffsetX, 0, flipperForwardOffset),
		Length = flipperLength,
		RestAngleDegrees = restAngleDegrees,
		TipRadius = tipRadius,
	}
	local upAngleDegrees = flipperBase.UpAngleDegrees or 45
	local rootRadiusForCheck = flipperBase.RootRadius or 0.6
	local sweptEnvelope = FlipperGeometry.GetSweptEnvelope(leftFlipperGeomForCheck, rootRadiusForCheck, upAngleDegrees)
	local slingshotBoundingRadius = math.max(slingshotWidth, slingshotDepth)
	if FlipperGeometry.SweepIntersectsPoint(sweptEnvelope, Vector3.new(-slingshotOuterX, 0, slingshotZ), slingshotBoundingRadius) then
		error(
			"LowerPlayfieldGenerator.Generate: the slingshot's footprint intersects the flipper's swept envelope -- increase"
				.. " SlingshotLateralOffset or SlingshotForwardOffset",
			0
		)
	end

	-- Build the assembly's own container structure (spec section 7) and
	-- parent it into the real container IMMEDIATELY -- FlipperGenerator reads
	-- AssemblyMass while wiring the hinge, which is only meaningful once its
	-- part is a live DataModel descendant, so Left/Right must already be live
	-- before FlipperGenerator.Generate runs. This means the usual "build
	-- fully in memory, then swap" idempotency pattern (PrimitiveFactory.
	-- ReplaceOrParent) can't apply to the assembly's OWN top-level Model;
	-- instead any previous assembly with the same GenerationId is found and
	-- destroyed only AFTER the new one is fully built below, preserving spec
	-- section 19's "build the replacement before removing the previous
	-- version" guarantee.
	local assemblyModel = Instance.new("Model")
	assemblyModel.Name = name

	local assemblyRoot = Instance.new("Part")
	assemblyRoot.Name = "Root"
	assemblyRoot.Size = Vector3.new(0.2, 0.2, 0.2)
	assemblyRoot.CFrame = origin
	assemblyRoot.Anchored = true
	assemblyRoot.CanCollide = false
	assemblyRoot.CanTouch = false
	assemblyRoot.CanQuery = false
	assemblyRoot.Transparency = 1
	assemblyRoot.Parent = assemblyModel
	assemblyModel.PrimaryPart = assemblyRoot

	local leftFolder = Instance.new("Folder")
	leftFolder.Name = "Left"
	leftFolder.Parent = assemblyModel

	local rightFolder = Instance.new("Folder")
	rightFolder.Name = "Right"
	rightFolder.Parent = assemblyModel

	local centerDrainFolder = Instance.new("Folder")
	centerDrainFolder.Name = "CenterDrain"
	centerDrainFolder.Parent = assemblyModel

	local sharedGuidesFolder = Instance.new("Folder")
	sharedGuidesFolder.Name = "SharedGuides"
	sharedGuidesFolder.Parent = assemblyModel

	local attachmentsFolder = Instance.new("Folder")
	attachmentsFolder.Name = "Attachments"
	attachmentsFolder.Parent = assemblyModel

	local debugFolder = Instance.new("Folder")
	debugFolder.Name = "Debug"
	if config.Debug then
		debugFolder.Parent = assemblyModel
	end

	local attributes = Constants.ASSET_ATTRIBUTES
	local generationId = "LowerPlayfieldAssembly_" .. name
	assemblyModel:SetAttribute(attributes.PinballAsset, true)
	assemblyModel:SetAttribute(attributes.AssetType, "LowerPlayfieldAssembly")
	assemblyModel:SetAttribute(attributes.AssetVersion, Constants.LIBRARY_VERSION)
	assemblyModel:SetAttribute(attributes.BallDiameter, Scale.BALL_DIAMETER_STUDS)
	assemblyModel:SetAttribute(attributes.GeneratedBy, Constants.GENERATED_BY)
	assemblyModel:SetAttribute(attributes.GenerationId, generationId)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	local previousAssemblies: { Model } = {}
	if options.ReplaceExisting ~= false then
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute(attributes.GenerationId) == generationId then
				table.insert(previousAssemblies, child)
			end
		end
	end

	assemblyModel.Parent = parent

	-- Left flipper (canonical side).
	local leftFlipperOrigin = origin * CFrame.new(-pivotOffsetX, 0, flipperForwardOffset)
	-- RestAngleDegrees is passed through explicitly (not left to fall through
	-- to flipperBase's own value) so FlipperGenerator.Generate always builds
	-- against the exact same restAngleDegrees this module already resolved
	-- above and used for pivotOffsetX/the sweep check/the drain trigger --
	-- otherwise an omitted Config.Flipper.RestAngleDegrees would silently
	-- fall back to FlipperGenerator's own default (-45) instead of this
	-- module's (-30), diverging from every layout calculation that assumed
	-- the resolved value.
	local leftFlipperConfig =
		cloneWithOverrides(flipperBase, { Side = "Left", RestAngleDegrees = restAngleDegrees }) :: FlipperGenerator.FlipperConfig
	local leftFlipper = FlipperGenerator.Generate({
		Name = "LeftFlipper",
		Parent = leftFolder,
		Origin = leftFlipperOrigin,
		Config = leftFlipperConfig,
	})

	-- Right flipper: mirrored pivot position, FlipperGenerator's own Side
	-- logic handles the rest-angle/offset mirroring internally.
	local rightFlipperOrigin = origin * CFrame.new(pivotOffsetX, 0, flipperForwardOffset)
	local rightFlipperConfig =
		cloneWithOverrides(flipperBase, { Side = "Right", RestAngleDegrees = restAngleDegrees }) :: FlipperGenerator.FlipperConfig
	local rightFlipper = FlipperGenerator.Generate({
		Name = "RightFlipper",
		Parent = rightFolder,
		Origin = rightFlipperOrigin,
		Config = rightFlipperConfig,
	})

	-- Left slingshot: Origin is a pure translation from `origin` (no extra
	-- rotation), so mirroring for the Right side is just negating local X --
	-- SlingshotGenerator's own MirrorX flag handles the internal geometry
	-- flip (verified against its inline math -- see MirrorTransform.luau).
	local slingshotBase = config.Slingshot
	local leftSlingshotOrigin = origin * CFrame.new(-slingshotOuterX, 0, slingshotZ)
	local leftSlingshotConfig = cloneWithOverrides(slingshotBase, { MirrorX = false }) :: SlingshotGenerator.SlingshotConfig
	local leftSlingshot = SlingshotGenerator.Generate({
		Name = "LeftSlingshot",
		Parent = leftFolder,
		Origin = leftSlingshotOrigin,
		Config = leftSlingshotConfig,
	})

	local rightSlingshotOrigin = origin * CFrame.new(slingshotOuterX, 0, slingshotZ)
	local rightSlingshotConfig = cloneWithOverrides(slingshotBase, { MirrorX = true }) :: SlingshotGenerator.SlingshotConfig
	if slingshotBase.PostPositions ~= nil then
		-- PostPositions ignores MirrorX (spec: caller mirrors the point list
		-- itself) -- see SlingshotGenerator.luau's header comment.
		rightSlingshotConfig.PostPositions = MirrorTransform.MirrorPath(slingshotBase.PostPositions)
	end
	local rightSlingshot = SlingshotGenerator.Generate({
		Name = "RightSlingshot",
		Parent = rightFolder,
		Origin = rightSlingshotOrigin,
		Config = rightSlingshotConfig,
	})

	-- Lanes: a straight divider running from alongside the slingshot down
	-- past Origin's Z = 0 toward the drain (spec section 16's "inlane exit ->
	-- flipper heel region," "outlane exit -> side drain path"). The Left
	-- divider's start CFrame is unrotated relative to Origin (Right already
	-- points toward +X = toward centerline = the inlane side, per
	-- InlaneOutlaneGenerator's own convention); the Right side needs its
	-- Right axis flipped while Up/Look stay exactly as-is (still vertical,
	-- still walking downhill) -- MirrorCFrame's whole-orientation reflection
	-- would flip Look too (correct for a wedge, wrong for a path), so
	-- MirrorPathStart is used instead (see its own header comment).
	local lanesBase = config.Lanes
	local inlaneWidth = lanesBase.InlaneClearWidth or 1.85
	local laneLength = slingshotZ + laneTailPastOrigin
	local dividerLeftX = -(slingshotOuterX + inlaneWidth)

	local leftLaneStartCFrame = origin * CFrame.new(dividerLeftX, 0, slingshotZ)
	local leftLaneConfig = cloneWithOverrides(lanesBase, {
		Side = "Left",
		Path = { PathType = "Straight", Length = laneLength },
	}) :: InlaneOutlaneGenerator.InlaneOutlaneConfig
	local leftLanes = InlaneOutlaneGenerator.Generate({
		Name = "LeftInlaneOutlane",
		Parent = leftFolder,
		Origin = leftLaneStartCFrame,
		Config = leftLaneConfig,
	})

	local rightLaneStartCFrame = MirrorTransform.MirrorPathStart(origin, leftLaneStartCFrame)
	local rightLaneConfig = cloneWithOverrides(lanesBase, {
		Side = "Right",
		Path = { PathType = "Straight", Length = laneLength },
	}) :: InlaneOutlaneGenerator.InlaneOutlaneConfig
	local rightLanes = InlaneOutlaneGenerator.Generate({
		Name = "RightInlaneOutlane",
		Parent = rightFolder,
		Origin = rightLaneStartCFrame,
		Config = rightLaneConfig,
	})

	-- Center drain trigger, between resting flipper tips (spec section 17):
	-- non-blocking, positioned slightly downfield of the tip midpoint so it
	-- never overlaps the still-in-play area, matching architecture.md's
	-- "DrainTrigger must sit past the drain edge" rule generically (no ramp
	-- math needed here since this composition works in Origin-local space).
	local leftFlipperGeom: FlipperGeometry.FlipperGeometryConfig = {
		Side = "Left",
		PivotLocal = Vector3.new(-pivotOffsetX, 0, flipperForwardOffset),
		Length = flipperLength,
		RestAngleDegrees = restAngleDegrees,
		TipRadius = tipRadius,
	}
	local rightFlipperGeom: FlipperGeometry.FlipperGeometryConfig = {
		Side = "Right",
		PivotLocal = Vector3.new(pivotOffsetX, 0, flipperForwardOffset),
		Length = flipperLength,
		RestAngleDegrees = restAngleDegrees,
		TipRadius = tipRadius,
	}
	local leftTipLocal = FlipperGeometry.ComputeTipPosition(leftFlipperGeom)
	local rightTipLocal = FlipperGeometry.ComputeTipPosition(rightFlipperGeom)
	local restingTipGap = FlipperGeometry.GetRestingTipGap(leftFlipperGeom, rightFlipperGeom)
	local drainCenterLocal = (leftTipLocal + rightTipLocal) / 2

	local drainWidth = math.max(desiredGap, restingTipGap + (2 * tipRadius))
	local drainOrigin = origin * CFrame.new(drainCenterLocal.X, drainCenterLocal.Y, drainCenterLocal.Z - DEFAULT_DRAIN_DOWNFIELD_OFFSET_STUDS)
	local centerDrainTrigger = PrimitiveFactory.CreatePart({
		Name = "CenterDrainTrigger",
		Size = Vector3.new(drainWidth, DEFAULT_DRAIN_HEIGHT_STUDS, 1),
		CFrame = drainOrigin,
		Role = "Trigger",
		Parent = centerDrainFolder,
	})
	centerDrainTrigger.Transparency = 1

	for _, previous in ipairs(previousAssemblies) do
		previous:Destroy()
	end

	return {
		Model = assemblyModel,
		Root = assemblyRoot,
		Attachments = {},
		Left = { Flipper = leftFlipper, Slingshot = leftSlingshot, Lanes = leftLanes },
		Right = { Flipper = rightFlipper, Slingshot = rightSlingshot, Lanes = rightLanes },
		CenterDrainTrigger = centerDrainTrigger,
		RestingTipGap = restingTipGap,
		PivotOffsetX = pivotOffsetX,
	}
end

return LowerPlayfieldGenerator
