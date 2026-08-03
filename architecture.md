# Dream Pinball Architecture

## Product definition

Dream Pinball is a Roblox game being created by Gabe and his son.

The gameplay concept, target devices, multiplayer model, progression, monetization, and first-playable success criteria have not been defined yet. Record those decisions here before implementing dependent systems.

## Development workflow

- Roblox Studio is the authority for visual objects, terrain, physics tuning, animation placement, audio placement, and publishing.
- Git-tracked `.luau` files are the authority for synchronized scripts.
- Roblox Script Sync connects the directories under `src/` to their corresponding Studio services.

## Source boundaries

| Local directory | Roblox Studio destination | Intended contents |
| --- | --- | --- |
| `src/ReplicatedStorage` | `ReplicatedStorage` | Shared modules and remotes |
| `src/ServerScriptService` | `ServerScriptService` | Server-authoritative systems |
| `src/StarterPlayerScripts` | `StarterPlayerScripts` | Client controllers and input |
| `src/StarterGui` | `StarterGui` | UI scripts |

## Security boundary

Clients request actions. The server validates permissions, state, ranges, timing, and values before changing authoritative game state.

## Decisions

Add confirmed architectural and product decisions here. Do not use this section as a wishlist.
