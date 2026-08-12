# Dream Pinball TODO

## Setup

- [x] Connect the four `src/` directories to Roblox Studio using Script Sync.
- [ ] Install the recommended VS Code extensions.
- [ ] Confirm StyLua formatting works.
- [ ] Confirm Selene static analysis works.
- [x] Complete one Script Sync round trip between a local `.luau` file and Studio.

## Product definition

- [x] Define the core pinball gameplay loop. See `PINBALL_GAME_HANDOFF.md`.
- [x] Define the first playable success criteria. Sand-level prototype build order in `PINBALL_GAME_HANDOFF.md`.
- [x] Define supported devices and input methods. PC first, console second, mobile third; input-agnostic (WASD/click + controller-portable).
- [x] Decide whether the first version is single-player or multiplayer. Single-player runs.

## Sand level prototype build order

Full design context lives in `PINBALL_GAME_HANDOFF.md` — do not duplicate its content here. Track only build-order progress:

- [x] 1. Data schemas (ModuleScripts): `Ball`, `Character`, `Item`, `Encounter`
- [x] 2. Type-effectiveness table (full 8x8, soft multipliers)
- [x] 3. Repo structure confirmation (already using `src/ReplicatedStorage/DreamPinballShared` etc. via Script Sync)
- [x] 4. Fixed camera rig for in-level table view
- [x] 5. Bumper control script (Q/E input -> physics impulse) on an empty test table -- SUPERSEDED, see "Cabinet design comparison" below
- [x] 6. Turn-state machine: hand (3 slots), 4-action menu, turn counter, 5-turn loss condition
- [x] 7. Launch -> physics segment -> return-to-hand or durability-loss -> back to menu loop (implemented, NOT playtested yet -- press L in Play mode)
- [x] 8. Item system: single-use, modifies only the next-launched ball, consumes on use (implemented, NOT playtested yet -- press 1-5 for Feather/Coffee/ExtraBall/Magnet/Hammer)
- [x] 9. One full Sand-themed (Water-type) encounter wired end-to-end (implemented, NOT playtested yet)
- [x] 10. Run-currency: award on encounter/quest completion (implemented, NOT playtested yet -- awarded once on Won)
- [ ] 11. Basic in-machine shop (run-currency only) -- BLOCKED, needs shop inventory/pricing design decision first
- [ ] 12. Autosave at level-end: seed, hand, inventory, run-currency
- [x] 13. Minimal HUD: hand display, threshold progress, turn counter, per-ball durability (implemented, NOT playtested yet -- see HudController.local.luau + per-cabinet EngagementZone in CabinetDesignsTest.server.luau)
- [ ] 14. Playtest full Sand-level loop end-to-end

## Cabinet design comparison (in progress)

The hand-built test flipper rig (steps 4-5) kept producing confusing/wrong
physics that took many rounds to debug. Retired it and researched how other
Roblox pinball projects build cabinets instead. Three side-by-side test
cabinets exist for comparison -- see `CabinetDesignsTest.server.luau` and
`CabinetBuilder.luau` (shared construction logic; the flipper setup there is
now the confirmed baseline for every board, see architecture.md "Flipper
baseline"). The full gameplay loop (steps 6-10: turn state, launch, items,
encounter, currency) now runs independently on each of the three cabinets at
once -- `LaunchTest.server.luau` and `TurnStateTest.server.luau` are deleted,
superseded by this. Each cabinet has a ProximityPrompt ("interact button",
key F) at standing height in front of it -- pressing it starts a fresh level
and engages that player with the cabinet (Q/E/R/1-5 route only to that
cabinet, and the HUD shows only its state). Launching locks that player's
movement until the turn resolves Won/Lost, like a real arcade machine. The
fixed camera (`CameraRig.local.luau`) is remote-driven the same way: it
activates on Start Level and deactivates on Won/Lost, instead of always
being on -- `CabinetDesignsCamera.server.luau` (a single always-on global
camera anchor) is deleted, superseded by per-cabinet `CameraCFrame` values
computed in `CabinetBuilder.build`.

