--!strict

-- Post-generation validation for a LowerPlayfieldGenerator.LowerPlayfieldAsset
-- (spec section 21). GeometryValidator/Scale checks raw config before
-- geometry exists; AssetValidator checks any single generated Model's
-- Instance tree; this module is the third layer -- checks that only make
-- sense across the WHOLE composed assembly (symmetry, gap, sweep-vs-static-
-- geometry). Same (boolean, string?)-style reporting convention as the
-- other validators, wrapped in one ValidationReport.

local Scale = require(script.Parent.Parent.Scale)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)
local FlipperGeometry = require(script.Parent.Parent.Geometry.FlipperGeometry)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local LowerPlayfieldGenerator = require(script.Parent.Parent.Generators.LowerPlayfieldGenerator)

local LowerPlayfieldValidator = {}

export type ValidationReport = {
	Ok: boolean,
	Errors: { string },
}

-- Spec section 6: "Default symmetry error remains below 0.01 studs."
local SYMMETRY_TOLERANCE_STUDS = 0.01
local DEFAULT_TIP_RADIUS_STUDS = 0.45
local DEFAULT_ROOT_RADIUS_STUDS = 0.6
local DEFAULT_REST_ANGLE_DEGREES = -30
local DEFAULT_UP_ANGLE_DEGREES = 50

local function checkSymmetry(origin: CFrame, leftWorldPosition: Vector3, rightWorldPosition: Vector3, label: string, errors: { string })
	local mirroredLeft = MirrorTransform.MirrorPosition(origin, leftWorldPosition)
	local delta = (mirroredLeft - rightWorldPosition).Magnitude
	if delta > SYMMETRY_TOLERANCE_STUDS then
		table.insert(
			errors,
			string.format("%s symmetry error %.4f studs exceeds the %.4f-stud tolerance", label, delta, SYMMETRY_TOLERANCE_STUDS)
		)
	end
end

local function flipperGeometryFromAsset(
	origin: CFrame,
	side: MirrorTransform.Side,
	pivotWorldPosition: Vector3,
	config: LowerPlayfieldGenerator.LowerPlayfieldConfig
): FlipperGeometry.FlipperGeometryConfig
	local flipperConfig = config.Flipper
	return {
		Side = side,
		PivotLocal = origin:PointToObjectSpace(pivotWorldPosition),
		Length = (flipperConfig.FlipperSize :: Vector3).X,
		RestAngleDegrees = flipperConfig.RestAngleDegrees or DEFAULT_REST_ANGLE_DEGREES,
		TipRadius = flipperConfig.TipRadius or DEFAULT_TIP_RADIUS_STUDS,
	}
end

-- Full validation pass against an already-generated asset + the config it
-- was generated from. Run from Studio's Command Bar (no headless runtime --
-- see PinballKit/README.md's "Known Roblox physics limitations").
function LowerPlayfieldValidator.Validate(
	asset: LowerPlayfieldGenerator.LowerPlayfieldAsset,
	config: LowerPlayfieldGenerator.LowerPlayfieldConfig,
	origin: CFrame
): ValidationReport
	local errors: { string } = {}

	-- Dimensions (spec section 21).
	if Scale.BALL_DIAMETER_STUDS ~= 1.5 then
		table.insert(errors, "Scale.BALL_DIAMETER_STUDS is not 1.5 studs")
	end

	local flipperLength = (config.Flipper.FlipperSize :: Vector3).X
	local flipperLengthOk, flipperLengthErr = GeometryValidator.ValidatePositive(flipperLength, "Flipper length")
	if not flipperLengthOk then
		table.insert(errors, flipperLengthErr :: string)
	end

	local minimumGap = math.max(config.MinimumCenterDrainWidth or Scale.DEFAULT_INNER_DIAMETER_STUDS, Scale.DEFAULT_INNER_DIAMETER_STUDS)
	if asset.RestingTipGap < minimumGap then
		table.insert(
			errors,
			string.format("Resting center drain gap %.4f studs is below the minimum %.4f studs", asset.RestingTipGap, minimumGap)
		)
	end

	local laneMinimum = math.max(config.Lanes.MinimumClearance or Scale.DEFAULT_INNER_DIAMETER_STUDS, Scale.DEFAULT_INNER_DIAMETER_STUDS)
	local inlaneWidth = config.Lanes.InlaneClearWidth or 1.85
	local outlaneWidth = config.Lanes.OutlaneClearWidth or 1.85
	if inlaneWidth < laneMinimum then
		table.insert(errors, string.format("InlaneClearWidth %.4f studs is below the minimum %.4f studs", inlaneWidth, laneMinimum))
	end
	if outlaneWidth < laneMinimum then
		table.insert(errors, string.format("OutlaneClearWidth %.4f studs is below the minimum %.4f studs", outlaneWidth, laneMinimum))
	end

	-- Symmetry (spec section 21): mirror every Left reference point and diff
	-- against the actual Right one.
	checkSymmetry(origin, asset.Left.Flipper.Root.Position, asset.Right.Flipper.Root.Position, "Flipper pivot", errors)
	checkSymmetry(origin, asset.Left.Slingshot.Root.Position, asset.Right.Slingshot.Root.Position, "Slingshot", errors)
	checkSymmetry(origin, asset.Left.Lanes.Root.Position, asset.Right.Lanes.Root.Position, "Lane divider start", errors)

	-- Collision (spec section 21): flipper sweep vs. sling posts and lane
	-- guide segments, using the same sampled-envelope approach
	-- FlipperGeometry uses everywhere else (a few reliable checks, not exact
	-- analytic geometry).
	local rootRadius = config.Flipper.RootRadius or DEFAULT_ROOT_RADIUS_STUDS
	local upAngleDegrees = config.Flipper.UpAngleDegrees or DEFAULT_UP_ANGLE_DEGREES

	for _, side in ipairs({ "Left", "Right" } :: { MirrorTransform.Side }) do
		local sideAsset = if side == "Left" then asset.Left else asset.Right
		local geom = flipperGeometryFromAsset(origin, side, sideAsset.Flipper.Root.Position, config)
		local envelope = FlipperGeometry.GetSweptEnvelope(geom, rootRadius, upAngleDegrees)

		local posts = sideAsset.Slingshot.Posts
		if posts ~= nil then
			local postRadius = config.Slingshot.PostRadius or 0.25
			for _, post in ipairs(posts) do
				if FlipperGeometry.SweepIntersectsPoint(envelope, post.Position, postRadius) then
					table.insert(errors, string.format("%s flipper's swept envelope intersects a slingshot post", side))
					break
				end
			end
		end

		for _, segment in ipairs(sideAsset.Lanes.DividerSegments) do
			local segmentRadius = segment.Size.Z / 2
			if FlipperGeometry.SweepIntersectsPoint(envelope, segment.Position, segmentRadius) then
				table.insert(errors, string.format("%s flipper's swept envelope intersects a lane guide segment", side))
				break
			end
		end
	end

	return { Ok = #errors == 0, Errors = errors }
end

return LowerPlayfieldValidator
