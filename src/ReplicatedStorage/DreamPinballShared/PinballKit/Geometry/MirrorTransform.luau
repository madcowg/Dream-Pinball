--!strict

-- Shared left/right mirroring primitives (spec section 6: generate one
-- canonical side, mirror for the other). Every function below mirrors across
-- the VERTICAL plane through `origin` that contains origin's own Up and Look
-- axes (i.e. negates the origin-local X component) -- never a hardcoded world
-- axis, so this still works after the whole playfield is translated, rotated,
-- or tilted.
--
-- IMPORTANT, found while wiring this into the existing generators: this
-- codebase already has two DIFFERENT, individually-correct mirroring
-- conventions, and they do not reduce to one formula:
--   1. A true linear reflection (negate the local-X component of a position
--      or direction, then re-derive an orthonormal frame) -- what
--      SlingshotGenerator's `MirrorX` already does to its wedge's Right
--      vector. MirrorPosition/MirrorDirection/MirrorCFrame below implement
--      exactly this, verified to reproduce SlingshotGenerator's existing
--      per-term math bit-for-bit.
--   2. FlipperGenerator's convention: negate the SIGNED rest angle and the
--      pivot-side offset, leaving the paddle's own local Y-axis rotation
--      construction otherwise untouched. This relies on a flipper paddle's
--      own near-planar symmetry and is NOT the same transform as (1) --
--      verified by direct computation that negating a yaw angle and
--      reflecting a Right/Up basis produce different rotation matrices in
--      general. MirrorAngleDegrees/MirrorSignedOffset below implement THIS
--      convention; do not use MirrorCFrame as a substitute for it on a
--      flipper's own rest orientation.
-- Use (1) for generic placement (lane paths, slingshot posts, rail
-- orientation) and (2) only for the flipper's own Side-driven angle/offset
-- math, matching how FlipperGenerator already builds its rest pose.

local MirrorTransform = {}

export type Side = "Left" | "Right"

-- Reflects a world position across origin's own vertical (Up/Look) plane.
function MirrorTransform.MirrorPosition(origin: CFrame, worldPosition: Vector3): Vector3
	local localPosition = origin:PointToObjectSpace(worldPosition)
	local mirroredLocal = Vector3.new(-localPosition.X, localPosition.Y, localPosition.Z)
	return origin:PointToWorldSpace(mirroredLocal)
end

-- Reflects a free direction vector (no translation) the same way.
function MirrorTransform.MirrorDirection(origin: CFrame, worldDirection: Vector3): Vector3
	local localDirection = origin:VectorToObjectSpace(worldDirection)
	local mirroredLocal = Vector3.new(-localDirection.X, localDirection.Y, localDirection.Z)
	return origin:VectorToWorldSpace(mirroredLocal)
end

-- Reflects both the position and the full orientation of a world CFrame.
-- Reconstructs the frame from the mirrored Right/Up axes via CFrame.fromMatrix's
-- 3-argument form (letting Roblox re-derive the third axis) rather than a
-- 4-argument call, per this library's own "Known Roblox physics limitations"
-- note on that form silently producing a mirrored transform when the axes are
-- inconsistent -- here that mirrored result is exactly what's wanted, and the
-- 3-arg form derives it safely from two already-orthonormal reflected axes.
function MirrorTransform.MirrorCFrame(origin: CFrame, worldCFrame: CFrame): CFrame
	local mirroredPosition = MirrorTransform.MirrorPosition(origin, worldCFrame.Position)
	local mirroredRight = MirrorTransform.MirrorDirection(origin, worldCFrame.RightVector)
	local mirroredUp = MirrorTransform.MirrorDirection(origin, worldCFrame.UpVector)
	return CFrame.fromMatrix(mirroredPosition, mirroredRight, mirroredUp)
end

-- Mirrors ONLY the Right axis (and position) across origin's vertical plane,
-- explicitly preserving Up and the Look/forward direction exactly as given --
-- unlike MirrorCFrame (which reflects the whole orientation via Right+Up,
-- correct for a shape that's symmetric under a 180-degree yaw, like
-- SlingshotGenerator's wedge, but flips the forward direction as a side
-- effect), this is the right choice for mirroring a PATH's starting CFrame:
-- a lane guide built from plain box segments (GuideRailBuilder) has no
-- chirality to get wrong, and the path must keep walking the SAME
-- functional direction (e.g. downhill toward the drain) on both sides while
-- only left/right swaps, and Up must stay vertical for correct wall-height
-- placement. Necessarily an improper (det = -1) transform -- verified safe
-- here specifically because every consumer is reflection-symmetric box
-- geometry; do not reuse this for an asymmetric shape's own placement (use
-- MirrorCFrame there instead).
function MirrorTransform.MirrorPathStart(origin: CFrame, worldCFrame: CFrame): CFrame
	local mirroredPosition = MirrorTransform.MirrorPosition(origin, worldCFrame.Position)
	local mirroredRight = MirrorTransform.MirrorDirection(origin, worldCFrame.RightVector)
	local up = worldCFrame.UpVector
	local back = -worldCFrame.LookVector
	return CFrame.fromMatrix(mirroredPosition, mirroredRight, up, back)
end

-- FlipperGenerator's own convention (see header comment): negates a signed
-- rest/active angle expressed in degrees. Verified to reproduce the sign flip
-- FlipperGenerator's old MOTOR_DIRECTION table applied by hand.
function MirrorTransform.MirrorAngleDegrees(angleDegrees: number): number
	return -angleDegrees
end

-- Same convention, for a signed local offset (e.g. FlipperGenerator's
-- pivot-side X offset) rather than an angle. Mathematically identical to
-- MirrorAngleDegrees; kept as a separate named entry point so call sites read
-- as "mirroring an offset," not "mirroring an angle."
function MirrorTransform.MirrorSignedOffset(value: number): number
	return -value
end

function MirrorTransform.MirrorSide(side: Side): Side
	if side == "Left" then
		return "Right"
	end
	return "Left"
end

-- Mirrors a set of local (X, Z) lane-path points across local X = 0.
function MirrorTransform.MirrorPath(points: { Vector2 }): { Vector2 }
	local mirrored = table.create(#points)
	for index, point in ipairs(points) do
		mirrored[index] = Vector2.new(-point.X, point.Y)
	end
	return mirrored
end

return MirrorTransform
