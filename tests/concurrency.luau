-- Independent adversarial interleavings against the actual service and adapter.
-- These are deterministic simulated workers, not live Roblox cross-server tests.
local Storage = require("../src/server/Storage")
local VoyageService = require("../src/server/VoyageService")
local Config = require("../src/shared/Config")
local Catalog = require("../src/shared/Catalog")
local checks = 0
local function expect(condition, message)
	assert(condition, message)
	checks += 1
end

local function fixture()
	local storage = Storage.createSimulation()
	local now, sequence = 1000, 0
	local clock = { now = function() return now end }
	local function id()
		sequence += 1
		return "test-" .. sequence
	end
	local options = { config = Config, catalog = Catalog, newId = id, random = function(_, upper) return upper end }
	local a, b = VoyageService.new(storage, clock, options), VoyageService.new(storage, clock, options)
	a:loadPlayer(1)
	storage:updateProfile("1", function(p) p.tutorial.skipped = true; return p end)
	local hatch = a:handle(1, "Hatch", { name = "Gerald", sequence = 0 })
	assert(hatch.ok, hatch.error)
	local monsterId = hatch.effect.monsterId
	local launch = a:handle(1, "Launch", { monsterId = monsterId, plan = "ShortHop", objective = "hat", version = storage:getMonster(monsterId).version })
	assert(launch.ok, launch.error)
	local function addCourier(userId)
		a:loadPlayer(userId)
		storage:updateProfile(tostring(userId), function(p) p.tutorial.skipped = true; return p end)
	end
	return storage, a, b, monsterId, addCourier, function(value) now = value end
end

local function payload(storage, monsterId)
	local m = storage:getMonster(monsterId)
	return { monsterId = monsterId, voyageId = m.voyage.id, version = m.version, souvenirId = "sunhat" }
end

