# PinballKit

A reusable, typed-Luau library of classic Williams-style pinball components for
Dream Pinball, built on top of the existing Rojo project structure
(`src/ReplicatedStorage/DreamPinballShared/PinballKit/`). It is a separate,
additive module family — it does not replace `CabinetBuilder.luau` /
`CabinetLayouts.luau` (the existing 3-comparison-cabinet pipeline) or the
hand-built commercial-spec cabinet track (`CabinetGameplay.luau`). Use
whichever fits: PinballKit for spinners/rails/tunnels/ramps/lights/buttons and
the richer bumper/slingshot/target, the existing systems for anything already
working.

## Status

Every module here has been reviewed by hand but **has not yet been run inside
Roblox Studio** — there is no Luau runtime, Rojo, or Roblox physics engine
available outside Studio to execute or test it against. Per this project's own
`AGENTS.md` rule ("Do not claim a feature works until it has been tested in
Studio"), treat everything below as implemented-but-unverified until someone
syncs it in and runs the demo layout.

## Installation

Already in place: this whole folder lives under
`src/ReplicatedStorage/DreamPinballShared/PinballKit/` and syncs into
`ReplicatedStorage.DreamPinballShared.PinballKit` through the existing
`default.project.json` mapping — no Rojo config changes were needed or made.

## Generation

Every generator follows the same shape:

```luau
type GenerateOptions<T> = {
    Name: string?,        -- defaults to a per-generator name
    Parent: Instance?,    -- defaults to Workspace.GeneratedPinballAssets
    Origin: CFrame,       -- required; everything is built relative to this
    Config: T,            -- the generator's typed Config
    ReplaceExisting: boolean?, -- default true
}

type GeneratedAsset = {
    Model: Model,
    Root: BasePart,        -- PrimaryPart; Model/Root/Visuals/Colliders/
                            -- Triggers/Mechanism/Lights/Attachments hierarchy
    Attachments: {[string]: Attachment},
}
```

Example — a 60-degree U-shaped rail:

```luau
local PinballKit = require(game.ReplicatedStorage.DreamPinballShared.PinballKit)

local asset = PinballKit.Generators.RailGenerator.GenerateUHalfPipe({
    Name = "LeftLaneRail",
    Origin = workspace.SomeAnchor.CFrame,
    Config = PinballKit.Presets.Extend(PinballKit.Presets.WilliamsClassic.URail, {
        Path = { PathType = "Curved", Radius = 8, AngleDegrees = 60, Direction = "Left" },
    }),
})
```

Regeneration is idempotent: calling the same generator again with the same
`Name` replaces the previous model (matched by a `GenerationId` attribute)
instead of duplicating it, and never touches anything else in `Parent`.

### Command Bar bootstrap

From Roblox Studio's Command Bar, after a Rojo sync:

```luau
local PinballKit = require(game.ReplicatedStorage.DreamPinballShared.PinballKit)
PinballKit.Demo.Generate(workspace)
```

This builds the full demonstration layout (spec section 14: one of every
rail/tunnel angle, one of every ramp class, spinner, bumper, slingshot,
hideaway target, cabinet button, round/bar/ring inserts with a sample
sequence, labels, and 1.5-stud test balls) into `Workspace.PinballKitDemo`.
Re-running it replaces the previous demo. **Run this from a server context**
(Command Bar in Studio counts) — the cabinet button's press validation relies
on `ProximityPrompt.Triggered`, which only behaves as a server-validated event
when the attaching code runs on the server.

## Configuration

Every asset family has its own `Config` type owned by its generator module
(e.g. `RailGenerator.UHalfPipeConfig`, `SpinnerGenerator.SpinnerConfig`) —
there is no central `Types.luau` holding every config shape. This matches the
existing convention in this codebase (see `CabinetBuilder.CabinetConfig`,
`CabinetLayouts.BumperSpec`): the owning module exports its type, other
modules reference it by dotted name after `require`-ing that module.
`PinballKit/Types.luau` only holds the small set of cross-cutting types every
generator shares (`GenerateOptions<T>`, `GeneratedAsset`, `Quality`,
`Controller`, etc).

All dimensions route through `PinballKit/Scale.luau`
(`BALL_DIAMETER_STUDS = 1.5`, `STUDS_PER_INCH`, `MIN_INNER_DIAMETER_STUDS =
1.7`) — never hardcode a scale factor in a generator. Any enclosed path's
inner diameter is validated against `Scale.MIN_INNER_DIAMETER_STUDS` before
geometry is built; passing a smaller value raises immediately.

## Runtime activation

Mechanism controllers (`Runtime/*Controller.luau`) are attached to a
generator's returned asset table, not baked into the generator itself —
geometry and gameplay logic stay separate on purpose:

```luau
local bumperAsset = PinballKit.Generators.BumperGenerator.Generate({
    Origin = someCFrame,
    Config = PinballKit.Presets.WilliamsClassic.PopBumper,
})

local bumperHandle = PinballKit.Runtime.BumperController.Attach(
    bumperAsset,
    PinballKit.Presets.WilliamsClassic.PopBumperRuntime,
    function(part) return part.Name == "TestBall" end -- your own ball predicate
)

-- later:
bumperHandle:Destroy() -- disconnects every connection this controller made
```

Every controller implements the same shape (`Activate`, `Reset`,
`SetEnabled`, `Destroy`); light-capable ones add `SetLit`/`SetLightState`/
`SetColor`. `Runtime/ComponentRegistry.luau` provides the shared cooldown
(global and per-ball) and connection-tracking primitives every controller is
built on — reuse it rather than re-implementing debounce/cleanup per
mechanism.

There is no canonical "is this part a pinball ball" check anywhere in this
codebase yet, so every controller that needs one takes an `isBall` predicate
from the caller instead of assuming a name or tag.

## Adding a new preset

```luau
local myPopBumper = PinballKit.Presets.Extend(PinballKit.Presets.WilliamsClassic.PopBumper, {
    CapColor = Color3.fromRGB(220, 35, 35),
    LightColor = Color3.fromRGB(255, 60, 40),
})
```

`Extend` returns a new table; it never mutates the base preset, so multiple
generated instances never share a mutable config table. To add a whole new
named preset family (e.g. `PinballKit/Presets/NeonArcade.luau`), copy the
shape of `Presets/WilliamsClassic.luau` — cast every field to its generator's
`Config` type (`:: RailGenerator.UHalfPipeConfig` etc.) so string-literal
fields like `Shape`/`Kind`/`Direction` don't widen to plain `string` under
`--!strict`, then require it from `PinballKit/Presets/init.luau`.

## Adding a new asset generator

1. Add `Generators/YourThingGenerator.luau`. Export a `YourThingConfig` type
   and a `Generate(options: Types.GenerateOptions<YourThingConfig>):
   Types.GeneratedAsset` (or an intersection type if the controller needs
   extra handles, e.g. `Types.GeneratedAsset & { Paddle: BasePart }` like
   `SpinnerGenerator.SpinnerAsset`).
2. Validate the config with `Validation/GeometryValidator.luau` (and
   `Scale.ValidateInnerDiameter` if it encloses a ball path) before creating
   any Instance.
3. Build geometry through `Geometry/PrimitiveFactory.CreatePart` (not raw
   `Instance.new("Part")`) so size validation and per-role
   CanCollide/CanTouch/CanQuery flags stay consistent, and
   `PrimitiveFactory.BuildStandardHierarchy` for the Model/Root/folder
   contract.
4. If it needs a swept path (rail/tunnel/ramp-like), reuse
   `Geometry/PathBuilder.Build` (straight or curved) and
   `Geometry/ProfileSweep.Sweep` (circular cross-section) rather than
   re-deriving arc math.
5. Finish with `PrimitiveFactory.ReplaceOrParent(parent, hierarchy.Model,
   options.ReplaceExisting)` for idempotent regeneration.
6. If it has runtime behavior, add `Runtime/YourThingController.luau` built on
   `ComponentRegistry.NewState`/`ConnectTouched`/`Check*Cooldown`/`Destroy`.
7. Register both in `PinballKit/init.luau`.

## Collision-group setup

`PrimitiveFactory.CreatePart` registers a part's `CollisionGroup` on demand
(idempotent, via `pcall(PhysicsService.RegisterCollisionGroup, ...)`, the same
pattern as `CabinetBuilder.ensureCollisionGroups`) if you pass one in a
generator's config. PinballKit does not define any global collision groups of
its own — following this project's existing precedent (`architecture.md`
"Flipper baseline": only the Flippers-vs-Playfield pair has its own groups,
everything else stays in whatever group the caller assigns), only introduce a
new group when a moving mechanism's swept volume legitimately overlaps static
geometry by design. Most PinballKit assets don't need one.

