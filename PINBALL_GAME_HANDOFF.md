# Pinball Roguelike — Full Game Vision + Sand Level Prototype Spec

## PROTOTYPE SCOPE (read this first)
Building ONLY the Sand level (World 1, Level 1 of 5: Sand > Shallow Water >
Water > Deep Water > Leviathan boss). No hub, no meta-currency, no
Shallow/Water/Deep/Leviathan content yet. Everything below the "Full Game
Vision" section is long-term design context — not all of it is in scope for
this build. See "Sand Level Prototype Spec" for what to actually build.

---

## FULL GAME VISION (original design doc)

Follows a roguelike formula where you start a run with a group of pinballs
that have different abilities and enter a pinball machine. In the machine you
can have around 5-ish encounters (these can be fights with the beings in the
machine, shops, chance encounters, quests, or other various things) after the
encounters you must fight a harder boss (this one will scale based on how many
machines previously beaten and you must pass have a certain criteria to beat
them [this adds an rng element to worlds]) after beating the boss you enter a
"hub" world in between machines that has a shop (most likely with worse stuff
than encounter shops) and a place where you can save and pick up back on a
run.

### Character
Your character will start a run with a certain "build" that consists of
different balls with different abilities. There will also be accessories that
can give more perks to your character, these can be upgraded either through
points or (preference) an encounter in a machine. Your character could also
have abilities that can help while in combat. Along with items (these could
range from boosts to points to free extra balls).

### Combat
When in combat encounters — rather than a normal enemy or boss — you win by
reaching a point threshold. Depending on the enemy you face it'll depend on
what type of ball you will need to use.

How combat works: when a fight starts you get balls from your deck (from a
gum-ball machine, at random) into your hand. From here you have 4 options:

- **LAUNCH** — send out one of the pinballs in your hand into the machine,
  where you play a game of pinball to deal damage. Pinballs have durability so
  you can't keep a ball going forever. If a ball lands in the launch-again
  section of the machine, it returns to your hand. Turn ends after you
  launch.
- **ITEM** — access your inventory, use up to 3 items a turn. Certain
  combinations can give special effects.
- **CHARACTER** — use abilities from your character or equipment. Limited to
  one per turn, but much more powerful.
- **SPIN** — take a turn to get a new pinball into your hand. Ends your turn.

Against bosses: you must fulfill a certain criteria (e.g. hitting certain
targets makes the boss susceptible to damage / gain more points). Bosses can
have machine hazards that make it harder to gain points (e.g. spikes that
destroy your ball on contact).

### Collecting "creatures"
The balls you launch into machines take the form of various creatures you can
collect and use. Each creature has different stats and attributes. Acquired
via items and by completing quests and minigames.

### Stat sacrificing
Certain balls have abilities that help in fights. These can be sacrificed
(most likely at an encounter) to put an extra attribute on another ball. The
number of attributes that can be put on one ball depends on rarity.

### Dreams (worlds)
The machines you jump into take place in dreams. Each has different events and
balls exclusive to it, and follows a certain attribute throughout its fights,
with the boss having something similar but harder. Each world has a specific
weakness that can be exploited if you have certain balls.

---

## DESIGN DECISIONS LOCKED (from Q&A)

### Movement / camera
- Menu-driven (click) outside encounters
- Q/E controls bumpers/paddles during LAUNCH
- WASD usable for UI traversal (controller-portability)
- Fixed/angled camera per table during levels (no player camera control)
- First/third-person free camera in the hub only (post-world, out of scope
  for this prototype since no hub is being built yet)

### Combat model (hybrid)
- Menu-driven turns: LAUNCH / ITEM / CHARACTER / SPIN
- LAUNCH hands real-time control to the player: Q/E move bumpers, ball physics
  plays out until it drains or returns to the launch lane (ends turn)
- SPIN: draw a random ball from the FULL collection (not just current hand
  pool) into hand, ends turn
- ITEM: use up to 3 items/turn from inventory
- CHARACTER: 1 ability/turn, character only buffs/transmits effects to balls,
  no direct combat action of its own

### Win/loss
- Fights: reach point threshold within 5 turns or it's a loss
- Threshold value is per-encounter, NOT a global constant
- Non-fight encounters (quests/favors): fulfill requirement or skip, no fail
  state either way, continue on
- No continues on death — full run restart, no exceptions

### Balls / creatures
- 3 hand slots at run start (expandable via purchase later — post-prototype)
- Stats: Speed, Atk, Def, HP (confirm/expand as needed during build)
- Durability drops per SCORING bounce only (not every physical hit) — ball
  breaks and leaves the hand for the rest of the run at 0 durability
