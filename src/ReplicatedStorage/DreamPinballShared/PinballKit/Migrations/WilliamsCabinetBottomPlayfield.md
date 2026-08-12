# WilliamsCabinet Bottom-of-Playfield Spec

Consolidated reference for the flipper/drain/slingshot/lane-guide system at
the bottom of WilliamsCabinet's playfield. Every number below is tagged with
where it actually came from — **MEASURED** (given directly, from a real
Studio measurement of this cabinet), **REFERENCED** (a real-world Williams/
WPC/Bally standard found via web research, with a citation), **DERIVED**
(computed from MEASURED/REFERENCED numbers via geometry, not a second
independent measurement), **LIVE-READ** (computed at generation time from
another part's actual current position/size, not a fixed constant), or
**ESTIMATE** (a reasonable guess with no measurement or citation behind it,
needs a real number or visual tuning). Treat this file, not scattered chat
history or code comments, as the authority — update it whenever a number
changes, the same way `WilliamsCabinetSpec.luau` gets updated.

This follows PinballKit's own foundational rules (the original spec, cited
throughout the codebase as `-- spec section N`):
- **Dimension sourcing must be tagged** (spec section 3) — never claim a
  Williams-hardware dimension without a citation. The tags above are this
  project's version of that rule; REFERENCED entries below link their source.
- **Ball clearance**: any enclosed path/tunnel/gate the ball travels through
  needs at least 0.1 studs of radial clearance per side (`Scale.
  MIN_RADIAL_CLEARANCE_STUDS`), i.e. minimum inner diameter = ball diameter
  (1.5 studs) + 0.2 studs = 1.7 studs. The lane guides here are a single
  wall, not an enclosed tunnel, so this rule constrains their *height*
  (tall enough the ball can't hop over) rather than an inner diameter.
- **Standard hierarchy** (spec section 6): every generated asset is a Model
  with Root/Visuals/Colliders/Triggers/Mechanism/Lights/Attachments, stamped
  with `PinballAsset`/`AssetType`/`AssetVersion`/`GenerationId` attributes.
- **Idempotent generation** (spec section 12): regenerating replaces the
  previous output by `GenerationId`, never duplicates, never touches
  anything else in the parent container.
- **Real physics over scripted animation**: flippers reuse
  `CabinetBuilder.attachFlipperHinge` (the locked baseline mechanism, not
  re-derived); the plunger uses a `PrismaticConstraint`, not a CFrame tween.

**Conversion used throughout**: `STUDS_PER_INCH = 1.5 / 1.0625 ≈ 1.41176`
(one real pinball diameter, 1.0625in, equals 1.5 studs).

## Coordinate frame (how "up-table," "centerline," and "left/right" are found)

Defined in `CabinetUpgrade.luau`'s `computeTableFrame`/`computeFloorReference`
/`computeCenterlineAxis` — restated here so this spec is self-consistent with
the code, not a separate story:
- **Up** — `CabinetFloor`'s own surface normal (sign-corrected skyward). The
  authority for "flat" and "correct height," not `playsurface` (a decorative
  overlay, not necessarily co-planar with the real collision floor).
- **TableForward** (up-table, away from the drain) — `LaunchAnchor`'s
  `LookVector`, projected flat against Up. `CabinetGameplay.luau`'s own doc
  comment guarantees this points at the main playfield.
- **Right** — `TableForward x Up`.
- **Centerline** — `DrainTrigger`'s own lateral position (assumed centered
  on the table by construction — it's where a drained ball falls, which is
  the bottom-center of a real table).
- **Left vs. Right (handedness)** — decided by checking `slingshotL`'s
  current position against `Right`, trusted for handedness only, never for
  placement.

## Flippers

