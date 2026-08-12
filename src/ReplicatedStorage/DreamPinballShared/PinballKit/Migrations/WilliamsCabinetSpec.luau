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
	CenterlineMarkerName = "DrainTrigger",
	-- "cabinetwalls" per the Explorer -- may be a Model spanning both side
	-- walls; GenerateLaneDividers falls back to the plain estimate below if
	-- this isn't found or doesn't look right once you see it in Studio.
	OuterWallMarkerName = "cabinetwalls",
	-- "CabinetFloor" per the Explorer -- the real structural floor, used to
	-- force every flipper flat and at the correct ball-center height
	-- regardless of how precisely markers were placed vertically.
	FloorMarkerName = "CabinetFloor",

	FinalLeftFlipperName = "LeftFlipper",
	FinalRightFlipperName = "RightFlipper",
	FinalBumperName = "Bumper",

	NewLeftFlipperName = "LeftFlipper_New",
	NewRightFlipperName = "RightFlipper_New",
	NewBumperPrefix = "Bumper_New_",
	NewLaneDividerPrefix = "LaneDivider_",
	PlungerName = "LaunchPlunger",

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
	-- Kept for reference/sanity-check even though FlipperShaftToShaftStuds
	-- below (a cited real measurement) now takes priority over deriving
	-- shaft-to-shaft from this.
	FlipperRestTipGapStuds = 1.375 * STUDS_PER_INCH,
	-- REFERENCED (not derived): WPC/Williams-standard flipper shaft-to-shaft
	-- is 6-13/16in to 7in (pinballmakers.com's Design wiki, explicitly citing
	-- "most WPC games") -- 7in matches the ~9.9 studs originally given for
	-- this cabinet almost exactly. The Gap/Length/RestAngle-derived value
	-- (~9.28 studs) came out smaller and produced flippers that visually
	-- crossed on WilliamsCabinet -- this override replaces that derivation.
	FlipperShaftToShaftStuds = 7 * STUDS_PER_INCH,
	-- "6 studs up from the edge of DrainTrigger" -- measured directly. Still
	-- used as a fallback: the analytic derivation from these numbers has
	-- produced a wrong result (position and/or rest angle) multiple times in
	-- a row on this specific cabinet despite each individual number being a
	-- real measurement -- something about how they combine keeps coming out
	-- wrong, and guessing a fifth correction isn't productive. Place
	-- LeftFlipperPivotMarker/LeftFlipperTipMarker (see below) by eye against
	-- the reference photo instead, and re-run GenerateNewFlippers -- it'll
	-- use those directly (mirroring to get the right side) and skip this
	-- whole derivation.
	FlipperUpTableOffsetFromCenterlineEdgeStuds = 6,

	-- Position-only override -- see CabinetUpgrade.CabinetSpec's doc comment.
	-- Only the LEFT pair is used; the right flipper is mirrored from it
	-- across the centerline (guaranteed symmetric), not read from a second
	-- hand-placed pair -- two independently-placed pairs came out visibly
	-- asymmetric on this cabinet. Delete RightFlipperPivotMarker/
	-- RightFlipperTipMarker if you placed them earlier; they're unused now.
	LeftFlipperPivotMarkerName = "LeftFlipperPivotMarker",
	LeftFlipperTipMarkerName = "LeftFlipperTipMarker",

	BumperScale = BUMPER_SCALE,

	-- Lane dividers: WilliamsCabinet has none today (nothing to replace). The
	-- rail's lateral position is derived entirely from slingshotL/slingshotR's
	-- own current outer edge (+ OUTLANE_CHANNEL_WIDTH_STUDS) -- NOT from
	-- cabinetwalls -- per direct instruction that the slingshot's own face IS
	-- the inlane's inner wall. The curve below each slingshot lands exactly
	-- on the flipper's physical top (both endpoints are real geometry, fully
	-- solved -- no free choice left there). LaneDividerLength (extra straight
	-- studs beyond the slingshot's own depth) and LaneDividerLateralOffset
	-- (only used if a slingshot can't be found at all) are the remaining
	-- ESTIMATEs.
	LaneDividerLength = 11,
	LaneDividerLateralOffset = FLIPPER_LENGTH_STUDS * 0.6,
	-- Matches WilliamsClassic.Slingshot.Height (2 studs) -- a lane guide next
	-- to the slingshot should read as the same height as the slingshot, not
	-- LaneGenerator's shorter ball-diameter-based default.
	LaneDividerHeight = 2,
	-- Starting point = LaneGenerator's own default wall thickness. This is
	-- the one deliberately tunable knob (see CabinetUpgrade.CabinetSpec's doc
	-- comment) -- adjust up (narrower outlane) or down (wider outlane) based
	-- on the achieved-outlane-width print from GenerateLaneDividers.
	LaneDividerThickness = 0.3,

	FlipperBasePreset = Presets.WilliamsClassic.Flipper,
	BumperBasePreset = Presets.WilliamsClassic.PopBumper,
	LaneDividerBasePreset = Presets.WilliamsClassic.LaneDivider,
	PlungerBasePreset = Presets.WilliamsClassic.Plunger,
}

return WilliamsCabinetSpec
