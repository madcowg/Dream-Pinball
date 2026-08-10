--!strict

local Element = require(script.Parent:WaitForChild("Element"))

--- A fight or non-fight encounter within a machine. Fights are won by
--- reaching PointThreshold within TurnLimit turns; non-fight encounters
--- (quests/favors) can be fulfilled or skipped with no fail state.
export type EncounterData = {
	Id: string,
	Name: string,
	IsFight: boolean,
	Element: Element.Element,
	PointThreshold: number,
	TurnLimit: number,
	RunCurrencyReward: number,
}

local Encounter = {}

function Encounter.new(
	id: string,
	name: string,
	isFight: boolean,
	element: Element.Element,
	pointThreshold: number,
	runCurrencyReward: number
): EncounterData
	return {
		Id = id,
		Name = name,
		IsFight = isFight,
		Element = element,
		PointThreshold = pointThreshold,
		TurnLimit = 5,
		RunCurrencyReward = runCurrencyReward,
	}
end

return Encounter
