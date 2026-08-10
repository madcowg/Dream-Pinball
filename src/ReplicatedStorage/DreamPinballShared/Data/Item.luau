--!strict

--- Effect applied to the next-launched ball only. Fields are optional deltas;
--- absent fields mean "no change" for that attribute.
export type ItemEffect = {
	SpeedDelta: number?,
	AtkDelta: number?,
	AttractionDelta: number?,
	DestroysFirstObstacle: boolean?,
	AddsExtraBall: boolean?,
}

export type ItemData = {
	Id: string,
	Name: string,
	Effect: ItemEffect,
}

local Item = {}

function Item.new(id: string, name: string, effect: ItemEffect): ItemData
	return {
		Id = id,
		Name = name,
		Effect = effect,
	}
end

--- Single-use items: applies to the next launched ball only, consumes on use.
local predefinedItems: { [string]: ItemData } = {
	Feather = Item.new("Feather", "Feather", { SpeedDelta = -10, AtkDelta = -10 }),
	Coffee = Item.new("Coffee", "Coffee", { SpeedDelta = 10 }),
	ExtraBall = Item.new("ExtraBall", "Extra Ball", { AddsExtraBall = true }),
	Magnet = Item.new("Magnet", "Magnet", { AttractionDelta = 10, SpeedDelta = -10 }),
	Hammer = Item.new("Hammer", "Hammer", { DestroysFirstObstacle = true }),
}
Item.Predefined = predefinedItems

return Item
