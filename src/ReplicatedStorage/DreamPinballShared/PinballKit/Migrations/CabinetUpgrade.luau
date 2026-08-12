--!strict

-- Generic additive cabinet-upgrade engine: generates NEW PinballKit parts
-- (flippers, bumpers, lane dividers, ...) alongside a cabinet's existing
-- hand-built ones, using a per-cabinet CabinetSpec for every measurement and
-- marker name that differs from table to table. Never touches, renames, or
-- deletes anything -- see the Finalize* functions below for the only way an
-- original gets replaced (and only after YOU delete it yourself).
--
-- Originally WilliamsCabinetUpgrade.luau, written specifically for one
-- cabinet. Generalized so every future cabinet reuses this exact engine and
-- only supplies its own CabinetSpec (see WilliamsCabinetSpec.luau for the
-- worked example) -- this file should not need to change per cabinet.
--
-- (An earlier version of this engine renamed originals into a backup folder
-- and swapped the new ones in immediately. That added real risk for a
-- workflow that doesn't need it -- a failure partway through left a cabinet
-- without a working LeftFlipper/RightFlipper at all, twice. This version
-- can't do that: until you explicitly delete something and finalize, the
-- originals are exactly as they were.)

local PinballKit = script.Parent.Parent
local Scale = require(PinballKit.Scale)
local Constants = require(PinballKit.Constants)
local MirrorTransform = require(PinballKit.Geometry.MirrorTransform)
local FlipperGenerator = require(PinballKit.Generators.FlipperGenerator)
local BumperGenerator = require(PinballKit.Generators.BumperGenerator)
local SlingshotGenerator = require(PinballKit.Generators.SlingshotGenerator)
local LaneGenerator = require(PinballKit.Generators.LaneGenerator)
local PlungerGenerator = require(PinballKit.Generators.PlungerGenerator)
local Presets = require(PinballKit.Presets)

local CabinetUpgrade = {}

export type CabinetSpec = {
	-- Marker names read off the cabinet folder (FindFirstChild(name, true)).
	LaunchAnchorName: string,
	-- Used ONLY to determine which physical side is "left" vs "right" (their
	-- own names are trusted for that) -- NOT as a position reference for the
	-- flipper layout. These may not even be in their final position yet.
	SlingshotLeftName: string,
	SlingshotRightName: string,
	-- The fixed point the whole flipper layout is centered/anchored on --
	-- e.g. "DrainTrigger", which sits on the table's own centerline. Must be
	-- a BasePart (its Size is used to find its up-table edge).
	CenterlineMarkerName: string,
	-- The cabinet's actual structural floor (e.g. "CabinetFloor") -- the
	-- authority for "flat" and "correct height," NOT playsurface: every
	-- flipper's hinge plane is forced parallel to this part's own orientation,
	-- and both the pivot and tip are snapped to sit at exactly
	-- floor-surface-height + one ball radius, so the ball can't ride over or
	-- duck under the flipper regardless of how precisely a hand-placed marker
	-- was positioned vertically. Must be a BasePart.
	FloorMarkerName: string,
	-- Optional: the cabinet's outer boundary wall(s) (BasePart or Model --
	-- if a Model, its GetBoundingBox() is used). When present, lane dividers
	-- anchor to this wall's own lateral extent (the actual edge of the
	-- playing board) instead of a guessed offset from the flipper pivot.
	OuterWallMarkerName: string?,

	-- The names CabinetGameplay.luau (and everything else gameplay-facing)
	-- actually looks for. FinalizeFlipperNames/FinalizeBumperNames rename the
	-- new parts to these, and refuse to run while anything is still using them.
	FinalLeftFlipperName: string,
	FinalRightFlipperName: string,
	FinalBumperName: string,

	-- Names the newly-generated parts get before finalizing, so they can sit
	-- next to the originals without colliding on name.
	NewLeftFlipperName: string,
	NewRightFlipperName: string,
	NewBumperPrefix: string,
	NewLaneDividerPrefix: string,

	FlipperCollisionGroup: string,
	PlayfieldCollisionGroup: string,

	-- Measured flipper spec (this should be an actual Studio measurement, not
	-- an estimate -- see WilliamsCabinetSpec.luau's header comment).
	FlipperSize: Vector3,
	FlipperRestAngleDegrees: number,
	FlipperUpAngleDegrees: number,
	-- Tip-to-tip gap between the two flippers AT REST, measured directly --
	-- combined with FlipperSize.X and FlipperRestAngleDegrees below to derive
	-- shaft-to-shaft distance analytically (S = Gap + 2*Length*cos(RestAngle))
	-- when FlipperShaftToShaftStuds below isn't given.
	FlipperRestTipGapStuds: number,
	-- Optional direct override for shaft-to-shaft distance -- takes priority
	-- over the Gap/Length/RestAngle derivation above when given. Prefer this
	-- when a real cited measurement is available (e.g. the WPC/Williams
	-- standard, 6-13/16in to 7in shaft-to-shaft) over the derived value: the
	-- derivation has produced a smaller, wrong-looking result on
	-- WilliamsCabinet more than once, while the cited real-world figure
	-- matches what was independently measured here from the start.
	FlipperShaftToShaftStuds: number?,
	-- How far up-table (in studs) the flipper pivots sit from
	-- CenterlineMarkerName's own up-table edge (not its center) -- e.g. "6
	-- studs up from the edge of DrainTrigger". Ignored when the four marker
	-- names below are given and found.
	FlipperUpTableOffsetFromCenterlineEdgeStuds: number,

	-- Optional position-only escape hatch: if both of these marker names
	-- resolve to real BaseParts, GenerateNewFlippers uses their positions
	-- directly (pivot position + tip-minus-pivot direction) for the LEFT
	-- flipper instead of the analytic centerline derivation above -- no
	-- rotation to get right, no sign convention to match, just "where did you
	-- put these two points." The RIGHT flipper is then mirrored from the left
	-- one across the table's own centerline -- deliberately NOT a second
	-- independently-placed marker pair, since two hand-placed pairs came out
	-- visibly asymmetric on WilliamsCabinet (unavoidable human placement
	-- error). Use this when the analytic derivation keeps coming out wrong
	-- despite correct measurements. Place the pair by eye against a
	-- reference photo. See CabinetUpgrade.luau's
	-- computeFlipperOriginsFromMarkers for exactly how they're used.
	LeftFlipperPivotMarkerName: string?,
	LeftFlipperTipMarkerName: string?,

	-- Uniform scale applied to every WilliamsClassic.PopBumper dimension, to
	-- account for a cabinet hand-built at a different size than the preset's
	-- reference scale. An ESTIMATE unless you've separately measured a real
	-- bumper on this cabinet -- see WilliamsCabinetSpec.luau.
	BumperScale: number,

	-- Lane-divider placement: the WHOLE in-lane/out-lane guide rail (not a
	-- short decorative section). The rail's LATERAL position is derived
	-- entirely from the slingshot's own current outer edge (+ one
	-- OUTLANE_CHANNEL_WIDTH_STUDS channel) -- NOT from OuterWallMarkerName/
	-- cabinetwalls at all -- per direct instruction: the slingshot's own face
	-- IS the inlane's inner wall, so the rail's position has to be measured
	-- from it, not guessed independently and reconciled later. The curve
	-- below the slingshot lands EXACTLY on the flipper's physical top (no
	-- stacked gap there -- "the inlane ends when the top of the flipper
	-- starts"), and the straight run above the slingshot covers the
	-- slingshot's own live depth plus this many EXTRA studs beyond it (a
	-- layout choice, not a citation-needing estimate). LaneDividerLateralOffset
	-- is only used as a last-resort fallback ESTIMATE if the slingshot itself
	-- can't be found at all.
	LaneDividerLength: number,
	LaneDividerLateralOffset: number,
	-- Height/thickness override matched to WilliamsClassic.Slingshot's own
	-- Height (2 studs) instead of LaneGenerator's ball-diameter-based default
	-- -- a lane guide next to a slingshot should read as the same height as
	-- the slingshot, not a shorter cosmetic curb.
	LaneDividerHeight: number,
	-- The rail's own thickness -- the ONE deliberately free/tunable variable
	-- in this whole layout, per direct instruction. The rail's INNER face
	-- (facing the slingshot) is pinned to slingshot-edge +
	-- OUTLANE_CHANNEL_WIDTH_STUDS; its OUTER face then lands wherever
	-- InnerFace + LaneDividerThickness ends up relative to cabinetwalls,
	-- which should ALSO read as roughly OUTLANE_CHANNEL_WIDTH_STUDS (the
	-- outlane channel). GenerateLaneDividers prints the achieved outlane
	-- width so this can be tuned up/down (larger = narrower outlane, smaller
	-- = wider outlane) until it matches, rather than the code silently
	-- forcing cabinetwalls or the slingshot to move to make the numbers fit.
	LaneDividerThickness: number,

	-- Name the generated plunger gets -- CabinetGameplay.luau looks for this
	-- exact name (optional, found-by-name, same as the backboard displays)
	-- to wire up BeginCharge/Launch. Baked once via GenerateNewPlunger, same
	-- as flippers/bumpers/lane dividers -- not runtime-generated, so every
	-- WilliamsCabinet asset is Explorer-visible the same way.
	PlungerName: string,

	-- Style base (colors/materials/mechanism tuning) each new part starts
	-- from before the measured overrides above are applied via Presets.Extend.
	-- Not necessarily WilliamsClassic -- a differently-styled cabinet passes
	-- its own preset family here.
	FlipperBasePreset: FlipperGenerator.FlipperConfig,
	BumperBasePreset: BumperGenerator.BumperConfig,
	LaneDividerBasePreset: LaneGenerator.LaneDividerConfig,
	PlungerBasePreset: PlungerGenerator.PlungerConfig,
}

