--!strict

-- Runtime behavior for a generated rollover lane switch
-- (Generators/ObstacleGenerator.GenerateRollover): the ball rolls straight
-- over it (CanCollide is false -- see the generator), this just detects the
-- pass-over and optionally flashes a light. Rubber posts need no controller
-- at all -- their bounce is pure passive physics.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local RolloverController = {}

export type RolloverControllerConfig = {
	CooldownSeconds: number?,
	FlashSeconds: number?,
}

local DEFAULT_COOLDOWN_SECONDS = 0.5
local DEFAULT_FLASH_SECONDS = 0.2

export type RolloverAssetLike = {
	Model: Model,
	Switch: BasePart,
	Light: PointLight?,
}

function RolloverController.Attach(
	asset: RolloverAssetLike,
	config: RolloverControllerConfig?,
	onRollover: ((BasePart) -> ())?,
	isBall: ((BasePart) -> boolean)?
): Types.Controller
	local resolvedConfig = config or {}
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS
	local flashSeconds = resolvedConfig.FlashSeconds or DEFAULT_FLASH_SECONDS

	local state = ComponentRegistry.NewState(asset.Model)

	local function onTouch(ball: BasePart)
		if not ComponentRegistry.CheckBallCooldown(state, ball, cooldown) then
			return
		end

		if asset.Light ~= nil then
			asset.Light.Enabled = true
			task.delay(flashSeconds, function()
				if not state.Destroyed and asset.Light ~= nil then
					asset.Light.Enabled = false
				end
			end)
		end

		if onRollover ~= nil then
			onRollover(ball)
		end
	end

	ComponentRegistry.ConnectTouched(state, asset.Switch, onTouch, isBall)

	return {
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				onTouch(ball)
			end
		end,
		Reset = function(_self)
			state.LastActivationByBall = {}
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return RolloverController