-- A reserves one inbox, then B obtains canonical custody before A's CAS runs.
do
	local storage, a, b, monsterId, addCourier = fixture()
	addCourier(2); addCourier(3)
	local queued = storage:getMonster(monsterId)
	local original = storage.updateMonster
	local interleaved = false
	storage.updateMonster = function(self, key, transform)
		if key == monsterId and not interleaved then
			interleaved = true
			expect(b:_match(queued), "The competing worker must claim custody")
		end
		return original(self, key, transform)
	end
	expect(not a:_match(queued), "The losing claim is rejected by canonical CAS")
	storage.updateMonster = original
	local m = storage:getMonster(monsterId)
	expect(m.state == "HELD" and m.ownerId == "1", "Exactly one holder preserves original ownership")
	local validReferences = 0
	for _, userId in ipairs({ "2", "3" }) do
		local ref = storage:getProfile(userId).inbox[monsterId]
		if ref then
			validReferences += 1
			expect(userId == m.voyage.holderId and ref.token == m.voyage.claimToken, "Only canonical holder keeps its reservation")
		end
	end
	expect(validReferences == 1, "Losing reservation is removed, not an actionable duplicate")
	expect(#a:snapshot(tonumber(m.voyage.holderId)).visitors == 1, "Winner sees exactly one actionable visitor")
end

-- Recall commits before a courier's already-read forward can commit.
do
	local storage, a, b, monsterId, addCourier, setNow = fixture()
	addCourier(2); assert(a:_match(storage:getMonster(monsterId)))
	local intent = payload(storage, monsterId)
	setNow(1700)
	local original, interleaved = storage.updateMonster, false
	storage.updateMonster = function(self, key, transform)
		if key == monsterId and not interleaved then
			interleaved = true
			local response = b:handle(1, "Recall", { monsterId = monsterId, voyageId = intent.voyageId })
			expect(response.ok, "Recall should commit first")
		end
		return original(self, key, transform)
	end
	local response = a:handle(2, "Forward", intent)
	storage.updateMonster = original
	expect(not response.ok, "A stale forward loses to recall")
	local m = storage:getMonster(monsterId)
	expect(m.state == "HOME" and m.lifetimeHops == 0, "Recall leaves no phantom human hop")
	expect(m.slots.hat == nil and storage:getProfile("2").currency == 40, "Stale courier earns neither souvenir nor reward")
	expect(storage:getProfile("1").currency == 40, "Owner receives only the original deposit")
	expect(not b:handle(2, "Forward", intent).ok, "Replaying the revoked custody token stays rejected")
end

-- Forward wins first; recall must include its already earned hop exactly once.
do
	local storage, a, b, monsterId, addCourier, setNow = fixture()
	addCourier(2); assert(a:_match(storage:getMonster(monsterId)))
	local intent = payload(storage, monsterId)
	setNow(1700)
	local original, interleaved = storage.updateMonster, false
	storage.updateMonster = function(self, key, transform)
		if key == monsterId and not interleaved then
			interleaved = true
			local response = b:handle(2, "Forward", intent)
			expect(response.ok, "Forward should commit first")
		end
		return original(self, key, transform)
	end
	local response = a:handle(1, "Recall", { monsterId = monsterId, voyageId = intent.voyageId })
	storage.updateMonster = original
	expect(response.ok, "Recall succeeds after committed forward")
	local m = storage:getMonster(monsterId)
	expect(m.state == "HOME" and m.lifetimeHops == 1, "Committed forwarding survives recall")
	expect(m.books[1].humanHops == 1 and m.books[1].rewardHops == 1, "Saved passport and eligible reward agree")
	expect(storage:getProfile("2").currency == 45, "Courier earns exactly five Postage")
	expect(storage:getProfile("1").currency == 50, "Owner receives deposit, one hop and hat objective")
	expect(not a:handle(2, "Forward", intent).ok, "A duplicate forward cannot replay earned hop")
end

local function pendingForward()
	local storage, a, b, monsterId, addCourier = fixture()
	addCourier(2); assert(a:_match(storage:getMonster(monsterId)))
	-- Stop after the canonical transition, as a server crash would.
	local process = a._process
	a._process = function() end
	local response = a:handle(2, "Forward", payload(storage, monsterId))
	a._process = process
	assert(response.ok, response.error)
	local operationId
	for id, operation in pairs(storage:getMonster(monsterId).operations) do
		if operation.kind == "carrier" then operationId = id end
	end
	assert(operationId, "Fixture requires a pending durable carrier operation")
	return storage, a, b, monsterId, operationId
end

-- Two workers enter the same payout: B pays, then A runs its old callback.
do
	local storage, a, b, monsterId, operationId = pendingForward()
	local original, interleaved = storage.updateProfile, false
	storage.updateProfile = function(self, key, transform)
		if tostring(key) == "2" and not interleaved then
			interleaved = true
			b:_deliver(monsterId, operationId)
		end
		return original(self, key, transform)
	end
	a:_deliver(monsterId, operationId)
	storage.updateProfile = original
	local p = storage:getProfile("2")
	expect(p.currency == 45 and p.stats.forwards == 1, "Concurrent outbox workers pay and count once")
	expect(p.caps.carrier["0"] == 1, "Concurrent delivery consumes one daily allowance")
	expect(storage:getMonster(monsterId).operations[operationId] == nil, "Acknowledged operation is removed")
end

-- B finishes and receipt compaction occurs before A resumes its old payment.
do
	local storage, a, b, monsterId, operationId = pendingForward()
	local original, interleaved = storage.updateProfile, false
	storage.updateProfile = function(self, key, transform)
		if tostring(key) == "2" and not interleaved then
			interleaved = true
			b:_deliver(monsterId, operationId)
			original(self, "2", function(p)
				for index = 1, 192 do p.receipts["old:" .. index] = { acknowledged = true, amount = 0 } end
				b:_compactReceipts(p)
				return p
			end)
		end
		return original(self, key, transform)
	end
	a:_deliver(monsterId, operationId)
	storage.updateProfile = original
	local p = storage:getProfile("2")
	expect(p.receipts[operationId] == nil and p.receiptEpoch == 2, "Paid receipt was legitimately compacted")
	expect(p.currency == 45 and p.stats.forwards == 1, "Epoch fence blocks old worker after receipt deletion")
	expect(p.caps.carrier["0"] == 1, "Compaction cannot reopen a daily allowance")
end

print("PASS: " .. checks .. " adversarial simulated concurrency checks")
