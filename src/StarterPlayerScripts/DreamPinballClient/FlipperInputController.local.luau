--!strict

--- Sends raw Q/E press-state to the server. Applies no physics itself --
--- the server owns and validates all flipper physics.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))

local remote = FlipperRemotes.getFlipperInputRemote()

-- Confirmed working visually with CabinetBuilder's original (unswapped)
-- pivot placement -- do not touch CabinetBuilder.luau's Left/Right pivot
-- assignment to "fix" this further; changing it broke the rest of the
-- layout. This key mapping is the only piece that should change.
local KEY_TO_SIDE: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Q] = "Right",
	[Enum.KeyCode.E] = "Left",
}

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local side = KEY_TO_SIDE[input.KeyCode]
	if side then
		remote:FireServer(side, true)
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	local side = KEY_TO_SIDE[input.KeyCode]
	if side then
		remote:FireServer(side, false)
	end
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
