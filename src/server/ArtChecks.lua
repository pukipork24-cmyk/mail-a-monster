--!strict
-- Optional Studio engine checks. Never auto-runs and never touches save data.
-- During Studio Play, SERVER Command Bar:
-- require(game.ServerScriptService.MailAMonster.ArtChecks).run()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MailAMonster"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Factory = require(Shared:WaitForChild("MonsterFactory"))

local ArtChecks = {}

local function countParts(model: Model): number
	local count = 0
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			assert(item.Anchored, "Unanchored monster geometry: " .. item.Name)
			assert(not item.CanCollide, "Monster geometry blocks walking: " .. item.Name)
			assert(item.Size.X > 0 and item.Size.Y > 0 and item.Size.Z > 0, "Invalid geometry size")
			count += 1
		end
	end
	assert(count <= 100, "Monster exceeded 100-part art budget")
	return count
end

function ArtChecks.run(): any
	assert(RunService:IsStudio(), "Art checks may run only in Studio")
	local samples = 0
	local maxParts = 0
	local fixture = Instance.new("Folder")
	fixture.Name = "TemporaryArtChecks"
	fixture.Parent = game:GetService("ServerStorage")
	local ok, failure = pcall(function()
		-- All 4 families x 12 souvenirs, tested at three practical scales.
		for _, body in ipairs(Catalog.Bodies) do
			for _, souvenirId in ipairs(Catalog.SouvenirOrder) do
				for _, scale in ipairs({ 0.45, 1, 1.7 }) do
					local souvenir = Catalog.Souvenirs[souvenirId]
					local model = Factory.create({ body = body, face = "smile", palette = "cream", slots = { [souvenir.slot] = souvenirId } }, scale)
					model.Parent = fixture
					assert(model.PrimaryPart and model:GetPivot().Position.Magnitude < 0.001, "Monster pivot moved from origin")
					local attachment = model.Souvenirs:FindFirstChild(souvenir.slot)
					assert(attachment and #attachment:GetChildren() > 0, "Missing attachment: " .. souvenirId .. " on " .. body)
					maxParts = math.max(maxParts, countParts(model))
					model:PivotTo(CFrame.new(20, 4, -3) * CFrame.Angles(0, 1.2, 0))
					Factory.applySouvenirs(model, { hat = "crown", accessory = "wings", patch = "starpatch" })
					assert(#model.Souvenirs:GetChildren() == 3, "Visual slots are not bounded at three")
					Factory.applySouvenirs(model, { hat = "postcap" })
					assert(#model.Souvenirs:GetChildren() == 1, "Replacing cosmetics leaked old slots")
					local _, size = model:GetBoundingBox()
					assert(size.Magnitude < 15 * scale, "Attachment escaped the monster after a scaled re-equip")
					model:Destroy()
					samples += 1
				end
			end
		end
		for _, body in ipairs(Catalog.Bodies) do
			for _, palette in ipairs(Catalog.PaletteOrder) do
				for _, face in ipairs(Catalog.Faces) do
					local model = Factory.create({ body = body, palette = palette, face = face }, 1)
					model.Parent = fixture
					maxParts = math.max(maxParts, countParts(model))
					assert(model:GetAttribute("BodyFamily") == body, "Body family was changed")
					model:Destroy()
					samples += 1
				end
			end
		end
	end)
	fixture:Destroy()
	assert(ok, tostring(failure))
	local world = workspace:FindFirstChild("MailAMonsterWorld")
	assert(world, "Start a Play session and wait for the world before running ArtChecks")
	local plots = world:FindFirstChild("Plots")
	assert(plots and #plots:GetChildren() == 8, "Expected eight personal islands")
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { world }
	rayParams.RespectCanCollide = true
	for _, plot in ipairs(plots:GetChildren()) do
		assert(plot:FindFirstChild("Hatchery") and plot:FindFirstChild("Mailbox") and plot:FindFirstChild("Cannon"), "An island is missing core machinery")
		local anchors = plot:FindFirstChild("DecorationAnchors")
		assert(anchors and #anchors:GetChildren() == 9, "Expected eight decoration anchors plus the model origin")
		local homeCount, visitorCount = 0, 0
		for _, child in ipairs(plot.RenderedMonsters:GetChildren()) do
			if string.match(child.Name, "^Home%d") then homeCount += 1 end
			if string.match(child.Name, "^Visitor%d") then visitorCount += 1 end
		end
		assert(homeCount <= 3 and visitorCount <= 3, "Unbounded island monster count")
		for _, descendant in ipairs(plot:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant:GetAttribute("MAMActivity") then
				local hit = workspace:Raycast(descendant.Position + Vector3.new(0, 8, 0), Vector3.new(0, -18, 0), rayParams)
				assert(hit and hit.Position.Y >= -0.1, "Activity waypoint has no reachable island floor")
			end
		end
	end
	print("MAIL A MONSTER ArtChecks PASS: " .. samples .. " monster configurations; maximum " .. maxParts .. " parts; eight plots; 48 souvenir/body pairs at three scales. Visual/mobile/performance playtests remain separate.")
	return { configurations = samples, maxMonsterParts = maxParts, islands = 8 }
end

return ArtChecks
