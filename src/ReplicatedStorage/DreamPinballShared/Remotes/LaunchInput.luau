--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "LaunchInputRemote"

--- Client fires this with no arguments to request a LAUNCH. The server owns
--- the RemoteEvent instance and validates the request against current turn
--- state before spawning a ball.
local LaunchRemotes = {}

function LaunchRemotes.getLaunchInputRemote(): RemoteEvent
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

return LaunchRemotes
