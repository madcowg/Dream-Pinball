--!strict

--- Shared cabinet construction, factored out so we can build multiple
--- side-by-side test cabinets (different tuning per design) without
--- duplicating the flipper/hinge logic that took this project many rounds
--- of debugging to get right the first time.
---
--- Lessons folded in from researching how other Roblox pinball projects
--- handle this (most notably a 2021-2022 devforum devlog for a multi-table
--- pinball hub, which documents almost the exact same failure modes we hit):
---  - Hinge rotation axis must be set explicitly via Attachment.Axis (and a
---    matching SecondaryAxis on both attachments) -- relying on default
---    attachment orientation is what caused our "tilts instead of sweeps"
---    bug originally.
---  - Motor-driven hinges can overshoot their LowerAngle/UpperAngle limits
---    under high torque/velocity between physics steps -- keep torque and
---    angular velocity modest rather than maximal, and treat the limits as
---    approximate, not exact.
---  - Fast/small balls can tunnel through thin flippers -- keep flipper
---    thickness (Y) and length reasonable relative to ball size and speed,
---    don't make either extreme.
---  - Flippers must not collide with the playfield floor/walls (their
---    swept volume overlaps it by design at rest height) -- both still
---    collide with the ball via the Default collision group.
---  - Flippers are built from the SAME tilted ramp frame as the floor, so
---    their hinge axis is the ramp's own normal (not world-up) and they lie
---    flush/parallel to the tilted playing surface instead of sweeping on a
---    flat horizontal plane that happens to intersect it.
local PhysicsService = game:GetService("PhysicsService")

export type Side = "Left" | "Right"

export type CabinetConfig = {
	Name: string,
	Origin: Vector3,
	TableWidth: number,
	TableLength: number,
	TiltDegrees: number,
	FlipperSize: Vector3,
	FlipperPivotOffsetX: number,
	FlipperRestAngleDegrees: number,
	FlipperUpAngleDegrees: number,
	FlipperMotorSpeed: number,
	FlipperMotorTorque: number,
}

export type CabinetResult = {
	Folder: Folder,
	Hinges: { [Side]: HingeConstraint },
	RampCFrame: { [Side]: CFrame },
	Ramp: CFrame,
	PlayfieldGroup: string,
	PlungerLaneX: number,
	PlungerLaneBottomZ: number,
	FrontEdgeWorldPosition: Vector3,
	InteractAnchorPosition: Vector3,
	CameraCFrame: CFrame,
}

local CabinetBuilder = {}

local FLOOR_THICKNESS = 1
local WALL_HEIGHT = 4
-- Thicker than a hairline wall so fast/bouncy balls can't tunnel through at
-- speed, and so butt-jointed wall segments (e.g. RightWall meeting BackWall)
-- overlap by a real margin instead of touching at a zero-volume seam.
local WALL_THICKNESS = 1.5
local FLIPPER_SURFACE_GAP = 0.5 -- small clearance between flipper and floor

-- Standard plunger lane (see PINBALL_GAME_HANDOFF.md reference image): a
-- separate narrow channel along the right edge, walled off from the main
-- playfield except for a gap near the top where it merges in. The ball
-- starts here and gets launched up the lane, not spawned mid-air over the
-- main playfield.
-- 5.5 (not 4) so the lane keeps a real ~1.25-stud clearance on each side of
-- a 1.5-diameter ball after WALL_THICKNESS's corridor-narrowing effect --
-- a too-tight lane turns a bouncy ball into a pinball-in-a-tube that zigzags
-- wall-to-wall and never makes forward progress out of the lane.
local PLUNGER_LANE_WIDTH = 5.5
local PLUNGER_LANE_OPENING_LENGTH = 8 -- length of the gap in the divider wall, near the high end
local PLUNGER_LANE_BOTTOM_MARGIN = 4 -- how far up from the drain edge the ball rests before launching

local MOTOR_DIRECTION: { [Side]: number } = { Left = 1, Right = -1 }

--- Which way pressing Q/E sweeps each flipper, independent of
--- MOTOR_DIRECTION (which only orients the rest-angle rotation). Kept as a
--- separate table since flipping one must not flip the other.
local SWEEP_DIRECTION: { [Side]: number } = { Left = -1, Right = 1 }

local function ensureCollisionGroups(flipperGroup: string, playfieldGroup: string)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(flipperGroup)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(playfieldGroup)
	end)
	PhysicsService:CollisionGroupSetCollidable(flipperGroup, playfieldGroup, false)
end
-- Exposed publicly for CabinetGameplay.luau's hand-built cabinets, which
-- need the same flipper/playfield collision-group separation (see
-- architecture.md "Flipper baseline") but don't go through CabinetBuilder.build.
CabinetBuilder.ensureCollisionGroups = ensureCollisionGroups

local function collisionGroupNames(cabinetName: string): (string, string)
	return cabinetName .. "Flippers", cabinetName .. "Playfield"
end

