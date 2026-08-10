--!strict

local Ball = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("Ball"))

export type TurnAction = "Launch" | "Item" | "Character" | "Spin"
export type TurnResult = "InProgress" | "Won" | "Lost"

--- LAUNCH and SPIN end the turn immediately. ITEM (up to MaxItemsPerTurn) and
--- CHARACTER (once) do not end the turn on their own -- a turn only ends
--- when LAUNCH or SPIN is taken.
export type TurnState = {
	Hand: { Ball.BallData },
	HandSize: number,
	TurnNumber: number,
	MaxTurns: number,
	ItemsUsedThisTurn: number,
	MaxItemsPerTurn: number,
	CharacterUsedThisTurn: boolean,
	Score: number,
	PointThreshold: number,
	Result: TurnResult,
}

local TurnState = {}

function TurnState.new(hand: { Ball.BallData }, handSize: number, pointThreshold: number): TurnState
	return {
		Hand = hand,
		HandSize = handSize,
		TurnNumber = 1,
		MaxTurns = 5,
		ItemsUsedThisTurn = 0,
		MaxItemsPerTurn = 3,
		CharacterUsedThisTurn = false,
		Score = 0,
		PointThreshold = pointThreshold,
		Result = "InProgress",
	}
end

function TurnState.isOver(state: TurnState): boolean
	return state.Result ~= "InProgress"
end

function TurnState.canUseItem(state: TurnState): boolean
	return not TurnState.isOver(state) and state.ItemsUsedThisTurn < state.MaxItemsPerTurn
end

function TurnState.canUseCharacter(state: TurnState): boolean
	return not TurnState.isOver(state) and not state.CharacterUsedThisTurn
end

function TurnState.canEndTurn(state: TurnState): boolean
	return not TurnState.isOver(state)
end

--- Caller must check canUseItem first; returns state unchanged if invalid.
function TurnState.useItem(state: TurnState): TurnState
	if not TurnState.canUseItem(state) then
		return state
	end

	return {
		Hand = state.Hand,
		HandSize = state.HandSize,
		TurnNumber = state.TurnNumber,
		MaxTurns = state.MaxTurns,
		ItemsUsedThisTurn = state.ItemsUsedThisTurn + 1,
		MaxItemsPerTurn = state.MaxItemsPerTurn,
		CharacterUsedThisTurn = state.CharacterUsedThisTurn,
		Score = state.Score,
		PointThreshold = state.PointThreshold,
		Result = state.Result,
	}
end

--- Caller must check canUseCharacter first; returns state unchanged if invalid.
function TurnState.useCharacter(state: TurnState): TurnState
	if not TurnState.canUseCharacter(state) then
		return state
	end

	return {
		Hand = state.Hand,
		HandSize = state.HandSize,
		TurnNumber = state.TurnNumber,
		MaxTurns = state.MaxTurns,
		ItemsUsedThisTurn = state.ItemsUsedThisTurn,
		MaxItemsPerTurn = state.MaxItemsPerTurn,
		CharacterUsedThisTurn = true,
		Score = state.Score,
		PointThreshold = state.PointThreshold,
		Result = state.Result,
	}
end

--- Adds to Score and marks the fight Won once PointThreshold is reached.
function TurnState.addScore(state: TurnState, amount: number): TurnState
	if TurnState.isOver(state) then
		return state
	end

	local newScore = state.Score + amount
	local newResult: TurnResult = if newScore >= state.PointThreshold then "Won" else state.Result

	return {
		Hand = state.Hand,
		HandSize = state.HandSize,
		TurnNumber = state.TurnNumber,
		MaxTurns = state.MaxTurns,
		ItemsUsedThisTurn = state.ItemsUsedThisTurn,
		MaxItemsPerTurn = state.MaxItemsPerTurn,
		CharacterUsedThisTurn = state.CharacterUsedThisTurn,
		Score = newScore,
		PointThreshold = state.PointThreshold,
		Result = newResult,
	}
end

--- Called for LAUNCH or SPIN -- the only two actions that end a turn. Resets
--- per-turn allowances and checks the 5-turn loss condition.
function TurnState.endTurn(state: TurnState): TurnState
	if not TurnState.canEndTurn(state) then
		return state
	end

	local newTurnNumber = state.TurnNumber + 1
	local newResult: TurnResult = if newTurnNumber > state.MaxTurns then "Lost" else state.Result

	return {
		Hand = state.Hand,
		HandSize = state.HandSize,
		TurnNumber = newTurnNumber,
		MaxTurns = state.MaxTurns,
		ItemsUsedThisTurn = 0,
		MaxItemsPerTurn = state.MaxItemsPerTurn,
		CharacterUsedThisTurn = false,
		Score = state.Score,
		PointThreshold = state.PointThreshold,
		Result = newResult,
	}
end

return TurnState
