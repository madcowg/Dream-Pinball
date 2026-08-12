--!strict

-- Runtime behavior for a generated standup target
-- (Generators/TargetGenerator.GenerateStandup). No state machine -- the
-- target never moves -- just cooldown-protected hit detection and an
-- optional light flash.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local StandupTargetController = {}

export type StandupTargetControllerConfig = {
	CooldownSeconds: number?,
	FlashSeconds: number?,
}

local DEFAULT_COOLDOWN_SECONDS = 0.3
local DEFAULT_FLASH_SECONDS = 0.15

export type StandupTargetAssetLike = {
	Model: Model,
	TargetFace: BasePart,
	Light: PointLight?,
}

function StandupTargetController.Attach(
	asset: StandupTargetAssetLike,
	config: StandupTargetControllerConfig?,
	onHit: ((BasePart) -> ())?,
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

		if onHit ~= nil then
			onHit(ball)
		end
	end

	ComponentRegistry.ConnectTouched(state, asset.TargetFace, onTouch, isBall)

	return {
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				onTouch(ball)
			end
		end,
		Reset = function(_self)
			ComponentRegistry.ClearBallActivations(state)
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return StandupTargetController
