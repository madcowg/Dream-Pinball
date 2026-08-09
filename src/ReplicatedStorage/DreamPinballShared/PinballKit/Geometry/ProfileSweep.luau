--!strict

-- Sweeps a circular cross-section profile along a path (straight or curved,
-- from PathFrames/ArcMath) using overlapping thin tangential panels, per spec
-- section 8. The same function builds both the U-shaped half-pipe (180-degree
-- coverage, open toward the path's local Up) and the macaroni tunnel
-- (360-degree coverage, fully enclosed) -- only CoverageDegrees differs.
--
-- Cross-section parametrization: for a path sample with basis (Right, Up,
-- Tangent), a point on the profile circle at angle phi is
--   profileDirection(phi) = Right * sin(phi) + (-Up) * cos(phi)
-- so phi = 0 is straight down (-Up) and phi = +/-90 degrees are +/-Right. A
-- panel spanning phi in [-Coverage/2, +Coverage/2] therefore always leaves any
-- gap (360 - Coverage degrees) centered on +Up -- the "open side faces up"
-- requirement in spec section 8, satisfied for any CoverageDegrees <= 360
-- without a separate configurable open-direction field.

local Constants = require(script.Parent.Parent.Constants)
local Scale = require(script.Parent.Parent.Scale)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)
local PathFrames = require(script.Parent.PathFrames)
local PrimitiveFactory = require(script.Parent.PrimitiveFactory)

local ProfileSweep = {}

export type ProfileSweepConfig = {
	Path: PathFrames.PathResult,
	-- Inner diameter at the path's start. InnerDiameterEnd defaults to this
	-- value (a uniform-radius rail/tunnel); set it separately to build a
	-- flared entrance/exit transition (spec section 8, macaroni tunnel).
	InnerDiameterStart: number,
	InnerDiameterEnd: number?,
	CoverageDegrees: number,
	PanelThickness: number?,
	ProfilePanelCount: number?,
	PanelOverlapDegrees: number?,
	LongitudinalOverlapStuds: number?,
	Quality: Types.Quality?,
	Parent: Instance?,
	CollisionGroup: string?,
	Material: Enum.Material?,
	Color: BrickColor?,
	NamePrefix: string?,
}

export type ProfileSweepResult = {
	Panels: { BasePart },
	InnerRadiusStart: number,
	InnerRadiusEnd: number,
}

-- Gameplay-tuned defaults (spec section 3: not Williams hardware, just
-- practical starting values -- tune per preset as needed).
local DEFAULT_PANEL_THICKNESS_STUDS = 0.2
local DEFAULT_PANEL_OVERLAP_DEGREES = 4

local function validateConfig(config: ProfileSweepConfig)
	local innerDiameterEnd = config.InnerDiameterEnd or config.InnerDiameterStart
	local startOk, startErr = Scale.ValidateInnerDiameter(config.InnerDiameterStart)
	local endOk, endErr = Scale.ValidateInnerDiameter(innerDiameterEnd)
	local coverageOk, coverageErr = GeometryValidator.ValidateAngleDegrees(config.CoverageDegrees, "CoverageDegrees")
	local thicknessOk, thicknessErr = GeometryValidator.ValidatePositive(
		config.PanelThickness or DEFAULT_PANEL_THICKNESS_STUDS,
		"PanelThickness"
	)

	GeometryValidator.AssertAll({
		{ ok = startOk, err = startErr },
		{ ok = endOk, err = endErr },
		{ ok = coverageOk, err = coverageErr },
		{ ok = thicknessOk, err = thicknessErr },
	}, "ProfileSweep.Sweep")

	if #config.Path.Samples < 2 then
		error("ProfileSweep.Sweep: Path must contain at least 2 samples", 0)
	end
end

local function resolvedQuality(quality: Types.Quality?): Types.Quality
	return quality or Constants.DEFAULT_QUALITY
end

-- Number of profile panels for the requested coverage, scaled from the quality
-- level's full-circle segment target.
local function resolveProfilePanelCount(config: ProfileSweepConfig): number
	if config.ProfilePanelCount ~= nil then
		return math.max(2, config.ProfilePanelCount)
	end

	local fullCircleSegments = Constants.QUALITY_SEGMENT_PARAMS[resolvedQuality(config.Quality)].ProfileSegments
	local scaled = math.ceil(fullCircleSegments * (config.CoverageDegrees / 360))
	return math.max(2, scaled)
end

function ProfileSweep.Sweep(config: ProfileSweepConfig): ProfileSweepResult
	validateConfig(config)

	local thickness = config.PanelThickness or DEFAULT_PANEL_THICKNESS_STUDS
	local panelOverlapRadians = math.rad(config.PanelOverlapDegrees or DEFAULT_PANEL_OVERLAP_DEGREES)
	local longitudinalOverlap = config.LongitudinalOverlapStuds or Constants.DEFAULT_SEGMENT_OVERLAP_STUDS

	local innerRadiusStart = config.InnerDiameterStart / 2
	local innerRadiusEnd = (config.InnerDiameterEnd or config.InnerDiameterStart) / 2
	local pathLength = math.max(config.Path.Length, 1e-6)

	local panelCount = resolveProfilePanelCount(config)
	local coverageRadians = math.rad(config.CoverageDegrees)
	local panelAngleStep = coverageRadians / panelCount
	local startAngle = -coverageRadians / 2

	local namePrefix = config.NamePrefix or "ProfilePanel"
	local panels: { BasePart } = {}

	local samples = config.Path.Samples

	for segmentIndex = 1, #samples - 1 do
		local startSample = samples[segmentIndex]
		local endSample = samples[segmentIndex + 1]

		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local midpointPosition = (startSample.Position + endSample.Position) / 2
		local pathTangent = startSample.Tangent
		local right = startSample.Right
		local up = startSample.Up

		local panelLength = segmentLength + longitudinalOverlap

		local midDistance = (startSample.DistanceAlongPath + endSample.DistanceAlongPath) / 2
		local radiusT = midDistance / pathLength
		local panelRadius = (innerRadiusStart + (innerRadiusEnd - innerRadiusStart) * radiusT) + (thickness / 2)

		for panelIndex = 0, panelCount - 1 do
			local midAngle = startAngle + (panelAngleStep * (panelIndex + 0.5))

			local radialDir = (right * math.sin(midAngle)) + (-up * math.cos(midAngle))
			local tangentDir = (right * math.cos(midAngle)) + (up * math.sin(midAngle))

			local chordAngle = panelAngleStep + panelOverlapRadians
			local circumferentialWidth = 2 * panelRadius * math.sin(chordAngle / 2)

			local position = midpointPosition + (radialDir * panelRadius)
			-- tangentDir x radialDir = pathTangent for every midAngle (falls out
			-- of the right/up cross-product identities), so the local Z basis
			-- vector must be +pathTangent here, not -pathTangent, to keep this a
			-- proper (non-mirrored) rotation.
			local cframe = CFrame.fromMatrix(position, tangentDir, radialDir, pathTangent)

			local panel = PrimitiveFactory.CreatePart({
				Name = string.format("%s_%d_%d", namePrefix, segmentIndex, panelIndex),
				Size = Vector3.new(circumferentialWidth, thickness, panelLength),
				CFrame = cframe,
				Role = "Collider",
				Material = config.Material,
				Color = config.Color,
				Parent = config.Parent,
				CollisionGroup = config.CollisionGroup,
			})

			table.insert(panels, panel)
		end
	end

	return { Panels = panels, InnerRadiusStart = innerRadiusStart, InnerRadiusEnd = innerRadiusEnd }
end

return ProfileSweep