-- Trims leading/trailing whitespace before comparing. Some of this cabinet's
-- hand-placed names carry an invisible trailing space (confirmed live:
-- "Bumper" was actually "Bumper ") that a plain == comparison silently never
-- matches, with nothing pointing at the real cause -- just a confusing
-- "0 found" result. Every name comparison in this module that walks
-- GetDescendants() manually goes through this; FindFirstChild-based lookups
-- (LaunchAnchor, CenterlineMarkerName, etc.) still do an exact match, since
-- Roblox's own FindFirstChild doesn't support a tolerant comparison -- if
-- one of those ever silently fails to resolve, whitespace in the name is
-- the first thing to check by hand.
local function trim(value: string): string
	return (value:gsub("^%s*(.-)%s*$", "%1"))
end

-- Some cabinets have more than one descendant sharing a name (e.g. a Model
-- wrapping a Part, both literally named "slingshotL") -- FindFirstChild(name,
-- true) isn't guaranteed to return the same one every call in that case.
-- Confirmed live on WilliamsCabinet: it returned the Part (a sensible
-- position) on one run and a Model with an unset/default pivot (garbage,
-- coincidentally close to an unrelated part's position) on the next,
-- silently swapping which physical side got called "left". This always
-- prefers an actual BasePart -- a Model's pivot can be unset, a BasePart's
-- Position never is.
local function findNamedBasePart(root: Instance, name: string): BasePart?
	for _, descendant in ipairs(root:GetDescendants()) do
		if trim(descendant.Name) == name and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- Resolves any named "original" marker to a reliable world CFrame, whether
-- it's a plain BasePart (used directly) or a Model (its OWN pivot is not
-- trusted -- same unset-pivot risk as findNamedBasePart above -- instead the
-- first BasePart found anywhere inside it is used). Handles a cabinet where
-- e.g. "Bumper" resolves to a Model wrapping an differently-named Part,
-- which a plain `descendant:IsA("BasePart") and descendant.Name == "Bumper"`
-- check would silently miss entirely (confirmed live: WilliamsCabinet's
-- GenerateNewBumpers found zero matches this way).
local function resolveNamedOriginalCFrame(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant.CFrame
			end
		end
	end
	return nil
end

export type TableFrame = {
	Up: Vector3,
	TableForward: Vector3,
	Right: Vector3,
	SlingshotLeftPos: Vector3,
	SlingshotRightPos: Vector3,
	-- The lateral-center point at the flipper pivots' own up-table position
	-- -- i.e. AnchorPoint +/- LeftDirection*someOffset gives a point at that
	-- same up-table position, any lateral distance from center. Used by
	-- GenerateLaneDividers to anchor off the same up-table position without
	-- re-deriving it.
	AnchorPoint: Vector3,
	-- CenterlineMarkerName's own up-table EDGE (not its center, not offset by
	-- FlipperUpTableOffsetFromCenterlineEdgeStuds) -- the lane guide starts
	-- relative to THIS, independently of where the flipper pivot ended up.
	CenterlineEdgePos: Vector3,
	LeftPivotPos: Vector3,
	RightPivotPos: Vector3,
	LeftDirection: Vector3,
	RightDirection: Vector3,
}

export type FloorReference = {
	-- The floor's own surface normal, sign-corrected to point mostly skyward
	-- (in case the mesh was authored upside down). Every flipper (and, via
	-- computeTableFrame, the analytic layout too) is built flat against THIS
	-- exact vector -- not an approximation of it -- so nothing generated can
	-- come out non-parallel to the actual floor.
	Up: Vector3,
	-- Scalar height (Position:Dot(Up)) of the floor's own top surface.
	SurfaceHeight: number,
	-- SurfaceHeight + one ball radius -- the height a resting ball's CENTER
	-- sits at. A flipper's cross-section center needs to sit here too, or the
	-- ball can ride over (flipper too low) or duck under (flipper too high).
	BallCenterHeight: number,
}

-- Reads the cabinet's actual structural floor (FloorMarkerName, e.g.
-- "CabinetFloor") once, so every piece of geometry that needs to be "flat"
-- or "at the right height" measures against the SAME real part instead of
-- each guessing independently (playsurface, a decorative overlay, is not
-- necessarily co-planar with the real collision floor -- this is why an
-- earlier version's flippers came out non-parallel to it).
local function computeFloorReference(cabinetFolder: Instance, spec: CabinetSpec): FloorReference
	local floor = cabinetFolder:FindFirstChild(spec.FloorMarkerName, true)
	if floor == nil or not floor:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.FloorMarkerName .. " under " .. cabinetFolder:GetFullName(), 0)
	end

	local floorCFrame = (floor :: BasePart).CFrame
	local floorSize = (floor :: BasePart).Size
	local up = floorCFrame.UpVector
	if up:Dot(Vector3.new(0, 1, 0)) < 0 then
		up = -up
	end

	-- Half-extent of the floor's own OBB projected onto its own (corrected)
	-- Up, i.e. how far its top surface sits above its center -- the same
	-- general OBB-projection technique used for the centerline marker's edge
	-- and the outer wall's extent, so it's correct regardless of the floor
	-- part's exact rotation, not just one that happens to be axis-aligned.
	local halfExtentAlongUp = math.abs(floorCFrame.RightVector:Dot(up)) * floorSize.X / 2
		+ math.abs(floorCFrame.UpVector:Dot(up)) * floorSize.Y / 2
		+ math.abs(floorCFrame.LookVector:Dot(up)) * floorSize.Z / 2

	local surfaceHeight = floorCFrame.Position:Dot(up) + halfExtentAlongUp
	return {
		Up = up,
		SurfaceHeight = surfaceHeight,
		BallCenterHeight = surfaceHeight + Scale.BALL_DIAMETER_STUDS / 2,
	}
end

-- Moves `position` purely along `up` until its height (Position:Dot(Up))
-- equals `targetHeight`, leaving its other two coordinates untouched.
-- Moves `position` purely along `axis` until its scalar coordinate along
-- that axis (position:Dot(axis)) equals `targetScalar`, leaving the other
-- two components untouched. Generic version of the height-snapping used for
-- the floor; also used along TableForward for repositioning along the
-- table's length.
local function snapAlongAxis(position: Vector3, axis: Vector3, targetScalar: number): Vector3
	return position + axis * (targetScalar - position:Dot(axis))
end

local function snapHeight(position: Vector3, up: Vector3, targetHeight: number): Vector3
	return snapAlongAxis(position, up, targetHeight)
end

-- Half-extent of an OBB (given its own CFrame and Size) projected onto an
-- arbitrary world axis -- how far its face sits from its own center along
-- that axis, correct regardless of the OBB's exact rotation (not just one
-- that happens to be axis-aligned). The same technique used repeatedly in
-- this file (the centerline marker's edge, the outer wall's extent, the
-- floor's surface) -- factored out here since RepositionSlingshots and
-- GenerateLaneDividers both need it for the slingshot's own depth.
local function computeHalfExtentAlongAxis(cframe: CFrame, size: Vector3, axis: Vector3): number
	return math.abs(cframe.RightVector:Dot(axis)) * size.X / 2
		+ math.abs(cframe.UpVector:Dot(axis)) * size.Y / 2
		+ math.abs(cframe.LookVector:Dot(axis)) * size.Z / 2
end

-- The SAME cited real-world channel-width figure (Bally-standard inlane/
-- outlane width, 1-3/8in = 1.375in) used for BOTH channels flanking the lane
-- guide rail, per direct instruction:
--   - INLANE (slingshot side): the rail's inner face sits this far from the
--     slingshot's own outer edge -- the slingshot's face IS the inlane's
--     inner wall, not a separately-gapped object.
--   - OUTLANE (cabinetwalls side): the rail's outer face SHOULD also end up
--     this far from cabinetwalls' inner face -- but that's a consequence of
--     where the slingshot and cabinetwalls already are, not something this
--     code forces by moving either of them. GenerateLaneDividers positions
--     the rail from the INLANE side only, then prints how close the
--     resulting OUTLANE gap comes to this same target so LaneDividerThickness
--     can be tuned to close the difference.
-- NOTE: RepositionSlingshots still enforces this same distance as an
-- up-table gap between the flipper's top and the slingshot's bottom edge --
-- that predates the "inlane ends when the top of the flipper starts"
-- correction (continuous, not stacked) and likely needs revisiting; flagged,
-- not yet changed.
local OUTLANE_CHANNEL_WIDTH_STUDS = 1.375 * (1.5 / 1.0625)

export type FlipperMarkerOrigins = {
	LeftOrigin: CFrame,
	RightOrigin: CFrame,
}

-- Right vector + a point on the table's own centerline, using only
-- LaunchAnchor/CenterlineMarkerName -- enough to mirror a left-side
-- placement into a right-side one. Deliberately does NOT do the
-- slingshot-based handedness check computeTableFrame does: mirroring
-- doesn't care which physical side is "left," only where the centerline is
-- (a small, intentional duplication of computeTableFrame's Right/Up
-- derivation rather than reusing its full pivot-computation logic, which
-- needs inputs -- FlipperSize, rest angle, tip gap -- this path doesn't).
local function computeCenterlineAxis(cabinetFolder: Instance, spec: CabinetSpec, up: Vector3): (Vector3, Vector3)
	local launchAnchor = cabinetFolder:FindFirstChild(spec.LaunchAnchorName, true)
	if launchAnchor == nil or not launchAnchor:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.LaunchAnchorName .. " under " .. cabinetFolder:GetFullName(), 0)
	end
	local centerlineMarker = cabinetFolder:FindFirstChild(spec.CenterlineMarkerName, true)
	if centerlineMarker == nil or not centerlineMarker:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.CenterlineMarkerName .. " under " .. cabinetFolder:GetFullName(), 0)
	end

	local rawTableForward = (launchAnchor :: BasePart).CFrame.LookVector
	local tableForward = (rawTableForward - up * rawTableForward:Dot(up)).Unit
	local right = tableForward:Cross(up)

	return right, (centerlineMarker :: BasePart).Position
