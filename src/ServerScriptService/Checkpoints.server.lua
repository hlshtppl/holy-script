local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local checkpoints = workspace:WaitForChild("Checkpoints")

-- remote buat tombol teleport dari panel
local remote = Instance.new("RemoteEvent")
remote.Name = "TeleportToCheckpoint"
remote.Parent = ReplicatedStorage

local function teleport(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local part = checkpoints:FindFirstChild(tostring(player:GetAttribute("Checkpoint") or 1))
	if root and part then
		root.CFrame = part.CFrame + Vector3.new(0, 4, 0)
	end
end

-- sentuh checkpoint = simpan (hanya kalau nomornya lebih tinggi)
for _, part in ipairs(checkpoints:GetChildren()) do
	local number = tonumber(part.Name)
	if number then
		part.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and number > (player:GetAttribute("Checkpoint") or 1) then
				player:SetAttribute("Checkpoint", number)
			end
		end)
	end
end

local function setupPlayer(player)
	player:SetAttribute("Checkpoint", 1)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		teleport(player) -- respawn di checkpoint terakhir
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end

remote.OnServerEvent:Connect(teleport)