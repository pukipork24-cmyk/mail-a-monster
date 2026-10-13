--!strict
-- Temporary island geometry. Persistent ownership, purchases and placements are
-- owned by Gameplay/VoyageService; no world instance is a currency authority.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Shared = ReplicatedStorage:WaitForChild("MailAMonster"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local MonsterFactory = require(Shared:WaitForChild("MonsterFactory"))

local World = {}
local activeWorld: any = nil
local C = {
	cream = Color3.fromRGB(255, 244, 218), teal = Color3.fromRGB(65, 164, 160),
	coral = Color3.fromRGB(244, 139, 128), lavender = Color3.fromRGB(187, 165, 222),
	sky = Color3.fromRGB(149, 210, 236), ink = Color3.fromRGB(48, 69, 82),
	grass = Color3.fromRGB(174, 213, 170), leaf = Color3.fromRGB(108, 173, 126),
	lemon = Color3.fromRGB(251, 221, 127), white = Color3.fromRGB(255, 251, 237),
}

local function makeModel(parent: Instance?, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Origin"
	root.Size = Vector3.one * 0.1
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = parent
	return model
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, collide: boolean?): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	object.CFrame = cf
	object.Color = color
	object.Material = Enum.Material.SmoothPlastic
	object.Shape = shape or Enum.PartType.Block
	object.Anchored = true
	object.CanCollide = collide ~= false
	object.CanTouch = false
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Parent = parent
	return object
end

local function ball(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, collide: boolean?): Part
	return part(parent, name, size, CFrame.new(position), color, Enum.PartType.Ball, collide)
end

local function disc(parent: Instance, name: string, position: Vector3, radius: number, height: number, color: Color3, collide: boolean?): Part
	return part(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.PartType.Cylinder, collide)
end

local function rod(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, color: Color3, collide: boolean?): Part
	return part(parent, name, Vector3.new(width, width, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, nil, collide)
end

local function label(parent: BasePart, text: string, width: number?, height: number?, offset: number?, color: Color3?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromOffset(width or 190, height or 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset or 2.8, 0)
	gui.MaxDistance = 115
	gui.AlwaysOnTop = false
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundColor3 = C.white
	textLabel.BackgroundTransparency = 0.08
	textLabel.Text = text
	textLabel.TextColor3 = color or C.ink
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = 16
	textLabel.TextWrapped = true
	textLabel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = textLabel
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.ink
	stroke.Transparency = 0.8
	stroke.Thickness = 1
	stroke.Parent = textLabel
	gui.Parent = parent
	return gui
end

local function prompt(parent: BasePart, action: string, title: string, kind: string?, target: string?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = "Interact"
	p.ActionText = title
	p.ObjectText = "MAIL A MONSTER"
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("MAMAction", action)
	p:SetAttribute("MAMKind", kind or "")
	if target then p:SetAttribute("MAMTarget", target) end
	p.Parent = parent
	return p
end

local function envelope(parent: Instance, cf: CFrame, width: number, color: Color3): Part
	local base = part(parent, "Envelope", Vector3.new(width, width * 0.66, 0.12), cf, color, nil, false)
	local a = cf:PointToWorldSpace(Vector3.new(-width * 0.48, width * 0.29, -0.07))
	local b = cf:PointToWorldSpace(Vector3.new(width * 0.48, width * 0.29, -0.07))
	local middle = cf:PointToWorldSpace(Vector3.new(0, -width * 0.09, -0.07))
	rod(parent, "Fold", a, middle, 0.06, C.coral, false)
	rod(parent, "Fold", b, middle, 0.06, C.coral, false)
	return base
end

local function flower(parent: Instance, position: Vector3, color: Color3, scale: number?)
	local s = scale or 1
	rod(parent, "Stem", position, position + Vector3.new(0, 1.4 * s, 0), 0.13 * s, C.leaf, false)
	for i = 0, 4 do
		local a = i * math.pi * 2 / 5
		ball(parent, "Petal", Vector3.new(0.6, 0.23, 0.6) * s, position + Vector3.new(math.sin(a) * 0.36, 1.45, math.cos(a) * 0.36) * s, color, false)
	end
	ball(parent, "Pollen", Vector3.new(0.44, 0.28, 0.44) * s, position + Vector3.new(0, 1.52 * s, 0), C.lemon, false)
end

local function island(parent: Instance, radius: number, color: Color3)
	disc(parent, "WalkableIsland", Vector3.new(0, -1, 0), radius, 2, color)
	disc(parent, "CreamRim", Vector3.new(0, -2.25, 0), radius + 0.2, 0.7, C.cream)
	ball(parent, "FloatingStone", Vector3.new(radius * 1.9, 11, radius * 1.9), Vector3.new(0, -7, 0), C.lavender, false)
	ball(parent, "IslandCloud", Vector3.new(radius * 1.65, 7, radius * 1.65), Vector3.new(0, -11, 0), C.white, false)
end

local function buildCannon(style: string): Model
	local model = makeModel(nil, "Cannon")
	local definition = Catalog.Cannons[style] or Catalog.Cannons.classic
	local color = Color3.fromRGB(table.unpack(definition.rgb))
	disc(model, "Plinth", Vector3.new(0, 0.3, 0), 4, 0.6, C.cream)
	local base = part(model, "Base", Vector3.new(5.3, 1.4, 3.8), CFrame.new(0, 1.35, 0.8), C.ink)
	for _, side in ipairs({ -1, 1 }) do
		part(model, "Wheel", Vector3.new(0.5, 2.5, 2.5), CFrame.new(side * 2.75, 1.4, 0.8), C.coral, Enum.PartType.Cylinder)
	end
	-- Cylinder's native axis is X. Rotate its geometry while Muzzle keeps a
	-- conventional LookVector aimed out of the barrel for client effects.
	local aim = CFrame.new(0, 3.5, -0.8) * CFrame.Angles(math.rad(23), 0, 0)
	part(model, "Barrel", Vector3.new(6.5, 3.4, 3.4), aim * CFrame.Angles(0, math.pi / 2, 0), color, Enum.PartType.Cylinder)
	part(model, "BarrelRim", Vector3.new(0.4, 3.7, 3.7), aim * CFrame.new(0, 0, -3.2) * CFrame.Angles(0, math.pi / 2, 0), C.lemon, Enum.PartType.Cylinder)
	part(model, "Opening", Vector3.new(0.08, 2.9, 2.9), aim * CFrame.new(0, 0, -3.43) * CFrame.Angles(0, math.pi / 2, 0), C.ink, Enum.PartType.Cylinder, false)
	local muzzle = part(model, "Muzzle", Vector3.one * 0.1, aim * CFrame.new(0, 0, -3.6), color, nil, false)
	muzzle.Transparency = 1
	envelope(model, CFrame.new(0, 3.6, -1.9), 1.55, C.cream)
	label(base, "POSTAL CANNON\nSend a smile", 195, 58, 5)
	prompt(base, "Launch", "Plan a voyage")
	model:SetAttribute("Style", style)
	return model
end

local function buildMailbox(style: string): Model
	local model = makeModel(nil, "Mailbox")
	local definition = Catalog.Mailboxes[style] or Catalog.Mailboxes.classic
	local color = Color3.fromRGB(table.unpack(definition.rgb))
	disc(model, "MailboxPlinth", Vector3.new(0, 0.15, 0), 3.4, 0.3, C.cream)
	part(model, "Post", Vector3.new(0.65, 2.9, 0.65), CFrame.new(0, 1.5, 0), C.ink)
	local body = part(model, "Body", Vector3.new(4, 2.3, 2.6), CFrame.new(0, 3.15, 0), color)
	if style == "cottage" then
		for _, sign in ipairs({ -1, 1 }) do
			part(model, "CottageRoof", Vector3.new(2.7, 0.28, 3.1), CFrame.new(sign * 0.85, 4.73, 0) * CFrame.Angles(0, 0, sign * -0.5), C.cream)
		end
		part(model, "Chimney", Vector3.new(0.55, 1.5, 0.65), CFrame.new(1.3, 5.0, 0.4), C.coral)
	elseif style == "cloud" then
		for i = -1, 1 do
			ball(model, "CloudRoof", Vector3.new(2.5, 1.8, 3), Vector3.new(i * 1.1, 4.07 + (i == 0 and 0.4 or 0), 0), C.white)
		end
	else
		ball(model, "RoundRoof", Vector3.new(4, 1.65, 2.6), Vector3.new(0, 4.05, 0), color)
	end
	part(model, "MailSlot", Vector3.new(2.7, 0.27, 0.1), CFrame.new(0, 3.62, -1.34), C.ink, nil, false)
	envelope(model, CFrame.new(0, 2.8, -1.4), 1.2, C.cream)
	part(model, "FlagPole", Vector3.new(0.12, 2.4, 0.12), CFrame.new(2.35, 4, 0), C.ink, nil, false)
	part(model, "Flag", Vector3.new(0.92, 0.67, 0.15), CFrame.new(2.74, 4.83, 0), C.lemon, nil, false)
	label(body, "VISITOR MAILBOX\nFree souvenirs + forwarding", 220, 60, 3.9)
	prompt(body, "Mailbox", "Meet visitors")
	model:SetAttribute("Style", style)
	return model
end

local function buildHatchery(parent: Instance)
	local model = makeModel(parent, "Hatchery")
	disc(model, "NestBase", Vector3.new(0, 0.35, 0), 4, 0.7, C.lavender)
	disc(model, "Nest", Vector3.new(0, 0.8, 0), 3.1, 0.3, C.lemon)
	local egg = ball(model, "Egg", Vector3.new(3.3, 4.2, 3.3), Vector3.new(0, 2.83, 0), C.cream)
	for i = 0, 3 do
		local a = i * math.pi / 2
		ball(model, "EggSpot", Vector3.new(0.65, 0.75, 0.2), Vector3.new(math.sin(a) * 1.18, 2.5 + (i % 2) * 0.95, -1.53 + math.abs(math.sin(a)) * 0.6), i % 2 == 0 and C.teal or C.coral, false)
	end
	label(egg, "HATCHERY\nA little friend awaits", 195, 60, 3.5)
	prompt(egg, "Hatch", "Hatch a monster")
	model:PivotTo(CFrame.new(-12, 0, 0))
end

local function buildDecoration(id: string): Model
	local model = makeModel(nil, "Decoration_" .. id)
	local definition = Catalog.Decorations[id] or Catalog.Decorations.welcome
	local color = Color3.fromRGB(table.unpack(definition.rgb))
	if id == "welcome" then
		part(model, "Pole", Vector3.new(0.22, 4, 0.22), CFrame.new(-1, 2, 0), C.ink, nil, false)
		local flag = part(model, "Pennant", Vector3.new(2.1, 1.5, 0.12), CFrame.new(0, 3.1, 0), color, nil, false)
		label(flag, "WELCOME!", 95, 30, 0)
	elseif id == "planter" then
		disc(model, "PlantPot", Vector3.new(0, 0.6, 0), 1.3, 1.2, color, false)
		for i = -1, 1 do flower(model, Vector3.new(i * 0.6, 1.2, (i % 2) * 0.4), C.white, 0.85) end
	elseif id == "bench" then
		part(model, "Seat", Vector3.new(4.4, 0.38, 1.5), CFrame.new(0, 1.1, 0), color, nil, false)
		part(model, "Back", Vector3.new(4.4, 1.2, 0.3), CFrame.new(0, 1.8, 0.6), color, nil, false)
		for _, sign in ipairs({ -1, 1 }) do part(model, "Leg", Vector3.new(0.4, 1.1, 1.3), CFrame.new(sign * 1.5, 0.55, 0), C.cream, nil, false) end
	elseif id == "lantern" then
		part(model, "Post", Vector3.new(0.24, 3.7, 0.24), CFrame.new(0, 1.85, 0), C.ink, nil, false)
		local glow = part(model, "Lantern", Vector3.new(1.4, 1.45, 1.2), CFrame.new(0, 3.9, 0), color, nil, false)
		glow.Material = Enum.Material.Neon
		part(model, "Top", Vector3.new(1.65, 0.2, 1.45), CFrame.new(0, 4.67, 0), C.ink, nil, false)
		envelope(model, CFrame.new(0, 3.9, -0.65), 0.9, C.cream)
	elseif id == "mushrooms" then
		for i = -1, 1 do
			local y = i == 0 and 1.4 or 0.85
			disc(model, "Stem", Vector3.new(i * 1.25, y / 2, math.abs(i) * 0.4), 0.3, y, C.cream, false)
			ball(model, "Cap", Vector3.new(1.6, 0.65, 1.6), Vector3.new(i * 1.25, y, math.abs(i) * 0.4), color, false)
			ball(model, "Spot", Vector3.new(0.45, 0.13, 0.45), Vector3.new(i * 1.25, y + 0.34, math.abs(i) * 0.4), C.white, false)
		end
	elseif id == "birdbath" then
		disc(model, "Stem", Vector3.new(0, 1, 0), 0.45, 2, C.cream, false)
		disc(model, "Basin", Vector3.new(0, 2.1, 0), 1.6, 0.4, C.cream, false)
		disc(model, "Water", Vector3.new(0, 2.32, 0), 1.35, 0.05, color, false)
		ball(model, "Bird", Vector3.new(0.6, 0.6, 0.8), Vector3.new(1.12, 2.72, 0), C.lemon, false)
	elseif id == "windchime" then
		part(model, "Post", Vector3.new(0.22, 4.8, 0.22), CFrame.new(-1.6, 2.4, 0), C.ink, nil, false)
		part(model, "Arm", Vector3.new(3.4, 0.25, 0.3), CFrame.new(0, 4.7, 0), color, nil, false)
		for i = -1, 1 do
			rod(model, "String", Vector3.new(i, 4.7, 0), Vector3.new(i, 3.1 - math.abs(i) * 0.45, 0), 0.04, C.ink, false)
			envelope(model, CFrame.new(i, 2.85 - math.abs(i) * 0.45, 0), 0.8, i == 0 and C.coral or C.cream)
		end
	elseif id == "arch" then
		for _, sign in ipairs({ -1, 1 }) do
			part(model, "Pillar", Vector3.new(0.55, 5.5, 0.65), CFrame.new(sign * 2, 2.75, 0), color, nil, false)
			ball(model, "RoundTop", Vector3.new(1.0, 1, 1), Vector3.new(sign * 2, 5.5, 0), C.lemon, false)
		end
		part(model, "Lintel", Vector3.new(4.6, 0.55, 0.65), CFrame.new(0, 5.5, 0), color, nil, false)
		envelope(model, CFrame.new(0, 5.5, -0.4), 1.5, C.cream)
	elseif id == "fountain" then
		disc(model, "Saucer", Vector3.new(0, 0.22, 0), 2, 0.4, C.cream, false)
		disc(model, "Cup", Vector3.new(0, 1.1, 0), 1.35, 1.7, C.cream, false)
		disc(model, "Water", Vector3.new(0, 1.98, 0), 1.15, 0.04, color, false)
		part(model, "Jet", Vector3.new(0.2, 1.4, 0.2), CFrame.new(0, 2.5, 0), color, nil, false)
		ball(model, "Drop", Vector3.new(0.5, 0.8, 0.5), Vector3.new(0, 3.2, 0), color, false)
		for _, y in ipairs({ 0.7, 1.5 }) do part(model, "CupHandle", Vector3.new(0.85, 0.22, 0.25), CFrame.new(1.6, y, 0), C.cream, nil, false) end
		part(model, "HandleEnd", Vector3.new(0.22, 1, 0.25), CFrame.new(2, 1.1, 0), C.cream, nil, false)
	elseif id == "telescope" then
		for i = 0, 2 do
			local a = i * math.pi * 2 / 3
			rod(model, "Tripod", Vector3.new(math.sin(a) * 1.35, 0, math.cos(a) * 1.35), Vector3.new(0, 2.45, 0), 0.16, C.ink, false)
		end
		local frame = CFrame.new(0, 2.8, 0) * CFrame.Angles(-0.35, 0, 0)
		part(model, "Tube", Vector3.new(3, 0.8, 0.8), frame * CFrame.Angles(0, math.pi / 2, 0), color, Enum.PartType.Cylinder, false)
		part(model, "Lens", Vector3.new(0.1, 0.85, 0.85), frame * CFrame.new(0, 0, -1.55) * CFrame.Angles(0, math.pi / 2, 0), C.sky, Enum.PartType.Cylinder, false)
	elseif id == "balloons" then
		for i = -1, 1 do
			local top = Vector3.new(i * 0.95, 4.4 + (i == 0 and 0.9 or 0), math.abs(i) * 0.4)
			rod(model, "Ribbon", Vector3.new(0, 0.1, 0), top, 0.035, C.ink, false)
			ball(model, "Balloon", Vector3.new(1.65, 2, 1.65), top, i == 0 and C.lavender or color, false)
		end
	else
		disc(model, "StatuePlinth", Vector3.new(0, 0.3, 0), 1.8, 0.6, C.cream, false)
		local monster = MonsterFactory.create({ name = "Golden courier", body = "puff", palette = "lemon", face = "smile", slots = { hat = "postcap" } }, 0.6)
		monster:PivotTo(CFrame.new(0, 0.6, 0))
		monster.Parent = model
	end
	model:SetAttribute("DecorationId", id)
	return model
end

local flowerPositions = { Vector3.new(-22, 0, 4), Vector3.new(-21, 0, 12), Vector3.new(-15, 0, 21), Vector3.new(-7, 0, 23) }
local letterPositions = { Vector3.new(17, 0, -16), Vector3.new(23, 0, -8), Vector3.new(23, 0, 2), Vector3.new(21, 0, 12), Vector3.new(14, 0, 21), Vector3.new(5, 0, 23) }
local anchorPositions = { Vector3.new(-7, 0, -13), Vector3.new(7, 0, -13), Vector3.new(-19, 0, -4), Vector3.new(19, 0, -4), Vector3.new(-9, 0, 8), Vector3.new(9, 0, 8), Vector3.new(-5, 0, 17), Vector3.new(5, 0, 17) }

local function buildPlot(parent: Instance, index: number, frame: CFrame): any
	local model = makeModel(parent, "Plot" .. tostring(index))
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("Occupied", false)
	island(model, 29, C.grass)
	part(model, "EntryPath", Vector3.new(7, 0.14, 29), CFrame.new(0, 0.04, -13.8), C.cream)
	part(model, "CrossPath", Vector3.new(38, 0.14, 6), CFrame.new(0, 0.05, -2), C.cream)
	for _, x in ipairs({ -20, 20 }) do part(model, "ActivityPath", Vector3.new(4.7, 0.1, 28), CFrame.new(x, 0.03, 7), C.cream) end
	part(model, "BackPath", Vector3.new(29, 0.1, 4.7), CFrame.new(0, 0.03, 22), C.cream)
	buildHatchery(model)
	local mailbox = buildMailbox("classic")
	mailbox:PivotTo(CFrame.new(0, 0, -5))
	mailbox.Parent = model
	local cannon = buildCannon("classic")
	cannon:PivotTo(CFrame.new(12, 0, 0))
	cannon.Parent = model
	local namePost = part(model, "IslandSign", Vector3.new(0.3, 4, 0.3), CFrame.new(-5.5, 2, -23), C.teal)
	local nameLabel = label(namePost, "ISLAND " .. index .. "\nAwaiting a courier", 210, 60, 2.5)
	local display = makeModel(model, "Display")
	for i = 1, 3 do disc(display, "Perch" .. i, Vector3.new((i - 2) * 4.8, 0.36, 12), 2.2, 0.72, C.lavender) end
	local displayPrompt = part(display, "CollectionStand", Vector3.new(1.8, 1.3, 1.3), CFrame.new(0, 0.7, 8), C.teal)
	prompt(displayPrompt, "Collection", "Your monsters")
	label(displayPrompt, "MONSTER GARDEN", 190, 34, 2.3)
	local sorting = makeModel(model, "ParcelSorting")
	local sortingPos = Vector3.new(-19, 0, -15)
	local sortStation = part(sorting, "SortingTable", Vector3.new(7.8, 1.4, 2.6), CFrame.new(sortingPos + Vector3.new(0, 0.75, 0)), C.teal)
	for i, bin in ipairs({ { "CIRCLE", C.coral }, { "TRIANGLE", C.lemon }, { "STAR", C.lavender } }) do
		local binPart = part(sorting, "Bin" .. i, Vector3.new(2, 1.1, 2), CFrame.new(sortingPos + Vector3.new((i - 2) * 2.5, 1.9, 0)), bin[2] :: Color3)
		label(binPart, bin[1] :: string, 76, 28, 0.8)
	end
	prompt(sortStation, "ActivityStart", "Parcel sorting", "sorting")
	label(sortStation, "PARCEL SORTING\nMatch the printed shapes", 195, 58, 4.5)
	local flowers = makeModel(model, "FlowerWatering")
	for i, position in ipairs(flowerPositions) do
		local bed = disc(flowers, "FlowerBed" .. i, position + Vector3.new(0, 0.2, 0), 1.5, 0.4, C.coral, false)
		for j = -1, 1 do flower(flowers, position + Vector3.new(j * 0.55, 0.4, (j % 2) * 0.45), i % 2 == 0 and C.lavender or C.white, 0.7) end
		label(bed, "WATER " .. i, 95, 30, 2.5)
		bed:SetAttribute("MAMActivity", "watering")
		bed:SetAttribute("MAMIndex", i)
		if i == 1 then prompt(bed, "ActivityStart", "Water postal flowers", "watering") end
	end
	local letters = makeModel(model, "FloatingLetters")
	for i, position in ipairs(letterPositions) do
		disc(letters, "LetterMarker" .. i, position + Vector3.new(0, 0.12, 0), 1.25, 0.12, C.lavender, false)
		local letter = envelope(letters, CFrame.new(position + Vector3.new(0, 2.2, 0)), 1.45, C.cream)
		letter.Name = "Letter" .. i
		letter:SetAttribute("MAMActivity", "letters")
		letter:SetAttribute("MAMIndex", i)
		label(letter, "LETTER " .. i, 92, 28, 1)
		if i == 1 then prompt(letter, "ActivityStart", "Collect floating letters", "letters") end
	end
	local anchors = makeModel(model, "DecorationAnchors")
	local anchorMap = {}
	for i, position in ipairs(anchorPositions) do
		local anchor = disc(anchors, "Anchor" .. i, position + Vector3.new(0, 0.1, 0), 1.7, 0.12, C.white, false)
		anchor.Transparency = 0.38
		anchor:SetAttribute("MAMAnchor", tostring(i))
		prompt(anchor, "Decorations", "Decorate anchor " .. i, "", tostring(i))
		anchorMap[tostring(i)] = frame:PointToWorldSpace(position)
	end
	local decorations = makeModel(model, "Decorations")
	local rendered = makeModel(model, "RenderedMonsters")
	model:PivotTo(frame)
	local activity = { sorting = frame:PointToWorldSpace(sortingPos + Vector3.new(0, 2, -3)), watering = {}, letters = {} }
	for i, position in ipairs(flowerPositions) do activity.watering[i] = frame:PointToWorldSpace(position + Vector3.new(0, 2, 0)) end
	for i, position in ipairs(letterPositions) do activity.letters[i] = frame:PointToWorldSpace(position + Vector3.new(0, 2, 0)) end
	return {
		model = model, index = index, frame = frame, center = frame.Position,
		spawn = frame * CFrame.new(0, 4, -21) * CFrame.Angles(0, math.pi, 0),
		ownerId = nil, owner = nil, activity = activity, decorationAnchors = anchorMap,
		nameLabel = nameLabel, cannon = cannon, mailbox = mailbox,
		decorations = decorations, rendered = rendered, signatures = {}, signals = {},
	}
end

local function buildCenter(parent: Instance)
	local center = makeModel(parent, "CentralPostOffice")
	island(center, 34, C.cream)
	disc(center, "Plaza", Vector3.new(0, 0.04, 0), 23, 0.08, C.white)
	part(center, "OfficeBack", Vector3.new(31, 10, 1.1), CFrame.new(0, 5, 20), C.teal)
	for _, sign in ipairs({ -1, 1 }) do
		part(center, "OfficePillar", Vector3.new(1.3, 10, 1.3), CFrame.new(sign * 15, 5, 5), C.coral)
	end
	part(center, "OfficeRoof", Vector3.new(35, 1.1, 20), CFrame.new(0, 10.4, 12), C.lavender)
	part(center, "RoofStripe", Vector3.new(35, 0.4, 1.2), CFrame.new(0, 9.9, 2.2), C.cream)
	local title = part(center, "Title", Vector3.new(18, 3.8, 0.6), CFrame.new(0, 8.5, 3.2), C.cream, nil, false)
	label(title, "MAIL A MONSTER\nLittle monster. Big adventure. Send a smile.", 370, 76, 0)
	envelope(center, CFrame.new(0, 6.5, 19.36), 7, C.cream)
	local stations = {
		{ "Shop", "COSMETIC SHOP\nSpend earned Postage", Vector3.new(-12, 0, 8), C.coral },
		{ "Album", "SOUVENIR JOURNAL\nMemories + discoveries", Vector3.new(-7, 0, 17), C.lavender },
		{ "Voyages", "VOYAGE BOARD\nLittle monsters, big adventures", Vector3.new(12, 0, 8), C.teal },
		{ "Requests", "DAILY REQUESTS\nA new reason to send a smile", Vector3.new(7, 0, 17), C.sky },
	}
	for _, station in ipairs(stations) do
		local pos = station[3] :: Vector3
		local object = part(center, station[1] :: string, Vector3.new(5.2, 2.8, 2.5), CFrame.new(pos + Vector3.new(0, 1.4, 0)), station[4] :: Color3)
		envelope(center, CFrame.new(pos + Vector3.new(0, 1.8, -1.33)), 1.6, C.cream)
		label(object, station[2] :: string, 190, 60, 3.3)
		prompt(object, station[1] :: string, "Open " .. string.lower(station[1] :: string))
	end
	local guide = MonsterFactory.create({ name = "NPC Pippa Post", body = "bean", palette = "coral", face = "wink", personality = "Curious", slots = { hat = "postcap", accessory = "satchel" } }, 1.35)
	guide:PivotTo(CFrame.new(0, 0.3, -6))
	guide.Parent = center
	local guideRoot = guide.PrimaryPart :: BasePart
	label(guideRoot, "NPC PIPPA POST\nYour fictional postal guide", 230, 60, 7.5)
	prompt(guideRoot, "Tutorial", "Meet your postal guide")
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "WelcomeSpawn"
	spawn.Size = Vector3.new(7, 0.15, 7)
	spawn.CFrame = CFrame.new(0, 0.15, -17) * CFrame.Angles(0, math.pi, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.Parent = center
end

local function teleportToPlot(player: Player, plot: any)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return end
	character:PivotTo(plot.spawn)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local protection = Instance.new("ForceField")
	protection.Visible = false
	protection.Parent = character
	Debris:AddItem(protection, 3)
end

local function renderSignature(monster: any): string
	local slots = monster.slots or {}
	return table.concat({ tostring(monster.id), tostring(monster.state), tostring(monster.body), tostring(monster.palette), tostring(monster.face), tostring(slots.hat), tostring(slots.accessory), tostring(slots.patch) }, ":")
end

function World.build(): any
	if activeWorld then activeWorld:destroy() end
	local previous = workspace:FindFirstChild("MailAMonsterWorld")
	if previous then previous:Destroy() end
	local root = makeModel(workspace, "MailAMonsterWorld")
	local assets = ReplicatedStorage:WaitForChild("MailAMonster"):WaitForChild("Assets")
	local oldDecorations = assets:FindFirstChild("Decorations")
	if oldDecorations then oldDecorations:Destroy() end
	local decorationTemplates = Instance.new("Folder")
	decorationTemplates.Name = "Decorations"
	for _, id in ipairs(Catalog.DecorationOrder) do
		local template = buildDecoration(id)
		template.Name = id
		template.Parent = decorationTemplates
	end
	decorationTemplates.Parent = assets
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(168, 164, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(187, 191, 210)
	Lighting.GlobalShadows = true
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "PostalAtmosphere"
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(217, 233, 250)
	atmosphere.Decay = Color3.fromRGB(186, 190, 220)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 0.7
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "PostalBloom"
	bloom.Intensity = 0.14
	bloom.Size = 16
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local sky = Lighting:FindFirstChildOfClass("Sky")
	local ownSky = sky == nil
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "PostalSky"
		sky.Parent = Lighting
	end
	sky.CelestialBodiesShown = true
	sky.StarCount = 0
	buildCenter(root)
	local plots = {}
	for i = 1, 8 do
		local angle = (i - 1) * math.pi / 4
		local center = Vector3.new(math.sin(angle) * 107, 0, math.cos(angle) * 107)
		local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))
		local bridgeCenter = center.Unit * 55.5
		local bridgeCf = CFrame.lookAt(bridgeCenter, Vector3.zero)
		part(root, "Bridge" .. i, Vector3.new(9, 0.5, 49), bridgeCf * CFrame.new(0, -0.15, 0), C.cream)
		for _, side in ipairs({ -1, 1 }) do
			part(root, "BridgeRail", Vector3.new(0.24, 1.2, 49), bridgeCf * CFrame.new(side * 4.55, 0.6, 0), C.teal)
			for post = -2, 2 do part(root, "BridgePost", Vector3.new(0.5, 2.3, 0.5), bridgeCf * CFrame.new(side * 4.55, 1.15, post * 10), C.coral) end
		end
		plots[i] = buildPlot(plotsFolder, i, frame)
	end
	-- A few large cloud clusters frame the archipelago; no per-frame particles.
	for i = 1, 12 do
		local a = i * math.pi / 6
		local center = Vector3.new(math.sin(a) * 153, -22 + (i % 3) * 3, math.cos(a) * 153)
		for j = -1, 1 do ball(root, "DriftingCloud", Vector3.new(24, 10, 19), center + Vector3.new(j * 13, (j % 2) * 2, 0), C.white, false) end
	end
	workspace.FallenPartsDestroyHeight = -80
	local effects: { Instance } = { atmosphere, bloom }
	if ownSky then table.insert(effects, sky) end
	local self: any = { root = root, plots = plots, byUser = {}, alive = true, lighting = effects, decorationTemplates = decorationTemplates }

	function self:getPlot(player: Player): any
		return self.byUser[player.UserId]
	end

	function self:assign(player: Player, profile: any): any
		if self.byUser[player.UserId] then return self.byUser[player.UserId] end
		local assigned = nil
		for _, plot in ipairs(self.plots) do if not plot.ownerId then assigned = plot; break end end
		if not assigned then return nil, "All eight island plots are occupied." end
		assigned.ownerId, assigned.owner = player.UserId, player
		assigned.model:SetAttribute("Occupied", true)
		assigned.cannon:SetAttribute("MAMPlotIndex", assigned.index)
		assigned.mailbox:SetAttribute("MAMPlotIndex", assigned.index)
		local textLabel = assigned.nameLabel:FindFirstChild("Text")
		if textLabel and textLabel:IsA("TextLabel") then textLabel.Text = player.DisplayName .. "'s island\nCourier " .. assigned.index end
		self.byUser[player.UserId] = assigned
		player:SetAttribute("MAMPlotIndex", assigned.index)
		assigned.signals.character = player.CharacterAdded:Connect(function(character)
			task.spawn(function()
				character:WaitForChild("HumanoidRootPart", 10)
				if self.alive and assigned.ownerId == player.UserId then teleportToPlot(player, assigned) end
			end)
		end)
		task.defer(function() if self.alive and assigned.ownerId == player.UserId then teleportToPlot(player, assigned) end end)
		self:refresh(player, profile, {}, {})
		return assigned
	end

	function self:release(player: Player)
		local plot = self.byUser[player.UserId]
		if not plot then return end
		for _, connection in pairs(plot.signals) do connection:Disconnect() end
		plot.signals = {}
		plot.ownerId, plot.owner = nil, nil
		plot.model:SetAttribute("Occupied", false)
		local textLabel = plot.nameLabel:FindFirstChild("Text")
		if textLabel and textLabel:IsA("TextLabel") then textLabel.Text = "ISLAND " .. plot.index .. "\nAwaiting a courier" end
		for _, folder in ipairs({ plot.rendered, plot.decorations }) do
			for _, child in ipairs(folder:GetChildren()) do if child.Name ~= "Origin" then child:Destroy() end end
		end
		plot.signatures = {}
		self.byUser[player.UserId] = nil
		player:SetAttribute("MAMPlotIndex", nil)
	end

	function self:getActivityPosition(player: Player, kind: string, index: number): Vector3?
		local plot = self:getPlot(player)
		if not plot then return nil end
		if kind == "sorting" then return plot.activity.sorting end
		if kind == "watering" or kind == "letters" then return plot.activity[kind][index] end
		return nil
	end

	function self:refresh(player: Player, profile: any, monsters: { any }, visitors: { any })
		local plot = self:getPlot(player)
		if not plot then return end
		local cannonStyle = Catalog.Cannons[profile.cannon] and profile.cannon or "classic"
		local mailboxStyle = Catalog.Mailboxes[profile.mailbox] and profile.mailbox or "classic"
		for _, info in ipairs({ { "cannon", cannonStyle }, { "mailbox", mailboxStyle } }) do
			local kind, style = info[1], info[2]
			if plot[kind]:GetAttribute("Style") ~= style then
				plot[kind]:Destroy()
				local replacement = kind == "cannon" and buildCannon(style) or buildMailbox(style)
				replacement:SetAttribute("MAMPlotIndex", plot.index)
				replacement:PivotTo(plot.frame * CFrame.new(kind == "cannon" and 12 or 0, 0, kind == "mailbox" and -5 or 0))
				replacement.Parent = plot.model
				plot[kind] = replacement
			end
		end
		for i = 1, 8 do
			local key = tostring(i)
			local id = (profile.placements or {})[key]
			if not Catalog.Decorations[id] then id = nil end
			local signatureKey = "anchor" .. key
			if plot.signatures[signatureKey] ~= id then
				local existing = plot.decorations:FindFirstChild(signatureKey)
				if existing then existing:Destroy() end
				if id then
					local model = decorationTemplates[id]:Clone()
					model.Name = signatureKey
					model:PivotTo(plot.frame * CFrame.new(anchorPositions[i]))
					model.Parent = plot.decorations
				end
				plot.signatures[signatureKey] = id
			end
		end
		local displays, displayPerches, used, selected = {}, {}, {}, {}
		for _, id in pairs(profile.displaySlots or {}) do selected[id] = true end
		for perch = 1, 3 do
			local wanted = (profile.displaySlots or {})[tostring(perch)]
			local candidate = nil
			for _, monster in ipairs(monsters or {}) do
				if monster.state == "HOME" and monster.id == wanted and not used[monster.id] then candidate = monster; break end
			end
			if not candidate then
				for _, monster in ipairs(monsters or {}) do
					if monster.state == "HOME" and not used[monster.id] and not selected[monster.id] then candidate = monster; break end
				end
			end
			if candidate then
				table.insert(displays, candidate)
				displayPerches[candidate.id] = perch
				used[candidate.id] = true
			end
		end
		local expected = {}
		for groupIndex, group in ipairs({ displays, visitors or {} }) do
			for i, monster in ipairs(group) do
				if i > 3 then break end
				local renderIndex = if groupIndex == 1 then displayPerches[monster.id] else i
				local key = (groupIndex == 1 and "Home" or "Visitor") .. tostring(renderIndex)
				expected[key] = true
				local signature = renderSignature(monster)
				if plot.signatures[key] ~= signature then
					local old = plot.rendered:FindFirstChild(key)
					if old then old:Destroy() end
					local model = MonsterFactory.create(monster, groupIndex == 1 and 0.82 or 0.55)
					model.Name = key
					local position = groupIndex == 1 and Vector3.new((renderIndex - 2) * 4.8, 0.75, 12) or Vector3.new((i - 2) * 2.2, 0.15, -10)
					model:PivotTo(plot.frame * CFrame.new(position))
					model.Parent = plot.rendered
					label(model.PrimaryPart :: BasePart, tostring(monster.name or "Visitor") .. (groupIndex == 2 and "\nVISITING COURIER CARE" or ""), 140, groupIndex == 2 and 48 or 30, groupIndex == 1 and 4.8 or 3.7)
					prompt(model.PrimaryPart :: BasePart, groupIndex == 1 and "Collection" or "Mailbox", groupIndex == 1 and "Meet monster" or "Open passport", "", tostring(monster.id))
					plot.signatures[key] = signature
				end
			end
		end
		for _, child in ipairs(plot.rendered:GetChildren()) do
			if child.Name ~= "Origin" and not expected[child.Name] then plot.signatures[child.Name] = nil; child:Destroy() end
		end
	end

	function self:destroy()
		if not self.alive then return end
		self.alive = false
		for _, player in ipairs(Players:GetPlayers()) do self:release(player) end
		for _, effect in ipairs(self.lighting) do effect:Destroy() end
		self.decorationTemplates:Destroy()
		self.root:Destroy()
		if activeWorld == self then activeWorld = nil end
	end

	-- One bounded low-frequency task recovers falls. It creates no connections
	-- per render frame and stops when this world is destroyed.
	task.spawn(function()
		while self.alive do
			task.wait(1)
			for _, plot in pairs(self.byUser) do
				local player = plot.owner
				local character = player and player.Character
				local humanoidRoot = character and character:FindFirstChild("HumanoidRootPart")
				if humanoidRoot and humanoidRoot:IsA("BasePart") and (humanoidRoot.Position.Y < -18 or humanoidRoot.Position.Magnitude > 650) then teleportToPlot(player, plot) end
			end
		end
	end)
	activeWorld = self
	return self
end

return World
