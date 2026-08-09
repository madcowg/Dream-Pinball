--!strict

-- Combines PathFrames (straight) and ArcMath (curved) behind one spec so every
-- generator that needs "straight or curved, pick one config shape" (rails,
-- tunnels, ramps, wireforms -- spec sections 8) can share the same call site
-- instead of branching on path type itself.

local PathFrames = require(script.Parent.PathFrames)
local ArcMath = require(script.Parent.ArcMath)
local Types = require(script.Parent.Parent.Types)

local PathBuilder = {}

export type PathType = "Straight" | "Curved"

export type PathSpec = {
	PathType: PathType,
	-- Straight-only:
	Length: number?,
	-- Curved-only:
	Radius: number?,
	AngleDegrees: number?,
	Direction: ArcMath.Direction?,
	-- Shared:
	MaxSegmentLength: number?,
	MaxSagittaError: number?,
	Quality: Types.Quality?,
}

function PathBuilder.Build(startCFrame: CFrame, spec: PathSpec): PathFrames.PathResult
	if spec.PathType == "Straight" then
		if spec.Length == nil then
			error("PathBuilder.Build: PathSpec.Length is required when PathType is \"Straight\"", 0)
		end

		return PathFrames.BuildStraightPath(startCFrame, spec.Length :: number, {
			MaxSegmentLength = spec.MaxSegmentLength,
			Quality = spec.Quality,
		})
	elseif spec.PathType == "Curved" then
		if spec.Radius == nil or spec.AngleDegrees == nil or spec.Direction == nil then
			error(
				"PathBuilder.Build: PathSpec.Radius, AngleDegrees, and Direction are all required when PathType is \"Curved\"",
				0
			)
		end

		return ArcMath.GenerateArc({
			Radius = spec.Radius :: number,
			AngleDegrees = spec.AngleDegrees :: number,
			Direction = spec.Direction :: ArcMath.Direction,
			StartCFrame = startCFrame,
			MaxSegmentLength = spec.MaxSegmentLength,
			MaxSagittaError = spec.MaxSagittaError,
		})
	end

	error(string.format('PathBuilder.Build: PathSpec.PathType must be "Straight" or "Curved", got %s', tostring(spec.PathType)), 0)
end

return PathBuilder
