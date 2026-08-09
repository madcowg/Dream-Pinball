--!strict

-- Straight, planar-curved, inclined, and curved+inclined ramps (spec section
-- 8). A ramp is a flat rolling surface swept along a path exactly like
-- RailGenerator's rails, except each path segment gets one flat box instead of
-- a circular profile. Rise and BankAngle are baked into the path's starting
-- orientation (constant across the main section); EntryTransitionLength /
-- ExitTransitionLength ease the pitch from level to the ramp's incline at each
-- end so the ball never meets a sudden angle change ("vertical lip").
--
-- "Ramp connected to a U-shaped rail or tunnel" (spec section 8) is achieved
-- by chaining generators through their shared Entry/Exit Attachment contract
-- (build the ramp, read GeneratedAsset.Attachments.Exit.WorldCFrame, generate
-- a rail/tunnel with that as its Origin) rather than a dedicated combined
-- generator -- every PinballKit generator returns/accepts CFrames through the
-- same contract for exactly this kind of composition.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local PathBuilder = require(script.Parent.Parent.Geometry.PathBuilder)
local PathFrames = require(script.Parent.Parent.Geometry.PathFrames)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local RampGenerator = {}

export type SideRailType = "None" | "Wall"

export type RampCurve = {
	Radius: number,
	AngleDegrees: number,
	Direction: "Left" | "Right",
}

export type RampConfig = {
	Width: number,
	Length: number,
	Rise: number?,
	Thickness: number?,
	BankAngleDegrees: number?,
	Curve: RampCurve?,
	SurfaceMaterial: Enum.Material?,
	SurfaceColor: BrickColor?,
	SideRailType: SideRailType?,
	SideRailHeight: number?,
	EntryTransitionLength: number?,
	ExitTransitionLength: number?,
	Quality: Types.Quality?,
	CollisionGroup: string?,
}

local DEFAULT_THICKNESS_STUDS = 0.5
local DEFAULT_SIDE_RAIL_HEIGHT_STUDS = 1.5
local DEFAULT_SIDE_RAIL_THICKNESS_STUDS = 0.3
local TRANSITION_EASE_SEGMENTS = 6

local function validateConfig(config: RampConfig)
	local widthOk, widthErr = GeometryValidator.ValidatePositive(config.Width, "RampConfig.Width")
	local lengthOk, lengthErr = GeometryValidator.ValidatePositive(config.Length, "RampConfig.Length")
	local riseOk, riseErr = true, nil
	if config.Rise ~= nil then
		riseOk, riseErr = GeometryValidator.ValidateNonNegative(math.abs(config.Rise), "RampConfig.Rise")
	end

	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = lengthOk, err = lengthErr },
		{ ok = riseOk, err = riseErr },
	}, "RampGenerator.Generate")

	if config.Width < Scale.BALL_DIAMETER_STUDS + 0.2 then
		error(
			string.format(
				"RampGenerator.Generate: Width %.4f studs is too narrow for the %.4f-stud ball plus clearance",
				config.Width,
				Scale.BALL_DIAMETER_STUDS
			),
			0
		)
	end
end

