-- Full service-level guided loop through the same network intent validator.
-- No Roblox renderer, physics, or real-service API is emulated by this test.
local Config = require("../src/shared/Config")
local Catalog = require("../src/shared/Catalog")
local Validation = require("../src/shared/Validation")
local Storage = require("../src/server/Storage")
local VoyageService = require("../src/server/VoyageService")
local GameplayService = require("../src/server/GameplayService")

local checks = 0
local function check(value, message)
	checks += 1
	assert(value, message)
end

local now = 20000 * 86400
local sequence = 0
local function nextId()
	sequence += 1
	return "integration-" .. sequence
end
local clock = { now = function() return now end }
local storage = Storage.createSimulation()
local voyages = VoyageService.new(storage, clock, {
	config = Config, catalog = Catalog, newId = nextId,
	random = function(low, _) return low end,
})
local world = {
	getActivityPosition = function(_, _, _, index) return index end,
	getPlot = function(_, player) return { ownerId = player.UserId } end,
}
local gameplay = GameplayService.new(voyages, world, {
	config = Config, catalog = Catalog,
	distance = function() return 0 end,
	idFactory = nextId,
})
local player = { UserId = 1 }
local core = { Snapshot = true, Hatch = true, Launch = true, Forward = true, Recall = true, ReleaseVisitor = true, ClaimHomecoming = true, SkipTutorial = true }

local function invoke(action, payload)
	local valid, reason = Validation.validate(action, payload)
	check(valid, action .. " violates client/server contract: " .. tostring(reason))
	local response = if core[action] then voyages:handle(player.UserId, action, payload) else gameplay:handle(player, action, payload)
	check(response.ok, action .. " failed: " .. tostring(response.error))
	return response.data or voyages:snapshot(player.UserId)
end

local initial = voyages:loadPlayer(player.UserId)
check(initial.profile.currency == 40 and #initial.monsters == 0, "New player receives 40 Postage and a free egg")
local hatched = invoke("Hatch", { name = "Gerald", sequence = 0 })
check(#hatched.monsters == 1 and hatched.profile.currency == 40, "First hatch is free")
check(#hatched.visitors == 1, "Tutorial visitor arrives")
local monsterId = hatched.monsters[1].id
local visitor = hatched.visitors[1]
check(visitor.voyage.tutorial and visitor.voyage.practice, "NPC tutorial is explicit in data")
local forwarded = invoke("Forward", { monsterId = visitor.id, voyageId = visitor.voyage.id, version = visitor.version, souvenirId = "sunhat" })
check(forwarded.profile.tutorial.visitor, "Tutorial visitor step persists")
check(forwarded.profile.currency == 40 and forwarded.profile.stats.forwards == 0, "NPC tutorial does not mint normal human forwarding money or stats")

local function activity(kind)
	invoke("ActivityStart", { kind = kind })
	for _ = 1, Config.Activities[kind].steps do
		local session = gameplay:getActivity(player.UserId)
		check(session ~= nil, kind .. " session exists")
		now = session.readyAt
		invoke("ActivityStep", { sessionId = session.sessionId, target = session.target })
	end
	check(gameplay:getActivity(player.UserId) == nil, kind .. " session completes")
end

activity("sorting")
check(voyages:snapshot(1).profile.currency == 48, "Sorting pays exactly eight Postage")
local launched = invoke("Launch", { monsterId = monsterId, plan = "Practice", objective = "hat", version = storage:getMonster(monsterId).version })
check(launched.monsters[1].voyage.practice, "Practice launch is labeled and active")
for _ = 1, 3 do now += Config.PracticeNpcInterval; voyages:tick() end
now += Config.PracticeSeconds - 3 * Config.PracticeNpcInterval
voyages:tick()
local returned = invoke("Snapshot", {})
local monster = returned.monsters[1]
check(monster.state == "HOME", "Practice returns without an eligible human")
check(monster.practiceVoyagesCompleted == 1 and monster.normalVoyagesCompleted == 0, "Practice and normal voyage statistics remain separate")
local book = monster.books[#monster.books]
check(book.practice and book.humanHops == 0 and book.rewardHops == 0, "Practice never becomes human-hop income")
local npcCount = 0
for _, event in ipairs(book.events) do if event.kind == "NPC" then npcCount += 1 end end
check(npcCount == 3, "Three fictional NPC postcards survive homecoming")
check(returned.profile.currency == 48, "Practice does not pay normal income")
local claimed = invoke("ClaimHomecoming", { monsterId = monsterId, bookId = book.id })
check(claimed.profile.tutorial.claimed and claimed.profile.cosmetics["decor:welcome"], "Starter decoration is granted")
local balance = claimed.profile.currency
local repeatClaim = invoke("ClaimHomecoming", { monsterId = monsterId, bookId = book.id })
check(repeatClaim.profile.currency == balance, "Replaying homecoming cannot duplicate money")

activity("watering")
activity("letters")
local purchased = invoke("Buy", { itemId = "decor:planter" })
check(purchased.profile.cosmetics["decor:planter"], "Earned Postage buys a decoration")
local placed = invoke("Place", { anchor = "1", itemId = "planter" })
check(placed.profile.placements["1"] == "planter", "Placement persists canonical decoration ID")
invoke("Settings", { key = "reducedMotion", value = true })
invoke("Settings", { key = "acceptVisitors", value = false })
voyages:playerLeaving(1)
gameplay:playerLeaving(1)
local fresh = VoyageService.new(storage, clock, { config = Config, catalog = Catalog, newId = nextId })
local rejoined = fresh:loadPlayer(1)
check(rejoined.profile.placements["1"] == "planter", "Placements survive service restart")
check(rejoined.profile.settings.reducedMotion and not rejoined.profile.settings.acceptVisitors, "Settings survive service restart")
check(rejoined.profile.tutorial.claimed and #rejoined.monsters == 1 and #rejoined.visitors == 0, "Tutorial and ownership survive service restart")
check(rejoined.monsters[1].books[1].claimed, "Claimed homecoming survives service restart")
check(rejoined.profile.stats.sorting == 1 and rejoined.profile.stats.watering == 1 and rejoined.profile.stats.letters == 1, "Every activity is counted exactly once")
check(#gameplay:getDaily(rejoined.profile) == 3, "Three rotating requests are available")
check(gameplay:handle(player, "ClaimMilestone", { milestoneId = "first_suitcase" }).ok, "Practice discoveries qualify for a collection milestone")
local milestoneXP = storage:getProfile("1").xp
check(gameplay:handle(player, "ClaimMilestone", { milestoneId = "first_suitcase" }).ok, "Completed milestone is safely replayable")
check(storage:getProfile("1").xp == milestoneXP and storage:getProfile("1").milestones.first_suitcase, "Milestone grants remain once-only")
check(not gameplay:handle(player, "ClaimMilestone", { milestoneId = "monster_garden" }).ok, "Unfinished collection cannot claim a grant")
print("PASS: " .. checks .. " integrated tutorial, activity, shop, placement, and reload checks (simulation; no Studio playtest)")
