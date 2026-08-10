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
local FlipperGenerator = require(PinballKit.Generators.FlipperGenerator)
local BumperGenerator = require(PinballKit.Generators.BumperGenerator)
local LaneGenerator = require(PinballKit.Generators.LaneGenerator)
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
	PlaysurfaceName: string?,
	-- The fixed point the whole flipper layout is centered/anchored on --
	-- e.g. "DrainTrigger", which sits on the table's own centerline. Must be
	-- a BasePart (its Size is used to find its up-table edge).
	CenterlineMarkerName: string,
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
	-- instead of a separately-guessed shaft-to-shaft constant, so all three
	-- numbers stay a single coherent unit rather than three independent
	-- guesses that can silently disagree with each other.
	FlipperRestTipGapStuds: number,
	-- How far up-table (in studs) the flipper pivots sit from
	-- CenterlineMarkerName's own up-table edge (not its center) -- e.g. "6
	-- studs up from the edge of DrainTrigger". Ignored when the four marker
	-- names below are given and found.
	FlipperUpTableOffsetFromCenterlineEdgeStuds: number,

	-- Optional position-only escape hatch: if ALL FOUR of these marker names
	-- resolve to real BaseParts, GenerateNewFlippers uses their positions
	-- directly (pivot position + tip-minus-pivot direction) instead of the
	-- analytic centerline derivation above -- no rotation to get right, no
	-- sign convention to match, just "where did you put these two points."
	-- Use this when the analytic derivation keeps coming out wrong despite
	-- correct measurements (as happened repeatedly on WilliamsCabinet) --
	-- place each pair by eye against a reference photo. See
	-- CabinetUpgrade.luau's computeFlipperOriginsFromMarkers for exactly how
	-- they're used.
	LeftFlipperPivotMarkerName: string?,
	LeftFlipperTipMarkerName: string?,
	RightFlipperPivotMarkerName: string?,
	RightFlipperTipMarkerName: string?,

	-- Uniform scale applied to every WilliamsClassic.PopBumper dimension, to
	-- account for a cabinet hand-built at a different size than the preset's
	-- reference scale. An ESTIMATE unless you've separately measured a real
	-- bumper on this cabinet -- see WilliamsCabinetSpec.luau.
	BumperScale: number,

	-- Lane-divider placement: the WHOLE in-lane/out-lane guide (not a short
	-- decorative section) -- a plain straight wall running up-table from near
	-- the bottom of the playing board, parallel to TableForward.
	-- LaneDividerLateralOffset is only used as a fallback ESTIMATE when
	-- OuterWallMarkerName isn't given or isn't found -- otherwise the wall's
	-- own extent decides the distance.
	LaneDividerLength: number,
	LaneDividerLateralOffset: number,
	-- How far up-table (in studs) the divider's BOTTOM end starts from
	-- CenterlineMarkerName's own up-table edge -- independent of
	-- FlipperUpTableOffsetFromCenterlineEdgeStuds, since the lane guide
	-- starts nearer the very bottom of the board, not at the flipper pivot.
	LaneDividerStartOffsetFromCenterlineEdgeStuds: number,
	-- Height/thickness override matched to WilliamsClassic.Slingshot's own
	-- Height (2 studs) instead of LaneGenerator's ball-diameter-based default
	-- -- a lane guide next to a slingshot should read as the same height as
	-- the slingshot, not a shorter cosmetic curb.
	LaneDividerHeight: number,

	-- Style base (colors/materials/mechanism tuning) each new part starts
	-- from before the measured overrides above are applied via Presets.Extend.
	-- Not necessarily WilliamsClassic -- a differently-styled cabinet passes
	-- its own preset family here.
	FlipperBasePreset: FlipperGenerator.FlipperConfig,
	BumperBasePreset: BumperGenerator.BumperConfig,
	LaneDividerBasePreset: LaneGenerator.LaneDividerConfig,
}

-- Reads a world up-vector off either a BasePart or a Model (playsurface may
-- be either, per the Explorer).
local function upVectorOf(instance: Instance): Vector3
	if instance:IsA("BasePart") then
		return instance.CFrame.UpVector
	elseif instance:IsA("Model") then
		return instance:GetPivot().UpVector
	end
	error("CabinetUpgrade: " .. instance:GetFullName() .. " is neither a BasePart nor a Model, can't read its orientation", 0)
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
		if descendant.Name == name and descendant:IsA("BasePart") then
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

