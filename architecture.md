# Dream Pinball Architecture

## Product definition

Dream Pinball is a Roblox game being created by Gabe and his son.

Dream Pinball is a pinball roguelike. Full game vision, locked design decisions, and the current build target (the Sand-level prototype, World 1 Level 1 of 5) are recorded in `PINBALL_GAME_HANDOFF.md`. Read that file before implementing any gameplay system — it is the authoritative product spec referenced by the "Do not invent game mechanics" rule in `AGENTS.md`.

Current build target: Sand Level Prototype only (see `PINBALL_GAME_HANDOFF.md` "SAND LEVEL PROTOTYPE — BUILD ORDER"). Hub, meta-currency, stat-sacrifice, dual-type balls, and worlds beyond Sand are explicitly out of scope until the Sand level is playtested end-to-end.

## Development workflow

- Roblox Studio is the authority for visual objects, terrain, physics tuning, animation placement, audio placement, and publishing.
- Git-tracked `.luau` files are the authority for synchronized scripts.
- **Rojo** connects the directories under `src/` to their corresponding Studio services (see `default.project.json`) -- replaces the previous Roblox Script Sync setup; see "Sync tooling history" below for why.

## Source boundaries

| Local directory | Roblox Studio destination | Intended contents |
| --- | --- | --- |
| `src/ReplicatedStorage/DreamPinballShared` | `ReplicatedStorage` | Shared modules and remotes |
| `src/ServerScriptService/DreamPinballServer` | `ServerScriptService` | Server-authoritative systems |
| `src/StarterPlayerScripts/DreamPinballClient` | `StarterPlayerScripts` | Client controllers and input |
| `src/StarterGui/DreamPinballUI` | `StarterGui` | UI scripts |

## Security boundary

Clients request actions. The server validates permissions, state, ranges, timing, and values before changing authoritative game state.

## Flipper baseline (standard for every board)

**Historical note:** this baseline was confirmed live against `CabinetDesignsTest.server.luau`'s three comparison boards (Design A/B/C) and the standalone `PhysicsTestRig.server.luau`, both since removed once WilliamsCabinet was confirmed working and the project moved to PinballKit-generated assets going forward. The values and lessons below remain accurate and are preserved here for anyone building or tuning a flipper/cabinet, including PinballKit's own generators. `CabinetBuilder.luau` itself (the shared hinge/collision-group helper module) is still in active use by `WilliamsCabinet.server.luau` / `CabinetGameplay.luau` and was NOT removed.

Any flipper/cabinet built for any board in this project must match `CabinetBuilder.luau`'s approach. This section is the reference; re-derive from scratch only if the underlying `CabinetBuilder.luau` approach itself changes, and re-verify live rather than trusting reasoning about yaw/camera math or on-screen left/right descriptions -- both repeatedly produced wrong conclusions during this project's testing.

