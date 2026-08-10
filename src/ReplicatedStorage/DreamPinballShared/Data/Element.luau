--!strict

--- Ball/creature elements. World 1 (Sand level) only uses Water; the rest
--- exist so the type-effectiveness table can be built as a complete 8x8 grid.
export type Element = "Water" | "Grass" | "Rock" | "Earth" | "Air" | "Fire" | "Nightmare" | "Dream"

local Element = {}

local allElements: { Element } = {
	"Water",
	"Grass",
	"Rock",
	"Earth",
	"Air",
	"Fire",
	"Nightmare",
	"Dream",
}
Element.All = allElements

function Element.isValid(value: string): boolean
	for _, element in Element.All do
		if element == value then
			return true
		end
	end
	return false
end

return Element
