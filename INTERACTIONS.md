# Interaction Contracts

Companion document to `ROBLOX_AI_GAME_DEV_INSTRUCTIONS.md`. Documents interactions as they actually exist in `CabinetGameplay.luau` (shared by WilliamsCabinet, WilliamsCabinetPlayground, and Cabinet01 -- one engine, one contract, three independent instances). Update this file when the contract changes, not just the code.

## Flipper

- Owner: split -- client sends raw press/release intent; server owns and validates all physics.
- States (per flipper hinge): `Resting`, `Rising`, `Held`, `Returning`, `Disabled` (see `PinballKit/Runtime/FlipperController.luau`'s `GetState`, classified from `Hinge.CurrentAngle`/`AngularVelocity` magnitude -- not currently read by `CabinetGameplay.luau`'s own flipper path, which drives the hinge directly via `CabinetBuilder.setFlipperInput`).
- Request: `FlipperInputRemote:FireServer(side: "Left" | "Right", pressed: boolean)`, sent by `FlipperInputController.local.luau` (keyboard Q/E, gamepad L1/L2/R1/R2, or any future physical-button prop using the same remote/payload).
- Server guards: `FlipperInput.ValidateInput(side, pressed)` rejects anything where `side` isn't exactly `"Left"`/`"Right"` or `pressed` isn't a boolean (shared by every cabinet's listener, not duplicated per-cabinet). `gameplay.IsEngagedBy(player)` additionally gates every cabinet's own listener -- an unengaged player's flipper input for that cabinet is dropped silently.
- Transition table:

| Current state | Event | Guards | Next state | Effects |
| --- | --- | --- | --- | --- |
| Resting | `pressed=true` | engaged, valid side | Rising -> Held | `hinge.AngularVelocity = speed * ACTUATE_SPEED_MULTIPLIER * SWEEP_DIRECTION[side]` |
| Held | `pressed=false` | engaged, valid side | Returning -> Resting | `hinge.AngularVelocity = -speed * RETURN_SPEED_MULTIPLIER * SWEEP_DIRECTION[side]` |

- Cancellation: none dedicated -- a player leaving (`PlayerRemoving`) calls `gameplay.ForceDisengage`, which stops HUD/camera updates but does NOT itself release a held flipper (the hinge simply keeps whatever `AngularVelocity` it last had; a disengaged player can no longer fire new input, so it settles once it reaches its limit). Acceptable for the current scope -- not a real gap unless a disconnect-while-held bug is observed live.
- Replication: none beyond the physics itself -- both flippers are server-authoritative `HingeConstraint`s; clients see the resulting motion via normal physics replication, no explicit state broadcast.
- Idempotency: a duplicate `pressed=true` while already Held just re-sets the same `AngularVelocity` (no-op in practice); a duplicate `pressed=false` while already Resting is likewise harmless.
- Cleanup: none needed -- the hinge is a permanent per-cabinet Instance, not created/destroyed per press.

**Left/Right sign authority** (do not re-derive from geometry reasoning -- see architecture.md's repeated caution on this):
- Which key/button sends which `side` string: `FlipperInputController.local.luau`'s `KEY_TO_SIDE` -- **LOCKED**: Q/L1/L2 = `"Left"`, E/R1/R2 = `"Right"`, for every cabinet. This is a labeling fact (Q is the physically-left flipper's key), never a tuning knob -- do not invert it to compensate for a hinge-direction bug.
- Which way a given `side`'s hinge physically sweeps: `CabinetBuilder.luau`'s `SWEEP_DIRECTION` table, applied identically regardless of which construction path built that hinge (`CabinetBuilder.buildFlipper` for code-built tables, `CabinetBuilder.attachFlipperHinge` for hand-built/marker-built ones including Cabinet01). **This is the correct fix location for a "flippers respond to the wrong key" symptom that affects every cabinet uniformly** (confirmed 2026-08-12: flipped to `{ Left = 1, Right = -1 }` after WilliamsCabinet/WilliamsCabinetPlayground both tested backwards under the locked key mapping).
- A "this specific cabinet's flipper visually sweeps the wrong way while another cabinet's is correct" symptom is a geometry/construction bug in that ONE cabinet's own flipper CFrames, not `SWEEP_DIRECTION` (shared, so it can't explain a single-cabinet disagreement) and never `KEY_TO_SIDE` -- see Cabinet01Builder.luau's live-verification note 2.

## Start Level

- Owner: server.
- States: `Idle` (no engaged player) -> `Engaged` (one player, turn state fresh) -> `Idle` (on drain/win + no re-engage, or on `ForceDisengage`).
- Inputs: `ProximityPrompt.Triggered` (key F, `InteractAnchor`).
- Guards: `MaxActivationDistance = 10`, no line-of-sight requirement, `HoldDuration = 0`.
- Transitions: Triggered by player P while cabinet is Idle -> Engaged(P), fresh `TurnState`/hand/inventory/run-currency, movement NOT yet locked (only locks on first `Launch`), camera snapped to `CameraAnchor.CFrame` for P. Triggered by player P while Engaged(Q!=P) -> the previous player Q is bumped (unlocked, HUD/camera cleared for Q), then Engaged(P) as above.
- Effects: HUD push, backboard update (if present), `describeState` print.
- Cancellation: `player.PlayerRemoving` -> `ForceDisengage` -> Idle, movement unlock skipped (character is gone).
- Replication: `HudRemotes`/`CameraRemotes` fire only to the engaged player -- no other client sees this cabinet's state change.
- Idempotency: re-triggering by the same already-engaged player just restarts their own level (destroys any in-flight ball, resets state) -- explicit, not accidental.
- Cleanup: previous ball (if any) destroyed before the new hand is created.

## Launch

- Owner: server (client requests via `LaunchInputRemote`, holds R to charge, releases to fire -- see `LaunchInputController.local.luau`).
- States: `NoBall` -> `InLane` (spawned, not yet touched `MainFieldEntry`) -> `InField` (touched `MainFieldEntry`) -> `NoBall` (drained, or broken/lost).
- Guards (`CabinetGameplay.launch`): must be the engaged player; turn state must not already be over; if a ball exists and is `InField`, reject (only one ball in play); if a ball exists, is `InLane`, and still moving above `LANE_REST_SPEED_THRESHOLD`, reject; `hand[1]` must not be broken (0 durability); `power` clamped `[0.2, 1]` server-side regardless of client input.
- Transitions: see states above. Re-launch (ball `InLane`, at rest) fires the SAME ball object from wherever it is along `LaunchAnchor.CFrame.LookVector`, not a new one.
- Effects: movement lock engages on first launch of the turn; plunger visual release (if a baked plunger exists); ball velocity set from `hand[1].Stats.Speed + pendingSpeedDelta`, scaled by `LAUNCH_SPEED_TO_VELOCITY_SCALE`; ball network ownership forced server-side.
- Cancellation: none mid-flight -- a launched ball resolves via scoring bounces, `MainFieldEntry`, or `DrainTrigger` only.
- Replication: ball is a normal replicated physics part; HUD/backboard pushed to the engaged player only.
- Idempotency: a rejected launch (see guards) is a no-op warn, not a partial state change.
- Cleanup: `endLaunch` destroys the active ball part and clears `activeBallPart`/`activeBallData`/`ballInMainField` on drain or all-balls-broken.