end

-- If both marker names are given AND resolve to real BaseParts, computes the
-- LEFT flipper's Origin directly from their positions -- pure position, no
-- rotation/sign ambiguity at all (the analytic centerline derivation below
-- has come out wrong on position and/or rest-angle sign multiple times on
-- WilliamsCabinet despite real measurements; this sidesteps that entirely).
-- Place the pair by eye against a reference photo: Pivot at the hinge point,
-- Tip at where the paddle's far end should rest -- position only, no
-- rotation needed on the marker parts themselves. Height doesn't need to be
-- exact either: both points are snapped to FloorReference.BallCenterHeight
-- before use, which also FLATTENS the resulting pivot-to-tip direction
-- (since pivot and tip end up at the identical height) -- the flipper comes
-- out parallel to the floor and centered on the ball regardless of how
-- precisely the markers were placed vertically.
--
-- The RIGHT flipper is then mirrored from the left one across the table's
-- centerline (computeCenterlineAxis), NOT read from a second independently
-- hand-placed pair -- two markers placed by eye came out visibly asymmetric
-- on WilliamsCabinet (confirmed live), which mirroring makes impossible by
-- construction.
--
-- FlipperGenerator's Origin convention: with RestAngleDegrees = 0, the bat
-- extends from pivot along Origin's local +X (Right) for Side="Left", local
-- -X for Side="Right". So Right is set directly to the Left tip's direction,
-- and to the mirrored tip's direction negated -- and RestAngleDegrees = 0 is
-- forced for both by the caller when this path is used, since the tip
-- marker's direction already IS the desired rest angle; nothing left to
-- rotate.
local function computeFlipperOriginsFromMarkers(cabinetFolder: Instance, spec: CabinetSpec): FlipperMarkerOrigins?
	if spec.LeftFlipperPivotMarkerName == nil or spec.LeftFlipperTipMarkerName == nil then
		return nil
	end

	local leftPivot = findNamedBasePart(cabinetFolder, spec.LeftFlipperPivotMarkerName)
	local leftTip = findNamedBasePart(cabinetFolder, spec.LeftFlipperTipMarkerName)
	if leftPivot == nil or leftTip == nil then
		return nil
	end

	local floorRef = computeFloorReference(cabinetFolder, spec)
	local up = floorRef.Up

	local leftPivotPos = snapHeight(leftPivot.Position, up, floorRef.BallCenterHeight)
	local leftTipPos = snapHeight(leftTip.Position, up, floorRef.BallCenterHeight)
	local leftBatDirection = (leftTipPos - leftPivotPos).Unit

	local right, centerlinePoint = computeCenterlineAxis(cabinetFolder, spec, up)
	local function mirrorAcrossCenterline(point: Vector3): Vector3
		return point - (right * (2 * (point - centerlinePoint):Dot(right)))
	end

	local rightPivotPos = mirrorAcrossCenterline(leftPivotPos)
	local rightTipPos = mirrorAcrossCenterline(leftTipPos)
	local rightBatDirection = (rightTipPos - rightPivotPos).Unit

	return {
		LeftOrigin = CFrame.fromMatrix(leftPivotPos, leftBatDirection, up),
		RightOrigin = CFrame.fromMatrix(rightPivotPos, -rightBatDirection, up),
	}
end

-- Prefers a direct, cited FlipperShaftToShaftStuds override when given.
-- Otherwise falls back to the analytic derivation from three
-- independently-measured numbers: each flipper's rest tip sits
-- FlipperSize.X away from its own pivot, foreshortened laterally by
-- cos(RestAngleDegrees); the two tips' lateral gap is
-- FlipperRestTipGapStuds. So ShaftToShaft = Gap + 2*Length*cos(RestAngle).
-- The derivation has come out smaller than the real target on
-- WilliamsCabinet -- prefer the override once a real number is known.
local function computeShaftToShaftStuds(spec: CabinetSpec): number
	if spec.FlipperShaftToShaftStuds ~= nil then
		return spec.FlipperShaftToShaftStuds
	end
	return spec.FlipperRestTipGapStuds + 2 * spec.FlipperSize.X * math.cos(math.rad(spec.FlipperRestAngleDegrees))
end

-- Fully analytic construction from the CabinetSpec -- doesn't require
-- LeftFlipper/RightFlipper (or anything else flipper-shaped) to already
-- exist, and does NOT use the slingshots' current position as a placement
-- reference (an earlier version did; confirmed wrong against a live Studio
-- measurement). Whether the slingshots need to move turned out to be less
-- clear-cut than first assumed: a cited real-world slingshot rubber span
-- (~11-7/8in outside-to-outside, ~16.8 studs) is close to this cabinet's
-- CURRENT ~15.9-stud slingshot spacing, while the flipper shaft-to-shaft
-- target is a real ~9.9 studs -- i.e. slingshots may already be close to
-- correct, and it's the flippers that need to sit closer together than an
-- earlier derivation produced. See WilliamsCabinetBottomPlayfield.md.
--   - Up = FloorMarkerName's own surface normal (see computeFloorReference)
--     -- everything generated from this frame is forced flat against the
--     cabinet's real floor, not an approximation of it.
--   - TableForward (up-table, away from the drain) = LaunchAnchor's
--     LookVector, which CabinetGameplay.luau's own doc comment guarantees
--     points at the main playfield -- projected flat against Up.
--   - Right = TableForward x Up (verified against the identity basis:
--     (0,0,-1) x (0,1,0) = (1,0,0) = Right).
-- The whole layout is centered on CenterlineMarkerName's own lateral
-- position (e.g. DrainTrigger, which sits on the table's centerline by
-- construction), FlipperUpTableOffsetFromCenterlineEdgeStuds up-table from
-- that marker's own up-table EDGE (found via its Size, not just its center
-- point) -- both pivots sit ShaftToShaft/2 either side of that point.
-- LeftDirection/RightDirection (which of +Right/-Right is physically "left")
-- are still decided by the SlingshotLeft/SlingshotRight markers' CURRENT
-- position/naming -- trusted for handedness only, not for placement.
local function computeTableFrame(cabinetFolder: Instance, spec: CabinetSpec): TableFrame
	local launchAnchor = cabinetFolder:FindFirstChild(spec.LaunchAnchorName, true)
	if launchAnchor == nil or not launchAnchor:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.LaunchAnchorName .. " under " .. cabinetFolder:GetFullName(), 0)
	end

	local slingshotLeft = findNamedBasePart(cabinetFolder, spec.SlingshotLeftName)
	local slingshotRight = findNamedBasePart(cabinetFolder, spec.SlingshotRightName)
	if slingshotLeft == nil or slingshotRight == nil then
		error(
			"CabinetUpgrade: could not find a BasePart named "
				.. spec.SlingshotLeftName
				.. "/"
				.. spec.SlingshotRightName
				.. " under "
				.. cabinetFolder:GetFullName()
				.. " (used only to tell left from right) -- if these names only resolve to a Model, add/rename an actual"
				.. " BasePart so the lookup isn't ambiguous",
			0
		)
	end

	local slingshotLeftPos = slingshotLeft.Position
	local slingshotRightPos = slingshotRight.Position

	local centerlineMarker = cabinetFolder:FindFirstChild(spec.CenterlineMarkerName, true)
	if centerlineMarker == nil or not centerlineMarker:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.CenterlineMarkerName .. " under " .. cabinetFolder:GetFullName(), 0)
	end

	local floorRef = computeFloorReference(cabinetFolder, spec)
	local up = floorRef.Up

	local rawTableForward = (launchAnchor :: BasePart).CFrame.LookVector
	local tableForward = (rawTableForward - up * rawTableForward:Dot(up)).Unit

	local right = tableForward:Cross(up)

	local sign = if (slingshotLeftPos - slingshotRightPos):Dot(right) > 0 then 1 else -1
	local leftDirection = right * sign
	local rightDirection = -leftDirection

	-- Half-extent of the centerline marker's own OBB projected onto
	-- TableForward, i.e. how far its up-table edge sits from its own center
	-- -- correct regardless of the marker's exact rotation, not just for one
	-- that happens to be axis-aligned with TableForward.
	local markerCFrame = (centerlineMarker :: BasePart).CFrame
	local markerSize = (centerlineMarker :: BasePart).Size
	local halfExtentAlongForward = math.abs(markerCFrame.RightVector:Dot(tableForward)) * markerSize.X / 2
		+ math.abs(markerCFrame.UpVector:Dot(tableForward)) * markerSize.Y / 2
		+ math.abs(markerCFrame.LookVector:Dot(tableForward)) * markerSize.Z / 2

	-- Snapped to the real floor's surface height (not ball-center height --
	-- this point is also used as a lane-divider WALL base, which should sit
	-- flush on the floor, not at ball-center height), regardless of whatever
	-- height CenterlineMarkerName itself happens to sit at.
	local centerlineEdgePos = snapHeight(markerCFrame.Position + (tableForward * halfExtentAlongForward), up, floorRef.SurfaceHeight)
	local anchorPoint = centerlineEdgePos + (tableForward * spec.FlipperUpTableOffsetFromCenterlineEdgeStuds)
	-- Same reasoning as the marker path: pin the flipper pivots' height to
	-- the ball's actual resting height above the real floor, regardless of
	-- what height CenterlineMarkerName itself happens to sit at.
	anchorPoint = snapHeight(anchorPoint, up, floorRef.BallCenterHeight)

	local halfShaftToShaft = computeShaftToShaftStuds(spec) / 2
	local leftPivotPos = anchorPoint - (leftDirection * halfShaftToShaft)
	local rightPivotPos = anchorPoint - (rightDirection * halfShaftToShaft)

	return {
		Up = up,
		TableForward = tableForward,
		Right = right,
		SlingshotLeftPos = slingshotLeftPos,
		SlingshotRightPos = slingshotRightPos,
		AnchorPoint = anchorPoint,
		CenterlineEdgePos = centerlineEdgePos,
		LeftPivotPos = leftPivotPos,
		RightPivotPos = rightPivotPos,
		LeftDirection = leftDirection,
		RightDirection = rightDirection,
	}
