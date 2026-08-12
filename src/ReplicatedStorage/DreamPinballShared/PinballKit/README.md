# PinballKit

A reusable, typed-Luau library of classic Williams-style pinball components for
Dream Pinball, built on top of the existing Rojo project structure
(`src/ReplicatedStorage/DreamPinballShared/PinballKit/`). It started as a
separate, additive module family alongside `CabinetBuilder.luau`/
`CabinetLayouts.luau` (the 3-comparison-cabinet pipeline) and
`CabinetGameplay.luau` (the hand-built commercial-spec cabinet track). It now
also **integrates into `CabinetGameplay.luau` (every cabinet that uses it,
including `WilliamsCabinet`) and into `WilliamsCabinet` specifically** — see
"WilliamsCabinet integration" below for exactly what changed:
- `CabinetGameplay.luau`'s launch-time ball creation is routed through
  `BallGenerator` (behavior-neutral — same physical properties as before).
- `CabinetGameplay.luau`'s bumper scoring reads a per-instance `"PointValue"`
  attribute (falling back to the old flat `GameplayTuning.SCORE_PER_BOUNCE`
  constant), so each bumper/spinner/target's point value is finally
  independently configurable instead of one shared placeholder number.
- `CabinetGameplay.luau` looks for a plunger rod (by name, `"LaunchPlunger"`)
  under `LaunchAnchor` and drives it from the existing `BeginCharge`/`Launch`
  calls if found — hold R to pull it back, release to see it spring forward.
  Purely cosmetic; see `PlungerGenerator.luau`'s header comment for why it
  never touches actual launch velocity. Optional and found-by-name (same
  pattern as the backboard displays) — a cabinet with no plunger baked just
  has no plunger animation, no error.
- `WilliamsCabinet`'s hand-built flippers and bumpers can be swapped for
  PinballKit-generated ones, and new in-lane/out-lane dividers and a plunger
  rod added, via the generic `Migrations/CabinetUpgrade.luau` engine +
  `Migrations/WilliamsCabinetSpec.luau`'s measured numbers. Additive-only for
  flippers/bumpers (never touches the originals); lane dividers and the
  plunger are plain new additions since none exist today. Every one of these
  is baked once via the Command Bar and stays Explorer-visible from then on
  — nothing on this list is generated only at runtime except the ball itself
  (which inherently has to be, since it's created/destroyed every launch).

## Status

Every module here has been reviewed by hand but **has not yet been run inside
Roblox Studio** — there is no Luau runtime, Rojo, or Roblox physics engine
available outside Studio to execute or test it against. Per this project's own
`AGENTS.md` rule ("Do not claim a feature works until it has been tested in
Studio"), treat everything below as implemented-but-unverified until someone
syncs it in and runs the demo layout.

## WilliamsCabinet integration

`WilliamsCabinet` (`Workspace.BakedCabinets.WilliamsCabinet`) is the one live
cabinet. Its geometry is hand-built directly in Studio — it only exists in the
`.rbxl` place file, not in git/Rojo-tracked source, so none of this could be
done as a plain file edit; the flipper/bumper swap specifically has to run as
a script inside Studio.

### Code changes (git-tracked, revert with `git revert`/`git checkout`)

- **`GameplayTuning.FLIPPER_MOTOR_SPEED`**: 12 → 16. Read fresh on every
  flipper input, affects `WilliamsCabinet` immediately.
- **`CabinetGameplay.luau` ball creation**: now calls `BallGenerator.Generate`
  with the exact same PhysicalProperties/Material/Color as before
  (density 7.85, friction 0.3, elasticity 0.4, steel look) — a refactor, not a
  physics change.
- **`CabinetGameplay.luau` bumper scoring**: reads a `"PointValue"` attribute
  off the bumper's ancestor Model (via a new local `getPointValue` helper),
  falling back to `GameplayTuning.SCORE_PER_BOUNCE` if absent. Old hand-built
  bumpers with no attribute behave exactly as before.
- **`CabinetGameplay.luau` plunger**: `setup()` looks for a plunger rod named
  `"LaunchPlunger"` under the cabinet folder and wires it to the existing
  `BeginCharge`/`Launch` calls if found — optional, found-by-name, no error
  if absent. Applies to every cabinet that calls `CabinetGameplay.setup`
  (hand-built or `CabinetBuilder`-built), not just `WilliamsCabinet` —
  cosmetic only, ball launch velocity is unchanged. (An earlier version
  generated this at runtime instead of baking it — changed so every
  WilliamsCabinet asset is Explorer-visible the same way, not a mix of
  baked-in-Studio and appears-only-on-Play.)

### Flipper/bumper/lane generation (Studio-side, additive-only for
flippers/bumpers)

`Migrations/CabinetUpgrade.luau` is a generic engine, parameterized by a
`CabinetSpec` (marker names + measured numbers), so any future cabinet reuses
these same functions instead of a bespoke migration script — it should never
need to change per cabinet. `Migrations/WilliamsCabinetSpec.luau` supplies
WilliamsCabinet's own measured spec.

It builds PinballKit-generated flippers/bumpers — heavier/stronger/faster
flippers built to the measured spec, bumpers with a configurable
`PointValue` — **next to** the existing hand-built ones, and never touches,
renames, or deletes `LeftFlipper`/`RightFlipper`/`Bumper`. This is a
deliberate design from an earlier version that renamed the originals into a
backup folder and swapped the new ones in immediately — that added real risk
(a failure partway through left the cabinet without a working flipper at
all, twice) for a workflow that doesn't need it. Lane dividers (the whole
in-lane/out-lane guide, not a short decorative section) are a separate, plain
new addition — WilliamsCabinet has none today, so there's nothing to protect
and no finalize step for them.