- [ ] Playtest the full loop (launch, items, scoring, drain, win/loss,
      currency) on each of the three cabinets, compare what works
- [ ] Pick one of the three designs (Classic Arcade / Historic Simple /
      Modular Template) as the real Sand-level cabinet base
- [ ] Delete `CabinetDesignsTest.server.luau` and the two unchosen designs'
      geometry once a choice is made

Contributor visual access: `CabinetLayouts.luau` is now the single source of
truth for all three designs' configs/bumper/slingshot placement (read by
both `CabinetDesignsTest.server.luau` and the new `CabinetBaker.luau`).
`addBumper`/`addSlingshot` moved from the test script into `CabinetBuilder.luau`
as public functions for the same reason. To give contributors something
visible/editable in Studio without running Play, run once from Studio's
Command Bar:

```lua
local Baker = require(game.ReplicatedStorage.DreamPinballShared.CabinetBaker)
Baker.bakeAll(workspace)
```

then Ctrl+S. This creates a separate, static `Workspace.BakedCabinets`
folder (offset 300 studs in +Z from the live test area, names suffixed
`_Baked`) with real, saved Parts contributors can select/move/recolor
directly -- it does not interact with or get rebuilt by
`CabinetDesignsTest.server.luau`'s live Play-time harness. Re-run any time
`CabinetLayouts.luau` changes to refresh the baked copy (safe to re-run,
replaces the previous bake instead of duplicating it) -- BUT once a
contributor starts hand-editing a specific baked design, stop re-baking
that one (re-running destroys and rebuilds it from CabinetLayouts,
discarding their edits).

## Hand-built commercial-spec cabinets (new track)

The team is now building new cabinets by hand in Studio to real commercial
pinball dimensions, NOT via `CabinetLayouts.luau`/`CabinetBuilder.build`
(that pipeline stays as-is for the 3 comparison designs above). To attach
full gameplay (turn state, launch, items, scoring, drain, HUD, fixed camera,
movement lock, interact prompt) to a hand-built cabinet without writing
per-cabinet code, `CabinetGameplay.luau` wires up ANY cabinet Folder by
finding required markers BY NAME instead of requiring `CabinetBuilder`
output. See that module's doc comment for the full marker list and how to
build each one; short version:

- `LeftFlipper` / `RightFlipper` -- built by the team already, hinge wired
  and working. `CabinetGameplay` finds and DRIVES the existing hinge, it
  does not build one.
- `Bumper` (any count) -- reused from the existing bumper asset, works as-is.
- `DrainTrigger` -- NEW, team places a Part where a lost ball should fall through.
- `LaunchAnchor` -- NEW, team places a Part where the ball spawns; it
  launches along that Part's own forward (+Z) direction -- point its front
  face at the main playfield.
- `InteractAnchor` -- standing-height Part in front of the cabinet, gets the
  "Start Level" prompt (key F).
- `CameraAnchor` -- a Part whose CFrame becomes the fixed in-level camera
  exactly as placed. Set it without typing coordinates: fly Studio's own
  edit-mode camera to the desired view, then run from the Command Bar:
  ```lua
  local CabinetGameplay = require(game.ReplicatedStorage.DreamPinballShared.CabinetGameplay)
  CabinetGameplay.snapCameraAnchorToViewport(workspace.BakedCabinets.WilliamsCabinet.CameraAnchor)
  ```
  then Ctrl+S.

First cabinet on this track: `WilliamsCabinet` (`Workspace.BakedCabinets.WilliamsCabinet`),
wired up by `WilliamsCabinet.server.luau`. Completely independent of
`CabinetDesignsTest.server.luau` -- separate turn state, separate engaged-player
tracking, no shared code path beyond `CabinetGameplay`/`CabinetBuilder` itself.

