--!strict

--- Twin of WilliamsCabinet.server.luau, wired to the SAME CabinetGameplay
--- engine, pointed at Workspace.BakedCabinets.WilliamsCabinetPlayground
--- instead of the live WilliamsCabinet -- a full second, independently
--- playable cabinet, not a preview/no-op. Purpose: a sandbox to test
--- gameplay/CabinetUpgrade changes on before they touch the real
--- WilliamsCabinet, and the template to copy when building future
--- hand-built cabinets (copy this file, change CABINET_NAME/the label
--- string, done -- CabinetGameplay.setup finds everything else by marker
--- name, same as it does here).
---
--- Completely independent of WilliamsCabinet.server.luau -- its own
--- CabinetGameplay.setup call, its own engagedPlayer tracker. A player can
--- be engaged with WilliamsCabinet and WilliamsCabinetPlayground at the
--- same time without conflict, same guarantee CabinetDesignsTest.server.luau
--- already relies on for its three comparison cabinets.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local CabinetGameplay = require(DreamPinballShared:WaitForChild("CabinetGameplay"))
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))
local LaunchRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("LaunchInput"))
local ItemRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("ItemInput"))

local BAKED_FOLDER_NAME = "BakedCabinets"
local CABINET_NAME = "WilliamsCabinetPlayground"

local bakedFolder = Workspace:WaitForChild(BAKED_FOLDER_NAME)
local cabinetFolder = bakedFolder:WaitForChild(CABINET_NAME)

-- CabinetGameplay.setup errors immediately (naming the missing marker) if
-- WilliamsCabinetPlayground is missing a required piece -- see
-- CabinetGameplay.luau's doc comment for the full list and how to build
-- each one. If this halts here, WilliamsCabinet.server.luau (a separate
-- script) is unaffected -- one cabinet's missing marker never blocks the
-- other's setup.
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
