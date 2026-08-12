--!strict

-- Perpendicular-offset boundaries for inlane/outlane channels (spec section
-- 9: "measure channel clearance perpendicular to the lane centerline, not
-- simply along the global X axis"). Builds on PathBuilder/PathFrames's
-- existing straight-or-curved centerline samples -- this module only adds the
-- left/right offset step, it does not re-derive path math.

local PathFrames = require(script.Parent.PathFrames)
local Scale = require(script.Parent.Parent.Scale)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local LanePath = {}

export type LaneBoundarySample = {
	Position: Vector3,
	Right: Vector3,
	Up: Vector3,
	Tangent: Vector3,
	DistanceAlongPath: number,
}

export type LaneBoundaries = {
	Inner: { LaneBoundarySample },
	Outer: { LaneBoundarySample },
	ClearWidth: number,
}

-- Validates a configured clear width against an absolute floor (spec
-- section 2's "Absolute minimum lane width: 1.70 studs" by default).
function LanePath.ValidateClearWidth(clearWidthStuds: number, minimumStuds: number?, fieldName: string?): (boolean, string?)
	local minimum = minimumStuds or Scale.DEFAULT_INNER_DIAMETER_STUDS
	local name = fieldName or "ClearWidth"

	local positiveOk, positiveErr = GeometryValidator.ValidatePositive(clearWidthStuds, name)
	if not positiveOk then
		return false, positiveErr
	end

	if clearWidthStuds < minimum then
		return false, string.format("%s (%.4f studs) is below the minimum lane width of %.4f studs", name, clearWidthStuds, minimum)
	end

	return true, nil
end

-- Offsets a centerline path both directions along each sample's own Right
-- vector (perpendicular to the path's tangent, not global X) by half the
-- clear width, producing the two boundary rails a lane's walls follow.
function LanePath.OffsetBoundaries(centerline: PathFrames.PathResult, clearWidthStuds: number): LaneBoundaries
	local ok, err = LanePath.ValidateClearWidth(clearWidthStuds)
	if not ok then
		error("LanePath.OffsetBoundaries: " .. (err :: string), 0)
	end

	local halfWidth = clearWidthStuds / 2
	local inner: { LaneBoundarySample } = table.create(#centerline.Samples)
	local outer: { LaneBoundarySample } = table.create(#centerline.Samples)

	for index, sample in ipairs(centerline.Samples) do
		inner[index] = {
			Position = sample.Position - (sample.Right * halfWidth),
			Right = sample.Right,
			Up = sample.Up,
			Tangent = sample.Tangent,
			DistanceAlongPath = sample.DistanceAlongPath,
		}
		outer[index] = {
			Position = sample.Position + (sample.Right * halfWidth),
			Right = sample.Right,
			Up = sample.Up,
			Tangent = sample.Tangent,
			DistanceAlongPath = sample.DistanceAlongPath,
		}
	end

	return { Inner = inner, Outer = outer, ClearWidth = clearWidthStuds }
end

-- Perpendicular distance between two world points, measured along a given
-- centerline sample's own Right axis -- the "measure clearance perpendicular
-- to the lane centerline" primitive every lane-width validation check should
-- use instead of a raw |a.X - b.X| comparison.
function LanePath.MeasurePerpendicularWidth(centerlineSample: PathFrames.PathSample, pointA: Vector3, pointB: Vector3): number
	local delta = pointB - pointA
	return math.abs(delta:Dot(centerlineSample.Right))
end

return LanePath
