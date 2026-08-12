--!strict

--- Cabinet01: wired to the SAME CabinetGameplay engine as WilliamsCabinet and
--- WilliamsCabinetPlayground, using the exact template those two established
--- (copy this file, change CABINET_NAME, done -- CabinetGameplay.setup finds
--- everything else by marker name). Completely independent -- its own
--- CabinetGameplay.setup call, its own engagedPlayer tracker. See
--- Cabinet01Builder.luau for how the cabinet itself is constructed and its
--- full spatial contract/live-verification notes.
---
--- Unlike WilliamsCabinet/WilliamsCabinetPlayground (built once by hand in
--- Studio), this auto-builds Cabinet01 from Cabinet01Builder if it's missing
--- -- so a fresh clone of this repo is playable without a manual Command Bar
--- step first. If the team later hand-edits Cabinet01 in Studio and wants to
--- keep those edits, do NOT re-run Cabinet01Builder.build() (it destroys and
--- rebuilds from scratch) -- this auto-build only fires when the folder is
--- entirely absent.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local CabinetGameplay = require(DreamPinballShared:WaitForChild("CabinetGameplay"))
local Cabinet01Builder = require(DreamPinballShared:WaitForChild("Cabinet01Builder"))
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))
local LaunchRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("LaunchInput"))
local ItemRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("ItemInput"))

local BAKED_FOLDER_NAME = "BakedCabinets"
local CABINET_NAME = "Cabinet01"

local bakedFolder = Workspace:FindFirstChild(BAKED_FOLDER_NAME)
if not bakedFolder then
	bakedFolder = Instance.new("Folder")
	bakedFolder.Name = BAKED_FOLDER_NAME
	bakedFolder.Parent = Workspace
end

local cabinetFolder = bakedFolder:FindFirstChild(CABINET_NAME)
if not cabinetFolder then
	warn(CABINET_NAME .. ": not found under Workspace." .. BAKED_FOLDER_NAME .. ", building it now via Cabinet01Builder")
	cabinetFolder = Cabinet01Builder.build()
end

-- CabinetGameplay.setup errors immediately (naming the missing marker) if
-- Cabinet01 is missing a required piece -- see CabinetGameplay.luau's doc
-- comment for the full list. If this halts here, WilliamsCabinet.server.luau
-- and WilliamsCabinetPlayground.server.luau (separate scripts) are
-- unaffected -- one cabinet's missing marker never blocks the others' setup.
local gameplay = CabinetGameplay.setup(cabinetFolder, CABINET_NAME)

local function onFlipperInput(player: Player, side: unknown, pressed: unknown)
	if not gameplay.IsEngagedBy(player) then
		return
	end
	local resolvedSide, resolvedPressed = FlipperRemotes.ValidateInput(side, pressed)
	if resolvedSide == nil or resolvedPressed == nil then
		warn(CABINET_NAME .. ": rejected invalid flipper input from " .. player.Name)
		return
	end
	gameplay.SetFlipperInput(resolvedSide, resolvedPressed)
end

local function onLaunchInput(player: Player, action: unknown, power: unknown)
	if not gameplay.IsEngagedBy(player) then
		return
	end

	if action == "charge" then
		gameplay.BeginCharge(player)
		return
	end

	if action ~= "release" or typeof(power) ~= "number" then
		warn(CABINET_NAME .. ": rejected invalid launch input from " .. player.Name)
		return
	end
	gameplay.Launch(player, math.clamp(power, 0.2, 1))
end

local function onItemInput(player: Player, itemId: unknown)
	if not gameplay.IsEngagedBy(player) then
		return
	end
	gameplay.UseItem(player, itemId)
end

FlipperRemotes.getFlipperInputRemote().OnServerEvent:Connect(onFlipperInput)
LaunchRemotes.getLaunchInputRemote().OnServerEvent:Connect(onLaunchInput)
ItemRemotes.getItemInputRemote().OnServerEvent:Connect(onItemInput)

game.Players.PlayerRemoving:Connect(function(player: Player)
	gameplay.ForceDisengage(player)
end)

print(CABINET_NAME .. ": gameplay wired up -- press F on its interact prompt to start a level")
