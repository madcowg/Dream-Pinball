--!strict

--- Soft, Pokemon-style elemental effectiveness (resist/neutral/weak), not a
--- hard counter. The full 8x8 grid exists now so later worlds don't need a
--- rework, but no matchup beyond "Neutral" has been designed yet -- only
--- Water is active in the Sand level, and even Water's specific
--- resistances/weaknesses are not yet decided. Every cell defaults to
--- Neutral until a real matchup is set via TypeEffectiveness.set.
local Element = require(script.Parent:WaitForChild("Element"))

export type Multiplier = number

local Multiplier = {
	Resist = 0.75,
	Neutral = 1,
	Weak = 1.25,
}

local TypeEffectiveness = {
	Multiplier = Multiplier,
}

local grid: { [Element.Element]: { [Element.Element]: Multiplier } } = {}
for _, attacker in Element.All do
	grid[attacker] = {}
	for _, defender in Element.All do
		grid[attacker][defender] = Multiplier.Neutral
	end
end

--- Overrides one attacker/defender matchup. Call this as real element
--- matchups get designed; do not hardcode design decisions elsewhere.
function TypeEffectiveness.set(attacker: Element.Element, defender: Element.Element, multiplier: Multiplier)
	grid[attacker][defender] = multiplier
end

function TypeEffectiveness.get(attacker: Element.Element, defender: Element.Element): Multiplier
	return grid[attacker][defender]
end

return TypeEffectiveness
