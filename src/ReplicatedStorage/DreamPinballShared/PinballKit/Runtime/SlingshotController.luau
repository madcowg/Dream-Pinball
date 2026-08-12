--!strict

-- Runtime behavior for a generated Slingshot (Generators/SlingshotGenerator.luau).
-- Force direction is read from FaceNormalAttachment.WorldCFrame.LookVector at
-- hit time -- never a hardcoded world direction -- so it stays correct if the
-- whole cabinet is translated or rotated after generation.

local TweenService = game:GetService("TweenService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local SlingshotController = {}

export type SlingshotControllerConfig = {
	OutwardImpulse: number?,
	CooldownSeconds: number?,
	CompressionTweenTime: number?,
}

local DEFAULT_OUTWARD_IMPULSE = 50
local DEFAULT_COOLDOWN_SECONDS = 0.15
local DEFAULT_COMPRESSION_TWEEN_TIME = 0.06

export type SlingshotAssetLike = {
	Model: Model,
	HiddenCollider: BasePart,
	TriggerRegion: BasePart,
	RubberBand: BasePart,
	FaceNormalAttachment: Attachment,
	Lights: { PointLight },
}

function SlingshotController.Attach(
	asset: SlingshotAssetLike,
	config: SlingshotControllerConfig?,
	isBall: ((BasePart) -> boolean)?
): Types.Controller
	local resolvedConfig = config or {}
	local outward = resolvedConfig.OutwardImpulse or DEFAULT_OUTWARD_IMPULSE
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS
	local tweenTime = resolvedConfig.CompressionTweenTime or DEFAULT_COMPRESSION_TWEEN_TIME

	local state = ComponentRegistry.NewState(asset.Model)
	local bandRestSize = asset.RubberBand.Size
	local activeTween: Tween? = nil

	local function playCompression()
		if activeTween ~= nil then
			activeTween:Cancel()
		end

		asset.RubberBand.Size = bandRestSize * Vector3.new(1, 1, 0.85)

		local returnTween = TweenService:Create(
			asset.RubberBand,
			TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = bandRestSize }
		)
		activeTween = returnTween
		returnTween:Play()

		for _, light in ipairs(asset.Lights) do
			light.Enabled = true
		end
		if #asset.Lights > 0 then
			task.delay(tweenTime * 3, function()
				if state.Destroyed then
					return
				end
				for _, light in ipairs(asset.Lights) do
					light.Enabled = false
				end
			end)
		end
	end

	local function onHit(ball: BasePart)
		if not ComponentRegistry.CheckBallCooldown(state, ball, cooldown) then
			return
		end

		local faceNormal = asset.FaceNormalAttachment.WorldCFrame.LookVector
		ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity + (faceNormal * outward)

		playCompression()
	end

	ComponentRegistry.ConnectTouched(state, asset.TriggerRegion, onHit, isBall)
	ComponentRegistry.ConnectTouched(state, asset.HiddenCollider, onHit, isBall)

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

return SlingshotController
