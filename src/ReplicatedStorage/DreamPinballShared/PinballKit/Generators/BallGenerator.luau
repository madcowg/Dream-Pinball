--!strict

-- The pinball itself. Deliberately does NOT use PrimitiveFactory's standard
-- Model/Root/Visuals/Colliders/.../Attachments hierarchy that every other
-- PinballKit asset uses -- a ball is spawned and destroyed constantly during
-- normal play (once per launch, at minimum), not a static decoration, so
-- wrapping every one in a Model plus six Folders would be pure overhead with
-- no benefit. `BallGenerator.Generate` returns a bare, physics-ready BasePart.
--
-- Tuning is copied from this project's existing, live-playtested ball
-- construction (CabinetDesignsTest.server.luau's LaunchBall) rather than
-- invented fresh -- see that file's comments for why these specific numbers
-- (2.75 density, 0.35 friction, 0.65 elasticity) were chosen over Roblox's
-- defaults. NOTE: PhysicsTestRig.server.luau is actively testing whether
-- removing this custom tuning entirely changes observed "askew" ball
-- behavior -- if that investigation concludes the tuning itself is the
-- problem, update DEFAULT_PHYSICAL_PROPERTIES here to match whatever the
-- project settles on, don't treat these numbers as permanently correct.

local Scale = require(script.Parent.Parent.Scale)
local GeometryValidator = require(script.Parent.Parent.Validation.GeometryValidator)

local BallGenerator = {}

export type BallConfig = {
	Diameter: number?,
	Color: Color3?,
	Material: Enum.Material?,
	Density: number?,
	Friction: number?,
	Elasticity: number?,
	FrictionWeight: number?,
	ElasticityWeight: number?,
	Name: string?,
	CFrame: CFrame,
	Parent: Instance?,
}

-- Matches CabinetDesignsTest.server.luau's LaunchBall exactly.
local DEFAULT_DENSITY = 2.75
local DEFAULT_FRICTION = 0.35
local DEFAULT_ELASTICITY = 0.65
local DEFAULT_FRICTION_WEIGHT = 1
local DEFAULT_ELASTICITY_WEIGHT = 1

function BallGenerator.Generate(config: BallConfig): BasePart
	local diameter = config.Diameter or Scale.BALL_DIAMETER_STUDS
	local ok, err = GeometryValidator.ValidatePositive(diameter, "BallConfig.Diameter")
	if not ok then
		error(err, 0)
	end

	local ball = Instance.new("Part")
	ball.Name = config.Name or "PinballKitBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(diameter, diameter, diameter)
	ball.Anchored = false
	ball.CanCollide = true
	ball.CanTouch = true
	ball.Material = config.Material or Enum.Material.SmoothPlastic
	ball.Color = config.Color or Color3.fromRGB(220, 220, 60)
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		config.Density or DEFAULT_DENSITY,
		config.Friction or DEFAULT_FRICTION,
		config.Elasticity or DEFAULT_ELASTICITY,
		config.FrictionWeight or DEFAULT_FRICTION_WEIGHT,
		config.ElasticityWeight or DEFAULT_ELASTICITY_WEIGHT
	)
	ball.CFrame = config.CFrame

	-- Deliberately NOT assigned to a CollisionGroup: this project keeps the
	-- ball in the default "Default" group so it collides with both a
	-- cabinet's Flippers and Playfield groups (which don't collide with each
	-- other) -- see CabinetDesignsTest.server.luau's ball construction.
	-- Assigning it to either group would silently make it pass through parts
	-- in the other.

	if config.Parent ~= nil then
		ball.Parent = config.Parent
	end

	-- Server-authoritative: an unanchored part is otherwise auto-owned by
	-- whichever player's character is nearest, which would let a client set
	-- the ball's CFrame/velocity directly. SetNetworkOwner is server-only --
	-- Roblox raises an error if this is called from client code, so
	-- BallGenerator.Generate must only ever be called from the server.
	ball:SetNetworkOwner(nil)

	return ball
end

return BallGenerator
