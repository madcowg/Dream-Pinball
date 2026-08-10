--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "ItemInputRemote"

--- Client fires this with (itemId: string). The server validates the id,
--- inventory count, and per-turn item allowance before applying anything.
local ItemRemotes = {}

function ItemRemotes.getItemInputRemote(): RemoteEvent
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

return ItemRemotes
