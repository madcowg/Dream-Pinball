# Dream Pinball

A Roblox game by Gabe & Lucas, configured for collaboration through Roblox Studio, Codex, and Claude Code.

## Required applications

- Roblox Studio
- Visual Studio Code
- Git
- Codex
- Claude Code

Open this repository as the working directory when starting Codex or Claude Code so each tool loads its project instructions.

## Connect Roblox Studio

Create or open the Dream Pinball experience in Roblox Studio. For each row below, select the Studio container in Explorer, right-click it, choose **Sync to...**, and select the corresponding local directory.

| Studio container | Local directory |
| --- | --- |
| `ReplicatedStorage` | `src/ReplicatedStorage` |
| `ServerScriptService` | `src/ServerScriptService` |
| `StarterPlayer > StarterPlayerScripts` | `src/StarterPlayerScripts` |
| `StarterGui` | `src/StarterGui` |

Resolve the first sync in favor of Studio if Studio already contains scripts that are not present locally. Review the conflict list before confirming.

Do not place visual objects in synchronized script folders. Script Sync manages scripts and folders, not the complete Studio data model.

## VS Code

Open the repository in VS Code and accept the recommended extensions. The workspace recommends:

- Roblox Luau Language Server
- StyLua
- Selene

## Agent workflow

Use one agent as the implementer and the other as the reviewer. Do not let both edit the same feature concurrently.

1. Define one small feature and its observable success criteria.
2. Ask Codex or Claude Code to inspect the relevant files and implement it.
3. Review the diff before accepting it.
4. Test it in Roblox Studio.
5. Give the exact Studio errors and observed behavior back to the implementing agent.
6. Ask the other agent for a read-only review.
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
