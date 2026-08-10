--!strict

--- Wires up the FULL gameplay loop (turn state, launch, items, scoring,
--- drain, HUD, fixed camera, movement lock, run-currency) on ANY cabinet
--- Folder -- hand-built by the team in Studio (e.g. WilliamsCabinet) OR
--- built procedurally by CabinetBuilder.build. Unlike CabinetDesignsTest's
--- setupGameplay (which requires a CabinetBuilder.CabinetResult), this finds
--- everything it needs by NAME inside the given Folder, so it works on any
--- cabinet regardless of how its geometry was made.
---
--- SELF-CORRECTING ANCHORING: every non-flipper BasePart under cabinetFolder
--- is forced to Anchored = true during setup. Studio's default for a newly-
--- inserted Part is UNANCHORED, and this has already silently broken
--- InteractAnchor, CameraAnchor, and MainFieldEntry once each -- each looked
--- correctly placed in Edit mode, then fell/drifted the instant Play
--- started, breaking whatever depended on its position with no error at
--- all. The team never needs to remember to set Anchored by hand on a new
--- marker/geometry Part; this module fixes it automatically every time
--- gameplay wires up.
---
--- REQUIRED markers inside the cabinet Folder (create by hand in Studio,
--- any name/shape for the geometry itself, but these exact names/types):
---   LeftFlipper, RightFlipper   -- each a BasePart with a single pivot
---                                  Attachment placed at the correct hinge
---                                  point (e.g. via Studio's "Edit Pivot"
---                                  tool). If a HingeConstraint already
---                                  exists (found by searching the whole
---                                  cabinet folder), this module drives it as-
---                                  is. If NOT, one is built automatically
---                                  from the flipper's current position/
---                                  rotation and that one Attachment via
---                                  CabinetBuilder.attachFlipperHinge --
---                                  using the SAME locked baseline (rest
---                                  angle taken as wherever you placed it,
---                                  45-degree swing, 87500 torque -- see
---                                  GameplayTuning.luau / architecture.md
---                                  "Flipper baseline") as the 3 code-built
---                                  comparison cabinets.
---   Bumper (any number, anywhere) -- BasePart, scoring bumper. Touched
---                                  connects automatically; no code needed
---                                  per bumper beyond placing it and naming
---                                  it "Bumper".
---   DrainTrigger                -- BasePart, CanCollide false. A ball
---                                  touching this ends the turn as "drained"
---                                  (lost life). ONLY takes effect once the
---                                  ball has reached the main field (see
---                                  MainFieldEntry below) -- a ball still in
---                                  the plunger lane that happens to clip a
---                                  drain-adjacent trigger will not lose a
---                                  life, matching a real table where the
---                                  lane and the drain are physically
---                                  unreachable from each other.
---   LaunchAnchor                 -- BasePart. The ball spawns at this
---                                  Part's Position and launches along its
---                                  own forward (+Z, i.e. LookVector)
---                                  direction. Replaces CabinetBuilder's
---                                  PlungerLaneX/PlungerLaneBottomZ math --
---                                  point this Part's front face toward the
---                                  main playfield.
---   MainFieldEntry               -- BasePart, CanCollide false, spanning
---                                  the gap in the plunger lane's divider
---                                  wall (same gap every code-built cabinet
---                                  has via CabinetBuilder's
---                                  PLUNGER_LANE_OPENING_LENGTH). A ball
---                                  touching this has "made it out" of the
---                                  lane -- from that moment on it's treated
---                                  as being in the main field (DrainTrigger
---                                  becomes live for it). Before touching
---                                  this, a launch that stalls and rolls
---                                  back down the lane under gravity can
---                                  simply be re-launched by holding R again
---                                  -- see "how relaunch works" below.
---   InteractAnchor               -- BasePart, standing height in front of
---                                  the cabinet. Gets the "Start Level"
---                                  ProximityPrompt (key F).
---   CameraAnchor                 -- BasePart. Its CFrame (Position AND
---                                  Orientation) becomes the fixed in-level
---                                  camera view exactly as placed -- fly
---                                  Studio's own edit camera to the desired
---                                  view, then run
---                                  CabinetGameplay.snapCameraAnchorToViewport(cameraAnchorPart)
---                                  from the Command Bar to match it without
---                                  typing coordinates by hand.
---
--- OPTIONAL (backboard display -- e.g. WilliamsCabinet's "Ocean Dreams" art
--- with 4 blank boxes for score/modifiers/balls-left/name). Each is a
--- TextLabel the team places by hand (inside a SurfaceGui on whichever Part
--- has the backboard art, positioned visually over its box) -- this module
--- only sets .Text on it, never creates or positions it, so the team keeps
--- full control of font/size/placement to match the art. Found anywhere
--- under cabinetFolder by name; skipped individually if absent, so you can
--- add them one at a time:
---   BackboardScoreText           -- set to "<Score>/<PointThreshold>".
---   BackboardModifiersText       -- set to a comma-separated list of item
---                                  effects currently queued for the next
---                                  launch (e.g. "Coffee, Magnet"), or "--"
---                                  when none are queued.
---   BackboardBallsLeftText       -- set to how many turns remain
---                                  (MaxTurns - TurnNumber + 1, i.e. counts
---                                  down from MaxTurns on turn 1 to 1 on the
---                                  last turn).
---   BackboardNameText            -- set to the engaged player's DisplayName,
---                                  or "" when no one is engaged.
---
--- HOW RELAUNCH WORKS (no RelaunchTrigger needed): a real pinball lane has
--- no way to tell "just spawned" apart from "rolled back to rest" other than
--- by watching whether the ball ever reached the field -- trying to catch a
--- ball at one exact rest position with a proximity trigger is unreliable
--- (real physics doesn't stop it in the exact same spot twice). Instead,
--- this module tracks whether the CURRENT ball has touched MainFieldEntry
--- yet. If not, and the ball's speed has dropped near zero (it rolled back
--- and stopped, wherever that happens to be in the lane), a fresh Launch
--- call re-fires the SAME ball object from wherever it is, along
--- LaunchAnchor's direction -- no destroy/recreate, no risk of losing a
--- life, no separate trigger Part required at the bottom of the lane.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DreamPinballShared = ReplicatedStorage:WaitForChild("DreamPinballShared")
local Data = DreamPinballShared:WaitForChild("Data")
local Combat = DreamPinballShared:WaitForChild("Combat")

