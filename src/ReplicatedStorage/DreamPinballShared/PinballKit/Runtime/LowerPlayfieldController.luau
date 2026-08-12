--!strict

-- Composes a generated LowerPlayfieldGenerator.LowerPlayfieldAsset's runtime
-- behavior behind one handle (spec sections 14/16): both flippers, both
-- slingshots, all four lane rollovers, and the center drain. Every
-- underlying controller already exists (FlipperController/SlingshotController/
-- LaneSwitchController) -- this module only wires them together and reports
-- events via caller-supplied callbacks, matching this codebase's existing
-- convention that controllers report events rather than decide game logic
-- (LaneController's onPass, CabinetGameplay's endLaunch for the ball itself).
-- OnBallDrained does NOT destroy or otherwise touch the ball -- the caller
-- decides its fate, same as CabinetGameplay.endLaunch does today.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local FlipperController = require(script.Parent.FlipperController)
local SlingshotController = require(script.Parent.SlingshotController)
local LaneSwitchController = require(script.Parent.LaneSwitchController)
local Types = require(script.Parent.Parent.Types)
local MirrorTransform = require(script.Parent.Parent.Geometry.MirrorTransform)
local LowerPlayfieldGenerator = require(script.Parent.Parent.Generators.LowerPlayfieldGenerator)

local LowerPlayfieldController = {}

export type Side = MirrorTransform.Side
export type LaneType = LaneSwitchController.LaneType

local DEFAULT_DRAIN_COOLDOWN_SECONDS = 1

export type LowerPlayfieldControllerConfig = {
	FlipperMotorSpeed: number?,
	SlingshotOutwardImpulse: number?,
	SlingshotCooldownSeconds: number?,
	LaneCooldownSeconds: number?,
	IsBall: ((BasePart) -> boolean)?,
	OnLaneSwitch: ((laneId: string, side: Side, laneType: LaneType, ball: BasePart, entered: boolean) -> ())?,
	OnSlingshotFired: ((side: Side, ball: BasePart) -> ())?,
	OnBallDrained: ((ball: BasePart) -> ())?,
}

export type LowerPlayfieldHandle = {
	Press: (self: LowerPlayfieldHandle, side: Side) -> (),
	Release: (self: LowerPlayfieldHandle, side: Side) -> (),
	SetEnabled: (self: LowerPlayfieldHandle, enabled: boolean) -> (),
	Reset: (self: LowerPlayfieldHandle) -> (),
	GetState: (self: LowerPlayfieldHandle, side: Side) -> FlipperController.FlipperState,
	Destroy: (self: LowerPlayfieldHandle) -> (),
}

