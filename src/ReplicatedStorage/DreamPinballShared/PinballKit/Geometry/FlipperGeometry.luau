--!strict

-- Pure math (no Instances) for flipper pivot/gap/sweep geometry (spec
-- section 13). Every function here treats a flipper as: a pivot point + a
-- signed rest angle + a paddle length + a tip radius, using EXACTLY
-- FlipperGenerator's own tip-position formula (Origin is the pivot rest
-- pose; the same Left=1/Right=-1 direction sign FlipperGenerator applies to
-- the rest-angle rotation) so results always match what FlipperGenerator
-- will actually build. All positions are LOCAL to a shared origin (e.g. the
-- lower-playfield's own Origin) -- Up is assumed constant across that
-- origin's plane, matching this library's existing yaw-only convention (see
-- ArcMath.luau's header).
--
-- This is the fresh derivation spec section 13 asks for, for the generic
-- flat-playfield, mirrored-pair case -- NOT a fix for
-- Migrations/WilliamsCabinetSpec.luau's own marker-override workaround,
-- which solves a different problem (an already hand-built, not-necessarily-
-- symmetric cabinet) and is left untouched.

local MirrorTransform = require(script.Parent.MirrorTransform)

local FlipperGeometry = {}

export type Side = MirrorTransform.Side

export type FlipperGeometryConfig = {
	Side: Side,
	-- Local (X, _, Z) offset from the shared origin -- the flipper's pivot
	-- rest pose position, i.e. the same Origin FlipperGenerator.Generate takes.
	PivotLocal: Vector3,
	Length: number,
	RestAngleDegrees: number,
	TipRadius: number,
}

-- Local (X, Z) tip offset from the shared origin for a flipper resting at
-- `angleDegrees` (pass RestAngleDegrees for the resting tip, or a different
-- angle for the raised tip) -- the exact formula FlipperGenerator uses to
-- place its box collider, so results always match generated geometry.
local function tipLocalOffset(side: Side, pivotLocal: Vector3, length: number, angleDegrees: number): Vector3
	local direction = if side == "Left" then 1 else -1
	local usedAngleDegrees = -direction * angleDegrees
	local usedAngleRadians = math.rad(usedAngleDegrees)
	local rightLocalX = math.cos(usedAngleRadians)
	local rightLocalZ = -math.sin(usedAngleRadians)
	local flipperOffsetX = if side == "Left" then length / 2 else -length / 2
	local reach = 2 * flipperOffsetX
	return Vector3.new(pivotLocal.X + rightLocalX * reach, pivotLocal.Y, pivotLocal.Z + rightLocalZ * reach)
end

function FlipperGeometry.ComputeTipPosition(config: FlipperGeometryConfig, angleDegrees: number?): Vector3
	return tipLocalOffset(config.Side, config.PivotLocal, config.Length, angleDegrees or config.RestAngleDegrees)
end

-- Surface-to-surface gap between two flippers' tip colliders at rest.
function FlipperGeometry.GetRestingTipGap(left: FlipperGeometryConfig, right: FlipperGeometryConfig): number
	local leftTip = FlipperGeometry.ComputeTipPosition(left)
	local rightTip = FlipperGeometry.ComputeTipPosition(right)
	return (rightTip - leftTip).Magnitude - left.TipRadius - right.TipRadius
end

-- Same, but at explicit (raised) angles instead of each side's RestAngleDegrees.
function FlipperGeometry.GetActiveTipGap(
	left: FlipperGeometryConfig,
	leftActiveAngleDegrees: number,
	right: FlipperGeometryConfig,
	rightActiveAngleDegrees: number
): number
	local leftTip = FlipperGeometry.ComputeTipPosition(left, leftActiveAngleDegrees)
	local rightTip = FlipperGeometry.ComputeTipPosition(right, rightActiveAngleDegrees)
	return (rightTip - leftTip).Magnitude - left.TipRadius - right.TipRadius
end

-- Solves the pivot half-spacing (LEFT pivot at local X = -result, RIGHT
-- pivot at +result, same Z) so a mirrored pair rests with exactly
-- `desiredGapStuds` between tip surfaces. Derived directly from
-- tipLocalOffset("Right", ...): tipRight.X = pivotX - length * cos(rad(restAngleDegrees)),
-- and by mirror symmetry the resting gap runs purely along X. cos() is even,
-- so this is correct regardless of RestAngleDegrees's own sign. Assumes both
-- flippers share Length/RestAngleDegrees/TipRadius and rest at the same Z --
-- true for any mirrored pair built via MirrorTransform, the only supported
-- layout for this solver.
function FlipperGeometry.SolvePivotOffsetForCenterGap(desiredGapStuds: number, length: number, restAngleDegrees: number, tipRadius: number): number
	local cosRestAngle = math.cos(math.rad(restAngleDegrees))
	return (desiredGapStuds / 2) + tipRadius + (length * cosRestAngle)
end

export type SweptEnvelope = {
	PivotLocal: Vector3,
	RootRadius: number,
	TipRadius: number,
	TipSamplesLocal: { Vector3 },
}

local DEFAULT_SWEEP_SAMPLES = 10

-- Samples tip position across the flipper's stroke, from RestAngleDegrees to
-- an active angle (both read through the SAME ComputeTipPosition formula --
-- not a signed hinge delta, so no SWEEP_DIRECTION duplication is needed
-- here). Defaults the active angle to RestAngleDegrees + strokeDegrees; this
-- direction has NOT been verified live and matches this project's own
-- repeated caution about yaw-sign reasoning (architecture.md "Flipper
-- baseline") -- pass an explicit activeAngleDegreesOverride once confirmed in
-- Studio if the default turns out to sweep the wrong way.
function FlipperGeometry.GetSweptEnvelope(
	config: FlipperGeometryConfig,
	rootRadius: number,
	strokeDegrees: number,
	activeAngleDegreesOverride: number?,
	sampleCount: number?
): SweptEnvelope
	local activeAngleDegrees = activeAngleDegreesOverride or (config.RestAngleDegrees + strokeDegrees)
	local samples = sampleCount or DEFAULT_SWEEP_SAMPLES
	local tipSamples: { Vector3 } = table.create(samples + 1)

	for i = 0, samples do
		local t = i / samples
		local angle = config.RestAngleDegrees + t * (activeAngleDegrees - config.RestAngleDegrees)
		tipSamples[i + 1] = tipLocalOffset(config.Side, config.PivotLocal, config.Length, angle)
	end

	return {
		PivotLocal = config.PivotLocal,
		RootRadius = rootRadius,
		TipRadius = config.TipRadius,
		TipSamplesLocal = tipSamples,
	}
end

-- Closest distance from point `p` to segment [a, b] -- generic 3D
-- point-segment distance, used to check the swept envelope against static
-- guide-rail segments.
local function distancePointToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local abLengthSquared = ab:Dot(ab)
	if abLengthSquared < 1e-8 then
		return (p - a).Magnitude
	end
	local t = math.clamp((p - a):Dot(ab) / abLengthSquared, 0, 1)
	local closest = a + (ab * t)
	return (p - closest).Magnitude
end

-- True if any sampled point along the swept envelope (root or tip circle)
-- comes within `pointRadius` of `pointLocal` -- e.g. a sling post's position
-- and radius, per spec section 13's "flipper sweep intersects a sling post."
function FlipperGeometry.SweepIntersectsPoint(envelope: SweptEnvelope, pointLocal: Vector3, pointRadius: number): boolean
	if (envelope.PivotLocal - pointLocal).Magnitude < (envelope.RootRadius + pointRadius) then
		return true
	end
	for _, tip in ipairs(envelope.TipSamplesLocal) do
		if (tip - pointLocal).Magnitude < (envelope.TipRadius + pointRadius) then
			return true
		end
	end
	return false
end

-- Same, against a static line segment (e.g. a lane guide wall panel), per
-- spec section 13's "flipper sweep intersects a lane guide."
function FlipperGeometry.SweepIntersectsSegment(envelope: SweptEnvelope, segmentA: Vector3, segmentB: Vector3, segmentRadius: number): boolean
	if distancePointToSegment(envelope.PivotLocal, segmentA, segmentB) < (envelope.RootRadius + segmentRadius) then
		return true
	end
	for _, tip in ipairs(envelope.TipSamplesLocal) do
		if distancePointToSegment(tip, segmentA, segmentB) < (envelope.TipRadius + segmentRadius) then
			return true
		end
	end
	return false
end

return FlipperGeometry
