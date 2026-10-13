-- Deterministic domain tests; no Roblox services or engine emulation.
local Storage = require("../src/server/Storage")
local VoyageService = require("../src/server/VoyageService")
local Config = require("../src/shared/Config")
local Catalog = require("../src/shared/Catalog")

local passed = 0
local crashCases = 0
local function eq(actual, expected, message)
	assert(actual == expected, (message or "Values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
	local ok, message = pcall(run)
	if not ok then error("FAIL " .. name .. ": " .. tostring(message), 0) end
	passed += 1; print("PASS " .. name)
end
local function fixture()
	local now, sequence = 2000000000, 0
	local clock = {now = function() return now end, advance = function(seconds) now += seconds end}
	local storage = Storage.createSimulation()
	local options = {config = Config, catalog = Catalog, workerId = "worker-A", random = function(a, b) return a end,
		newId = function() sequence += 1; return "test-" .. sequence end}
	local service = VoyageService.new(storage, clock, options)
	return service, storage, clock, options
end
local function loaded(service, storage, id)
	service:loadPlayer(id)
	storage:updateProfile(id, function(p) p.tutorial.skipped = true; return p end)
end
local function hatch(service, id)
	local result = service:handle(id, "Hatch", {name = "Gerald", sequence = service.storage:getProfile(id).hatchSeq})
	assert(result.ok, result.error)
	return result.effect.monsterId
end
local function launch(service, id, monsterId, plan)
	local result = service:handle(id, "Launch", {monsterId = monsterId, plan = plan or "ShortHop", version = service.storage:getMonster(monsterId).version})
	assert(result.ok, result.error)
end
local function visitor(storage, monsterId, souvenir)
	local m = storage:getMonster(monsterId)
	return {monsterId = monsterId, voyageId = m.voyage.id, version = m.version, souvenirId = souvenir or "sunhat"}
end
local function forward(service, storage, id, monsterId)
	local result = service:handle(id, "Forward", visitor(storage, monsterId))
	assert(result.ok, result.error)
	return result
end

test("starter profile, free egg and resumable NPC tutorial", function()
	local service, storage = fixture()
	service:loadPlayer("A")
	eq(storage:getProfile("A").currency, 40)
	local id = hatch(service, "A")
	eq(storage:getProfile("A").currency, 40)
	eq(storage:getMonster(id).ownerId, "A")
	local snapshot = service:snapshot("A")
	eq(#snapshot.visitors, 1)
	assert(snapshot.visitors[1].voyage.tutorial)
	forward(service, storage, "A", "tutorial-A")
	local p = storage:getProfile("A")
	assert(p.tutorial.visitor); eq(p.currency, 40); eq(p.stats.forwards, 0)
	service:loadPlayer("A")
	eq(#service:snapshot("A").visitors, 0)
end)

test("practice catch-up creates three NPC postcards and a once-only starter grant", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A"); local id = hatch(service, "A")
	launch(service, "A", id, "Practice")
	clock.advance(75); service:tick()
	local m = storage:getMonster(id)
	eq(m.state, "HOME"); eq(m.books[1].humanHops, 0); eq(m.books[1].payout, 0)
	local postcards = 0
	for _, event in ipairs(m.books[1].events) do if event.kind == "NPC" then postcards += 1 end end
	eq(postcards, 3)
	for _ = 1, 2 do assert(service:handle("A", "ClaimHomecoming", {monsterId = id, bookId = m.books[1].id}).ok) end
	local p = storage:getProfile("A")
	eq(p.currency, 40); assert(p.tutorial.practice and p.tutorial.claimed and p.cosmetics["decor:welcome"])
	assert(not service:handle("A", "Launch", {monsterId = id, plan = "Practice", version = storage:getMonster(id).version}).ok)
end)

test("cross-worker handoff preserves owner and credits a courier once", function()
	local service, storage, clock, options = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local peer = VoyageService.new(storage, clock, options)
	local id = hatch(service, "A"); launch(service, "A", id)
	local m = storage:getMonster(id)
	eq(m.state, "HELD"); eq(m.voyage.holderId, "B")
	local payload = visitor(storage, id)
	assert(peer:handle("B", "Forward", payload).ok)
	assert(not service:handle("B", "Forward", payload).ok)
	m = storage:getMonster(id)
	eq(m.ownerId, "A"); eq(m.voyage.humanHops, 1); eq(m.voyage.rewardHops, 1); eq(m.slots.hat, "sunhat")
	eq(storage:getProfile("B").currency, 45); eq(storage:getProfile("A").currency, 20)
	service:tick(); eq(storage:getProfile("B").currency, 45)
end)

test("owner and previous contributor cannot receive the same voyage", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local id = hatch(service, "A"); launch(service, "A", id); forward(service, storage, "B", id)
	clock.advance(310); service:tick()
	local m = storage:getMonster(id)
	eq(m.state, "QUEUED"); eq(m.voyage.humanHops, 1); eq(m.voyage.npcCount, 1)
	eq(storage:getProfile("B").currency, 45)
end)

test("target homecoming pays deposit and capped eligible hops exactly once", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A")
	for _, courier in ipairs({"B", "C", "D"}) do loaded(service, storage, courier) end
	local id = hatch(service, "A"); launch(service, "A", id)
	for _ = 1, 3 do local m = storage:getMonster(id); forward(service, storage, m.voyage.holderId, id) end
	local m = storage:getMonster(id)
	eq(m.state, "HOME"); eq(m.lifetimeHops, 3); eq(m.books[1].humanHops, 3); eq(m.books[1].payout, 40)
	eq(storage:getProfile("A").currency, 60) -- 40 -20 +20 +15 +5 objective
	clock.advance(30); service:tick(); service:loadPlayer("A")
	service:handle("A", "ClaimHomecoming", {monsterId = id, bookId = m.books[1].id})
	eq(storage:getProfile("A").currency, 60)
end)

test("early recall rejects before ten minutes and safely revokes holder", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local id = hatch(service, "A"); launch(service, "A", id)
	local old = visitor(storage, id)
	assert(not service:handle("A", "Recall", {monsterId = id, voyageId = storage:getMonster(id).voyage.id}).ok)
	clock.advance(600); assert(service:handle("A", "Recall", {monsterId = id, voyageId = storage:getMonster(id).voyage.id}).ok)
	eq(storage:getMonster(id).state, "HOME"); eq(storage:getProfile("A").currency, 40)
	assert(not service:handle("B", "Forward", old).ok)
	eq(storage:getProfile("B").currency, 40)
end)

test("offline owner and vanished queue hints recover overdue return", function()
	local service, storage, clock, options = fixture()
	loaded(service, storage, "A"); local id = hatch(service, "A"); launch(service, "A", id)
	service:playerLeaving("A"); storage.hints = {}; storage.leases = {}
	clock.advance(Config.Plans.ShortHop.seconds + 1)
	local restarted = VoyageService.new(storage, clock, options); restarted:tick()
	eq(storage:getMonster(id).state, "HOME"); eq(storage:getProfile("A").currency, 40)
	assert(storage:getCheckpoint("enumerator:1").at)
end)

test("24 hour holder expiry forwards automatically without rewards", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	storage:updateProfile("A", function(p) p.xp = 200; return p end)
	local id = hatch(service, "A"); launch(service, "A", id, "Expedition")
	service:playerLeaving("B")
	clock.advance(Config.HoldSeconds + 1); service:tick()
	local m = storage:getMonster(id)
	eq(m.state, "QUEUED"); eq(m.voyage.humanHops, 0); eq(storage:getProfile("B").currency, 40)
end)

test("full mailbox and opt-out never receive new assignments", function()
	local service, storage = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B"); loaded(service, storage, "C")
	storage:updateProfile("B", function(p) p.settings.acceptVisitors = false; return p end)
	storage:updateProfile("C", function(p) p.inbox = {a = {}, b = {}, c = {}}; return p end)
	local id = hatch(service, "A"); launch(service, "A", id)
	eq(storage:getMonster(id).state, "QUEUED")
end)

test("carrier and owner daily caps preserve history but stop bonus income", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local day = tostring(Config.day(clock.now()))
	storage:updateProfile("A", function(p) p.caps.owner[day] = Config.OwnerDailyHopCap; return p end)
	storage:updateProfile("B", function(p) p.caps.carrier[day] = Config.CarrierDailyCap; return p end)
	local id = hatch(service, "A"); launch(service, "A", id); forward(service, storage, "B", id)
	local m = storage:getMonster(id)
	eq(m.voyage.humanHops, 1); eq(m.voyage.rewardHops, 0); eq(storage:getProfile("B").currency, 40)
	clock.advance(600); assert(service:handle("A", "Recall", {monsterId = id, voyageId = storage:getMonster(id).voyage.id}).ok)
	eq(storage:getProfile("A").currency, 45) -- deposit plus objective only
end)

test("failed storage reads never replace a profile or fall back to defaults", function()
	local service, storage = fixture()
	loaded(service, storage, "A")
	storage:updateProfile("A", function(p) p.currency = 123; return p end)
	storage:failNext("getProfile")
	assert(not service:handle("A", "Snapshot", {}).ok)
	eq(storage:getProfile("A").currency, 123)
	storage:failNext("updateProfile")
	local ok = pcall(function() service:loadPlayer("A") end)
	assert(not ok); eq(storage:getProfile("A").currency, 123)
end)

test("invalid names, souvenirs, self-forwarding and forged versions fail", function()
	local service, storage = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	assert(not service:handle("A", "Hatch", {name = "Unfiltered input"}).ok)
	local id = hatch(service, "A"); launch(service, "A", id)
	local payload = visitor(storage, id, "unknown")
	assert(not service:handle("B", "Forward", payload).ok)
	payload.souvenirId = "sunhat"; payload.version -= 1
	assert(not service:handle("B", "Forward", payload).ok)
	assert(not service:handle("A", "Forward", visitor(storage, id)).ok)
	eq(storage:getMonster(id).voyage.humanHops, 0)
end)

test("release visitor is free and does not count a human hop", function()
	local service, storage = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local id = hatch(service, "A"); launch(service, "A", id)
	storage:updateProfile("B", function(p) p.settings.acceptVisitors = false; return p end)
	assert(service:handle("B", "ReleaseVisitor", visitor(storage, id)).ok)
	eq(storage:getMonster(id).voyage.humanHops, 0); eq(storage:getProfile("B").currency, 40)
end)

test("failed launch refunds or never charges and leaves a usable home monster", function()
	local service, storage = fixture()
	loaded(service, storage, "A"); local id = hatch(service, "A")
	storage:updateProfile("A", function(p) p.currency = 0; return p end)
	assert(not service:handle("A", "Launch", {monsterId = id, plan = "ShortHop", version = storage:getMonster(id).version}).ok)
	eq(storage:getMonster(id).state, "HOME"); eq(storage:getProfile("A").currency, 0)
	storage:updateProfile("A", function(p) p.currency = 40; return p end)
	launch(service, "A", id)
	eq(storage:getProfile("A").currency, 20)
end)

test("outgoing capacities and per-account practice guard are durable", function()
	local service, storage, clock = fixture()
	loaded(service, storage, "A")
	storage:updateProfile("A", function(p) p.currency = 1000; return p end)
	local a, b, c = hatch(service, "A"), hatch(service, "A"), hatch(service, "A")
	launch(service, "A", a, "Practice"); clock.advance(11)
	assert(not service:handle("A", "Launch", {monsterId = b, plan = "Practice", version = storage:getMonster(b).version}).ok)
	launch(service, "A", b); clock.advance(11)
	assert(not service:handle("A", "Launch", {monsterId = c, plan = "ShortHop", version = storage:getMonster(c).version}).ok)
	storage:updateProfile("A", function(p) p.xp = 140; return p end)
	launch(service, "A", c)
end)

test("public snapshots contain no custody tokens or internal owner IDs", function()
	local service, storage = fixture()
	loaded(service, storage, "A"); loaded(service, storage, "B")
	local id = hatch(service, "A"); launch(service, "A", id)
	local snapshot = service:snapshot("B")
	eq(snapshot.profile.id, nil); eq(snapshot.profile.receipts, nil); eq(snapshot.profile.inbox, nil)
	eq(snapshot.visitors[1].ownerId, nil); eq(snapshot.visitors[1].operations, nil)
	eq(snapshot.visitors[1].voyage.holderId, nil); eq(snapshot.visitors[1].voyage.claimToken, nil); eq(snapshot.visitors[1].voyage.visited, nil)
end)

-- Each run injects a process death before/after one durable write, then starts a
-- new service over the same storage. This covers uncertain write outcomes too.
local function inject(storage, cut, after)
	local originalProfile, originalMonster = storage.updateProfile, storage.updateMonster
	local status = { writes = 0, fired = false }
	local function wrapper(original)
		return function(self, ...)
			status.writes += 1
			local hit = status.writes == cut
			if hit then status.fired = true end
			if hit and not after then error("simulated process death") end
			local result = original(self, ...)
			if hit and after then error("simulated process death after commit") end
			return result
		end
	end
	storage.updateProfile = wrapper(originalProfile); storage.updateMonster = wrapper(originalMonster)
	return function() storage.updateProfile = originalProfile; storage.updateMonster = originalMonster end, status
end

test("launch crash matrix: every measured commit boundary recovers without duplicate deposits", function()
	local measuredService, measuredStorage = fixture()
	loaded(measuredService, measuredStorage, "A"); local measuredId = hatch(measuredService, "A")
	local unhook, measured = inject(measuredStorage, math.huge, false)
	launch(measuredService, "A", measuredId); unhook()
	assert(measured.writes > 0)
	for _, after in ipairs({false, true}) do for cut = 1, measured.writes do
		local service, storage, clock, options = fixture()
		loaded(service, storage, "A"); local id = hatch(service, "A")
		local restore, status = inject(storage, cut, after)
		service:handle("A", "Launch", {monsterId = id, plan = "ShortHop", version = storage:getMonster(id).version})
		restore()
		assert(status.fired, "Launch fault did not execute at boundary " .. cut); crashCases += 1
		local restart = VoyageService.new(storage, clock, options)
		restart:loadPlayer("A")
		if storage:getMonster(id).state == "HOME" then launch(restart, "A", id) end
		restart:tick()
		eq(storage:getProfile("A").currency, 20, "launch fault " .. cut)
		eq(storage:getMonster(id).voyageNumber, 1)
		clock.advance(Config.Plans.ShortHop.seconds + 1); restart:tick()
		eq(storage:getProfile("A").currency, 40); eq(storage:getMonster(id).state, "HOME")
	end end
end)

test("forward crash matrix: every measured write preserves one hop and one courier payout", function()
	local measuredService, measuredStorage = fixture()
	loaded(measuredService, measuredStorage, "A"); loaded(measuredService, measuredStorage, "B")
	local measuredId = hatch(measuredService, "A"); launch(measuredService, "A", measuredId)
	local unhook, measured = inject(measuredStorage, math.huge, false)
	forward(measuredService, measuredStorage, "B", measuredId); unhook()
	assert(measured.writes > 0)
	for _, after in ipairs({false, true}) do for cut = 1, measured.writes do
		local service, storage, clock, options = fixture()
		loaded(service, storage, "A"); loaded(service, storage, "B")
		local id = hatch(service, "A"); launch(service, "A", id)
		local payload = visitor(storage, id)
		local restore, status = inject(storage, cut, after)
		service:handle("B", "Forward", payload); restore()
		assert(status.fired, "Forward fault did not execute at boundary " .. cut); crashCases += 1
		local restart = VoyageService.new(storage, clock, options)
		restart:loadPlayer("A"); restart:loadPlayer("B"); restart:tick()
		if storage:getMonster(id).voyage.humanHops == 0 then assert(restart:handle("B", "Forward", payload).ok) end
		clock.advance(30); restart:tick()
		local m = storage:getMonster(id)
		eq(m.voyage.humanHops, 1, "forward fault " .. cut); eq(m.voyage.rewardHops, 1)
		eq(storage:getProfile("B").currency, 45); eq(storage:getProfile("B").stats.forwards, 1)
	end end
end)

test("homecoming crash matrix: every measured commit preserves deposit and payout once", function()
	local measuredService, measuredStorage, measuredClock = fixture()
	loaded(measuredService, measuredStorage, "A"); local measuredId = hatch(measuredService, "A"); launch(measuredService, "A", measuredId)
	measuredClock.advance(Config.Plans.ShortHop.seconds + 1)
	local unhook, measured = inject(measuredStorage, math.huge, false)
	measuredService:tick(); unhook()
	assert(measured.writes > 0)
	for _, after in ipairs({false, true}) do for cut = 1, measured.writes do
		local service, storage, clock, options = fixture()
		loaded(service, storage, "A"); local id = hatch(service, "A"); launch(service, "A", id)
		clock.advance(Config.Plans.ShortHop.seconds + 1)
		local restore, status = inject(storage, cut, after)
		pcall(function() service:tick() end); restore()
		assert(status.fired, "Homecoming fault did not execute at boundary " .. cut); crashCases += 1
		local restart = VoyageService.new(storage, clock, options)
		restart:loadPlayer("A"); clock.advance(30); restart:tick()
		eq(storage:getMonster(id).state, "HOME"); eq(#storage:getMonster(id).books, 1)
		eq(storage:getProfile("A").currency, 40, "return fault " .. cut)
	end end
end)

print("Core service tests: " .. passed .. " passed; " .. crashCases .. " injected crash scenarios executed (all target failures confirmed fired).")
