-- Run with: .tools/bin/luau tests/gameplay.luau
local GameplayService = require("../src/server/GameplayService")
local Config = require("../src/shared/Config")
local Catalog = require("../src/shared/Catalog")
local checks = 0
local function expect(condition, label)
	assert(condition, label)
	checks += 1
end
local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = clone(item) end
	return result
end

local function fixture()
	local now, guid = 0, 0
	local profiles = {}
	for id = 1, 2 do
		profiles[tostring(id)] = {
			id = tostring(id), currency = 40, xp = 0, stats = {}, tutorial = {},
			settings = {}, cosmetics = { ["cannon:classic"] = true, ["mailbox:classic"] = true },
			placements = {}, requests = { day = 0, counters = {}, claimed = {} },
		}
	end
	local storage = { profiles = profiles, monsters = {}, mode = nil, cancelReturnsCurrent = false }
	function storage:getProfile(id) return clone(self.profiles[id]) end
	function storage:updateProfile(id, transform)
		if self.mode == "before" then self.mode = nil; error("simulated before-commit outage") end
		-- Real UpdateAsync may invoke callbacks repeatedly; only its final result commits.
		transform(clone(self.profiles[id]))
		local result = transform(clone(self.profiles[id]))
		if result then self.profiles[id] = clone(result) end
		if self.mode == "after" then self.mode = nil; error("simulated response loss after commit") end
		return clone(result or (if self.cancelReturnsCurrent then self.profiles[id] else nil))
	end
	function storage:updateMonster(id, transform)
		transform(clone(self.monsters[id]))
		local result = transform(clone(self.monsters[id]))
		if result then self.monsters[id] = clone(result) end
		return clone(result or (if self.cancelReturnsCurrent then self.monsters[id] else nil))
	end
	local world = { owner = 1 }
	function world:getActivityPosition(_player, _kind, index) return index end
	function world:getPlot(_player) return { ownerId = self.owner } end
	local clock = { now = function() return now end }
	local voyages = { storage = storage, clock = clock }
	local function service()
		return GameplayService.new(voyages, world, {
			config = Config, catalog = Catalog,
			idFactory = function() guid += 1; return "activity:" .. guid end,
			distance = function(player, position)
				return if player.at == position then 0 else 100
			end,
		})
	end
	local f = { service = service, storage = storage, world = world, player = { UserId = 1, at = 1 } }
	f.game = service()
	function f:advance(seconds) now += seconds end
	function f:setNow(seconds) now = seconds end
	function f:step(gameplay, player)
		local activity = gameplay:getActivity(player.UserId)
		player.at = if activity.kind == "sorting" then 1 else activity.index
		now = math.max(now, activity.readyAt)
		return gameplay:handle(player, "ActivityStep", { sessionId = activity.sessionId, target = activity.target })
	end
	function f:finish(gameplay, player)
		local total = gameplay:getActivity(player.UserId).total
		for _ = 1, total do expect(self:step(gameplay, player).ok, "Valid timed objective completes") end
	end
	return f
end

-- All three complete flows, pacing, objective order, distance, and double clicks.
for _, kind in ipairs({ "sorting", "watering", "letters" }) do
	local f = fixture()
	expect(f.game:handle(f.player, "ActivityStart", { kind = kind }).ok, "Activity starts: " .. kind)
	local activity = f.game:getActivity(1)
	expect(type(activity.target) == "number", "Network target is a numeric bin/objective")
	expect(not f.game:handle(f.player, "ActivityStep", { sessionId = activity.sessionId, target = activity.target }).ok,
		"Impossible timing grants nothing")
	expect(not f.game:handle(f.player, "ActivityStep", { sessionId = activity.sessionId, target = 999 }).ok,
		"Unissued objective is rejected")
	expect(not f.game:handle({ UserId = 2, at = 1 }, "ActivityStep", { sessionId = activity.sessionId, target = activity.target }).ok,
		"Another player cannot claim objectives")
	f:setNow(activity.readyAt)
	f.player.at = 99
	expect(not f.game:handle(f.player, "ActivityStep", { sessionId = activity.sessionId, target = activity.target }).ok,
		"Distance is checked at the objective")
	f:finish(f.game, f.player)
	local profile = f.storage:getProfile("1")
	expect(profile.currency == 40 + Config.Activities[kind].reward, "One server-calculated activity reward")
	expect(profile.stats.activities == 1 and profile.stats[kind] == 1, "Activity counters persist")
	expect(profile.tutorial.activity and profile.xp == Config.ActivityXP, "Activity advances tutorial and level XP")
	expect(profile.requests.counters[kind] == 1, "Activity advances today's requests")
	expect(f.game:getActivity(1) == nil, "Completed session is removed")
	expect(not f.game:handle(f.player, "ActivityStep", { sessionId = activity.sessionId, target = activity.target }).ok,
		"Repeated completion cannot pay again")
	expect(profile.activitySession.complete, "Completion receipt persists with grant")
end

