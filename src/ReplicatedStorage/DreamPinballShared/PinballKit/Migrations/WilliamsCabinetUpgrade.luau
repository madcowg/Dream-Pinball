--!strict

-- One-shot migration: replaces WilliamsCabinet's hand-built LeftFlipper/
-- RightFlipper/Bumper markers with PinballKit-generated equivalents, WITHOUT
-- deleting the originals -- they're moved into a backup Folder first, so
-- Revert() can restore them exactly. Run from Studio's Command Bar (see
-- README.md for the exact snippet); this is Studio-instance surgery, it
-- cannot run headlessly and has not been tested against the live cabinet.
--
-- IMPORTANT -- read before running:
--   This script cannot see WilliamsCabinet's actual current geometry ahead of
--   time (it only exists in the Studio place file, not in git/Rojo-tracked
--   source). It computes the new flippers' placement FROM the existing
--   flipper Parts' own live CFrame at the moment you run it, using the
--   formula documented in EACH step below -- but per architecture.md's
--   "Flipper baseline" note (yaw/orientation reasoning has repeatedly been
--   wrong in this project without live verification), you MUST visually
--   check the result in Studio immediately after running this, BEFORE
--   testing gameplay:
--     - Do the new flippers sit at roughly the same position/angle as the
--       old ones?
--     - Does each flipper's paddle extend toward the correct side (not
--       mirrored)?
--     - Does pressing Q/E in Play mode raise the correct flipper?
--   If anything looks wrong, call Revert() immediately -- it costs nothing,
--   the originals are untouched in the backup folder.

local PhysicsService = game:GetService("PhysicsService")

local PinballKit = script.Parent.Parent
local FlipperGenerator = require(PinballKit.Generators.FlipperGenerator)
local BumperGenerator = require(PinballKit.Generators.BumperGenerator)
local Presets = require(PinballKit.Presets)
local CabinetBuilder = require(script.Parent.Parent.Parent.CabinetBuilder)

local WilliamsCabinetUpgrade = {}

local BACKUP_FOLDER_NAME = "PreUpgradeBackup"
local FLIPPER_GROUP = "WilliamsCabinetFlippers"
local PLAYFIELD_GROUP = "WilliamsCabinetPlayfield"

local function findPivotAttachment(flipperPart: BasePart): Attachment
	local attachments = {}
	for _, child in ipairs(flipperPart:GetChildren()) do
		if child:IsA("Attachment") then
			table.insert(attachments, child)
		end
	end
	if #attachments ~= 1 then
		error(
			string.format(
				"WilliamsCabinetUpgrade: %s has %d Attachments, expected exactly 1 pivot marker -- cannot determine hinge point",
				flipperPart:GetFullName(),
				#attachments
			),
			0
		)
	end
	return attachments[1]
end

export type UpgradeReport = {
	LeftFlipperOrigin: CFrame,
	RightFlipperOrigin: CFrame,
	BumperCount: number,
}

