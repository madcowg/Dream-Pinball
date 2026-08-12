--!strict

-- Runtime behavior for a generated LaneDivider's rollover trigger
-- (Generators/LaneGenerator.luau): reports ball passes through a caller-
-- supplied callback and drives the divider's small indicator light. What a
-- rollover actually DOES (points, extra ball, saved ball, nothing) is
-- deliberately not decided here -- that changes per level, so this module
-- only reports the event and lets whoever owns the current level's rules
-- attach a callback (or not).

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local LightController = require(script.Parent.LightController)
local Types = require(script.Parent.Parent.Types)
local LaneGenerator = require(script.Parent.Parent.Generators.LaneGenerator)

local LaneController = {}

export type LaneControllerConfig = {
	CooldownSeconds: number?,
}

local DEFAULT_COOLDOWN_SECONDS = 0.5

export type LaneHandle = Types.Controller & {
	SetTriggerLit: (self: LaneHandle, enabled: boolean) -> (),
	SetTriggerLightState: (self: LaneHandle, lightState: Types.LightState) -> (),
}

function LaneController.Attach(asset: LaneGenerator.LaneDividerAsset, config: LaneControllerConfig?, onPass: ((BasePart) -> ())?): LaneHandle
	local resolvedConfig = config or {}
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS

	if asset.Trigger == nil then
		error("LaneController.Attach: this LaneDividerAsset has no Trigger -- it was generated with Config.IncludeTrigger = false", 0)
	end
	local trigger = asset.Trigger :: BasePart

	local state = ComponentRegistry.NewState(asset.Model)

	local lightHandle = if asset.TriggerLight ~= nil then LightController.Attach(asset.TriggerLight) else nil

	ComponentRegistry.ConnectTouched(state, trigger, function(otherPart: BasePart)
		if not ComponentRegistry.CheckBallCooldown(state, otherPart, cooldown) then
			return
		end
		if onPass ~= nil then
			onPass(otherPart)
		end
	end)

	local handle: LaneHandle
	handle = {
		SetTriggerLit = function(_self, enabled: boolean)
			if lightHandle ~= nil then
				lightHandle:SetLit(enabled)
			end
		end,
		SetTriggerLightState = function(_self, lightState: Types.LightState)
			if lightHandle ~= nil then
				lightHandle:SetLightState(lightState)
			end
		end,
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil and onPass ~= nil then
				onPass(ball)
			end
		end,
		Reset = function(_self)
			ComponentRegistry.ClearBallActivations(state)
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			if lightHandle ~= nil then
				lightHandle:Destroy()
			end
			ComponentRegistry.Destroy(state)
		end,
	}

	return handle
end

return LaneController
