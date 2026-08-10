--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "FlipperInputRemote"

--- Client fires this with (side: "Left" | "Right", pressed: boolean). The
--- server owns the RemoteEvent instance and must validate both arguments --
--- never trust client-provided values.
local FlipperRemotes = {}

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