local CabinetBuilder = require(script.Parent:WaitForChild("CabinetBuilder"))
local GameplayTuning = require(script.Parent:WaitForChild("GameplayTuning"))
local PinballKit = script.Parent:WaitForChild("PinballKit")
local PinballKitConstants = require(PinballKit:WaitForChild("Constants"))
local Scale = require(PinballKit:WaitForChild("Scale"))
local BallGenerator = require(PinballKit:WaitForChild("Generators"):WaitForChild("BallGenerator"))
local PlungerGenerator = require(PinballKit:WaitForChild("Generators"):WaitForChild("PlungerGenerator"))
local PlungerController = require(PinballKit:WaitForChild("Runtime"):WaitForChild("PlungerController"))
local Ball = require(Data:WaitForChild("Ball"))
local Item = require(Data:WaitForChild("Item"))
local Encounter = require(Data:WaitForChild("Encounter"))
local TurnState = require(Combat:WaitForChild("TurnState"))
local HudRemotes = require(script.Parent:WaitForChild("Remotes"):WaitForChild("HudState"))
local CameraRemotes = require(script.Parent:WaitForChild("Remotes"):WaitForChild("CameraControl"))

local INTERACT_HOLD_DURATION = 0
local INTERACT_MAX_ACTIVATION_DISTANCE = 10

export type GameplayHandle = {
	BeginCharge: (player: Player) -> (),
	Launch: (player: Player, power: number) -> (),
	UseItem: (player: Player, itemId: unknown) -> (),
	IsEngagedBy: (player: Player) -> boolean,
	StartLevel: (player: Player) -> (),
	ForceDisengage: (player: Player) -> (),
	SetFlipperInput: (side: CabinetBuilder.Side, pressed: boolean) -> (),
}

--- Finds the working HingeConstraint that drives flipperContainer, searching
--- the whole cabinet folder rather than assuming a fixed path -- this works
--- regardless of the flipper's internal structure (pivot part name,
--- attachment names), including CabinetBuilder.buildFlipper's own layout,
--- where the hinge is parented onto a separate pivot Part that's a SIBLING
--- of the flipper (not a descendant of it), connected only via the hinge's
--- own Attachment0/Attachment1.
local function findFlipperHinge(cabinetFolder: Instance, flipperContainer: Instance): HingeConstraint?
	for _, descendant in cabinetFolder:GetDescendants() do
		if descendant:IsA("HingeConstraint") then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			if (a0 and a0:IsDescendantOf(flipperContainer)) or (a1 and a1:IsDescendantOf(flipperContainer)) then
				return descendant
			end
		end
	end
	return nil
end

local CabinetGameplay = {}

--- Orients cameraAnchorPart to exactly match the CURRENT Studio edit-mode
--- viewport camera. Run from Studio's Command Bar after flying the edit
--- camera to the desired fixed-camera view:
---   local CabinetGameplay = require(game.ReplicatedStorage.DreamPinballShared.CabinetGameplay)
---   CabinetGameplay.snapCameraAnchorToViewport(workspace.BakedCabinets.WilliamsCabinet.CameraAnchor)
--- Then Ctrl+S. No coordinates to type by hand -- what you see in the
--- viewport at the moment you run this becomes the in-game fixed camera.
function CabinetGameplay.snapCameraAnchorToViewport(cameraAnchorPart: BasePart)
	local camera = workspace.CurrentCamera
	if not camera then
		error("CabinetGameplay.snapCameraAnchorToViewport: workspace.CurrentCamera is nil -- open a viewport first")
	end
	cameraAnchorPart.CFrame = camera.CFrame
