--!strict

-- Runtime behavior for a generated drop target bank
-- (Generators/TargetGenerator.GenerateDropBank). Each target is tracked
-- individually (down/up); driving a target's HingeConstraint.TargetAngle is a
-- real physics move (it pushes anything in the way, including the ball, along
-- the way), not a position tween. Bank-level Reset() raises every target;
-- ResetOne raises a single one. Fires an optional onBankComplete callback the
-- moment the last standing target goes down.

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local DropTargetController = {}

export type DropTargetControllerConfig = {
	DownAngleDegrees: number?,
	CooldownSeconds: number?,
}

local DEFAULT_DOWN_ANGLE_DEGREES = 80
local DEFAULT_COOLDOWN_SECONDS = 0.2

export type DropTargetBankAssetLike = {
	Model: Model,
	Targets: { BasePart },
	Hinges: { HingeConstraint },
}

export type DropTargetBankHandle = Types.Controller & {
	ResetOne: (self: DropTargetBankHandle, index: number) -> (),
	IsDown: (self: DropTargetBankHandle, index: number) -> boolean,
}

function DropTargetController.Attach(
	asset: DropTargetBankAssetLike,
	config: DropTargetControllerConfig?,
	onHit: ((number, BasePart) -> ())?,
	onBankComplete: (() -> ())?,
	isBall: ((BasePart) -> boolean)?
): DropTargetBankHandle
	local resolvedConfig = config or {}
	local downAngle = resolvedConfig.DownAngleDegrees or DEFAULT_DOWN_ANGLE_DEGREES
	local cooldown = resolvedConfig.CooldownSeconds or DEFAULT_COOLDOWN_SECONDS

	local state = ComponentRegistry.NewState(asset.Model)
	local isDown: { boolean } = table.create(#asset.Targets, false)

	local function allDown(): boolean
		for _, down in ipairs(isDown) do
			if not down then
				return false
			end
		end
		return true
	end

	local function knockDown(index: number, ball: BasePart)
		if isDown[index] then
			return
		end

		if not ComponentRegistry.CheckGlobalCooldown(state, cooldown) then
			return
		end

		isDown[index] = true
		-- HingeConstraint angle properties are degrees (same as LowerAngle/
		-- UpperAngle elsewhere in this codebase), not radians.
		asset.Hinges[index].TargetAngle = downAngle

		if onHit ~= nil then
			onHit(index, ball)
		end

		if allDown() and onBankComplete ~= nil then
			onBankComplete()
		end
	end

	for index, target in ipairs(asset.Targets) do
		ComponentRegistry.ConnectTouched(state, target, function(ball: BasePart)
			knockDown(index, ball)
		end, isBall)
	end

	local function resetOne(index: number)
		isDown[index] = false
		asset.Hinges[index].TargetAngle = 0
	end

	local function resetAll()
		for index in ipairs(asset.Targets) do
			resetOne(index)
		end
	end

	return {
		ResetOne = function(_self, index: number)
			resetOne(index)
		end,
		IsDown = function(_self, index: number)
			return isDown[index] == true
		end,
		Activate = function(_self, ball: BasePart?, _context)
			if ball ~= nil then
				knockDown(1, ball)
			end
		end,
		Reset = function(_self)
			resetAll()
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return DropTargetController
