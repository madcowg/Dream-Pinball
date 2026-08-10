--!strict

--- Temporary test trigger for the ITEM action (build order step 8) -- no
--- action menu UI exists yet, so pressing 1-5 stands in for choosing an
--- item from the menu. Server validates the item id, inventory count, and
--- per-turn item allowance before applying anything.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local ItemRemotes = require(DreamPinballShared:WaitForChild("Remotes"):WaitForChild("ItemInput"))

local remote = ItemRemotes.getItemInputRemote()

local KEY_TO_ITEM_ID: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Feather",
	[Enum.KeyCode.Two] = "Coffee",
	[Enum.KeyCode.Three] = "ExtraBall",
	[Enum.KeyCode.Four] = "Magnet",
	[Enum.KeyCode.Five] = "Hammer",
}

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	local itemId = KEY_TO_ITEM_ID[input.KeyCode]
	if itemId then
		remote:FireServer(itemId)
	end
end

UserInputService.InputBegan:Connect(onInputBegan)
