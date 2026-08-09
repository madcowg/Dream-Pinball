--!strict

-- Slingshot (spec section 9): a triangular wedge footprint with a hidden
-- (invisible but real) collision boundary, two decorative posts, a visible
-- rubber band, and a Trigger region for activation. The kick direction is
-- baked into a FaceNormalAttachment at generation time rather than derived
-- from the wedge mesh's actual face equation (a deliberate simplification --
-- see the module-level comment on FaceNormalLocal below) -- but because it
-- lives on an Attachment parented into the model, it still rotates correctly
-- with the model instead of being a hardcoded world direction.

local PrimitiveFactory = require(script.Parent.Parent.Geometry.PrimitiveFactory)
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
	-- a different feel. Not derived from the wedge geometry itself.
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
}

local DEFAULT_WIDTH_STUDS = 3
local DEFAULT_DEPTH_STUDS = 2
local DEFAULT_HEIGHT_STUDS = 2
local DEFAULT_POST_RADIUS_STUDS = 0.25
local DEFAULT_POST_HEIGHT_STUDS = 1.5

local function validateConfig(config: SlingshotConfig)
	local widthOk, widthErr = GeometryValidator.ValidatePositive(config.Width or DEFAULT_WIDTH_STUDS, "Width")
	local depthOk, depthErr = GeometryValidator.ValidatePositive(config.Depth or DEFAULT_DEPTH_STUDS, "Depth")

	GeometryValidator.AssertAll({
		{ ok = widthOk, err = widthErr },
		{ ok = depthOk, err = depthErr },
	}, "SlingshotGenerator.Generate")
end

export type SlingshotAsset = Types.GeneratedAsset & {
	HiddenCollider: BasePart,
	TriggerRegion: BasePart,
	RubberBand: BasePart,
	FaceNormalAttachment: Attachment,
	Lights: { PointLight },
}

function SlingshotGenerator.Generate(options: Types.GenerateOptions<SlingshotConfig>): SlingshotAsset
	local config = options.Config
	validateConfig(config)

	local name = options.Name or "Slingshot"
	local width = config.Width or DEFAULT_WIDTH_STUDS
	local depth = config.Depth or DEFAULT_DEPTH_STUDS
	local height = config.Height or DEFAULT_HEIGHT_STUDS
	local mirrorSign = (config.MirrorX and -1) or 1
	local postRadius = config.PostRadius or DEFAULT_POST_RADIUS_STUDS
	local postHeight = config.PostHeight or DEFAULT_POST_HEIGHT_STUDS

	local hierarchy = PrimitiveFactory.BuildStandardHierarchy({
		Name = name,
		Origin = options.Origin,
		AssetType = "Slingshot",
		BallDiameter = Scale.BALL_DIAMETER_STUDS,
		RootSize = Vector3.new(0.2, 0.2, 0.2),
	})

	local origin = options.Origin
	local right = origin.RightVector
	local up = origin.UpVector
	local look = origin.LookVector

	-- Right-angle corner at Origin; the wedge extends `depth` forward and
	-- `width` sideways (toward mirrorSign * Right), rising `height` tall.
	local wedgeCenter = origin.Position + (look * (depth / 2)) + (right * mirrorSign * (width / 2)) + (up * (height / 2))
	local wedge = Instance.new("WedgePart")
	wedge.Name = "HiddenCollider"
	wedge.Size = Vector3.new(width, height, depth)
	-- Invisible hitbox (Transparency = 1) -- 3-arg fromMatrix derives a proper
	-- third axis automatically, which is all that matters here since nothing
	-- ever reads which exact way the wedge's slanted face points.
	wedge.CFrame = CFrame.fromMatrix(wedgeCenter, right * mirrorSign, up)
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
	local faceCorner1 = origin.Position + (right * mirrorSign * width)
	local faceCorner2 = origin.Position + (look * depth)
	for index, corner in ipairs({ faceCorner1, faceCorner2 }) do
		PrimitiveFactory.CreatePart({
			Name = string.format("Post_%d", index),
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(postHeight, postRadius * 2, postRadius * 2),
			CFrame = CFrame.fromMatrix(corner + (up * (postHeight / 2)), up, right),
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
		CFrame = CFrame.fromMatrix(wedgeCenter, right * mirrorSign, up),
		Role = "Trigger",
		Parent = hierarchy.Folders.Triggers,
		CollisionGroup = config.CollisionGroup,
	})

	local faceNormalLocal = config.FaceNormalLocal or ((right * mirrorSign * 0.7) + (look * 0.7))
	local faceNormalWorld = ((right * mirrorSign * faceNormalLocal.X) + (up * faceNormalLocal.Y) + (look * faceNormalLocal.Z)).Unit
	local faceNormalAttachment = Instance.new("Attachment")
	faceNormalAttachment.Name = "FaceNormalAttachment"
	faceNormalAttachment.CFrame = CFrame.lookAt(wedgeCenter, wedgeCenter + faceNormalWorld, up)
	faceNormalAttachment.Parent = hierarchy.Root

	local lights: { PointLight } = {}
	if config.IncludeLights then
		for index, corner in ipairs({ faceCorner1, faceCorner2 }) do
			local light = Instance.new("PointLight")
			light.Name = string.format("SlingshotLight_%d", index)
			light.Color = config.LightColor or Color3.fromRGB(255, 255, 255)
			light.Brightness = 1.5
			light.Range = 6
			light.Enabled = false

			local holder = Instance.new("Part")
			holder.Name = string.format("LightHolder_%d", index)
			holder.Size = Vector3.new(0.1, 0.1, 0.1)
			holder.CFrame = CFrame.new(corner + (up * postHeight))
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
		HiddenCollider = wedge,
		TriggerRegion = triggerRegion,
		RubberBand = rubberBand,
		FaceNormalAttachment = faceNormalAttachment,
		Lights = lights,
	}
end

return SlingshotGenerator
