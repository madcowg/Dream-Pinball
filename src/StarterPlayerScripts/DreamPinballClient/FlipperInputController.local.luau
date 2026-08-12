--!strict

--- Sends raw press-state to the server. Applies no physics itself -- the
--- server owns and validates all flipper physics.
---
--- One shared hook for anything else that wants to drive the same remote
--- (spec section 15's "physical cabinet button integration hook"): any
--- script with access to Remotes/FlipperInput.luau can already call
--- `FlipperRemotes.getFlipperInputRemote():FireServer(side, pressed)` with
--- this exact payload -- e.g. a future physical-button prop's own LocalScript
--- (a ClickDetector/ProximityPrompt handler). No separate export is added
--- here: this file stays a LocalScript per architecture.md's locked
--- "Client script folder structure," and the remote itself IS the shared
--- hook, per this project's own "one shared remote, not one per input" rule.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local FlipperRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("FlipperInput"))

local remote = FlipperRemotes.getFlipperInputRemote()

local function fireInput(side: string, pressed: boolean)
	remote:FireServer(side, pressed)
end

-- Natural mapping, and this is the ONLY correct place for it: Q = "Left",
-- E = "Right". Q is the physically-left flipper's key; E is the
-- physically-right flipper's key. Full stop -- this is a labeling fact, not
-- a tuning knob, and must never be inverted to compensate for a wiring bug
-- elsewhere (a hinge/pivot-naming mixup does not change which key a player
-- expects to control which side). Confirmed live in Studio (2026-08-12
-- session) that WilliamsCabinet's and WilliamsCabinetPlayground's flippers
-- responded backwards under this exact mapping -- the actual defect was in
-- the hinge sweep direction, not here; see CabinetBuilder.luau's
-- SWEEP_DIRECTION table and architecture.md's "Flipper baseline" section for
-- where that fix lives.
local KEY_TO_SIDE: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Q] = "Left",
	[Enum.KeyCode.E] = "Right",
}

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local side = KEY_TO_SIDE[input.KeyCode]
	if side then
		fireInput(side, true)
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	local side = KEY_TO_SIDE[input.KeyCode]
	if side then
		fireInput(side, false)
	end
end

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)

-- Gamepad + touch (spec section 15), via ContextActionService -- natural
-- mapping, same convention as KEY_TO_SIDE above (see its comment): L1/L2
-- (physically left) sends "Left", R1/R2 (physically right) sends "Right".
-- `createTouchButton = true` gives every player a working on-screen touch
-- control for free.
local ACTION_LEFT_FLIPPER = "PinballFlipperLeft"
local ACTION_RIGHT_FLIPPER = "PinballFlipperRight"

local function onFlipperAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	local side = if actionName == ACTION_LEFT_FLIPPER then "Left" else "Right"

	if inputState == Enum.UserInputState.Begin then
		fireInput(side, true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		fireInput(side, false)
	end

	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction(ACTION_LEFT_FLIPPER, onFlipperAction, true, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonL2)
ContextActionService:BindAction(ACTION_RIGHT_FLIPPER, onFlipperAction, true, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle(ACTION_LEFT_FLIPPER, "Left Flipper")
ContextActionService:SetTitle(ACTION_RIGHT_FLIPPER, "Right Flipper")