end

-- Resolves where the flipper pivots ACTUALLY are, preferring the
-- position-only marker override over the analytic derivation -- the single
-- source of truth both GenerateNewFlippers and GenerateLaneDividers use, so
-- lane guides always target wherever the flippers really ended up rather
-- than a possibly-different analytic guess. Only positions are needed here
-- (not the full rotated Origin) -- `frame` still supplies Right/Up/
-- TableForward regardless of which path wins.
-- Returns full Origins (position AND rotation -- marker-derived Origins have
-- a per-side Right vector, e.g. the tip direction, that plain positions
-- would lose), plus the RestAngleDegrees actually in effect (0 for markers,
-- spec.FlipperRestAngleDegrees for the analytic path) -- needed by callers
-- that must reconstruct the flipper's real box geometry
-- (computeFlipperTopPosition below), not just its pivot point.
local function resolveFlipperOrigins(cabinetFolder: Instance, spec: CabinetSpec, frame: TableFrame): (CFrame, CFrame, number)
	local markerOrigins = computeFlipperOriginsFromMarkers(cabinetFolder, spec)
	if markerOrigins ~= nil then
		return markerOrigins.LeftOrigin, markerOrigins.RightOrigin, 0
	end
	local leftOrigin = CFrame.fromMatrix(frame.LeftPivotPos, frame.Right, frame.Up)
	local rightOrigin = CFrame.fromMatrix(frame.RightPivotPos, frame.Right, frame.Up)
	return leftOrigin, rightOrigin, spec.FlipperRestAngleDegrees
end

-- The flipper BOX's true closest point to the slingshot -- NOT the pivot
-- point itself. The hinge Attachment sits at the pivot-end FACE's center,
-- but that face still has real width/thickness (FlipperSize.Y/Z), and at a
-- nonzero rest angle the face is tilted relative to TableForward -- so the
-- physical edge of the flipper closest to the slingshot isn't the same
-- point as the pivot. Reconstructs the pivot-end face's own orientation the
-- same way FlipperGenerator.Generate builds the box (restCFrame), then
-- projects only that face's extent (Y and Z -- it has no extent along the
-- bat's own length axis, unlike the whole box) onto TableForward, using the
-- same OBB-half-extent-along-an-axis technique used elsewhere in this file
-- for DrainTrigger/cabinetwalls/CabinetFloor.
local function computeFlipperTopPosition(origin: CFrame, side: FlipperGenerator.Side, restAngleDegrees: number, flipperSize: Vector3, tableForward: Vector3): Vector3
	-- Reconstructs the rest orientation via the SAME two MirrorTransform calls
	-- FlipperGenerator.Generate itself makes (Left = -restAngleDegrees, Right =
	-- MirrorAngleDegrees of that) instead of an independently-maintained sign
	-- table -- there is now exactly one place this convention is written down.
	local isLeft = side == "Left"
	local leftBaseAngleDegrees = -restAngleDegrees
	local usedAngleDegrees = if isLeft then leftBaseAngleDegrees else MirrorTransform.MirrorAngleDegrees(leftBaseAngleDegrees)
	local restCFrame = origin * CFrame.Angles(0, math.rad(usedAngleDegrees), 0)

	local halfExtentAlongForward = math.abs(restCFrame.UpVector:Dot(tableForward)) * flipperSize.Y / 2
		+ math.abs(restCFrame.LookVector:Dot(tableForward)) * flipperSize.Z / 2

	return restCFrame.Position + (tableForward * halfExtentAlongForward)
end

export type NewFlippersReport = {
	LeftFlipperOrigin: CFrame,
	RightFlipperOrigin: CFrame,
}