## Known Roblox physics limitations

- **Ball tunneling at high speed**: thin panels (rail/tunnel walls, wire
  rails) can, like any thin Roblox collider, be tunneled through by a
  fast-enough ball in a single physics step. `SegmentOverlap` mitigates seams
  between adjacent panels but does not fix high-speed tunneling; if it comes
  up, use the project's existing swept-collision handling if there is one, or
  add a narrowly-scoped spatial query fallback rather than making every panel
  thicker.
- **HingeConstraint has no native damping property**: `SpinnerGenerator`'s
  optional resistance uses `ActuatorType = Motor` with `AngularVelocity = 0`
  and a capped `MotorMaxTorque` as a damper, not a true friction model.
- **`CFrame.fromMatrix`'s 4-argument form does not enforce a proper
  (right-handed) rotation** — passing an inconsistent third axis silently
  produces a mirrored transform. Every call site in this library was checked
  by hand (see the comment in `Geometry/ProfileSweep.luau`); prefer the
  3-argument form (let Roblox derive the third axis) for any new symmetric
  shape (box/cylinder), and re-derive the cross-product identity by hand for
  anything asymmetric (like a WedgePart) before adding a 4-argument call.
- **Left/Right curve direction and yaw/tilt sign conventions have bitten this
  project before** (see `architecture.md`, "Flipper baseline") — `ArcMath`'s
  Left/Right derivation is documented and internally consistent, but has not
  been visually verified in Studio. Confirm a curved U-rail/tunnel/ramp
  actually curves the intended direction before relying on it in a real
  cabinet.
- **No headless test runner**: everything in `Validation/` can run from a
  Command Bar or a Studio test script, but there is no way to execute Luau or
  simulate Roblox physics outside Studio. The "ball actually rolls through
  without snagging" acceptance criterion (spec section 15/19) can only be
  checked live — drop a test ball on the demo layout and watch it.
