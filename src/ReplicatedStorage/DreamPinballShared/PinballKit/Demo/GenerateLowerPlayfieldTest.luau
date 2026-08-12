--!strict

-- Studio Command Bar bootstrap for the lower-playfield system (spec section
-- 20), matching PinballKit.Demo.Generate's own bootstrap pattern:
--
--   local PinballKit = require(game.ReplicatedStorage.DreamPinballShared.PinballKit)
--   PinballKit.LowerPlayfieldTest.Generate(workspace)
--
-- Requires leaf modules directly (not the PinballKit aggregator) for the same
-- reason Demo/DemoLayout.luau does -- avoids a circular require. Run this
-- from a server context (Command Bar in Studio counts) -- BallGenerator's
-- SetNetworkOwner call and the PinballMechanisms registration below both
-- require server-equivalent permissions, same as PinballKit.Demo.Generate.

local LowerPlayfieldGenerator = require(script.Parent.Parent.Generators.LowerPlayfieldGenerator)
local LowerPlayfieldController = require(script.Parent.Parent.Runtime.LowerPlayfieldController)
local LowerPlayfieldValidator = require(script.Parent.Parent.Validation.LowerPlayfieldValidator)
local BallGenerator = require(script.Parent.Parent.Generators.BallGenerator)
local AssetValidator = require(script.Parent.Parent.Validation.AssetValidator)
local Presets = require(script.Parent.Parent.Presets)

local GenerateLowerPlayfieldTest = {}

local CONTAINER_NAME = "PinballKitLowerPlayfieldTest"
local COLLISION_GROUP = "PinballKitLowerPlayfieldTestFlippers"
local TEST_BALL_NAME = "PinballKitLowerPlayfieldTestBall"

local function isTestBall(part: BasePart): boolean
	return part.Name == TEST_BALL_NAME
end

function GenerateLowerPlayfieldTest.Generate(workspaceInstance: Instance)
	local existing = workspaceInstance:FindFirstChild(CONTAINER_NAME)

	-- Parented into the real Workspace tree IMMEDIATELY, before generating
	-- anything -- FlipperGenerator (via LowerPlayfieldGenerator) reads
	-- AssemblyMass while wiring the hinge, which is only meaningful once the
	-- flipper part is a live DataModel descendant. The OLD container (if any)
	-- is only destroyed once the new one is fully built, at the very end.
	local container = Instance.new("Folder")
	container.Name = CONTAINER_NAME
	container.Parent = workspaceInstance

	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	-- Away from world origin/default spawn and WilliamsCabinet's own build
	-- area on purpose -- (0, 5, 0) sat right on top of the player spawn and
	-- visually overlapped whatever else lives there, making this rig's own
	-- geometry unreadable (looked "broken" when it was actually just
	-- superimposed on unrelated parts).
	anchor.CFrame = CFrame.new(75, 1, 0)
	anchor.Parent = container

	local preset = Presets.WilliamsClassicLowerPlayfield

	local flipperConfig = table.clone(preset.LowerPlayfield.Flipper)
	flipperConfig.CollisionGroup = COLLISION_GROUP

	local lowerPlayfieldConfig = table.clone(preset.LowerPlayfield)
	lowerPlayfieldConfig.Flipper = flipperConfig

	local asset = LowerPlayfieldGenerator.Generate({
		Name = "TestLowerPlayfield",
		Parent = container,
		Origin = anchor.CFrame,
		Config = lowerPlayfieldConfig,
	})

	local controller = LowerPlayfieldController.Attach(asset, {
		FlipperMotorSpeed = preset.LowerPlayfieldRuntime.FlipperMotorSpeed,
		SlingshotOutwardImpulse = preset.LowerPlayfieldRuntime.SlingshotOutwardImpulse,
		SlingshotCooldownSeconds = preset.LowerPlayfieldRuntime.SlingshotCooldownSeconds,
		LaneCooldownSeconds = preset.LowerPlayfieldRuntime.LaneCooldownSeconds,
		IsBall = isTestBall,
		OnLaneSwitch = function(laneId: string, _side, laneType: string, _ball: BasePart, entered: boolean)
			print(string.format("[LowerPlayfieldTest] %s (%s) %s", laneId, laneType, if entered then "ENTER" else "EXIT"))
		end,
		OnSlingshotFired = function(side: string, _ball: BasePart)
			print(string.format("[LowerPlayfieldTest] Slingshot fired: %s", side))
		end,
		OnBallDrained = function(ball: BasePart)
			print("[LowerPlayfieldTest] Ball drained")
			ball:Destroy()
		end,
	})

	-- Registers with the generic server dispatcher so any connected player's
	-- existing keyboard/gamepad/touch input (FlipperInputController.local.luau)
	-- drives this test rig directly -- exercises the full networked path
	-- end-to-end, not a bypassed local-only shortcut. `ownerCheck` always
	-- returns true: this is a standalone test table, not a real multi-cabinet
	-- game feature needing per-player exclusivity.
	local ServerScriptService = game:GetService("ServerScriptService")
	local dreamPinballServer = ServerScriptService:FindFirstChild("DreamPinballServer")
	if dreamPinballServer ~= nil then
		local mechanismsModule = dreamPinballServer:FindFirstChild("PinballMechanisms")
		if mechanismsModule ~= nil and mechanismsModule:IsA("ModuleScript") then
			local PinballMechanisms = require(mechanismsModule)
			PinballMechanisms.Init()
			PinballMechanisms.RegisterCabinet(CONTAINER_NAME, controller, function(_player)
				return true
			end)
		end
	end

	-- Test balls (spec section 20).
	for i = 1, 3 do
		BallGenerator.Generate({
			Name = TEST_BALL_NAME,
			CFrame = anchor.CFrame * CFrame.new(-3 + (i - 1) * 3, 3, 6),
			Parent = container,
		})
	end

	local partCount = AssetValidator.CountParts(asset.Model)
	print(
		string.format(
			"[LowerPlayfieldTest] Generated. Total parts: %d. Resting tip gap: %.4f studs. Pivot half-spacing: %.4f studs.",
			partCount,
			asset.RestingTipGap,
			asset.PivotOffsetX
		)
	)
	print("[LowerPlayfieldTest] From Command Bar: controller:Press(\"Left\") / :Release(\"Left\") to test a flipper without input.")

	local report = LowerPlayfieldValidator.Validate(asset, lowerPlayfieldConfig, anchor.CFrame)
	if report.Ok then
		print("[LowerPlayfieldTest] Validation: OK")
	else
		warn("[LowerPlayfieldTest] Validation FAILED:\n  - " .. table.concat(report.Errors, "\n  - "))
	end

	if existing ~= nil then
		existing:Destroy()
	end

	return { Asset = asset, Controller = controller, Container = container }
end

return GenerateLowerPlayfieldTest
