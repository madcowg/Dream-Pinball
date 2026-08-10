--!strict

-- WilliamsCabinet's own measured numbers + marker names, fed into the
-- generic CabinetUpgrade engine (Migrations/CabinetUpgrade.luau). A future
-- cabinet gets its own sibling spec file instead of a bespoke migration
-- script -- CabinetUpgrade.luau itself should never need to change per
-- cabinet.

local PinballKit = script.Parent.Parent
local Presets = require(PinballKit.Presets)
local CabinetUpgrade = require(script.Parent.CabinetUpgrade)

local STUDS_PER_INCH = 1.5 / 1.0625

-- WilliamsCabinet's real flipper is ~0.563x WilliamsClassic's default
-- reference size (4.221 studs measured / 7.5 studs preset default) -- this
-- whole cabinet is hand-built at a noticeably smaller scale than the preset
-- assumes, so the bumper defaults below are scaled by the same ratio. This is
-- an ESTIMATE (the same ratio the measured flipper gave, not a second
-- measurement) -- check it in Studio and adjust BUMPER_SCALE if it's still
-- off.
local FLIPPER_LENGTH_STUDS = 3 * STUDS_PER_INCH
local BUMPER_SCALE = FLIPPER_LENGTH_STUDS / 7.5

local WilliamsCabinetSpec: CabinetUpgrade.CabinetSpec = {
	LaunchAnchorName = "LaunchAnchor",
	SlingshotLeftName = "slingshotL",
	SlingshotRightName = "slingshotR",
	PlaysurfaceName = "playsurface",
	CenterlineMarkerName = "DrainTrigger",
	-- "cabinetwalls" per the Explorer -- may be a Model spanning both side
	-- walls; GenerateLaneDividers falls back to the plain estimate below if
	-- this isn't found or doesn't look right once you see it in Studio.
	OuterWallMarkerName = "cabinetwalls",

	FinalLeftFlipperName = "LeftFlipper",
	FinalRightFlipperName = "RightFlipper",
	FinalBumperName = "Bumper",

	NewLeftFlipperName = "LeftFlipper_New",
	NewRightFlipperName = "RightFlipper_New",
	NewBumperPrefix = "Bumper_New_",
	NewLaneDividerPrefix = "LaneDivider_",

	FlipperCollisionGroup = "WilliamsCabinetFlippers",
	PlayfieldCollisionGroup = "WilliamsCabinetPlayfield",

	-- Measured directly in Studio (not an estimate).
	FlipperSize = Vector3.new(FLIPPER_LENGTH_STUDS, 0.788, 1.126),
	-- +30, not -30: a live diagnostic (comparing the generated Flipper part's
	-- actual RightVector against LaunchAnchor/slingshot data) showed -30 put
	-- the rest tip pointing up-table (toward the main field) instead of
	-- down-table (toward the drain, converging near the bottom gap, per the
	-- reference photo) -- backwards for this cabinet's coordinate handedness.
	FlipperRestAngleDegrees = 30,
	FlipperUpAngleDegrees = 50,
	-- Measured directly in Studio: 1.375in gap between paddle tips at rest.
	-- Combined with FlipperSize.X/FlipperRestAngleDegrees above, this derives
	-- a shaft-to-shaft distance of ~9.28 studs -- notably NOT the ~15.9 studs
	-- the two slingshots currently sit apart. The slingshots are expected to
	-- move inward to match this layout (see CabinetUpgrade.luau's header);
	-- this spec does not do that yet.
	FlipperRestTipGapStuds = 1.375 * STUDS_PER_INCH,
	-- "6 studs up from the edge of DrainTrigger" -- measured directly. Still
	-- used as a fallback: the analytic derivation from these numbers has
	-- produced a wrong result (position and/or rest angle) multiple times in
	-- a row on this specific cabinet despite each individual number being a
	-- real measurement -- something about how they combine keeps coming out
	-- wrong, and guessing a fifth correction isn't productive. Place
	-- LeftFlipperPivotMarker/LeftFlipperTipMarker/RightFlipperPivotMarker/
	-- RightFlipperTipMarker (see below) by eye against the reference photo
	-- instead, and re-run GenerateNewFlippers -- it'll use those directly and
	-- skip this whole derivation.
	FlipperUpTableOffsetFromCenterlineEdgeStuds = 6,

	-- Position-only override -- see CabinetUpgrade.CabinetSpec's doc comment.
	-- Not placed yet (these names don't exist under WilliamsCabinet), so
	-- GenerateNewFlippers currently still falls back to the analytic
	-- derivation above. Once you place these four (small Parts, position
	-- only -- no rotation needed), GenerateNewFlippers switches to using them
	-- automatically, no code change needed.
	LeftFlipperPivotMarkerName = "LeftFlipperPivotMarker",
	LeftFlipperTipMarkerName = "LeftFlipperTipMarker",
	RightFlipperPivotMarkerName = "RightFlipperPivotMarker",
	RightFlipperTipMarkerName = "RightFlipperTipMarker",

	BumperScale = BUMPER_SCALE,

	-- Lane dividers: WilliamsCabinet has none today (nothing to replace).
	-- LaneDividerLateralOffset is a fallback ESTIMATE, only used if
	-- OuterWallMarkerName above isn't found -- otherwise the wall's own
	-- extent decides the distance. Length/start ARE estimates too (measured
	-- roughly off live marker positions: DrainTrigger to slingshotR is
	-- ~13.9 studs up-table, so a 2-stud start + 14-stud length reaches a
	-- little past the slingshot -- covering the whole in-lane/out-lane run,
	-- not a short section) -- re-check against Studio once the flipper
	-- position itself is confirmed, since this still starts relative to
	-- DrainTrigger, not the flippers.
	LaneDividerLength = 14,
	LaneDividerLateralOffset = FLIPPER_LENGTH_STUDS * 0.6,
	LaneDividerStartOffsetFromCenterlineEdgeStuds = 2,
	-- Matches WilliamsClassic.Slingshot.Height (2 studs) -- a lane guide next
	-- to the slingshot should read as the same height as the slingshot, not
	-- LaneGenerator's shorter ball-diameter-based default.
	LaneDividerHeight = 2,

	FlipperBasePreset = Presets.WilliamsClassic.Flipper,
	BumperBasePreset = Presets.WilliamsClassic.PopBumper,
	LaneDividerBasePreset = Presets.WilliamsClassic.LaneDivider,
}

return WilliamsCabinetSpec
