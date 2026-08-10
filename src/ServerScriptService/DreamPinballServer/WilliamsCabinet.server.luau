--!strict

--- Wires up full gameplay (turn state, launch, items, scoring, drain, HUD,
--- fixed camera, movement lock, interact prompt) on the team's hand-built
--- WilliamsCabinet (Workspace.BakedCabinets.WilliamsCabinet), using
--- CabinetGameplay.setup -- the same discovery-based wiring any future
--- hand-built, commercial-spec cabinet can reuse just by matching its
--- required marker names (see CabinetGameplay.luau's doc comment for the
--- full list: LeftFlipper/RightFlipper with a working hinge, Bumper x N,
--- DrainTrigger, LaunchAnchor, InteractAnchor, CameraAnchor).
---
--- Completely separate from CabinetDesignsTest.server.luau's three
--- code-built comparison cabinets -- neither script touches the other's
--- state, and a player can be engaged with a WilliamsCabinet run and one of
--- the CabinetDesignsTest cabinets at the same time without conflict (two
--- independent engagedPlayer trackers).
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local CabinetGameplay = require(DreamPinballShared:WaitForChild("CabinetGameplay"))
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))
local LaunchRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("LaunchInput"))
local ItemRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("ItemInput"))

local BAKED_FOLDER_NAME = "BakedCabinets"
local CABINET_NAME = "WilliamsCabinet"

local bakedFolder = Workspace:WaitForChild(BAKED_FOLDER_NAME)
local cabinetFolder = bakedFolder:WaitForChild(CABINET_NAME)

-- CabinetGameplay.setup errors immediately (naming the missing marker) if
-- WilliamsCabinet is missing a required piece -- see CabinetGameplay.luau's
-- doc comment for the full list and how to build each one.
local gameplay = CabinetGameplay.setup(cabinetFolder, "WilliamsCabinet")

local function onFlipperInput(player: Player, side: unknown, pressed: unknown)
	if not gameplay.IsEngagedBy(player) then
		return
	end
	if typeof(side) ~= "string" or (side ~= "Left" and side ~= "Right") then
		warn("WilliamsCabinet: rejected invalid side value from " .. player.Name)
		return
	end
	if typeof(pressed) ~= "boolean" then
		warn("WilliamsCabinet: rejected invalid pressed value from " .. player.Name)
		return
	end
	gameplay.SetFlipperInput(side :: "Left" | "Right", pressed)
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
		warn("WilliamsCabinet: rejected invalid launch input from " .. player.Name)
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

print("WilliamsCabinet: gameplay wired up -- press F on its interact prompt to start a level")
