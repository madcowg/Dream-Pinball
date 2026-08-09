--!strict

-- Runtime wrappers for gates and diverters (Generators/RoutingGenerator.luau).
-- A gate needs no touch handling at all -- its bounded Servo torque already
-- makes it a working one-way valve purely through physics -- so
-- AttachGate only exposes Reset/SetEnabled/Destroy for lifecycle management.
-- A diverter is actively commanded, so AttachDiverter adds SetDiverted.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local RoutingController = {}

export type FlapAssetLike = {
	Model: Model,
	Hinge: HingeConstraint,
}

function RoutingController.AttachGate(asset: FlapAssetLike): Types.Controller
	local state = ComponentRegistry.NewState(asset.Model)
	local closedAngle = asset.Hinge.LowerAngle

	return {
		Activate = function(_self, _ball, _context) end,
		Reset = function(_self)
			asset.Hinge.TargetAngle = closedAngle
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
			asset.Hinge.Enabled = enabled
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

export type DiverterHandle = Types.Controller & {
	SetDiverted: (self: DiverterHandle, diverted: boolean) -> (),
}

function RoutingController.AttachDiverter(asset: FlapAssetLike): DiverterHandle
	local state = ComponentRegistry.NewState(asset.Model)
	local straightAngle = asset.Hinge.LowerAngle
	local divertedAngle = asset.Hinge.UpperAngle

	local function setDiverted(diverted: boolean)
		if state.Destroyed or not state.Enabled then
			return
		end
		asset.Hinge.TargetAngle = diverted and divertedAngle or straightAngle
	end

	return {
		SetDiverted = function(_self, diverted: boolean)
			setDiverted(diverted)
		end,
		Activate = function(_self, _ball, _context)
			setDiverted(true)
		end,
		Reset = function(_self)
			setDiverted(false)
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return RoutingController
