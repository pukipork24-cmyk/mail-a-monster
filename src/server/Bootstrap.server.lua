--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local LocalizationService = game:GetService("LocalizationService")
local HttpService = game:GetService("HttpService")

local root = ReplicatedStorage:WaitForChild("MailAMonster")
local shared = root:WaitForChild("Shared")
local Config = require(shared.Config)
local Catalog = require(shared.Catalog)
local Validation = require(shared.Validation)
local ServerConfig = require(script.Parent.ServerConfig)
local Storage = require(script.Parent.Storage)
local VoyageService = require(script.Parent.VoyageService)
local GameplayService = require(script.Parent.GameplayService)
local World = require(script.Parent.World)
local RateLimiter = require(script.Parent.RateLimiter)
local request = root.Remotes.Request :: RemoteFunction
local update = root.Remotes.Update :: RemoteEvent

local simulation = RunService:IsStudio() and ServerConfig.Mode == "Simulation"
local clockOffset = 0
local clock = { now = function() return os.time() + clockOffset end }
local storage = if simulation then Storage.createSimulation() else Storage.createLive({ namespace = ServerConfig.LiveNamespace })
local countries: { [string]: string } = {}
local voyages = VoyageService.new(storage, clock, {
	config = Config,
	catalog = Catalog,
	jobId = if game.JobId ~= "" then game.JobId else "Studio",
	workerId = HttpService:GenerateGUID(false),
	countryFor = function(id) return countries[tostring(id)] end,
})
local world = World.build()
local gameplay = GameplayService.new(voyages, world, { config = Config, catalog = Catalog })
local limiter = RateLimiter.new(Config.ActionBurst, Config.ActionsPerSecond)
local loaded: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}
local snapshotCosts: { [Player]: number } = {}
local shuttingDown = false
local workerRunning = false
local coreActions = { Snapshot = true, Hatch = true, Launch = true, Forward = true, Recall = true, ReleaseVisitor = true, ClaimHomecoming = true, SkipTutorial = true }

local function enrich(player: Player, snapshot)
	snapshot.activity = gameplay:getActivity(player.UserId)
	snapshot.profile.rewardLimits = snapshot.profile.daily
	snapshot.profile.daily = gameplay:getDaily(snapshot.profile)
	snapshot.profile.level = Config.level(snapshot.profile.xp or 0)
	snapshotCosts[player] = 1 + #(snapshot.profile.owned or snapshot.monsters) + Config.IncomingCapacity
	return snapshot
end

local function refreshWorld(player: Player, snapshot)
	local ok = pcall(function() world:refresh(player, snapshot.profile, snapshot.monsters, snapshot.visitors) end)
	if not ok then warn("MAIL A MONSTER: island visual refresh needs retry.") end
end

local function load(player: Player)
	if loaded[player] then return end
	local snapshot = enrich(player, voyages:loadPlayer(player.UserId))
	if not player.Parent then voyages:playerLeaving(player.UserId); return end
	local plot = world:assign(player, snapshot.profile)
	if not plot then
		voyages:playerLeaving(player.UserId)
		player:Kick("All eight postal islands are occupied. Please join another server.")
		return
	end
	loaded[player] = true
	refreshWorld(player, snapshot)
	update:FireClient(player, snapshot)
	if snapshot.profile.settings.shareCountry then
		task.spawn(function()
			local ok, country = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(player) end)
			if ok and player.Parent and type(country) == "string" and #country == 2 then countries[tostring(player.UserId)] = country end
		end)
	end
end

local function safeLoad(player: Player)
	if busy[player] then return end
	busy[player] = true
	local ok = pcall(load, player)
	busy[player] = nil
	if not ok and player.Parent then
		warn("MAIL A MONSTER: player load paused; next Snapshot request retries. No default save was substituted.")
	end
end

request.OnServerInvoke = function(player: Player, action, payload)
	if shuttingDown then return { ok = false, error = "This post office is closing. Please rejoin to continue." } end
	if not limiter:allow(player.UserId, os.clock()) then return { ok = false, error = "A little too fast. Please wait a moment and retry." } end
	if payload == nil then payload = {} end
	local valid, reason = Validation.validate(action, payload)
	if not valid then return { ok = false, error = reason or "That request could not be read." } end
	if busy[player] then return { ok = false, error = "Your last action is still being saved. Please wait and retry." } end
	busy[player] = true
	local ok, result = pcall(function()
		if not loaded[player] then load(player) end
		if not loaded[player] then return { ok = false, error = "Your island is still loading. Please retry." } end
		local response
		if coreActions[action] then
			response = voyages:handle(player.UserId, action, payload)
		else
			response = gameplay:handle(player, action, payload)
		end
		if response.ok then
			response.data = enrich(player, response.data or voyages:snapshot(player.UserId))
			refreshWorld(player, response.data)
			if action == "Settings" and payload.key == "shareCountry" then
				countries[tostring(player.UserId)] = nil
				if payload.value then
					task.spawn(function()
						local fetched, country = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(player) end)
						if fetched and player.Parent and type(country) == "string" and #country == 2 then
							countries[tostring(player.UserId)] = country
						end
					end)
				end
			end
		end
		return response
	end)
	busy[player] = nil
	if not ok then
		warn("MAIL A MONSTER: action paused (" .. tostring(action) .. "). Durable state will reconcile on retry.")
		return { ok = false, error = "The post office could not finish saving. Please retry; your monster and saved progress are protected." }
	end
	return result
