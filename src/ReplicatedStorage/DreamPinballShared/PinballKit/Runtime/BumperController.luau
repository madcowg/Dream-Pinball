--!strict

-- Runtime behavior for a generated Bumper (Generators/BumperGenerator.luau):
-- radial activation from the skirt trigger, an outward+upward kick aimed from
-- the bumper's center through the ball's horizontal position, a compression
-- animation on the cap, and cooldown/duplicate-hit protection.

local TweenService = game:GetService("TweenService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local BumperController = {}

export type BumperControllerConfig = {
	OutwardImpulse: number?,
	UpwardImpulse: number?,
	CooldownSeconds: number?,
	CompressionTweenTime: number?,
}

local DEFAULT_OUTWARD_IMPULSE = 45
local DEFAULT_UPWARD_IMPULSE = 6
local DEFAULT_COOLDOWN_SECONDS = 0.15
local DEFAULT_COMPRESSION_TWEEN_TIME = 0.08
local COMPRESSION_DROP_STUDS = 0.15

export type BumperAssetLike = {
	Model: Model,
	Body: BasePart,
	SkirtTrigger: BasePart,
	Cap: BasePart,
	CapLight: PointLight?,
}

-- The kick is a direct velocity change (not a mass-scaled ApplyImpulse), a
-- deliberate simplification for a predictable, mass-independent arcade feel --
-- matches the existing bumper kick in CabinetGameplay.luau.
local function computeKickVelocity(bumperCenter: Vector3, up: Vector3, fallbackDirection: Vector3, ballPosition: Vector3, outward: number, upward: number): Vector3
	local toBall = ballPosition - bumperCenter
	local alongUp = toBall:Dot(up)
	local horizontal = toBall - (up * alongUp)

	local direction = horizontal.Magnitude > 1e-4 and horizontal.Unit or fallbackDirection

	return (direction * outward) + (up * upward)
end

function BumperController.Attach(asset: BumperAssetLike, config: BumperControllerConfig?, isBall: ((BasePart) -> boolean)?): Types.Controller
	local resolvedConfig = config or {}
	local outward = resolvedConfig.OutwardImpulse or DEFAULT_OUTWARD_IMPULSE
	local upward = resolvedConfig.UpwardImpulse or DEFAULT_UPWARD_IMPULSE
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS
	local tweenTime = resolvedConfig.CompressionTweenTime or DEFAULT_COMPRESSION_TWEEN_TIME

	local state = ComponentRegistry.NewState(asset.Model)
	local capRestCFrame = asset.Cap.CFrame
	local activeTween: Tween? = nil

	local function playCompression()
		if activeTween ~= nil then
			activeTween:Cancel()
		end

		asset.Cap.CFrame = capRestCFrame * CFrame.new(0, -COMPRESSION_DROP_STUDS, 0)

		local returnTween = TweenService:Create(
			asset.Cap,
			TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = capRestCFrame }
		)
		activeTween = returnTween
		returnTween:Play()

		if asset.CapLight ~= nil then
			asset.CapLight.Enabled = true
			task.delay(tweenTime * 2, function()
				if not state.Destroyed and asset.CapLight ~= nil then
					asset.CapLight.Enabled = false
				end
			end)
		end
	end

	local function onHit(ball: BasePart)
		if not ComponentRegistry.CheckBallCooldown(state, ball, cooldown) then
			return
		end

		local bumperCenter = asset.Body.Position
		local pivot = asset.Model:GetPivot()
		local up = pivot.UpVector
		local fallbackDirection = pivot.RightVector

		local kick = computeKickVelocity(bumperCenter, up, fallbackDirection, ball.Position, outward, upward)
		ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity + kick

		playCompression()
	end

	ComponentRegistry.ConnectTouched(state, asset.SkirtTrigger, onHit, isBall)
	ComponentRegistry.ConnectTouched(state, asset.Body, onHit, isBall)

	return {
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				onHit(ball)
			end
		end,
		Reset = function(_self)
			ComponentRegistry.ClearBallActivations(state)
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			if activeTween ~= nil then
				activeTween:Cancel()
			end
			ComponentRegistry.Destroy(state)
		end,
	}
end

return BumperController
