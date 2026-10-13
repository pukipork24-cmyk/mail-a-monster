-- Regression cases for replayed eggs, recovery partitions, late UTC callbacks,
-- and durable display choices. Actual Roblox APIs/geometry are tested in Studio.
local Config = require("../src/shared/Config")
local Catalog = require("../src/shared/Catalog")
local Storage = require("../src/server/Storage")
local VoyageService = require("../src/server/VoyageService")
local GameplayService = require("../src/server/GameplayService")
local checks = 0
local function check(condition, message) checks += 1; assert(condition, message) end
local function fixture(partitions)
	local now, sequence = 864000, 0
	local clock = { now = function() return now end }
	local function guid() sequence += 1; return "hardening-" .. sequence end
	local storage = Storage.createSimulation({ partitions = partitions or 1 })
	local options = { config = Config, catalog = Catalog, newId = guid, random = function(low, _) return low end }
	local voyages = VoyageService.new(storage, clock, options)
	voyages:loadPlayer(1)
	local world = { getPlot = function() return { ownerId = 1 } end, getActivityPosition = function(_, _, _, index) return index end }
	local gameplay = GameplayService.new(voyages, world, { config = Config, catalog = Catalog, idFactory = guid, distance = function() return 0 end })
	return storage, voyages, gameplay, clock, options, function(value) now = value end
end

do
	local storage, voyages = fixture()
	storage.profiles["1"] = { schema = 0, id = "1", currency = 17, owned = { "legacy-monster" },
		settings = { reducedMotion = true }, stats = { forwards = 3 }, caps = { carrier = { ["0"] = 1 } },
		requests = { day = 10, counters = { sorting = 1 } } }
	storage.monsters["legacy-monster"] = { schema = 0, id = "legacy-monster", ownerId = "1", name = "Gerald", state = "HOME",
		books = { { id = "remembered-voyage", events = { { kind = "NPC", label = "A preserved memory" } } } }, lifetimeHops = 7 }
	local loaded = voyages:loadPlayer(1)
	check(loaded.profile.currency == 17 and loaded.profile.settings.reducedMotion, "Migration retains currency and settings")
	check(loaded.profile.hatchSeq == 1 and loaded.profile.tutorial.hatched, "Existing collections cannot replay a free first hatch")
	check(loaded.monsters[1].lifetimeHops == 7 and loaded.monsters[1].books[1].events[1].label == "A preserved memory", "Monster migration preserves lifetime and archived events")
	check(storage:getMonster("legacy-monster").schema == Config.SchemaVersion, "Monster migration is durably saved")
	storage:updateProfile("1", function(p) p.schema = Config.SchemaVersion + 1; return p end)
	local ok = pcall(function() voyages:loadPlayer(1) end)
	check(not ok and storage:getProfile("1").currency == 17, "Newer schemas pause without default-data overwrite")
end