-- Before-commit outage preserves a retryable final step; after-commit response
-- loss repeats the same receipt without crediting another reward.
for _, failureMode in ipairs({ "before", "after" }) do
	local f = fixture()
	expect(f.game:handle(f.player, "ActivityStart", { kind = "watering" }).ok, "Start outage fixture")
	for _ = 1, 3 do expect(f:step(f.game, f.player).ok, "Advance to final watering bed") end
	f.storage.mode = failureMode
	expect(not f:step(f.game, f.player).ok, "Storage outage is visible")
	expect(f.game:getActivity(1) ~= nil, "Unacknowledged reward remains retryable")
	expect(f:step(f.game, f.player).ok, "Retry acknowledges final step")
	expect(f.storage:getProfile("1").currency == 48, "Storage retry grants exactly once")
end

-- The old server keeps its unacknowledged session, a new server finishes a new
-- session, then the old worker retries: its durable token must remain invalid.
do
	local f = fixture()
	f.game:handle(f.player, "ActivityStart", { kind = "watering" })
	for _ = 1, 3 do f:step(f.game, f.player) end
	f.storage.mode = "after"
	expect(not f:step(f.game, f.player).ok, "Server A loses completion response")
	local nextServer = f.service()
	f.player.at = 1
	expect(nextServer:handle(f.player, "ActivityStart", { kind = "letters" }).ok, "Server B reserves newer session")
	f:finish(nextServer, f.player)
	f.storage.cancelReturnsCurrent = true
	expect(not f:step(f.game, f.player).ok, "Delayed server A reward retry is fenced")
	expect(f.storage:getProfile("1").currency == 56, "Only A and B each paid once")
	expect(f.game:getActivity(1) == nil, "Stale activity cannot remain actionable")
end

do
	local f = fixture()
	f.storage.mode = "before"
	expect(not f.game:handle(f.player, "ActivityStart", { kind = "letters" }).ok, "Start requires durable session reservation")
	expect(f.game:getActivity(1) == nil, "Failed reservation creates no activity")
	f.player.at = 99
	expect(not f.game:handle(f.player, "ActivityStart", { kind = "letters" }).ok, "Start requires distance")
	f.player.at = 1
	f.game:handle(f.player, "ActivityStart", { kind = "letters" })
	local firstId = f.game:getActivity(1).sessionId
	expect(f.game:handle(f.player, "ActivityStart", { kind = "letters" }).ok, "Repeated start resumes activity")
	expect(f.game:getActivity(1).sessionId == firstId, "Resume cannot reset timing")
	expect(not f.game:handle(f.player, "ActivityStart", { kind = "sorting" }).ok, "Overlapping activities blocked")
	f:advance(Config.ActivitySessionSeconds)
	expect(f.game:getActivity(1) == nil, "Abandoned sessions expire")
	f.game:handle(f.player, "ActivityStart", { kind = "letters" })
	f.game:playerLeaving(1)
	expect(f.game:getActivity(1) == nil, "Leaving cleans ephemeral objectives")
end

-- Purchases debit with ownership in the same record and accept duplicate intent.
do
	local f = fixture()
	expect(not f.game:handle(f.player, "Buy", { itemId = "decor:welcome" }).ok, "Insufficient Postage cannot buy")
	f.storage.profiles["1"].currency = 600
	expect(not f.game:handle(f.player, "Buy", { itemId = "decor:statue" }).ok, "Level locks apply")
	expect(not f.game:handle(f.player, "Buy", { itemId = "invented" }).ok, "Unlisted merchandise rejected")
	expect(f.game:handle(f.player, "Buy", { itemId = "decor:welcome" }).ok, "Owned decoration purchase")
	expect(f.game:handle(f.player, "Buy", { itemId = "decor:welcome" }).ok, "Duplicate purchase acknowledges ownership")
	expect(f.storage:getProfile("1").currency == 550, "Duplicate purchase debits once")
	expect(f.game:handle(f.player, "Place", { anchor = "1", itemId = "welcome" }).ok, "Owner places owned decoration")
	expect(f.storage:getProfile("1").placements["1"] == "welcome", "Decoration uses canonical asset ID")
	expect(not f.game:handle(f.player, "Place", { anchor = "2", itemId = "statue" }).ok, "Unowned decoration rejected")
	expect(not f.game:handle(f.player, "Place", { anchor = "9", itemId = "welcome" }).ok, "Invalid anchor rejected")
	f.world.owner = 2
	expect(not f.game:handle(f.player, "Place", { anchor = "1", itemId = "" }).ok, "Cannot edit another owner's plot")
	f.world.owner = 1
	expect(f.game:handle(f.player, "Place", { anchor = "1", itemId = "" }).ok, "Owner removes decoration")
	expect(f.storage:getProfile("1").placements["1"] == nil, "Removal persists")
	expect(not f.game:handle(f.player, "Style", { kind = "cannon", itemId = "coral" }).ok, "Unowned finish rejected")
	f.storage.profiles["1"].xp = 20
	expect(f.game:handle(f.player, "Buy", { itemId = "cannon:coral" }).ok, "Unlocked finish can be purchased")
	expect(f.game:handle(f.player, "Style", { kind = "cannon", itemId = "coral" }).ok, "Owned finish can be equipped")
	expect(f.storage:getProfile("1").cannon == "coral", "Finish persists")
	expect(f.storage:getProfile("1").currency == 450, "Finish cost is canonical")
	f.storage.mode = "after"
	expect(not f.game:handle(f.player, "Buy", { itemId = "decor:planter" }).ok, "Purchase response loss returns retry")
	expect(f.game:handle(f.player, "Buy", { itemId = "decor:planter" }).ok, "Purchase retry recovers ownership")
	expect(f.storage:getProfile("1").currency == 400, "Purchase response loss cannot double debit")
