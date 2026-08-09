--!strict

-- Runtime behavior for a generated cabinet button
-- (Generators/ButtonGenerator.luau). Must be attached from server-side code --
-- ProximityPrompt.Triggered is what supplies the "server-validated activation
-- event" spec section 9 asks for, and that guarantee only holds when this
-- runs on the server.

local TweenService = game:GetService("TweenService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local ButtonController = {}

export type ButtonControllerConfig = {
	DebounceSeconds: number?,
	PressTweenTime: number?,
}

local DEFAULT_DEBOUNCE_SECONDS = 0.4
local DEFAULT_PRESS_TWEEN_TIME = 0.06

export type ButtonAssetLike = {
	Model: Model,
	Cap: BasePart,
	RestCFrame: CFrame,
	PressTravel: number,
	Prompt: ProximityPrompt,
	Light: PointLight?,
}

export type ButtonHandle = Types.Controller & {
	SetLit: (self: ButtonHandle, enabled: boolean) -> (),
}

function ButtonController.Attach(
	asset: ButtonAssetLike,
	config: ButtonControllerConfig?,
	onPressed: ((Player) -> ())?
): ButtonHandle
	local resolvedConfig = config or {}
	local debounceSeconds = resolvedConfig.DebounceSeconds or DEFAULT_DEBOUNCE_SECONDS
	local tweenTime = resolvedConfig.PressTweenTime or DEFAULT_PRESS_TWEEN_TIME

	local state = ComponentRegistry.NewState(asset.Model)
	local pressedCFrame = asset.RestCFrame * CFrame.new(0, -asset.PressTravel, 0)
	local activeTween: Tween? = nil

	local function playPress()
		if activeTween ~= nil then
			activeTween:Cancel()
		end

		asset.Cap.CFrame = pressedCFrame

		local returnTween = TweenService:Create(
			asset.Cap,
			TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = asset.RestCFrame }
		)
		activeTween = returnTween
		returnTween:Play()
	end

	local promptConnection = asset.Prompt.Triggered:Connect(function(player: Player)
		if state.Destroyed or not state.Enabled then
			return
		end

		if not ComponentRegistry.CheckGlobalCooldown(state, debounceSeconds) then
			return
		end

		playPress()

		if onPressed ~= nil then
			onPressed(player)
		end
	end)
	ComponentRegistry.TrackConnection(state, promptConnection)

	return {
		SetLit = function(_self, enabled: boolean)
			if asset.Light ~= nil then
				asset.Light.Enabled = enabled
			end
		end,
		Activate = function(_self, _ball, context)
			if context ~= nil and context.Player ~= nil then
				playPress()
				if onPressed ~= nil then
					onPressed(context.Player :: Player)
				end
			end
		end,
		Reset = function(_self)
			if activeTween ~= nil then
				activeTween:Cancel()
			end
			asset.Cap.CFrame = asset.RestCFrame
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
			asset.Prompt.Enabled = enabled
		end,
		Destroy = function(_self)
			if activeTween ~= nil then
				activeTween:Cancel()
			end
			ComponentRegistry.Destroy(state)
		end,
	} :: ButtonHandle
end

return ButtonController
