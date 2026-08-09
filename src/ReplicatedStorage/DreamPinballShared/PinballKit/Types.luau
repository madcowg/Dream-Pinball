--!strict

-- Shared cross-cutting types used by every PinballKit generator and controller.
-- Per-asset configuration types (SpinnerConfig, RampConfig, etc.) are NOT defined
-- here -- following this codebase's existing convention (see CabinetBuilder.luau,
-- CabinetLayouts.luau), each generator module owns and exports its own Config
-- type, and other modules reference it by dotted name after requiring that module.

export type Quality = "Low" | "Medium" | "High"

export type LightState = "Off" | "On" | "Pulse" | "Blink"

-- Documents where a dimension came from, per spec section 3: never claim a
-- dimension is a Williams standard unless it is backed by a manual, drawing, or
-- identifiable part. Every preset-level dimension should carry one of these.
export type DimensionSource = "WilliamsHardware" | "ReferencedPart" | "GameplayDefault"

export type DimensionSpec = {
	Studs: number,
	Inches: number?,
	Source: DimensionSource,
	-- Required when Source is "WilliamsHardware" or "ReferencedPart": the manual,
	-- drawing, or part name/number the dimension is drawn from.
	Reference: string?,
}

export type ActivationContext = {
	Ball: BasePart?,
	Player: Player?,
	Timestamp: number?,
}

export type GenerateOptions<T> = {
	Name: string?,
	Parent: Instance?,
	Origin: CFrame,
	Config: T,
	ReplaceExisting: boolean?,
}

export type GeneratedAsset = {
	Model: Model,
	Root: BasePart,
	Attachments: { [string]: Attachment },
}

-- Standard runtime component interface. Generator-specific controllers should
-- implement this shape; SetLit/SetLightState/SetColor are additive for
-- light-capable assets (see Runtime/LightController.luau).
export type Controller = {
	Activate: (self: Controller, ball: BasePart?, context: ActivationContext?) -> (),
	Reset: (self: Controller) -> (),
	SetEnabled: (self: Controller, enabled: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

return {}