--- The tilted playing-surface frame, shared by the floor and the flippers so
--- both agree on what "flush with the table" means. Local +Z runs from the
--- open/drain edge (0) up to the far/high end (TableLength); local +Y is the
--- ramp's own normal, not world-up.
local function computeRampCFrame(config: CabinetConfig): CFrame
	local rampOrigin = config.Origin + Vector3.new(0, -1, 0)
	return CFrame.new(rampOrigin) * CFrame.Angles(0, math.rad(180), 0) * CFrame.Angles(math.rad(-config.TiltDegrees), 0, 0)
end

local function buildFlipper(
	config: CabinetConfig,
	side: Side,
	rampCFrame: CFrame,
	pivotOffsetX: number,
	parent: Folder,
	flipperGroup: string
): (HingeConstraint, CFrame)
	local flipperOffsetX = if side == "Left" then config.FlipperSize.X / 2 else -config.FlipperSize.X / 2
	local direction = MOTOR_DIRECTION[side]

	-- Pull the pivot back (toward the open/drain edge, local -Z) by the
	-- amount the rest-angle rotation pushes the tip forward, so the tip
	-- lands near local Z=0 (close to the drain) at any rest angle, instead
	-- of drifting up-ramp toward the bumpers as the angle increases.
	local tipReachZ = config.FlipperSize.X * math.sin(math.rad(config.FlipperRestAngleDegrees))
	local pivotLocalCFrame = CFrame.new(pivotOffsetX, FLOOR_THICKNESS / 2 + FLIPPER_SURFACE_GAP, -tipReachZ)

	-- Ramp-aligned (tilt baked in, no yaw yet) -- local +Y here is already
	-- the ramp's normal, so the hinge Axis below needs no special-casing.
	local pivotBaseCFrame = rampCFrame * pivotLocalCFrame
	local restCFrame = pivotBaseCFrame * CFrame.Angles(0, math.rad(-direction * config.FlipperRestAngleDegrees), 0)

	local pivot = Instance.new("Part")
	pivot.Name = side .. "FlipperPivot"
	pivot.Size = Vector3.new(1, 1, 1)
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.CFrame = restCFrame
	pivot.Parent = parent

	-- Traditional flipper silhouette (per the reference diagram): a core
	-- spine (kept narrow, matching the tip width, so it stays hidden inside
	-- the wider segments below) with a stack of rounded, graduated-diameter
	-- segments welded on top -- full width at the pivot end tapering smoothly
	-- down to half width at the free tip. Roblox has no native tapered-
	-- cylinder/cone shape, so this approximates a smooth cone with enough
	-- discrete steps; flat (SmoothPlastic) finish throughout.
	--
	-- NOTE: a UnionAsync-based single-part merge was tried here to cut part
	-- count for faster loading, but it came out badly misoriented live
	-- (flippers appeared as tall vertical bars, not flat tapered rods) and
	-- was reverted. Re-attempt only with careful live re-verification, same
	-- as every other flipper-geometry change in this project's history (see
	-- architecture.md "Flipper baseline") -- do not reintroduce blind.
	local flipper = Instance.new("Part")
	flipper.Name = side .. "Flipper"
	flipper.Size = Vector3.new(config.FlipperSize.X, config.FlipperSize.Y, config.FlipperSize.Z)
	flipper.Material = Enum.Material.SmoothPlastic
	flipper.Anchored = false
	flipper.CanCollide = true
	flipper.Color = Color3.fromRGB(200, 60, 60)
	-- Invisible -- this box is full pivot-width along its ENTIRE length (not
	-- tapered), so if rendered it pokes out past the tapered cosmetic
	-- segments below near the tip, looking like a red slab flanking the
	-- flipper. The tapered segments are what the player actually sees; this
	-- box exists only to be the single, seam-free collision volume.
	flipper.Transparency = 1
	flipper.CFrame = restCFrame * CFrame.new(flipperOffsetX, 0, 0)
	-- Denser than a default part, elastic enough for a solid hit, and
	-- higher friction ("sticky") so the ball grips briefly instead of
	-- skidding straight off.
	flipper.CustomPhysicalProperties = PhysicalProperties.new(3, 0.75, 0.65, 1, 1)
	flipper.Parent = parent
	flipper.CollisionGroup = flipperGroup

	-- Cylinder axis (local X) must point along the flipper's own local Y
	-- (vertical, the ramp's normal) so the round face lies flat and flush
	-- with the flipper's top surface -- same rotation used for the disc
	-- bumpers.
	local capRotation = CFrame.Angles(0, 0, math.rad(90))
	-- High segment count with a small overlap between neighbors -- with only
	-- 5 segments the size jumps between them were visible as rings/ripples
	-- rather than a smooth cone. More, thinner, overlapping segments read as
	-- smooth at normal viewing distance; this is the standard workaround
	-- since Roblox has no native tapered-cylinder/cone shape.
	local SEGMENT_COUNT = 26
	local segmentThickness = config.FlipperSize.Y * 1.4 -- >1x on purpose, for overlap
	-- Segments are a cosmetic shell (the core `flipper` part already carries
	-- the ball-hitting collision volume) welded on for a smooth tapered look.
	-- Reusing the flipper's own density here made each flipper a 27-part-
	-- dense assembly once SEGMENT_COUNT went up for smoothness, ballooning
	-- rotational inertia around the hinge and making the same motor torque
	-- feel sluggish. Near-zero density keeps their collision shape (needed
	-- so the ball bounces off the visible tapered surface) without adding
	-- meaningful mass/inertia to the swing.
	local segmentPhysicalProperties = PhysicalProperties.new(0.01, 0.75, 0.65, 1, 1)

	for i = 0, SEGMENT_COUNT - 1 do
		local t = i / (SEGMENT_COUNT - 1) -- 0 at the hinge end, 1 at the tip
		local localX = -flipperOffsetX + t * (2 * flipperOffsetX)
		local diameter = config.FlipperSize.Z - t * (config.FlipperSize.Z / 2) -- full width -> half width

		local segment = Instance.new("Part")
		segment.Name = side .. "FlipperSegment" .. tostring(i)
		segment.Shape = Enum.PartType.Cylinder
		segment.Material = Enum.Material.SmoothPlastic
		segment.Size = Vector3.new(segmentThickness, diameter, diameter)
		segment.Anchored = false
		-- Purely cosmetic (per this function's doc comment) -- the core
		-- `flipper` box above is the sole collision volume. Previously left
		-- CanCollide = true, which made every flipper 27 separate, slightly
		-- overlapping collidable parts welded together; a ball could catch
		-- in the seams between segments and get wedged, pinned horizontally
		-- while sliding straight down under gravity until it happened to
		-- drop far enough to trigger the drain -- confirmed live via
		-- PhysicsTestRig: AssemblyLinearVelocity's X/Z components froze to
		-- an exact bit-for-bit constant across many frames while only Y
		-- kept falling, the signature of a part pinned in a collision seam.
		segment.CanCollide = false
		segment.CanQuery = false
		segment.Color = flipper.Color
		segment.CustomPhysicalProperties = segmentPhysicalProperties
		segment.CFrame = flipper.CFrame * CFrame.new(localX, 0, 0) * capRotation
		segment.Parent = parent
		segment.CollisionGroup = flipperGroup

		local segmentWeld = Instance.new("WeldConstraint")
		segmentWeld.Part0 = flipper
		segmentWeld.Part1 = segment
		segmentWeld.Parent = flipper
	end

	local pivotAttachment = Instance.new("Attachment")
	pivotAttachment.Axis = Vector3.new(0, 1, 0)
	pivotAttachment.SecondaryAxis = Vector3.new(1, 0, 0)
	pivotAttachment.Parent = pivot

	local flipperAttachment = Instance.new("Attachment")
	flipperAttachment.Position = Vector3.new(-flipperOffsetX, 0, 0)
	flipperAttachment.Axis = Vector3.new(0, 1, 0)
	flipperAttachment.SecondaryAxis = Vector3.new(1, 0, 0)
	flipperAttachment.Parent = flipper

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = pivotAttachment
	hinge.Attachment1 = flipperAttachment
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.LimitsEnabled = true
	hinge.Restitution = 0 -- no bounce past the limit, reduces overshoot risk
	local sweepDirection = SWEEP_DIRECTION[side]
	hinge.LowerAngle = if sweepDirection == 1 then 0 else -config.FlipperUpAngleDegrees
	hinge.UpperAngle = if sweepDirection == 1 then config.FlipperUpAngleDegrees else 0
	hinge.MotorMaxTorque = config.FlipperMotorTorque
	hinge.AngularVelocity = 0
	hinge.Parent = pivot

	return hinge, restCFrame
end

local function buildTable(config: CabinetConfig, rampCFrame: CFrame, parent: Folder, playfieldGroup: string): (number, Vector3, Vector3)
	local floor = Instance.new("Part")
	floor.Name = "CabinetFloor"
	floor.Size = Vector3.new(config.TableWidth, FLOOR_THICKNESS, config.TableLength)
	floor.Anchored = true
	floor.CanCollide = true
	floor.Color = Color3.fromRGB(60, 90, 60)
	floor.CFrame = rampCFrame * CFrame.new(0, 0, config.TableLength / 2)
	-- Low friction so the ball rolls/slides like glass; elasticity is
	-- deliberately modest here (the ball's own CustomPhysicalProperties
	-- elasticityWeight dominates every bounce -- see CabinetDesignsTest's
	-- ball construction), this is just a sane non-default fallback.
	floor.CustomPhysicalProperties = PhysicalProperties.new(2, 0.2, 0.5, 1, 1)
	floor.Parent = parent
	floor.CollisionGroup = playfieldGroup

	local function buildWallSegment(name: string, xOffset: number, zCenter: number, zLength: number)
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, zLength)
		wall.Anchored = true
		wall.CanCollide = true
		wall.Transparency = 0.5
		wall.Color = Color3.fromRGB(90, 90, 90)
		wall.CFrame = rampCFrame * CFrame.new(xOffset, WALL_HEIGHT / 2, zCenter)
		-- Bouncy so the ball actually rebounds off the rail instead of
		-- absorbing into it (Roblox's default elasticity is too dead).
		wall.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
		wall.Parent = parent
		wall.CollisionGroup = playfieldGroup
	end

	-- Angled segments are stretched WALL_OVERLAP_MARGIN past each of their
	-- nominal endpoints (along their own length, not just their thickness).
	-- Two anchored parts meeting at an exact point-computed endpoint have
	-- zero real overlap -- Roblox's physics solver doesn't guarantee solid
	-- contact there, especially where a straight wall butts into an angled
	-- one. A fast ball can find that seam and either slip through it (read
	-- as "the funnel isn't working") or clip it unevenly and get an unstable
	-- velocity spike (read as the ball "disappearing"). Overlapping the
	-- geometry itself, rather than trying to compute exact touching
	-- endpoints, removes the seam regardless of the exact math.
	local WALL_OVERLAP_MARGIN = 1.5
	local function buildAngledWallSegment(name: string, x1: number, z1: number, x2: number, z2: number)
		local dx = x2 - x1
		local dz = z2 - z1
		local length = math.sqrt(dx * dx + dz * dz)
		local angle = math.atan2(dx, dz)
		local wall = Instance.new("Part")
		wall.Name = name
		wall.Size = Vector3.new(WALL_THICKNESS, WALL_HEIGHT, length + WALL_OVERLAP_MARGIN * 2)
		wall.Anchored = true
		wall.CanCollide = true
		wall.Transparency = 0.5
		wall.Color = Color3.fromRGB(90, 90, 90)
		wall.CFrame = rampCFrame * CFrame.new((x1 + x2) / 2, WALL_HEIGHT / 2, (z1 + z2) / 2) * CFrame.Angles(0, angle, 0)
		wall.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
		wall.Parent = parent
		wall.CollisionGroup = playfieldGroup
	end

	-- NOTE: local +X lands on screen-left and local -X on screen-right, due
	-- to the 180-degree yaw in computeRampCFrame (same reason the flipper
	-- Left/Right pivot assignment looks backwards -- see architecture.md
	-- "Flipper baseline"). The plunger lane belongs on screen-right, so it
	-- goes on the NEGATIVE local X side; "RightWall" (screen-left) is +X.
	--
	-- Bottom section (below FUNNEL_LENGTH) tapers inward toward the
	-- flippers instead of staying a uniform rectangle, per the reference
	-- diagram's funnel shape -- only on this (non-lane) side; the plunger
	-- lane side keeps a straight divider so the lane itself stays a
	-- consistent width.
	local FUNNEL_LENGTH = 14
	-- Must stay outside where the flipper pivots actually sit
	-- (config.FlipperPivotOffsetX), or the taper would cut into the
	-- flippers' own swept area at the bottom.
	local FUNNEL_BOTTOM_X = config.FlipperPivotOffsetX + 1
	-- Chamfer across the RightWall/BackWall corner (the top-right of the
	-- main field, screen-top-left per the note above). A bare 90-degree
	-- interior corner lets a fast/bouncy ball get hit by both walls nearly
	-- simultaneously, which can throw it off the board at extreme velocity
	-- instead of deflecting cleanly (read as the ball "disappearing").
	-- Every other interior corner on this table is already angled (funnel
	-- bottoms, plunger lane deflector) -- this was the one sharp corner left.
	-- RightWall itself is shortened to stop short of the corner (instead of
	-- reaching config.TableLength), so the chamfer actually replaces the
	-- sharp point rather than just adding an extra wall in front of it.
	local CHAMFER_SIZE = 3
	local rightWallTopZ = config.TableLength - CHAMFER_SIZE
	buildWallSegment("RightWall", config.TableWidth / 2, (rightWallTopZ + FUNNEL_LENGTH) / 2, rightWallTopZ - FUNNEL_LENGTH)
	buildAngledWallSegment("RightFunnelWall", config.TableWidth / 2, FUNNEL_LENGTH, FUNNEL_BOTTOM_X, 0)
	buildAngledWallSegment("TopRightChamfer", config.TableWidth / 2, rightWallTopZ, config.TableWidth / 2 - CHAMFER_SIZE, config.TableLength)

	-- Divider between the main playfield and the plunger lane: solid except
	-- for a gap near the high end (where the lane merges into the main
	-- field) and tapered near the bottom (matching RightFunnelWall above) --
	-- the plunger lane's own outer wall stays straight, so the lane widens
	-- slightly near the bottom rather than the taper affecting its width.
	local dividerLength = config.TableLength - PLUNGER_LANE_OPENING_LENGTH
	buildWallSegment(
		"PlayfieldDivider",
		-config.TableWidth / 2,
		(dividerLength + FUNNEL_LENGTH) / 2,
		dividerLength - FUNNEL_LENGTH
	)
	buildAngledWallSegment("LeftFunnelWall", -config.TableWidth / 2, FUNNEL_LENGTH, -FUNNEL_BOTTOM_X, 0)

	-- Plunger lane: a narrow channel outside the divider, same tilt/length.
	local plungerLaneX = -(config.TableWidth / 2 + PLUNGER_LANE_WIDTH / 2)
	local plungerFloor = Instance.new("Part")
	plungerFloor.Name = "PlungerLaneFloor"
	plungerFloor.Size = Vector3.new(PLUNGER_LANE_WIDTH, FLOOR_THICKNESS, config.TableLength)
	plungerFloor.Anchored = true
	plungerFloor.CanCollide = true
	plungerFloor.Color = Color3.fromRGB(60, 90, 60)
	plungerFloor.CFrame = rampCFrame * CFrame.new(plungerLaneX, 0, config.TableLength / 2)
	plungerFloor.Parent = parent
	plungerFloor.CollisionGroup = playfieldGroup

	buildWallSegment("PlungerLaneOuterWall", -(config.TableWidth / 2 + PLUNGER_LANE_WIDTH), config.TableLength / 2, config.TableLength)

	-- Deflector at the gap in the divider, guiding the ball from the lane
	-- (moving up, +Z, hugging the outer/right wall) into the main field.
	-- Endpoint A sits on PlungerLaneOuterWall (the lane's right side) right
	-- where the gap starts (z=dividerLength) -- this is where the ball
	-- actually is when it enters the gap. Endpoint B sits on BackWall (the
	-- top) at the inner/field side. The diagonal must run bottom-right to
	-- top-left, NOT the reverse: a bottom-left-to-top-right diagonal leaves
	-- the gap wide open near the outer wall (where the ball travels) and
	-- only closes near the back-right corner, pinning the ball there
	-- instead of deflecting it into the field (previous bug).
	buildAngledWallSegment(
		"PlungerLaneDeflector",
		-(config.TableWidth / 2 + PLUNGER_LANE_WIDTH),
		dividerLength,
		-config.TableWidth / 2,
		config.TableLength
	)

	-- Back wall spans both the main floor and the plunger lane.
	local totalWidth = config.TableWidth + PLUNGER_LANE_WIDTH
	local backWallCenterX = -PLUNGER_LANE_WIDTH / 2
	local backWall = Instance.new("Part")
	backWall.Name = "BackWall"
	backWall.Size = Vector3.new(totalWidth, WALL_HEIGHT, WALL_THICKNESS)
	backWall.Anchored = true
	backWall.CanCollide = true
	backWall.Color = Color3.fromRGB(90, 90, 90)
	backWall.CFrame = rampCFrame * CFrame.new(backWallCenterX, WALL_HEIGHT / 2, config.TableLength)
	backWall.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
	backWall.Parent = parent
	backWall.CollisionGroup = playfieldGroup

	-- Cosmetic cabinet body panel closing off the visual gap underneath the
	-- low/front edge, like a real arcade cabinet's enclosure. Upright (not
	-- tilted with the playfield), non-colliding so it doesn't block the
	-- drain trigger below.
	local CABINET_BODY_HEIGHT = 15
	local frontEdgeWorldPosition = (rampCFrame * CFrame.new(backWallCenterX, 0, 0)).Position
	local bodyPanel = Instance.new("Part")
	bodyPanel.Name = "CabinetBodyPanel"
	bodyPanel.Size = Vector3.new(totalWidth, CABINET_BODY_HEIGHT, 2)
	bodyPanel.Anchored = true
	bodyPanel.CanCollide = false
	bodyPanel.Color = Color3.fromRGB(40, 40, 60)
	bodyPanel.CFrame = CFrame.new(frontEdgeWorldPosition - Vector3.new(0, CABINET_BODY_HEIGHT / 2, 0))
	bodyPanel.Parent = parent

	-- Standing-height anchor for this cabinet's interact button (see
	-- CabinetDesignsTest's ProximityPrompt setup). frontEdgeWorldPosition
	-- itself sits at the playing surface's height (~9 studs up on a typical
	-- board, well above where a player's capsule can reach). The bottom edge
	-- of the cosmetic body panel above IS the actual ground level this
	-- cabinet stands on (bodyPanel's center minus half its height), so this
	-- anchor sits a fixed human-reachable distance above THAT instead.
	local INTERACT_ANCHOR_HEIGHT_ABOVE_GROUND = 4
	local groundWorldY = frontEdgeWorldPosition.Y - CABINET_BODY_HEIGHT
	local interactAnchor = Instance.new("Part")
	interactAnchor.Name = "InteractAnchor"
	interactAnchor.Size = Vector3.new(1, 1, 1)
	interactAnchor.Anchored = true
	interactAnchor.CanCollide = false
	interactAnchor.Transparency = 1
	interactAnchor.CFrame = CFrame.new(frontEdgeWorldPosition.X, groundWorldY + INTERACT_ANCHOR_HEIGHT_ABOVE_GROUND, frontEdgeWorldPosition.Z)
	interactAnchor.Parent = parent

	-- Stopper across just the plunger lane's bottom -- the main floor's
	-- bottom (the drain) must stay open, but the lane itself needs a solid
	-- floor at its low end so the ball can't roll/fall out of it before or
	-- after a weak launch.
	local plungerStopper = Instance.new("Part")
	plungerStopper.Name = "PlungerLaneStopper"
	plungerStopper.Size = Vector3.new(PLUNGER_LANE_WIDTH, WALL_HEIGHT, WALL_THICKNESS)
	plungerStopper.Anchored = true
	plungerStopper.CanCollide = true
	plungerStopper.Color = Color3.fromRGB(90, 90, 90)
	plungerStopper.CFrame = rampCFrame * CFrame.new(plungerLaneX, WALL_HEIGHT / 2, 0)
	plungerStopper.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
	plungerStopper.Parent = parent
	plungerStopper.CollisionGroup = playfieldGroup

	return plungerLaneX, frontEdgeWorldPosition, interactAnchor.Position
end

function CabinetBuilder.build(config: CabinetConfig, workspaceParent: Instance): CabinetResult
	local flipperGroup, playfieldGroup = collisionGroupNames(config.Name)
	ensureCollisionGroups(flipperGroup, playfieldGroup)

	local folder = Instance.new("Folder")
	folder.Name = config.Name
	folder.Parent = workspaceParent

	local rampCFrame = computeRampCFrame(config)
	local plungerLaneX, frontEdgeWorldPosition, interactAnchorPosition = buildTable(config, rampCFrame, folder, playfieldGroup)

	local hinges: { [Side]: HingeConstraint } = {}
	local restCFrames: { [Side]: CFrame } = {}

	hinges.Left, restCFrames.Left = buildFlipper(config, "Left", rampCFrame, -config.FlipperPivotOffsetX, folder, flipperGroup)
	hinges.Right, restCFrames.Right = buildFlipper(config, "Right", rampCFrame, config.FlipperPivotOffsetX, folder, flipperGroup)

	-- Fixed in-level camera framing, scaled off TableLength so every board
	-- gets a sane full-table view regardless of its size, instead of one
	-- hand-tuned position per design. Ratios below match the hand-tuned
	-- framing that was confirmed working live for Design A (TableLength 52:
	-- camera at Origin + (0, 17, 21), looking at Origin + (0, 1, -17)) --
	-- see CabinetDesignsCamera's prior CAMERA_POSITION/LOOK_AT_POSITION.
	local CAMERA_HEIGHT_RATIO = 17 / 52
	local CAMERA_BACK_RATIO = 21 / 52
	local LOOK_AT_HEIGHT = 1
	local LOOK_AT_FORWARD_RATIO = 17 / 52
	-- Confirmed live adjustment on top of the base framing above: raised 2
	-- studs and pitched 5 degrees further down (rotated about the resulting
	-- frame's own local X/right axis, applied after lookAt so the look-at
	-- target/position math above doesn't need to change).
	local CAMERA_EXTRA_HEIGHT = 2
	local CAMERA_EXTRA_TILT_DOWN_DEGREES = 5
	local cameraPosition = config.Origin
		+ Vector3.new(0, CAMERA_HEIGHT_RATIO * config.TableLength + CAMERA_EXTRA_HEIGHT, CAMERA_BACK_RATIO * config.TableLength)
	local lookAtPosition = config.Origin + Vector3.new(0, LOOK_AT_HEIGHT, -LOOK_AT_FORWARD_RATIO * config.TableLength)

	return {
		Folder = folder,
		Hinges = hinges,
		PlungerLaneX = plungerLaneX,
		PlungerLaneBottomZ = PLUNGER_LANE_BOTTOM_MARGIN,
		RampCFrame = restCFrames,
		Ramp = rampCFrame,
		PlayfieldGroup = playfieldGroup,
		FrontEdgeWorldPosition = frontEdgeWorldPosition,
		InteractAnchorPosition = interactAnchorPosition,
		-- Extra downward tilt applied about the look-at frame's own local X
		-- (right) axis, after the aim point is established -- rotates the
		-- view further down without changing where the camera is looking
		-- FROM. Sign not yet re-verified live (see architecture.md's
		-- "Flipper baseline" note on camera/orientation math being
		-- unreliable to reason about) -- if this tilts UP instead of down,
		-- flip CAMERA_EXTRA_TILT_DOWN_DEGREES to negative.
		CameraCFrame = CFrame.lookAt(cameraPosition, lookAtPosition) * CFrame.Angles(math.rad(CAMERA_EXTRA_TILT_DOWN_DEGREES), 0, 0),
	}
end

--- A world CFrame for a point on the tilted playing surface, given local
--- coordinates within the ramp (localZ=0 is the open/drain edge, localX=0 is
--- the centerline, heightAboveSurface is how far above the floor top to
--- place something). Use this for bumpers/slingshots/decorations instead of
--- hardcoded world Y values -- the floor's actual world height increases
--- with localZ because it's tilted, so a fixed Y will end up embedded in or
--- floating above the floor depending on how far up-ramp it is.
function CabinetBuilder.pointOnRamp(ramp: CFrame, localX: number, localZ: number, heightAboveSurface: number): CFrame
	return ramp * CFrame.new(localX, FLOOR_THICKNESS / 2 + heightAboveSurface, localZ)
end

-- pointOnRamp's heightAboveSurface places the shape's CENTER that far above
-- the floor -- it does NOT know how tall the shape becomes after rotation,
-- so a flat "1 stud" guess left this disc's bottom edge floating well above
-- the real floor (half its rotated height, 0.3, minus the embed margin
-- below). That gap was exactly wide enough for the ball to wedge its nose
-- underneath and get stuck -- the root cause of a "ball gets stuck on
-- bumpers" bug found during Design B playtesting. BUMPER_EMBED_MARGIN pushes
-- the bottom slightly below the floor surface instead of exactly flush, so
-- small numerical/physics-solver slop can't reopen the gap.
local BUMPER_THICKNESS = 0.6
local BUMPER_EMBED_MARGIN = 0.05
local BUMPER_HEIGHT_ABOVE_SURFACE = BUMPER_THICKNESS / 2 - BUMPER_EMBED_MARGIN

--- Disc-shaped scoring bumper, flush with the tilted floor at (localX,
--- localZ). Caller is responsible for connecting a Touched handler and
--- managing scoring -- this only builds and places the physical part.
function CabinetBuilder.addBumper(parent: Instance, ramp: CFrame, localX: number, localZ: number, color: Color3, playfieldGroup: string): BasePart
	local bumper = Instance.new("Part")
	bumper.Name = "Bumper"
	bumper.Shape = Enum.PartType.Cylinder
	bumper.Size = Vector3.new(BUMPER_THICKNESS, 2.5, 2.5) -- X is the cylinder's axis/thickness, Y/Z its diameter
	bumper.Anchored = true
	bumper.CanCollide = true
	bumper.Color = color
	bumper.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
	-- Rotate so the cylinder's axis points along the ramp's normal (flat
	-- disc lying on the tilted surface), not lying on its side.
	bumper.CFrame = CabinetBuilder.pointOnRamp(ramp, localX, localZ, BUMPER_HEIGHT_ABOVE_SURFACE) * CFrame.Angles(0, 0, math.rad(90))
	bumper.Parent = parent
	bumper.CollisionGroup = playfieldGroup
	return bumper
end

-- Triangular wedge kicker (matches the reference image's slingshot shape,
-- Downloads/Typical_pinball_machine.png), instead of a plain rectangle.
-- mirrorX flips it for the opposite side, so a pair angles toward each
-- other like the reference.
local SLINGSHOT_SIZE = Vector3.new(2, 2, 3)
-- A clean 90-degree rotation about local X swaps the bounding box's Y and Z
-- extents, so the wedge's actual vertical half-height after rotation is
-- half of its ORIGINAL Z size, not Y -- same class of bug as the bumper's
-- floating-gap fix above. Embedded slightly (not just flush) for the same
-- reason: safer to bury a hair too deep than leave any gap the ball can
-- wedge under.
local SLINGSHOT_EMBED_MARGIN = 0.05
local SLINGSHOT_HEIGHT_ABOVE_SURFACE = SLINGSHOT_SIZE.Z / 2 - SLINGSHOT_EMBED_MARGIN

--- Wedge-shaped guide, flush with the tilted floor at (localX, localZ).
function CabinetBuilder.addSlingshot(parent: Instance, ramp: CFrame, localX: number, localZ: number, mirrorX: boolean, playfieldGroup: string): BasePart
	local slingshot = Instance.new("WedgePart")
	slingshot.Name = "Slingshot"
	slingshot.Size = SLINGSHOT_SIZE
	slingshot.Anchored = true
	slingshot.CanCollide = true
	slingshot.Color = Color3.fromRGB(120, 160, 220)
	slingshot.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.65, 1, 1)
	local mirror = if mirrorX then -1 else 1
	slingshot.CFrame = CabinetBuilder.pointOnRamp(ramp, localX, localZ, SLINGSHOT_HEIGHT_ABOVE_SURFACE) * CFrame.Angles(math.rad(90) * mirror, 0, 0)
	slingshot.Parent = parent
	slingshot.CollisionGroup = playfieldGroup
	return slingshot
end

-- Actuate (pressed) and return (released) speeds, tuned from playtesting --
-- deliberately not symmetric like a real hinge motor would naturally be.
local ACTUATE_SPEED_MULTIPLIER = 4.5
local RETURN_SPEED_MULTIPLIER = 5.5

function CabinetBuilder.setFlipperInput(hinges: { [Side]: HingeConstraint }, side: Side, pressed: boolean, speed: number)
	local hinge = hinges[side]
	if not hinge then
		return
	end
	local magnitude = if pressed then speed * ACTUATE_SPEED_MULTIPLIER else -speed * RETURN_SPEED_MULTIPLIER
	hinge.AngularVelocity = magnitude * SWEEP_DIRECTION[side]
end

--- Builds a working hinge for a HAND-BUILT flipper (e.g. WilliamsCabinet)
--- that already has the correct shape and a pivot Attachment placed at the
--- correct point, but no HingeConstraint yet. Unlike buildFlipper (which
--- computes the flipper's rest position/orientation from ramp tilt math),
--- this takes the flipper EXACTLY as the team already built it -- its
--- current CFrame at call time becomes the rest pose, and pivotAttachment's
--- current position (a child of flipper, so already flipper-LOCAL) becomes
--- the hinge point. No tilt/ramp math involved, so it works regardless of
--- how the surrounding table was built.
---
--- pivotAttachment must be a child of flipper itself -- typically the single
--- Attachment Studio's pivot tool creates when you set a custom pivot point
--- on the flipper Part. Its Axis/SecondaryAxis are overwritten here to
--- (0,1,0)/(1,0,0) (flipper-local), matching buildFlipper's own convention
--- -- since the new pivot Part built below shares the flipper's exact
--- current rotation, that pair of local defaults correctly means "hinge
--- axis = flipper's own up" / "secondary = flipper's own right" on BOTH
--- sides of the hinge, with no world-space math needed.
---
--- upAngleDegrees lets the caller reuse the same locked baseline angle as
--- the code-built cabinets (see GameplayTuning.luau). torquePerMass is a
--- RATIO (torque per stud of AssemblyMass), not an absolute torque -- unlike
--- buildFlipper's code-built flippers (always built to one known reference
--- mass, so an absolute torque constant is safe there), a hand-built
--- flipper's real mass varies with its actual geometry/density and is
--- measured live right here via flipper.AssemblyMass, so the SAME swing
--- feel (torque relative to mass) is achieved regardless of how heavy or
--- light the team's model turned out to be. Passing an absolute torque
--- number here instead was the original bug: a hand-built flipper 4.5x
--- lighter than the reference still got the reference's full torque value,
--- producing a badly wrong torque-to-mass ratio and the jittery/
--- inconsistent flipper behavior reported during WilliamsCabinet
--- playtesting (scoring bounces on only 2 of 5 launches, AssemblyAngularVelocity
--- reading ~0 at nearly every sampled moment). See GameplayTuning.luau's
--- FLIPPER_MOTOR_TORQUE_PER_MASS for the calibrated ratio.
function CabinetBuilder.attachFlipperHinge(
	flipper: BasePart,
	pivotAttachment: Attachment,
	side: Side,
	upAngleDegrees: number,
	torquePerMass: number,
	flipperGroup: string
): HingeConstraint
	-- Pivot part's world CFrame = flipper's current rotation, translated to
	-- the pivot attachment's local offset -- same composition buildFlipper
	-- uses (rampCFrame * pivotLocalCFrame), just built from the flipper's
	-- own existing CFrame instead of ramp tilt math.
	local pivot = Instance.new("Part")
	pivot.Name = side .. "FlipperPivot"
	pivot.Size = Vector3.new(1, 1, 1)
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.CFrame = flipper.CFrame * CFrame.new(pivotAttachment.Position)
	pivot.Parent = flipper.Parent

	local pivotSideAttachment = Instance.new("Attachment")
	pivotSideAttachment.Axis = Vector3.new(0, 1, 0)
	pivotSideAttachment.SecondaryAxis = Vector3.new(1, 0, 0)
	pivotSideAttachment.Parent = pivot

	pivotAttachment.Axis = Vector3.new(0, 1, 0)
	pivotAttachment.SecondaryAxis = Vector3.new(1, 0, 0)

	flipper.Anchored = false
	flipper.CanCollide = true
	flipper.CollisionGroup = flipperGroup

	-- AssemblyMass is only meaningful once the flipper is unanchored (an
	-- anchored part isn't a real physics assembly) -- read AFTER the
	-- flipper.Anchored = false above, not before.
	local motorTorque = torquePerMass * flipper.AssemblyMass

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = pivotSideAttachment
	hinge.Attachment1 = pivotAttachment
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.LimitsEnabled = true
	hinge.Restitution = 0
	local sweepDirection = SWEEP_DIRECTION[side]
	hinge.LowerAngle = if sweepDirection == 1 then 0 else -upAngleDegrees
	hinge.UpperAngle = if sweepDirection == 1 then upAngleDegrees else 0
	hinge.MotorMaxTorque = motorTorque
	hinge.AngularVelocity = 0
	hinge.Parent = pivot

	return hinge
end

return CabinetBuilder
