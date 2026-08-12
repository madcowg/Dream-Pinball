--!strict

-- Runtime behavior for one InlaneOutlaneGenerator rollover trigger (spec
-- section 10). Sibling to LaneController, not a replacement -- LaneController
-- stays as-is for the plain LaneDivider asset's simpler cooldown-based
-- rollover. This controller tracks which balls currently overlap the trigger
-- (a Touched/TouchEnded latch, not a pure time cooldown) so a ball resting on
-- the trigger fires OnBallEntered exactly once instead of re-firing every
-- CooldownSeconds while it sits there, and reports OnBallExited once it
-- actually leaves -- matching spec section 10's "fire once per complete
-- crossing... do not repeatedly score while a ball rests on the trigger,"
-- for either direction of travel. Scoring/game effect stays outside this
-- module -- callers get raw enter/exit events only.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local LightController = require(script.Parent.LightController)
local Types = require(script.Parent.Parent.Types)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local LightGenerator = require(script.Parent.Parent.Generators.LightGenerator)

local LaneSwitchController = {}

export type Side = MirrorTransform.Side
export type LaneType = "Inlane" | "Outlane"

export type LaneSwitchAssetLike = {
	Model: Model,
	Trigger: BasePart,
	Light: LightGenerator.LightAsset?,
}

export type LaneSwitchConfig = {
	LaneId: string,
	Side: Side,
	LaneType: LaneType,
	CooldownSeconds: number?,
}

export type LaneSwitchCallbacks = {
	OnBallEntered: ((BasePart) -> ())?,
	OnBallExited: ((BasePart) -> ())?,
}

local DEFAULT_COOLDOWN_SECONDS = 0.1

export type LaneSwitchHandle = Types.Controller & {
	GetLaneId: (self: LaneSwitchHandle) -> string,
	GetSide: (self: LaneSwitchHandle) -> Side,
	GetLaneType: (self: LaneSwitchHandle) -> LaneType,
	SetTriggerLit: (self: LaneSwitchHandle, enabled: boolean) -> (),
}

function LaneSwitchController.Attach(
	asset: LaneSwitchAssetLike,
	config: LaneSwitchConfig,
	callbacks: LaneSwitchCallbacks?,
	isBall: ((BasePart) -> boolean)?
): LaneSwitchHandle
	local resolvedCallbacks = callbacks or {}
	local cooldown = config.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS
	local state = ComponentRegistry.NewState(asset.Model)
	-- Weak-keyed for the same reason ComponentRegistry.NewState's
	-- LastActivationByBall is: TouchEnded never fires for a ball that gets
	-- Destroyed while still overlapping the trigger, which would otherwise
	-- leave its entry here forever.
	local insideBalls: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: { [BasePart]: boolean }
	local lightHandle = if asset.Light ~= nil then LightController.Attach(asset.Light) else nil

	local function isValidHit(part: BasePart): boolean
		if isBall ~= nil then
			return isBall(part)
		end
		return true
	end

	local touchedConnection = asset.Trigger.Touched:Connect(function(otherPart: BasePart)
		if state.Destroyed or not state.Enabled then
			return
		end
		if not isValidHit(otherPart) then
			return
		end
		if insideBalls[otherPart] then
			return
		end

		-- Latch AFTER the cooldown check, not before -- otherwise a hit
		-- suppressed by cooldown still marks the ball "inside," so the
		-- following TouchEnded fires an OnBallExited with no matching
		-- OnBallEntered ever having fired for it.
		if ComponentRegistry.CheckBallCooldown(state, otherPart, cooldown) then
			insideBalls[otherPart] = true
			if resolvedCallbacks.OnBallEntered ~= nil then
				resolvedCallbacks.OnBallEntered(otherPart)
			end
			if lightHandle ~= nil then
				lightHandle:SetLit(true)
			end
		end
	end)
	ComponentRegistry.TrackConnection(state, touchedConnection)

	local touchEndedConnection = asset.Trigger.TouchEnded:Connect(function(otherPart: BasePart)
		if state.Destroyed then
			return
		end
		if not insideBalls[otherPart] then
			return
		end
		insideBalls[otherPart] = nil

		if resolvedCallbacks.OnBallExited ~= nil then
			resolvedCallbacks.OnBallExited(otherPart)
		end
	end)
	ComponentRegistry.TrackConnection(state, touchEndedConnection)

	local handle: LaneSwitchHandle
	handle = {
		GetLaneId = function(_self)
			return config.LaneId
		end,
		GetSide = function(_self)
			return config.Side
		end,
		GetLaneType = function(_self)
			return config.LaneType
		end,
		SetTriggerLit = function(_self, enabled: boolean)
			if lightHandle ~= nil then
				lightHandle:SetLit(enabled)
			end
		end,
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil and resolvedCallbacks.OnBallEntered ~= nil then
				resolvedCallbacks.OnBallEntered(ball)
			end
		end,
		Reset = function(_self)
			table.clear(insideBalls)
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

return LaneSwitchController
