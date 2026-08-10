--!strict

--- Fixed/angled camera for in-level table view, active ONLY while the local
--- player has an active run on a cabinet. The server fires
--- CameraControlRemote with a CFrame when the player presses a cabinet's
--- "Start Level" prompt, and with nil once that cabinet's turn state
--- resolves to Won or Lost (or the player is bumped by someone else
--- starting a new level) -- see CabinetDesignsTest.server.luau's
--- startLevel/unlockMovementIfGameOver. Outside of an active run, the
--- player's normal camera controls are left untouched.
---
--- Reads Workspace.CurrentCamera fresh every time instead of caching it once,
--- because Roblox replaces CurrentCamera with a new Camera instance when the
--- character spawns -- a script that grabs it only at startup ends up
--- modifying a camera nobody is looking through anymore.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local CameraRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("CameraControl"))

local fixedCFrame: CFrame? = nil

local function applyCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if fixedCFrame then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = fixedCFrame
	elseif camera.CameraType == Enum.CameraType.Scriptable then
		-- Hand control back to the player once a run ends -- Custom is
		-- Roblox's normal player-controlled camera type.
		camera.CameraType = Enum.CameraType.Custom
	end
end

local cameraRemote = CameraRemotes.getCameraControlRemote()
cameraRemote.OnClientEvent:Connect(function(cframe: unknown)
	fixedCFrame = if typeof(cframe) == "CFrame" then cframe else nil
	applyCamera()
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyCamera)

RunService.RenderStepped:Connect(function()
	if fixedCFrame then
		applyCamera()
	end
end)
