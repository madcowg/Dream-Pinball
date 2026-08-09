--!strict

-- Instance-level validation for a generated asset Model (spec section 15).
-- GeometryValidator checks raw numbers/config BEFORE geometry is built; this
-- module checks the Instance tree AFTER it exists. Every check here can run
-- headlessly from a Command Bar or a Studio test script -- it inspects
-- properties, it never simulates physics (see README.md for why the
-- ball-roll test in spec section 15 has to run live in Studio instead).

local Constants = require(script.Parent.Parent.Constants)

local AssetValidator = {}

export type ValidationReport = {
	Ok: boolean,
	Errors: { string },
	PartCount: number,
}

local function isFiniteVector3(vector: Vector3): boolean
	return vector.X == vector.X
		and vector.Y == vector.Y
		and vector.Z == vector.Z
		and math.abs(vector.X) ~= math.huge
		and math.abs(vector.Y) ~= math.huge
		and math.abs(vector.Z) ~= math.huge
end

-- Checks required by spec section 15 that only need one Model to evaluate:
-- attributes present, no NaN/infinite positions or sizes, no zero/negative
-- dimensions, visual-only parts don't collide, trigger parts don't physically
-- block the ball, and Root/PrimaryPart are set up correctly.
function AssetValidator.ValidateModel(model: Model): ValidationReport
	local errors: { string } = {}
	local partCount = 0

	local attributes = Constants.ASSET_ATTRIBUTES
	for _, attributeName in pairs(attributes) do
		if model:GetAttribute(attributeName) == nil then
			table.insert(errors, string.format("Missing required attribute %q on %s", attributeName, model:GetFullName()))
		end
	end

	if model.PrimaryPart == nil then
		table.insert(errors, string.format("%s has no PrimaryPart (Root must be set as PrimaryPart)", model:GetFullName()))
	elseif model.PrimaryPart.Name ~= "Root" then
		table.insert(errors, string.format("%s PrimaryPart is %q, expected \"Root\"", model:GetFullName(), model.PrimaryPart.Name))
	end

	for _, folderName in ipairs(Constants.STANDARD_HIERARCHY_FOLDERS) do
		local folder = model:FindFirstChild(folderName)
		if folder ~= nil and not folder:IsA("Folder") then
			table.insert(errors, string.format("%s.%s exists but is not a Folder", model:GetFullName(), folderName))
		end
	end

	local visualsFolder = model:FindFirstChild("Visuals")
	local triggersFolder = model:FindFirstChild("Triggers")

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partCount += 1
			local part = descendant :: BasePart

			if not isFiniteVector3(part.Position) then
				table.insert(errors, string.format("%s has a non-finite Position", part:GetFullName()))
			end
			if not isFiniteVector3(part.Size) then
				table.insert(errors, string.format("%s has a non-finite Size", part:GetFullName()))
			end
			if part.Size.X <= 0 or part.Size.Y <= 0 or part.Size.Z <= 0 then
				table.insert(errors, string.format("%s has a zero or negative Size dimension (%s)", part:GetFullName(), tostring(part.Size)))
			end

			if visualsFolder ~= nil and part:IsDescendantOf(visualsFolder) and part.CanCollide then
				table.insert(errors, string.format("%s is under Visuals but CanCollide is true", part:GetFullName()))
			end

			if triggersFolder ~= nil and part:IsDescendantOf(triggersFolder) then
				if part.CanCollide then
					table.insert(errors, string.format("%s is under Triggers but CanCollide is true (would physically block the ball)", part:GetFullName()))
				end
				if not part.CanTouch then
					table.insert(errors, string.format("%s is under Triggers but CanTouch is false", part:GetFullName()))
				end
			end
		end
	end

	return {
		Ok = #errors == 0,
		Errors = errors,
		PartCount = partCount,
	}
end

-- Regeneration must replace, not duplicate: calls `generateFn` twice with the
-- same name/origin and checks the container ends up with exactly one matching
-- generation id afterward.
function AssetValidator.ValidateIdempotentRegeneration(
	container: Instance,
	generationId: string,
	generateFn: () -> ()
): ValidationReport
	generateFn()
	generateFn()

	local matches = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(Constants.ASSET_ATTRIBUTES.GenerationId) == generationId then
			matches += 1
		end
	end

	local errors: { string } = {}
	if matches ~= 1 then
		table.insert(
			errors,
			string.format("Expected exactly 1 model with GenerationId %q after regenerating twice, found %d", generationId, matches)
		)
	end

	return { Ok = #errors == 0, Errors = errors, PartCount = matches }
end

-- Aggregates PartCount across many ValidationReports (or raw models) for the
-- performance report spec section 16 asks for.
function AssetValidator.CountParts(model: Model): number
	local count = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return AssetValidator
