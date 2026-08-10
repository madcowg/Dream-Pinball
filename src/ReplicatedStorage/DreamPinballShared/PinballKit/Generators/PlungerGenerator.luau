--!strict

-- The spring-loaded plunger rod at a cabinet's LaunchAnchor -- a visual/
-- mechanical accompaniment to CabinetGameplay.luau's existing launch() call,
-- NOT a second way of launching the ball. launch() already assigns the
-- ball's velocity directly (see CabinetGameplay.luau's "HOW RELAUNCH WORKS"
-- doc comment); this generator does not change that. The Rod is
-- CanCollide = false for exactly that reason -- giving it a real collider
-- would risk a double impulse (script-assigned velocity AND a physical
-- strike) the first time timing lines up wrong, for what was asked as a
-- cosmetic feature ("animate and pull"). A physically-struck-ball plunger
-- would be a deliberate, separate change to CabinetGameplay's launch
-- mechanism, not something to back into here.
--
-- The retract/release motion IS real physics, though: a PrismaticConstraint
-- (ActuatorType.Servo) -- matching this library's existing preference for a
-- driven physical constraint over a scripted CFrame tween (see
-- TargetGenerator's drop-target hinges, RoutingGenerator's gate/diverter
-- hinges). Runtime/PlungerController.luau drives TargetPosition; Roblox's
-- physics solver moves the Rod.
--
-- Axis convention: `fixedAttachment` is parented to Root with NO extra
-- rotation, so it keeps Root's (= Origin's) exact orientation, and Roblox's
-- default Attachment.Axis, (0,0,1) local, already points along Origin's own
-- local Z -- which is "backward, into the sleeve" (Origin's local -Z /
-- LookVector is "forward, toward the ball"). A positive TargetPosition
-- therefore retracts the rod and 0 returns it to rest; no cross-product
-- derivation needed here, unlike CabinetUpgrade's computeTableFrame, which
-- has to derive a frame from scratch because nothing there already shares
-- one. `rodAttachment`'s position is computed via CFrame:PointToObjectSpace
-- rather than a hand-derived local offset, so the separate 90-degree visual
-- twist applied to the Rod/Sleeve shapes below (purely so the cylinders look
-- like rods instead of flat discs -- a symmetric shape, so its sign truly
-- doesn't matter) can never desync the constraint's rest alignment.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local PlungerGenerator = {}

export type PlungerConfig = {
	RodLength: number?,
	RodDiameter: number?,
	SleeveLength: number?,
	SleeveDiameter: number?,
	KnobDiameter: number?,
	MaxRetractStuds: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	SleeveColor: BrickColor?,
}

local DEFAULT_ROD_LENGTH = 2.5
local DEFAULT_ROD_DIAMETER = 0.35
local DEFAULT_SLEEVE_LENGTH = 1.5
local DEFAULT_SLEEVE_DIAMETER = 0.6
local DEFAULT_KNOB_DIAMETER = 0.7
local DEFAULT_MAX_RETRACT_STUDS = 2

-- Light, not structural -- the Rod never contacts anything (see header
-- comment). This only affects how briskly the Servo actuator can move it.
local ROD_DENSITY = 0.5

local function validateConfig(config: PlungerConfig)
	local rodLength = config.RodLength or DEFAULT_ROD_LENGTH
	local rodDiameter = config.RodDiameter or DEFAULT_ROD_DIAMETER
	local maxRetractStuds = config.MaxRetractStuds or DEFAULT_MAX_RETRACT_STUDS
	local rodLengthOk, rodLengthErr = GeometryValidator.ValidatePositive(rodLength, "RodLength")
	local rodDiameterOk, rodDiameterErr = GeometryValidator.ValidatePositive(rodDiameter, "RodDiameter")
	local maxRetractOk, maxRetractErr = GeometryValidator.ValidatePositive(maxRetractStuds, "MaxRetractStuds")
	GeometryValidator.AssertAll({
		{ ok = rodLengthOk, err = rodLengthErr },
		{ ok = rodDiameterOk, err = rodDiameterErr },
		{ ok = maxRetractOk, err = maxRetractErr },
	}, "PlungerGenerator.Generate")
end

export type PlungerAsset = Types.GeneratedAsset & {
	Rod: BasePart,
	Constraint: PrismaticConstraint,
	MaxRetractStuds: number,
}

function PlungerGenerator.Generate(options: Types.GenerateOptions<PlungerConfig>): PlungerAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Plunger"
	local rodLength = config.RodLength or DEFAULT_ROD_LENGTH
	local rodDiameter = config.RodDiameter or DEFAULT_ROD_DIAMETER
	local sleeveLength = config.SleeveLength or DEFAULT_SLEEVE_LENGTH
	local sleeveDiameter = config.SleeveDiameter or DEFAULT_SLEEVE_DIAMETER
	local knobDiameter = config.KnobDiameter or DEFAULT_KNOB_DIAMETER
	local maxRetractStuds = config.MaxRetractStuds or DEFAULT_MAX_RETRACT_STUDS
	local material = config.Material or Enum.Material.Metal
	local color = config.Color or BrickColor.new("Really black")
	local sleeveColor = config.SleeveColor or BrickColor.new("Dark stone grey")

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Plunger",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	-- Cylinders are always long along their own local X axis in Roblox,
	-- regardless of Size ordering -- this reorients that axis onto Origin's
	-- local Z (the travel line) once, so Size can read naturally as
	-- (length, diameter, diameter) below. Symmetric shape: the rotation's
	-- sign genuinely doesn't matter (see header comment).
	local visualTwist = CFrame.Angles(0, math.rad(90), 0)

	-- Sleeve: static housing the rod slides through, centered behind Origin
	-- so the rod's rest position sits at the sleeve's forward mouth.
	local sleeve = PrimitiveFactory.CreatePart({
		Name = "Sleeve",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(sleeveLength, sleeveDiameter, sleeveDiameter),
		CFrame = options.Origin * CFrame.new(0, 0, sleeveLength / 2) * visualTwist,
		Role = "Visual",
		Material = material,
		Color = sleeveColor,
		Parent = hierarchy.Folders.Visuals,
	})
	sleeve.Anchored = true

	-- Rod: the moving Mechanism part. Rest CFrame keeps its front tip exactly
	-- at Origin -- see header comment for the retract-direction convention.
	local rod = Instance.new("Part")
	rod.Name = "Rod"
	rod.Shape = Enum.PartType.Cylinder
	rod.Size = Vector3.new(rodLength, rodDiameter, rodDiameter)
	rod.Anchored = false
	rod.CanCollide = false
	rod.CanTouch = false
	rod.CanQuery = false
	rod.Material = material
	rod.BrickColor = color
	rod.CustomPhysicalProperties = PhysicalProperties.new(ROD_DENSITY, 0.3, 0.1, 1, 1)
	rod.CFrame = options.Origin * CFrame.new(0, 0, rodLength / 2) * visualTwist
	rod.Parent = hierarchy.Folders.Mechanism

	-- Knob: cosmetic handle on the rod's back end, welded so it rides along.
	-- A Ball has no directional axis, so no twist is needed here.
	local knob = Instance.new("Part")
	knob.Name = "Knob"
	knob.Shape = Enum.PartType.Ball
	knob.Size = Vector3.new(knobDiameter, knobDiameter, knobDiameter)
	knob.Anchored = false
	knob.CanCollide = false
	knob.CanTouch = false
	knob.CanQuery = false
	knob.Material = material
	knob.BrickColor = color
	knob.CFrame = options.Origin * CFrame.new(0, 0, rodLength)
	knob.Parent = hierarchy.Folders.Visuals

	local knobWeld = Instance.new("WeldConstraint")
	knobWeld.Part0 = rod
	knobWeld.Part1 = knob
	knobWeld.Parent = rod

	local fixedAttachment = Instance.new("Attachment")
	fixedAttachment.Name = "PlungerFixed"
	fixedAttachment.Parent = hierarchy.Root

	local rodAttachment = Instance.new("Attachment")
	rodAttachment.Name = "PlungerRod"
	-- See header comment: computed via PointToObjectSpace so the Rod's
	-- visualTwist rotation can never desync this from the fixed attachment.
	rodAttachment.Position = rod.CFrame:PointToObjectSpace(options.Origin.Position)
	rodAttachment.Parent = rod

	local constraint = Instance.new("PrismaticConstraint")
	constraint.Name = "PlungerConstraint"
	constraint.Attachment0 = fixedAttachment
	constraint.Attachment1 = rodAttachment
	constraint.ActuatorType = Enum.ActuatorType.Servo
	constraint.ServoMaxForce = 3000
	constraint.LimitsEnabled = true
	constraint.LowerLimit = -rodLength * 0.3
	constraint.UpperLimit = maxRetractStuds
	constraint.TargetPosition = 0
	constraint.Parent = hierarchy.Root

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = { Fixed = fixedAttachment, Rod = rodAttachment },
		Rod = rod,
		Constraint = constraint,
		MaxRetractStuds = maxRetractStuds,
	}
end

return PlungerGenerator
