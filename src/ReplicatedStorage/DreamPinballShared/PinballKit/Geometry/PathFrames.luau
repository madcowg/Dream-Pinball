--!strict

-- Shared path-sampling types and straight-path generation. ArcMath.luau builds
-- on the same PathSample/PathResult shape for curved paths, so ProfileSweep.luau
-- (and every generator that sweeps a cross-section) can consume either without
-- caring whether the underlying path was straight or curved.
--
-- Frame convention: a path's "forward" direction at any sample is CFrame.LookVector
-- (Roblox's local -Z), "right" is CFrame.RightVector (local +X), "up" is
-- CFrame.UpVector (local +Y) -- the same convention as every other CFrame in this
-- codebase (e.g. CabinetBuilder's ramp frames).

local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)

local PathFrames = {}

export type PathSample = {
	CFrame: CFrame,
	Position: Vector3,
	Tangent: Vector3,
	Right: Vector3,
	Up: Vector3,
	DistanceAlongPath: number,
}

export type PathResult = {
	Samples: { PathSample },
	Length: number,
	StartCFrame: CFrame,
	EndCFrame: CFrame,
}

-- Resolves an optional MaxSegmentLength against the given quality's default.
function PathFrames.ResolveMaxSegmentLength(maxSegmentLength: number?, quality: Types.Quality?): number
	if maxSegmentLength ~= nil then
		return maxSegmentLength
	end

	local resolvedQuality: Types.Quality = quality or Constants.DEFAULT_QUALITY
	return Constants.QUALITY_SEGMENT_PARAMS[resolvedQuality].MaxSegmentLength
end

function PathFrames.ResolveMaxSagittaError(maxSagittaError: number?, quality: Types.Quality?): number
	if maxSagittaError ~= nil then
		return maxSagittaError
	end

	local resolvedQuality: Types.Quality = quality or Constants.DEFAULT_QUALITY
	return Constants.QUALITY_SEGMENT_PARAMS[resolvedQuality].MaxSagittaError
end

-- Number of segments needed so no single segment exceeds maxSegmentLength.
function PathFrames.SegmentCountFromLength(length: number, maxSegmentLength: number): number
	return math.max(1, math.ceil(length / maxSegmentLength))
end

-- Builds a straight-line path of the given length starting at startCFrame,
-- travelling along startCFrame.LookVector. Orientation is constant along the
-- whole path.
function PathFrames.BuildStraightPath(
	startCFrame: CFrame,
	length: number,
	options: { MaxSegmentLength: number?, Quality: Types.Quality? }?
): PathResult
	local resolvedOptions = options or {}
	local maxSegmentLength = PathFrames.ResolveMaxSegmentLength(resolvedOptions.MaxSegmentLength, resolvedOptions.Quality)
	local segmentCount = PathFrames.SegmentCountFromLength(length, maxSegmentLength)

	local rotationOnly = startCFrame - startCFrame.Position
	local forward = startCFrame.LookVector
	local right = startCFrame.RightVector
	local up = startCFrame.UpVector

	local samples: { PathSample } = table.create(segmentCount + 1)

	for index = 0, segmentCount do
		local t = index / segmentCount
		local distance = t * length
		local position = startCFrame.Position + forward * distance
		local cframe = CFrame.new(position) * rotationOnly

		table.insert(samples, {
			CFrame = cframe,
			Position = position,
			Tangent = forward,
			Right = right,
			Up = up,
			DistanceAlongPath = distance,
		})
	end

	return {
		Samples = samples,
		Length = length,
		StartCFrame = startCFrame,
		EndCFrame = samples[#samples].CFrame,
	}
end

return PathFrames
