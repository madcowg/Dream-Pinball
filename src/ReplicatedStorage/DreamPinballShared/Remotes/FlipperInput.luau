--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "FlipperInputRemote"

--- Client fires this with (side: "Left" | "Right", pressed: boolean). The
--- server owns the RemoteEvent instance and must validate both arguments --
--- never trust client-provided values.
local FlipperRemotes = {}

export type Side = "Left" | "Right"

-- Shared validation for this remote's payload, so every server-side listener
-- (WilliamsCabinet.server.luau, PinballMechanisms.luau) rejects the exact
-- same malformed payloads instead of maintaining two independent copies of
-- the same typeof/equality checks that could silently drift apart. Returns
-- the narrowed (side, pressed) pair, or nil if invalid.
function FlipperRemotes.ValidateInput(side: unknown, pressed: unknown): (Side?, boolean?)
	if typeof(side) ~= "string" or (side ~= "Left" and side ~= "Right") then
		return nil, nil
	end
	if typeof(pressed) ~= "boolean" then
		return nil, nil
	end
	return side :: Side, pressed
end

function FlipperRemotes.getFlipperInputRemote(): RemoteEvent
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = ReplicatedStorage
		return remote
	end

	return ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent
end

return FlipperRemotes
