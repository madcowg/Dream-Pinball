--!strict

-- Flipper. The MECHANISM (geometry + hinge wiring) is reused, not
-- reimplemented: the tapered cosmetic segment shell welded onto a single
-- invisible box collider mirrors CabinetBuilder.luau's `buildFlipper` line
-- for line, and the hinge is wired by literally calling
-- `CabinetBuilder.attachFlipperHinge` -- the same function
-- WilliamsCabinet-style hand-built flippers use. Do not re-derive that
-- hinge-setup code here.
--
-- The TUNING (mass, torque-per-mass, motor speed in FlipperController) is
-- deliberately NOT copied from the locked CabinetLayouts.SHARED_FLIPPER_CONFIG
-- baseline -- live playtesting found those flippers under-hit the ball. This
-- generator's defaults are heavier and produce more torque/speed on purpose
-- (see DEFAULT_DENSITY/DEFAULT_MOTOR_TORQUE_PER_MASS below for the reasoning).
-- This changes nothing about CabinetBuilder.luau or any existing cabinet --
-- only PinballKit's own default preset is different, and it's fully
-- overridable per instance same as everything else in this library.
--
-- `Origin` is the flipper's PIVOT rest pose (equivalent to buildFlipper's
-- `pivotBaseCFrame`): local +Y is the hinge axis (the playfield's normal at
-- that point), local +Z is "forward up the playfield" for rest-angle
-- purposes. Unlike CabinetBuilder.buildFlipper (which derives the pivot
-- position from a whole-cabinet ramp+offset calculation), this generator
-- takes the exact rest pose directly -- matching how the hand-built track
-- already works ("team places it, code wires the hinge").

local PhysicsService = game:GetService("PhysicsService")

local CabinetBuilder = require(script.Parent.Parent.Parent.CabinetBuilder)
local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local FlipperGenerator = {}

export type Side = CabinetBuilder.Side

export type FlipperConfig = {
	Side: Side,
	FlipperSize: Vector3?,
	RestAngleDegrees: number?,
	UpAngleDegrees: number?,
	MotorTorquePerMass: number?,
	Density: number?,
	Friction: number?,
	Elasticity: number?,
	-- Optional in the type so presets can omit it (it's inherently
	-- per-cabinet, not shareable) and be filled in later via Presets.Extend
	-- -- but functionally required: validateConfig raises if it's missing,
	-- since without Flippers/Playfield collision separation the flipper's
	-- swept volume (which overlaps the floor by design) fights the floor.
	CollisionGroup: string?,
	Material: Enum.Material?,
	Color: BrickColor?,

	-- Opt-in multi-collider mode (spec section 12): rounded root + tapered
	-- body + rounded tip colliders instead of the single invisible box
	-- above. Defaults to "SingleBox" -- the locked architecture.md "Flipper
	-- baseline" collider shape, unchanged for every existing caller. Only the
	-- new lower-playfield preset opts into "SegmentedCapsule".
	-- RootRadius/TipRadius/ColliderOverlap are only read in that mode.
	ColliderMode: ("SingleBox" | "SegmentedCapsule")?,
	RootRadius: number?,
	TipRadius: number?,
	ColliderOverlap: number?,
	-- Cosmetic-only additions, also gated behind ColliderMode ==
	-- "SegmentedCapsule": a rubber-band ring near the tip and a vertical
	-- shaft stub below the pivot (spec section 12's "visible rubber band,"
	-- "vertical shaft," "optional under-playfield mechanism visuals"). Never
	-- affects collision.
	RubberColor: Color3?,
	ShaftMaterial: Enum.Material?,
	ShowShaftCosmetic: boolean?,
}

-- Size/angles still match CabinetLayouts.luau's SHARED_FLIPPER_CONFIG -- the
-- physical shape/range of motion isn't what underperformed.
local DEFAULT_FLIPPER_SIZE = Vector3.new(7.5, 1.25, 2.5)
local DEFAULT_REST_ANGLE_DEGREES = -45
local DEFAULT_UP_ANGLE_DEGREES = 45