do
	local storage, voyages = fixture()
	storage:updateProfile("1", function(p) p.currency = 400; p.tutorial.skipped = true; return p end)
	local intent = { name = "Gerald", sequence = 0 }
	local first = voyages:handle(1, "Hatch", intent)
	check(first.ok, "First egg intent succeeds")
	check(not voyages:handle(1, "Hatch", intent).ok, "Replayed egg sequence is rejected")
	check(#storage:getProfile("1").owned == 1 and storage:getProfile("1").currency == 400, "Replay creates no second monster or charge")
	check(voyages:handle(1, "Hatch", { name = "Pickle", sequence = 1 }).ok, "A fresh sequence buys a second egg")
	check(storage:getProfile("1").currency == 320, "The new egg charges exactly 80")
end

do
	local storage, voyages, _, _, options = fixture()
	storage:updateProfile("1", function(p) p.currency = 400; p.tutorial.skipped = true; return p end)
	local competitor = VoyageService.new(storage, voyages.clock, options)
	local original, raced = storage.updateProfile, false
	storage.updateProfile = function(self, id, transform)
		if not raced then
			raced = true
			check(competitor:handle(1, "Hatch", { name = "Miso", sequence = 0 }).ok, "Competing egg commits first")
		end
		return original(self, id, transform)
	end
	check(not voyages:handle(1, "Hatch", { name = "Gerald", sequence = 0 }).ok, "Losing hatch sequence cannot commit")
	storage.updateProfile = original
	check(#storage:getProfile("1").owned == 1 and storage:getProfile("1").currency == 400, "Concurrent hatch creates one free first monster")
end

do
	local storage, voyages = fixture()
	local create, failed = storage.createMonster, false
	storage.createMonster = function(self, record)
		if not failed then failed = true; error("Interrupted canonical egg creation") end
		return create(self, record)
	end
	check(not voyages:handle(1, "Hatch", { name = "Gerald", sequence = 0 }).ok, "Interrupted hatch reports recoverable error")
	local id = storage:getProfile("1").owned[1]
	check(id and not storage:getMonster(id), "Pending hatch is durable before record creation")
	voyages:tick()
	check(storage:getMonster(id) ~= nil and not next(storage:getProfile("1").pendingHatches), "Online worker repairs pending hatch without rejoin or second purchase")
	check(#voyages:snapshot(1).visitors == 1 and storage:getProfile("1").currency == 40, "Tutorial inbox and original free egg recover")
end

do
	local storage, voyages, _, clock, options, setNow = fixture(16)
	local ids = {}
	storage:updateProfile("1", function(p) p.tutorial.skipped = true; return p end)
	-- Put overdue active records across every durable discovery prefix.
	for partition = 1, 16 do
		local suffix = 0
		local id
		repeat suffix += 1; id = "partition-" .. partition .. "-" .. suffix until Storage.partitionFor(id, 16) == partition
		local monster = voyages:_newMonster(id, "1", "Gerald", partition)
		monster.state, monster.voyageNumber, monster.launchOperation, monster.launchVersion = "QUEUED", 1, "launch:" .. id, 2
		monster.voyage = { id = id .. ":1", plan = "ShortHop", practice = false, startedAt = clock.now() - 22000, deadline = clock.now() - 1,
			hopTarget = 3, deposit = 20, humanHops = 0, rewardHops = 0, visited = {}, events = {}, slotsBefore = {}, npcCount = 0, lastNpcAt = clock.now(), objective = "hat" }
		storage:createMonster(monster)
		table.insert(ids, id)
	end
	voyages:playerLeaving(1)
	storage.hints = {}; storage.leases = {}
	local restarted = VoyageService.new(storage, clock, options)
	for pass = 1, 16 do setNow(864000 + pass * (Config.RecoveryInterval + 1)); restarted:tick() end
	for partition, id in ipairs(ids) do
		check(storage:getMonster(id).state == "HOME", "Partition " .. partition .. " recovers without hints")
		check(storage:getCheckpoint("enumerator:" .. partition) ~= nil, "Partition checkpoint persists")
	end
	local before = storage:getProfile("1").currency
	for pass = 17, 32 do setNow(864000 + pass * (Config.RecoveryInterval + 1)); restarted:tick() end
	check(storage:getProfile("1").currency == before, "Second full recovery traversal cannot repay returns")
end

do
	local storage, voyages = fixture()
	storage:updateProfile("1", function(p) p.tutorial.skipped = true; return p end)
	voyages:loadPlayer(2)
	local egg = voyages:handle(1, "Hatch", { name = "Gerald", sequence = 0 })
	check(egg.ok, "Interrupted assignment fixture hatches")
	local id = egg.effect.monsterId
	check(voyages:handle(1, "Launch", { monsterId = id, plan = "ShortHop", version = storage:getMonster(id).version }).ok, "Fixture reaches human custody")
	local monster = storage:getMonster(id)
	check(monster.state == "HELD" and monster.voyage.holderId == "2", "Courier has canonical custody")
	-- Models reservation cleanup racing a very delayed canonical claim.
	storage:updateProfile("2", function(p) p.inbox[id] = nil; return p end)
	check(#voyages:snapshot(2).visitors == 0, "A lost reference is never an actionable phantom")
	voyages:_process(id)
	local restored = voyages:snapshot(2).visitors[1]
	check(restored and restored.id == id, "Canonical held records reconstruct a missing inbox reference")
	check(voyages:handle(2, "Forward", { monsterId = id, voyageId = restored.voyage.id, version = restored.version, souvenirId = "sunhat" }).ok, "Repaired visitor remains forwardable")
	check(storage:getMonster(id).lifetimeHops == 1 and storage:getProfile("2").currency == 45, "Reference repair pays no extra hop or money")
end

do
	local storage, voyages, _, clock, _, setNow = fixture()
	storage:updateProfile("1", function(p) p.tutorial.skipped = true; return p end)
	local egg = voyages:handle(1, "Hatch", { name = "Gerald", sequence = 0 })
	check(egg.ok, "Voyage replay fixture hatches")
	local id = egg.effect.monsterId
	local oldLaunch = { monsterId = id, plan = "ShortHop", version = storage:getMonster(id).version }
	check(voyages:handle(1, "Launch", oldLaunch).ok, "Original launch succeeds")
	local oldVoyageId = storage:getMonster(id).voyage.id
	setNow(clock.now() + Config.Plans.ShortHop.seconds + 1); voyages:tick()
	check(storage:getMonster(id).state == "HOME", "First voyage finishes before replay")
	local balance = storage:getProfile("1").currency
	check(not voyages:handle(1, "Launch", oldLaunch).ok, "Old launch version cannot start another paid trip")
	check(storage:getProfile("1").currency == balance and not storage:getMonster(id).voyage, "Old launch replay charges nothing")
	check(voyages:handle(1, "Launch", { monsterId = id, plan = "ShortHop", version = storage:getMonster(id).version }).ok, "A fresh owner intent starts the next trip")
	local nextVoyageId = storage:getMonster(id).voyage.id
	setNow(clock.now() + Config.EarlyReturnSeconds)
	check(not voyages:handle(1, "Recall", { monsterId = id, voyageId = oldVoyageId }).ok, "Old recall cannot revoke a later voyage")
	check(storage:getMonster(id).voyage.id == nextVoyageId and storage:getProfile("1").currency == balance - 20, "New voyage and deposit survive stale recall")
	check(voyages:handle(1, "Recall", { monsterId = id, voyageId = nextVoyageId }).ok, "Current voyage remains safely recallable")
end

do
	local storage, voyages, gameplay, _, _, setNow = fixture()
	local hatch = voyages:handle(1, "Hatch", { name = "Gerald", sequence = 0 })
	check(hatch.ok, "Display fixture hatches")
	local id = hatch.effect.monsterId
	check(gameplay:handle({ UserId = 1 }, "Display", { monsterId = id, perch = 3 }).ok, "Owner chooses perch three")
	check(storage:getProfile("1").displaySlots["3"] == id, "Perch choice persists")
	check(gameplay:handle({ UserId = 1 }, "Display", { monsterId = id, perch = 1 }).ok, "Display can move to another perch")
	check(storage:getProfile("1").displaySlots["3"] == nil, "One monster does not occupy two perches")
	check(not gameplay:handle({ UserId = 2 }, "Display", { monsterId = id, perch = 1 }).ok, "Visitor cannot edit owner's monster display")
	check(not gameplay:handle({ UserId = 1 }, "Display", { monsterId = id, perch = 4 }).ok, "Only three display perches exist")

	local day = Config.day(voyages.clock.now())
	local request = Config.dailyRequests(voyages.clock.now())[1]
	storage:updateProfile("1", function(p) p.requests = { day = day, counters = { [request.stat] = request.target }, claimed = {} }; return p end)
	local original, advanced = storage.updateProfile, false
	storage.updateProfile = function(self, userId, transform)
		if not advanced then
			advanced = true
			setNow((day + 1) * 86400)
			original(self, userId, function(p) p.requests = { day = day + 1, counters = { watering = 1 }, claimed = {} }; return p end)
		end
		return original(self, userId, transform)
	end
	check(not gameplay:handle({ UserId = 1 }, "ClaimRequest", { requestId = request.id }).ok, "Delayed previous-day claim loses to new-day board")
	storage.updateProfile = original
	check(storage:getProfile("1").requests.day == day + 1 and storage:getProfile("1").requests.counters.watering == 1, "Old callback cannot reopen daily claims or erase new progress")
	check(storage:getProfile("1").currency == 40, "Stale daily claim grants no money")
end

print("PASS: " .. checks .. " hatch replay, sharded recovery, UTC fencing, and display regression checks")
