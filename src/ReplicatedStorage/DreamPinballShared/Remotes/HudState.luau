--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAME = "HudStateRemote"

--- Server fires this at a specific player with a snapshot table whenever
--- their engaged cabinet's state changes (launch, scoring bounce, item use,
--- turn end). Payload shape is HudState.Snapshot below -- nil means the
--- player is not currently engaged with any cabinet (HUD should hide).
export type BallSnapshot = {
	Name: string,
	CurrentDurability: number,
	MaxDurability: number,
}

export type Snapshot = {
	CabinetLabel: string,
	TurnNumber: number,
	MaxTurns: number,
	Score: number,
	PointThreshold: number,
	Result: string,
	RunCurrency: number,
	Hand: { BallSnapshot },
	ActiveBallIndex: number?,
}

local HudRemotes = {}

function HudRemotes.getHudStateRemote(): RemoteEvent
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = ReplicatedStorage
		return remote
	end

	return ReplicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteEvent
end

return HudRemotes