end

-- Requests rotate on absolute UTC days; either goal qualifies, grants are atomic.
do
	local f = fixture()
	local requests = f.game:getDaily(f.storage:getProfile("1"))
	expect(#requests == 3, "Exactly three rotating daily requests")
	expect(not f.game:handle(f.player, "ClaimRequest", { requestId = "helping" }).ok, "Incomplete request cannot pay")
	f.storage.profiles["1"].requests.counters.sorting = 3
	expect(f.game:getDaily(f.storage:getProfile("1"))[1].complete, "Activity alternative completes request")
	f.storage.mode = "after"
	expect(not f.game:handle(f.player, "ClaimRequest", { requestId = "helping" }).ok, "Request response loss is retryable")
	expect(f.game:handle(f.player, "ClaimRequest", { requestId = "helping" }).ok, "Request duplicate acknowledges claim")
	expect(f.storage:getProfile("1").currency == 40 + Config.RequestPostage, "Request grants once")
	expect(f.storage:getProfile("1").xp == Config.RequestXP, "Request XP grants once")
	f:setNow(86400)
	local tomorrow = f.game:getDaily(f.storage:getProfile("1"))
	expect(tomorrow[1].id ~= requests[1].id and not tomorrow[1].complete, "Next day rotates and resets progress")
	expect(not f.game:handle(f.player, "ClaimRequest", { requestId = "helping" }).ok, "Expired request cannot be replayed")
	f.game:handle(f.player, "ActivityStart", { kind = "watering" })
	f:finish(f.game, f.player)
	local saved = f.storage:getProfile("1")
	expect(saved.requests.day == 1 and saved.requests.counters.watering == 1, "Activity resets durable daily counters")
	expect(saved.requests.counters.sorting == nil and next(saved.requests.claimed) == nil, "Prior day counters and claims removed")
end

-- Settings are typed and finite; unrelated concurrent profile fields survive.
do
	local f = fixture()
	for _, value in ipairs({ math.huge, -math.huge, -1, 2, 0/0, "loud", true }) do
		expect(not f.game:handle(f.player, "Settings", { key = "musicVolume", value = value }).ok, "Invalid volume rejected")
	end
	expect(not f.game:handle(f.player, "Settings", { key = "currency", value = 999 }).ok, "Unlisted settings rejected")
	expect(not f.game:handle(f.player, "Settings", { key = "acceptVisitors", value = "yes" }).ok, "Boolean setting validated")
	expect(f.game:handle(f.player, "Settings", { key = "musicVolume", value = 0 }).ok, "Muting persists")
	expect(f.game:handle(f.player, "Settings", { key = "reducedMotion", value = true }).ok, "Reduced motion persists")
	expect(f.game:handle(f.player, "Settings", { key = "acceptVisitors", value = false }).ok, "Visitor opt-out persists")
	local profile = f.storage:getProfile("1")
	expect(profile.settings.musicVolume == 0 and profile.settings.reducedMotion and not profile.settings.acceptVisitors, "Independent settings retained")
	expect(profile.currency == 40, "Settings cannot affect money")
end

-- Appearances require canonical HOME state, immutable ownership, and earned IDs.
do
	local f = fixture()
	f.storage.monsters.monster = { ownerId = "1", state = "HOME", version = 1, earned = { sunhat = true }, slots = {} }
	expect(f.game:handle(f.player, "Equip", { monsterId = "monster", souvenirId = "sunhat" }).ok, "Earned appearance equips at home")
	expect(f.storage.monsters.monster.slots.hat == "sunhat" and f.storage.monsters.monster.version == 2, "Equip changes one slot and version")
	expect(f.game:handle(f.player, "Equip", { monsterId = "monster", souvenirId = "sunhat" }).ok, "Repeated equip is idempotent")
	expect(f.storage.monsters.monster.version == 2, "Repeated equip does not churn version")
	expect(not f.game:handle(f.player, "Equip", { monsterId = "monster", souvenirId = "crown" }).ok, "Unearned appearance rejected")
	expect(not f.game:handle({ UserId = 2 }, "Equip", { monsterId = "monster", souvenirId = "sunhat" }).ok, "Other owner cannot equip")
	f.storage.cancelReturnsCurrent = true
	f.storage.monsters.monster.state = "HELD"
	expect(not f.game:handle(f.player, "Equip", { monsterId = "monster", souvenirId = "sunhat" }).ok, "Traveling appearance cannot mutate")
end

print("PASS: " .. checks .. " gameplay progression, activity, receipt, shop, and settings checks")