function LowerPlayfieldController.Attach(asset: LowerPlayfieldGenerator.LowerPlayfieldAsset, config: LowerPlayfieldControllerConfig?): LowerPlayfieldHandle
	local resolvedConfig = config or {}
	local isBall = resolvedConfig.IsBall
	-- `state` tracks connections/Enabled for orchestration only. Cooldown
	-- bookkeeping (LastActivationByBall) is deliberately kept in SEPARATE
	-- state objects per independent debounce concern (drain, each side's
	-- slingshot-fired report) -- sharing one map across them would let a
	-- slingshot hit reset the timer a drain-detection right after it relies
	-- on for the SAME ball, wrongly suppressing the drain event.
	local state = ComponentRegistry.NewState(asset.Model)
	local drainCooldownState = ComponentRegistry.NewState(asset.Model)
	local slingshotReportCooldownStates: { [Side]: ComponentRegistry.ControllerState } = {
		Left = ComponentRegistry.NewState(asset.Model),
		Right = ComponentRegistry.NewState(asset.Model),
	}

	local flipperHandles: { [Side]: FlipperController.FlipperHandle } = {
		Left = FlipperController.Attach(asset.Left.Flipper, resolvedConfig.FlipperMotorSpeed),
		Right = FlipperController.Attach(asset.Right.Flipper, resolvedConfig.FlipperMotorSpeed),
	}

	local slingshotHandles: { Types.Controller } = {}
	local laneHandles: { LaneSwitchController.LaneSwitchHandle } = {}

	for _, side in ipairs({ "Left", "Right" } :: { Side }) do
		local sideAsset = if side == "Left" then asset.Left else asset.Right

		local slingshotHandle = SlingshotController.Attach(sideAsset.Slingshot, {
			OutwardImpulse = resolvedConfig.SlingshotOutwardImpulse,
			CooldownSeconds = resolvedConfig.SlingshotCooldownSeconds,
		}, isBall)
		table.insert(slingshotHandles, slingshotHandle)

		if resolvedConfig.OnSlingshotFired ~= nil then
			local onSlingshotFired = resolvedConfig.OnSlingshotFired
			local reportConnection = sideAsset.Slingshot.TriggerRegion.Touched:Connect(function(otherPart: BasePart)
				if state.Destroyed or not state.Enabled then
					return
				end
				if isBall ~= nil and not isBall(otherPart) then
					return
				end
				if ComponentRegistry.CheckBallCooldown(slingshotReportCooldownStates[side], otherPart, resolvedConfig.SlingshotCooldownSeconds or 0.15) then
					onSlingshotFired(side, otherPart)
				end
			end)
			ComponentRegistry.TrackConnection(state, reportConnection)
		end

		local laneSpecs: { { Trigger: BasePart?, Light: any, LaneType: LaneType } } = {
			{ Trigger = sideAsset.Lanes.InlaneTrigger, Light = sideAsset.Lanes.InlaneLight, LaneType = "Inlane" },
			{ Trigger = sideAsset.Lanes.OutlaneTrigger, Light = sideAsset.Lanes.OutlaneLight, LaneType = "Outlane" },
		}

		for _, spec in ipairs(laneSpecs) do
			if spec.Trigger ~= nil then
				local laneId = string.format("%s-%s", side, spec.LaneType)
				local laneHandle = LaneSwitchController.Attach(
					{ Model = sideAsset.Lanes.Model, Trigger = spec.Trigger :: BasePart, Light = spec.Light },
					{ LaneId = laneId, Side = side, LaneType = spec.LaneType, CooldownSeconds = resolvedConfig.LaneCooldownSeconds },
					{
						OnBallEntered = function(ball: BasePart)
							if resolvedConfig.OnLaneSwitch ~= nil then
								resolvedConfig.OnLaneSwitch(laneId, side, spec.LaneType, ball, true)
							end
						end,
						OnBallExited = function(ball: BasePart)
							if resolvedConfig.OnLaneSwitch ~= nil then
								resolvedConfig.OnLaneSwitch(laneId, side, spec.LaneType, ball, false)
							end
						end,
					},
					isBall
				)
				table.insert(laneHandles, laneHandle)
			end
		end
	end

	-- Center drain: fire-once-per-ball via a per-ball cooldown, same pattern
	-- as every other mechanism in this library (spec section 17: "fire once
	-- per drain"). Never destroys the ball -- the caller decides.
	local drainConnection = asset.CenterDrainTrigger.Touched:Connect(function(otherPart: BasePart)
		if state.Destroyed or not state.Enabled then
			return
		end
		if isBall ~= nil and not isBall(otherPart) then
			return
		end
		if not ComponentRegistry.CheckBallCooldown(drainCooldownState, otherPart, DEFAULT_DRAIN_COOLDOWN_SECONDS) then
			return
		end
		if resolvedConfig.OnBallDrained ~= nil then
			resolvedConfig.OnBallDrained(otherPart)
		end
	end)
	ComponentRegistry.TrackConnection(state, drainConnection)

	local handle: LowerPlayfieldHandle
	handle = {
		Press = function(_self, side: Side)
			if state.Destroyed or not state.Enabled then
				return
			end
			flipperHandles[side]:SetPressed(true)
		end,
		Release = function(_self, side: Side)
			flipperHandles[side]:SetPressed(false)
		end,
		SetEnabled = function(_self, enabled: boolean)
			flipperHandles.Left:SetEnabled(enabled)
			flipperHandles.Right:SetEnabled(enabled)
			for _, slingshotHandle in ipairs(slingshotHandles) do
				slingshotHandle:SetEnabled(enabled)
			end
			for _, laneHandle in ipairs(laneHandles) do
				laneHandle:SetEnabled(enabled)
			end
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Reset = function(_self)
			flipperHandles.Left:Reset()
			flipperHandles.Right:Reset()
			for _, slingshotHandle in ipairs(slingshotHandles) do
				slingshotHandle:Reset()
			end
			for _, laneHandle in ipairs(laneHandles) do
				laneHandle:Reset()
			end
			ComponentRegistry.ClearBallActivations(drainCooldownState)
			ComponentRegistry.ClearBallActivations(slingshotReportCooldownStates.Left)
			ComponentRegistry.ClearBallActivations(slingshotReportCooldownStates.Right)
		end,
		GetState = function(_self, side: Side)
			return flipperHandles[side]:GetState()
		end,
		Destroy = function(_self)
			flipperHandles.Left:Destroy()
			flipperHandles.Right:Destroy()
			for _, slingshotHandle in ipairs(slingshotHandles) do
				slingshotHandle:Destroy()
			end
			for _, laneHandle in ipairs(laneHandles) do
				laneHandle:Destroy()
			end
			ComponentRegistry.Destroy(state)
		end,
	}

	return handle
end

return LowerPlayfieldController
