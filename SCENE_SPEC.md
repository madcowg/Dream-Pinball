# Scene Specification

Companion document to `ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md` (`C:\Users\gabri\.claude\ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md`). Read alongside `TODO.md` and `architecture.md` before changing cabinet code. Populated only for cabinets that have actually been built under the new instructions doc's hierarchy (currently: Cabinet01). WilliamsCabinet and WilliamsCabinetPlayground predate this document and are governed by `architecture.md`'s "Flipper baseline" section instead -- they are not re-documented here.

## Coordinate conventions

- World up: `+Y`.
- Units: studs, seconds; radians in code, degrees in authored config constants (converted once via `math.rad`).
- Per-cabinet forward/up/right conventions are NOT global -- each cabinet's own ramp/table frame defines its own local axes (see each cabinet's entry below). Never assume one cabinet's Left/Right or +Z convention applies to another; WilliamsCabinet and Cabinet01 use *different* conventions on purpose (see `Cabinet01Builder.luau`'s doc comment for why).

## Instance map: Cabinet01

Built by `src/ReplicatedStorage/DreamPinballShared/Cabinet01Builder.luau`. Root: `Workspace.BakedCabinets.Cabinet01`.

| Semantic role (this doc) | Instance path (under `Cabinet01`) | Class | Pivot/attachment | Notes | Authority |
| --- | --- | --- | --- | --- | --- |
| Cabinet root frame | `CabinetRoot` | Part (anchored, invisible) | Own CFrame = `ORIGIN`, zero rotation | Reference only -- not read by any code yet, documents the cabinet's nominal placement frame | server (static) |
| Exterior shell | *(not built yet)* | -- | -- | Deferred -- this pass is gameplay-only, no cosmetic exterior | -- |
| Interior wrapper | `Interior` | Model | -- | Groups Playfield/Mechanisms/InteriorLights per the required hierarchy | server (static) |
| Playing surface | `Interior.Playfield.CabinetFloor` + `LeftWall`/`RightWall`/`BackWall`/`FrontWallLeft`/`FrontWallRight` | Part | `RAMP_CFRAME`-relative, see below | Tilted `TILT_DEGREES` (6.5, unverified sign) about `RAMP_CFRAME`'s local X | server (static) |
| Mechanisms wrapper | `Interior.Mechanisms` | Model | -- | Contains flippers, bumpers, drain, launch/field-entry markers | server (static) |
| Flippers (CabinetGameplay marker) | `Interior.Mechanisms.LeftFlipper`, `RightFlipper` | Part (unanchored, 1 `Attachment` named `Pivot`) | `Pivot` at local `(-FlipperSize.X/2, 0, 0)` | RightFlipper's rest CFrame is the TRUE mirror of LeftFlipper's (`MirrorTransform.MirrorCFrame`) -- see Cabinet01Builder's spatial contract. Hinge auto-built by `CabinetGameplay.setup` on first server start (not baked) | server (physics, motor input) |
| Scoring bumpers (CabinetGameplay marker) | `Interior.Mechanisms.Bumper` (x2) | Part (cylinder) | via `CabinetBuilder.addBumper` | Placeholder placement/point value (uses `GameplayTuning.SCORE_PER_BOUNCE` fallback, no per-instance override yet) | server |
| Drain (CabinetGameplay marker) | `Interior.Mechanisms.DrainTrigger` | Part (`CanCollide=false`) | `pointOnRamp(0, -3, -8)` | Past the drain edge, below floor surface, per architecture.md's DrainTrigger placement rule | server |
| Ball spawn (CabinetGameplay marker: `LaunchAnchor`) | `Interior.Mechanisms.LaunchAnchor` | Part | Local 180deg yaw so its own `LookVector` points back toward the flippers | No separate plunger lane in this pass -- ball spawns directly on the main floor near a back corner | server |
| Field-entry (CabinetGameplay marker: `MainFieldEntry`) | `Interior.Mechanisms.MainFieldEntry` | Part (`CanCollide=false`) | Immediately adjacent to `LaunchAnchor` | Because there's no separate lane, "in main field" triggers almost immediately after launch -- see Cabinet01Builder's live-verification note 4 | server |
| Interior lights | `Interior.InteriorLights` | Folder | -- | Empty -- no cabinet-local lights built yet; per the lighting contract, add lights here with `Shadows=false` before any interior visual work | -- |
| Camera rig | `CameraRig.CameraAnchor` (CabinetGameplay marker: `CameraAnchor`) | Part (invisible) | `CFrame.lookAt` from behind the drain end, see Cabinet01Builder | Authored guess, not live-verified -- fix via `CabinetGameplay.snapCameraAnchorToViewport` if wrong | server (drives client camera via `Remotes/CameraControl`) |
| Interaction entry (CabinetGameplay marker: `InteractAnchor`) | `InteractionPoints.InteractAnchor` | Part (invisible) | 4 studs above ground, 4 studs in front of the drain edge | Gets the "Start Level" `ProximityPrompt` (key F) | server |
| Interaction exit | *(none -- leaving is just walking away)* | -- | -- | N/A for this cabinet | -- |
| Generated-at-runtime instances | `Runtime` | Folder | -- | Currently unused -- `LaunchBall` is still parented directly to the cabinet folder by `BallGenerator`, not into `Runtime`, matching existing project convention | server |
| Config | *(none -- constants live in `Cabinet01Builder.luau`)* | -- | -- | No per-instance `Config` object yet; all tunables are the local constants at the top of the builder script | -- |

`RAMP_CFRAME` (Cabinet01Builder.luau): `CFrame.new(ORIGIN) * CFrame.Angles(math.rad(TILT_DEGREES), 0, 0)`, `ORIGIN = (150, 9, 0)`. Local +Z: drain (Z=0) to back wall (Z=52). Local +X: screen-right facing +Z. No yaw -- see Cabinet01Builder.luau's doc comment for why this differs from `CabinetBuilder.luau`'s own convention.

## Spatial invariants

- Cabinet01's `RightFlipper` rest CFrame is always the exact `MirrorTransform.MirrorCFrame` reflection of `LeftFlipper`'s rest CFrame across the table centerline (local X=0) -- enforced by construction (`Cabinet01Builder.buildFlippers`), not by a separately-maintained sign table.
- Every static Cabinet01 part's CFrame derives from `RAMP_CFRAME` via `CabinetBuilder.pointOnRamp` -- no part uses a hardcoded world-Y value.

## Streaming assumptions

- `Workspace.BakedCabinets` is outside the Rojo tree (see architecture.md's Rojo section) -- it only exists once `Cabinet01Builder.build()` has run (or `Cabinet01.server.luau` auto-builds it on first server start if missing). Not present on a fresh Rojo sync alone.
