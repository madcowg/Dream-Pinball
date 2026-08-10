# Dream Pinball

A Roblox game by Gabe and his son, configured for collaboration through Roblox Studio, Codex, and Claude Code.

## Required applications

- Roblox Studio
- Visual Studio Code
- Git
- Codex
- Claude Code

Open this repository as the working directory when starting Codex or Claude Code so each tool loads its project instructions.

## Connect Roblox Studio

This project uses **Rojo** (not Roblox Studio's native Script Sync -- see "Project history" below for why that changed). Setup:

1. Install [Rokit](https://github.com/rojo-rbx/rokit) if you don't have it, then from the repo root run `rokit install` to install the pinned Rojo version (`rokit.toml`).
2. Install the Rojo Studio plugin once: `rojo plugin install`.
3. Start the sync server from the repo root: `rojo serve default.project.json`.
4. In Studio, open the Rojo panel (Plugins tab) and click **Connect**. Review the diff it shows before accepting, especially on first connect.

`default.project.json` maps `src/` to Studio services:

| Local directory | Studio container |
| --- | --- |
| `src/ReplicatedStorage/DreamPinballShared` | `ReplicatedStorage` |
| `src/ServerScriptService/DreamPinballServer` | `ServerScriptService` |
| `src/StarterPlayerScripts/DreamPinballClient` | `StarterPlayer > StarterPlayerScripts` |
| `src/StarterGui/DreamPinballUI` | `StarterGui` |

`Workspace` (hand-built cabinet geometry, e.g. WilliamsCabinet) is intentionally NOT in the Rojo tree -- it stays a pure Studio/place-file concern. Do not place visual objects in the synced folders above; Rojo manages scripts and folders there, not the complete Studio data model.

## VS Code

Open the repository in VS Code and accept the recommended extensions. The workspace recommends:

- Roblox Luau Language Server
- StyLua
- Selene

## Agent workflow

Claude Code is the primary implementer. Codex performs read-only review unless explicitly assigned implementation. Do not let both edit the same feature concurrently.

1. Define one small feature and its observable success criteria.
2. Ask Claude Code to inspect the relevant files and implement it.
3. Review the diff before accepting it.
4. Test it in Roblox Studio.
5. Give the exact Studio errors and observed behavior back to Claude Code.
6. Ask Codex for a read-only review.
7. Apply approved findings and commit the tested version.

## Feature request template

```text
Implement <feature-name>.

Player experience:
<what the player does>

Success criteria:
- <observable result>
- <observable result>

Constraints:
- Typed Luau
- Server-authoritative gameplay
- Validate client requests
- No new dependencies
- Preserve existing systems

Before editing, read AGENTS.md, architecture.md, and TODO.md. Inspect the relevant code and identify the files that will change.

After editing, format and analyze changed files, provide exact Roblox Studio playtest instructions, and update TODO.md only if an item was completed.
```

## Project history

Kept for context on why things are built the way they are -- see `architecture.md` for the technical reference details these summarize.

- **Backboard UI** ("Ocean Dreams" art on WilliamsCabinet) wired to show score, queued item modifiers, balls remaining, and player name via `SurfaceGui` `TextLabel`s.
- **Shadows disabled game-wide** (`Lighting.GlobalShadows = false`), enforced by a standing `DisableShadows.server.luau` script so it can't silently drift back on in a saved place file.
- **Relaunch/drain system redesigned from scratch.** The original design lost lives incorrectly on weak plunges that rolled back down the lane. Replaced with a `MainFieldEntry` marker + `ballInMainField` boolean: the drain only becomes "live" for a ball once it has actually touched `MainFieldEntry`; before that, a stalled ball can simply be relaunched (snapped back to `LaunchAnchor`) with no life lost.
- **Flipper torque-to-mass bug found and fixed.** A hand-built flipper's torque was set to the same absolute value as the code-built reference flipper's, but the hand-built one massed 4.5x less -- wildly wrong torque-to-mass ratio, causing jittery/barely-swinging flippers. Fixed with `GameplayTuning.FLIPPER_MOTOR_TORQUE_PER_MASS`, a ratio applied against each flipper's own live-measured `AssemblyMass` at build time instead of a flat number.
- **Migrated from Roblox's native Script Sync to Rojo** after it caused repeated stray-folder bugs and, at one point, deleted three real server scripts outright. See `architecture.md`'s "Sync tooling history" for the full account.
- **Ball/flipper physics investigation.** A long debugging effort into a reported "ball disappears near the flippers" bug worked through (and ruled out via live server-side diagnostics) floor gaps, drain trigger placement, camera occlusion, content streaming, and ball material/density, before finding two real, confirmed causes: (1) `CabinetBuilder`'s cosmetic flipper segments were incorrectly collidable, letting the ball wedge in the seams between them, and (2) a fast-moving ball (40+ studs/s) could bounce off a flipper with a real physics response but no `.Touched` event firing, making some hits register as "no contact." Full technical details and the fixes are in `architecture.md`'s "Flipper baseline" section.
- **Old comparison cabinets removed.** `CabinetDesignsTest.server.luau` (the three code-built comparison boards), `CabinetLayouts.luau`, `CabinetBaker.luau`, and the diagnostic `PhysicsTestRig.server.luau` were removed once WilliamsCabinet was confirmed working correctly, in favor of building future cabinets/assets through **PinballKit** (`src/ReplicatedStorage/DreamPinballShared/PinballKit/`), a generator toolkit for pinball components.