-- Mass/torque are INTENTIONALLY higher than the locked baseline
-- (SHARED_FLIPPER_CONFIG implies ~2399.7 torque-per-mass at density 3) --
-- see this file's header comment. Reasoning, not just bigger-is-better:
--   - Heavier (density 3 -> 4.5): in a rigid-body hit, the heavier striking
--     body loses less of its own velocity and imparts more to the lighter
--     ball (basic momentum transfer) -- this is *why* a heavier flipper
--     "hits more reliably" in the way the ball actually responds, not just a
--     bigger number.
--   - More torque-per-mass (2399.7 -> 3400, ~42% higher): with AssemblyMass
--     also up ~50% from the density increase, effective absolute torque
--     (torquePerMass * AssemblyMass, computed inside attachFlipperHinge) rises
--     by roughly 2x over the baseline -- enough headroom that a fast/heavy
--     ball landing on the flipper mid-swing doesn't visibly bog the motor
--     down before it reaches UpAngle.
-- Live-verify against a real ball before treating these as final; they are a
-- reasoned starting point; not playtested numbers the way the original
-- baseline was.
local DEFAULT_DENSITY = 4.5
local DEFAULT_FRICTION = 0.75
local DEFAULT_ELASTICITY = 0.65
local DEFAULT_MOTOR_TORQUE_PER_MASS = 3400

local DEFAULT_COLLIDER_MODE: "SingleBox" | "SegmentedCapsule" = "SingleBox"
local DEFAULT_ROOT_RADIUS_STUDS = 0.6
local DEFAULT_TIP_RADIUS_STUDS = 0.45
-- Larger than the guide-rail default (Constants.DEFAULT_SEGMENT_OVERLAP_STUDS)
-- on purpose -- a fast-moving flipper needs more margin against the same
-- seam-wedging failure mode architecture.md documents for the locked
-- single-box baseline (a slow static guide rail can get away with less).
local DEFAULT_COLLIDER_OVERLAP_STUDS = 0.2
local DEFAULT_RUBBER_COLOR = Color3.fromRGB(35, 35, 35)
local DEFAULT_SHAFT_MATERIAL = Enum.Material.Metal

local SEGMENT_COUNT = 26

local function validateConfig(config: FlipperConfig)
	local flipperSize = config.FlipperSize or DEFAULT_FLIPPER_SIZE
	local xOk, xErr = GeometryValidator.ValidatePositive(flipperSize.X, "FlipperSize.X")
	local yOk, yErr = GeometryValidator.ValidatePositive(flipperSize.Y, "FlipperSize.Y")
	local zOk, zErr = GeometryValidator.ValidatePositive(flipperSize.Z, "FlipperSize.Z")

	GeometryValidator.AssertAll({
		{ ok = xOk, err = xErr },
		{ ok = yOk, err = yErr },
		{ ok = zOk, err = zErr },
	}, "FlipperGenerator.Generate")

	if config.CollisionGroup == nil then
		error(
			"FlipperGenerator.Generate: Config.CollisionGroup is required -- a flipper must be in its own"
				.. " collision group with collision disabled against the playfield group (see architecture.md"
				.. " \"Flipper baseline\"), or its swept volume will fight the floor it overlaps by design.",
			0
		)
	end
end

export type FlipperAsset = Types.GeneratedAsset & {
	Flipper: BasePart,
	Hinge: HingeConstraint,
	Side: Side,
	-- Recorded for layout calculations (spec section 12) -- pivot-center-to-
	-- tip-center distance, unchanged across ColliderMode. TipRadius/RootRadius
	-- are 0 for "SingleBox" (a flat-faced box, no rounding beyond its own
	-- edges); real values for "SegmentedCapsule". Feed these straight into
	-- Geometry/FlipperGeometry.luau's FlipperGeometryConfig.
	EffectiveCollisionLength: number,
	RootRadius: number,
	TipRadius: number,
}

