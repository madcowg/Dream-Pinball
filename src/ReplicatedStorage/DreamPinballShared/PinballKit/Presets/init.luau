--!strict

-- Presets.Extend(base, overrides) returns a NEW config table with `overrides`
-- applied on top of `base`, never mutating `base` itself (spec section 13:
-- "Do not share mutable nested configuration tables between generated
-- assets"). A shallow copy is sufficient because every generator Config type
-- in this library is a flat table of scalars/Enums/Color values -- none of
-- them nest another mutable config table that would need a deeper merge.

local Presets = {}

function Presets.Extend<T>(base: T, overrides: { [string]: any }): T
	local result = table.clone(base :: any)

	for key, value in pairs(overrides) do
		result[key] = value
	end

	return result :: T
end

Presets.WilliamsClassic = require(script.WilliamsClassic)
Presets.WilliamsClassicLowerPlayfield = require(script.WilliamsClassicLowerPlayfield)

return Presets
