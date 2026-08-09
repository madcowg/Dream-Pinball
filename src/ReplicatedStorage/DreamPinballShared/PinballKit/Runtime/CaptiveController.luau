--!strict

-- Runtime behavior for a generated captive-ball pocket
-- (Generators/CaptiveGenerator.luau): capture on the occupancy trigger, wait
-- CaptureDelaySeconds, then kick the ball out. Configure KickDirectionLocal
-- mostly-up for a kickout hole/VUK, or mostly-horizontal (toward the plunger
-- lane) for a ball trough/drain feed -- same controller, different config.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local CaptiveController = {}

export type CaptiveControllerConfig = {
	CaptureDelaySeconds: number?,
	KickStrength: number?,
	KickDirectionLocal: Vector3?,
	CooldownSeconds: number?,
}

local DEFAULT_CAPTURE_DELAY_SECONDS = 0.6
local DEFAULT_KICK_STRENGTH = 55
local DEFAULT_KICK_DIRECTION_LOCAL = Vector3.new(0, 1, 0.3)
local DEFAULT_COOLDOWN_SECONDS = 1

export type CaptivePocketAssetLike = {
	Model: Model,
	OccupancyTrigger: BasePart,
}

function CaptiveController.Attach(
	asset: CaptivePocketAssetLike,
	config: CaptiveControllerConfig?,
	onCapture: ((BasePart) -> ())?,
	onKick: ((BasePart) -> ())?,
	isBall: ((BasePart) -> boolean)?
): Types.Controller
	local resolvedConfig = config or {}
	local captureDelay = resolvedConfig.CaptureDelaySeconds or DEFAULT_CAPTURE_DELAY_SECONDS
	local kickStrength = resolvedConfig.KickStrength or DEFAULT_KICK_STRENGTH
	local kickDirectionLocal = resolvedConfig.KickDirectionLocal or DEFAULT_KICK_DIRECTION_LOCAL
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS

	local state = ComponentRegistry.NewState(asset.Model)
	local occupied = false

	local function kickOut(ball: BasePart)
		if state.Destroyed or not ball.Parent then
			return
		end

		local pivot = asset.Model:GetPivot()
		local kickDirectionWorld = pivot:VectorToWorldSpace(kickDirectionLocal).Unit

		-- Zero the existing velocity first so the kick is a clean, repeatable
		-- launch rather than adding on top of whatever momentum carried the
		-- ball in -- matches a real kickout's "ball stops completely, then
		-- fires" behavior.
		ball.AssemblyLinearVelocity = kickDirectionWorld * kickStrength

		occupied = false
		if onKick ~= nil then
			onKick(ball)
		end
	end

	local function onCaptured(ball: BasePart)
		if occupied then
			return
		end
		if not ComponentRegistry.CheckGlobalCooldown(state, cooldown) then
			return
		end

		occupied = true
		if onCapture ~= nil then
			onCapture(ball)
		end

		task.delay(captureDelay, function()
			if not state.Destroyed then
				kickOut(ball)
			end
		end)
	end

	ComponentRegistry.ConnectTouched(state, asset.OccupancyTrigger, onCaptured, isBall)

	return {
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				onCaptured(ball)
			end
		end,
		Reset = function(_self)
			occupied = false
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return CaptiveController
