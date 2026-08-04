# Dream Pinball Agent Instructions

Read `architecture.md` and `TODO.md` before changing code.

## Project rules

- This is a Roblox game written in typed Luau.
- Roblox Studio is used for building, playtesting, debugging, and publishing.
- Local files are synchronized with Studio using Roblox Script Sync. Setup is complete; the verified synchronized paths are `src/ReplicatedStorage/DreamPinballShared`, `src/ServerScriptService/DreamPinballServer`, `src/StarterPlayerScripts/DreamPinballClient`, and `src/StarterGui/DreamPinballUI`.
- Claude Code is the primary implementer. Codex performs read-only review unless explicitly assigned implementation.
- Add `--!strict` to new Luau files.
- Keep authoritative game state and validation on the server.
- Never trust client-provided values.
- Validate every `RemoteEvent` and `RemoteFunction` request.
- Keep gameplay systems modular and avoid unnecessary dependencies.
- Do not rename or relocate synchronized root directories without approval.
- Make the smallest change required by the task.
- Do not invent game mechanics that are not documented in `architecture.md`.
- Update `TODO.md` only when an item's status actually changes.

## Verification

After changing code:

1. Format changed Luau files with StyLua when available.
2. Run Selene static analysis when available.
3. Report the exact Roblox Studio playtest steps.
4. State whether single-player, multiplayer, mobile, or controller testing is required.
5. Never claim Studio testing passed unless test output was provided or the user performed it.

## Debugging

Use the exact Studio error, stack trace, reproduction steps, expected behavior, and observed behavior.

After two unsuccessful fixes, stop and audit the goal, architecture, assumptions, evidence, and attempted changes. Then propose one evidence-based next fix.