| Value | Number | Source |
|---|---|---|
| Length (pivot to tip) | 3 in ≈ 4.235 studs | **MEASURED** (this cabinet, Studio) — independently corroborated: pinball parts suppliers sell "Flipper Bat 3 Inch" as a standard WPC/Williams part |
| Height (vertical thickness) | 0.788 studs | **MEASURED** — but from the *other*, non-Rojo place file's flipper, not this cabinet directly. Re-verify if this cabinet's real flipper hardware differs. |
| Width (in-plane, perpendicular to length) | 1.126 studs | Same caveat as Height above |
| Rest angle | 30° | **MEASURED** direction ("30 degrees inward") + **DERIVED** sign (+30, not -30 — confirmed live by decomposing a generated flipper's actual rotation matrix; -30 put the rest tip pointing up-table instead of down-table toward the drain) |
| Sweep (rest → up angle) | 50° | **MEASURED** |
| Tip-to-tip gap at rest | 1.375 in ≈ 1.941 studs | **MEASURED** — kept for reference/sanity-check only now (see Shaft-to-shaft below) |
| **Shaft-to-shaft distance** | **7 in ≈ 9.88 studs** (real-world range 6-13/16in–7in ≈ 9.62–9.88 studs) | **REFERENCED**: [pinballmakers.com Design wiki](https://pinballmakers.com/wiki/index.php?title=Design) states flipper shafts on most WPC (Williams) games are 6-13/16in to 7in center-to-center. This matches the ~9.9 studs originally given for this cabinet almost exactly. **This now overrides the Gap/Length/RestAngle-derived value** (`Gap + 2·Length·cos(RestAngle)` ≈ 9.28 studs), which came out smaller and produced flippers that visually crossed on WilliamsCabinet — wired into `CabinetUpgrade.luau` as `FlipperShaftToShaftStuds`, which takes priority over the derivation when set. |
| Flipper shaft position | 7 in ≈ 9.88 studs up from the **bottom edge of the physical playfield** (a different reference point than DrainTrigger) | **REFERENCED** (same source, explicitly "most WPC games") — a useful cross-check against the "6 studs up from DrainTrigger's edge" MEASURED number below, though the two use different reference points (playfield bottom edge vs. DrainTrigger's edge) so they aren't directly comparable without also knowing DrainTrigger's own distance from the playfield's bottom edge |
| Pivot's up-table position (as currently coded) | 6 studs up-table from `DrainTrigger`'s own up-table **edge** (not its center) | **MEASURED** ("6 studs up from the edge of DrainTrigger") — the analytic version of this (combined with the flipper numbers above) has produced a wrong result multiple times in a row on this cabinet, even before the shaft-to-shaft fix above. Prefer the position-only marker override (`LeftFlipperPivotMarker`/`LeftFlipperTipMarker`, mirrored across centerline for the right side) over this derivation if it's still wrong. |

**Still open**: the analytic path's exact position (independent of the
shaft-to-shaft fix) hasn't been re-verified since this round of research.
Re-test on the replica; if it's still off, get a direct measurement of pivot
position relative to `DrainTrigger` rather than another derivation attempt.

## Drain / centerline anchor

`DrainTrigger` is the fixed reference everything else is built from — its
own position (lateral = centerline) and up-table edge (found via its own
`Size`, projected onto TableForward — **LIVE-READ**, not a fixed number).

## Slingshots

| Value | Number | Source |
|---|---|---|
| Width / Depth / Height | 3 / 2 / 2 studs | **ESTIMATE** (`WilliamsClassic.Slingshot` preset — a "GameplayDefault," not measured Williams hardware, per that preset file's own header) |
| Current separation (hand-built, live) | ≈ 15.9 studs apart | **LIVE-READ** from the two existing `slingshotL`/`slingshotR` parts |
| Slingshot rubber span (outside-to-outside) | ≈ 11-7/8 in ≈ 16.77 studs | **REFERENCED** (Bally-specific figure found via web research) |
| Slingshot top-post centers | ≈ 11 in ≈ 15.53 studs | **REFERENCED** (same source) |
| Correct sling rubber size | 3in band (not 4in) | **REFERENCED** ([Short Circuit Pinball build log](https://shortcircuitpinball.blogspot.com/2016/02/solenoids-and-slingshots.html), a homebrew builder's own corrected measurement) |

**This changes the earlier conclusion.** Previously this file said the
slingshots need to move inward to ~9.28 studs apart to match the flipper
layout. The REFERENCED slingshot rubber span (~16.77 studs) and post-center
spacing (~15.53 studs) are both **close to this cabinet's current ~15.9-stud
separation** — meaning the hand-built slingshots may already be roughly the
correct real-world width, and it was the FLIPPER shaft-to-shaft (now fixed
to ~9.9 studs above) that needed correcting, not the slingshots. On a real
table the slingshots flare outward, wider than the narrower flipper pair
below them — this is consistent with that shape, not a contradiction.

**Resolved (superseding the "Resolved" note in an earlier draft of this
section)**, per direct correction: the slingshot is not a separately-gapped
object sitting between two stacked 1.941-stud gaps. **The slingshot's own
outer face IS the inlane's inner wall.** The inlane channel is continuous —
it runs alongside the slingshot's own outer edge, 1.941 studs away the whole
time, and simply ends when the top of the flipper starts (no additional
stacked gap between the slingshot's bottom edge and the flipper). See Lane
guides below for exactly how this is now wired in.

**Open question, not yet resolved**: `CabinetUpgrade.RepositionSlingshots`
still MUTATES each slingshot's up-table position to enforce a 1.941-stud gap
between the flipper's top and the slingshot's bottom edge — that logic
predates this correction (it modeled a stacked gap that no longer exists in
the corrected topology) and has NOT been updated to match. Do not run it
without re-deciding what, if anything, it should still do — it may just be
obsolete now that `GenerateLaneDividers` reads the slingshot's actual live
position directly and routes around wherever it already is.

## Lane guides (in-lane/out-lane)

**Topology (corrected a second time — the drawing showed a single sweeping
hook, not a curve-then-parallel-straight-run)**: the rail's lateral position
is derived entirely from the slingshot's own current outer edge — NOT from
`cabinetwalls` at all. The slingshot's face IS the inlane's inner wall (see
Slingshots above), so the rail's inner face is pinned to
`slingshot's outer edge + OUTLANE_CHANNEL_WIDTH_STUDS`. ONE continuous curve
connects the flipper's physical **top** (`computeFlipperTopPosition` — the
pivot-end FACE of the flipper's box geometry, not the mathematical pivot
point itself) directly to that rail position, spanning the slingshot's
**entire depth** in a single sweep (the curve's forward target is the
slingshot's TOP edge, not its bottom edge) — both the curve's forward span
and its lateral shift are read live, so `solveArcForDisplacement`
(closed-form, via the half-angle identity
`tan(θ/2) = lateralDistance/forwardDistance`, derived from `ArcMath.luau`'s
own position formula) lands it exactly there — no free choice left in the
curve at all, and no separate straight segment hugging the slingshot's edge
in parallel. This is "the inlane ends when the top of the flipper starts":
no stacked gap, the curve lands ON the flipper. Only a short straight TAIL
(`LaneDividerLength` studs) continues beyond the slingshot's top edge, in
whatever direction the curve ends up tangent to.

`cabinetwalls` is used only AFTER the rail is positioned, as a diagnostic:
`GenerateLaneDividers` prints the achieved outlane width (rail's outer face
to `cabinetwalls`' inner face) so it can be compared against the same
1.941-stud target, with `LaneDividerThickness` as the one variable tuned to
close any leftover mismatch — the code does not force `cabinetwalls` or the
slingshot to move to make the numbers fit.

| Value | Number | Source |
|---|---|---|
| Channel width (slingshot-to-rail gap AND rail-to-outer-wall gap) | 1-3/8 in ≈ 1.941 studs | **REFERENCED** (Bally-specific: "the lanes are 1 3/8\" (inlane and outlane)") — `OUTLANE_CHANNEL_WIDTH_STUDS` in `CabinetUpgrade.luau`, used for BOTH channels per direct instruction that they're the same unit |
| Height | 2 studs (matched to slingshot height) | ESTIMATE |
| Thickness | 0.3 studs starting point | **ESTIMATE, deliberately tunable** — `LaneDividerThickness`; adjust based on the achieved-outlane-width print (larger = narrower outlane, smaller = wider outlane) |
| Curve forward span | derived from the flipper-top-to-slingshot-**top**-edge distance (spans the slingshot's entire depth in one sweep) | **LIVE-READ**, no longer a free layout choice — the curve's endpoint is fully determined by real geometry |
| Straight tail length | 11 studs, starting past the slingshot's top edge | **ESTIMATE** (`LaneDividerLength`) — no longer includes the slingshot's own depth, since the curve now covers that |
| Lateral position (rail) | slingshot's own outer edge + channel width | **LIVE-READ** + REFERENCED channel width — NOT derived from `cabinetwalls` |

Curve `Direction` (`"Left"`/`"Right"`) is **DERIVED**, not guessed: whichever
of `+Right`/`-Right` the divider's own `sideDirection` points along decides
it (see `GenerateLaneDividers`'s comment in `CabinetUpgrade.luau`).

**Re-verify on the replica**: confirm the curve visibly lands on the flipper
and doesn't clip through it, and that the printed achieved-outlane-width is
reasonably close to 1.941 studs — this hadn't been visually confirmed as of
this writing.

Bumpers are explicitly out of scope for this spec — not part of the bottom-
of-playfield system being fixed right now, and their dimensions are the
designer's call, not a fixed spec.

## Build order for the replica

1. Clone `WilliamsCabinet` → test replica (script below). Point every
   `CabinetUpgrade` call at the replica's folder instead of the live one.
   `WilliamsCabinetSpec.luau` itself doesn't need a separate copy — it works
   against whatever `cabinetFolder` is passed in.
2. Verify `DrainTrigger`/`CabinetFloor`/`cabinetwalls`/`LaunchAnchor` resolve
   correctly on the replica (they're cloned 1:1, so this should just work).
3. Place `LeftFlipperPivotMarker`/`LeftFlipperTipMarker` on the replica,
   sized against the shaft-to-shaft target above (**≈9.88 studs**, not the
   old ≈9.28) rather than eyeballing purely from the reference photo — use
   the number to sanity-check the placement before generating.
4. Generate flippers, check shaft-to-shaft printout against the ≈9.88 target
   and confirm the bats don't cross.
5. **Do not run `CabinetUpgrade.RepositionSlingshots` yet** — its up-table
   repositioning logic predates the "inlane ends when the top of the flipper
   starts" correction and hasn't been reconciled with it (see Slingshots
   above). Leave the slingshots wherever they already are.
6. Generate lane guides. The rail derives its lateral position from each
   slingshot's own current outer edge and the curve solves to land exactly
   on the flipper's physical top — visually confirm it reads as guiding the
   ball into the flipper, and check the printed achieved-outlane-width
   against the 1.941-stud target, adjusting `LaneDividerThickness`/
   `LaneDividerLength` as needed.
7. Only once all of the above looks right on the **replica**, decide whether
   to port the finalized numbers back to `WilliamsCabinetSpec.luau` for the
   live cabinet.

## Sources consulted (web research)

- [pinballmakers.com — Design](https://pinballmakers.com/wiki/index.php?title=Design) — WPC flipper shaft-to-shaft (6-13/16in–7in) and shaft position (7in from playfield bottom edge)
- [Short Circuit Pinball — Solenoids and Slingshots](https://shortcircuitpinball.blogspot.com/2016/02/solenoids-and-slingshots.html) — correct sling rubber size (3in band)
- General web search results (aggregated, no single authoritative page) — Bally inlane/outlane width (1-3/8in); Bally sling rubber span (~11-7/8in) and post centers (~11in); flipper bat 3in confirmed independently via multiple parts-supplier listings
