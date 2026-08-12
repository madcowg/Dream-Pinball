--!strict

-- Slingshot (spec section 9): a triangular wedge footprint with a hidden
-- (invisible but real) collision boundary, two decorative posts, a visible
-- rubber band, and a Trigger region for activation. The kick direction is
-- baked into a FaceNormalAttachment at generation time rather than derived
-- from the wedge mesh's actual face equation (a deliberate simplification --
-- see the module-level comment on FaceNormalLocal below) -- but because it
-- lives on an Attachment parented into the model, it still rotates correctly
-- with the model instead of being a hardcoded world direction.
--
-- Optional extension (Config.PostPositions, spec section 11): a literal
-- three-post triangle with stretched rubber between posts (never a circular
-- ring) and a face normal DERIVED from the active segment's own endpoints
-- instead of the hardcoded blend above. This mode replaces the two-corner
-- wedge posts/band; the plain Width/Depth/Height wedge path above stays the
-- default and is unchanged when PostPositions is omitted.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local Scale = require(script.Parent.Parent.Scale)
local Constants = require(script.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Types)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local SlingshotGenerator = {}

export type SlingshotConfig = {
	Width: number?,
	Depth: number?,
	Height: number?,
	MirrorX: boolean?,
	-- Local-space (relative to Origin's basis) outward kick direction. Defaults
	-- to a blend of sideways-away-from-center and forward, the typical real
	-- slingshot kick -- override per preset if the wedge proportions call for
	-- a different feel. Not derived from the wedge geometry itself. Ignored
	-- when PostPositions is set (the active segment's own normal is used).
	FaceNormalLocal: Vector3?,
	PostRadius: number?,
	PostHeight: number?,
	Material: Enum.Material?,
	Color: BrickColor?,
	CollisionGroup: string?,
	IncludeLights: boolean?,
	LightColor: Color3?,
	-- Stamped as a "PointValue" attribute if set -- see BumperGenerator's
	-- Config for why this isn't defaulted here.
	PointValue: number?,

	-- Explicit 3-post triangle: local (X, Z) offsets from Origin (X along
	-- Origin.RightVector, Y-of-the-Vector2 along Origin.LookVector), the same
	-- convention LaneConfig paths use. When set, this REPLACES the two-corner
	-- wedge posts/rubber-band with the literal post/rubber/plastic-cover
	-- layout spec section 11 describes. MirrorX is ignored in this mode --
	-- mirror the Vector2 list itself via MirrorTransform.MirrorPath for the
	-- other side, since a caller-supplied triangle isn't always symmetric.
	PostPositions: { Vector2 }?,
	-- Which edge (PostPositions[i] -> PostPositions[i + 1], wrapping,
	-- 1-indexed) is the ball-facing active rubber. Defaults to 1.
	ActiveSegmentIndex: number?,
	-- Williams 2.5-inch sling rubber's real cross-section (spec table:
	-- 0.1875in) is the default -- ReferencedPart, not a GameplayDefault.
	RubberCrossSectionStuds: number?,
	TriggerDepth: number?,
	PlasticColor: Color3?,
	PlasticTransparency: number?,
}

local DEFAULT_WIDTH_STUDS = 3
local DEFAULT_DEPTH_STUDS = 2
local DEFAULT_HEIGHT_STUDS = 2
local DEFAULT_POST_RADIUS_STUDS = 0.25
local DEFAULT_POST_HEIGHT_STUDS = 1.5
local DEFAULT_RUBBER_CROSS_SECTION_STUDS = 0.2647
local DEFAULT_TRIGGER_DEPTH_STUDS = 0.4
local DEFAULT_PLASTIC_TRANSPARENCY = 0.15
local MIN_POST_SPACING_STUDS = 1

local function validateConfig(config: SlingshotConfig)
	local widthOk, widthErr = GeometryValidator.ValidatePositive(config.Width or DEFAULT_WIDTH_STUDS, "Width")
	local depthOk, depthErr = GeometryValidator.ValidatePositive(config.Depth or DEFAULT_DEPTH_STUDS, "Depth")

	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = depthOk, err = depthErr },
	}, "SlingshotGenerator.Generate")

	if config.PostPositions ~= nil then
		local posts = config.PostPositions
		if #posts ~= 3 then
			error(string.format("SlingshotGenerator.Generate: Config.PostPositions must have exactly 3 entries, got %d", #posts), 0)
		end

		local a, b, c = posts[1], posts[2], posts[3]
		local ab = b - a
		local ac = c - a
		local cross = ab.X * ac.Y - ab.Y * ac.X
		if math.abs(cross) < 1e-4 then
			error("SlingshotGenerator.Generate: Config.PostPositions are collinear (degenerate triangle)", 0)
		end

		for _, pair in ipairs({ { a, b }, { b, c }, { c, a } }) do
			local spacing = (pair[2] - pair[1]).Magnitude
			if spacing < MIN_POST_SPACING_STUDS then
				error(
					string.format(
						"SlingshotGenerator.Generate: PostPositions are too close together (%.4f studs, minimum %.4f)",
						spacing,
						MIN_POST_SPACING_STUDS
					),
					0
				)
			end
		end

		local activeIndex = config.ActiveSegmentIndex or 1
		if activeIndex ~= 1 and activeIndex ~= 2 and activeIndex ~= 3 then
			error("SlingshotGenerator.Generate: Config.ActiveSegmentIndex must be 1, 2, or 3", 0)
		end
	end
end

export type SlingshotAsset = Types.GeneratedAsset & {
	HiddenCollider: BasePart,
	TriggerRegion: BasePart,
	RubberBand: BasePart,
	FaceNormalAttachment: Attachment,
	Lights: { PointLight },
	-- Only populated in the 3-post (Config.PostPositions) mode.
	Posts: { BasePart }?,
	RubberSegments: { BasePart }?,
	PlasticCover: BasePart?,
}

-- Default two-corner wedge path (unchanged behavior from before the
-- 3-post extension): a WedgePart hidden collider with two posts and one
-- rubber band spanning the exposed face.
local function generateWedgeSlingshot(
	options: Types.GenerateOptions<SlingshotConfig>,
	hierarchy: PrimitiveFactory.StandardHierarchy
): (BasePart, BasePart, BasePart, { Vector3 }, Attachment)
	local config = options.Config
	local width = config.Width or DEFAULT_WIDTH_STUDS
	local depth = config.Depth or DEFAULT_DEPTH_STUDS
	local height = config.Height or DEFAULT_HEIGHT_STUDS
	local postRadius = config.PostRadius or DEFAULT_POST_RADIUS_STUDS
	local postHeight = config.PostHeight or DEFAULT_POST_HEIGHT_STUDS

	local origin = options.Origin
	local up = origin.UpVector
	local look = origin.LookVector
	local baseRight = origin.RightVector
	-- `right` IS baseRight when MirrorX is unset -- MirrorX reflects it across
	-- origin's own vertical plane via MirrorTransform instead of a hand-rolled
	-- `right * mirrorSign` multiplication scattered across every term below
	-- (this is the same linear reflection, verified to produce identical
	-- results -- see MirrorTransform.luau's header). Post orientation below
	-- deliberately keeps using baseRight, unmirrored, matching this module's
	-- original behavior (only the wedge/corners/trigger/face-normal terms were
	-- ever mirrored).
	local right = if config.MirrorX then MirrorTransform.MirrorDirection(origin, baseRight) else baseRight

	-- Right-angle corner at Origin; the wedge extends `depth` forward and
	-- `width` sideways (toward `right`), rising `height` tall.
	local wedgeCenter = origin.Position + (look * (depth / 2)) + (right * (width / 2)) + (up * (height / 2))
	local wedge = Instance.new("WedgePart")
	wedge.Name = "HiddenCollider"
	wedge.Size = Vector3.new(width, height, depth)
	-- Invisible hitbox (Transparency = 1) -- 3-arg fromMatrix derives a proper
	-- third axis automatically, which is all that matters here since nothing
	-- ever reads which exact way the wedge's slanted face points.
	wedge.CFrame = CFrame.fromMatrix(wedgeCenter, right, up)
	wedge.Anchored = true
	wedge.CanCollide = true
	wedge.CanTouch = true
	wedge.CanQuery = true
	wedge.Transparency = 1
	wedge.Material = config.Material or Enum.Material.Metal
	if config.CollisionGroup ~= nil then
		wedge.CollisionGroup = config.CollisionGroup
	end
	wedge.Parent = hierarchy.Folders.Colliders

	-- Two posts at the exposed face's corners.
	local faceCorner1 = origin.Position + (right * width)
	local faceCorner2 = origin.Position + (look * depth)
	local lightAnchors: { Vector3 } = { faceCorner1, faceCorner2 }
	for index, corner in ipairs(lightAnchors) do
		PrimitiveFactory.CreatePart({
			Name = string.format("Post_%d", index),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(postHeight, postRadius * 2, postRadius * 2),
			CFrame = CFrame.fromMatrix(corner + (up * (postHeight / 2)), up, baseRight),
			Role = "Visual",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Visuals,
		})
	end

	-- Visible rubber band spanning the exposed face, roughly at ball height.
	local bandCenter = (faceCorner1 + faceCorner2) / 2 + (up * (postHeight * 0.5))
	local bandLength = (faceCorner2 - faceCorner1).Magnitude
	local rubberBand = PrimitiveFactory.CreatePart({
		Name = "RubberBand",
		Size = Vector3.new(0.15, 0.4, bandLength),
		CFrame = CFrame.lookAt(bandCenter, faceCorner2, up),
		Role = "Visual",
		Material = Enum.Material.SmoothPlastic,
		Color = config.Color or BrickColor.new("Black"),
		Parent = hierarchy.Folders.Visuals,
	})

	local triggerRegion = PrimitiveFactory.CreatePart({
		Name = "TriggerRegion",
		Size = Vector3.new(width + 0.6, height, depth + 0.6),
		CFrame = CFrame.fromMatrix(wedgeCenter, right, up),
		Role = "Trigger",
		Parent = hierarchy.Folders.Triggers,
		CollisionGroup = config.CollisionGroup,
	})

	local faceNormalLocal = config.FaceNormalLocal or ((right * 0.7) + (look * 0.7))
	local faceNormalWorld = ((right * faceNormalLocal.X) + (up * faceNormalLocal.Y) + (look * faceNormalLocal.Z)).Unit
	local faceNormalAttachment = Instance.new("Attachment")
	faceNormalAttachment.Name = "FaceNormalAttachment"
	faceNormalAttachment.CFrame = CFrame.lookAt(wedgeCenter, wedgeCenter + faceNormalWorld, up)
	faceNormalAttachment.Parent = hierarchy.Root

	return wedge, triggerRegion, rubberBand, lightAnchors, faceNormalAttachment
end

-- Explicit 3-post mode: real posts, stretched rubber per edge (never a
-- circular ring), a flat plastic cover approximating the triangle's
-- footprint, and a face normal derived from the active segment's own
-- endpoints -- never a hardcoded world direction.
local function generateTriangulatedSlingshot(
	options: Types.GenerateOptions<SlingshotConfig>,
	hierarchy: PrimitiveFactory.StandardHierarchy
): (BasePart, BasePart, BasePart, { BasePart }, { Vector3 }, { BasePart }, BasePart, Attachment)
	local config = options.Config
	local origin = options.Origin
	local up = origin.UpVector
	local look = origin.LookVector
	local right = origin.RightVector
	local height = config.Height or DEFAULT_HEIGHT_STUDS
	local postRadius = config.PostRadius or DEFAULT_POST_RADIUS_STUDS
	local postHeight = config.PostHeight or DEFAULT_POST_HEIGHT_STUDS
	local rubberCrossSection = config.RubberCrossSectionStuds or DEFAULT_RUBBER_CROSS_SECTION_STUDS
	local triggerDepth = config.TriggerDepth or DEFAULT_TRIGGER_DEPTH_STUDS
	local activeIndex = config.ActiveSegmentIndex or 1

	local localPosts = config.PostPositions :: { Vector2 }
	local worldPosts: { Vector3 } = table.create(3)
	for index, point in ipairs(localPosts) do
		worldPosts[index] = origin.Position + (right * point.X) + (look * point.Y)
	end

	local centroid = (worldPosts[1] + worldPosts[2] + worldPosts[3]) / 3

	local posts: { BasePart } = table.create(3)
	for index, worldPost in ipairs(worldPosts) do
		posts[index] = PrimitiveFactory.CreatePart({
			Name = string.format("Post_%d", index),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(postHeight, postRadius * 2, postRadius * 2),
			CFrame = CFrame.fromMatrix(worldPost + (up * (postHeight / 2)), up, right),
			Role = "Visual",
			Material = config.Material,
			Color = config.Color,
			Parent = hierarchy.Folders.Visuals,
		})
	end

	-- Stretched rubber between consecutive posts (wrapping), at ball height --
	-- never a circular ring resting flat on the playfield (spec section 11).
	local rubberBandHeight = up * (postHeight * 0.5)
	local rubberSegments: { BasePart } = table.create(3)
	local activeRubber: BasePart? = nil
	local activeSegmentAWorld: Vector3? = nil
	local activeSegmentBWorld: Vector3? = nil

	for segmentIndex = 1, 3 do
		local nextIndex = if segmentIndex == 3 then 1 else segmentIndex + 1
		local a = worldPosts[segmentIndex]
		local b = worldPosts[nextIndex]
		local segmentCenter = (a + b) / 2 + rubberBandHeight
		local segmentLength = (b - a).Magnitude

		local segment = PrimitiveFactory.CreatePart({
			Name = string.format("RubberSegment_%d", segmentIndex),
			Size = Vector3.new(rubberCrossSection, rubberCrossSection, segmentLength),
			CFrame = CFrame.lookAt(segmentCenter, b + rubberBandHeight, up),
			Role = "Visual",
			Material = Enum.Material.SmoothPlastic,
			Color = config.Color or BrickColor.new("Black"),
			Parent = hierarchy.Folders.Visuals,
		})
		rubberSegments[segmentIndex] = segment

		if segmentIndex == activeIndex then
			activeRubber = segment
			activeSegmentAWorld = a
			activeSegmentBWorld = b
		end
	end

	local segmentA = activeSegmentAWorld :: Vector3
	local segmentB = activeSegmentBWorld :: Vector3
	local segmentMid = (segmentA + segmentB) / 2
	local segmentDirection = (segmentB - segmentA).Unit
	local outwardCandidate = up:Cross(segmentDirection).Unit
	-- Choose whichever perpendicular points AWAY from the triangle's centroid
	-- -- the centroid sits inside the slingshot's own body, so "away from it"
	-- is the playable side, per spec section 11's "point into the playable
	-- area" requirement. Never a hardcoded world-space direction.
	local towardCentroid = (centroid - segmentMid)
	local faceNormalWorld = if outwardCandidate:Dot(towardCentroid) > 0 then -outwardCandidate else outwardCandidate

	local faceNormalAttachment = Instance.new("Attachment")
	faceNormalAttachment.Name = "FaceNormalAttachment"
	faceNormalAttachment.CFrame = CFrame.lookAt(segmentMid, segmentMid + faceNormalWorld, up)
	faceNormalAttachment.Parent = hierarchy.Root

	-- Hidden collision geometry: one slim box per rubber segment (matching the
	-- visible band, so the ball bounces off the same geometry it sees) plus a
	-- flat interior-fill box spanning the triangle's bounding footprint, so a
	-- ball can't tunnel into the slingshot's interior through a non-active
	-- edge. The fill box overshoots the exact triangle slightly (a bounding
	-- box, not a true triangular prism -- Roblox has no arbitrary-triangle
	-- part) which is fine since nothing renders there.
	local colliders: { BasePart } = table.create(3)
	for segmentIndex = 1, 3 do
		local nextIndex = if segmentIndex == 3 then 1 else segmentIndex + 1
		local a = worldPosts[segmentIndex]
		local b = worldPosts[nextIndex]
		local segmentCenter = (a + b) / 2 + rubberBandHeight
		local segmentLength = (b - a).Magnitude

		local collider = PrimitiveFactory.CreatePart({
			Name = string.format("RubberCollider_%d", segmentIndex),
			Size = Vector3.new(rubberCrossSection + 0.2, rubberCrossSection + 0.2, segmentLength),
			CFrame = CFrame.lookAt(segmentCenter, b + rubberBandHeight, up),
			Role = "Collider",
			Parent = hierarchy.Folders.Colliders,
			CollisionGroup = config.CollisionGroup,
		})
		collider.Transparency = 1
		colliders[segmentIndex] = collider
	end

	local hiddenCollider = colliders[activeIndex]

	local triggerCenter = segmentMid - (faceNormalWorld * (triggerDepth / 2)) + rubberBandHeight
	local triggerRegion = PrimitiveFactory.CreatePart({
		Name = "TriggerRegion",
		Size = Vector3.new((segmentB - segmentA).Magnitude, height, triggerDepth),
		CFrame = CFrame.lookAt(triggerCenter, triggerCenter + faceNormalWorld, up),
		Role = "Trigger",
		Parent = hierarchy.Folders.Triggers,
		CollisionGroup = config.CollisionGroup,
	})

	-- Flat plastic cover approximating the triangle's own footprint --
	-- Roblox has no native triangular part, so (matching this module's
	-- existing wedge-based approximation elsewhere) a flat WedgePart sized to
	-- the posts' bounding spread stands in for the exact triangle silhouette.
	local minRight, maxRight = math.huge, -math.huge
	local minLook, maxLook = math.huge, -math.huge
	for _, point in ipairs(localPosts) do
		minRight = math.min(minRight, point.X)
		maxRight = math.max(maxRight, point.X)
		minLook = math.min(minLook, point.Y)
		maxLook = math.max(maxLook, point.Y)
	end
	local coverWidth = math.max(maxRight - minRight, 0.5)
	local coverDepth = math.max(maxLook - minLook, 0.5)
	local coverCenter = origin.Position + (right * ((minRight + maxRight) / 2)) + (look * ((minLook + maxLook) / 2)) + (up * (postHeight * 0.85))
	local plasticCover = Instance.new("WedgePart")
	plasticCover.Name = "PlasticCover"
	plasticCover.Size = Vector3.new(coverWidth, 0.15, coverDepth)
	plasticCover.CFrame = CFrame.fromMatrix(coverCenter, right, up)
	plasticCover.Anchored = true
	plasticCover.CanCollide = false
	plasticCover.CanTouch = false
	plasticCover.CanQuery = false
	plasticCover.Material = Enum.Material.SmoothPlastic
	plasticCover.Color = config.PlasticColor or Color3.fromRGB(240, 240, 230)
	plasticCover.Transparency = config.PlasticTransparency or DEFAULT_PLASTIC_TRANSPARENCY
	plasticCover.Parent = hierarchy.Folders.Visuals

	local interiorFill = PrimitiveFactory.CreatePart({
		Name = "InteriorFill",
		Size = Vector3.new(coverWidth, height, coverDepth),
		CFrame = CFrame.fromMatrix(coverCenter - (up * (postHeight * 0.85 - height / 2)), right, up),
		Role = "Collider",
		Parent = hierarchy.Folders.Colliders,
		CollisionGroup = config.CollisionGroup,
	})
	interiorFill.Transparency = 1

	return hiddenCollider, triggerRegion, (activeRubber :: BasePart), posts, worldPosts, rubberSegments, plasticCover, faceNormalAttachment
end

function SlingshotGenerator.Generate(options: Types.GenerateOptions<SlingshotConfig>): SlingshotAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Slingshot"

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Slingshot",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local usingTriangulated = config.PostPositions ~= nil

	local hiddenCollider: BasePart
	local triggerRegion: BasePart
	local rubberBand: BasePart
	local posts: { BasePart }? = nil
	local lightAnchors: { Vector3 }
	local rubberSegments: { BasePart }? = nil
	local plasticCover: BasePart? = nil
	local faceNormalAttachment: Attachment

	if usingTriangulated then
		local triHiddenCollider, triTriggerRegion, triRubberBand, triPosts, triWorldPosts, triRubberSegments, triPlasticCover, triFaceNormalAttachment =
			generateTriangulatedSlingshot(options, hierarchy)
		hiddenCollider = triHiddenCollider
		triggerRegion = triTriggerRegion
		rubberBand = triRubberBand
		posts = triPosts
		lightAnchors = triWorldPosts
		rubberSegments = triRubberSegments
		plasticCover = triPlasticCover
		faceNormalAttachment = triFaceNormalAttachment
	else
		local wedgeHiddenCollider, wedgeTriggerRegion, wedgeRubberBand, wedgeLightAnchors, wedgeFaceNormalAttachment = generateWedgeSlingshot(options, hierarchy)
		hiddenCollider = wedgeHiddenCollider
		triggerRegion = wedgeTriggerRegion
		rubberBand = wedgeRubberBand
		lightAnchors = wedgeLightAnchors
		faceNormalAttachment = wedgeFaceNormalAttachment
	end

	local up = options.Origin.UpVector
	local postHeight = config.PostHeight or DEFAULT_POST_HEIGHT_STUDS
	local lights: { PointLight } = {}
	if config.IncludeLights then
		for index, anchor in ipairs(lightAnchors) do
			local light = Instance.new("PointLight")
			light.Name = string.format("SlingshotLight_%d", index)
			light.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
			light.Brightness = 1.5
			light.Range = 6
			light.Enabled = false

			local holder = Instance.new("Part")
			holder.Name = string.format("LightHolder_%d", index)
			holder.Size = Vector3.new(0.1, 0.1, 0.1)
			holder.CFrame = CFrame.new(anchor + (up * postHeight))
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanTouch = false
			holder.CanQuery = false
			holder.Transparency = 1
			holder.Parent = hierarchy.Folders.Lights

			light.Parent = holder
			table.insert(lights, light)
		end
	end

	if config.PointValue ~= nil then
		hierarchy.Model:SetAttribute(Constants.POINT_VALUE_ATTRIBUTE, config.PointValue)
	end

	local parent = options.Parent or PrimitiveFactory.GetDefaultContainer(game:GetService("Workspace"))
	PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model, options.ReplaceExisting)

	return {
		Model = hierarchy.Model,
		Root = hierarchy.Root,
		Attachments = { FaceNormal = faceNormalAttachment },
		HiddenCollider = hiddenCollider,
		TriggerRegion = triggerRegion,
		RubberBand = rubberBand,
		FaceNormalAttachment = faceNormalAttachment,
		Lights = lights,
		Posts = posts,
		RubberSegments = rubberSegments,
		PlasticCover = plasticCover,
	}
end

return SlingshotGenerator