**Flipper placement — two paths.**

The analytic path (centered on `DrainTrigger`'s edge, `FlipperSize`/
`FlipperRestAngleDegrees`/`FlipperRestTipGapStuds` deriving shaft-to-shaft —
see `computeTableFrame`) has produced a wrong result — wrong position and/or
wrong rest-angle direction — on multiple attempts on this cabinet, despite
each individual input being a real Studio measurement. Root cause not
pinned down; treat it as a fallback, not the primary path.

`CabinetSpec` supports a **position-only marker override** instead: if
`LeftFlipperPivotMarkerName`/`LeftFlipperTipMarkerName` both resolve to real
`BasePart`s **directly under the cabinet folder** (a common mistake: placing
them loose in `Workspace` instead of inside
`Workspace.BakedCabinets.WilliamsCabinet` — the lookup only searches inside
the cabinet folder), `GenerateNewFlippers` uses their positions directly
(pivot position + tip-minus-pivot direction) for the LEFT flipper instead of
the analytic derivation — no rotation, no sign convention, just two points.
The RIGHT flipper is then **mirrored from the left one across the table's
centerline** — deliberately not a second independently hand-placed pair,
since two markers placed by eye came out visibly asymmetric on this cabinet;
mirroring makes that impossible by construction. Height doesn't need to be
exact either: both points are snapped to `FloorMarkerName`'s
(`"CabinetFloor"`) own surface height + one ball radius before use, which
also flattens the pivot-to-tip direction (pivot and tip end up at the
identical height) — the flipper comes out parallel to the floor and centered
on the ball automatically, regardless of how precisely the markers were
placed vertically. `WilliamsCabinetSpec.luau` already points the two marker
names at `LeftFlipperPivotMarker`/`LeftFlipperTipMarker` — place two small
Parts with those exact names **inside the cabinet folder** (position only,
no rotation needed) at the correct pivot/tip locations by eye against the
reference photo, then re-run `GenerateNewFlippers` — it switches to the
marker path automatically, no code change needed. The console print tells
you which path was actually used. (If you placed
`RightFlipperPivotMarker`/`RightFlipperTipMarker` earlier, delete them —
they're unused now.)

**Lane dividers are a curved lead-in + straight run, not a plain wall** — a
straight wall only divides the lanes, it doesn't guide the ball into the
flipper the way a real lane guide's curved bottom end does. The curve's
`Direction` (`"Left"`/`"Right"`) is derived from which way `sideDirection`
actually points relative to the cabinet's own `Right` vector (see
`GenerateLaneDividers`'s comment) rather than assumed, so it bends the
correct way regardless of this cabinet's specific handedness.
`LaneDividerCurveRadiusStuds`/`AngleDegrees`/`InwardOffsetStuds` are all
estimates — tune and re-run.

**Step 1 — generate, in Studio's Command Bar (Edit mode):**

```luau
local cabinetFolder = workspace.BakedCabinets.WilliamsCabinet
local CabinetUpgrade = require(game.ReplicatedStorage.DreamPinballShared.PinballKit.Migrations.CabinetUpgrade)
local WilliamsCabinetSpec = require(game.ReplicatedStorage.DreamPinballShared.PinballKit.Migrations.WilliamsCabinetSpec)

CabinetUpgrade.GenerateNewFlippers(cabinetFolder, WilliamsCabinetSpec) -- creates LeftFlipper_New / RightFlipper_New
CabinetUpgrade.GenerateNewBumpers(cabinetFolder, WilliamsCabinetSpec)  -- creates Bumper_New_1, Bumper_New_2, ...
CabinetUpgrade.GenerateLaneDividers(cabinetFolder, WilliamsCabinetSpec) -- creates LaneDivider_Left(_Curve) / LaneDivider_Right(_Curve)
CabinetUpgrade.GenerateNewPlunger(cabinetFolder, WilliamsCabinetSpec)  -- creates LaunchPlunger
```

All four are safe to re-run — each call replaces its own previous output
(matched by name/GenerationId), never the hand-built originals. Compare the
new ones against the old ones. Per `architecture.md`'s own repeated warning
that yaw/orientation reasoning in this project has been wrong before without
live verification: check that each flipper sits near the right spot, its
paddle extends toward the correct side (not mirrored), and the shaft-to-shaft
distance printed by the generate call looks right. For lane dividers: they're
a plain straight wall matched to the slingshot's own height
(`LaneDividerHeight`), anchored laterally to `OuterWallMarkerName`'s
(`"cabinetwalls"`) own extent when found — otherwise `LaneDividerLateralOffset`
is a fallback estimate — starting `LaneDividerStartOffsetFromCenterlineEdgeStuds`
studs up-table from `DrainTrigger`'s edge and running `LaneDividerLength`
studs. `Length`/`StartOffset` are still estimates (see
`WilliamsCabinetSpec.luau`'s comments) — adjust and re-run until they match a
real Williams/Bally reference layout, and re-check them once the flipper
position itself is confirmed (the lane guide's start position is currently
independent of the flipper pivot on purpose, but both should visually line
up).

**Known open issue:** `GenerateNewBumpers` originally found zero bumpers
because `"Bumper"` resolves to a `Model` (wrapping a differently-named Part)
on this cabinet, not a plain `BasePart` — the same ambiguity that swapped
flipper left/right. Fixed by no longer requiring an exact `BasePart` match
(see `resolveNamedOriginalCFrame`) — not yet re-verified live.

**Cabinet reorientation (not done):** it was suggested that the whole cabinet
be rotated 180° so its own "up-table" direction aligns with a cleaner world
axis, to make future measurements less error-prone. Deliberately not
scripted — rotating a folder full of existing hinges/welds/constraints in
bulk with no live verification available is exactly the kind of hard-to-
reverse action worth doing by hand in Studio (select the relevant parts,
rotate as one unit) rather than blind via script. `CabinetUpgrade.luau`'s
math doesn't require this for correctness — it derives Up/Forward/Right from
`LaunchAnchor`/`playsurface` regardless of the cabinet's world orientation —
so it's optional, for human readability only.

**Step 2 — once you're happy with the flippers/bumpers, delete the originals
yourself** (`LeftFlipper`, `RightFlipper`, every `Bumper`) in the Explorer.
(Lane dividers need no equivalent step — they're already final.)

**Step 3 — finalize names**, only after the originals are actually gone
(these error if `LeftFlipper`/`RightFlipper`/`Bumper` still exist, specifically
so you can never end up with two things sharing the same marker name):

```luau
CabinetUpgrade.FinalizeFlipperNames(cabinetFolder, WilliamsCabinetSpec)
CabinetUpgrade.FinalizeBumperNames(cabinetFolder, WilliamsCabinetSpec)
```

This renames `LeftFlipper_New`/`RightFlipper_New` to `LeftFlipper`/
`RightFlipper`, and each new bumper's `Body` part to `Bumper` (matching what
`CabinetGameplay.luau` looks for by name), completing the swap. Bumper
scoring wiring only happens once, when `WilliamsCabinet.server.luau` calls
`CabinetGameplay.setup` at server start — so finalize before pressing Play,
not after.

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

This builds the full demonstration layout (spec section 14, plus the
Bally/Williams additions below: one of every rail/tunnel angle, one of every
ramp class, spinner, bumper, slingshot, hideaway/standup/drop targets,
one-way gate, diverter, kickout hole, ball trough, rubber post, rollover
switch, lane divider, a flipper pair, cabinet button, round/bar/ring inserts
with a sample sequence, labels, and 1.5-stud test balls) into
`Workspace.PinballKitDemo`. Re-running it replaces the previous demo. **Run
this from a server context** (Command Bar in Studio counts) — both the cabinet
button's `ProximityPrompt.Triggered` and `BallGenerator`'s `SetNetworkOwner`
call require server-equivalent permissions.

## Asset families

Beyond the original 12 (spinner, pop bumper, ramps, wire rails, U-half-pipe
rails, macaroni tunnels, slingshot, hideaway target, playfield inserts,
illuminated buttons), PinballKit also covers other classic Bally/Williams
mechanisms, built with the same rules (typed config, `GeometryValidator`
before generating, the standard Model/Root/folder contract, a matching
Runtime controller):

| Family | Generator | Controller | Notes |
| --- | --- | --- | --- |
| Ball | `BallGenerator` | — | Bare `BasePart`, not Model-wrapped (see its header comment) |
| Flipper | `FlipperGenerator` | `FlipperController` | Wraps `CabinetBuilder.attachFlipperHinge` — see below |
| Standup target | `TargetGenerator.GenerateStandup` | `StandupTargetController` | Fixed, no state machine |
| Drop target bank | `TargetGenerator.GenerateDropBank` | `DropTargetController` | Servo-driven per-target hinges |
| One-way gate | `RoutingGenerator.GenerateGate` | `RoutingController.AttachGate` | Weak Servo = spring return |
| Diverter | `RoutingGenerator.GenerateDiverter` | `RoutingController.AttachDiverter` | Strong Servo, script-commanded |
| Kickout hole / VUK | `CaptiveGenerator.GeneratePocket` | `CaptiveController` | Tall rim, vertical kick |
| Ball trough / drain feed | `CaptiveGenerator.GeneratePocket` | `CaptiveController` | Same generator, short rim, horizontal kick |
| Rubber bounce post | `ObstacleGenerator.GenerateRubberPost` | — (passive) | High elasticity only |
| Rollover lane switch | `ObstacleGenerator.GenerateRollover` | `RolloverController` | Non-colliding, flush with the floor |
| In-lane/out-lane divider | `LaneGenerator.GenerateDivider` | `LaneController` | Ball-scaled low guide wall, not a boundary wall; carries a programmable rollover trigger + indicator light (level decides what a pass does) |
| Plunger rod | `PlungerGenerator` | `PlungerController` | Servo-driven `PrismaticConstraint`; cosmetic only, never sets ball velocity (see its header comment) |
| Inlane/outlane pair | `InlaneOutlaneGenerator` | `LaneSwitchController` | One shared divider rail + two independent rollover triggers; enter/exit latch (not a time cooldown), see "Lower playfield composition" below |
| Lower-playfield assembly | `LowerPlayfieldGenerator` | `LowerPlayfieldController` | Composes a mirrored flipper pair, slingshot pair, inlane/outlane pair, and center drain from one `Origin` |

### Flipper: mechanism reused, tuning intentionally stronger

`FlipperGenerator` does **not** invent new flipper *mechanics*. Per
`architecture.md`'s "Flipper baseline" (locked, must not be re-derived from
scratch), it builds the same geometry as `CabinetBuilder.buildFlipper` — a
single invisible box collider with a tapered cosmetic cylinder-segment shell
welded on — and wires the hinge by literally calling
`CabinetBuilder.attachFlipperHinge`, the exact function this project's
hand-built (WilliamsCabinet-style) flippers use. `FlipperController` drives
input through `CabinetBuilder.setFlipperInput`, again the real function, not a
re-derived sign convention. If you need a flipper, use these — don't build a
new HingeConstraint by hand.

The *tuning* (mass, torque-per-mass, motor speed) is a different story:
`WilliamsClassic.Flipper`/`.FlipperRuntime` are deliberately **heavier and
stronger/faster than `CabinetLayouts.SHARED_FLIPPER_CONFIG`** — density 4.5
vs. 3, ~3400 torque-per-mass vs. ~2399.7, motor speed 16 vs. 12 — because live
playtesting found the existing board's flippers didn't hit the ball
reliably. This changes nothing about `CabinetBuilder.luau` or any existing
cabinet's behavior; it's purely PinballKit's own default, fully overridable
per instance. The reasoning (not just "bigger numbers"): a heavier flipper
loses less of its own velocity and imparts more to the ball on contact
(basic momentum transfer), and the torque increase gives enough headroom that
a ball landing on the flipper mid-swing doesn't visibly bog the motor down.
These are a reasoned starting point, not playtested numbers the way the
original baseline was — expect to retune live.

### Lower playfield composition

`LowerPlayfieldGenerator` builds a mirrored flipper pair, slingshot pair,
inlane/outlane pair, and center drain from one `Origin` -- a standalone,
generic PinballKit capability, not wired into `WilliamsCabinet` (that cabinet
keeps its own hand-built/marker-driven track, `Migrations/CabinetUpgrade.luau`,
untouched). Every piece is also usable on its own:

```luau
local PinballKit = require(game.ReplicatedStorage.DreamPinballShared.PinballKit)
local preset = PinballKit.Presets.WilliamsClassicLowerPlayfield

local flipperConfig = table.clone(preset.LowerPlayfield.Flipper)
flipperConfig.CollisionGroup = "MyTableFlippers" -- required, per-cabinet

local config = table.clone(preset.LowerPlayfield)
config.Flipper = flipperConfig

local assembly = PinballKit.Generators.LowerPlayfieldGenerator.Generate({
	Name = "LowerPlayfield",
	Parent = workspace.GeneratedPinballAssets,
	Origin = workspace.PlayfieldOrigin.CFrame,
	Config = config,
})

local controller = PinballKit.Runtime.LowerPlayfieldController.Attach(assembly, {
	FlipperMotorSpeed = preset.LowerPlayfieldRuntime.FlipperMotorSpeed,
	OnBallDrained = function(ball) ball:Destroy() end,
})
```

Supporting geometry modules, each independently reusable:

- `Geometry/MirrorTransform.luau` -- left/right mirroring primitives. This
  codebase has TWO different, individually-correct mirroring conventions
  (a true linear reflection for generic placement, vs. angle/offset
  negation for a flipper paddle's own near-planar symmetry) -- read its
  header comment before using it on a new shape.
- `Geometry/LanePath.luau` -- perpendicular-offset lane boundaries from a
  centerline, and `MinimumClearance`-checked width validation.
- `Geometry/GuideRailBuilder.luau` -- the per-segment wall-building math
  `LaneGenerator` and `InlaneOutlaneGenerator` both use, with optional
  rounded end caps.
- `Geometry/FlipperGeometry.luau` -- pure math (no Instances): resting/active
  tip gap, swept-envelope sampling, and `SolvePivotOffsetForCenterGap`, the
  formula that solves pivot spacing for a desired center-drain gap on a flat,
  mirrored-pair layout (a fresh derivation for the generic case, not a fix
  for `WilliamsCabinetSpec.luau`'s own marker-override workaround).
- `Validation/LowerPlayfieldValidator.luau` -- dimension, 0.01-stud symmetry,
  and sweep-vs-static-geometry checks against an already-generated assembly.
  Run it from the Command Bar after generating (see
  `Demo/GenerateLowerPlayfieldTest.luau`).

`FlipperGenerator`'s optional `ColliderMode = "SegmentedCapsule"` (rounded
root + tapered body + rounded tip, each overlapping the next) is opt-in --
the default `"SingleBox"` collider (this section's locked baseline) is
unchanged for every existing caller. Only
`Presets.WilliamsClassicLowerPlayfield.Flipper` opts into the capsule mode;
verify it live in Studio across the full stroke before trusting it on a real
table, the same as any other flipper-geometry change in this project's
history.

`server/PinballMechanisms.luau` (`ServerScriptService/DreamPinballServer/`) is
a generic flipper-input dispatcher for any `LowerPlayfieldGenerator`-based
cabinet -- a cabinet-id-keyed registry with per-cabinet ownership checks and
rate limiting, on the SAME shared `FlipperInputRemote` `WilliamsCabinet.
server.luau` already uses. Both listeners coexist independently; neither
touches the other.

### Physics-first design choices this round

Since a ball's realistic reaction to these parts mattered more than visual
completeness for this batch:

- Drop targets and gates/diverters use real `HingeConstraint`s (`Servo`
  actuator), not `TweenService` position animation — driving `TargetAngle`
  physically pushes anything in the way (including the ball) along the route,
  and a gate's weak `ServoMaxTorque` genuinely has to be overpowered by a
  rolling ball, not scripted open.
- `BallGenerator`'s physical properties (density 2.75 / friction 0.35 /
  elasticity 0.65) are copied from this project's own live-playtested ball
  (`CabinetDesignsTest.server.luau`'s `LaunchBall`), not invented fresh — see
  that generator's header comment about `PhysicsTestRig.server.luau`'s
  ongoing investigation into whether this tuning is even correct.
- `BallGenerator` calls `ball:SetNetworkOwner(nil)` and leaves the ball in the
  `Default` collision group (matching `CabinetDesignsTest`'s ball exactly) —
  never assign a generated ball to a Flippers or Playfield group, or it will
  silently stop colliding with one of them.

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

### Scoring: `PointValue`

Scoring-capable generators (`BumperGenerator`, `SlingshotGenerator`,
`SpinnerGenerator`, `TargetGenerator`'s standup/drop-bank variants,
`ObstacleGenerator.GenerateRollover`) accept an optional `PointValue: number?`
in their Config, stamped as a `"PointValue"` attribute
(`Constants.POINT_VALUE_ATTRIBUTE`) on the asset's root Model when set. This
replaces having one flat shared constant (`GameplayTuning.SCORE_PER_BOUNCE`)
apply identically to every instance — each placed bumper/target/etc. can now
award a different amount. Left unset by default (a generator shouldn't invent
a game's scoring balance); game-integration code reads the attribute and
falls back to whatever default makes sense for that game (see
`CabinetGameplay.luau`'s bumper scoring for the pattern). Only bumper scoring
in `CabinetGameplay.luau` actually reads this today — slingshot/spinner/target
scoring isn't wired into `WilliamsCabinet`'s gameplay loop yet, so their
`PointValue` attribute is stamped and ready but currently unused there.

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

**`FlipperGenerator.FlipperConfig.CollisionGroup` is functionally required**
(optional in the type so `Presets.Extend` can fill it in per-cabinet, but
`Generate` raises immediately if it's still `nil`) — a flipper's swept volume
overlaps the floor by design, exactly like `CabinetBuilder`'s own flippers, so
it needs its own group with collision against the playfield's group disabled.
`FlipperGenerator` self-registers the group name you pass (same
`pcall`-wrapped idempotent pattern), but does **not** call
`CabinetBuilder.ensureCollisionGroups` for you — if you have a real playfield
group to exclude, register that exclusion yourself, the same way
`CabinetGameplay.luau` does for hand-built cabinets.

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
- **`Servo`-actuated `HingeConstraint`s (drop targets, gates, diverters) have
  not been live-tuned**: `ServoMaxTorque`/`AngularSpeed` defaults are
  reasonable guesses, not playtested values like the flipper's numbers are.
  A gate's return spring in particular may need retuning live — too strong
  and the ball can't push it open, too weak and it doesn't reliably reset.
- **The demo's flipper pair uses one shared, demo-only collision group**
  (`PinballKitDemoFlippers`), since the demo has no real playfield floor for
  them to need separation from. A real cabinet must still pair
  `FlipperGenerator`'s group with `CabinetBuilder.ensureCollisionGroups` (or
  equivalent) against its actual playfield group.