- Rest angle: `FlipperRestAngleDegrees = -45` (sign convention: rotation is `-direction * FlipperRestAngleDegrees` about the ramp's own normal, where `direction` is `Left = 1, Right = -1`).
- The pivot is pulled back along local Z by `FlipperSize.X * sin(rad(FlipperRestAngleDegrees))` so the flipper tips land near the cabinet's Z origin (by the drain) instead of drifting up-ramp toward the bumpers as the rest angle increases.
- Sweep direction (which way Q/E presses rotate each flipper) is a separate `SWEEP_DIRECTION` table (`Left = -1, Right = 1`), intentionally decoupled from the `MOTOR_DIRECTION` table used for the rest-angle rotation -- flipping one must not flip the other.
- Hinge attachments need explicit `Axis = (0,1,0)` and `SecondaryAxis = (1,0,0)` on both sides; relying on default attachment orientation causes the flipper to tilt instead of sweep.
- Flippers and the playfield floor/walls must be in separate PhysicsService collision groups with collision disabled between them (both still collide with the ball via Default) -- their swept volume overlaps the floor by design at rest height.
- Flippers must be built from the SAME tilted ramp `CFrame` as the floor (`computeRampCFrame` in `CabinetBuilder.luau`), not a world-flat plane -- the pivot's local +Y is the ramp's own normal, so the flipper lies flush/parallel to the tilted playing surface and sweeps along it, instead of cutting through it at a fixed world-horizontal angle.
- The ramp frame includes a 180-degree yaw (`CFrame.Angles(0, math.rad(180), 0)`) before the tilt is applied, in `computeRampCFrame`. Without it the cabinet loads facing the wrong way relative to the player's spawn/camera. Any camera code (fixed per-cabinet `CameraCFrame` values are computed in `CabinetBuilder.build` itself) must be positioned on the matching side of this yawed frame, not the pre-yaw orientation.
- `CabinetBuilder.build` gives the `"Left"` pivot the NEGATIVE local offset (`-config.FlipperPivotOffsetX`) and `"Right"` the positive one. This is the original assignment -- do NOT change it to try to make the Left/Right code labels match physical side directly; doing so affects the rest of the layout (bumpers/slingshots/etc.) and was reverted twice during testing. Left/right correction belongs ONLY in the client key mapping, below.
- Confirmed player-facing key mapping: **Q sends `"Right"`, E sends `"Left"`**, in `FlipperInputController.local.luau`'s `KEY_TO_SIDE`. This looks backwards from the naming but is correct given the (unmodified) pivot assignment above -- this is the only place to change if left/right ever needs correcting again. If in doubt, use a server-side diagnostic print of the actual pivot `.Name` and `.Position` on keypress, and do a full close-and-reopen of Studio before testing to rule out stale sync.
- Decoration placement (bumpers, slingshots, targets, etc.) must use `CabinetBuilder.pointOnRamp(ramp, localX, localZ, heightAboveSurface)`, not fixed world-Y coordinates -- the floor is tilted, so a flat world Y ends up embedded in or floating above the floor depending on how far up-ramp the decoration sits.
- Every board has a standard plunger lane (see `Typical_pinball_machine.png` reference image, Downloads folder): a narrow channel along the right edge (`PLUNGER_LANE_WIDTH`), separated from the main playfield by a divider wall with a gap near the high end (`PLUNGER_LANE_OPENING_LENGTH`) where the lane merges into the main field. The ball spawns and launches from here (`CabinetResult.PlungerLaneX`, `.PlungerLaneBottomZ`), not mid-air over the main playfield. In-lane/out-lane channels flanking the flippers, from the same reference image, are NOT yet implemented.
- **Flipper collision must be a single, seam-free volume.** `buildFlipper`'s 26 tapered cosmetic segments were originally left `CanCollide = true` (contradicting the module's own "cosmetic shell" doc comment) -- a fast ball could catch in the seams between overlapping segments and get wedged, visible live as `AssemblyLinearVelocity`'s X/Z components freezing to an exact bit-for-bit constant across many frames while only Y kept falling under gravity. Fixed by setting all segments `CanCollide = false` and widening the core `flipper` part to the FULL visual width (not half), with `Transparency = 1` on that core box so its non-tapered silhouette is never actually seen -- only the cosmetic tapered segments render.
- **Resizing a flipper changes rotational inertia faster than mass.** Uniformly scaling a flipper's linear size by factor `s` scales mass by `s^3` (volume) but moment of inertia by `s^5` (mass times radius-squared). `GameplayTuning.FLIPPER_MOTOR_TORQUE_PER_MASS` only compensates for the `s^3` mass change -- after a live 25% linear resize, the flipper's swing measurably weakened even with torque "correctly" recalculated from the new mass, because inertia had grown by `s^5 ≈ 3.05x` against torque's `s^3 ≈ 1.95x`. Any future resize needs torque scaled by the full inertia ratio, not just the mass ratio, to preserve the same swing feel.
- **Launch speed constants are NOT shared and must not be mixed up.** `GameplayTuning.LAUNCH_SPEED_TO_VELOCITY_SCALE = 15` is calibrated specifically for WilliamsCabinet's harder-to-clear hand-built lane ("spring needed more power to clear the lane"). The code-built comparison boards used their own separate local `LAUNCH_SPEED_TO_VELOCITY_SCALE = 7.5` -- using WilliamsCabinet's constant on a `CabinetBuilder`-built table launches the ball at roughly 2x the intended, proven speed.
- **Fast balls can pass a Touched-based collider without firing `.Touched`.** Server-side diagnostics on WilliamsCabinet caught the ball's velocity changing correctly (a real physics bounce) with no corresponding flipper `Touched` event at ball speeds above roughly 40 studs/s -- Roblox's discrete Touched event can miss contacts brief enough at high closing velocity, even though the physics solver still resolves the bounce. Since scoring, contact feedback, and diagnostics all depend on `.Touched`, this reads as "the flipper didn't hit it" even though it physically did. Fix: clamp the ball's speed once it's live in the main field (not during the plunger launch itself, which needs its full strength to clear the lane) so every collision stays slow enough for `.Touched` to be reliable, rather than trying to detect and patch missed events after the fact.
- **A `DrainTrigger` must sit PAST the drain edge and BELOW the floor surface**, not overlapping the playfield -- e.g. `pointOnRamp(ramp, 0, -2, -9)` (negative local Z, negative height). A trigger positioned inside the playfield or floating above it can catch a ball that is still legitimately in play.
- **Ball `CustomPhysicalProperties` for a "solid steel" feel:** density `7.85` (matches real steel's density ratio to Roblox's own Plastic default of `~0.7`), friction `0.3` (polished metal slides easily), elasticity `0.4` (a heavy solid ball thuds rather than bounces).

