--!strict

-- Shared Instance-creation helpers: the standard generated-model hierarchy
-- (spec section 6), per-role collision/query flags, and idempotent
-- generate-and-replace (spec section 12). Every Generator module should build
-- its Model through PrimaryFactory.BuildStandardHierarchy rather than
-- constructing Model/Folder/Root by hand, so the contract stays identical
-- across all twelve asset families.

local PhysicsService = game:GetService("PhysicsService")

local Constants = require(script.Parent.Parent.Constants)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local PrimitiveFactory = {}

export type PartRole = "Visual" | "Collider" | "Trigger" | "Mechanism"

export type PartSpec = {
	Name: string,
	Shape: Enum.PartType?,
	Size: Vector3,
	CFrame: CFrame,
	Role: PartRole,
	Material: Enum.Material?,
	Color: BrickColor?,
	Parent: Instance?,
	CollisionGroup: string?,
	CanQuery: boolean?,
}

export type StandardHierarchy = {
	Model: Model,
	Root: BasePart,
	Folders: { [string]: Folder },
}

export type BuildHierarchyOptions = {
	Name: string,
	Origin: CFrame,
	AssetType: string,
	PresetName: string?,
	BallDiameter: number,
	GeneratedBy: string?,
	RootSize: Vector3?,
}

local function validatePartSpecSize(spec: PartSpec)
	local xOk, xErr = GeometryValidator.ValidatePositive(spec.Size.X, spec.Name .. ".Size.X")
	local yOk, yErr = GeometryValidator.ValidatePositive(spec.Size.Y, spec.Name .. ".Size.Y")
	local zOk, zErr = GeometryValidator.ValidatePositive(spec.Size.Z, spec.Name .. ".Size.Z")

	GeometryValidator.AssertAll({
		{ ok = xOk, err = xErr },
		{ ok = yOk, err = yErr },
		{ ok = zOk, err = zErr },
	}, "PrimitiveFactory.CreatePart(" .. spec.Name .. ")")
end

-- Applies the CanCollide/CanTouch/CanQuery flags required for each role
-- (spec section 6): visuals never collide, triggers are sensors only,
-- colliders/mechanisms physically interact with the ball.
local function applyRoleFlags(part: BasePart, role: PartRole, canQuery: boolean?)
	if role == "Visual" then
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = if canQuery ~= nil then canQuery else false
	elseif role == "Trigger" then
		part.CanCollide = false
		part.CanTouch = true
		part.CanQuery = if canQuery ~= nil then canQuery else false
	else
		-- Collider / Mechanism: real ball-contact geometry.
		part.CanCollide = true
		part.CanTouch = true
		part.CanQuery = if canQuery ~= nil then canQuery else true
	end
end

-- Creates one BasePart per PartSpec. Static roles (Visual/Collider/Trigger) are
-- anchored; Mechanism parts are left unanchored by default since spinners,
-- bumpers, and hideaway targets need to move -- callers building a static
-- Mechanism part (e.g. a fixed pivot bracket) should set Anchored = true on the
-- returned part themselves.
function PrimitiveFactory.CreatePart(spec: PartSpec): BasePart
	validatePartSpecSize(spec)

	local part = Instance.new("Part")
	part.Name = spec.Name
	part.Shape = spec.Shape or Enum.PartType.Block
	part.Size = spec.Size
	part.CFrame = spec.CFrame
	part.Material = spec.Material or Constants.DEFAULT_METAL_MATERIAL
	part.BrickColor = spec.Color or Constants.DEFAULT_METAL_COLOR
	part.Anchored = spec.Role ~= "Mechanism"

	applyRoleFlags(part, spec.Role, spec.CanQuery)

	if spec.CollisionGroup ~= nil then
		-- Registration is idempotent: pcall tolerates "already registered" (see
		-- CabinetBuilder.ensureCollisionGroups for the same pattern).
		pcall(function()
			PhysicsService:RegisterCollisionGroup(spec.CollisionGroup :: string)
		end)
		part.CollisionGroup = spec.CollisionGroup :: string
	end

	if spec.Parent ~= nil then
		part.Parent = spec.Parent
	end

	return part
end

-- Builds the standard Model/Root/Visuals/Colliders/Triggers/Mechanism/Lights/
-- Attachments hierarchy and stamps the required asset attributes. Root is an
-- invisible anchored reference part and the Model's PrimaryPart; every other
-- part is positioned relative to `options.Origin` by generators, not to world
-- origin directly.
function PrimitiveFactory.BuildStandardHierarchy(options: BuildHierarchyOptions): StandardHierarchy
	local model = Instance.new("Model")
	model.Name = options.Name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = options.RootSize or Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = options.Origin
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Transparency = 1
	root.Parent = model

	local folders: { [string]: Folder } = {}
	for _, folderName in ipairs(Constants.STANDARD_HIERARCHY_FOLDERS) do
		local folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = model
		folders[folderName] = folder
	end

	model.PrimaryPart = root

	local attributes = Constants.ASSET_ATTRIBUTES
	model:SetAttribute(attributes.PinballAsset, true)
	model:SetAttribute(attributes.AssetType, options.AssetType)
	model:SetAttribute(attributes.AssetVersion, Constants.LIBRARY_VERSION)
	model:SetAttribute(attributes.PresetName, options.PresetName)
	model:SetAttribute(attributes.BallDiameter, options.BallDiameter)
	model:SetAttribute(attributes.GeneratedBy, options.GeneratedBy or Constants.GENERATED_BY)
	model:SetAttribute(attributes.GenerationId, options.AssetType .. "_" .. options.Name)

	return { Model = model, Root = root, Folders = folders }
end

-- Idempotent generation (spec section 12): builds `newModel` fully before
-- looking for a prior generated model with the same GenerationId under
-- `container`, then swaps it in and destroys the old one. Never touches
-- anything else under `container`.
function PrimitiveFactory.ReplaceOrParent(container: Instance, newModel: Model, replaceExisting: boolean?)
	local generationId = newModel:GetAttribute(Constants.ASSET_ATTRIBUTES.GenerationId)

	if replaceExisting ~= false and generationId ~= nil then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute(Constants.ASSET_ATTRIBUTES.GenerationId) == generationId then
				child:Destroy()
			end
		end
	end

	newModel.Parent = container
end

-- Finds (or creates) the named container under Workspace that generated assets
-- are parented into by default.
function PrimitiveFactory.GetDefaultContainer(workspaceInstance: Instance): Folder
	local existing = workspaceInstance:FindFirstChild(Constants.DEFAULT_CONTAINER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end

	local container = Instance.new("Folder")
	container.Name = Constants.DEFAULT_CONTAINER_NAME
	container.Parent = workspaceInstance
	return container
end

return PrimitiveFactory
