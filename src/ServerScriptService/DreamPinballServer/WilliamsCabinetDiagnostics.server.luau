--!strict

--- Permanent, SERVER-SIDE diagnostics for WilliamsCabinet's ball-disappearing
--- bug. Every prior diagnostic attempt ran via Command Bar in CLIENT
--- context, which is unreliable for a server-owned ball (SetNetworkOwner(nil)
--- in CabinetGameplay.luau) -- a non-owning client only extrapolates its
--- position between replication packets, so client-side readings can show
--- contacts/positions the server never actually had. This script watches
--- the real, authoritative server state instead. Delete once the
--- disappearing-ball bug is confirmed fixed.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local cabinet = Workspace:WaitForChild("BakedCabinets"):WaitForChild("WilliamsCabinet")
local leftFlipper = cabinet:FindFirstChild("LeftFlipper", true) :: BasePart?
local rightFlipper = cabinet:FindFirstChild("RightFlipper", true) :: BasePart?

local function log(message: string)
	print("[WilliamsCabinetDiagnostics] " .. message)
end

if leftFlipper then
	leftFlipper.Touched:Connect(function(hit: BasePart)
		if hit.Name ~= "LaunchBall" then
			return
		end
		log("LeftFlipper contact -- ball at " .. tostring(hit.Position) .. " velocity=" .. tostring(hit.AssemblyLinearVelocity))
	end)
end

if rightFlipper then
	rightFlipper.Touched:Connect(function(hit: BasePart)
		if hit.Name ~= "LaunchBall" then
			return
		end
		log("RightFlipper contact -- ball at " .. tostring(hit.Position) .. " velocity=" .. tostring(hit.AssemblyLinearVelocity))
	end)
end

-- Captures the EXACT position/velocity the instant a LaunchBall is
-- destroyed, from the server's own authoritative state -- this alone
-- answers "was it the drain trigger, or something else, and from where."
cabinet.DescendantRemoving:Connect(function(descendant: Instance)
	if descendant.Name == "LaunchBall" and descendant:IsA("BasePart") then
		log("BALL DESTROYED at " .. tostring(descendant.Position) .. " velocity=" .. tostring(descendant.AssemblyLinearVelocity))
	end
end)

-- Always-on floor-gap guard, server-side this time -- one raycast per
-- heartbeat per active ball, flags anything more than 3 studs of empty
-- space directly below it.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- Roughly where the playfield actually is -- used only to flag a ball that
-- has been flung an implausible distance away (a hinge-overshoot ejection
-- would look like exactly this: a huge velocity spike, then the ball miles
-- from the board, never touching the drain, just gone from view).
local cabinetOrigin = (cabinet:FindFirstChild("LaunchAnchor", true) :: BasePart).Position

local function armFloorGapGuard(ball: BasePart)
	rayParams.FilterDescendantsInstances = { ball }
	local connection: RBXScriptConnection
	local lastVelocity: Vector3? = nil
	connection = RunService.Heartbeat:Connect(function()
		if not ball.Parent then
			connection:Disconnect()
			return
		end
		-- No longer logging every frame -- that wall of text was adding
		-- real overhead (Studio's Output console struggles with high-rate
		-- prints). Only anomalies below still print.
		local velocity = ball.AssemblyLinearVelocity

		if lastVelocity then
			local delta = (velocity - lastVelocity).Magnitude
			if delta > 40 then
				log("VELOCITY SPIKE: changed by " .. tostring(delta) .. " studs/s in one frame (from " .. tostring(lastVelocity) .. " to " .. tostring(velocity) .. ") -- possible hinge overshoot")
			end
		end
		lastVelocity = velocity

		local distanceFromBoard = (ball.Position - cabinetOrigin).Magnitude
		if distanceFromBoard > 100 then
			log("BALL FAR FROM BOARD: " .. tostring(distanceFromBoard) .. " studs from LaunchAnchor, at " .. tostring(ball.Position))
		end

		local result = Workspace:Raycast(ball.Position, Vector3.new(0, -50, 0), rayParams)
		if not result then
			log("NO SURFACE BELOW BALL at " .. tostring(ball.Position))
		elseif (ball.Position - result.Position).Magnitude > 3 then
			log("GAP BELOW BALL at " .. tostring(ball.Position) .. " -- nearest surface " .. result.Instance:GetFullName() .. " " .. tostring((ball.Position - result.Position).Magnitude) .. " studs down")
		end
	end)
end

cabinet.DescendantAdded:Connect(function(descendant: Instance)
	if descendant.Name == "LaunchBall" and descendant:IsA("BasePart") then
		armFloorGapGuard(descendant)
	end
end)

log("armed -- server-side flipper contact, destroy-position, and floor-gap logging active for WilliamsCabinet")
