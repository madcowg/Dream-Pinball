--!strict

--- Temporary test trigger for the LAUNCH action (build order step 7) -- no
--- action menu UI exists yet (that's step 13), so pressing R stands in for
--- choosing LAUNCH from the menu. Hold R to charge launch power (like
--- pulling back a plunger spring), release to fire -- server validates
--- whether a launch is actually allowed and clamps the power value.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local LaunchRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("LaunchInput"))

local remote = LaunchRemotes.getLaunchInputRemote()

local CHARGE_MAX_SECONDS = 1.5
local MIN_POWER = 0.2 -- a quick tap still launches, just weakly

local chargeStartTime: number? = nil

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R and not chargeStartTime then
		chargeStartTime = tick()
		remote:FireServer("charge")
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.KeyCode ~= Enum.KeyCode.R or not chargeStartTime then
		return
	end

	local heldSeconds = tick() - chargeStartTime
	chargeStartTime = nil

	local power = math.clamp(heldSeconds / CHARGE_MAX_SECONDS, MIN_POWER, 1)
	remote:FireServer("release", power)
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