-- Builds the new-named flipper pair, never from an existing flipper -- works
-- whether or not FinalLeftFlipperName/FinalRightFlipperName already exist.
-- Safe to re-run: each call replaces its own previous New-named pair
-- (PrimitiveFactory's normal idempotent-regeneration behavior), never
-- touches the Final names.
--
-- Tries computeFlipperOriginsFromMarkers first (position-only hand-placed
-- markers -- see its doc comment) -- only falls back to the analytic
-- centerline derivation (computeTableFrame) if those markers aren't set up.
-- When markers ARE used, RestAngleDegrees is forced to 0 for both sides:
-- the tip marker's direction from the pivot already IS the desired rest
-- angle, so applying spec.FlipperRestAngleDegrees on top would rotate past
-- where the markers were actually placed.
function CabinetUpgrade.GenerateNewFlippers(cabinetFolder: Instance, spec: CabinetSpec): NewFlippersReport
	local markerOrigins = computeFlipperOriginsFromMarkers(cabinetFolder, spec)
	local leftOrigin: CFrame
	local rightOrigin: CFrame
	local restAngleDegrees: number

	if markerOrigins ~= nil then
		leftOrigin = markerOrigins.LeftOrigin
		rightOrigin = markerOrigins.RightOrigin
		restAngleDegrees = 0
	else
		local frame = computeTableFrame(cabinetFolder, spec)
		-- 3-arg fromMatrix derives a proper (non-mirrored) third axis.
		leftOrigin = CFrame.fromMatrix(frame.LeftPivotPos, frame.Right, frame.Up)
		rightOrigin = CFrame.fromMatrix(frame.RightPivotPos, frame.Right, frame.Up)
		restAngleDegrees = spec.FlipperRestAngleDegrees
	end

	FlipperGenerator.Generate({
		Name = spec.NewLeftFlipperName,
		Origin = leftOrigin,
		Parent = cabinetFolder,
		Config = Presets.Extend(spec.FlipperBasePreset, {
			Side = "Left",
			RestAngleDegrees = restAngleDegrees,
			UpAngleDegrees = spec.FlipperUpAngleDegrees,
			FlipperSize = spec.FlipperSize,
			CollisionGroup = spec.FlipperCollisionGroup,
		}),
	})

	FlipperGenerator.Generate({
		Name = spec.NewRightFlipperName,
		Origin = rightOrigin,
		Parent = cabinetFolder,
		Config = Presets.Extend(spec.FlipperBasePreset, {
			Side = "Right",
			RestAngleDegrees = restAngleDegrees,
			UpAngleDegrees = spec.FlipperUpAngleDegrees,
			FlipperSize = spec.FlipperSize,
			CollisionGroup = spec.FlipperCollisionGroup,
		}),
	})

	local shaftToShaft = (rightOrigin.Position - leftOrigin.Position).Magnitude
	local sourceNote = if markerOrigins ~= nil
		then "using hand-placed pivot/tip markers (position-only, no analytic guess)"
		else "using the analytic centerline derivation (no pivot/tip markers found)"
	print(
		string.format(
			"CabinetUpgrade: generated %s / %s next to the originals (untouched), %s. Resulting shaft-to-shaft distance: %.3f studs. Compare visually.",
			spec.NewLeftFlipperName,
			spec.NewRightFlipperName,
			sourceNote,
			shaftToShaft
		)
	)

	return { LeftFlipperOrigin = leftOrigin, RightFlipperOrigin = rightOrigin }
end

-- Moves each existing slingshot along TableForward ONLY (lateral position,
-- height, and orientation are all left exactly as they are) so its bottom
-- edge sits OUTLANE_CHANNEL_WIDTH_STUDS up-table from the flipper's actual
-- top -- the same 1.941-stud unit as the lane guide's own gaps, per direct
-- instruction that the lane-to-slingshot gap and the slingshot-to-flipper
-- gap are the same distance. MUTATES existing geometry (unlike every other
-- function in this module) -- run GenerateNewFlippers first and confirm the
-- flippers look right, since this depends on wherever they actually are.
--
-- A slingshot's name can resolve to more than one top-level object (a Model
-- and a Part sharing the same name, the same duality that bit the flipper-
-- handedness lookup) -- moves EVERY direct child of cabinetFolder sharing
-- that name by the same delta, so nothing gets left behind regardless of
-- which one is the "real" visual container. Uses one reliable BasePart
-- (findNamedBasePart) only to MEASURE the required shift.
function CabinetUpgrade.RepositionSlingshots(cabinetFolder: Instance, spec: CabinetSpec)
	local frame = computeTableFrame(cabinetFolder, spec)
	local leftOrigin, rightOrigin, restAngleDegrees = resolveFlipperOrigins(cabinetFolder, spec, frame)

	local function repositionOne(name: string, side: FlipperGenerator.Side, flipperOrigin: CFrame)
		local referencePart = findNamedBasePart(cabinetFolder, name)
		if referencePart == nil then
			error("CabinetUpgrade.RepositionSlingshots: could not find a BasePart named " .. name .. " under " .. cabinetFolder:GetFullName(), 0)
		end

		local flipperTopPos = computeFlipperTopPosition(flipperOrigin, side, restAngleDegrees, spec.FlipperSize, frame.TableForward)
		local slingshotHalfExtent = computeHalfExtentAlongAxis(referencePart.CFrame, referencePart.Size, frame.TableForward)
		local targetCenterScalar = (flipperTopPos + frame.TableForward * (OUTLANE_CHANNEL_WIDTH_STUDS + slingshotHalfExtent)):Dot(frame.TableForward)
		local currentScalar = referencePart.Position:Dot(frame.TableForward)
		local shiftAmount = targetCenterScalar - currentScalar
		local delta = frame.TableForward * shiftAmount

		local movedCount = 0
		for _, child in ipairs(cabinetFolder:GetChildren()) do
			if trim(child.Name) == name then
				if child:IsA("Model") then
					child:PivotTo(child:GetPivot() + delta)
					movedCount += 1
				elseif child:IsA("BasePart") then
					child.CFrame = child.CFrame + delta
					movedCount += 1
				end
			end
		end

		print(string.format("CabinetUpgrade: repositioned %d top-level object(s) named %s by %.3f studs along TableForward.", movedCount, name, shiftAmount))
	end

	repositionOne(spec.SlingshotLeftName, "Left", leftOrigin)
	repositionOne(spec.SlingshotRightName, "Right", rightOrigin)
end

-- Builds one new bumper per EXISTING FinalBumperName-named marker, at the
-- same position, named NewBumperPrefix .. index -- also untouched originals.
-- The marker can be a plain BasePart OR a Model wrapping a differently-named
-- Part (see resolveNamedOriginalCFrame) -- a plain BasePart-only check found
-- zero matches on a live cabinet where "Bumper" turned out to be a Model.
function CabinetUpgrade.GenerateNewBumpers(cabinetFolder: Instance, spec: CabinetSpec): number
	local originals: { { CFrame: CFrame, PointValue: any } } = {}
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if trim(descendant.Name) == spec.FinalBumperName then
			local cframe = resolveNamedOriginalCFrame(descendant)
			if cframe ~= nil then
				table.insert(originals, { CFrame = cframe, PointValue = descendant:GetAttribute("PointValue") })
			end
		end
	end

	for index, original in ipairs(originals) do
		BumperGenerator.Generate({
			Name = spec.NewBumperPrefix .. tostring(index),
			Origin = original.CFrame,
			Parent = cabinetFolder,
			Config = Presets.Extend(spec.BumperBasePreset, {
				BaseDiameter = 3.5 * spec.BumperScale,
				BaseHeight = 0.3 * spec.BumperScale,
				BodyDiameter = 2.5 * spec.BumperScale,
				BodyHeight = 1.2 * spec.BumperScale,
				CapHeight = 0.35 * spec.BumperScale,
				SkirtDiameter = (2.5 + 1.6) * spec.BumperScale,
				CollisionGroup = spec.PlayfieldCollisionGroup,
				PointValue = original.PointValue,
			}),
		})
	end

	print(
		string.format(
			"CabinetUpgrade: generated %d new bumper(s) (%s1..%s%d) next to the %d original(s) (untouched). Compare visually.",
			#originals,
			spec.NewBumperPrefix,
			spec.NewBumperPrefix,
			#originals,
			#originals
		)
	)

	return #originals
end

-- Builds the plunger rod at LaunchAnchor, baked once (Explorer-visible,
-- same as flippers/bumpers/lane dividers) rather than generated at runtime
-- by CabinetGameplay.luau -- see PlungerName's doc comment on CabinetSpec.
-- Safe to re-run: idempotent replace-by-name, same as everything else here.
-- No Finalize step: there's no original plunger to protect on a hand-built
-- cabinet.
function CabinetUpgrade.GenerateNewPlunger(cabinetFolder: Instance, spec: CabinetSpec): PlungerGenerator.PlungerAsset
	local launchAnchor = cabinetFolder:FindFirstChild(spec.LaunchAnchorName, true)
	if launchAnchor == nil or not launchAnchor:IsA("BasePart") then
		error("CabinetUpgrade: could not find a BasePart named " .. spec.LaunchAnchorName .. " under " .. cabinetFolder:GetFullName(), 0)
	end

	-- Offset back by one ball radius so the rod's tip rests just behind the
	-- ball's spawn point instead of inside its center.
	local origin = (launchAnchor :: BasePart).CFrame * CFrame.new(0, 0, Scale.BALL_DIAMETER_STUDS / 2)

	local asset = PlungerGenerator.Generate({
		Name = spec.PlungerName,
		Origin = origin,
		Parent = cabinetFolder,
		Config = spec.PlungerBasePreset,
	})

	print("CabinetUpgrade: generated " .. spec.PlungerName .. " at " .. spec.LaunchAnchorName .. ". CabinetGameplay.luau picks it up by name automatically -- no finalize step needed.")

	return asset
end

export type NewLaneDividersReport = {
	Left: LaneGenerator.LaneDividerAsset,
	Right: LaneGenerator.LaneDividerAsset,
}

-- Half-extent of OuterWallMarkerName's own bounding geometry projected onto
-- `right`, i.e. how far the actual playing-board edge sits from that
-- marker's own center -- works for a BasePart (its own Size/CFrame) or a
-- Model (GetBoundingBox()). Returns nil if no marker name was given or it
-- wasn't found, so callers fall back to the plain estimate.
local function computeOuterHalfWidth(cabinetFolder: Instance, spec: CabinetSpec, right: Vector3): number?
	if spec.OuterWallMarkerName == nil then
		return nil
	end

	local marker = cabinetFolder:FindFirstChild(spec.OuterWallMarkerName, true)
	if marker == nil then
		return nil
	end

	local markerCFrame: CFrame
	local markerSize: Vector3
	if marker:IsA("BasePart") then
		markerCFrame, markerSize = marker.CFrame, marker.Size
	elseif marker:IsA("Model") then
		markerCFrame, markerSize = marker:GetBoundingBox()
	else
		return nil
	end

	return math.abs(markerCFrame.RightVector:Dot(right)) * markerSize.X / 2
		+ math.abs(markerCFrame.UpVector:Dot(right)) * markerSize.Y / 2
		+ math.abs(markerCFrame.LookVector:Dot(right)) * markerSize.Z / 2
end