Second cabinet on this track: `WilliamsCabinetPlayground`
(`Workspace.BakedCabinets.WilliamsCabinetPlayground`), wired up by
`WilliamsCabinetPlayground.server.luau` -- a full twin of
`WilliamsCabinet.server.luau`, same `CabinetGameplay.setup` wiring, own
independent engagement tracking. Purpose: a sandbox to test gameplay/
`CabinetUpgrade` changes on before they touch the real WilliamsCabinet, and
the template to copy for future hand-built cabinets (copy the file, change
`CABINET_NAME` and the label string).

Third cabinet, new track (added 2026-08-12): `Cabinet01`
(`Workspace.BakedCabinets.Cabinet01`), built by `Cabinet01Builder.luau` and
wired by `Cabinet01.server.luau` -- the first cabinet built under
`C:\Users\gabri\.claude\ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md`'s spatial-contract
discipline (explicit hierarchy, true-mirrored flippers via
`MirrorTransform.MirrorCFrame` instead of a hand-copied sign table, live-
verification notes instead of trusted-from-reasoning geometry). Coexists with
WilliamsCabinet/WilliamsCabinetPlayground -- does not replace either.
Auto-builds itself on first server start if missing, so no manual Command Bar
step is required. Minimal "flippers first" scope: launch, flip, score on 2
bumpers, drain -- no plunger lane, backboard, or cosmetic shell yet. See
`SCENE_SPEC.md`/`INTERACTIONS.md`/`HANDOFF.md` for the full spec.

- [ ] Team places whichever of `DrainTrigger`/`LaunchAnchor`/`MainFieldEntry`/
      `InteractAnchor`/`CameraAnchor` is still missing on `WilliamsCabinet`
      (`LeftFlipper`/`RightFlipper` were already fixed this session -- see
      below) -- check the exact marker name in the Output error next Play
- [ ] Same check + same missing markers, independently, on
      `WilliamsCabinetPlayground` -- never wired up before this session, so
      status unknown; expect at least one to error on first Play
- [ ] Playtest each cabinet's full loop once its own markers exist (fully
      independent scripts -- one erroring doesn't block the other)

### Session status (2026-08-11) -- pending for next session

