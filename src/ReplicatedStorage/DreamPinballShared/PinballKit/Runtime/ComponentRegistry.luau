--!strict

-- Shared runtime primitives every mechanism controller (Spinner, Bumper,
-- Slingshot, Target, ...) builds on: cooldown tracking (global and per-ball,
-- spec section 7: "Prevent duplicate activation from multiple touching parts"),
-- and connection bookkeeping so Destroy() reliably disconnects everything a
-- controller created (spec section 11: "Store and disconnect all event
-- connections during cleanup").
--
-- This is deliberately plain tables + functions, not a class/metatable
-- hierarchy, matching this codebase's existing style (see CabinetGameplay.luau)
-- -- concrete controllers hold a ControllerState and call these functions on
-- it rather than inheriting from a base class.

local ComponentRegistry = {}

export type ControllerState = {
	Model: Model,
	Enabled: boolean,
	Destroyed: boolean,
	Connections: { RBXScriptConnection },
	LastActivationGlobal: number?,
	LastActivationByBall: { [BasePart]: number },
}

function ComponentRegistry.NewState(model: Model): ControllerState
	return {
		Model = model,
		Enabled = true,
		Destroyed = false,
		Connections = {},
		LastActivationGlobal = nil,
		LastActivationByBall = {},
	}
end

-- Tracks a connection so Destroy() can disconnect it later. Every controller
-- should route every Connect() call through this instead of holding
-- connections in ad-hoc locals.
function ComponentRegistry.TrackConnection(state: ControllerState, connection: RBXScriptConnection)
	table.insert(state.Connections, connection)
end

-- Global (per-mechanism) cooldown check. Returns true and records `now` if the
-- cooldown has elapsed (or this is the first activation); returns false
-- without recording if still cooling down, so the caller should ignore this
-- hit entirely.
function ComponentRegistry.CheckGlobalCooldown(state: ControllerState, cooldownSeconds: number): boolean
	local now = os.clock()
	local last = state.LastActivationGlobal

	if last ~= nil and (now - last) < cooldownSeconds then
		return false
	end

	state.LastActivationGlobal = now
	return true
end

-- Per-ball cooldown check, for mechanisms that must not double-trigger from
-- one ball resting across multiple overlapping colliders but SHOULD still
-- react promptly to a different ball.
function ComponentRegistry.CheckBallCooldown(state: ControllerState, ball: BasePart, cooldownSeconds: number): boolean
	local now = os.clock()
	local last = state.LastActivationByBall[ball]

	if last ~= nil and (now - last) < cooldownSeconds then
		return false
	end

	state.LastActivationByBall[ball] = now
	return true
end

-- Connects `callback` to `part.Touched`, tracks the connection, and only
-- invokes `callback` when the touching part is still valid (mechanism not
-- destroyed/disabled) and passes `isValidHit` (defaults to accepting anything,
-- since this codebase has no single canonical "is this part a pinball" check
-- yet -- callers filter by whatever's appropriate, e.g. a Ball-folder
-- ancestry check or CollectionService tag).
function ComponentRegistry.ConnectTouched(
	state: ControllerState,
	part: BasePart,
	callback: (BasePart) -> (),
	isValidHit: ((BasePart) -> boolean)?
)
	local connection = part.Touched:Connect(function(otherPart: BasePart)
		if state.Destroyed or not state.Enabled then
			return
		end

		if isValidHit ~= nil and not isValidHit(otherPart) then
			return
		end

		callback(otherPart)
	end)

	ComponentRegistry.TrackConnection(state, connection)
	return connection
end

function ComponentRegistry.SetEnabled(state: ControllerState, enabled: boolean)
	state.Enabled = enabled
end

-- Disconnects every tracked connection exactly once. Safe to call more than
-- once (subsequent calls are no-ops).
function ComponentRegistry.Destroy(state: ControllerState)
	if state.Destroyed then
		return
	end

	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end

	table.clear(state.Connections)
	state.Destroyed = true
	state.Enabled = false
end

return ComponentRegistry
