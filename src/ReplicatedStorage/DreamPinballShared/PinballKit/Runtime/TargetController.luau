--!strict

-- Runtime state machine for a generated hideaway target
-- (Generators/TargetGenerator.luau): Up -> Retracting -> Hidden -> Raising ->
-- Up. Every state transition cancels whatever tween is currently running
-- before starting a new one, so a manual Reset() interrupting an in-progress
-- retraction (or a new hit interrupting a reset) can never leave two tweens
-- fighting over the same part.

local TweenService = game:GetService("TweenService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local TargetController = {}

export type TargetState = "Up" | "Retracting" | "Hidden" | "Raising"

export type TargetControllerConfig = {
	HitThreshold: number?,
	AutoResetDelaySeconds: number?,
	RetractTweenTime: number?,
	RaiseTweenTime: number?,
	CooldownSeconds: number?,
}

local DEFAULT_RETRACT_TWEEN_TIME = 0.12
local DEFAULT_RAISE_TWEEN_TIME = 0.2
local DEFAULT_COOLDOWN_SECONDS = 0.5

export type TargetAssetLike = {
	Model: Model,
	TargetFace: BasePart,
	RaisedCFrame: CFrame,
	TravelDirectionWorld: Vector3,
	TravelDistance: number,
	Light: PointLight?,
}

export type TargetHandle = Types.Controller & {
	GetState: (self: TargetHandle) -> TargetState,
}

function TargetController.Attach(
	asset: TargetAssetLike,
	config: TargetControllerConfig?,
	onHit: ((BasePart) -> ())?,
	isBall: ((BasePart) -> boolean)?
): TargetHandle
	local resolvedConfig = config or {}
	local hitThreshold = resolvedConfig.HitThreshold or 0
	local autoResetDelay = resolvedConfig.AutoResetDelaySeconds
	local retractTweenTime = resolvedConfig.RetractTweenTime or DEFAULT_RETRACT_TWEEN_TIME
	local raiseTweenTime = resolvedConfig.RaiseTweenTime or DEFAULT_RAISE_TWEEN_TIME
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS

	local state = ComponentRegistry.NewState(asset.Model)
	local currentState: TargetState = "Up"
	local activeTween: Tween? = nil
	local autoResetGeneration = 0

	local hiddenCFrame = asset.RaisedCFrame + (asset.TravelDirectionWorld * asset.TravelDistance)

	local function cancelActiveTween()
		if activeTween ~= nil then
			activeTween:Cancel()
			activeTween = nil
		end
	end

	local function setLight(enabled: boolean)
		if asset.Light ~= nil then
			asset.Light.Enabled = enabled
		end
	end

	local retract: () -> ()
	local raise: () -> ()

	retract = function()
		cancelActiveTween()
		currentState = "Retracting"
		autoResetGeneration += 1
		local thisGeneration = autoResetGeneration

		local tween = TweenService:Create(
			asset.TargetFace,
			TweenInfo.new(retractTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = hiddenCFrame }
		)
		activeTween = tween

		tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if state.Destroyed or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			asset.TargetFace.CanCollide = false
			currentState = "Hidden"

			if autoResetDelay ~= nil then
				task.delay(autoResetDelay, function()
					if not state.Destroyed and autoResetGeneration == thisGeneration and currentState == "Hidden" then
						raise()
					end
				end)
			end
		end)

		tween:Play()
	end

	raise = function()
		cancelActiveTween()
		autoResetGeneration += 1
		currentState = "Raising"
		asset.TargetFace.CanCollide = true

		local tween = TweenService:Create(
			asset.TargetFace,
			TweenInfo.new(raiseTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = asset.RaisedCFrame }
		)
		activeTween = tween

		tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if state.Destroyed or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			currentState = "Up"
		end)

		tween:Play()
		setLight(false)
	end

	local function onTouch(ball: BasePart)
		if currentState ~= "Up" then
			return
		end

		if hitThreshold > 0 and ball.AssemblyLinearVelocity.Magnitude < hitThreshold then
			return
		end

		if not ComponentRegistry.CheckGlobalCooldown(state, cooldown) then
			return
		end

		setLight(true)

		if onHit ~= nil then
			onHit(ball)
		end

		retract()
	end

	ComponentRegistry.ConnectTouched(state, asset.TargetFace, onTouch, isBall)

	local handle: TargetHandle = {
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				onTouch(ball)
			end
		end,
		Reset = function(_self)
			raise()
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			cancelActiveTween()
			ComponentRegistry.Destroy(state)
		end,
		GetState = function(_self)
			return currentState
		end,
	}

	return handle
end

return TargetController
