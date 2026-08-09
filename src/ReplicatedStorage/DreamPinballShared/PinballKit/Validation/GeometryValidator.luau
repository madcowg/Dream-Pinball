--!strict

-- General-purpose numeric/config guards reused by every generator before it
-- creates any Instance. Generators must call these on their Config and raise a
-- descriptive error (spec section 8: "If validation fails, raise a descriptive
-- error before partially generating an asset") rather than generate partial
-- geometry. Instance-level checks (no NaN positions, no zero-size parts, etc.)
-- live in AssetValidator.luau, added alongside the first generator.

local Scale = require(script.Parent.Parent.Scale)

local GeometryValidator = {}

function GeometryValidator.IsFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function GeometryValidator.ValidatePositive(value: number, fieldName: string): (boolean, string?)
	if not GeometryValidator.IsFiniteNumber(value) then
		return false, string.format("%s must be a finite number, got %s", fieldName, tostring(value))
	end

	if value <= 0 then
		return false, string.format("%s must be greater than 0, got %.4f", fieldName, value)
	end

	return true, nil
end

function GeometryValidator.ValidateNonNegative(value: number, fieldName: string): (boolean, string?)
	if not GeometryValidator.IsFiniteNumber(value) then
		return false, string.format("%s must be a finite number, got %s", fieldName, tostring(value))
	end

	if value < 0 then
		return false, string.format("%s must be greater than or equal to 0, got %.4f", fieldName, value)
	end

	return true, nil
end

function GeometryValidator.ValidateAngleDegrees(angleDegrees: number, fieldName: string): (boolean, string?)
	local ok, err = GeometryValidator.ValidatePositive(angleDegrees, fieldName)
	if not ok then
		return false, err
	end

	if angleDegrees > 360 then
		return false, string.format("%s must be <= 360 degrees, got %.4f", fieldName, angleDegrees)
	end

	return true, nil
end

-- Wraps Scale.ValidateInnerDiameter with a field name for consistent error text.
function GeometryValidator.ValidateInnerDiameter(innerDiameterStuds: number, fieldName: string): (boolean, string?)
	local ok, err = Scale.ValidateInnerDiameter(innerDiameterStuds)
	if not ok then
		return false, string.format("%s: %s", fieldName, err :: string)
	end

	return true, nil
end

-- Runs a list of (ok, err) validator calls and raises with all failures at once,
-- so a caller sees every problem in one pass instead of fixing one error at a
-- time. Pass results as { { ok: boolean, err: string? }, ... }.
function GeometryValidator.AssertAll(results: { [number]: { ok: boolean, err: string? } }, context: string)
	local errors: { string } = {}

	for _, result in ipairs(results) do
		if not result.ok and result.err ~= nil then
			table.insert(errors, result.err)
		end
	end

	if #errors > 0 then
		error(string.format("%s validation failed:\n  - %s", context, table.concat(errors, "\n  - ")), 0)
	end
end

return GeometryValidator
