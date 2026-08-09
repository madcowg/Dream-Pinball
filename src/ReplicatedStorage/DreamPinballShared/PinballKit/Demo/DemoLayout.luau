--!strict

-- Demonstration layout (spec section 14). Builds one of every PinballKit
-- asset family into a labeled, spaced-out grid, plus 1.5-stud test balls at
-- rail/tunnel/ramp entrances and one sample light sequence. Idempotent: reruns
-- replace the previous demo instead of duplicating it (PrimitiveFactory's
-- GenerationId-based replace, same as every other generator).
--
-- Command Bar bootstrap (see README.md for the full explanation):
--   local PinballKit = require(game.ReplicatedStorage.DreamPinballShared.PinballKit)
--   PinballKit.Demo.Generate(workspace)
--
-- Requires leaf modules directly rather than the PinballKit aggregator
-- (init.luau) -- init.luau requires this module too (to expose
-- PinballKit.Demo), and requiring init.luau back from here would be a
-- circular require that Roblox's require() rejects at runtime.

local Scale = require(script.Parent.Parent.Scale)
local Presets = require(script.Parent.Parent.Presets)
local RailGenerator = require(script.Parent.Parent.Generators.RailGenerator)
local RampGenerator = require(script.Parent.Parent.Generators.RampGenerator)
local SpinnerGenerator = require(script.Parent.Parent.Generators.SpinnerGenerator)
local BumperGenerator = require(script.Parent.Parent.Generators.BumperGenerator)
local SlingshotGenerator = require(script.Parent.Parent.Generators.SlingshotGenerator)
local TargetGenerator = require(script.Parent.Parent.Generators.TargetGenerator)
local LightGenerator = require(script.Parent.Parent.Generators.LightGenerator)
local ButtonGenerator = require(script.Parent.Parent.Generators.ButtonGenerator)
local SpinnerController = require(script.Parent.Parent.Runtime.SpinnerController)
local BumperController = require(script.Parent.Parent.Runtime.BumperController)
local SlingshotController = require(script.Parent.Parent.Runtime.SlingshotController)
local TargetController = require(script.Parent.Parent.Runtime.TargetController)
local LightController = require(script.Parent.Parent.Runtime.LightController)
local ButtonController = require(script.Parent.Parent.Runtime.ButtonController)

local DemoLayout = {}

local ROW_SPACING = 14
local COLUMN_SPACING = 14
local DEMO_CONTAINER_NAME = "PinballKitDemo"

local function labelPart(parent: Instance, position: Vector3, text: string)
	local anchor = Instance.new("Part")
	anchor.Name = "Label"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LabelGui"
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.3
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Text = text
	textLabel.Parent = billboard
end

local function spawnTestBall(parent: Instance, position: Vector3): BasePart
	local ball = Instance.new("Part")
	ball.Name = "TestBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(
		Scale.BALL_DIAMETER_STUDS,
		Scale.BALL_DIAMETER_STUDS,
		Scale.BALL_DIAMETER_STUDS
	)
	ball.Position = position
	ball.Material = Enum.Material.SmoothPlastic
	ball.BrickColor = BrickColor.new("Silver")
	ball.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.3, 0.4, 1, 1)
	ball.Parent = parent
	return ball
end

local function isTestBall(part: BasePart): boolean
	return part.Name == "TestBall"
end

-- Grid layout: each call returns the next slot's world CFrame (flat, facing
-- +Z) and advances the cursor.
local function makeGrid(origin: CFrame, columns: number)
	local index = 0
	return function(): CFrame
		local column = index % columns
		local row = math.floor(index / columns)
		index += 1
		return origin * CFrame.new(column * COLUMN_SPACING, 0, row * ROW_SPACING)
	end
end

