--!strict

-- Runtime input handling for a generated Flipper
-- (Generators/FlipperGenerator.luau). Delegates the actual AngularVelocity
-- math to CabinetBuilder.setFlipperInput -- the SWEEP_DIRECTION sign
-- convention that makes "pressed" actually raise the flipper (rather than
-- drive it further into its rest position) is private to CabinetBuilder.luau,
-- so this must go through that function rather than re-deriving the sign.

local CabinetBuilder = require(script.Parent.Parent.Parent.CabinetBuilder)
local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local FlipperController = {}

-- INTENTIONALLY faster than GameplayTuning.FLIPPER_MOTOR_SPEED (12, the
-- locked baseline) -- see FlipperGenerator.luau's header comment: live
-- playtesting found the baseline flippers under-hit the ball, so PinballKit's
-- own default is ~33% faster on top of the generator's heavier/stronger
-- defaults. setFlipperInput scales this linearly (magnitude = speed * a fixed
-- multiplier), so this single number is the whole "how fast does it swing"
-- lever.
local DEFAULT_MOTOR_SPEED = 16

export type FlipperAssetLike = {
	Model: Model,
	Hinge: HingeConstraint,
	Side: CabinetBuilder.Side,
}

export type FlipperHandle = Types.Controller & {
	SetPressed: (self: FlipperHandle, pressed: boolean) -> (),
}

function FlipperController.Attach(asset: FlipperAssetLike, motorSpeed: number?): FlipperHandle
	local speed = motorSpeed or DEFAULT_MOTOR_SPEED
	local state = ComponentRegistry.NewState(asset.Model)
	local hinges: { [CabinetBuilder.Side]: HingeConstraint } = { [asset.Side] = asset.Hinge }
	local pressed = false

	-- Always applies, regardless of Enabled/Destroyed -- used directly by
	-- SetEnabled(false) to force a release even while otherwise disabling.
	local function applyPressed(nextPressed: boolean)
		pressed = nextPressed
		CabinetBuilder.setFlipperInput(hinges, asset.Side, pressed, speed)
	end

	local function setPressed(nextPressed: boolean)
		if state.Destroyed or not state.Enabled then
			return
		end
		applyPressed(nextPressed)
	end

	return {
		SetPressed = function(_self, nextPressed: boolean)
			setPressed(nextPressed)
		end,
		Activate = function(_self, _ball, _context)
			setPressed(true)
		end,
		Reset = function(_self)
			setPressed(false)
		end,
		SetEnabled = function(_self, enabled: boolean)
			if not enabled then
				applyPressed(false)
			end
			ComponentRegistry.SetEnabled(state, enabled)
		end,
		Destroy = function(_self)
			applyPressed(false)
			ComponentRegistry.Destroy(state)
		end,
	}
end

return FlipperController