Found and fixed a real bug in `CabinetUpgrade.luau`: `FinalizeFlipperNames`
renamed a flipper's `.Name` but never updated its `GenerationId` attribute
(what `PrimitiveFactory.ReplaceOrParent` uses to detect "did I already build
this"), so any later `GenerateNewFlippers` re-run would silently destroy the
renamed/finalized flipper and recreate it as `LeftFlipper_New`/
`RightFlipper_New`. This had already happened to both `WilliamsCabinet` and
`WilliamsCabinetPlayground` -- neither currently has a plain `LeftFlipper`/
`RightFlipper`, only the `_New` pair.

- [ ] Run the fixed `FinalizeFlipperNames` (Server Command Bar, Edit mode)
      against BOTH cabinets to restore `LeftFlipper`/`RightFlipper`:
      ```lua
      local CabinetUpgrade = require(game.ReplicatedStorage.DreamPinballShared.PinballKit.Migrations.CabinetUpgrade)
      local WilliamsCabinetSpec = require(game.ReplicatedStorage.DreamPinballShared.PinballKit.Migrations.WilliamsCabinetSpec)
      for _, cabinetName in ipairs({"WilliamsCabinet", "WilliamsCabinetPlayground"}) do
      	local cabinet = workspace.BakedCabinets:FindFirstChild(cabinetName)
      	if cabinet then
      		CabinetUpgrade.FinalizeFlipperNames(cabinet, WilliamsCabinetSpec)
      	end
      end
      ```
- [ ] Confirm both cabinets show plain `LeftFlipper`/`RightFlipper` only
      (no `_New`) before playtesting either

Also pending: everything in "Cabinet design comparison" and the Lower
Playfield rig (`PinballKit.LowerPlayfieldTest`) below is still uncommitted --
a code review this session found and fixed 8 real bugs across
`PinballMechanisms.luau`/`FlipperInputController.local.luau`/
`LaneSwitchController.luau`/`ComponentRegistry.luau`/`FlipperGenerator.luau`/
`CabinetUpgrade.luau` (rate-limiter drop, gamepad/keyboard mirroring
mismatch, lane-switch enter/exit latch ordering, per-ball cooldown memory
leak, flipper-input dispatcher firing every registered cabinet, a duplicate
flipper-mirroring table drifting from the real one). The Lower Playfield
test rig itself has not been playtested end-to-end yet -- its demo anchor
was also moved from world origin (overlapped spawn/WilliamsCabinet visually)
to `(75, 1, 0)`.

- [ ] Commit the uncommitted PinballKit/Lower-Playfield work once it's been
      playtested (currently sitting as local changes only)
- [ ] Playtest the Lower Playfield rig in isolation at its new position

### Session status (2026-08-12) -- pending for next session

Live-tested Q/E on WilliamsCabinet and WilliamsCabinetPlayground: both
flippers responded backwards under the correct, natural key mapping
(Q="Left", E="Right"). The player-facing key mapping is LOCKED -- Q is
always the physically-left flipper's key, full stop -- so the fix does NOT
belong in `FlipperInputController.local.luau`. The actual defect was
`CabinetBuilder.luau`'s `SWEEP_DIRECTION` table; flipped from
`{ Left = -1, Right = 1 }` to `{ Left = 1, Right = -1 }`. This is shared code
(used by every hand-built/marker-built cabinet's hinge, via
`attachFlipperHinge`), so the fix applies to WilliamsCabinet,
WilliamsCabinetPlayground, AND the new `Cabinet01` below all at once.
`architecture.md` updated to lock this in writing so the key mapping doesn't
get re-inverted again by mistake.

Found and fixed a real bug in `CabinetGameplay.setup`'s auto-anchor pass
(`isExcludedFromAutoAnchor`): it only excluded *descendants* of the
`LeftFlipper`/`RightFlipper` marker, never the marker itself, so a cabinet
whose flipper marker is a bare Part (not a Model wrapping it) would get that
Part force-anchored and its hinge silently broken. Did not affect
WilliamsCabinet/WilliamsCabinetPlayground (their flipper markers are Models),
but would have broken `Cabinet01` (below) on first Play. Fixed.

Built `Cabinet01`, a new coexisting cabinet under
`ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md`'s discipline -- see the "Hand-built
commercial-spec cabinets" section above for what it is and why. NOT yet
playtested (built this session, ready for tomorrow):

- [ ] Playtest WilliamsCabinet: confirm both flippers now sweep toward
      center with Q on the left, E on the right (F to start, R to launch)
- [ ] Playtest WilliamsCabinetPlayground: same check, independently
- [ ] Playtest Cabinet01 (`Workspace.BakedCabinets.Cabinet01`, built
      automatically on first Play if missing -- no Command Bar step needed):
      F to start, Q/E to flip, R to launch, confirm scoring on its 2 bumpers,
      confirm drain. Known unverified guesses to watch for (see
      `Cabinet01Builder.luau`'s doc comment for the full list): table tilt
      direction (ball should roll toward the drain, not the back wall),
      fixed camera framing (fixable live via
      `CabinetGameplay.snapCameraAnchorToViewport` without touching code),
      whether Cabinet01's flippers sweep the same correct direction as
      WilliamsCabinet's once both are confirmed working
- [ ] If WilliamsCabinet/WilliamsCabinetPlayground's flippers still look
      wrong on only ONE side after the `SWEEP_DIRECTION` fix (not both,
      uniformly), see `HANDOFF.md`'s "Findings/blockers" note on
      `CabinetUpgrade.luau`'s two structurally different flipper-origin
      conventions -- that is the next thing to investigate. Do NOT touch
      `FlipperInputController.local.luau`'s `KEY_TO_SIDE` for any
      flipper-direction symptom -- that mapping is locked (see
      architecture.md)
- [ ] Once all three are confirmed working (or their specific remaining bugs
      are identified), decide whether to build out Cabinet01's plunger lane/
      backboard/cosmetic shell next, or pick one design as primary

## Features

Add features only after they have been discussed and accepted.