function DemoLayout.Generate(workspaceInstance: Instance)
	local container = Instance.new("Folder")
	container.Name = DEMO_CONTAINER_NAME

	local existing = workspaceInstance:FindFirstChild(DEMO_CONTAINER_NAME)

	local origin = CFrame.new(0, 5, 0)
	local nextSlot = makeGrid(origin, 6)

	-- U-shaped half-pipe rails: 30/60/90-degree and straight.
	for _, angle in ipairs({ 30, 60, 90 }) do
		local slot = nextSlot()
		local asset = RailGenerator.GenerateUHalfPipe({
			Name = string.format("URail_%d", angle),
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.URail, {
				Path = { PathType = "Curved", Radius = 8, AngleDegrees = angle, Direction = "Left" },
			}),
		})
		labelPart(container, slot.Position, string.format("U-Rail %d deg", angle))
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	do
		local slot = nextSlot()
		local asset = RailGenerator.GenerateUHalfPipe({
			Name = "URail_Straight",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.URail, {
				Path = { PathType = "Straight", Length = 10 },
			}),
		})
		labelPart(container, slot.Position, "U-Rail Straight")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	-- Macaroni tunnels: 30/60/90-degree and straight.
	for _, angle in ipairs({ 30, 60, 90 }) do
		local slot = nextSlot()
		local asset = RailGenerator.GenerateMacaroniTunnel({
			Name = string.format("Tunnel_%d", angle),
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.MacaroniTunnel, {
				Path = { PathType = "Curved", Radius = 8, AngleDegrees = angle, Direction = "Right" },
			}),
		})
		labelPart(container, slot.Position, string.format("Tunnel %d deg", angle))
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition)
	end

	do
		local slot = nextSlot()
		local asset = RailGenerator.GenerateMacaroniTunnel({
			Name = "Tunnel_Straight",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.MacaroniTunnel, {
				Path = { PathType = "Straight", Length = 10 },
			}),
		})
		labelPart(container, slot.Position, "Tunnel Straight")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition)
	end

	-- Ramps: straight, planar curved, inclined straight, curved + inclined.
	do
		local slot = nextSlot()
		local asset = RampGenerator.Generate({
			Name = "Ramp_Straight",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.Ramp, { Length = 10 }),
		})
		labelPart(container, slot.Position, "Ramp: Straight")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	do
		local slot = nextSlot()
		local asset = RampGenerator.Generate({
			Name = "Ramp_PlanarCurved",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.Ramp, {
				Length = 10,
				Curve = { Radius = 8, AngleDegrees = 60, Direction = "Left" },
			}),
		})
		labelPart(container, slot.Position, "Ramp: Planar Curved")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	do
		local slot = nextSlot()
		local asset = RampGenerator.Generate({
			Name = "Ramp_InclinedStraight",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.Ramp, { Length = 10, Rise = 4 }),
		})
		labelPart(container, slot.Position, "Ramp: Inclined Straight")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	do
		local slot = nextSlot()
		local asset = RampGenerator.Generate({
			Name = "Ramp_CurvedInclined",
			Origin = slot,
			Parent = container,
			Config = Presets.Extend(Presets.WilliamsClassic.Ramp, {
				Length = 10,
				Rise = 4,
				Curve = { Radius = 8, AngleDegrees = 60, Direction = "Right" },
			}),
		})
		labelPart(container, slot.Position, "Ramp: Curved + Inclined")
		spawnTestBall(container, asset.Attachments.Entry.WorldPosition + Vector3.new(0, 1, 0))
	end

	-- Spinner.
	do
		local slot = nextSlot()
		local asset = SpinnerGenerator.Generate({
			Name = "DemoSpinner",
			Origin = slot,
			Parent = container,
			Config = Presets.WilliamsClassic.Spinner,
		})
		SpinnerController.Attach(asset.Paddle, Presets.WilliamsClassic.SpinnerRuntime)
		labelPart(container, slot.Position, "Spinner")
	end

	-- Pop bumper.
	do
		local slot = nextSlot()
		local asset = BumperGenerator.Generate({
			Name = "DemoBumper",
			Origin = slot,
			Parent = container,
			Config = Presets.WilliamsClassic.PopBumper,
		})
		BumperController.Attach(asset, Presets.WilliamsClassic.PopBumperRuntime, isTestBall)
		labelPart(container, slot.Position, "Pop Bumper")
	end

	-- Slingshot.
	do
		local slot = nextSlot()
		local asset = SlingshotGenerator.Generate({
			Name = "DemoSlingshot",
			Origin = slot,
			Parent = container,
			Config = Presets.WilliamsClassic.Slingshot,
		})
		SlingshotController.Attach(asset, Presets.WilliamsClassic.SlingshotRuntime, isTestBall)
		labelPart(container, slot.Position, "Slingshot")
	end

	-- Hideaway target.
	do
		local slot = nextSlot()
		local asset = TargetGenerator.Generate({
			Name = "DemoTarget",
			Origin = slot,
			Parent = container,
			Config = Presets.WilliamsClassic.HideawayTarget,
		})
		TargetController.Attach(asset, Presets.WilliamsClassic.HideawayTargetRuntime, nil, isTestBall)
		labelPart(container, slot.Position, "Hideaway Target")
	end

	-- Illuminated cabinet button.
	do
		local slot = nextSlot()
		local asset = ButtonGenerator.Generate({
			Name = "DemoButton",
			Origin = slot,
			Parent = container,
			Config = Presets.WilliamsClassic.CabinetButton,
		})
		local handle = ButtonController.Attach(asset, Presets.WilliamsClassic.CabinetButtonRuntime)
		handle:SetLit(true)
		labelPart(container, slot.Position, "Cabinet Button")
	end

	-- Round / bar / ring inserts, plus a sample sequence across the three.
	local insertHandles = {}
	local insertSpecs = {
		{ Name = "DemoRoundInsert", Label = "Round Insert", Config = Presets.WilliamsClassic.RoundInsert },
		{ Name = "DemoBarInsert", Label = "Bar Insert", Config = Presets.WilliamsClassic.BarInsert },
		{ Name = "DemoRingInsert", Label = "Ring Insert", Config = Presets.WilliamsClassic.RingInsert },
	}
	for _, spec in ipairs(insertSpecs) do
		local slot = nextSlot()
		local asset = LightGenerator.Generate({
			Name = spec.Name,
			Origin = slot,
			Parent = container,
			Config = spec.Config,
		})
		local handle = LightController.Attach(asset, {
			OnColor = spec.Config.OnColor,
			OffColor = spec.Config.OffColor,
		})
		table.insert(insertHandles, handle)
		labelPart(container, slot.Position, spec.Label)
	end

	LightController.RunSequence(insertHandles, 0.4, true)

	if existing ~= nil then
		existing:Destroy()
	end
	container.Parent = workspaceInstance
end

return DemoLayout
