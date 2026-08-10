--!strict

--- Visual assets that AREN'T tied to any one creature species -- e.g.
--- StainlessBall, the plain neutral steel ball used by the Extra Ball item
--- (Ball.BallData.Species == nil). See CreatureModels.luau for per-species
--- (Sea Goblin, etc.) pinball/creature models instead.
---
--- Folder structure (ReplicatedStorage.DreamPinballShared.SharedModelAssets --
--- named distinctly from this ModuleScript itself: Roblox does not allow a
--- Folder and a ModuleScript to share the same name under the same parent,
--- which is exactly the naming collision hit when this used to be called
--- "SharedModels" like the script):
---   SharedModelAssets
---     StainlessBall
---
--- Just drag Models directly into SharedModelAssets in Studio and name them
--- exactly what getModel(name) will be called with -- no per-item
--- sub-folder needed, unlike CreatureModels' two-form-per-species layout.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROOT_FOLDER_NAME = "SharedModelAssets"

local SharedModels = {}

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

--- Returns the named shared Model (e.g. "StainlessBall"), or nil if it
--- hasn't been added to SharedModels yet.
function SharedModels.getModel(name: string): Model?
	local root = getRootFolder()
	local model = root:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

return SharedModels
