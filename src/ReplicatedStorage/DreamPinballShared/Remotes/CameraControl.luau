--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "CameraControlRemote"

--- Server fires this at a specific player to activate (payload: CFrame) or
--- deactivate (payload: nil) the fixed in-level camera. Fired with a CFrame
--- when that player starts a level on a cabinet (see CabinetDesignsTest's
--- StartLevelPrompt), and with nil once that cabinet's turn state resolves
--- to Won or Lost -- the camera stays fixed for exactly the duration of one
--- play session, not permanently.
local CameraRemotes = {}

function CameraRemotes.getCameraControlRemote(): RemoteEvent
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

return CameraRemotes
