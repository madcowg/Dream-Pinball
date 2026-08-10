--!strict

local Element = require(script.Parent:WaitForChild("Element"))

export type Stats = {
	Speed: number,
	Atk: number,
	Def: number,
	HP: number,
}

--- A ball/creature instance in a player's hand or collection. Id is a
--- per-INSTANCE identifier (e.g. a specific ball currently sitting in hand
--- slot 2) -- it is NOT stable across different balls of the same species,
--- and must never be used to look up visual assets. Species is the stable
--- key for that (e.g. "SeaGoblin", shared by every Sea Goblin ball anyone
--- ever holds) -- see CreatureModels.luau, which maps Species to that
--- creature's PinballModel/CreatureModel. nil Species means a neutral/
--- speciesless ball (e.g. the Extra Ball item's plain steel ball) -- look
--- those up in SharedModels instead.
export type BallData = {
	Id: string,
	Name: string,
	Species: string?,
	Element: Element.Element,
	Rarity: string,
	Stats: Stats,
	MaxDurability: number,
	CurrentDurability: number,
}

local Ball = {}

function Ball.new(
	id: string,
	name: string,
	species: string?,
	element: Element.Element,
	rarity: string,
	stats: Stats,
	maxDurability: number
): BallData
	return {
		Id = id,
		Name = name,
		Species = species,
		Element = element,
		Rarity = rarity,
		Stats = stats,
		MaxDurability = maxDurability,
		CurrentDurability = maxDurability,
	}
end

--- Durability drops per scoring bounce only, not every physical hit. Callers
--- are responsible for only invoking this on a scoring bounce.
function Ball.applyScoringBounceDurabilityLoss(ball: BallData, amount: number): BallData
	local nextDurability = math.max(ball.CurrentDurability - amount, 0)
	return {
		Id = ball.Id,
		Name = ball.Name,
		Species = ball.Species,
		Element = ball.Element,
		Rarity = ball.Rarity,
		Stats = ball.Stats,
		MaxDurability = ball.MaxDurability,
		CurrentDurability = nextDurability,
	}
end

function Ball.isBroken(ball: BallData): boolean
	return ball.CurrentDurability <= 0
end

return Ball