end

--- Wires up the full gameplay loop on cabinetFolder. label is used in HUD
--- text and Output prints to identify this cabinet. Errors immediately if a
--- REQUIRED marker (see module doc comment above) is missing, naming which
--- one, rather than failing silently or partway through.
function CabinetGameplay.setup(cabinetFolder: Instance, label: string): GameplayHandle
	local function requireChild(name: string): Instance
		local child = cabinetFolder:FindFirstChild(name, true)
		if not child then
			error("CabinetGameplay.setup(" .. label .. "): missing required marker '" .. name .. "' somewhere under " .. cabinetFolder:GetFullName())
		end
		return child
	end

	local leftFlipperContainer = requireChild("LeftFlipper")
	local rightFlipperContainer = requireChild("RightFlipper")

	-- Parts that must be able to move under physics and are therefore
	-- EXCLUDED from the auto-anchor pass below -- flippers (swing on their
	-- hinge) and a moving plunger, if/when the team builds one and names it
	-- "Plunger" (matching CabinetDesignsTest's cosmetic plunger part).
	-- LaunchBall (the actual ball) is created later, at Launch() time, and
	-- always explicitly unanchored there -- it doesn't exist yet at setup()
	-- time, so it's never touched by this pass regardless.
	local function isExcludedFromAutoAnchor(descendant: Instance): boolean
		return descendant:IsDescendantOf(leftFlipperContainer)
			or descendant:IsDescendantOf(rightFlipperContainer)
			or descendant.Name == "Plunger"
	end

	-- Flippers get their own collision group, separate from the rest of the
	-- playfield (walls/floor/bumpers) -- their swept volume overlaps the
	-- floor by design at rest height, same rule as every code-built cabinet
	-- (see architecture.md "Flipper baseline"). Registered here (not left to
	-- the team to set by hand) since a hand-built cabinet has no
	-- CabinetBuilder.build call to do this automatically.
	local flipperGroup = label .. "Flippers"
	local playfieldGroup = label .. "Playfield"
	CabinetBuilder.ensureCollisionGroups(flipperGroup, playfieldGroup)
	for _, descendant in cabinetFolder:GetDescendants() do
		if descendant:IsA("BasePart") and not isExcludedFromAutoAnchor(descendant) then
			local part = descendant :: BasePart
			part.CollisionGroup = playfieldGroup

			-- Every non-flipper, non-plunger Part in a hand-built cabinet is
			-- a static marker or piece of geometry -- none of them should
			-- ever move under gravity. Studio's default for a newly-inserted
			-- Part is UNANCHORED, and this exact mistake has already
			-- silently broken InteractAnchor, CameraAnchor, and
			-- MainFieldEntry once each (the part looks correctly placed in
			-- Edit mode, then drifts/falls the instant Play starts, breaking
			-- whatever depended on its position with no error -- just a
			-- mysteriously "not working" feature). Forcing Anchored = true
			-- here makes the whole cabinet self-correcting: even if the team
			-- places a new Part unanchored by mistake, it's fixed
			-- automatically the moment gameplay wires up, instead of only
			-- when someone thinks to check.
			part.Anchored = true
		end
	end

	--- Finds a flipper's own single pivot Attachment (the one Studio's Edit
	--- Pivot tool creates), for use as attachFlipperHinge's hinge-point
	--- marker when no hinge exists yet. Errors if there's more than one
	--- Attachment directly on the flipper Part -- ambiguous which one is the
	--- pivot -- rather than guessing wrong.
	local function findPivotAttachment(flipperContainer: Instance): Attachment
		local flipperPart = if flipperContainer:IsA("BasePart") then flipperContainer else flipperContainer:FindFirstChildWhichIsA("BasePart")
		if not flipperPart then
			error("CabinetGameplay.setup(" .. label .. "): " .. flipperContainer.Name .. " has no BasePart to hinge")
		end
		local attachments = {}
		for _, child in flipperPart:GetChildren() do
			if child:IsA("Attachment") then
				table.insert(attachments, child)
			end
		end
		if #attachments == 0 then
			error("CabinetGameplay.setup(" .. label .. "): " .. flipperContainer.Name .. " has no pivot Attachment -- set a custom pivot point on it in Studio first")
		end
		if #attachments > 1 then
			error("CabinetGameplay.setup(" .. label .. "): " .. flipperContainer.Name .. " has " .. tostring(#attachments) .. " Attachments -- expected exactly 1 pivot marker")
		end
		return attachments[1]
	end

	local leftHinge = findFlipperHinge(cabinetFolder, leftFlipperContainer)
	if not leftHinge then
		local flipperPart = leftFlipperContainer :: BasePart
		leftHinge = CabinetBuilder.attachFlipperHinge(
			flipperPart,
			findPivotAttachment(leftFlipperContainer),
			"Left",
			GameplayTuning.FLIPPER_UP_ANGLE_DEGREES,
			GameplayTuning.FLIPPER_MOTOR_TORQUE_PER_MASS,
			flipperGroup
		)
		print(label .. ": built LeftFlipper's hinge automatically from its pivot Attachment")
	end

	local rightHinge = findFlipperHinge(cabinetFolder, rightFlipperContainer)
	if not rightHinge then
		local flipperPart = rightFlipperContainer :: BasePart
		rightHinge = CabinetBuilder.attachFlipperHinge(
			flipperPart,
			findPivotAttachment(rightFlipperContainer),
			"Right",
			GameplayTuning.FLIPPER_UP_ANGLE_DEGREES,
			GameplayTuning.FLIPPER_MOTOR_TORQUE_PER_MASS,
			flipperGroup
		)
		print(label .. ": built RightFlipper's hinge automatically from its pivot Attachment")
	end

	local hinges: { [CabinetBuilder.Side]: HingeConstraint } = { Left = leftHinge, Right = rightHinge }

	local drainTrigger = requireChild("DrainTrigger") :: BasePart
	local launchAnchor = requireChild("LaunchAnchor") :: BasePart
	local mainFieldEntry = requireChild("MainFieldEntry") :: BasePart
	local interactAnchor = requireChild("InteractAnchor") :: BasePart
	local cameraAnchor = requireChild("CameraAnchor") :: BasePart

	-- Cosmetic plunger rod at LaunchAnchor -- pulls back while BeginCharge is
	-- held and springs forward on Launch, echoing the charge/release the
	-- player already controls with R. Never touches launch velocity itself
	-- (see PlungerGenerator.luau's header comment) -- purely visual feedback.
	-- Origin is offset back by one ball radius so the rod's tip rests just
	-- behind the ball's spawn point instead of inside its center.
	local plungerAsset = PlungerGenerator.Generate({
		Name = "LaunchPlunger",
		Origin = launchAnchor.CFrame * CFrame.new(0, 0, Scale.BALL_DIAMETER_STUDS / 2),
		Parent = cabinetFolder,
		Config = {},
	})
	local plungerHandle = PlungerController.Attach(plungerAsset.Rod, plungerAsset.Constraint, plungerAsset.MaxRetractStuds)

	-- Optional backboard display -- see module doc comment above. Each is
	-- found independently so the team can add them one at a time; a missing
	-- one just means that box stays blank, not an error. Font forced to
	-- Gotham (Roblox's cleanest built-in sans-serif -- there is no true
	-- dyslexia-specific font built into Roblox; that would need a custom
	-- font asset upload) regardless of whatever font the team picked when
	-- creating the TextLabel in Studio, so every box stays consistent even
	-- if the team adds more later.
	local BACKBOARD_FONT = Enum.Font.Gotham
	local function findBackboardLabel(name: string): TextLabel?
		local label = cabinetFolder:FindFirstChild(name, true) :: TextLabel?
		if label then
			label.Font = BACKBOARD_FONT
		end
		return label
	end
	local backboardScoreText = findBackboardLabel("BackboardScoreText")
	local backboardModifiersText = findBackboardLabel("BackboardModifiersText")
	local backboardBallsLeftText = findBackboardLabel("BackboardBallsLeftText")
	local backboardNameText = findBackboardLabel("BackboardNameText")

	local scoringBumpers: { BasePart } = {}
	for _, descendant in cabinetFolder:GetDescendants() do
		if descendant.Name == "Bumper" and descendant:IsA("BasePart") then
			table.insert(scoringBumpers, descendant)
		end
	end

	local function freshHand(): { Ball.BallData }
		return {
			Ball.new(label .. "TestBall1", "Test Ball 1", "SeaGoblin", "Water", "Common", { Speed = 10, Atk = 10, Def = 10, HP = 10 }, 5),
		}
	end

	-- Build order step 9: one full Sand-themed (Water-type) encounter wired
	-- end-to-end. Threshold/reward values are placeholder test balance, not
	-- final encounter design (per-encounter values are TBD, not global).
	local encounter = Encounter.new(label .. "SandTestEncounter1", "Sand Test Encounter", true, "Water", 50, 20)

	local hand: { Ball.BallData } = freshHand()
	local state = TurnState.new(hand, 3, encounter.PointThreshold)
	local runCurrency = 0
	local encounterRewardPaid = false

	local activeBallPart: BasePart? = nil
	local activeBallData: Ball.BallData? = nil
	local lastBounceAt = 0
	-- Tracks whether the CURRENT activeBallPart has touched MainFieldEntry
	-- yet -- true means it's genuinely in the main field (DrainTrigger can
	-- end the turn); false means it's still somewhere in the plunger lane
	-- (could be freshly spawned, mid-flight up the lane, or rolled back and
	-- at rest) and can simply be re-launched by holding R again. See this
	-- module's "HOW RELAUNCH WORKS" doc comment above for the reasoning.
	local ballInMainField = false

	local hudRemote = HudRemotes.getHudStateRemote()
	local cameraRemote = CameraRemotes.getCameraControlRemote()

	local engagedPlayer: Player? = nil
	local movementLocked = false

	local function setMovementLocked(player: Player, locked: boolean)
		local character = player.Character
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		if locked then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
		else
			humanoid.WalkSpeed = GameplayTuning.DEFAULT_WALK_SPEED
			humanoid.JumpPower = GameplayTuning.DEFAULT_JUMP_POWER
			humanoid.JumpHeight = GameplayTuning.DEFAULT_JUMP_HEIGHT
		end
	end

	local function unlockMovementIfGameOver()
		if not TurnState.isOver(state) or not engagedPlayer then
			return
		end
		if movementLocked then
			movementLocked = false
			setMovementLocked(engagedPlayer, false)
			print(label .. ": movement unlocked for " .. engagedPlayer.Name .. " (" .. state.Result .. ")")
		end
		cameraRemote:FireClient(engagedPlayer, nil)
	end

	local function forceLostIfAllBallsBroken()
		if TurnState.isOver(state) then
			return
		end
		for _, b in hand do
			if not Ball.isBroken(b) then
				return
			end
		end
		state = {
			Hand = state.Hand,
			HandSize = state.HandSize,
			TurnNumber = state.TurnNumber,
			MaxTurns = state.MaxTurns,
			ItemsUsedThisTurn = state.ItemsUsedThisTurn,
			MaxItemsPerTurn = state.MaxItemsPerTurn,
			CharacterUsedThisTurn = state.CharacterUsedThisTurn,
			Score = state.Score,
			PointThreshold = state.PointThreshold,
			Result = "Lost",
		}
		print(label .. ": all balls broken, encounter lost")
	end

	local function freshInventory(): { [string]: number }
		return {
			Feather = 1,
			Coffee = 1,
			ExtraBall = 1,
			Magnet = 1,
			Hammer = 1,
		}
	end
	local inventory: { [string]: number } = freshInventory()

	local pendingSpeedDelta = 0
	local pendingAtkDelta = 0
	local pendingAttractionDelta = 0
	local pendingDestroysFirstObstacle = false
	local launchDestroysFirstObstacle = false
	-- Names of items queued for the next launch (e.g. {"Coffee", "Magnet"}),
	-- purely for the backboard's modifiers box -- cleared alongside the
	-- pending*Delta fields once a launch consumes them. Not used for any
	-- gameplay logic, so it deliberately does NOT include ExtraBall (which
	-- resolves immediately in useItem, not as a queued launch effect).
	local pendingModifierNames: { string } = {}

	local function updateBackboard()
		if backboardScoreText then
			backboardScoreText.Text = tostring(state.Score) .. "/" .. tostring(state.PointThreshold)
		end
		if backboardModifiersText then
			backboardModifiersText.Text = if #pendingModifierNames > 0 then table.concat(pendingModifierNames, ", ") else "--"
		end
		if backboardBallsLeftText then
			backboardBallsLeftText.Text = tostring(state.MaxTurns - state.TurnNumber + 1)
		end
		if backboardNameText then
			backboardNameText.Text = if engagedPlayer then engagedPlayer.DisplayName else ""
		end
	end

	local function pushHudState()
		if not engagedPlayer then
			return
		end

		local handSnapshots = table.create(#hand)
		local activeIndex: number? = nil
		for i, b in hand do
			table.insert(handSnapshots, { Name = b.Name, CurrentDurability = b.CurrentDurability, MaxDurability = b.MaxDurability })
			if activeBallData and b.Id == activeBallData.Id then
				activeIndex = i
			end
		end

		local snapshot: HudRemotes.Snapshot = {
			CabinetLabel = label,
			TurnNumber = state.TurnNumber,
			MaxTurns = state.MaxTurns,
			Score = state.Score,
			PointThreshold = state.PointThreshold,
			Result = state.Result,
			RunCurrency = runCurrency,
			Hand = handSnapshots,
			ActiveBallIndex = activeIndex,
		}
		hudRemote:FireClient(engagedPlayer, snapshot)
	end

	local function describeState(eventLabel: string)
		local durabilityText = "n/a"
		if activeBallData then
			durabilityText = tostring(activeBallData.CurrentDurability) .. "/" .. tostring(activeBallData.MaxDurability)
		end

		print(
			string.format(
				"%s [%s]: Turn %d/%d, Score %d/%d, Result %s, BallDurability %s, RunCurrency %d",
				label,
				eventLabel,
				state.TurnNumber,
				state.MaxTurns,
				state.Score,
				state.PointThreshold,
				state.Result,
				durabilityText,
				runCurrency
			)
		)
		pushHudState()
		updateBackboard()
	end

	local function checkEncounterCompletion()
		if state.Result == "Won" and not encounterRewardPaid then
			encounterRewardPaid = true
			runCurrency += encounter.RunCurrencyReward
			print(label .. ": encounter won, awarded " .. tostring(encounter.RunCurrencyReward) .. " run-currency")
		end
	end

	local function endLaunch(outcome: string)
		if activeBallPart then
			activeBallPart:Destroy()
		end
		activeBallPart = nil
		activeBallData = nil
		ballInMainField = false

		state = TurnState.endTurn(state)
		forceLostIfAllBallsBroken()
		describeState("launch ended (" .. outcome .. ")")
		unlockMovementIfGameOver()
	end

	-- Reads a PinballKit-generated bumper's per-instance "PointValue" attribute
	-- (stamped on its root Model, not the bumper Part itself -- see
	-- BumperGenerator.luau), falling back to the old flat placeholder constant
	-- for hand-built bumpers that predate this and never had one set. This is
	-- what makes bumper scoring configurable per-instance instead of one
	-- global number applied identically everywhere.
	local function getPointValue(part: BasePart, fallback: number): number
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model then
			local value = model:GetAttribute(PinballKitConstants.POINT_VALUE_ATTRIBUTE)
			if typeof(value) == "number" then
				return value
			end
		end
		return fallback
	end

	for _, bumper in scoringBumpers do
		bumper.Touched:Connect(function(hit: BasePart)
			if hit ~= activeBallPart or not activeBallData then
				return
			end

			local now = tick()
			if now - lastBounceAt < GameplayTuning.BOUNCE_DEBOUNCE_SECONDS then
				return
			end
			lastBounceAt = now

			local awayFromBumper = hit.Position - bumper.Position
			if awayFromBumper.Magnitude > 0 then
				hit.AssemblyLinearVelocity = awayFromBumper.Unit * GameplayTuning.BUMPER_KICK_STRENGTH
			end

			if launchDestroysFirstObstacle then
				launchDestroysFirstObstacle = false
				print(label .. ": Hammer effect destroyed a scoring bumper")
				bumper:Destroy()
			end

			state = TurnState.addScore(state, getPointValue(bumper, GameplayTuning.SCORE_PER_BOUNCE))
			checkEncounterCompletion()
			activeBallData = Ball.applyScoringBounceDurabilityLoss(activeBallData, GameplayTuning.DURABILITY_LOSS_PER_BOUNCE)
			hand[1] = activeBallData

			if Ball.isBroken(activeBallData) then
				print(label .. ": ball broke from durability loss")
				forceLostIfAllBallsBroken()
			end

			describeState("scoring bounce")
			unlockMovementIfGameOver()
		end)
	end

	mainFieldEntry.Touched:Connect(function(hit: BasePart)
		if hit ~= activeBallPart or ballInMainField then
			return
		end
		ballInMainField = true
		print(label .. ": ball reached the main field")
	end)

	-- Only ends the turn if the ball has actually reached the main field --
	-- a ball still in the plunger lane is physically unreachable from
	-- DrainTrigger on a correctly-built table, but this check is the
	-- authoritative guard regardless of geometry: it guarantees a weak
	-- plunge can never accidentally cost a life.
	drainTrigger.Touched:Connect(function(hit: BasePart)
		if hit ~= activeBallPart or not ballInMainField then
			return
		end
		endLaunch("drained")
	end)

	-- A ball still in the lane (never touched MainFieldEntry) counts as
	-- "at rest" once it's nearly stopped -- below this, tiny residual
	-- physics jitter from resting on a tilted surface doesn't count as
	-- still moving. Only a ball at rest (or none at all) can be launched;
	-- a ball mid-flight up the lane can't be re-launched out from under
	-- itself.
	local LANE_REST_SPEED_THRESHOLD = 1

	-- Live diagnostics (WilliamsCabinetDiagnostics.server.luau) caught the
	-- ball hitting a flipper at 40+ studs/s with a real, physically-correct
	-- velocity change but NO .Touched event firing -- the ball crossed the
	-- flipper's thin collision volume too fast for the discrete Touched
	-- event to reliably register, even though Roblox's physics solver still
	-- resolved the bounce. Every scoring bounce, contact log, and piece of
	-- player feedback in this game depends on .Touched, so a missed event
	-- there means a real bounce with zero gameplay feedback -- exactly the
	-- "flippers don't seem to hit it" / "floats weirdly" behavior reported.
	-- Capping speed keeps every collision slow enough for .Touched to be
	-- reliable, rather than trying to detect and patch missed events after
	-- the fact.
	-- Only clamps once the ball has reached the main field (ballInMainField)
	-- -- the plunger lane launch NEEDS a strong initial speed to reliably
	-- clear the lane and the deflector into the field (see
	-- LAUNCH_SPEED_TO_VELOCITY_SCALE's own "spring needed more power"
	-- history); this clamp targets the open-field bounce speeds where the
	-- missed-collision bug was actually observed, without re-weakening the
	-- launch itself.
	local MAX_BALL_SPEED = 40
	local function armSpeedClamp(ball: BasePart)
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			if not ball.Parent then
				connection:Disconnect()
				return
			end
			if not ballInMainField then
				return
			end
			local velocity = ball.AssemblyLinearVelocity
			if velocity.Magnitude > MAX_BALL_SPEED then
				ball.AssemblyLinearVelocity = velocity.Unit * MAX_BALL_SPEED
			end
		end)
	end

	local function launch(player: Player, power: number)
		-- Authoritative clamp lives here, not just at call sites: power
		-- feeds directly into launch velocity, so an unclamped value from a
		-- future caller (or a modified client skipping its own clamp) would
		-- mean unbounded ball speed/score. See LaunchInputController.local.luau
		-- for the plunger-charge range this mirrors (0.2-1).
		power = math.clamp(power, 0.2, 1)
		-- Springs the plunger forward regardless of whether this launch
		-- attempt is actually accepted below -- the player already released
		-- R, so the visual should always respond to that, not just to a
		-- successful launch.
		plungerHandle:Release(power)
		if engagedPlayer ~= player then
			warn(label .. ": rejected LAUNCH from " .. player.Name .. " -- not engaged with this cabinet")
			return
		end
		if TurnState.isOver(state) then
			warn(label .. ": rejected LAUNCH from " .. player.Name .. " -- turn state is already " .. state.Result)
			return
		end

		-- Re-launch case: the current ball never made it to the main field
		-- and has rolled back to rest somewhere in the lane -- fire the SAME
		-- ball object again from wherever it is, instead of rejecting or
		-- destroying/recreating it. See "HOW RELAUNCH WORKS" doc comment.
		local isRelaunch = false
		if activeBallPart then
			if ballInMainField then
				warn(label .. ": rejected LAUNCH from " .. player.Name .. " -- a ball is already in play")
				return
			end
			if activeBallPart.AssemblyLinearVelocity.Magnitude > LANE_REST_SPEED_THRESHOLD then
				warn(label .. ": rejected LAUNCH from " .. player.Name .. " -- ball is still moving in the lane")
				return
			end
			isRelaunch = true
		end

		if Ball.isBroken(hand[1]) then
			warn(label .. ": rejected LAUNCH from " .. player.Name .. " -- hand[1] is broken (0 durability)")
			return
		end

		if not movementLocked then
			movementLocked = true
			setMovementLocked(player, true)
			print(label .. ": movement locked for " .. player.Name .. " (playing)")
		end

		local ball: BasePart
		if isRelaunch then
			ball = activeBallPart :: BasePart
			-- Snap back to the exact same known-good spawn point/orientation
			-- a fresh launch uses, instead of firing from wherever it
			-- happens to have rolled to (which can be off-center or resting
			-- against a lane wall at an angle) -- otherwise a fixed-
			-- direction relaunch can repeatedly clip the same wall corner
			-- it just stalled against, requiring many tries to clear the
			-- lane (observed: 6+ relaunches in a single turn).
			ball.CFrame = launchAnchor.CFrame
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.AssemblyAngularVelocity = Vector3.zero
		else
			-- Routed through PinballKit's BallGenerator for consistency across
			-- the codebase -- behavior-neutral, the exact same stainless-steel
			-- tuning as before (real steel density ~7,850 kg/m^3 scaled to
			-- Roblox's density units; low friction since polished metal slides
			-- easily; moderate-low elasticity so a solid heavy ball thuds
			-- rather than bounces like a rubber ball). BallGenerator itself
			-- also calls SetNetworkOwner -- redundant with the unconditional
			-- call below (harmless, idempotent) but that call still has to
			-- stay, since it's the only one that runs on the isRelaunch path.
			local newBall = BallGenerator.Generate({
				Name = "LaunchBall",
				CFrame = launchAnchor.CFrame,
				Parent = cabinetFolder,
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(200, 200, 205),
				Density = 7.85,
				Friction = 0.3,
				Elasticity = 0.4,
			})
			ball = newBall
			armSpeedClamp(newBall)
		end
		-- Force server-authoritative physics: an unanchored part otherwise
		-- gets auto-owned by whichever player's character is nearest (the
		-- player at the cabinet), letting an exploit client set the ball's
		-- CFrame/velocity directly and teleport onto bumpers to farm score.
		ball:SetNetworkOwner(nil)

		local effectiveSpeed = (hand[1].Stats.Speed + pendingSpeedDelta) * power
		local launchDirection = launchAnchor.CFrame.LookVector
		ball.AssemblyLinearVelocity = launchDirection * effectiveSpeed * GameplayTuning.LAUNCH_SPEED_TO_VELOCITY_SCALE
		launchDestroysFirstObstacle = pendingDestroysFirstObstacle
		if pendingAttractionDelta ~= 0 then
			print(label .. ": Magnet attraction effect queued but not yet mechanically implemented")
		end
		pendingSpeedDelta = 0
		pendingAtkDelta = 0
		pendingAttractionDelta = 0
		pendingDestroysFirstObstacle = false
		table.clear(pendingModifierNames)

		activeBallPart = ball
		activeBallData = hand[1]
		describeState(if isRelaunch then "relaunched" else "launched")
	end

	local function useItem(player: Player, itemId: unknown)
		if engagedPlayer ~= player then
			warn(label .. ": rejected item use from " .. player.Name .. " -- not engaged with this cabinet")
			return
		end
		if typeof(itemId) ~= "string" then
			warn(label .. ": rejected invalid item id from " .. player.Name)
			return
		end

		local item = Item.Predefined[itemId]
		if not item then
			warn(label .. ": rejected unknown item id " .. itemId .. " from " .. player.Name)
			return
		end
		if not TurnState.canUseItem(state) then
			warn(label .. ": rejected item use from " .. player.Name .. " -- cannot use another item this turn")
			return
		end
		if (inventory[itemId] or 0) <= 0 then
			warn(label .. ": rejected item use from " .. player.Name .. " -- none remaining: " .. itemId)
			return
		end

		inventory[itemId] = inventory[itemId] - 1
		state = TurnState.useItem(state)

		if itemId == "ExtraBall" then
			if #hand < state.HandSize then
				local extraBall = Ball.new(
					label .. "ExtraBall" .. tostring(#hand + 1),
					"Extra Ball",
					nil, -- neutral/speciesless -- StainlessBall model, see SharedModels
					"Water",
					"Common",
					{ Speed = 10, Atk = 10, Def = 10, HP = 10 },
					5
				)
				table.insert(hand, extraBall)
				print(label .. ": used ExtraBall, added a ball to hand (" .. tostring(#hand) .. "/" .. tostring(state.HandSize) .. ")")
			else
				print(label .. ": used ExtraBall but hand is full, no ball added")
			end
		else
			pendingSpeedDelta += item.Effect.SpeedDelta or 0
			pendingAtkDelta += item.Effect.AtkDelta or 0
			pendingAttractionDelta += item.Effect.AttractionDelta or 0
			if item.Effect.DestroysFirstObstacle then
				pendingDestroysFirstObstacle = true
			end
			table.insert(pendingModifierNames, item.Name)
			print(label .. ": used " .. itemId .. ", effect queued for next launch")
		end

		describeState("item used: " .. itemId)
	end

	local function startLevel(player: Player)
		if engagedPlayer and engagedPlayer ~= player then
			if movementLocked then
				setMovementLocked(engagedPlayer, false)
			end
			hudRemote:FireClient(engagedPlayer, nil)
			cameraRemote:FireClient(engagedPlayer, nil)
			print(label .. ": " .. engagedPlayer.Name .. " bumped by " .. player.Name .. " starting a new level")
		end

		if activeBallPart then
			activeBallPart:Destroy()
		end

		hand = freshHand()
		state = TurnState.new(hand, 3, encounter.PointThreshold)
		runCurrency = 0
		encounterRewardPaid = false
		activeBallPart = nil
		activeBallData = nil
		ballInMainField = false
		inventory = freshInventory()
		pendingSpeedDelta = 0
		pendingAtkDelta = 0
		pendingAttractionDelta = 0
		pendingDestroysFirstObstacle = false
		table.clear(pendingModifierNames)
		launchDestroysFirstObstacle = false
		movementLocked = false

		engagedPlayer = player
		cameraRemote:FireClient(player, cameraAnchor.CFrame)
		describeState("level started by " .. player.Name)
		print(label .. ": " .. player.Name .. " started a new level")
	end

	local function forceDisengage(player: Player)
		if engagedPlayer ~= player then
			return
		end
		engagedPlayer = nil
		movementLocked = false
		updateBackboard()
		print(label .. ": " .. player.Name .. " force-disengaged (left game)")
	end

	local function isEngagedBy(player: Player): boolean
		return engagedPlayer == player
	end

	local function setFlipperInput(side: CabinetBuilder.Side, pressed: boolean)
		CabinetBuilder.setFlipperInput(hinges, side, pressed, GameplayTuning.FLIPPER_MOTOR_SPEED)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StartLevelPrompt"
	prompt.ActionText = "Start Level"
	prompt.ObjectText = label
	prompt.HoldDuration = INTERACT_HOLD_DURATION
	prompt.MaxActivationDistance = INTERACT_MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	-- Default ProximityPrompt key is E, which collides with the Left flipper
	-- input (FlipperInputController.local.luau's KEY_TO_SIDE) -- F avoids it.
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = interactAnchor

	local handle: GameplayHandle = {
		BeginCharge = function(_player: Player)
			plungerHandle:BeginCharge()
		end,
		Launch = launch,
		UseItem = useItem,
		IsEngagedBy = isEngagedBy,
		StartLevel = startLevel,
		ForceDisengage = forceDisengage,
		SetFlipperInput = setFlipperInput,
	}

	prompt.Triggered:Connect(function(player: Player)
		handle.StartLevel(player)
	end)

	describeState("ready, hold R to launch, 1-5 to use an item")

	return handle
end

return CabinetGameplay
