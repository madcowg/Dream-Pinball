--!strict

--- Cabinet01: the first cabinet built under ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md's
--- spatial-contract discipline instead of a hand-copied Left/Right sign
--- table. Coexists with WilliamsCabinet and WilliamsCabinetPlayground --
--- does not replace or modify either. Minimal "flippers first" scope:
--- launch, flip, score on 2 bumpers, drain. No plunger lane, no backboard,
--- no cosmetic shell yet -- see TODO.md for the deferred follow-up list.
---
--- Marker names match CabinetGameplay.luau's REQUIRED list exactly (see that
--- module's doc comment), so:
---   1. CabinetGameplay.setup(cabinetFolder, "Cabinet01") (Cabinet01.server.luau)
---      wires up the full gameplay loop with zero cabinet-specific code
---      beyond this builder.
---   2. LeftFlipper/RightFlipper/Bumper/etc. can be cut/pasted between this
---      cabinet and WilliamsCabinet/WilliamsCabinetPlayground by name if the
---      team wants to move geometry between them later.
---
--- Spatial contract: Cabinet01 playfield
--- Reference: Workspace.BakedCabinets.Cabinet01.CabinetRoot
--- Reference frame: object -- everything below is built relative to
---   RAMP_CFRAME, which shares CabinetRoot's position (see SCENE_SPEC.md's
---   instance map for the exact nesting).
--- Pivot: CabinetRoot's own CFrame (a plain anchored Part, zero rotation --
---   the ramp tilt below is a Playfield-only property, not applied to
---   CabinetRoot itself).
--- Forward/up/right convention: RAMP_CFRAME's local +Z runs from the drain
---   (Z=0, low/front end, where the player stands) to the back wall
---   (Z=TABLE_LENGTH, high/back end); local +Y is the ramp's own normal
---   (tilted, not world-up); local +X is screen-right when standing at the
---   front looking up-table (+Z). UNLIKE CabinetBuilder.luau's
---   computeRampCFrame, this deliberately does NOT apply a 180-degree yaw
---   first -- there is no hidden Left/Right flip to reason about here, by
---   design, specifically to avoid the class of bug documented in
---   architecture.md's "Flipper baseline" section.
--- Output transform: every static part's CFrame is
---   RAMP_CFRAME * CFrame.new(localX, heightAboveFloor, localZ) [* rotation],
---   via CabinetBuilder.pointOnRamp (reused, not re-derived).
--- Boundary cases / NOT yet live-verified -- see "Live verification" below.
---
--- LeftFlipper/RightFlipper are built as a TRUE mirror pair (position
--- mirrored across the table's own centerline plane, rest angle mirrored via
--- PinballKit.Geometry.MirrorTransform.MirrorAngleDegrees -- FlipperGenerator's
--- own convention, NOT MirrorCFrame's whole-orientation reflection, per
--- MirrorTransform.luau's doc comment) -- there is no separate hand-authored
--- sign for flipper PLACEMENT here; only Left's rest pose is chosen by hand,
--- and Right is derived from it by mirroring, so the two are geometrically
--- guaranteed to be mirror images of each other. The hinge's MOTOR direction
--- itself still comes entirely from CabinetGameplay.setup's existing
--- auto-build path (CabinetBuilder.attachFlipperHinge + its SWEEP_DIRECTION
--- table) -- the exact same mechanism already in use on WilliamsCabinet and
--- WilliamsCabinetPlayground. SWEEP_DIRECTION was flipped 2026-08-12 (see
--- CabinetBuilder.luau and architecture.md "Flipper baseline") after live
--- testing showed WilliamsCabinet/WilliamsCabinetPlayground's flippers
--- responding backwards under the correct, natural key mapping -- Cabinet01
--- inherits that same fix automatically since it goes through the same
--- attachFlipperHinge call, not a separate copy.
---
--- LIVE VERIFICATION REQUIRED -- do not trust any of this from code reading
--- alone (do not claim it works until it's been played in Studio):
---  1. If the ball at rest rolls UP-table (toward the back wall) instead of
---     down toward the drain, negate TILT_DEGREES below and re-run.
---  2. If either flipper sweeps AWAY from the table's center instead of
---     toward it, check WilliamsCabinet's flippers in the SAME Play session
---     first. If both cabinets agree (both backwards or both correct), the
---     fix belongs in CabinetBuilder.luau's SWEEP_DIRECTION table (shared,
---     cabinet-agnostic -- see architecture.md "Flipper baseline"). NEVER
---     "fix" this by inverting FlipperInputController.local.luau's
---     KEY_TO_SIDE -- Q is always the physically-left flipper's key, E is
---     always the physically-right flipper's key, regardless of any hinge
---     wiring bug; see that file's own doc comment. If ONLY Cabinet01
---     disagrees with WilliamsCabinet, the bug is in this builder's
---     LeftFlipper/RightFlipper CFrames below, not SWEEP_DIRECTION (which is
---     shared, so it can't be the cause of a Cabinet01-only disagreement).
---  3. CAMERA_ANCHOR's framing below is an authored guess (reusing the exact
---     ratios CabinetBuilder.build confirmed live for a 52-stud table, but
---     without that module's 180-degree yaw, so the sign of the "behind the
---     table" offset is a fresh guess, not re-derived math). If the fixed
---     camera doesn't frame the table sensibly, run
---     CabinetGameplay.snapCameraAnchorToViewport(cameraAnchorPart) from the
---     Command Bar after flying Studio's edit camera to the desired view --
---     no need to hand-fix the math here.
---  4. MainFieldEntry sits immediately next to LaunchAnchor (no separate
---     plunger lane in this pass), so "rolled back into the lane, re-launch
---     with R" barely applies here -- a weak launch will register as
---     drained almost immediately instead. Acceptable for this minimal pass;
---     a real plunger lane is a deferred follow-up (see TODO.md).
---
--- Run once from Studio's Command Bar (Edit mode), then Ctrl+S:
---   local Cabinet01Builder = require(game.ReplicatedStorage.DreamPinballShared.Cabinet01Builder)
---   Cabinet01Builder.build()
--- Safe to re-run: destroys and rebuilds Workspace.BakedCabinets.Cabinet01
--- from scratch each time (same convention CabinetBaker used to follow).
--- Do NOT re-run after the team has hand-edited Cabinet01 in Studio -- same
--- caution as CabinetBaker's own doc comment (see TODO.md).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local CabinetBuilder = require(DreamPinballShared:WaitForChild("CabinetBuilder"))
local PinballKit = DreamPinballShared:WaitForChild("PinballKit")
local MirrorTransform = require(PinballKit:WaitForChild("Geometry"):WaitForChild("MirrorTransform"))

local Cabinet01Builder = {}

local BAKED_FOLDER_NAME = "BakedCabinets"
local CABINET_NAME = "Cabinet01"

-- Placed well clear of WilliamsCabinet/WilliamsCabinetPlayground (near world
-- origin) and the Lower Playfield test rig (75, 1, 0) -- see TODO.md.
local ORIGIN = Vector3.new(150, 9, 0)
local TABLE_WIDTH = 24
local TABLE_LENGTH = 52
local TILT_DEGREES = 6.5 -- authored guess, NOT live-verified -- see doc comment above
local FLOOR_THICKNESS = 1
local WALL_HEIGHT = 4
local WALL_THICKNESS = 1.5
local DRAIN_GAP_WIDTH = 8 -- gap in the front wall the ball falls through when it drains

local FLIPPER_SIZE = Vector3.new(7.5, 1.25, 2.5) -- matches the calibrated reference flipper, see GameplayTuning.luau
local FLIPPER_PIVOT_OFFSET_X = 5
local FLIPPER_ZONE_Z = 6 -- how far up-table from the drain the flipper pivots sit
local FLIPPER_REST_ANGLE_DEGREES = 45 -- magnitude only; Left's sign is chosen once below, Right is its true mirror
local FLIPPER_SURFACE_GAP = 0.5

local RAMP_CFRAME = CFrame.new(ORIGIN) * CFrame.Angles(math.rad(TILT_DEGREES), 0, 0)

local function pointOnRamp(localX: number, localZ: number, heightAboveSurface: number): CFrame
	return CabinetBuilder.pointOnRamp(RAMP_CFRAME, localX, localZ, heightAboveSurface)
end

local function buildFloorAndWalls(parent: Instance, playfieldGroup: string): BasePart
	local floor = Instance.new("Part")
	floor.Name = "CabinetFloor"
	floor.Size = Vector3.new(TABLE_WIDTH, FLOOR_THICKNESS, TABLE_LENGTH)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Color = Color3.fromRGB(60, 90, 60)
	floor.CFrame = RAMP_CFRAME * CFrame.new(0, 0, TABLE_LENGTH / 2)
	floor.CustomPhysicalProperties = PhysicalProperties.new(2, 0.2, 0.5, 1, 1)
	floor.Parent = parent
	floor.CollisionGroup = playfieldGroup

	local function wallAlongZ(name: string, xOffset: number, zCenter: number, zLength: number)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, zLength)
		part.Anchored = true
		part.CanCollide = true
		part.Transparency = 0.5
		part.Color = Color3.fromRGB(90, 90, 90)
		part.CFrame = RAMP_CFRAME * CFrame.new(xOffset, WALL_HEIGHT / 2, zCenter)
		part.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
		part.Parent = parent
		part.CollisionGroup = playfieldGroup
	end

	local function wallAlongX(name: string, xCenter: number, zOffset: number, xLength: number)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(xLength, WALL_HEIGHT, WALL_THICKNESS)
		part.Anchored = true
		part.CanCollide = true
		part.Transparency = 0.5
		part.Color = Color3.fromRGB(90, 90, 90)
		part.CFrame = RAMP_CFRAME * CFrame.new(xCenter, WALL_HEIGHT / 2, zOffset)
		part.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
		part.Parent = parent
		part.CollisionGroup = playfieldGroup
	end

	wallAlongZ("LeftWall", -TABLE_WIDTH / 2, TABLE_LENGTH / 2, TABLE_LENGTH)
	wallAlongZ("RightWall", TABLE_WIDTH / 2, TABLE_LENGTH / 2, TABLE_LENGTH)
	wallAlongX("BackWall", 0, TABLE_LENGTH, TABLE_WIDTH)

	-- Front wall, split around the drain gap (centered at local X=0).
	local frontSegmentLength = (TABLE_WIDTH - DRAIN_GAP_WIDTH) / 2
	local frontSegmentCenterX = DRAIN_GAP_WIDTH / 2 + frontSegmentLength / 2
	wallAlongX("FrontWallLeft", -frontSegmentCenterX, 0, frontSegmentLength)
	wallAlongX("FrontWallRight", frontSegmentCenterX, 0, frontSegmentLength)

	return floor
end

local function buildDrainTrigger(parent: Instance): BasePart
	local drainTrigger = Instance.new("Part")
	drainTrigger.Name = "DrainTrigger"
	drainTrigger.Size = Vector3.new(DRAIN_GAP_WIDTH, WALL_HEIGHT, 2)
	drainTrigger.Anchored = true
	drainTrigger.CanCollide = false
	drainTrigger.Transparency = 1
	-- Past the drain edge (negative local Z) and below the floor surface
	-- (negative height) -- see architecture.md's "A DrainTrigger must sit
	-- PAST the drain edge and BELOW the floor surface" note.
	drainTrigger.CFrame = pointOnRamp(0, -3, -8)
	drainTrigger.Parent = parent
	return drainTrigger
end

local function buildLaunchAnchorAndMainFieldEntry(parent: Instance): (BasePart, BasePart)
	local launchLocalX = TABLE_WIDTH / 2 - 3
	local launchLocalZ = TABLE_LENGTH - 6

	local launchAnchor = Instance.new("Part")
	launchAnchor.Name = "LaunchAnchor"
	launchAnchor.Size = Vector3.new(1, 1, 1)
	launchAnchor.Anchored = true
	launchAnchor.CanCollide = false
	launchAnchor.Transparency = 1
	-- Local 180-degree yaw so THIS part's own LookVector (+Z) points back
	-- down-table toward the flippers/drain, matching CabinetGameplay's
	-- "launches along its own forward (+Z)" contract -- this yaw is local to
	-- just this one Part, not a change to RAMP_CFRAME's own convention.
	launchAnchor.CFrame = pointOnRamp(launchLocalX, launchLocalZ, 1) * CFrame.Angles(0, math.rad(180), 0)
	launchAnchor.Parent = parent

	local mainFieldEntry = Instance.new("Part")
	mainFieldEntry.Name = "MainFieldEntry"
	mainFieldEntry.Size = Vector3.new(4, WALL_HEIGHT, 1)
	mainFieldEntry.Anchored = true
	mainFieldEntry.CanCollide = false
	mainFieldEntry.Transparency = 1
	mainFieldEntry.CFrame = pointOnRamp(launchLocalX, launchLocalZ - 2, 1)
	mainFieldEntry.Parent = parent

	return launchAnchor, mainFieldEntry
end

--- Builds Left's rest CFrame by hand (one authored choice), then derives
--- Right by mirroring position + negating the signed rest angle --
--- FlipperGenerator's own convention (MirrorTransform.luau's doc comment
--- explicitly warns MirrorCFrame's whole-orientation reflection is NOT
--- equivalent to this for a flipper paddle's own rest orientation and would
--- silently produce the wrong Right rest angle).
local function buildFlippers(parent: Instance): (BasePart, BasePart)
	local leftRestCFrame = pointOnRamp(-FLIPPER_PIVOT_OFFSET_X, FLIPPER_ZONE_Z, FLIPPER_SURFACE_GAP)
		* CFrame.Angles(0, math.rad(-FLIPPER_REST_ANGLE_DEGREES), 0)

	local rightRestCFrame = pointOnRamp(FLIPPER_PIVOT_OFFSET_X, FLIPPER_ZONE_Z, FLIPPER_SURFACE_GAP)
		* CFrame.Angles(0, math.rad(MirrorTransform.MirrorAngleDegrees(-FLIPPER_REST_ANGLE_DEGREES)), 0)

	local function buildFlipperPart(name: string, restCFrame: CFrame): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = FLIPPER_SIZE
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(200, 60, 60)
		part.Anchored = false
		part.CanCollide = true
		part.CustomPhysicalProperties = PhysicalProperties.new(3, 0.75, 0.65, 1, 1)
		part.CFrame = restCFrame
		part.Parent = parent

		-- Exactly one Attachment, at the box's own near edge (local -X/2) --
		-- CabinetGameplay.setup's findPivotAttachment requires exactly one,
		-- and auto-builds the hinge from it via CabinetBuilder.attachFlipperHinge
		-- the first time the server starts (see that module's doc comment).
		-- Not built here: this is the exact same mechanism already proven on
		-- WilliamsCabinet/WilliamsCabinetPlayground, deliberately reused
		-- as-is rather than re-implemented for this cabinet.
		local pivotAttachment = Instance.new("Attachment")
		pivotAttachment.Name = "Pivot"
		pivotAttachment.Position = Vector3.new(-FLIPPER_SIZE.X / 2, 0, 0)
		pivotAttachment.Parent = part

		return part
	end

	local leftFlipper = buildFlipperPart("LeftFlipper", leftRestCFrame)
	local rightFlipper = buildFlipperPart("RightFlipper", rightRestCFrame)
	return leftFlipper, rightFlipper
end

local function buildInteractAnchor(parent: Instance): BasePart
	local frontEdgeWorld = (RAMP_CFRAME * CFrame.new(0, 0, 0)).Position
	-- ORIGIN.Y was chosen as 9 studs above the ground (matching the "well
	-- above where a player's capsule can reach" convention used elsewhere in
	-- this project) -- so ground level is ORIGIN.Y - 9.
	local groundWorldY = ORIGIN.Y - 9
	local interactAnchor = Instance.new("Part")
	interactAnchor.Name = "InteractAnchor"
	interactAnchor.Size = Vector3.new(1, 1, 1)
	interactAnchor.Anchored = true
	interactAnchor.CanCollide = false
	interactAnchor.Transparency = 1
	interactAnchor.CFrame = CFrame.new(frontEdgeWorld.X, groundWorldY + 4, frontEdgeWorld.Z - 4)
	interactAnchor.Parent = parent
	return interactAnchor
end

local function buildCameraAnchor(parent: Instance): BasePart
	-- Reuses the exact height/back/look-at ratios CabinetBuilder.build
	-- confirmed live for a 52-stud table (TABLE_LENGTH here is also 52, on
	-- purpose, so the absolute numbers transfer directly) -- but WITHOUT
	-- that module's 180-degree yaw, so the camera sits behind the FRONT
	-- (drain/player) end here, not the back end. See "Live verification"
	-- item 3 in this module's doc comment if this framing looks wrong.
	local cameraPosition = ORIGIN + Vector3.new(0, 17, -21)
	local lookAtPosition = ORIGIN + Vector3.new(0, 1, 17)

	local cameraAnchor = Instance.new("Part")
	cameraAnchor.Name = "CameraAnchor"
	cameraAnchor.Size = Vector3.new(1, 1, 1)
	cameraAnchor.Anchored = true
	cameraAnchor.CanCollide = false
	cameraAnchor.Transparency = 1
	cameraAnchor.CFrame = CFrame.lookAt(cameraPosition, lookAtPosition)
	cameraAnchor.Parent = parent
	return cameraAnchor
end

function Cabinet01Builder.build()
	local bakedFolder = Workspace:FindFirstChild(BAKED_FOLDER_NAME)
	if not bakedFolder then
		bakedFolder = Instance.new("Folder")
		bakedFolder.Name = BAKED_FOLDER_NAME
		bakedFolder.Parent = Workspace
	end

	local existing = bakedFolder:FindFirstChild(CABINET_NAME)
	if existing then
		existing:Destroy()
	end

	local cabinetFolder = Instance.new("Folder")
	cabinetFolder.Name = CABINET_NAME
	cabinetFolder.Parent = bakedFolder

	-- Required hierarchy per ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md section 1A --
	-- see SCENE_SPEC.md for the exact mapping from this hierarchy to
	-- CabinetGameplay.luau's flat marker names (found by FindFirstChild(name, true),
	-- so nesting them here doesn't break that lookup).
	local cabinetRoot = Instance.new("Part")
	cabinetRoot.Name = "CabinetRoot"
	cabinetRoot.Size = Vector3.new(1, 1, 1)
	cabinetRoot.Anchored = true
	cabinetRoot.CanCollide = false
	cabinetRoot.Transparency = 1
	cabinetRoot.CFrame = CFrame.new(ORIGIN)
	cabinetRoot.Parent = cabinetFolder

	local interior = Instance.new("Model")
	interior.Name = "Interior"
	interior.Parent = cabinetFolder

	local playfield = Instance.new("Model")
	playfield.Name = "Playfield"
	playfield.Parent = interior

	local mechanisms = Instance.new("Model")
	mechanisms.Name = "Mechanisms"
	mechanisms.Parent = interior

	local interiorLights = Instance.new("Folder")
	interiorLights.Name = "InteriorLights"
	interiorLights.Parent = interior

	local cameraRig = Instance.new("Model")
	cameraRig.Name = "CameraRig"
	cameraRig.Parent = cabinetFolder

	local interactionPoints = Instance.new("Folder")
	interactionPoints.Name = "InteractionPoints"
	interactionPoints.Parent = cabinetFolder

	local runtime = Instance.new("Folder")
	runtime.Name = "Runtime"
	runtime.Parent = cabinetFolder

	local playfieldGroup = CABINET_NAME .. "Playfield"
	pcall(function()
		game:GetService("PhysicsService"):RegisterCollisionGroup(playfieldGroup)
	end)

	buildFloorAndWalls(playfield, playfieldGroup)
	buildDrainTrigger(mechanisms)
	buildLaunchAnchorAndMainFieldEntry(mechanisms)
	buildFlippers(mechanisms)

	CabinetBuilder.addBumper(mechanisms, RAMP_CFRAME, -6, 24, Color3.fromRGB(220, 60, 60), playfieldGroup)
	CabinetBuilder.addBumper(mechanisms, RAMP_CFRAME, 6, 30, Color3.fromRGB(60, 120, 220), playfieldGroup)

	buildInteractAnchor(interactionPoints)
	buildCameraAnchor(cameraRig)

	print(CABINET_NAME .. ": built at " .. tostring(ORIGIN) .. " -- run CabinetGameplay.setup on it from Cabinet01.server.luau, then Play to test")

	return cabinetFolder
end

return Cabinet01Builder