- Power-ups can modify durability / durability-loss rate (post-prototype)
- Single-type balls for v1; dual-type deferred to later worlds
- 8 elements total: Water, Grass, Rock, Earth, Air, Fire, Nightmare, Dream
- Type effectiveness: SOFT multiplier (resist/neutral/weak, Pokémon-style),
  not a hard counter — build the full 8x8 table now even though only
  Water-type is active in the Sand level, to avoid rework later
- Stat sacrifice: sacrifice a ball (at an encounter) to add an attribute to
  another ball; number of attribute slots gated by rarity tier (exact slot
  counts per rarity TBD — not blocking for Sand-level build since this system
  is post-prototype)

### Items (single-use, applies to next launched ball only)
| Item | Effect |
|---|---|
| Feather | Ball falls slower; -10 Speed, -10 Atk |
| Coffee | +10 Speed |
| Extra Ball | Adds a consumable neutral ball to hand: base stats, no element, no abilities |
| Magnet | +10 attraction to paddles, -10 Speed |
| Hammer | Destroys the first obstacle the ball hits |

### Characters (choose 1 at run start)
- Striped PJ: +10% to one stat (tankier lean)
- Dinosaur Onesie: +10% to one stat (speed lean)
- Characters only apply effects/buffs to balls via the CHARACTER action — no
  direct combat action of their own

### Accessories
- Upgrade path: ENCOUNTER-based only for v1 (not points-based)

### Currency (dual-tier, long-term design)
- Run-currency: earned per encounter/quest completion, spent at in-machine
  shops, does NOT persist between runs
- Meta-currency: earned at safe points/run-end, DOES persist across runs, buys
  permanent abilities/accessories — OUT OF SCOPE for Sand-level prototype
  (requires the hub, which isn't being built yet)

### World 1 (Ocean world, 5 levels total)
- Level order: Sand > Shallow Water > Water > Deep Water > Leviathan (boss)
- All creatures in World 1 are Water-typed (or Water-primary once dual-typing
  exists)
- Boss: Leviathan — mechanic/criteria details deferred, not needed for
  Sand-level prototype
- 3 distinct creature/ball types found in the Sand level specifically

### Persistence
- Autosave at end of every level (not mid-level)
- Full run state persists: seed, hand, inventory, position in run,
  run-currency (meta-currency persistence is post-prototype, tied to hub)
- Individual levels (pre-hub) only show inventory/equipment — no world map/hub
  UI until a full world is cleared

### Platform / assets
- PC first, console second, mobile third (or simultaneous if the system
  supports it) — build input-agnostic (WASD/click + controller-portable) from
  day one
- Art created manually in Roblox Studio, tied to what Claude Code builds
  (art pipeline is manual, not procedural)
- No monetization plan for this phase

### Repo / tooling
- Rojo — see `architecture.md`'s "Sync tooling history" section (originally
  built without Rojo, migrated to it after repeated native Script Sync bugs)
- Server already set up

---

## SAND LEVEL PROTOTYPE — BUILD ORDER

1. Data schemas (ModuleScripts): `Ball`, `Character`, `Item`, `Encounter`
2. Type-effectiveness table (full 8x8, soft multipliers)
3. Repo structure: `src/client`, `src/server`, `src/shared`, plus `TODO.md`
   and `architecture.md` at repo root
4. Fixed camera rig for in-level table view
5. Bumper control script (Q/E input → physics impulse) on an empty test table
6. Turn-state machine: hand (3 slots), 4-action menu, turn counter, 5-turn
   loss condition
7. Launch → physics segment → return-to-hand or durability-loss (per scoring
   bounce) → back to menu loop
8. Item system: single-use, modifies only the next-launched ball, consumes on
   use
9. One full Sand-themed (Water-type) encounter wired end-to-end: spawn → fight
   → threshold win/loss (threshold value TBD per encounter, not global)
10. Run-currency: award on encounter/quest completion
11. Basic in-machine shop (run-currency only — no meta-currency, no hub)
12. Autosave at level-end: seed, hand, inventory, run-currency
13. Minimal HUD: hand display, threshold progress, turn counter, per-ball
    durability
14. Playtest full Sand-level loop end-to-end before touching hub,
    meta-currency, or stat-sacrifice UI (all post-prototype)

## EXPLICITLY OUT OF SCOPE FOR THIS BUILD
- Hub world (shops, save-and-resume-between-machines, first/third-person
  free camera)
- Meta-currency and anything it unlocks
- Stat sacrifice system
- Dual-type balls
- Shallow Water / Water / Deep Water / Leviathan boss content
- Accessory purchasing beyond encounter-based drops
- Extra hand-slot purchasing
