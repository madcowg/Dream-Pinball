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

- [ ] Team places `DrainTrigger`, `LaunchAnchor`, and `CameraAnchor` on
      `WilliamsCabinet` (only pieces still missing)
- [ ] Playtest `WilliamsCabinet`'s full loop once those markers exist

## Features

Add features only after they have been discussed and accepted.