end

Players.PlayerAdded:Connect(function(player) task.spawn(safeLoad, player) end)
Players.PlayerRemoving:Connect(function(player)
	loaded[player] = nil
	busy[player] = nil
	snapshotCosts[player] = nil
	countries[tostring(player.UserId)] = nil
	limiter:remove(player.UserId)
	gameplay:playerLeaving(player.UserId)
	world:release(player)
	local ok = pcall(function() voyages:playerLeaving(player.UserId) end)
	if not ok then warn("MAIL A MONSTER: presence cleanup deferred to its expiration.") end
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(safeLoad, player) end

local function runWorker()
	if workerRunning or shuttingDown then return end
	workerRunning = true
	local ok = pcall(function() voyages:tick() end)
	workerRunning = false
	if not ok then warn("MAIL A MONSTER: recovery worker paused; it will retry with durable work intact.") end
end

task.spawn(function()
	while not shuttingDown do
		runWorker()
		task.wait(Config.WorkerInterval + math.random())
	end
end)

task.spawn(function()
	while not shuttingDown do
		task.wait(ServerConfig.SnapshotInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			if loaded[player] and not busy[player] and storage:hasBudget((snapshotCosts[player] or 16) + 20, 8) then
				local ok, snapshot = pcall(function() return enrich(player, voyages:snapshot(player.UserId)) end)
				if ok and player.Parent then
					refreshWorld(player, snapshot)
					update:FireClient(player, snapshot)
				end
			end
			task.wait(0.2)
		end
	end
end)

-- Accessible only from Studio's SERVER command bar. No replicated debug remote.
if simulation and ServerConfig.EnableStudioDeveloperCommands then
	local debugCommand = Instance.new("BindableFunction")
	debugCommand.Name = "MailAMonsterDevelopment"
	debugCommand.Parent = ServerStorage
	debugCommand.OnInvoke = function(command, userId, args)
		assert(RunService:IsStudio() and storage.simulation, "Simulation tools are Studio-only")
		args = args or {}
		local id = tostring(userId)
		if command == "Inspect" then
			return voyages:snapshot(id)
		elseif command == "AdvanceClock" then
			assert(type(args.seconds) == "number" and args.seconds == args.seconds and args.seconds >= 0 and args.seconds <= 7 * 86400, "seconds must be 0..604800")
			clockOffset += args.seconds
			voyages:tick()
		elseif command == "CreateMonster" then
			storage:updateProfile(id, function(p) assert(p, "Join first"); p.currency += Config.EggCost; return p end)
			return voyages:handle(id, "Hatch", { name = args.name or "Gerald", sequence = storage:getProfile(id).hatchSeq })
		elseif command == "Enqueue" then
			return voyages:handle(id, "Launch", { monsterId = args.monsterId, plan = args.plan or "ShortHop", version = storage:getMonster(args.monsterId).version })
		elseif command == "ExpireHolder" then
			storage:updateMonster(args.monsterId, function(m)
				assert(m and m.state == "HELD", "Select a held monster")
				m.voyage.holdUntil = clock.now() - 1
				m.version += 1
				return m
			end)
			voyages:tick()
		elseif command == "ServiceError" then
			local allowed = { getProfile = true, updateProfile = true, getMonster = true, updateMonster = true, enqueue = true, listMonsterIds = true, presence = true }
			assert(allowed[args.operation], "Choose a supported storage operation")
			storage:failNext(args.operation, math.clamp(args.count or 1, 1, 5))
		elseif command == "RemoveHint" then
			storage:removeHint(args.monsterId)
		elseif command == "RetryPayout" then
			voyages:_drain(args.monsterId)
		elseif command == "ResetSimulation" then
			storage:reset()
			clockOffset = 0
			for _, player in ipairs(Players:GetPlayers()) do
				gameplay:playerLeaving(player.UserId)
				voyages:loadPlayer(player.UserId)
			end
		else
			error("Commands: Inspect, CreateMonster, Enqueue, AdvanceClock, ExpireHolder, ServiceError, RemoveHint, RetryPayout, ResetSimulation")
		end
		return "Simulation command complete. Refresh your game screen."
	end
end

game:BindToClose(function()
	shuttingDown = true
	-- Every mutation is already durable; there is no stale profile cache to save.
	for _, player in ipairs(Players:GetPlayers()) do pcall(function() voyages:playerLeaving(player.UserId) end) end
	world:destroy()
end)

print("MAIL A MONSTER | " .. (if simulation then "Studio simulation — progress is not saved" else "Live services | namespace=" .. ServerConfig.LiveNamespace .. " | JobId=" .. game.JobId))
