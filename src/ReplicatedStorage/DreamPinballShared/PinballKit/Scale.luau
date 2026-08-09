--!strict

-- Single source of truth for the ball/inch/stud scale relationship used by every
-- PinballKit generator. Do not scatter scale factors or unexplained dimensions
-- elsewhere -- convert real-world pinball dimensions through this module only.

local Scale = {}

Scale.BALL_DIAMETER_STUDS = 1.5
Scale.BALL_RADIUS_STUDS = 0.75
Scale.REAL_BALL_DIAMETER_INCHES = 1.0625
Scale.STUDS_PER_INCH = Scale.BALL_DIAMETER_STUDS / Scale.REAL_BALL_DIAMETER_INCHES

-- Ball clearance (spec section 4): any enclosed path's inner diameter must be at
-- least the ball diameter plus 0.1 studs of radial clearance per side.
Scale.MIN_RADIAL_CLEARANCE_STUDS = 0.1
Scale.MIN_INNER_DIAMETER_STUDS = Scale.BALL_DIAMETER_STUDS + (Scale.MIN_RADIAL_CLEARANCE_STUDS * 2)
Scale.DEFAULT_INNER_DIAMETER_STUDS = 1.7

function Scale.InchesToStuds(inches: number): number
	return inches * Scale.STUDS_PER_INCH
end

function Scale.StudsToInches(studs: number): number
	return studs / Scale.STUDS_PER_INCH
end

-- Validates an enclosed-path inner diameter against the minimum ball clearance.
-- Every ramp, rail, tunnel, gate, or target opening must be checked with this
-- before it is used to generate geometry.
function Scale.ValidateInnerDiameter(innerDiameterStuds: number): (boolean, string?)
	if innerDiameterStuds ~= innerDiameterStuds or innerDiameterStuds == math.huge or innerDiameterStuds == -math.huge then
		return false, "InnerDiameter must be a finite number"
	end

	if innerDiameterStuds < Scale.MIN_INNER_DIAMETER_STUDS then
		return false,
			string.format(
				"InnerDiameter %.4f studs is below the minimum ball clearance of %.4f studs (ball diameter %.4f + %.4f clearance per side)",
				innerDiameterStuds,
				Scale.MIN_INNER_DIAMETER_STUDS,
				Scale.BALL_DIAMETER_STUDS,
				Scale.MIN_RADIAL_CLEARANCE_STUDS
			)
	end

	return true, nil
end

return Scale
