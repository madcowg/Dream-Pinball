--!strict

export type BoostedStat = "Speed" | "Atk" | "Def" | "HP"

--- Characters only apply effects/buffs to balls via the CHARACTER action; they
--- have no direct combat action of their own.
export type CharacterData = {
	Id: string,
	Name: string,
	BoostedStat: BoostedStat,
	BoostPercent: number,
}

local Character = {}

function Character.new(id: string, name: string, boostedStat: BoostedStat, boostPercent: number): CharacterData
	return {
		Id = id,
		Name = name,
		BoostedStat = boostedStat,
		BoostPercent = boostPercent,
	}
end

--- Predefined run-start characters. BoostedStat below is a placeholder pick
--- for each character's documented "lean" (tankier / speed) — confirm the
--- exact stat with design before this is player-facing.
local predefinedCharacters: { [string]: CharacterData } = {
	StripedPJ = Character.new("StripedPJ", "Striped PJ", "Def", 10),
	DinosaurOnesie = Character.new("DinosaurOnesie", "Dinosaur Onesie", "Speed", 10),
}
Character.Predefined = predefinedCharacters

return Character
