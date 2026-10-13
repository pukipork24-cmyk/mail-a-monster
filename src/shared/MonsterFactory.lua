--!strict
-- All monster art is made here from local Roblox primitives. No asset downloads.
local TweenService = game:GetService("TweenService")

local MonsterFactory = {}
local running: { [Model]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

local palette = {
	cream = Color3.fromRGB(255, 230, 177),
	teal = Color3.fromRGB(104, 210, 186),
	coral = Color3.fromRGB(255, 151, 140),
	lavender = Color3.fromRGB(188, 167, 237),
	sky = Color3.fromRGB(135, 205, 238),
	lemon = Color3.fromRGB(245, 221, 118),
}
local ink = Color3.fromRGB(47, 65, 82)
local cream = Color3.fromRGB(255, 247, 221)
local coral = Color3.fromRGB(245, 127, 120)
local teal = Color3.fromRGB(64, 165, 159)
local lavender = Color3.fromRGB(162, 137, 216)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ball(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	return part(parent, name, size, CFrame.new(position), color, Enum.PartType.Ball)
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, color: Color3): Part
	local delta = b - a
	return part(parent, name, Vector3.new(width, width, delta.Magnitude), CFrame.lookAt((a + b) / 2, b), color)
end

local function disc(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	return part(parent, name, size, cf * CFrame.Angles(0, 0, math.pi / 2), color, Enum.PartType.Cylinder)
end

local function star(parent: Instance, name: string, center: Vector3, radius: number, color: Color3)
	for i = 0, 4 do
		local theta = i * math.pi * 2 / 5
		local inner = center + Vector3.new(math.sin(theta), math.cos(theta), 0) * radius * 0.2
		local outer = center + Vector3.new(math.sin(theta), math.cos(theta), 0) * radius
		rod(parent, name .. tostring(i), inner, outer, radius * 0.35, color)
	end
	ball(parent, name .. "Center", Vector3.new(radius * 0.7, radius * 0.7, 0.15), center, color)
end

local function envelope(parent: Instance, position: Vector3, size: number, color: Color3)
	part(parent, "Envelope", Vector3.new(size, size * 0.68, 0.12), CFrame.new(position), color)
	local front = position + Vector3.new(0, 0, -0.07)
	rod(parent, "FoldLeft", front + Vector3.new(-size / 2, size * 0.32, 0), front, 0.05, coral)
	rod(parent, "FoldRight", front + Vector3.new(size / 2, size * 0.32, 0), front, 0.05, coral)
end

local function face(parent: Instance, style: string, z: number)
	local eyeY = 2.58
	for _, sign in ipairs({ -1, 1 }) do
		local x = sign * 0.53
		if style == "sleepy" or (style == "wink" and sign == 1) then
			rod(parent, "ClosedEye", Vector3.new(x - 0.18, eyeY, z), Vector3.new(x + 0.18, eyeY + sign * 0.06, z), 0.09, ink)
		else
			ball(parent, "Eye", Vector3.new(0.24, 0.36, 0.15), Vector3.new(x, eyeY, z), ink)
			ball(parent, "EyeGlint", Vector3.new(0.075, 0.085, 0.05), Vector3.new(x - 0.045, eyeY + 0.08, z - 0.08), cream)
		end
		ball(parent, "Cheek", Vector3.new(0.39, 0.19, 0.07), Vector3.new(sign * 0.9, eyeY - 0.33, z + 0.04), coral)
	end
	if style == "surprised" then
		ball(parent, "Mouth", Vector3.new(0.24, 0.32, 0.08), Vector3.new(0, 2.08, z - 0.02), ink)
	else
		rod(parent, "SmileLeft", Vector3.new(-0.23, 2.13, z), Vector3.new(0, 2.04, z - 0.02), 0.07, ink)
		rod(parent, "SmileRight", Vector3.new(0, 2.04, z - 0.02), Vector3.new(0.23, 2.13, z), 0.07, ink)
	end
end

-- A stable attachment frame makes every accessory compatible with every family.
local function renderSouvenir(parent: Instance, id: string, slot: string)
	if slot == "hat" then
		if id == "sunhat" then
			disc(parent, "SunhatBrim", Vector3.new(0.17, 2.75, 2.75), CFrame.new(0, 4.06, 0), palette.lemon)
			disc(parent, "SunhatCrown", Vector3.new(0.65, 1.56, 1.56), CFrame.new(0, 4.4, 0), palette.lemon)
			disc(parent, "SunhatRibbon", Vector3.new(0.15, 1.6, 1.6), CFrame.new(0, 4.17, 0), coral)
		elseif id == "sproutcap" then
			disc(parent, "SproutCap", Vector3.new(0.35, 1.8, 1.8), CFrame.new(0, 4.16, 0), teal)
			rod(parent, "SproutStem", Vector3.new(0, 4.26, 0), Vector3.new(0, 5.02, 0), 0.14, teal)
			for _, sign in ipairs({ -1, 1 }) do
				part(parent, "CapLeaf", Vector3.new(0.94, 0.3, 0.6), CFrame.new(sign * 0.34, 4.86, 0) * CFrame.Angles(0, 0, sign * 0.45), palette.lemon, Enum.PartType.Ball)
			end
		elseif id == "hat_bucket" or id == "bucket_hat" or string.find(id, "bucket", 1, true) then
			disc(parent, "BucketBrim", Vector3.new(0.17, 2.15, 2.15), CFrame.new(0, 4.06, 0), teal)
			disc(parent, "BucketCrown", Vector3.new(0.73, 1.58, 1.58), CFrame.new(0, 4.43, 0), teal)
			envelope(parent, Vector3.new(0, 4.42, -0.81), 0.52, cream)
		elseif string.find(id, "crown", 1, true) then
			disc(parent, "CrownBand", Vector3.new(0.35, 1.8, 1.8), CFrame.new(0, 4.2, 0), palette.lemon)
			for i = 0, 4 do
				local a = i * math.pi * 2 / 5
				ball(parent, "CrownTip", Vector3.new(0.28, 0.64, 0.28), Vector3.new(math.sin(a) * 0.72, 4.59, math.cos(a) * 0.72), palette.lemon)
			end
			ball(parent, "CrownJewel", Vector3.new(0.29, 0.29, 0.12), Vector3.new(0, 4.25, -0.91), coral)
		elseif string.find(id, "flower", 1, true) then
			for i = 0, 7 do
				local a = i * math.pi / 4
				ball(parent, "FlowerPetal", Vector3.new(0.64, 0.3, 0.64), Vector3.new(math.sin(a) * 0.77, 4.12, math.cos(a) * 0.77), coral)
			end
			ball(parent, "FlowerHeart", Vector3.new(1, 0.4, 1), Vector3.new(0, 4.22, 0), palette.lemon)
		elseif string.find(id, "paper", 1, true) or string.find(id, "boat", 1, true) then
			part(parent, "PaperBrim", Vector3.new(2.05, 0.16, 1.4), CFrame.new(0, 4.05, 0), cream)
			for _, sign in ipairs({ -1, 1 }) do
				part(parent, "PaperFold", Vector3.new(1.3, 0.13, 1.35), CFrame.new(sign * 0.38, 4.48, 0) * CFrame.Angles(0, 0, sign * math.pi / 4), cream)
			end
		else
			-- Postal cap is the canonical fourth hat and a harmless future fallback.
			disc(parent, "PostalCap", Vector3.new(0.62, 1.75, 1.75), CFrame.new(0, 4.28, 0), lavender)
			ball(parent, "CapVisor", Vector3.new(1.8, 0.18, 1.12), Vector3.new(0, 4.05, -0.6), ink)
			envelope(parent, Vector3.new(0, 4.28, -0.89), 0.55, cream)
		end
	elseif slot == "accessory" then
		if string.find(id, "glasses", 1, true) or string.find(id, "spectacle", 1, true) then
			for _, sign in ipairs({ -1, 1 }) do
				local x = sign * 0.53
				for _, y in ipairs({ 2.31, 2.87 }) do
					rod(parent, "GlassesRim", Vector3.new(x - 0.33, y, -1.81), Vector3.new(x + 0.33, y, -1.81), 0.1, teal)
				end
				for _, edge in ipairs({ -0.33, 0.33 }) do
					rod(parent, "GlassesSide", Vector3.new(x + edge, 2.31, -1.81), Vector3.new(x + edge, 2.87, -1.81), 0.1, teal)
				end
			end
			rod(parent, "GlassesBridge", Vector3.new(-0.19, 2.64, -1.81), Vector3.new(0.19, 2.64, -1.81), 0.1, teal)
		elseif string.find(id, "wing", 1, true) then
			for _, sign in ipairs({ -1, 1 }) do
				part(parent, "Wing", Vector3.new(1.25, 2, 0.5), CFrame.new(sign * 1.93, 2.15, 0.2) * CFrame.Angles(0, 0, -sign * 0.5), cream, Enum.PartType.Ball)
				ball(parent, "WingTip", Vector3.new(0.7, 1.25, 0.45), Vector3.new(sign * 2.28, 1.61, 0.18), palette.sky)
			end
		elseif string.find(id, "satchel", 1, true) or string.find(id, "bag", 1, true) then
			rod(parent, "SatchelStrap", Vector3.new(-1.04, 3.1, -1.54), Vector3.new(1.48, 1.15, -1.54), 0.19, ink)
			part(parent, "Satchel", Vector3.new(1.2, 1, 0.4), CFrame.new(1.23, 1.13, -1.4), coral)
			envelope(parent, Vector3.new(1.23, 1.2, -1.63), 0.65, cream)
		elseif string.find(id, "bow", 1, true) then
			for _, sign in ipairs({ -1, 1 }) do
				part(parent, "Bow", Vector3.new(0.78, 0.58, 0.24), CFrame.new(sign * 0.35, 1.46, -1.63) * CFrame.Angles(0, 0, sign * 0.35), coral, Enum.PartType.Ball)
			end
			ball(parent, "BowKnot", Vector3.new(0.32, 0.4, 0.3), Vector3.new(0, 1.46, -1.68), lavender)
		else
			ball(parent, "ScarfWrap", Vector3.new(3.4, 0.47, 3.15), Vector3.new(0, 1.15, 0), coral)
			part(parent, "ScarfTail", Vector3.new(0.53, 1.15, 0.24), CFrame.new(0.82, 0.65, -1.53) * CFrame.Angles(0, 0, 0.18), coral)
		end
	elseif slot == "patch" then
		if string.find(id, "heart", 1, true) then
			ball(parent, "HeartLeft", Vector3.new(0.43, 0.44, 0.14), Vector3.new(-0.17, 1.57, -1.64), coral)
			ball(parent, "HeartRight", Vector3.new(0.43, 0.44, 0.14), Vector3.new(0.17, 1.57, -1.64), coral)
			part(parent, "HeartPoint", Vector3.new(0.48, 0.48, 0.12), CFrame.new(0, 1.34, -1.64) * CFrame.Angles(0, 0, math.pi / 4), coral)
		elseif string.find(id, "cloud", 1, true) then
			for i = -1, 1 do
				ball(parent, "CloudPatch", Vector3.new(0.48, 0.43 + (i == 0 and 0.15 or 0), 0.12), Vector3.new(i * 0.29, 1.48 + (i == 0 and 0.08 or 0), -1.67), cream)
			end
		elseif string.find(id, "freckle", 1, true) or string.find(id, "spot", 1, true) then
			for i = 1, 5 do
				ball(parent, "Freckle", Vector3.new(0.18, 0.18, 0.09), Vector3.new((i - 3) * 0.26, 1.52 + (i % 2) * 0.19, -1.66), lavender)
			end
		elseif string.find(id, "moon", 1, true) then
			ball(parent, "Moon", Vector3.new(0.8, 0.83, 0.11), Vector3.new(0, 1.52, -1.64), palette.lemon)
			ball(parent, "MoonInset", Vector3.new(0.65, 0.67, 0.12), Vector3.new(0.2, 1.68, -1.72), lavender)
		else
			star(parent, "StarPatch", Vector3.new(0, 1.5, -1.7), 0.51, palette.lemon)
		end
	end
end

function MonsterFactory.applySouvenirs(model: Model, slots: { [string]: string }?)
	local old = model:FindFirstChild("Souvenirs")
	if old then old:Destroy() end
	local attachments = Instance.new("Model")
	attachments.Name = "Souvenirs"
	local pivot = model:GetPivot()
	local scale = model:GetScale()
	for _, slot in ipairs({ "hat", "accessory", "patch" }) do
		local id = slots and slots[slot]
		if type(id) == "string" then
			local visual = Instance.new("Model")
			visual.Name = slot
			visual:SetAttribute("SouvenirId", id)
			visual.Parent = attachments
			renderSouvenir(visual, id, slot)
		end
	end
	-- Build attachments at authoring scale, then transform exactly once into the
	-- monster's current pivot. This also works for viewport and display models.
	for _, descendant in ipairs(attachments:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local cf = descendant.CFrame
			descendant.Size *= scale
			descendant.CFrame = pivot * CFrame.new(cf.Position * scale) * cf.Rotation
		end
	end
	attachments.Parent = model
end

function MonsterFactory.create(monster: any, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = tostring(monster.name or "Little monster")
	model:SetAttribute("MonsterId", tostring(monster.id or ""))
	model:SetAttribute("Personality", monster.personality or "Curious")
	model:SetAttribute("BodyFamily", monster.body or "puff")
	model:SetAttribute("Palette", monster.palette or "cream")
	local root = part(model, "Root", Vector3.one * 0.2, CFrame.identity, cream)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root
	local geometry = Instance.new("Model")
	geometry.Name = "Body"
	geometry.Parent = model
	local color = palette[monster.palette] or palette.cream
	local light = color:Lerp(cream, 0.38)
	local body = monster.body or "puff"
	local faceZ = -1.51
	if body == "slug" then
		ball(geometry, "SlugBody", Vector3.new(4.15, 2.7, 3.1), Vector3.new(0, 1.82, 0.25), color)
		ball(geometry, "SlugHead", Vector3.new(2.8, 2.9, 2.7), Vector3.new(0, 2.38, -0.08), color)
		for _, sign in ipairs({ -1, 1 }) do
			rod(geometry, "Feelers", Vector3.new(sign * 0.75, 3.3, -0.08), Vector3.new(sign * 1.1, 4.0, -0.2), 0.17, light)
			ball(geometry, "FeelerTip", Vector3.new(0.32, 0.32, 0.32), Vector3.new(sign * 1.1, 4.0, -0.2), coral)
		end
	elseif body == "sprout" then
		ball(geometry, "SproutBody", Vector3.new(3.3, 3.55, 3.0), Vector3.new(0, 2.08, 0), color)
		for _, sign in ipairs({ -1, 1 }) do
			part(geometry, "Leaf", Vector3.new(1.4, 0.32, 0.75), CFrame.new(sign * 0.49, 3.98, 0.22) * CFrame.Angles(0, sign * 0.3, sign * 0.55), teal, Enum.PartType.Ball)
		end
	elseif body == "bean" then
		part(geometry, "BeanBody", Vector3.new(3.0, 3.65, 2.9), CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, -0.09), color, Enum.PartType.Ball)
		ball(geometry, "BeanBelly", Vector3.new(2.05, 2.1, 1.7), Vector3.new(0.34, 1.6, 0.06), color)
		ball(geometry, "BeanTuft", Vector3.new(0.74, 0.75, 0.7), Vector3.new(-0.43, 3.75, 0), light)
	else
		ball(geometry, "PuffBody", Vector3.new(3.65, 3.4, 3.25), Vector3.new(0, 2.05, 0), color)
		for _, sign in ipairs({ -1, 1 }) do
			ball(geometry, "PuffEar", Vector3.new(0.95, 1.1, 0.9), Vector3.new(sign * 1.28, 3.35, 0.15), light)
		end
		faceZ = -1.65
	end
	for _, sign in ipairs({ -1, 1 }) do
		ball(geometry, "Foot", Vector3.new(0.93, 0.46, 1.15), Vector3.new(sign * 0.89, 0.36, -0.22), light)
		part(geometry, "Arm", Vector3.new(0.51, 0.86, 0.7), CFrame.new(sign * 1.51, 1.57, -0.1) * CFrame.Angles(0, 0, sign * 0.25), light, Enum.PartType.Ball)
	end
	face(geometry, monster.face or "smile", faceZ)
	model:ScaleTo(math.clamp(scale or 1, 0.15, 5))
	MonsterFactory.applySouvenirs(model, monster.slots or {})
	return model
end

function MonsterFactory.react(model: Model, reaction: string, reducedMotion: boolean?)
	if running[model] then running[model]() end
	model:SetAttribute("Reaction", reaction)
	if reducedMotion or not model.Parent then return end
	local duration = reaction == "idle" and 2.4 or (reaction == "homecoming" and 1.6 or 0.9)
	local base = model:GetPivot()
	local value = Instance.new("NumberValue")
	local connection: RBXScriptConnection? = nil
	local deathConnection: RBXScriptConnection? = nil
	local completed: RBXScriptConnection? = nil
	local finished = false
	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = 1 })
	local function cleanup()
		if finished then return end
		finished = true
		if connection then connection:Disconnect() end
		if deathConnection then deathConnection:Disconnect() end
		if completed then completed:Disconnect() end
		tween:Cancel()
		value:Destroy()
		if model.Parent then model:PivotTo(base) end
		running[model] = nil
	end
	running[model] = cleanup
	connection = value.Changed:Connect(function(t)
		if not model.Parent then cleanup(); return end
		local wave = math.sin(t * math.pi)
		local height, tilt = 0.12 * wave, 0
		if reaction == "happy" or reaction == "homecoming" then
			height = math.abs(math.sin(t * math.pi * 2)) * (reaction == "homecoming" and 0.95 or 0.55)
			tilt = math.sin(t * math.pi * 2) * 0.14
		elseif reaction == "startled" then
			height, tilt = wave * 0.42, -wave * 0.15
		elseif reaction == "packing" then
			height, tilt = -wave * 0.23, math.sin(t * math.pi * 4) * 0.09
		elseif model:GetAttribute("Personality") == "Sleepy" then
			height, tilt = wave * 0.07, wave * 0.045
		elseif model:GetAttribute("Personality") == "Mischievous" then
			tilt = math.sin(t * math.pi * 2) * 0.09
		elseif model:GetAttribute("Personality") == "Dramatic" then
			height, tilt = wave * 0.23, math.sin(t * math.pi * 2) * 0.11
		end
		local personality = model:GetAttribute("Personality")
		if personality == "Sleepy" then height *= 0.55; tilt *= 0.5
		elseif personality == "Dramatic" then height *= 1.3; tilt *= 1.25
		elseif personality == "Mischievous" then tilt += math.sin(t * math.pi * 4) * 0.06 end
		model:PivotTo(base * CFrame.new(0, height, 0) * CFrame.Angles(0, 0, tilt))
	end)
	deathConnection = model.Destroying:Connect(cleanup)
	completed = tween.Completed:Connect(cleanup)
	tween:Play()
end

return MonsterFactory
