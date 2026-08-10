local cabinet = workspace.BakedCabinets.WilliamsCabinet
local floor = cabinet:FindFirstChild("CabinetFloor", true)
local leftFlipper = cabinet:FindFirstChild("LeftFlipper", true)
local rightFlipper = cabinet:FindFirstChild("RightFlipper", true)

print("CabinetFloor Position: " .. tostring(floor.Position))
print("CabinetFloor Size: " .. tostring(floor.Size))
print("LeftFlipper Position: " .. tostring(leftFlipper.Position))
print("RightFlipper Position: " .. tostring(rightFlipper.Position))

local function checkOverFloor(name, flipper)
	local localPos = floor.CFrame:PointToObjectSpace(flipper.Position)
	local halfX = floor.Size.X / 2
	local halfZ = floor.Size.Z / 2
	local outside = math.abs(localPos.X) > halfX or math.abs(localPos.Z) > halfZ
	print(name .. " local-to-floor: " .. tostring(localPos) .. " halfExtents X=" .. tostring(halfX) .. " Z=" .. tostring(halfZ) .. " -- " .. (if outside then "OUTSIDE FLOOR FOOTPRINT" else "within floor footprint"))
end

checkOverFloor("LeftFlipper", leftFlipper)
checkOverFloor("RightFlipper", rightFlipper)

local RunService = game:GetService("RunService")

local function onFlipperTouched(flipperName, hit)
	if hit.Name ~= "LaunchBall" then
		return
	end
	print("CONTACT: " .. flipperName .. " touched by ball at " .. tostring(hit.Position) .. " velocity=" .. tostring(hit.AssemblyLinearVelocity))
	task.defer(function()
		if hit.Parent then
			print("CONTACT +1frame: velocity=" .. tostring(hit.AssemblyLinearVelocity) .. " position=" .. tostring(hit.Position))
		else
			print("CONTACT +1frame: ball already destroyed!")
		end
	end)
end

leftFlipper.Touched:Connect(function(hit)
	onFlipperTouched("LeftFlipper", hit)
end)

rightFlipper.Touched:Connect(function(hit)
	onFlipperTouched("RightFlipper", hit)
end)

cabinet.DescendantAdded:Connect(function(descendant)
	if descendant.Name ~= "LaunchBall" or not descendant:IsA("BasePart") then
		return
	end
	local ball = descendant
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not ball.Parent then
			conn:Disconnect()
			return
		end
		local localToFloor = floor.CFrame:PointToObjectSpace(ball.Position)
		if localToFloor.Y < -2 then
			print("FELL THROUGH FLOOR: ball at " .. tostring(ball.Position) .. " is " .. tostring(localToFloor.Y) .. " studs below CabinetFloor surface")
		end
	end)
end)

print("Diagnostics armed -- play and try to reproduce the disappearing ball near the flippers.")
