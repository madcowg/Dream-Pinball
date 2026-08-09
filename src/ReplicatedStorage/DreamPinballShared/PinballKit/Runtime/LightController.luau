--!strict

-- Runtime state (Off/On/Pulse/Blink) for a generated light/insert/bar/ring
-- (Generators/LightGenerator.luau), plus a shared sequence runner for groups.
-- Every state change cancels whatever loop/tween is currently running before
-- starting the next one (a monotonically increasing generation counter, the
-- standard Luau cancellation idiom -- the old loop's `while generation ==
-- myGeneration` check fails on its next iteration and the coroutine ends
-- itself) so a component is never driven by two competing animations, and a
-- component never accumulates more than one live loop.

local TweenService = game:GetService("TweenService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local LightController = {}

export type LightControllerConfig = {
	OnColor: Color3?,
	OffColor: Color3?,
	PulseTime: number?,
	BlinkInterval: number?,
}

local DEFAULT_PULSE_TIME = 0.9
local DEFAULT_BLINK_INTERVAL = 0.35

export type LightAssetLike = {
	Model: Model,
	InsertParts: { BasePart },
	Light: (PointLight | SurfaceLight)?,
}

export type LightHandle = Types.Controller & {
	SetLit: (self: LightHandle, enabled: boolean) -> (),
	SetLightState: (self: LightHandle, lightState: Types.LightState) -> (),
	SetColor: (self: LightHandle, color: Color3) -> (),
}

function LightController.Attach(asset: LightAssetLike, config: LightControllerConfig?): LightHandle
	local resolvedConfig = config or {}
	local onColor = resolvedConfig.OnColor or Color3.fromRGB(255, 220, 80)
	local offColor = resolvedConfig.OffColor or Color3.fromRGB(60, 55, 40)
	local pulseTime = resolvedConfig.PulseTime or DEFAULT_PULSE_TIME
	local blinkInterval = resolvedConfig.BlinkInterval or DEFAULT_BLINK_INTERVAL
	local baseBrightness = if asset.Light ~= nil then asset.Light.Brightness else 2

	local state = ComponentRegistry.NewState(asset.Model)
	local generation = 0
	local activeTween: Tween? = nil
	local currentColor = onColor

	local function applyInsertColor(color: Color3)
		local brickColor = BrickColor.new(color)
		for _, part in ipairs(asset.InsertParts) do
			part.BrickColor = brickColor
		end
	end

	local function cancelLoop()
		generation += 1
		if activeTween ~= nil then
			activeTween:Cancel()
			activeTween = nil
		end
	end

	local function setEnabled(enabled: boolean)
		if asset.Light ~= nil then
			asset.Light.Enabled = enabled
		end
		applyInsertColor(enabled and currentColor or offColor)
	end

	local handle: LightHandle
	handle = {
		SetLit = function(_self, enabled: boolean)
			cancelLoop()
			setEnabled(enabled)
		end,
		SetColor = function(_self, color: Color3)
			currentColor = color
			if asset.Light ~= nil then
				asset.Light.Color = color
			end
			if asset.Light == nil or asset.Light.Enabled then
				applyInsertColor(color)
			end
		end,
		SetLightState = function(_self, lightState: Types.LightState)
			cancelLoop()
			local myGeneration = generation

			if lightState == "Off" then
				setEnabled(false)
			elseif lightState == "On" then
				setEnabled(true)
			elseif lightState == "Pulse" then
				if asset.Light == nil then
					setEnabled(true)
					return
				end
				asset.Light.Enabled = true
				applyInsertColor(currentColor)
				local tween = TweenService:Create(
					asset.Light,
					TweenInfo.new(pulseTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Brightness = baseBrightness * 0.15 }
				)
				activeTween = tween
				tween:Play()
			elseif lightState == "Blink" then
				task.spawn(function()
					local lit = false
					while generation == myGeneration and not state.Destroyed do
						lit = not lit
						setEnabled(lit)
						task.wait(blinkInterval)
					end
				end)
			end
		end,
		Activate = function(_self, _ball, _context)
			handle:SetLightState("On")
		end,
		Reset = function(_self)
			handle:SetLightState("Off")
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
			if not enabled then
				cancelLoop()
				setEnabled(false)
			end
		end,
		Destroy = function(_self)
			cancelLoop()
			ComponentRegistry.Destroy(state)
		end,
	}

	setEnabled(false)

	return handle
end

-- Lights `handles` one at a time, `stepSeconds` apart, optionally looping.
-- One coroutine drives the whole sequence regardless of how many lights are
-- in it. Returns a stop function; calling it ends the sequence after the
-- current step (previously-lit components are left in whatever state they
-- were in -- call SetLightState("Off") on the group afterward if a clean
-- blackout is wanted).
function LightController.RunSequence(handles: { LightHandle }, stepSeconds: number, loop: boolean?): () -> ()
	local stopped = false

	task.spawn(function()
		repeat
			for _, handle in ipairs(handles) do
				if stopped then
					break
				end
				handle:SetLightState("On")
				task.wait(stepSeconds)
				handle:SetLightState("Off")
			end
		until stopped or not loop
	end)

	return function()
		stopped = true
	end
end

return LightController