-- Playsurface's own surface normal, sign-corrected to point mostly skyward
-- (in case the mesh was authored upside down), falling back to world-up if
-- there's no playsurface marker. Shared by computeTableFrame and the
-- marker-based flipper path below, so both agree on which way is "up."
local function computeUp(cabinetFolder: Instance, spec: CabinetSpec): Vector3
	local playsurface = if spec.PlaysurfaceName ~= nil then cabinetFolder:FindFirstChild(spec.PlaysurfaceName, true) else nil
	local up = if playsurface ~= nil then upVectorOf(playsurface) else Vector3.new(0, 1, 0)
	if up:Dot(Vector3.new(0, 1, 0)) < 0 then
		up = -up
	end
	return up
end

export type FlipperMarkerOrigins = {
	LeftOrigin: CFrame,
	RightOrigin: CFrame,
}

-- If all four marker names are given AND resolve to real BaseParts, computes
-- flipper Origins directly from their positions -- pure position, no
-- rotation/sign ambiguity at all (the analytic centerline derivation below
-- has come out wrong on position and/or rest-angle sign multiple times on
-- WilliamsCabinet despite real measurements; this sidesteps that entirely).
-- Place each pair by eye against a reference photo: Pivot at the hinge
-- point, Tip at where the paddle's far end should rest -- position only, no
-- rotation needed on the marker parts themselves.
--
-- FlipperGenerator's Origin convention: with RestAngleDegrees = 0, the bat
-- extends from pivot along Origin's local +X (Right) for Side="Left", local
-- -X for Side="Right". So Right is set directly to the Left tip's direction,
-- and to the Right tip's direction negated -- and RestAngleDegrees = 0 is
-- forced for both by the caller when this path is used, since the tip
-- marker's direction already IS the desired rest angle; nothing left to
-- rotate.
local function computeFlipperOriginsFromMarkers(cabinetFolder: Instance, spec: CabinetSpec): FlipperMarkerOrigins?
	if spec.LeftFlipperPivotMarkerName == nil or spec.LeftFlipperTipMarkerName == nil or spec.RightFlipperPivotMarkerName == nil or spec.RightFlipperTipMarkerName == nil then
		return nil
	end

	local leftPivot = findNamedBasePart(cabinetFolder, spec.LeftFlipperPivotMarkerName)
	local leftTip = findNamedBasePart(cabinetFolder, spec.LeftFlipperTipMarkerName)
	local rightPivot = findNamedBasePart(cabinetFolder, spec.RightFlipperPivotMarkerName)
	local rightTip = findNamedBasePart(cabinetFolder, spec.RightFlipperTipMarkerName)
	if leftPivot == nil or leftTip == nil or rightPivot == nil or rightTip == nil then
		return nil
	end

	local up = computeUp(cabinetFolder, spec)
	local leftBatDirection = (leftTip.Position - leftPivot.Position).Unit
	local rightBatDirection = (rightTip.Position - rightPivot.Position).Unit

	return {
		LeftOrigin = CFrame.fromMatrix(leftPivot.Position, leftBatDirection, up),
		RightOrigin = CFrame.fromMatrix(rightPivot.Position, -rightBatDirection, up),
	}
end

-- Analytic shaft-to-shaft distance from three independently-measured
-- numbers, so they stay one coherent unit instead of three separate guesses
-- that can silently disagree: each flipper's rest tip sits FlipperSize.X away
-- from its own pivot, foreshortened laterally by cos(RestAngleDegrees); the
-- two tips' lateral gap is FlipperRestTipGapStuds. So
-- ShaftToShaft = Gap + 2*Length*cos(RestAngle).
local function computeShaftToShaftStuds(spec: CabinetSpec): number
	return spec.FlipperRestTipGapStuds + 2 * spec.FlipperSize.X * math.cos(math.rad(spec.FlipperRestAngleDegrees))
end

-- Fully analytic construction from the CabinetSpec -- doesn't require
-- LeftFlipper/RightFlipper (or anything else flipper-shaped) to already
-- exist, and does NOT use the slingshots' current position as a placement
-- reference (an earlier version did; confirmed wrong against a live Studio
-- measurement, and the slingshots themselves are expected to move to match
-- this layout, not the other way around).
--   - Up = the playsurface's own surface normal (sign-corrected to point
--     mostly skyward, in case the mesh was authored upside down), falling
--     back to world-up if there's no playsurface marker.
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

	local up = computeUp(cabinetFolder, spec)

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

	local centerlineEdgePos = markerCFrame.Position + (tableForward * halfExtentAlongForward)
	local anchorPoint = centerlineEdgePos + (tableForward * spec.FlipperUpTableOffsetFromCenterlineEdgeStuds)

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

-- Builds one new bumper per EXISTING FinalBumperName-named marker, at the
-- same position, named NewBumperPrefix .. index -- also untouched originals.
-- The marker can be a plain BasePart OR a Model wrapping a differently-named
-- Part (see resolveNamedOriginalCFrame) -- a plain BasePart-only check found
-- zero matches on a live cabinet where "Bumper" turned out to be a Model.
function CabinetUpgrade.GenerateNewBumpers(cabinetFolder: Instance, spec: CabinetSpec): number
	local originals: { { CFrame: CFrame, PointValue: any } } = {}
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if descendant.Name == spec.FinalBumperName then
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

