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

-- Mirrors CabinetBuilder.luau's private (non-exported) MOTOR_DIRECTION table.
-- This orients the REST angle only -- SWEEP_DIRECTION (which way Q/E presses
-- sweep the flipper) lives inside attachFlipperHinge and is applied there,
-- not duplicated here. If CabinetBuilder's MOTOR_DIRECTION table ever
-- changes, update this to match.
local MOTOR_DIRECTION: { [Side]: number } = { Left = 1, Right = -1 }

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

	local direction = MOTOR_DIRECTION[config.Side]
	local restCFrame = options.Origin * CFrame.Angles(0, math.rad(-direction * restAngleDegrees), 0)
	local flipperOffsetX = if config.Side == "Left" then flipperSize.X / 2 else -flipperSize.X / 2
	local flipperCFrame = restCFrame * CFrame.new(flipperOffsetX, 0, 0)

	-- Core collision volume: a single invisible box (not the tapered visual
	-- shell) -- see CabinetBuilder.buildFlipper's doc comment on why the
	-- cosmetic segments must stay CanCollide = false (a ball can wedge in the
	-- seams between them and get pinned, confirmed live via PhysicsTestRig).
	local flipper = Instance.new("Part")
	flipper.Name = "Flipper"
	flipper.Size = flipperSize
	flipper.Material = Enum.Material.SmoothPlastic
	flipper.Anchored = false
	flipper.CanCollide = true
	flipper.Color = (config.Color or BrickColor.new("Bright red")).Color
	flipper.Transparency = 1
	flipper.CFrame = flipperCFrame
	-- Denser, more elastic, and higher friction than a default part -- see
	-- this file's header/DEFAULT_DENSITY comments for why these exceed
	-- CabinetBuilder.buildFlipper's own tuning on purpose.
	flipper.CustomPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, 1, 1)
	flipper.Parent = hierarchy.Folders.Mechanism

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
	}
end

return FlipperGenerator
