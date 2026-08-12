--!strict

-- Generic flipper-input dispatcher for any LowerPlayfieldGenerator-based
-- cabinet (spec section 15). A plain ModuleScript, not a `.server.luau`
-- Script -- it must be require()-able so a future cabinet's own server script
-- can call RegisterCabinet on it, the same reason PinballKit's other Runtime
-- controllers are modules rather than standalone scripts.
--
-- WilliamsCabinet.server.luau keeps its own separate OnServerEvent listener
-- on the SAME shared FlipperInputRemote and is never touched by this module
-- -- both listeners coexist independently, each with its own ownership check,
-- exactly how Remotes/FlipperInput.luau's "one shared remote" rule is meant
-- to scale to more than one cabinet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))

local PinballMechanisms = {}

export type Side = "Left" | "Right"

export type CabinetHandle = {
	Press: (self: any, side: Side) -> (),
	Release: (self: any, side: Side) -> (),
}

type CabinetEntry = {
	Handle: CabinetHandle,
	OwnerCheck: (player: Player) -> boolean,
}

local registry: { [string]: CabinetEntry } = {}
-- Keyed by "<UserId>:<Side>", not just the player -- a single per-player key
-- meant a fast Left-press followed immediately by a Right-press (or by that
-- same side's release) could get rejected by the OTHER side/transition's
-- timestamp. Presses are rate-limited; releases never are (dropping a
-- release is worse than a client getting one extra release through -- it
-- leaves a flipper permanently commanded "pressed" server-side).
local lastPressTimestampByPlayerSide: { [string]: number } = {}
local initialized = false

-- Minimum spacing between accepted PRESS fires from the same player+side --
-- rejects a misbehaving/malicious client spamming the remote far faster than
-- any real flipper press could repeat (spec section 15: "Rate-limit remote
-- state changes").
local RATE_LIMIT_WINDOW_SECONDS = 0.05

-- Registers a cabinet's LowerPlayfieldController handle under `cabinetId`.
-- `ownerCheck(player)` decides whether a given player's input applies to
-- THIS cabinet -- same pattern as WilliamsCabinet.server.luau's own
-- `gameplay.IsEngagedBy`, just generalized to a registry instead of one
-- hardcoded cabinet.
function PinballMechanisms.RegisterCabinet(cabinetId: string, handle: CabinetHandle, ownerCheck: (player: Player) -> boolean)
	registry[cabinetId] = { Handle = handle, OwnerCheck = ownerCheck }
end

function PinballMechanisms.UnregisterCabinet(cabinetId: string)
	registry[cabinetId] = nil
end

local function onFlipperInput(player: Player, side: unknown, pressed: unknown)
	-- Validate before touching anything else -- never trust client-provided
	-- values (Remotes/FlipperInput.luau's own doc comment).
	local resolvedSide, resolvedPressed = FlipperRemotes.ValidateInput(side, pressed)
	if resolvedSide == nil or resolvedPressed == nil then
		return
	end

	if resolvedPressed then
		local key = tostring(player.UserId) .. ":" .. resolvedSide
		local now = os.clock()
		local lastFire = lastPressTimestampByPlayerSide[key]
		if lastFire ~= nil and (now - lastFire) < RATE_LIMIT_WINDOW_SECONDS then
			return
		end
		lastPressTimestampByPlayerSide[key] = now
	end

	-- A player is only ever meaningfully engaged with one cabinet at a time
	-- (each OwnerCheck answers "is this THIS cabinet's player" -- see the doc
	-- comment above). Stop at the first match instead of firing every
	-- registered cabinet whose OwnerCheck happens to also return true for
	-- this player, so one overly-permissive OwnerCheck (e.g. a standalone
	-- test rig) can only ever claim the input, never pile additional
	-- cabinets' reactions on top of the real one's.
	for _, entry in pairs(registry) do
		if entry.OwnerCheck(player) then
			if resolvedPressed then
				entry.Handle:Press(resolvedSide)
			else
				entry.Handle:Release(resolvedSide)
			end
			break
		end
	end
end

-- Idempotent: safe to call from multiple require()s of this module.
function PinballMechanisms.Init()
	if initialized then
		return
	end
	initialized = true

	FlipperRemotes.getFlipperInputRemote().OnServerEvent:Connect(onFlipperInput)

	Players.PlayerRemoving:Connect(function(player: Player)
		local userIdPrefix = tostring(player.UserId) .. ":"
		lastPressTimestampByPlayerSide[userIdPrefix .. "Left"] = nil
		lastPressTimestampByPlayerSide[userIdPrefix .. "Right"] = nil
		-- Release every cabinet's flippers for this player, in case they
		-- disconnect mid-press -- spec section 15: "Release both flippers when
		-- ... the player leaves."
		for _, entry in pairs(registry) do
			if entry.OwnerCheck(player) then
				entry.Handle:Release("Left")
				entry.Handle:Release("Right")
			end
		end
	end)
end

return PinballMechanisms