-- Margin kept between the divider and the outer wall's own face, so it
-- doesn't clip into the wall -- not a ball-clearance figure (this is a
-- structural margin against another static part, not a path the ball
-- travels through), just enough to avoid two static parts overlapping.
local OUTER_WALL_INSET_STUDS = 1

-- Builds the in-lane/out-lane divider walls flanking the flippers -- pure new
-- additions, not replacements (most hand-built cabinets, including
-- WilliamsCabinet, have none today). No Finalize step: there's no original
-- name to protect, so these are generated directly under their real names
-- and can simply be re-run (idempotent replace-by-name) as you tune the
-- CabinetSpec.
--
-- A plain straight wall running up-table, parallel to TableForward -- not
-- angled (an earlier version swept it toward an "outward angle" estimate,
-- which produced a confusing result on top of the flipper-placement bug it
-- was compounding). This is the WHOLE in-lane/out-lane guide, not a short
-- decorative section -- it starts near the bottom of the board
-- (CenterlineEdgePos + LaneDividerStartOffsetFromCenterlineEdgeStuds, NOT
-- tied to the flipper pivot -- a real lane guide starts closer to the drain
-- corners than the flippers sit) and runs LaneDividerLength studs up-table.
-- Height is pinned to LaneDividerHeight (matched to the slingshot's own
-- height) rather than LaneGenerator's ball-diameter default, so it reads as
-- part of the same structure as the slingshot, not a shorter curb.
-- Lateral position comes from the cabinet's actual outer wall extent
-- (OuterWallMarkerName) when available -- "at the edges of the playing
-- board" -- falling back to LaneDividerLateralOffset as a plain estimate
-- otherwise.
function CabinetUpgrade.GenerateLaneDividers(cabinetFolder: Instance, spec: CabinetSpec): NewLaneDividersReport
	local frame = computeTableFrame(cabinetFolder, spec)
	local outerHalfWidth = computeOuterHalfWidth(cabinetFolder, spec, frame.Right)
	local lateralOffset = if outerHalfWidth ~= nil then math.max(0.1, outerHalfWidth - OUTER_WALL_INSET_STUDS) else spec.LaneDividerLateralOffset
	local startAnchor = frame.CenterlineEdgePos + (frame.TableForward * spec.LaneDividerStartOffsetFromCenterlineEdgeStuds)

	local function buildSide(name: string, sideDirection: Vector3): LaneGenerator.LaneDividerAsset
		local startPos = startAnchor + sideDirection * lateralOffset
		local origin = CFrame.fromMatrix(startPos, frame.Right, frame.Up)

		return LaneGenerator.GenerateDivider({
			Name = name,
			Origin = origin,
			Parent = cabinetFolder,
			Config = Presets.Extend(spec.LaneDividerBasePreset, {
				Height = spec.LaneDividerHeight,
				Path = { PathType = "Straight", Length = spec.LaneDividerLength },
				CollisionGroup = spec.PlayfieldCollisionGroup,
			}),
		})
	end

	local left = buildSide(spec.NewLaneDividerPrefix .. "Left", frame.LeftDirection)
	local right = buildSide(spec.NewLaneDividerPrefix .. "Right", frame.RightDirection)

	local sourceNote = if outerHalfWidth ~= nil
		then string.format("anchored to %s's own extent (%.3f studs from centerline).", spec.OuterWallMarkerName :: string, lateralOffset)
		else string.format("using the LaneDividerLateralOffset ESTIMATE (%.3f studs from the flipper pivot) -- no OuterWallMarkerName found.", lateralOffset)
	print("CabinetUpgrade: generated " .. spec.NewLaneDividerPrefix .. "Left/" .. spec.NewLaneDividerPrefix .. "Right, " .. sourceNote)

	return { Left = left, Right = right }
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
	print("CabinetUpgrade: renamed " .. spec.NewLeftFlipperName .. "/" .. spec.NewRightFlipperName .. " to " .. spec.FinalLeftFlipperName .. "/" .. spec.FinalRightFlipperName .. ".")
end

-- Call ONLY after you've deleted the original FinalBumperName-named markers
-- yourself. Checks for either a BasePart or a Model with that name -- see
-- resolveNamedOriginalCFrame's comment on why a BasePart-only check isn't
-- enough on every cabinet.
function CabinetUpgrade.FinalizeBumperNames(cabinetFolder: Instance, spec: CabinetSpec)
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if (descendant:IsA("BasePart") or descendant:IsA("Model")) and descendant.Name == spec.FinalBumperName then
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
