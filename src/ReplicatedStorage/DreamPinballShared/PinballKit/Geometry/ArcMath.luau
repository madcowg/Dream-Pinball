--!strict

-- Circular arc path generation (spec section 8 "Arc generation"). Produces the
-- same PathFrames.PathResult shape as a straight path so ProfileSweep.luau and
-- every generator can treat straight/curved paths identically.
--
-- Geometric derivation (for anyone re-deriving this, per architecture.md's
-- caution about re-verifying yaw/left-right math live rather than trusting
-- reasoning alone -- verify Left vs Right visually in Studio before trusting
-- this in a new context):
--   Let sign = +1 for "Left", -1 for "Right".
--   radiusVector0 = sign * StartCFrame.RightVector (unit vector from the arc's
--   center to the start point). center = StartPosition - radiusVector0 * Radius.
--   At arc-length parameter theta (radians, 0..totalAngle), the point rotates
--   about StartCFrame.UpVector by angle (sign * theta) using the right-hand
--   rule (CFrame.fromAxisAngle). The forward (tangent) direction at that point
--   is sign * (Up:Cross(currentRadiusVector)) -- this falls out of
--   differentiating the rotated radius vector with respect to theta, and is
--   sign-consistent so that at theta = 0 the tangent always equals
--   StartCFrame.LookVector regardless of Direction.
--   Up is held constant along the whole arc (the curve is planar, in the plane
--   spanned by StartCFrame's Right/Look vectors) -- correct for playfield-plane
--   curves; an inclined+curved ramp composes this with a separate tilt, it does
--   not tilt within ArcMath itself.

local PathFrames = require(script.Parent.PathFrames)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local ArcMath = {}

export type Direction = "Left" | "Right"

export type ArcConfig = {
	Radius: number,
	AngleDegrees: number,
	Direction: Direction,
	StartCFrame: CFrame,
	MaxSegmentLength: number?,
	MaxSagittaError: number?,
	SegmentOverlap: number?,
}

local function validateArcConfig(config: ArcConfig)
	local radiusOk, radiusErr = GeometryValidator.ValidatePositive(config.Radius, "ArcConfig.Radius")
	local angleOk, angleErr = GeometryValidator.ValidateAngleDegrees(config.AngleDegrees, "ArcConfig.AngleDegrees")

	GeometryValidator.AssertAll({
		{ ok = radiusOk, err = radiusErr },
		{ ok = angleOk, err = angleErr },
	}, "ArcMath.GenerateArc")

	if config.Direction ~= "Left" and config.Direction ~= "Right" then
		error(string.format('ArcConfig.Direction must be "Left" or "Right", got %s', tostring(config.Direction)), 0)
	end
end

-- Maximum angular step (radians) so a chord's sagitta does not exceed
-- maxSagittaError, for the given radius. Clamped so the formula never receives
-- an out-of-domain acos argument.
local function maxAngleStepForSagitta(radius: number, maxSagittaError: number): number
	local clampedError = math.clamp(maxSagittaError, 1e-6, radius)
	local acosArgument = math.clamp(1 - (clampedError / radius), -1, 1)
	return 2 * math.acos(acosArgument)
end

function ArcMath.GenerateArc(config: ArcConfig): PathFrames.PathResult
	validateArcConfig(config)

	local totalAngleRadians = math.rad(config.AngleDegrees)
	local arcLength = config.Radius * totalAngleRadians

	local maxSegmentLength = PathFrames.ResolveMaxSegmentLength(config.MaxSegmentLength, nil)
	local maxSagittaError = PathFrames.ResolveMaxSagittaError(config.MaxSagittaError, nil)

	local segmentsFromLength = PathFrames.SegmentCountFromLength(arcLength, maxSegmentLength)
	local maxAngleStep = maxAngleStepForSagitta(config.Radius, maxSagittaError)
	local segmentsFromSagitta = math.max(1, math.ceil(totalAngleRadians / maxAngleStep))
	local segmentCount = math.max(segmentsFromLength, segmentsFromSagitta)

	local sign = (config.Direction == "Left") and 1 or -1
	local startCFrame = config.StartCFrame
	local up = startCFrame.UpVector
	local radiusVector0 = startCFrame.RightVector * sign
	local center = startCFrame.Position - (radiusVector0 * config.Radius)

	local samples: { PathFrames.PathSample } = table.create(segmentCount + 1)

	for index = 0, segmentCount do
		local t = index / segmentCount
		local theta = t * totalAngleRadians
		local rotation = CFrame.fromAxisAngle(up, sign * theta)
		local currentRadiusVector = rotation:VectorToWorldSpace(radiusVector0)
		local position = center + (currentRadiusVector * config.Radius)
		local forward = (up:Cross(currentRadiusVector) * sign).Unit
		local right = currentRadiusVector * sign
		local back = -forward

		table.insert(samples, {
			CFrame = CFrame.fromMatrix(position, right, up, back),
			Position = position,
			Tangent = forward,
			Right = right,
			Up = up,
			DistanceAlongPath = t * arcLength,
		})
	end

	return {
		Samples = samples,
		Length = arcLength,
		StartCFrame = startCFrame,
		EndCFrame = samples[#samples].CFrame,
	}
end

return ArcMath