function FlipperGenerator.Generate(options: Types.GenerateOptions<FlipperConfig>): FlipperAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or (config.Side .. "Flipper")
	local flipperSize = config.FlipperSize or DEFAULT_FLIPPER_SIZE
	local restAngleDegrees = config.RestAngleDegrees or DEFAULT_REST_ANGLE_DEGREES
	local upAngleDegrees = config.UpAngleDegrees or DEFAULT_UP_ANGLE_DEGREES
	local torquePerMass = config.MotorTorquePerMass or DEFAULT_MOTOR_TORQUE_PER_MASS
	local density = config.Density or DEFAULT_DENSITY
	local friction = config.Friction or DEFAULT_FRICTION
	local elasticity = config.Elasticity or DEFAULT_ELASTICITY

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Flipper",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	-- Parented into the real container BEFORE building flipper geometry
	-- (every other generator defers this to the end) -- attachFlipperHinge
	-- below reads flipper.AssemblyMass to compute motor torque, which is only
	-- meaningful once the part is a live descendant of the DataModel; the
	-- hand-built flippers this function was designed for are always already
	-- parented in Workspace by the time it runs. Safe: nothing yields between
	-- here and the fully-built return, so the model is never observed
	-- half-built by any other script or frame.
	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	-- Left's baseline angle is -restAngleDegrees; Right mirrors it via the
	-- same MirrorAngleDegrees convention FlipperGenerator has always used
	-- (previously a hand-copied MOTOR_DIRECTION table, now centralized in
	-- MirrorTransform -- see its header for why this convention, not a
	-- generic CFrame reflection, is correct for a flipper paddle specifically).
	local isLeft = config.Side == "Left"
	local leftBaseAngleDegrees = -restAngleDegrees
	local usedAngleDegrees = if isLeft then leftBaseAngleDegrees else MirrorTransform.MirrorAngleDegrees(leftBaseAngleDegrees)
	local restCFrame = options.Origin * CFrame.Angles(0, math.rad(usedAngleDegrees), 0)
	local leftOffsetX = flipperSize.X / 2
	local flipperOffsetX = if isLeft then leftOffsetX else MirrorTransform.MirrorSignedOffset(leftOffsetX)
	local flipperCFrame = restCFrame * CFrame.new(flipperOffsetX, 0, 0)

	local colliderMode = config.ColliderMode or DEFAULT_COLLIDER_MODE
	local rootRadius = config.RootRadius or DEFAULT_ROOT_RADIUS_STUDS
	local tipRadius = config.TipRadius or DEFAULT_TIP_RADIUS_STUDS
	local colliderOverlap = config.ColliderOverlap or DEFAULT_COLLIDER_OVERLAP_STUDS

	if colliderMode == "SegmentedCapsule" then
		-- The body collider is centered the same as the SingleBox case and
		-- sized to overlap each end sphere by ColliderOverlap studs -- but
		-- that overlap is only equal on both ends when RootRadius == TipRadius.
		-- The smaller-radius end's ACTUAL overlap is
		-- ColliderOverlap -/+ (RootRadius - TipRadius) / 2 (see the derivation
		-- in WilliamsCabinetBottomPlayfield.md-style seam math); if a preset
		-- ever pushes the two radii far enough apart, that seam's overlap hits
		-- zero or goes negative, reopening the exact ball-wedging failure mode
		-- (frozen AssemblyLinearVelocity) SegmentedCapsule was built to avoid.
		local radiusDelta = (rootRadius - tipRadius) / 2
		local rootSeamOverlap = colliderOverlap + radiusDelta
		local tipSeamOverlap = colliderOverlap - radiusDelta
		local seamOk, seamErr = GeometryValidator.ValidatePositive(math.min(rootSeamOverlap, tipSeamOverlap), "FlipperGenerator SegmentedCapsule seam overlap (RootRadius/TipRadius/ColliderOverlap combination)")
		-- rootSeamOverlap/tipSeamOverlap above assume the body collider is
		-- exactly flipperSize.X - rootRadius - tipRadius + 2*colliderOverlap
		-- long (the unclamped formula below). If FlipperSize.X is too short
		-- for RootRadius + TipRadius, that formula goes below the
		-- colliderOverlap * 2 floor and gets clamped to it, silently
		-- shrinking the REAL overlap below what was just validated above and
		-- reopening the same seam-wedging failure mode. Reject that
		-- combination outright instead of building a mismatched collider.
		local bodyLengthOk, bodyLengthErr = GeometryValidator.ValidatePositive(
			flipperSize.X - rootRadius - tipRadius,
			"FlipperGenerator SegmentedCapsule FlipperSize.X (too short for RootRadius + TipRadius)"
		)
		GeometryValidator.AssertAll({ { ok = seamOk, err = seamErr }, { ok = bodyLengthOk, err = bodyLengthErr } }, "FlipperGenerator.Generate")
	end

	local flipperPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, 1, 1)
	local flipperColor = (config.Color or BrickColor.new("Bright red")).Color

	-- Core collision volume. SingleBox (default, locked architecture.md
	-- baseline): one invisible box spanning the full paddle -- see
	-- CabinetBuilder.buildFlipper's doc comment on why the cosmetic segments
	-- must stay CanCollide = false (a ball can wedge in the seams between them
	-- and get pinned, confirmed live via PhysicsTestRig). SegmentedCapsule
	-- (opt-in, spec section 12): the box narrows to a BODY collider only, with
	-- rounded root/tip colliders welded on, each overlapping the body by
	-- ColliderOverlap studs -- the same anti-seam discipline
	-- GuideRailBuilder/LaneGenerator already use, applied here specifically to
	-- avoid reintroducing the seam-wedging failure mode the single-box
	-- baseline was built to fix. Named "Flipper" either way so
	-- attachFlipperHinge/pivotAttachment wiring below needs no branching.
	local flipper = Instance.new("Part")
	flipper.Name = "Flipper"
	flipper.Material = Enum.Material.SmoothPlastic
	flipper.Anchored = false
	flipper.CanCollide = true
	flipper.Color = flipperColor
	flipper.Transparency = 1
	flipper.CustomPhysicalProperties = flipperPhysicalProperties

	if colliderMode == "SingleBox" then
		flipper.Size = flipperSize
		flipper.CFrame = flipperCFrame
	else
		local bodyLength = math.max(flipperSize.X - rootRadius - tipRadius + (2 * colliderOverlap), colliderOverlap * 2)
		flipper.Size = Vector3.new(bodyLength, flipperSize.Y, flipperSize.Z)
		flipper.CFrame = flipperCFrame
	end
	flipper.Parent = hierarchy.Folders.Mechanism

	if colliderMode == "SegmentedCapsule" then
		local rootPart = Instance.new("Part")
		rootPart.Name = "FlipperRoot"
		rootPart.Shape = Enum.PartType.Ball
		rootPart.Size = Vector3.new(rootRadius * 2, rootRadius * 2, rootRadius * 2)
		rootPart.Material = Enum.Material.SmoothPlastic
		rootPart.Anchored = false
		rootPart.CanCollide = true
		rootPart.Color = flipperColor
		rootPart.Transparency = 1
		rootPart.CustomPhysicalProperties = flipperPhysicalProperties
		rootPart.CFrame = flipper.CFrame * CFrame.new(-flipperOffsetX, 0, 0)
		rootPart.Parent = hierarchy.Folders.Mechanism

		local rootWeld = Instance.new("WeldConstraint")
		rootWeld.Part0 = flipper
		rootWeld.Part1 = rootPart
		rootWeld.Parent = flipper

		local tipPart = Instance.new("Part")
		tipPart.Name = "FlipperTip"
		tipPart.Shape = Enum.PartType.Ball
		tipPart.Size = Vector3.new(tipRadius * 2, tipRadius * 2, tipRadius * 2)
		tipPart.Material = Enum.Material.SmoothPlastic
		tipPart.Anchored = false
		tipPart.CanCollide = true
		tipPart.Color = flipperColor
		tipPart.Transparency = 1
		tipPart.CustomPhysicalProperties = flipperPhysicalProperties
		tipPart.CFrame = flipper.CFrame * CFrame.new(flipperOffsetX, 0, 0)
		tipPart.Parent = hierarchy.Folders.Mechanism

		local tipWeld = Instance.new("WeldConstraint")
		tipWeld.Part0 = flipper
		tipWeld.Part1 = tipPart
		tipWeld.Parent = flipper

		-- Rubber-band ring near the tip, and a short vertical shaft stub below
		-- the pivot (spec section 12) -- purely cosmetic, never collides.
		local rubberRing = Instance.new("Part")
		rubberRing.Name = "RubberBand"
		rubberRing.Shape = Enum.PartType.Cylinder
		rubberRing.Material = Enum.Material.SmoothPlastic
		rubberRing.Size = Vector3.new(flipperSize.X * 0.06, flipperSize.Z * 1.15, flipperSize.Z * 1.15)
		rubberRing.Anchored = false
		rubberRing.CanCollide = false
		rubberRing.CanQuery = false
		rubberRing.Color = config.RubberColor or DEFAULT_RUBBER_COLOR
		rubberRing.CFrame = flipper.CFrame * CFrame.new(flipperOffsetX * 0.6, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
		rubberRing.Parent = hierarchy.Folders.Visuals

		local rubberWeld = Instance.new("WeldConstraint")
		rubberWeld.Part0 = flipper
		rubberWeld.Part1 = rubberRing
		rubberWeld.Parent = flipper

		if config.ShowShaftCosmetic then
			local shaftHeight = 1.5
			local shaft = Instance.new("Part")
			shaft.Name = "FlipperShaft"
			shaft.Shape = Enum.PartType.Cylinder
			shaft.Material = config.ShaftMaterial or DEFAULT_SHAFT_MATERIAL
			shaft.Size = Vector3.new(shaftHeight, rootRadius * 0.9, rootRadius * 0.9)
			shaft.Anchored = true
			shaft.CanCollide = false
			shaft.CanTouch = false
			shaft.CanQuery = false
			shaft.Color = Color3.fromRGB(150, 150, 150)
			shaft.CFrame = options.Origin * CFrame.new(0, -shaftHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
			shaft.Parent = hierarchy.Folders.Mechanism
		end
	end

	-- Tapered cosmetic shell: full width at the pivot end, half width at the
	-- tip, approximated with overlapping cylinder segments (Roblox has no
	-- native tapered-cylinder/cone shape). Purely visual -- CanCollide = false
	-- throughout; welded to `flipper` so it moves with the hinge.
	--
	-- Thickness is tied to the ACTUAL spacing between adjacent segment centers
	-- (flipperSize.X / (SEGMENT_COUNT - 1)) plus a small fixed overlap margin,
	-- not to flipperSize.Y -- tying it to an unrelated dimension meant the
	-- overlap ratio (thickness vs. spacing) scaled unpredictably with flipper
	-- proportions. At WilliamsCabinet's smaller hand-built size the old
	-- formula produced segments ~6.5x wider than the gap between them, fusing
	-- all 26 into one solid blocky mass instead of a smooth taper. This
	-- formula keeps the overlap ratio (and therefore the visual result)
	-- consistent regardless of absolute flipper size.
	local capRotation = CFrame.Angles(0, 0, math.rad(90))
	local segmentSpacing = flipperSize.X / (SEGMENT_COUNT - 1)
	local segmentThickness = segmentSpacing + Constants.DEFAULT_SEGMENT_OVERLAP_STUDS
	local segmentPhysicalProperties = PhysicalProperties.new(0.01, 0.75, 0.65, 1, 1)

	for i = 0, SEGMENT_COUNT - 1 do
		local t = i / (SEGMENT_COUNT - 1)
		local localX = -flipperOffsetX + t * (2 * flipperOffsetX)
		local diameter = flipperSize.Z - t * (flipperSize.Z / 2)

		local segment = Instance.new("Part")
		segment.Name = "FlipperSegment" .. tostring(i)
		segment.Shape = Enum.PartType.Cylinder
		segment.Material = Enum.Material.SmoothPlastic
		segment.Size = Vector3.new(segmentThickness, diameter, diameter)
		segment.Anchored = false
		segment.CanCollide = false
		segment.CanQuery = false
		segment.Color = flipper.Color
		segment.CustomPhysicalProperties = segmentPhysicalProperties
		segment.CFrame = flipper.CFrame * CFrame.new(localX, 0, 0) * capRotation
		segment.Parent = hierarchy.Folders.Visuals

		local segmentWeld = Instance.new("WeldConstraint")
		segmentWeld.Part0 = flipper
		segmentWeld.Part1 = segment
		segmentWeld.Parent = flipper
	end

	local pivotAttachment = Instance.new("Attachment")
	pivotAttachment.Name = "PivotAttachment"
	pivotAttachment.Position = Vector3.new(-flipperOffsetX, 0, 0)
	pivotAttachment.Parent = flipper

	-- validateConfig already raised if this were nil.
	local collisionGroup = config.CollisionGroup :: string

	-- attachFlipperHinge below calls SetPartCollisionGroup, which requires the
	-- group to already be registered -- unlike PrimitiveFactory.CreatePart
	-- (which self-registers), attachFlipperHinge assumes a cabinet-level
	-- ensureCollisionGroups call already happened, which isn't true for a
	-- standalone PinballKit-generated flipper. pcall makes this idempotent.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(collisionGroup)
	end)

	-- Wires the actual HingeConstraint (limits, motor, sweep direction) --
	-- see this file's header comment: this is the same function every
	-- hand-built flipper in the project uses, not a re-derived equivalent.
	local hinge = CabinetBuilder.attachFlipperHinge(flipper, pivotAttachment, config.Side, upAngleDegrees, torquePerMass, collisionGroup)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = { Pivot = pivotAttachment },
		Flipper = flipper,
		Hinge = hinge,
		Side = config.Side,
		EffectiveCollisionLength = flipperSize.X,
		RootRadius = if colliderMode == "SegmentedCapsule" then rootRadius else 0,
		TipRadius = if colliderMode == "SegmentedCapsule" then tipRadius else 0,
	}
end

return FlipperGenerator