## Sync tooling history: why Rojo replaced Script Sync

**Historical note, kept for anyone hitting sync weirdness in the future.** This project originally used Roblox Studio's built-in native File Sync feature (no config file, no plugin -- a first-party, name-convention-based sync between Studio's Explorer and `src/`). It caused repeated, hard-to-diagnose problems over the course of this project:

- A duplicate `StarterPlayerScripts/StarterPlayerScripts/DreamPinballClient` folder appeared multiple times, with stray script instances whose sync link pointed at a stale/orphaned disk path -- editing the "obviously correct" file on disk did nothing because Studio was never actually watching that file for the affected instance.
- Native sync stayed silently active even after no sync-status icons were visible in Explorer and no relevant Beta Feature toggle was enabled, and at one point it cleared `ServerScriptService/DreamPinballServer` entirely on disk after hitting an `"Invalid name in hierarchy"` error on one bad child instance, deleting three real, working scripts (recovered from a manual Studio backup and this session's own conversation history -- always keep a `File > Download a Copy` backup before touching sync configuration).

The project migrated to **Rojo** (`rokit.toml` pins the version; `default.project.json` defines the explicit mapping) specifically because Rojo requires an explicit, unambiguous project file instead of guessing paths by naming convention, which eliminates this entire class of bug. Two things matter if you ever touch `default.project.json`:

- `Workspace` (and therefore `BakedCabinets`/`WilliamsCabinet`'s hand-built geometry) is deliberately NOT included in the Rojo tree -- it stays purely a Studio/place-file concern, exactly like before.
- `ReplicatedStorage.DreamPinballShared` has `$ignoreUnknownInstances: true` specifically so Rojo never deletes the hand-placed `CreatureModelAssets` / `SharedModelAssets` model folders, which have no disk representation.

Run `rojo serve default.project.json` from the repo root, then connect via the Rojo Studio plugin, before syncing any code changes.

## Client script folder structure (locked)

- `StarterPlayerScripts` (Studio) contains exactly one folder: `DreamPinballClient`.
- `DreamPinballClient` contains exactly four LocalScripts: `CameraRig`, `FlipperInputController`, `ItemInputController`, `LaunchInputController` -- matching the four `.local.luau` files in `src/StarterPlayerScripts/DreamPinballClient/` on disk (plus `BallVisualSmoother`, added later).
- No nested/duplicate `DreamPinballClient` or `StarterPlayerScripts` folders should ever exist -- under Rojo this shouldn't recur, but if the Explorer ever shows two, verify via each script's actual content which one is stale before deleting either.

## Decisions

Add confirmed architectural and product decisions here. Do not use this section as a wishlist.

- Rojo is the sync tool between `src/` and Studio (see `default.project.json`); Script Sync is no longer used. The four source paths above are verified against Roblox Studio via Rojo.
- Claude Code is the primary implementer. Codex performs read-only review unless explicitly assigned implementation.
- Product definition is locked for the Sand-level prototype scope; see `PINBALL_GAME_HANDOFF.md`.
- Flipper/cabinet construction baseline is locked; see "Flipper baseline" above.
- `StarterPlayerScripts` folder structure is locked; see "Client script folder structure" above.
- `CabinetDesignsTest.server.luau`, `CabinetLayouts.luau`, `CabinetBaker.luau`, and the diagnostic `PhysicsTestRig.server.luau` have been removed now that WilliamsCabinet is the sole cabinet and the project is moving to PinballKit-generated assets. `CabinetBuilder.luau` and `CabinetGameplay.luau` remain in active use.