-- Replaces the flippers and every "Bumper"-named part. Idempotent guard: errors
-- if a backup already exists (run Revert() first if you want to try again).
function WilliamsCabinetUpgrade.Upgrade(cabinetFolder: Instance): UpgradeReport
	if cabinetFolder:FindFirstChild(BACKUP_FOLDER_NAME) then
		error(
			"WilliamsCabinetUpgrade.Upgrade: a "
				.. BACKUP_FOLDER_NAME
				.. " already exists under "
				.. cabinetFolder:GetFullName()
				.. " -- call Revert() first if you want to re-run this",
			0
		)
	end

	local leftFlipperPart = cabinetFolder:FindFirstChild("LeftFlipper", true) :: BasePart?
	local rightFlipperPart = cabinetFolder:FindFirstChild("RightFlipper", true) :: BasePart?
	if leftFlipperPart == nil or rightFlipperPart == nil then
		error("WilliamsCabinetUpgrade.Upgrade: could not find LeftFlipper/RightFlipper under " .. cabinetFolder:GetFullName(), 0)
	end
	local leftFlipper = leftFlipperPart :: BasePart
	local rightFlipper = rightFlipperPart :: BasePart

	-- Pivot world CFrame = the flipper's own current rotation (assumed already
	-- correctly flush with the tilted playfield, since the team built it that
	-- way), translated to the pivot Attachment's world position (using the
	-- Attachment's own precomputed .WorldPosition rather than re-deriving it).
	-- RestAngleDegrees is passed as 0 below specifically so this CFrame is
	-- used AS THE FINAL rest pose directly, with no additional rotation
	-- applied on top -- see this module's header comment.
	local function pivotOrigin(flipperPart: BasePart): CFrame
		local pivotAttachment = findPivotAttachment(flipperPart)
		return CFrame.new(pivotAttachment.WorldPosition) * (flipperPart.CFrame - flipperPart.CFrame.Position)
	end

	local leftOrigin = pivotOrigin(leftFlipper)
	local rightOrigin = pivotOrigin(rightFlipper)

	local bumperBackups: { { Part: BasePart, CFrame: CFrame, PointValue: any, OriginalName: string } } = {}
	for _, descendant in ipairs(cabinetFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Bumper" then
			table.insert(bumperBackups, {
				Part = descendant,
				CFrame = descendant.CFrame,
				PointValue = descendant:GetAttribute("PointValue"),
				OriginalName = descendant.Name,
			})
		end
	end

	-- Move originals into the backup folder BEFORE generating anything new --
	-- if generation errors partway through, the originals are still intact
	-- and findable, not deleted. Renamed first: CabinetGameplay.setup finds
	-- markers by recursive name search (FindFirstChild(name, true) /
	-- GetDescendants scanning for "Bumper"), which would otherwise still find
	-- these backed-up originals sitting right next to their replacements and
	-- wire BOTH -- storing OriginalName above is what lets Revert() name them
	-- back correctly.
	local backup = Instance.new("Folder")
	backup.Name = BACKUP_FOLDER_NAME
	leftFlipper.Name = "LeftFlipper_Backup"
	rightFlipper.Name = "RightFlipper_Backup"
	leftFlipper.Parent = backup
	rightFlipper.Parent = backup
	for index, info in ipairs(bumperBackups) do
		info.Part.Name = string.format("Bumper_Backup_%d", index)
		info.Part.Parent = backup
	end
	backup.Parent = cabinetFolder

	pcall(function()
		CabinetBuilder.ensureCollisionGroups(FLIPPER_GROUP, PLAYFIELD_GROUP)
	end)

	FlipperGenerator.Generate({
		Name = "LeftFlipper",
		Origin = leftOrigin,
		Parent = cabinetFolder,
		Config = Presets.Extend(Presets.WilliamsClassic.Flipper, {
			Side = "Left",
			RestAngleDegrees = 0,
			CollisionGroup = FLIPPER_GROUP,
		}),
	})

	FlipperGenerator.Generate({
		Name = "RightFlipper",
		Origin = rightOrigin,
		Parent = cabinetFolder,
		Config = Presets.Extend(Presets.WilliamsClassic.Flipper, {
			Side = "Right",
			RestAngleDegrees = 0,
			CollisionGroup = FLIPPER_GROUP,
		}),
	})

	for index, info in ipairs(bumperBackups) do
		local pointValue = if typeof(info.PointValue) == "number" then info.PointValue else nil
		local asset = BumperGenerator.Generate({
			Name = string.format("Bumper_%d", index),
			Origin = info.CFrame,
			Parent = cabinetFolder,
			Config = Presets.Extend(Presets.WilliamsClassic.PopBumper, {
				CollisionGroup = PLAYFIELD_GROUP,
				PointValue = pointValue,
			}),
		})
		-- CabinetGameplay finds scoring bumpers by literally checking
		-- Name == "Bumper" on a BasePart -- rename the generated Body so the
		-- EXISTING scoring/durability/HUD logic keeps working unchanged.
		asset.Body.Name = "Bumper"
	end

	print(
		string.format(
			"WilliamsCabinetUpgrade: replaced 2 flippers and %d bumper(s). Originals backed up under %s. VERIFY visually before testing gameplay -- see this module's header comment.",
			#bumperBackups,
			backup:GetFullName()
		)
	)

	return {
		LeftFlipperOrigin = leftOrigin,
		RightFlipperOrigin = rightOrigin,
		BumperCount = #bumperBackups,
	}
end

-- Destroys the generated replacements and restores the originals from the
-- backup folder. Safe to call any time after Upgrade(); errors if there's no
-- backup to restore from.
function WilliamsCabinetUpgrade.Revert(cabinetFolder: Instance)
	local backup = cabinetFolder:FindFirstChild(BACKUP_FOLDER_NAME)
	if backup == nil then
		error("WilliamsCabinetUpgrade.Revert: no " .. BACKUP_FOLDER_NAME .. " found under " .. cabinetFolder:GetFullName(), 0)
	end

	for _, child in ipairs(cabinetFolder:GetChildren()) do
		if child:GetAttribute("PinballAsset") == true then
			local assetType = child:GetAttribute("AssetType")
			if assetType == "Flipper" or assetType == "Bumper" then
				child:Destroy()
			end
		end
	end

	-- Restore original names before reparenting back out of the backup
	-- folder -- see the "Renamed first" comment in Upgrade().
	for _, child in ipairs((backup :: Folder):GetChildren()) do
		if child.Name == "LeftFlipper_Backup" then
			child.Name = "LeftFlipper"
		elseif child.Name == "RightFlipper_Backup" then
			child.Name = "RightFlipper"
		elseif child:IsA("BasePart") and child.Name:match("^Bumper_Backup_%d+$") then
			child.Name = "Bumper"
		end
		child.Parent = cabinetFolder
	end
	backup:Destroy()

	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(FLIPPER_GROUP, PLAYFIELD_GROUP, true)
	end)

	print("WilliamsCabinetUpgrade: reverted -- original LeftFlipper/RightFlipper/Bumper parts restored.")
end

return WilliamsCabinetUpgrade