-- Exact closed-form solve for the (Radius, AngleDegrees) that make
-- ArcMath.GenerateArc's arc travel exactly `forwardDistance` along the
-- starting Tangent and `lateralDistance` toward the curve's own bend
-- direction (Direction picked by the caller) -- NOT a guessed radius/angle
-- pair. Derived from ArcMath.luau's own position formula (see its header
-- comment): displacement = (R*sinθ) forward, R*(1-cosθ) lateral, so
-- (1-cosθ)/sinθ = tan(θ/2) = lateralDistance/forwardDistance (half-angle
-- identity) gives θ directly, then R = forwardDistance/sinθ. Returns nil if
-- lateralDistance is negligible (no curve needed -- would need an infinite
-- radius) so the caller can fall back to a straight path instead.
local MIN_CURVE_LATERAL_DISTANCE_STUDS = 0.05
-- Used by GenerateLaneDividers' buildCurveOrSnap: below this much forward
-- room, a curve's own math (radius = forwardDistance/sin(angle)) degenerates
-- toward a near-zero radius rather than a real curve -- see that function's
-- comment for when this triggers (a hand-placed flipper marker and a
-- hand-built slingshot box overlapping by a fraction of a stud).
local MIN_CURVE_FORWARD_DISTANCE_STUDS = 0.1
local function solveArcForDisplacement(forwardDistance: number, lateralDistance: number): (number?, number?)
	if math.abs(lateralDistance) < MIN_CURVE_LATERAL_DISTANCE_STUDS then
		return nil, nil
	end

	local halfAngle = math.atan2(math.abs(lateralDistance), forwardDistance)
	local angleRadians = 2 * halfAngle
	local radius = forwardDistance / math.sin(angleRadians)
	return radius, math.deg(angleRadians)
end

