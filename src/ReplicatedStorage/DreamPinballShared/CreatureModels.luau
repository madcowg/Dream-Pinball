--!strict

--- Looks up a creature's visual assets by SPECIES (the stable key on
--- Ball.BallData.Species -- NOT the per-instance Id; every ball of the same
--- species shares one set of models). Two forms per creature, each an
--- Roblox Model:
---   PinballModel  -- used when that creature's ball is launched into a machine.
---   CreatureModel -- used when that creature is walking around a common
---                    area / previewed in inventory (post-prototype feature,
---                    but the asset organization is set up now).
---
--- Folder structure (ReplicatedStorage.DreamPinballShared.CreatureModelAssets --
--- named distinctly from this ModuleScript itself: Roblox does not allow a
--- Folder and a ModuleScript to share the same name under the same parent,
--- which is exactly the naming collision hit when this used to be called
--- "CreatureModels" like the script):
---   CreatureModelAssets
---     SeaGoblin
---       PinballModel   -- Urchinball
---       CreatureModel  -- Sea Goblin
---     <other species>
---       PinballModel
---       CreatureModel  -- may not exist yet; getCreatureModel returns nil, not an error
---
--- A ball with Species == nil (e.g. the Extra Ball item's plain steel ball)
--- has no entry here -- see SharedModels.luau instead.
---
--- Run once from Studio's Command Bar to create/rename a species folder as
--- new models are ready:
---   local CreatureModels = require(game.ReplicatedStorage.DreamPinballShared.CreatureModels)
---   CreatureModels.ensureSpeciesFolder("SeaGoblin")
--- Then drag PinballModel/CreatureModel Models into the folder it creates
--- (or prints the path to, if it already exists), name them exactly
--- "PinballModel" / "CreatureModel", and Ctrl+S.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROOT_FOLDER_NAME = "CreatureModelAssets"
local PINBALL_MODEL_NAME = "PinballModel"
local CREATURE_MODEL_NAME = "CreatureModel"

local CreatureModels = {}

local function getRootFolder(): Folder
	local shared = ReplicatedStorage:WaitForChild("DreamPinballShared")
	local existing = shared:FindFirstChild(ROOT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local root = Instance.new("Folder")
	root.Name = ROOT_FOLDER_NAME
	root.Parent = shared
	return root
end

--- Creates (or finds) the folder for one species, ready for PinballModel/
--- CreatureModel to be dragged in by hand. Safe to call repeatedly -- never
--- destroys an existing folder or its contents.
function CreatureModels.ensureSpeciesFolder(species: string): Folder
	local root = getRootFolder()
	local existing = root:FindFirstChild(species)
	if existing and existing:IsA("Folder") then
		print("CreatureModels: '" .. species .. "' folder already exists at " .. existing:GetFullName())
		return existing
	end

	local speciesFolder = Instance.new("Folder")
	speciesFolder.Name = species
	speciesFolder.Parent = root
	print("CreatureModels: created '" .. species .. "' folder at " .. speciesFolder:GetFullName() .. " -- drag in PinballModel/CreatureModel Models")
	return speciesFolder
end

--- Returns the given species' pinball-form Model, or nil if that species
--- folder or its PinballModel doesn't exist yet.
function CreatureModels.getPinballModel(species: string): Model?
	local root = getRootFolder()
	local speciesFolder = root:FindFirstChild(species)
	if not speciesFolder then
		return nil
	end
	local model = speciesFolder:FindFirstChild(PINBALL_MODEL_NAME)
	return if model and model:IsA("Model") then model else nil
end

--- Returns the given species' walking-around-form Model, or nil if that
--- species folder or its CreatureModel doesn't exist yet (this form is
--- expected to lag behind PinballModel for many species early on).
function CreatureModels.getCreatureModel(species: string): Model?
	local root = getRootFolder()
	local speciesFolder = root:FindFirstChild(species)
	if not speciesFolder then
		return nil
	end
	local model = speciesFolder:FindFirstChild(CREATURE_MODEL_NAME)
	return if model and model:IsA("Model") then model else nil
end

return CreatureModels
