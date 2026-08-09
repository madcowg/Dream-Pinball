--!strict

--- Placeholder test balance values shared by every cabinet's gameplay wiring
--- (CabinetDesignsTest.server.luau's code-built cabinets AND CabinetGameplay.luau's
--- hand-built ones) so the two can't silently drift apart. NOT final encounter
--- design/balance -- see PINBALL_GAME_HANDOFF.md for that.
local GameplayTuning = {}

GameplayTuning.SCORE_PER_BOUNCE = 10
GameplayTuning.DURABILITY_LOSS_PER_BOUNCE = 1
GameplayTuning.BOUNCE_DEBOUNCE_SECONDS = 0.5
GameplayTuning.LAUNCH_SPEED_TO_VELOCITY_SCALE = 15 -- 2x, per playtesting: spring needed more power to clear the lane
GameplayTuning.BUMPER_KICK_STRENGTH = 30 -- active outward kick on contact, not just passive elasticity

-- Roblox's stock Humanoid defaults -- restored when a cabinet's movement lock releases.
GameplayTuning.DEFAULT_WALK_SPEED = 16
GameplayTuning.DEFAULT_JUMP_POWER = 50
GameplayTuning.DEFAULT_JUMP_HEIGHT = 7.2

-- Locked flipper baseline (see architecture.md "Flipper baseline") -- used
-- both by CabinetLayouts.luau's SHARED_FLIPPER_CONFIG (code-built cabinets)
-- and CabinetBuilder.attachFlipperHinge (hand-built cabinets, e.g.
-- WilliamsCabinet), so a hand-built flipper's swing feels identical to the
-- three code-built comparison cabinets by default.
GameplayTuning.FLIPPER_UP_ANGLE_DEGREES = 45
-- FLIPPER_MOTOR_TORQUE is an ABSOLUTE torque value, correct only for a
-- flipper with the SAME mass as CabinetLayouts.luau's code-built reference
-- flipper (measured live: AssemblyMass ~36.46 -- a Union/Part combo built
-- from FlipperSize (7.5, 1.25, 2.5) and density 3). Applying this same flat
-- number to a hand-built flipper with a different mass produces a badly
-- wrong torque-to-mass ratio -- confirmed live on WilliamsCabinet, whose
-- flipper massed only ~8.13 (4.5x lighter) while receiving the identical
-- 87500 torque, causing exactly the jittery/inconsistent/barely-swinging
-- behavior reported during playtesting (flippers producing scoring bounces
-- on only 2 of 5 launches, AssemblyAngularVelocity reading ~0 at almost
-- every sampled moment).
--
-- CabinetBuilder.attachFlipperHinge (used by hand-built cabinets) does NOT
-- use this constant directly -- it uses FLIPPER_MOTOR_TORQUE_PER_MASS
-- below, multiplied by the ACTUAL flipper's measured AssemblyMass at build
-- time, so torque scales correctly regardless of the flipper's real size/
-- density. CabinetBuilder.buildFlipper (code-built cabinets) still uses
-- FLIPPER_MOTOR_TORQUE directly, since those flippers are always built to
-- the one reference mass this ratio was calibrated against.
GameplayTuning.FLIPPER_MOTOR_TORQUE = 87500
-- = 87500 / 36.46 (the reference flipper's live-measured AssemblyMass),
-- i.e. "how much torque per stud of flipper mass" -- keeps the SAME swing
-- feel as the reference cabinet on any flipper, any mass.
GameplayTuning.FLIPPER_MOTOR_TORQUE_PER_MASS = 2399.7
-- Bumped from 12 -> 16 (~33%): live playtesting on WilliamsCabinet found the
-- baseline swing speed unreliable at hitting the ball even after fixing the
-- torque-per-mass bug documented above (see PinballKit's FlipperGenerator.luau
-- for the matching heavier/stronger flipper defaults this pairs with). Read
-- fresh on every setFlipperInput call (not baked in at hinge-creation time
-- like torque is), so this affects every hand-built AND code-built flipper's
-- commanded speed immediately.
GameplayTuning.FLIPPER_MOTOR_SPEED = 16

return GameplayTuning
