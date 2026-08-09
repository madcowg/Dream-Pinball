--!strict

-- Runtime behavior for a generated Spinner (Generators/SpinnerGenerator.luau):
-- angular-velocity-based spin detection with a configurable threshold and
-- cooldown. The paddle's rotation itself is pure physics (HingeConstraint) --
-- this controller only watches it and reports qualifying spins; it never sets
-- the paddle's rotation or velocity directly.

local RunService = game:GetService("RunService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local SpinnerController = {}

export type SpinnerControllerConfig = {
	ScoreThresholdRadPerSecond: number?,
	CooldownSeconds: number?,
}

local DEFAULT_SCORE_THRESHOLD_RAD_PER_SECOND = 8
local DEFAULT_COOLDOWN_SECONDS = 0.3

export type SpinnerHandle = Types.Controller & {
	Paddle: BasePart,
}

function SpinnerController.Attach(
	paddle: BasePart,
	config: SpinnerControllerConfig?,
	onSpin: ((BasePart, number) -> ())?
): SpinnerHandle
	local resolvedConfig = config or {}
	local threshold = resolvedConfig.ScoreThresholdRadPerSecond or DEFAULT_SCORE_THRESHOLD_RAD_PER_SECOND
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS

	local model = paddle:FindFirstAncestorOfClass("Model")
	if model == nil then
		error("SpinnerController.Attach: paddle must be a descendant of a Model (the generated Spinner asset)", 0)
	end

	local state = ComponentRegistry.NewState(model)

	local heartbeatConnection = RunService.Heartbeat:Connect(function()
		if state.Destroyed or not state.Enabled then
			return
		end

		local angularSpeed = paddle.AssemblyAngularVelocity.Magnitude
		if angularSpeed < threshold then
			return
		end

		if not ComponentRegistry.CheckGlobalCooldown(state, cooldown) then
			return
		end

		if onSpin ~= nil then
			onSpin(paddle, angularSpeed)
		end
	end)

	ComponentRegistry.TrackConnection(state, heartbeatConnection)

	local handle: SpinnerHandle = {
		Paddle = paddle,
		Activate = function(_self, _ball, _context)
			-- Spinners activate purely from physical contact (see module doc
			-- comment) -- Activate is a no-op, present only to satisfy the
			-- shared Controller interface for registries that call it uniformly.
		end,
		Reset = function(_self)
			state.LastActivationGlobal = nil
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}

	return handle
end

return SpinnerController