-- Builds a short PathResult that eases pitch (rotation about the path's own
-- Right axis, applied absolutely from `startCFrame` at each sample rather than
-- accumulated step-to-step) linearly from 0 to `targetPitchRadians` over
-- `length` studs. This is a linear ease, not a true clothoid/circular blend --
-- adequate to avoid a sudden angle discontinuity for the short transition
-- lengths ramps use; revisit with a proper vertical arc (mirroring ArcMath's
-- yaw-plane derivation, but bending about Right instead of Up) if a future
-- preset needs a longer, more visually critical transition.
local function buildPitchTransitionPath(startCFrame: CFrame, length: number, targetPitchRadians: number): PathFrames.PathResult
	local segmentCount = math.max(1, math.min(TRANSITION_EASE_SEGMENTS, PathFrames.SegmentCountFromLength(length, 1)))
	local stepLength = length / segmentCount

	local samples: { PathFrames.PathSample } = table.create(segmentCount + 1)
	local position = startCFrame.Position

	table.insert(samples, {
		CFrame = startCFrame,
		Position = position,
		Tangent = startCFrame.LookVector,
		Right = startCFrame.RightVector,
		Up = startCFrame.UpVector,
		DistanceAlongPath = 0,
	})

	for index = 1, segmentCount do
		local t = index / segmentCount
		local pitch = targetPitchRadians * t
		local orientedCFrame = startCFrame * CFrame.Angles(pitch, 0, 0)
		local previousForward = samples[index].Tangent

		position = position + (previousForward * stepLength)

		local rotationOnly = orientedCFrame - orientedCFrame.Position
		table.insert(samples, {
			CFrame = CFrame.new(position) * rotationOnly,
			Position = position,
			Tangent = orientedCFrame.LookVector,
			Right = orientedCFrame.RightVector,
			Up = orientedCFrame.UpVector,
			DistanceAlongPath = stepLength * index,
		})
	end

	return {
		Samples = samples,
		Length = length,
		StartCFrame = startCFrame,
		EndCFrame = samples[#samples].CFrame,
	}
end

-- One flat rolling-surface panel plus optional side-rail walls per path
-- segment, overlapping longitudinally like every other PinballKit sweep.
local function buildSurfaceSegments(
	path: PathFrames.PathResult,
	width: number,
	thickness: number,
	sideRailType: SideRailType,
	sideRailHeight: number,
	parent: Folder,
	sideRailParent: Folder,
	material: Enum.Material?,
	color: BrickColor?,
	collisionGroup: string?,
	namePrefix: string
)
	local samples = path.Samples
	local overlap = Constants.DEFAULT_SEGMENT_OVERLAP_STUDS

	for segmentIndex = 1, #samples - 1 do
		local startSample = samples[segmentIndex]
		local endSample = samples[segmentIndex + 1]
		local segmentLength = (endSample.Position - startSample.Position).Magnitude
		local panelLength = segmentLength + overlap
		local midpointPosition = (startSample.Position + endSample.Position) / 2
		local up = startSample.Up
		local right = startSample.Right
		local tangent = startSample.Tangent

		local surfaceCenter = midpointPosition - (up * (thickness / 2))
		local surfaceCFrame = CFrame.fromMatrix(surfaceCenter, right, up, -tangent)

		PrimitiveFactory.CreatePart({
			Name = string.format("%s_%d", namePrefix, segmentIndex),
			Size = Vector3.new(width, thickness, panelLength),
			CFrame = surfaceCFrame,
			Role = "Collider",
			Material = material,
			Color = color,
			Parent = parent,
			CollisionGroup = collisionGroup,
		})

		if sideRailType == "Wall" then
			for _, sign in ipairs({ -1, 1 }) do
				local railCenter = midpointPosition
					+ (right * sign * ((width / 2) - (DEFAULT_SIDE_RAIL_THICKNESS_STUDS / 2)))
					+ (up * (sideRailHeight / 2))
				local railCFrame = CFrame.fromMatrix(railCenter, right, up, -tangent)

				PrimitiveFactory.CreatePart({
					Name = string.format("%sSideRail_%d_%d", namePrefix, segmentIndex, sign),
					Size = Vector3.new(DEFAULT_SIDE_RAIL_THICKNESS_STUDS, sideRailHeight, panelLength),
					CFrame = railCFrame,
					Role = "Collider",
					Material = material,
					Color = color,
					Parent = sideRailParent,
					CollisionGroup = collisionGroup,
				})
			end
		end
	end
end

local function createPlacementAttachment(attachmentsFolder: Folder, name: string, cframe: CFrame): Attachment
	local anchorPart = Instance.new("Part")
	anchorPart.Name = name
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame = cframe
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.Transparency = 1
	anchorPart.Parent = attachmentsFolder

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = anchorPart

	return attachment
end

function RampGenerator.Generate(options: Types.GenerateOptions<RampConfig>): Types.GeneratedAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Ramp"
	local thickness = config.Thickness or DEFAULT_THICKNESS_STUDS
	local sideRailType = config.SideRailType or "None"
	local sideRailHeight = config.SideRailHeight or DEFAULT_SIDE_RAIL_HEIGHT_STUDS
	local rise = config.Rise or 0
	local bankAngleDegrees = config.BankAngleDegrees or 0
	local entryTransitionLength = config.EntryTransitionLength or 0
	local exitTransitionLength = config.ExitTransitionLength or 0

	local inclineRadians = math.asin(math.clamp(rise / config.Length, -1, 1))
	local bankedOrigin = options.Origin * CFrame.Angles(0, 0, math.rad(bankAngleDegrees))

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Ramp",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local function drawSurface(path: PathFrames.PathResult, namePrefix: string)
		buildSurfaceSegments(
			path,
			config.Width,
			thickness,
			sideRailType,
			sideRailHeight,
			hierarchy.Folders.Colliders,
			hierarchy.Folders.Colliders,
			config.SurfaceMaterial,
			config.SurfaceColor,
			config.CollisionGroup,
			namePrefix
		)
	end

	local entryCFrame = bankedOrigin
	local mainStartCFrame = bankedOrigin

	if entryTransitionLength > 0 then
		local entryPath = buildPitchTransitionPath(bankedOrigin, entryTransitionLength, inclineRadians)
		drawSurface(entryPath, "EntryTransition")
		mainStartCFrame = entryPath.EndCFrame
		entryCFrame = entryPath.StartCFrame
	end

	-- Length always drives the incline calculation (rise / Length = slope),
	-- independent of the curve's own arc length (Radius * AngleDegrees) when
	-- Curve is set -- the two can differ deliberately (e.g. a gentle rise over
	-- a tightly-curved horizontal path).
	local pathSpec: PathBuilder.PathSpec = if config.Curve ~= nil
		then {
			PathType = "Curved" :: "Curved",
			Radius = config.Curve.Radius,
			AngleDegrees = config.Curve.AngleDegrees,
			Direction = config.Curve.Direction,
			Quality = config.Quality,
		}
		else {
			PathType = "Straight" :: "Straight",
			Length = config.Length,
			Quality = config.Quality,
		}

	local mainPath = PathBuilder.Build(mainStartCFrame, pathSpec)
	drawSurface(mainPath, "RampSurface")

	local exitCFrame = mainPath.EndCFrame

	if exitTransitionLength > 0 then
		local exitPath = buildPitchTransitionPath(mainPath.EndCFrame, exitTransitionLength, -inclineRadians)
		drawSurface(exitPath, "ExitTransition")
		exitCFrame = exitPath.EndCFrame
	end

	local entryAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "EntryAttachment", entryCFrame)
	local exitAttachment = createPlacementAttachment(hierarchy.Folders.Attachments, "ExitAttachment", exitCFrame)

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = {
			Entry = entryAttachment,
			Exit = exitAttachment,
		},
	}
end

return RampGenerator