-- Builds the in-lane/out-lane divider walls flanking the flippers -- pure new
-- additions, not replacements (most hand-built cabinets, including
-- WilliamsCabinet, have none today). No Finalize step: there's no original
-- name to protect, so these are generated directly under their real names
-- and can simply be re-run (idempotent replace-by-name) as you tune the
-- CabinetSpec.
--
-- The rail's LATERAL position is derived entirely from the slingshot's own
-- current outer edge (see OUTLANE_CHANNEL_WIDTH_STUDS's doc comment) -- the
-- slingshot's face IS the inlane's inner wall, per direct correction; this
-- is NOT a separately-gapped object, and the rail is NOT positioned from
-- OuterWallMarkerName/cabinetwalls at all (that marker is only used
-- afterward, to print a diagnostic). Two segments per side, built in this
-- order:
--   1. ONE continuous curve from the flipper's physical top
--      (computeFlipperTopPosition, NOT its pivot point -- see that
--      function's comment) all the way past the slingshot's ENTIRE depth,
--      landing at the rail's position level with the slingshot's TOP edge --
--      a single sweeping hook, matching the reference drawing, NOT a short
--      curve feeding into a separate straight run that hugs the slingshot's
--      edge in parallel (an earlier version did this; it read nothing like
--      the reference). BOTH the forward span (how far up-table the
--      slingshot's top edge actually is from the flipper's top) and the
--      lateral shift (how far sideways the rail needs to sit) are read live
--      from real geometry, and Radius/AngleDegrees are SOLVED to land
--      exactly there (solveArcForDisplacement) -- nothing guessed. This is
--      "the inlane ends when the top of the flipper starts": the curve
--      lands ON the flipper, no stacked gap.
--   2. A short straight tail continuing LaneDividerLength studs beyond that
--      (a layout choice), in whatever direction the curve ends up tangent
--      to -- not a fixed lateral offset run parallel to the slingshot.
--
-- Falls back to LaneDividerLateralOffset (a plain estimate, fixed distance
-- from centerline) and a fixed forward span only if the named slingshot
-- can't be found at all -- there's nothing real to derive the channel or
-- the curve's target from in that case.
--
-- Curve direction is DERIVED, not guessed: ArcMath's Direction="Left" bends
-- the path toward -Right (from the path's own starting orientation),
-- Direction="Right" toward +Right (see ArcMath.luau's own derivation
-- comment). The curve needs to bend toward `sideDirection` (outward, from
-- the flipper-side start to the slingshot-side end) as it travels forward
-- -- so Direction is picked by checking whether sideDirection itself points
-- along +Right or -Right for this cabinet's actual handedness, rather than
-- assuming one cabinet's "Left"/"Right" naming lines up with world Right.
function CabinetUpgrade.GenerateLaneDividers(cabinetFolder: Instance, spec: CabinetSpec): NewLaneDividersReport
	local frame = computeTableFrame(cabinetFolder, spec)
	local leftOrigin, rightOrigin, restAngleDegrees = resolveFlipperOrigins(cabinetFolder, spec, frame)
	local outerHalfWidth = computeOuterHalfWidth(cabinetFolder, spec, frame.Right)

	-- Solves a curve from `curveOrigin` to `targetLateralOffset` over
	-- `forwardDistance` studs, same as solveArcForDisplacement everywhere
	-- else -- EXCEPT when forwardDistance itself is at or below
	-- MIN_CURVE_FORWARD_DISTANCE_STUDS (the target point is already at or
	-- behind the curve's own start, up-table-wise -- confirmed live: a
	-- hand-placed flipper marker and a hand-built slingshot box can overlap
	-- by a fraction of a stud). A curve needs positive forward room to solve
	-- a sane (non-near-zero) radius -- with none available, there's nothing
	-- to gain by forcing one; snap laterally to the target offset right at
	-- curveOrigin's own up-table position instead of erroring, since a
	-- fraction-of-a-stud sideways snap is invisible next to the overlap that
	-- caused it.
	local function buildCurveOrSnap(curveName: string, curveOrigin: CFrame, sideDirection: Vector3, curveStartLateralOffset: number, targetLateralOffset: number, forwardDistance: number, arcDirection: "Left" | "Right"): CFrame
		if forwardDistance > MIN_CURVE_FORWARD_DISTANCE_STUDS then
			local lateralDistance = targetLateralOffset - curveStartLateralOffset
			local radius, angleDegrees = solveArcForDisplacement(forwardDistance, lateralDistance)
			if radius ~= nil and angleDegrees ~= nil then
				local curveAsset = LaneGenerator.GenerateDivider({
					Name = curveName,
					Origin = curveOrigin,
					Parent = cabinetFolder,
					Config = Presets.Extend(spec.LaneDividerBasePreset, {
						Height = spec.LaneDividerHeight,
						Thickness = spec.LaneDividerThickness,
						Path = { PathType = "Curved", Radius = radius, AngleDegrees = angleDegrees, Direction = arcDirection },
						CollisionGroup = spec.PlayfieldCollisionGroup,
						IncludeTrigger = false,
					}),
				})
				return curveAsset.EndCFrame
			end
			-- Lateral shift was negligible -- no curve needed, just advance
			-- forward at the same lateral offset.
			return CFrame.fromMatrix(curveOrigin.Position + frame.TableForward * forwardDistance, frame.Right, frame.Up)
		end
		local snappedPos = snapAlongAxis(curveOrigin.Position, sideDirection, frame.CenterlineEdgePos:Dot(sideDirection) + targetLateralOffset)
		return CFrame.fromMatrix(snappedPos, frame.Right, frame.Up)
	end

	local function buildSide(name: string, sideDirection: Vector3, side: FlipperGenerator.Side, flipperOrigin: CFrame, slingshotName: string): LaneGenerator.LaneDividerAsset
		local arcDirection: "Left" | "Right" = if sideDirection:Dot(frame.Right) > 0 then "Right" else "Left"
		local flipperTopPos = computeFlipperTopPosition(flipperOrigin, side, restAngleDegrees, spec.FlipperSize, frame.TableForward)
		local curveOrigin = CFrame.fromMatrix(flipperTopPos, frame.Right, frame.Up)
		local curveStartLateralOffset = (flipperTopPos - frame.CenterlineEdgePos):Dot(sideDirection)

		local slingshotPart = findNamedBasePart(cabinetFolder, slingshotName)

		local railCenterLateralOffset: number
		local straightRunLength: number
		local curveEndCFrame: CFrame

		if slingshotPart ~= nil then
			local slingshotHalfExtentForward = computeHalfExtentAlongAxis(slingshotPart.CFrame, slingshotPart.Size, frame.TableForward)
			local slingshotHalfExtentLateral = computeHalfExtentAlongAxis(slingshotPart.CFrame, slingshotPart.Size, sideDirection)
			local slingshotOuterEdgeOffset = (slingshotPart.Position - frame.CenterlineEdgePos):Dot(sideDirection) + slingshotHalfExtentLateral
			local slingshotTopEdgePos = slingshotPart.Position + (frame.TableForward * slingshotHalfExtentForward)

			railCenterLateralOffset = slingshotOuterEdgeOffset + OUTLANE_CHANNEL_WIDTH_STUDS + spec.LaneDividerThickness / 2

			-- ONE continuous curve spans the slingshot's ENTIRE depth (target
			-- = its TOP edge, not its bottom edge) -- per the reference
			-- drawing, this is a single sweeping hook from the flipper past
			-- the slingshot, NOT a short curve feeding into a separate
			-- straight run that hugs the slingshot's own edge in parallel.
			-- Only a short tail (LaneDividerLength) continues beyond that,
			-- in whatever direction the curve ends up tangent to.
			local forwardDistanceToTopEdge = (slingshotTopEdgePos - flipperTopPos):Dot(frame.TableForward)
			curveEndCFrame = buildCurveOrSnap(name .. "_Curve", curveOrigin, sideDirection, curveStartLateralOffset, railCenterLateralOffset, forwardDistanceToTopEdge, arcDirection)
			straightRunLength = math.max(spec.LaneDividerLength, 0.1)
		else
			railCenterLateralOffset = spec.LaneDividerLateralOffset
			-- No slingshot to size the curve's target against -- reuse the
			-- straight-run length as a plain layout fallback.
			curveEndCFrame = buildCurveOrSnap(name .. "_Curve", curveOrigin, sideDirection, curveStartLateralOffset, railCenterLateralOffset, spec.LaneDividerLength, arcDirection)
			straightRunLength = spec.LaneDividerLength
		end

		return LaneGenerator.GenerateDivider({
			Name = name,
			Origin = curveEndCFrame,
			Parent = cabinetFolder,
			Config = Presets.Extend(spec.LaneDividerBasePreset, {
				Height = spec.LaneDividerHeight,
				Thickness = spec.LaneDividerThickness,
				Path = { PathType = "Straight", Length = straightRunLength },
				CollisionGroup = spec.PlayfieldCollisionGroup,
			}),
		})
	end

	local left = buildSide(spec.NewLaneDividerPrefix .. "Left", frame.LeftDirection, "Left", leftOrigin, spec.SlingshotLeftName)
	local right = buildSide(spec.NewLaneDividerPrefix .. "Right", frame.RightDirection, "Right", rightOrigin, spec.SlingshotRightName)

	-- Diagnostic only -- the rail's position above was NOT derived from this
	-- at all (see OUTLANE_CHANNEL_WIDTH_STUDS's comment). Prints how close
	-- the resulting outlane gap (rail's outer face to cabinetwalls' inner
	-- face) comes to the same 1.941-stud target, so LaneDividerThickness can
	-- be tuned by hand instead of the code forcing anything to move.
	if outerHalfWidth ~= nil then
		local function achievedOutlaneWidth(sideDirection: Vector3, slingshotName: string): number?
			local slingshotPart = findNamedBasePart(cabinetFolder, slingshotName)
			if slingshotPart == nil then
				return nil
			end
			local slingshotHalfExtentLateral = computeHalfExtentAlongAxis(slingshotPart.CFrame, slingshotPart.Size, sideDirection)
			local slingshotOuterEdgeOffset = (slingshotPart.Position - frame.CenterlineEdgePos):Dot(sideDirection) + slingshotHalfExtentLateral
			local railOuterFaceOffset = slingshotOuterEdgeOffset + OUTLANE_CHANNEL_WIDTH_STUDS + spec.LaneDividerThickness
			return (outerHalfWidth :: number) - railOuterFaceOffset
		end

		local leftOutlane = achievedOutlaneWidth(frame.LeftDirection, spec.SlingshotLeftName)
		local rightOutlane = achievedOutlaneWidth(frame.RightDirection, spec.SlingshotRightName)
		print(
			string.format(
				"CabinetUpgrade: achieved outlane width (rail's outer face to %s) -- Left: %s, Right: %s studs. Target: %.3f studs (OUTLANE_CHANNEL_WIDTH_STUDS). Adjust LaneDividerThickness (larger = narrower outlane) if these are off.",
				spec.OuterWallMarkerName :: string,
				if leftOutlane ~= nil then string.format("%.3f", leftOutlane) else "n/a",
				if rightOutlane ~= nil then string.format("%.3f", rightOutlane) else "n/a",
				OUTLANE_CHANNEL_WIDTH_STUDS
			)
		)
	end

	print(
		"CabinetUpgrade: generated "
			.. spec.NewLaneDividerPrefix
			.. "Left/"
			.. spec.NewLaneDividerPrefix
			.. "Right (each a curve landing exactly on the flipper's physical top, solved to reach the rail's position alongside the slingshot's own outer edge, + a straight run covering the slingshot's own depth plus LaneDividerLength extra studs)."
	)

	return { Left = left, Right = right }
end

export type PreviewBottomSectionSide = {
	Flipper: FlipperGenerator.FlipperAsset,
	Slingshot: SlingshotGenerator.SlingshotAsset,
	LaneDividerCurve: LaneGenerator.LaneDividerAsset?,
	LaneDividerStraight: LaneGenerator.LaneDividerAsset,
}

export type PreviewBottomSectionReport = {
	Left: PreviewBottomSectionSide,
	Right: PreviewBottomSectionSide,
}

-- Where the slingshot itself starts, up-table from each flipper's physical
-- top -- PREVIEW ONLY, not a citation, just a plausible gap so the wedge
-- doesn't visually overlap the flipper. The curve's own target is the
-- slingshot's TOP edge (see buildPreviewSide below), so this value mainly
-- controls how much of the curve happens "next to" vs. "past" the wedge, not
-- whether a curve happens at all. Tune by eye against the reference drawing;
-- it has no equivalent on a real cabinet -- there, this distance is whatever
-- the hand-built slingshot's live position already is, not something
-- authored.
local PREVIEW_SLINGSHOT_FORWARD_GAP_STUDS = 3
-- SlingshotGenerator's own defaults (Width/Depth -- see that module), not
-- re-exported from there, so restated here for this preview's own math.
local PREVIEW_SLINGSHOT_WIDTH_STUDS = 3
local PREVIEW_SLINGSHOT_DEPTH_STUDS = 2

-- Builds ONE side's flipper + slingshot + inlane/outlane guide rail as a
-- fully self-contained trio. Every relative position is AUTHORED here
-- directly from already-established numbers (FlipperSize,
-- OUTLANE_CHANNEL_WIDTH_STUDS, the flipper's own physical top via
-- computeFlipperTopPosition) -- see GeneratePreviewBottomSection's doc
-- comment for why this exists as a separate path from GenerateLaneDividers
-- rather than reading any cabinet's markers.
local function buildPreviewSide(
	parent: Instance,
	spec: CabinetSpec,
	pivotPos: Vector3,
	side: FlipperGenerator.Side,
	right: Vector3,
	up: Vector3,
	tableForward: Vector3,
	sideDirection: Vector3,
	centerlinePoint: Vector3,
	namePrefix: string
): PreviewBottomSectionSide
	local flipperOrigin = CFrame.fromMatrix(pivotPos, right, up)
	local flipperAsset = FlipperGenerator.Generate({
		Name = namePrefix .. "_Flipper",
		Origin = flipperOrigin,
		Parent = parent,
		Config = Presets.Extend(spec.FlipperBasePreset, {
			Side = side,
			RestAngleDegrees = spec.FlipperRestAngleDegrees,
			UpAngleDegrees = spec.FlipperUpAngleDegrees,
			FlipperSize = spec.FlipperSize,
			CollisionGroup = spec.FlipperCollisionGroup,
		}),
	})

	local flipperTopPos = computeFlipperTopPosition(flipperOrigin, side, spec.FlipperRestAngleDegrees, spec.FlipperSize, tableForward)

	-- SlingshotGenerator.Generate's Origin is the wedge's own back/inner
	-- corner (nearest the flipper) -- see that module's header comment --
	-- so this position IS the slingshot's own bottom-edge/inner-corner
	-- point, not a center that needs half-extents subtracted.
	local slingshotBottomEdgePos = flipperTopPos + (tableForward * PREVIEW_SLINGSHOT_FORWARD_GAP_STUDS)
	local slingshotOrigin = CFrame.fromMatrix(slingshotBottomEdgePos, right, up)
	local slingshotAsset = SlingshotGenerator.Generate({
		Name = namePrefix .. "_Slingshot",
		Origin = slingshotOrigin,
		Parent = parent,
		Config = {
			Width = PREVIEW_SLINGSHOT_WIDTH_STUDS,
			Depth = PREVIEW_SLINGSHOT_DEPTH_STUDS,
			MirrorX = side == "Left",
			CollisionGroup = spec.PlayfieldCollisionGroup,
		},
	})

	local slingshotOuterEdgeOffset = (slingshotBottomEdgePos - centerlinePoint):Dot(sideDirection) + PREVIEW_SLINGSHOT_WIDTH_STUDS
	local slingshotTopEdgePos = slingshotBottomEdgePos + (tableForward * PREVIEW_SLINGSHOT_DEPTH_STUDS)
	local railCenterLateralOffset = slingshotOuterEdgeOffset + OUTLANE_CHANNEL_WIDTH_STUDS + spec.LaneDividerThickness / 2

	local curveOrigin = CFrame.fromMatrix(flipperTopPos, right, up)
	local curveStartLateralOffset = (flipperTopPos - centerlinePoint):Dot(sideDirection)
	-- ONE continuous curve spans the slingshot's ENTIRE depth (target = its
	-- TOP edge) -- a single sweeping hook, per the reference drawing, not a
	-- short curve feeding into a straight run that hugs the slingshot's edge
	-- in parallel. See buildSide's identical fix in GenerateLaneDividers.
	local forwardDistanceToTopEdge = (slingshotTopEdgePos - flipperTopPos):Dot(tableForward)
	local arcDirection: "Left" | "Right" = if sideDirection:Dot(right) > 0 then "Right" else "Left"

	local curveEndCFrame: CFrame
	local curveAsset: LaneGenerator.LaneDividerAsset? = nil
	if forwardDistanceToTopEdge > MIN_CURVE_FORWARD_DISTANCE_STUDS then
		local lateralDistance = railCenterLateralOffset - curveStartLateralOffset
		local radius, angleDegrees = solveArcForDisplacement(forwardDistanceToTopEdge, lateralDistance)
		if radius ~= nil and angleDegrees ~= nil then
			curveAsset = LaneGenerator.GenerateDivider({
				Name = namePrefix .. "_LaneCurve",
				Origin = curveOrigin,
				Parent = parent,
				Config = Presets.Extend(spec.LaneDividerBasePreset, {
					Height = spec.LaneDividerHeight,
					Thickness = spec.LaneDividerThickness,
					Path = { PathType = "Curved", Radius = radius, AngleDegrees = angleDegrees, Direction = arcDirection },
					CollisionGroup = spec.PlayfieldCollisionGroup,
					IncludeTrigger = false,
				}),
			})
			curveEndCFrame = (curveAsset :: LaneGenerator.LaneDividerAsset).EndCFrame
		else
			curveEndCFrame = CFrame.fromMatrix(flipperTopPos + tableForward * forwardDistanceToTopEdge, right, up)
		end
	else
		local snappedPos = snapAlongAxis(flipperTopPos, sideDirection, centerlinePoint:Dot(sideDirection) + railCenterLateralOffset)
		curveEndCFrame = CFrame.fromMatrix(snappedPos, right, up)
	end

	local straightRunLength = math.max(spec.LaneDividerLength, 0.1)
	local straightAsset = LaneGenerator.GenerateDivider({
		Name = namePrefix .. "_LaneStraight",
		Origin = curveEndCFrame,
		Parent = parent,
		Config = Presets.Extend(spec.LaneDividerBasePreset, {
			Height = spec.LaneDividerHeight,
			Thickness = spec.LaneDividerThickness,
			Path = { PathType = "Straight", Length = straightRunLength },
			CollisionGroup = spec.PlayfieldCollisionGroup,
		}),
	})

	return {
		Flipper = flipperAsset,
		Slingshot = slingshotAsset,
		LaneDividerCurve = curveAsset,
		LaneDividerStraight = straightAsset,
	}
end

-- Builds a complete, SELF-CONTAINED bottom-section preview (2x flipper +
-- slingshot + inlane/outlane guide rail) at `origin`, parented directly
-- under `parent` -- NOT read from, and not positioned relative to, any
-- cabinet's existing markers, unlike every other function in this module.
-- Per direct instruction: the WilliamsCabinet-marker-driven path
-- (GenerateLaneDividers) kept producing visibly wrong geometry across
-- several rounds of fixes, and continuing to debug it against that
-- cabinet's own (possibly still-wrong) hand-placed markers wasn't
-- converging. This builds the SAME shapes from clean, authored numbers only
-- -- FlipperSize, FlipperRestAngleDegrees/UpAngleDegrees, FlipperShaftToShaftStuds,
-- OUTLANE_CHANNEL_WIDTH_STUDS, PREVIEW_SLINGSHOT_FORWARD_GAP_STUDS -- so the
-- shape itself can be judged against the reference drawing in isolation,
-- with zero contribution from whatever's currently off on any real cabinet.
-- Drop the result anywhere convenient in Workspace (a fresh folder, not
-- inside WilliamsCabinet) -- once it looks right, the SAME math already
-- powers GenerateLaneDividers for actually placing it on a real cabinet.
function CabinetUpgrade.GeneratePreviewBottomSection(parent: Instance, origin: CFrame, spec: CabinetSpec): PreviewBottomSectionReport
	local up = origin.UpVector
	local tableForward = origin.LookVector
	local right = origin.RightVector
	local centerlinePoint = origin.Position

	local halfShaftToShaft = computeShaftToShaftStuds(spec) / 2
	local leftPivotPos = centerlinePoint - (right * halfShaftToShaft)
	local rightPivotPos = centerlinePoint + (right * halfShaftToShaft)

	local left = buildPreviewSide(parent, spec, leftPivotPos, "Left", right, up, tableForward, -right, centerlinePoint, "PreviewLeft")
	local rightSide = buildPreviewSide(parent, spec, rightPivotPos, "Right", right, up, tableForward, right, centerlinePoint, "PreviewRight")

	print(
		"CabinetUpgrade: generated a standalone preview bottom section (2x flipper+slingshot+lane guide) under "
			.. parent:GetFullName()
			.. " -- fully self-contained, not positioned relative to any cabinet. Compare visually against the reference drawing before touching a real cabinet's placement."
	)

	return { Left = left, Right = rightSide }
end

-- Call ONLY after you've deleted the original FinalLeftFlipperName/
-- FinalRightFlipperName parts yourself. Errors if they still exist, so this
-- can never end up with two things both using the final name.
function CabinetUpgrade.FinalizeFlipperNames(cabinetFolder: Instance, spec: CabinetSpec)
	if cabinetFolder:FindFirstChild(spec.FinalLeftFlipperName, true) ~= nil or cabinetFolder:FindFirstChild(spec.FinalRightFlipperName, true) ~= nil then
		error(
			"CabinetUpgrade.FinalizeFlipperNames: "
				.. spec.FinalLeftFlipperName
				.. "/"
				.. spec.FinalRightFlipperName
				.. " still exist under "
				.. cabinetFolder:GetFullName()
				.. " -- delete the originals first, then call this again",
			0
		)
	end

	local newLeft = cabinetFolder:FindFirstChild(spec.NewLeftFlipperName, true)
	local newRight = cabinetFolder:FindFirstChild(spec.NewRightFlipperName, true)
	if newLeft == nil or newRight == nil then
		error(
			"CabinetUpgrade.FinalizeFlipperNames: could not find " .. spec.NewLeftFlipperName .. "/" .. spec.NewRightFlipperName .. " -- run GenerateNewFlippers first",
			0
		)
	end

	newLeft.Name = spec.FinalLeftFlipperName
	newRight.Name = spec.FinalRightFlipperName

	-- PrimitiveFactory.ReplaceOrParent matches prior generated output by the
	-- GenerationId ATTRIBUTE (AssetType .. "_" .. the Name given at
	-- generation time, e.g. "Flipper_LeftFlipper_New"), stamped once and
	-- never touched again by a plain rename -- renaming .Name alone (what
	-- this function used to do) leaves that attribute stale. The next time
	-- GenerateNewFlippers runs, it builds a fresh model whose GenerationId
	-- is that SAME "..._New" string, and ReplaceOrParent destroys whatever
	-- still carries it -- which, without this update, is the flipper this
	-- function just finalized, even though it's since been renamed away
	-- from "..._New" and looks completely unrelated in the Explorer.
	-- Re-stamping it here to the FINAL name's GenerationId makes a finalized
	-- flipper permanently immune to that collision, matching this module's
	-- own promise that nothing it builds touches a name once you've moved
	-- it out of the "New" naming.
	local assetType = newLeft:GetAttribute(Constants.ASSET_ATTRIBUTES.AssetType)
	newLeft:SetAttribute(Constants.ASSET_ATTRIBUTES.GenerationId, assetType .. "_" .. spec.FinalLeftFlipperName)
	newRight:SetAttribute(Constants.ASSET_ATTRIBUTES.GenerationId, assetType .. "_" .. spec.FinalRightFlipperName)

	print("CabinetUpgrade: renamed " .. spec.NewLeftFlipperName .. "/" .. spec.NewRightFlipperName .. " to " .. spec.FinalLeftFlipperName .. "/" .. spec.FinalRightFlipperName .. ".")
end

-- Call ONLY after you've deleted the original FinalBumperName-named markers
-- yourself. Checks for either a BasePart or a Model with that name -- see
-- resolveNamedOriginalCFrame's comment on why a BasePart-only check isn't
-- enough on every cabinet.
function CabinetUpgrade.FinalizeBumperNames(cabinetFolder: Instance, spec: CabinetSpec)
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("Model")) and trim(descendant.Name) == spec.FinalBumperName then
			error(
				"CabinetUpgrade.FinalizeBumperNames: "
					.. spec.FinalBumperName
					.. " still exists under "
					.. cabinetFolder:GetFullName()
					.. " -- delete the originals first, then call this again",
				0
			)
		end
	end

	local renamed = 0
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name:match("^" .. spec.NewBumperPrefix .. "%d+$") then
			local body = descendant:FindFirstChild("Body", true)
			if body ~= nil then
				(body :: Instance).Name = spec.FinalBumperName
				renamed += 1
			end
		end
	end

	print(string.format("CabinetUpgrade: renamed %d new bumper body part(s) to %s.", renamed, spec.FinalBumperName))
end

return CabinetUpgrade
