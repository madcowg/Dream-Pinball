--!strict

-- Generic per-segment wall/rail builder, factored out of
-- Generators/LaneGenerator.luau's GenerateDivider so InlaneOutlaneGenerator
-- can reuse the exact same anti-seam wall-segment construction (spec section
-- 9: "slightly overlap consecutive collision segments," "avoid collision
-- cracks," "support metal, rubber-covered, and plastic visual styles").
-- LaneGenerator was refactored to call this too -- same math, moved verbatim,
-- so its output is unchanged.

local PrimitiveFactory = require(script.Parent.PrimitiveFactory)
local PathFrames = require(script.Parent.PathFrames)
local Constants = require(script.Parent.Parent.Constants)

local GuideRailBuilder = {}

export type GuideRailConfig = {
	Height: number,
	Thickness: number,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	PhysicalProperties: PhysicalProperties?,
	SegmentNamePrefix: string?,
	-- Small cylinder caps at the path's two ends, flush with the wall's top
	-- surface -- smooths the joint where a rail butts into a post or another
	-- rail instead of leaving a square segment endpoint (spec section 9:
	-- "use rounded joints," "a ball must not strike a square guide endpoint").
	RoundedEndCaps: boolean?,
}

export type GuideRailResult = {
	Segments: { BasePart },
	EndCaps: { BasePart },
	EndCFrame: CFrame,
}

local DEFAULT_PHYSICAL_PROPERTIES = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)

-- Builds one anchored wall segment per consecutive pair of path samples,
-- each stretched past its nominal endpoints by Constants.DEFAULT_SEGMENT_OVERLAP_STUDS
-- so neighboring segments overlap instead of butting at a zero-volume seam.
function GuideRailBuilder.BuildWallSegments(path: PathFrames.PathResult, config: GuideRailConfig, parent: Folder): GuideRailResult
	local overlap = Constants.DEFAULT_SEGMENT_OVERLAP_STUDS
	local namePrefix = config.SegmentNamePrefix or "GuideWall"
	local physicalProperties = config.PhysicalProperties or DEFAULT_PHYSICAL_PROPERTIES

	local segments: { BasePart } = {}

	for segmentIndex = 1, #path.Samples - 1 do
		local startSample = path.Samples[segmentIndex]
		local endSample = path.Samples[segmentIndex + 1]
		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local midpointPosition = (startSample.Position + endSample.Position) / 2
		local up = startSample.Up
		local right = startSample.Right
		local tangent = startSample.Tangent

		local wallCenter = midpointPosition + (up * (config.Height / 2))
		local wallCFrame = CFrame.fromMatrix(wallCenter, right, up, -tangent)

		local segment = PrimitiveFactory.CreatePart({
			Name = string.format("%s_%d", namePrefix, segmentIndex),
			Size = Vector3.new(config.Thickness, config.Height, segmentLength + overlap),
			CFrame = wallCFrame,
			Role = "Collider",
			Material = config.Material or Enum.Material.Metal,
			Color = config.Color or BrickColor.new("Really black"),
			Parent = parent,
			CollisionGroup = config.CollisionGroup,
		})
		segment.CustomPhysicalProperties = physicalProperties

		table.insert(segments, segment)
	end

	local endCaps: { BasePart } = {}
	if config.RoundedEndCaps and #path.Samples > 0 then
		for _, endpointIndex in ipairs({ 1, #path.Samples }) do
			local sample = path.Samples[endpointIndex]
			local capCenter = sample.Position + (sample.Up * (config.Height / 2))
			-- Cylinder axis is local X (Roblox convention) -- fromMatrix's first
			-- direction arg becomes local X, so passing Up here stands the
			-- cylinder vertically: axis = Height (matches the wall), diameter =
			-- Thickness, round faces horizontal, curved side facing outward.
			local cap = PrimitiveFactory.CreatePart({
				Name = string.format("%s_EndCap_%d", namePrefix, endpointIndex),
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(config.Height, config.Thickness, config.Thickness),
				CFrame = CFrame.fromMatrix(capCenter, sample.Up, sample.Right),
				Role = "Collider",
				Material = config.Material or Enum.Material.Metal,
				Color = config.Color or BrickColor.new("Really black"),
				Parent = parent,
				CollisionGroup = config.CollisionGroup,
			})
			cap.CustomPhysicalProperties = physicalProperties
			table.insert(endCaps, cap)
		end
	end

	return { Segments = segments, EndCaps = endCaps, EndCFrame = path.EndCFrame }
end

return GuideRailBuilder
