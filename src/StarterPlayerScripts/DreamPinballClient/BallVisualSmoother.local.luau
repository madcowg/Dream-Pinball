--!strict

--- Smooths the visual position of server-owned pinballs (LaunchBall parts,
--- created by CabinetGameplay.luau) so their movement looks fluid on every
--- client regardless of network replication timing. The ball itself stays
--- fully server-owned (see CabinetGameplay.luau's SetNetworkOwner(nil) --
--- required so a client can't teleport it onto bumpers to farm score); a
--- server-owned part's CFrame only updates when a network replication
--- packet arrives, which under load/latency can visibly stutter -- freeze,
--- then jump forward once a delayed update lands (reported during the
--- WilliamsCabinet plunger: ball lags, then "reappears" further along the
--- lane). Instead of touching the real ball's CFrame (which would fight the
--- server's own replication), this hides the real ball from THIS client's
--- view only (LocalTransparencyModifier -- a client-only, non-replicated
--- override; the same mechanism Roblox's own first-person camera scripts
--- use to hide the character's head) and drives a purely cosmetic, non-
--- colliding clone that smoothly chases the real ball's latest known CFrame
--- every frame. The real ball keeps colliding/scoring/draining exactly as
--- the server intends -- only what the player SEES is decoupled and
--- smoothed, so there is no exploit/trust tradeoff.
-- TEMPORARILY DISABLED for diagnosis -- user reports the ball "floats
-- weirdly," seems to miss flipper contact, and disappears specifically near
-- the flippers (not at the drain). Server-side logs (WilliamsCabinetDiagnostics)
-- have twice shown the REAL ball behaving correctly with no floor gaps and
-- destruction only via the legitimate drain -- but the player never sees
-- the real ball, only this script's cosmetic clone chasing it. Disabling
-- entirely so the player sees the real, raw-replicated ball directly (some
-- normal network stutter expected) to isolate whether the smoothing itself
-- is the source of the visual symptoms. Re-enable once confirmed either way.
return

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BALL_NAME = "LaunchBall"
-- Higher = the visual clone catches up to the real ball faster (less
-- smoothing, more of any real stutter shows through); lower = smoother but
-- the visual trails the real position more during a sudden direction
-- change (e.g. a flipper hit). Framerate-independent (derived from dt each
-- frame below), so this feels the same at 30fps or 144fps.
local SMOOTHING_RATE = 18

local activeSmoothers: { [BasePart]: BasePart } = {}

local function cloneVisual(realBall: BasePart): BasePart
	local visual = Instance.new("Part")
	visual.Name = realBall.Name .. "Visual"
	visual.Shape = realBall.Shape
	visual.Size = realBall.Size
	visual.Material = realBall.Material
	visual.Color = realBall.Color
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CanTouch = false
	visual.CastShadow = realBall.CastShadow
	visual.CFrame = realBall.CFrame
	visual.Parent = realBall.Parent
	return visual
end

local function onBallAdded(realBall: BasePart)
	if activeSmoothers[realBall] then
		return
	end

	local visual = cloneVisual(realBall)
	activeSmoothers[realBall] = visual
	realBall.LocalTransparencyModifier = 1

	local sizeConnection = realBall:GetPropertyChangedSignal("Size"):Connect(function()
		visual.Size = realBall.Size
	end)
	local colorConnection = realBall:GetPropertyChangedSignal("Color"):Connect(function()
		visual.Color = realBall.Color
	end)

	realBall.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			activeSmoothers[realBall] = nil
			sizeConnection:Disconnect()
			colorConnection:Disconnect()
			visual:Destroy()
		end
	end)
end

for _, descendant in Workspace:GetDescendants() do
	if descendant.Name == BALL_NAME and descendant:IsA("BasePart") then
		onBallAdded(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(descendant: Instance)
	if descendant.Name == BALL_NAME and descendant:IsA("BasePart") then
		onBallAdded(descendant :: BasePart)
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	-- 1 - e^(-rate*dt): asymptotically approaches the target every frame,
	-- independent of frame rate -- the same visual "weight"/lag at 30fps or
	-- 144fps, unlike a fixed-fraction Lerp which would smooth more slowly
	-- per-second at low framerates.
	local alpha = 1 - math.exp(-SMOOTHING_RATE * dt)
	for realBall, visual in activeSmoothers do
		if not realBall.Parent then
			continue
		end
		visual.CFrame = visual.CFrame:Lerp(realBall.CFrame, alpha)
	end
end)
