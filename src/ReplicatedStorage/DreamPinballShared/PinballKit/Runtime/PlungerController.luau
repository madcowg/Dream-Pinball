--!strict

-- Runtime behavior for a generated Plunger (Generators/PlungerGenerator.luau):
-- drives the rod's PrismaticConstraint TargetPosition in response to
-- BeginCharge()/CancelCharge()/Release(power) calls, mirroring
-- LaunchInputController.local.luau's hold-R-to-charge / release-to-fire feel
-- on the server side. Purely cosmetic -- see PlungerGenerator's header
-- comment -- CabinetGameplay.launch() still owns the actual ball velocity.
-- Call BeginCharge/Release alongside gameplay.BeginCharge/gameplay.Launch
-- (see WilliamsCabinet.server.luau's onLaunchInput), not instead of them.

local RunService = game:GetService("RunService")

local ComponentRegistry = require(script.Parent.ComponentRegistry)
local Types = require(script.Parent.Parent.Types)

local PlungerController = {}

export type PlungerControllerConfig = {
	-- Should match the client's charge-hold window
	-- (LaunchInputController.local.luau's CHARGE_MAX_SECONDS) so the rod's
	-- retraction speed feels tied to how long the player has actually been
	-- holding R. There's no shared constant for this yet -- keep the two in
	-- sync by hand if either one changes.
	ChargeMaxSeconds: number?,
	ReleaseOvershootStuds: number?,
	ReleaseOutSeconds: number?,
	ReleaseSettleSeconds: number?,
}

local DEFAULT_CHARGE_MAX_SECONDS = 1.5
local DEFAULT_RELEASE_OUT_SECONDS = 0.08
local DEFAULT_RELEASE_SETTLE_SECONDS = 0.35

export type PlungerHandle = Types.Controller & {
	BeginCharge: (self: PlungerHandle) -> (),
	CancelCharge: (self: PlungerHandle) -> (),
	Release: (self: PlungerHandle, power: number) -> (),
}

function PlungerController.Attach(rod: BasePart, constraint: PrismaticConstraint, maxRetractStuds: number, config: PlungerControllerConfig?): PlungerHandle
	local resolvedConfig = config or {}
	local chargeMaxSeconds = resolvedConfig.ChargeMaxSeconds or DEFAULT_CHARGE_MAX_SECONDS
	local releaseOvershootStuds = resolvedConfig.ReleaseOvershootStuds or (maxRetractStuds * 0.25)
	local releaseOutSeconds = resolvedConfig.ReleaseOutSeconds or DEFAULT_RELEASE_OUT_SECONDS
	local releaseSettleSeconds = resolvedConfig.ReleaseSettleSeconds or DEFAULT_RELEASE_SETTLE_SECONDS

	local model = rod:FindFirstAncestorOfClass("Model")
	if model == nil then
		error("PlungerController.Attach: rod must be a descendant of a Model (the generated Plunger asset)", 0)
	end

	local state = ComponentRegistry.NewState(model)

	-- Only one of these is ever running: starting either kind of animation
	-- cancels whichever one (charge loop or release shove) was already
	-- running.
	local activeAnimation: thread? = nil

	local function stopActiveAnimation()
		if activeAnimation ~= nil then
			task.cancel(activeAnimation)
			activeAnimation = nil
		end
	end

	-- Declared before the functions below (which close over it) and assigned
	-- as one full table literal further down -- each closure only reads
	-- `handle` when it actually runs, by which point it's already assigned,
	-- so this self-reference is safe (a standard Luau idiom, avoids an
	-- incomplete-table type assertion).
	local handle: PlungerHandle

	local function beginCharge(_self: PlungerHandle)
		if state.Destroyed or not state.Enabled then
			return
		end
		stopActiveAnimation()
		local startClock = os.clock()
		activeAnimation = task.spawn(function()
			while true do
				local heldSeconds = os.clock() - startClock
				local t = math.clamp(heldSeconds / chargeMaxSeconds, 0, 1)
				constraint.TargetPosition = t * maxRetractStuds
				RunService.Heartbeat:Wait()
			end
		end)
	end

	local function cancelCharge(_self: PlungerHandle)
		stopActiveAnimation()
		constraint.TargetPosition = 0
	end

	local function release(_self: PlungerHandle, power: number)
		stopActiveAnimation()
		if state.Destroyed or not state.Enabled then
			return
		end

		local clampedPower = math.clamp(power, 0, 1)
		activeAnimation = task.spawn(function()
			-- Shove forward past rest, proportional to how hard this launch
			-- was, then spring back to rest -- the visual echo of
			-- CabinetGameplay.launch()'s actual velocity assignment, which
			-- has already happened by the time this runs.
			constraint.TargetPosition = -releaseOvershootStuds * clampedPower
			task.wait(releaseOutSeconds)
			constraint.TargetPosition = 0
			task.wait(releaseSettleSeconds)
			activeAnimation = nil
		end)
	end

	handle = {
		BeginCharge = beginCharge,
		CancelCharge = cancelCharge,
		Release = release,
		Activate = function(_self, _ball, _context)
			-- Plunger motion is driven explicitly via BeginCharge/Release, not
			-- through ball contact -- present only to satisfy the shared
			-- Controller interface for registries that call it uniformly.
		end,
		Reset = function(_self)
			cancelCharge(handle)
		end,
		SetEnabled = function(_self, enabled: boolean)
			ComponentRegistry.SetEnabled(state, enabled)
			if not enabled then
				cancelCharge(handle)
			end
		end,
		Destroy = function(_self)
			stopActiveAnimation()
			ComponentRegistry.Destroy(state)
		end,
	}

	return handle
end

return PlungerController
