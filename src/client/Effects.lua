--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Config = require(game:GetService("ReplicatedStorage").MailAMonster.Shared.Config)
local Theme = require(script.Parent.Theme)
local Effects = {}

local function ownPlot(): Instance?
	local world = workspace:FindFirstChild("MailAMonsterWorld")
	local plots = world and world:FindFirstChild("Plots")
	local index = Players.LocalPlayer:GetAttribute("MAMPlotIndex")
	return plots and plots:FindFirstChild("Plot" .. tostring(index))
end

local function cue(name: string, settings: any)
	local id = Config.Audio[name]
	if type(id) ~= "string" or id == "" or (settings.sfxVolume or 0) == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId, sound.Volume, sound.Parent = id, settings.sfxVolume, SoundService
	Debris:AddItem(sound, 8)
	sound:Play()
end

function Effects.dispatch(settings: any)
	local plot = ownPlot()
	local cannon = plot and plot:FindFirstChild("Cannon")
	local muzzle = cannon and cannon:FindFirstChild("Muzzle")
	if not (muzzle and muzzle:IsA("BasePart")) then return end
	local barrel = cannon:FindFirstChild("Barrel")
	local reduced = settings and settings.reducedMotion
	cue("Launch", settings or {})
	if barrel and barrel:IsA("BasePart") and not reduced then
		local original = barrel.CFrame
		TweenService:Create(barrel, TweenInfo.new(0.18, Enum.EasingStyle.Back), { CFrame = original - muzzle.CFrame.LookVector * 0.7 }):Play()
		task.delay(0.18, function()
			if barrel.Parent then TweenService:Create(barrel, TweenInfo.new(0.4, Enum.EasingStyle.Bounce), { CFrame = original }):Play() end
		end)
	end
	if not reduced and settings and settings.cameraShake then
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local original = humanoid.CameraOffset
			TweenService:Create(humanoid, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), { CameraOffset = original + Vector3.new(0.12, 0.1, 0) }):Play()
			task.delay(0.2, function() if humanoid.Parent then humanoid.CameraOffset = original end end)
		end
	end
	local parcel = Instance.new("Part")
	parcel.Name = "AcceptedDispatchParcel"
	parcel.Size = Vector3.new(1.9, 1.6, 1.6)
	parcel.Color = Theme.Cream
	parcel.Material = Enum.Material.SmoothPlastic
	parcel.Anchored, parcel.CanCollide, parcel.CanTouch, parcel.CanQuery = true, false, false, false
	parcel.CFrame = muzzle.CFrame
	parcel.Parent = workspace
	Debris:AddItem(parcel, 3)
	if reduced then
		TweenService:Create(parcel, TweenInfo.new(0.45), { Transparency = 1 }):Play()
		return
	end
	local a = Instance.new("Attachment")
	a.Position, a.Parent = Vector3.new(-0.7, 0, 0), parcel
	local b = Instance.new("Attachment")
	b.Position, b.Parent = Vector3.new(0.7, 0, 0), parcel
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a, b
	trail.Color = ColorSequence.new(Theme.Coral, Theme.Sky)
	trail.Lifetime, trail.Parent = 0.6, parcel
	TweenService:Create(parcel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Size = Vector3.new(2.2, 1.2, 1.6) }):Play()
	task.delay(0.2, function()
		if not parcel.Parent then return end
		local direction = muzzle.CFrame.LookVector
		TweenService:Create(parcel, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = parcel.CFrame + direction * 65 + Vector3.new(0, 45, 0),
			Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1,
		}):Play()
	end)
end

function Effects.mailbox(settings: any)
	cue("Mail", settings or {})
	if settings and settings.reducedMotion then return end
	local plot = ownPlot()
	local mailbox = plot and plot:FindFirstChild("Mailbox")
	if not mailbox then return end
	if not mailbox:IsA("Model") then return end
	local original = mailbox:GetPivot()
	local value = Instance.new("NumberValue")
	local signal = value.Changed:Connect(function(height)
		if mailbox.Parent then mailbox:PivotTo(original + Vector3.new(0, height, 0)) end
	end)
	local tween = TweenService:Create(value, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 1, true), { Value = 0.6 })
	tween.Completed:Once(function()
		signal:Disconnect()
		value:Destroy()
		if mailbox.Parent then mailbox:PivotTo(original) end
	end)
	tween:Play()
end

return Effects
