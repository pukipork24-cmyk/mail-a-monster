--!strict
-- Durable transitions have one canonical monster record; profiles contain references.
-- Dependencies are injected so this service runs under the standalone Luau VM.
local VoyageService = {}
VoyageService.__index = VoyageService

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function count(value) local n = 0; for _ in pairs(value or {}) do n += 1 end; return n end
local function contains(values, wanted) for _, value in ipairs(values) do if value == wanted then return true end end; return false end
local function fail(message) error(message, 0) end
local function expect(condition, message) if not condition then fail(message) end end
local function str(value) return type(value) == "string" and #value > 0 and #value <= 100 end

function VoyageService.new(storage, clock, options)
	options = options or {}
	local config = options.config
	local catalog = options.catalog
	if not config then config = require(game:GetService("ReplicatedStorage").MailAMonster.Shared.Config) end
	if not catalog then catalog = require(game:GetService("ReplicatedStorage").MailAMonster.Shared.Catalog) end
	local self = setmetatable({storage = storage, clock = clock, config = config, catalog = catalog, profiles = {}, active = {}, options = options, lastRecovery = -math.huge, lastPresence = -math.huge}, VoyageService)
	self.random = options.random or math.random
	self.newId = options.newId or function() return game:GetService("HttpService"):GenerateGUID(false) end
	self.workerId = options.workerId or self.newId()
	self.recoveryPartition = options.recoveryPartition or self.random(1, storage.recoveryPartitions or 1)
	return self
end

function VoyageService:level(profile) return self.config.level(profile.xp or 0) end

function VoyageService:_defaults(id, createdAt)
	return {schema = self.config.SchemaVersion, id = id, currency = self.config.StartingPostage,
		owned = {}, inbox = {}, outgoing = {}, xp = 0, hatchSeq = 0, pendingHatches = {}, launchReservations = {}, launchFloor = {},
		tutorial = {}, settings = {reducedMotion = false, musicVolume = 0.4, sfxVolume = 0.6, cameraShake = true, shareCountry = false, acceptVisitors = true},
		cosmetics = {["cannon:classic"] = true, ["mailbox:classic"] = true}, placements = {}, displaySlots = {}, cannon = "classic", mailbox = "classic",
		album = {}, stamps = {}, milestones = {}, stats = {forwards = 0, activities = 0, sorting = 0, watering = 0, letters = 0},
		requests = {day = self.config.day(createdAt), counters = {}, claimed = {}},
		receipts = {}, receiptEpoch = 1, caps = {carrier = {}, owner = {}}, capFloor = {carrier = -1, owner = -1}, lastLaunchAt = -1000000}
end

function VoyageService:_migrate(profile, id, createdAt)
	if not profile then return self:_defaults(id, createdAt) end
	expect((profile.schema or 0) <= self.config.SchemaVersion, "This save needs a newer server. Please rejoin.")
	if profile.hatchSeq == nil then profile.hatchSeq = #(profile.owned or {}) end
	local defaults = self:_defaults(id, createdAt)
	for key, value in pairs(defaults) do if profile[key] == nil then profile[key] = copy(value) end end
	for key, value in pairs(defaults.settings) do if profile.settings[key] == nil then profile.settings[key] = value end end
	for key, value in pairs(defaults.stats) do if profile.stats[key] == nil then profile.stats[key] = value end end
	for _, family in ipairs({ "carrier", "owner" }) do
		if profile.caps[family] == nil then profile.caps[family] = {} end
		if profile.capFloor[family] == nil then profile.capFloor[family] = -1 end
	end
	profile.requests.counters = profile.requests.counters or {}
	profile.requests.claimed = profile.requests.claimed or {}
	if profile.tutorial.hatched == nil and #profile.owned > 0 then profile.tutorial.hatched = true end
	profile.schema = self.config.SchemaVersion
	return profile
end

function VoyageService:_newMonster(id, owner, name, seed)
	local catalog = self.catalog
	return {schema = self.config.SchemaVersion, id = id, ownerId = owner, name = name, seed = seed,
		body = catalog.Bodies[seed % #catalog.Bodies + 1], palette = catalog.PaletteOrder[math.floor(seed / 4) % #catalog.PaletteOrder + 1],
		face = catalog.Faces[math.floor(seed / 24) % #catalog.Faces + 1], personality = catalog.Personalities[math.floor(seed / 96) % #catalog.Personalities + 1],
		state = "HOME", version = 1, voyageNumber = 0, lifetimeHops = 0, voyagesCompleted = 0, normalVoyagesCompleted = 0, practiceVoyagesCompleted = 0, slots = {}, earned = {}, books = {}, operations = {}}
end

function VoyageService:_migrateMonster(monster)
	if not monster then return nil end
	expect((monster.schema or 0) <= self.config.SchemaVersion, "This monster needs a newer server. Please rejoin.")
	if monster.schema == self.config.SchemaVersion then return monster end
	expect(str(monster.id) and str(monster.ownerId), "This monster record needs operator recovery.")
	expect(not monster.voyage or monster.state, "An ambiguous active voyage needs operator recovery.")
	local seed = monster.seed or 1
	expect(type(seed) == "number" and seed == seed and seed >= 0 and seed < math.huge, "This monster's cosmetic seed needs operator recovery.")
	local defaults = self:_newMonster(monster.id, monster.ownerId, monster.name or "Gerald", seed)
	for key, value in pairs(defaults) do if monster[key] == nil then monster[key] = copy(value) end end
	monster.schema = self.config.SchemaVersion
	return monster
end

function VoyageService:_readMonster(id)
	local monster = self.storage:getMonster(id)
	if monster and monster.schema ~= self.config.SchemaVersion then
		return self.storage:updateMonster(id, function(current) return self:_migrateMonster(current) end)
	end
	return monster
end

function VoyageService:_recoverHatches(id)
	local profile = self.storage:getProfile(id)
	for monsterId, record in pairs(profile.pendingHatches or {}) do
		local created = self.storage:createMonster(record)
		expect(created and created.ownerId == id, "Hatch recovery needs retry.")
		self.storage:updateProfile(id, function(p) if p and p.pendingHatches[monsterId] then p.pendingHatches[monsterId] = nil end; return p end)
	end
end

function VoyageService:loadPlayer(userId)
	local id = tostring(userId)
	local createdAt = self.clock.now()
	local profile = self.storage:updateProfile(id, function(old) return self:_migrate(old, id, createdAt) end)
	self.active[id] = true
	self:_recoverHatches(id)
	for _, monsterId in ipairs(profile.owned) do self:_process(monsterId) end
	self:_repairInbox(id)
	self:_ensureTutorialVisitor(id)
	self:_presence(id)
	return self:snapshot(id)
end

function VoyageService:_presence(id, profile)
	profile = profile or self.storage:getProfile(id)
	if profile then self.storage:presence(id, {accept = profile.settings.acceptVisitors, available = math.max(0, self.config.IncomingCapacity - count(profile.inbox)), job = self.options.jobId or self.workerId}, self.clock.now()) end
end

function VoyageService:playerLeaving(userId)
	local id = tostring(userId); self.active[id] = nil; self.profiles[id] = nil
	self.storage:presence(id, nil, self.clock.now())
end

function VoyageService:_ensureTutorialVisitor(id)
	local p = self.storage:getProfile(id)
	if not p or not p.tutorial.hatched or p.tutorial.visitor or p.tutorial.skipped then return end
	local monsterId = "tutorial-" .. id
	local now = self.clock.now()
	local monster = self:_newMonster(monsterId, "NPC", "Pickle", 11)
	monster.tutorialFor = id; monster.state = "HELD"; monster.voyageNumber = 1
	monster.voyage = {id = monsterId .. ":1", plan = "Tutorial", practice = true, tutorial = true, startedAt = now, deadline = now + 365 * 86400, hopTarget = 0, deposit = 0,
		humanHops = 0, rewardHops = 0, visited = {}, events = {{kind = "NPC", at = now, label = "NPC tutorial visitor — help Pickle learn the post!"}},
		slotsBefore = {}, holderId = id, claimToken = monsterId .. ":claim", holdUntil = now + 365 * 86400, npcCount = 0, lastNpcAt = now}
	self.storage:createMonster(monster)
	self.storage:updateProfile(id, function(profile)
		if profile and not profile.tutorial.visitor and count(profile.inbox) < self.config.IncomingCapacity then
			profile.inbox[monsterId] = {token = monster.voyage.claimToken, voyageId = monster.voyage.id, expires = monster.voyage.holdUntil}
		end
		return profile
	end)
end

function VoyageService:_hatch(id, payload)
	expect(contains(self.catalog.Names, payload.name), "Choose a name from the list.")
	expect(type(payload.sequence) == "number" and payload.sequence >= 0 and payload.sequence % 1 == 0, "Refresh your hatchery before hatching.")
	local newId = self.newId(); local seed = self.random(1, 1000000)
	local record = self:_newMonster(newId, id, payload.name, seed)
	local result = self.storage:updateProfile(id, function(p)
		if not p or p.hatchSeq ~= payload.sequence or next(p.pendingHatches) or #p.owned >= self.config.MaxOwnedMonsters then return nil end
		local price = if p.tutorial.hatched then self.config.EggCost else 0
		if p.currency < price then return nil end
		p.currency -= price; p.hatchSeq += 1; p.tutorial.hatched = true
		p.pendingHatches[newId] = copy(record); table.insert(p.owned, newId)
		return p
	end)
	expect(result and result.pendingHatches[newId], "The egg was already hatched, your collection is full, or you need more Postage. Refresh your collection before retrying.")
	self:_recoverHatches(id); self:_ensureTutorialVisitor(id)
	return {kind = "hatch", monsterId = newId}
end

function VoyageService:_launch(id, payload)
	expect(str(payload.monsterId), "Choose a monster.")
	local plan = self.config.Plans[payload.plan]
	expect(plan, "Choose a valid voyage plan.")
	local objective = payload.objective or "hat"
	expect(self.config.Objectives[objective], "Choose a valid voyage objective.")
	local now = self.clock.now()
	local profile = self.storage:getProfile(id)
	expect(profile and self:level(profile) >= plan.level, "This voyage unlocks at a higher courier level.")
	local current = self:_readMonster(payload.monsterId)
	expect(current and current.ownerId == id, "That monster is not in your collection.")
	if current.state == "LAUNCH_PENDING" then
		expect(current.launchVersion == payload.version + 1, "This launch request belongs to an older monster state. Refresh your collection.")
		self:_process(current.id)
		local recovered = self.storage:getMonster(current.id)
		expect(recovered and recovered.voyage and recovered.state ~= "HOME" and recovered.state ~= "LAUNCH_PENDING", "Launch reservation could not complete. Please retry.")
		return {kind = "launch", monsterId = current.id}
	end
	self:_drain(current.id); current = self.storage:getMonster(current.id)
	expect(current.version == payload.version, "That launch was already accepted or the monster changed. Refresh before planning another voyage.")
	expect(count(current.operations) == 0, "Your previous homecoming is still settling. Please retry.")
	expect(current.state == "HOME", "Your monster is already traveling.")
	expect(not plan.practice or not profile.tutorial.practice, "Your practice voyage is already complete.")
	local operation = "launch:" .. current.id .. ":" .. (current.version + 1)
	local voyage = {id = current.id .. ":" .. (current.voyageNumber + 1), plan = plan.id, practice = plan.practice == true, startedAt = now,
		deadline = now + plan.seconds, hopTarget = plan.hops, deposit = plan.cost, humanHops = 0, rewardHops = 0, visited = {},
		events = {{kind = "DEPARTURE", at = now, label = if plan.practice then "Practice Voyage — fictional NPC postal route" else "Departure from home"}},
		slotsBefore = copy(current.slots), npcCount = 0, lastNpcAt = now, objective = objective}
	local prepared = self.storage:updateMonster(current.id, function(m)
		if not m or m.ownerId ~= id or m.state ~= "HOME" or m.version ~= current.version or count(m.operations) > 0 then return nil end
		m.state = "LAUNCH_PENDING"; m.version += 1; m.voyage = copy(voyage); m.launchOperation = operation; m.launchVersion = m.version; m.launchCancelled = nil
		return m
	end)
	expect(prepared and prepared.launchOperation == operation, "The monster changed. Please retry.")
	self:_process(current.id)
	local accepted = self.storage:getMonster(current.id)
	expect(accepted and accepted.voyage and accepted.voyage.id == voyage.id and accepted.state ~= "HOME" and accepted.state ~= "LAUNCH_PENDING", "Launch could not reserve Postage or an outgoing slot. Please retry.")
	return {kind = "launch", monsterId = current.id}
end

function VoyageService:_cancelLaunch(monster)
	local operation = monster.launchOperation
	self.storage:updateProfile(monster.ownerId, function(p)
		if not p then return nil end
		p.launchFloor[monster.id] = math.max(p.launchFloor[monster.id] or 0, monster.launchVersion)
		local reservation = p.launchReservations[operation]
		if reservation and reservation.status == "reserved" then p.currency += reservation.amount end
		p.launchReservations[operation] = nil
		if p.outgoing[monster.id] == operation then p.outgoing[monster.id] = nil end
		if p.practiceActive == operation then p.practiceActive = nil end
		return p
	end)
	self.storage:updateMonster(monster.id, function(m)
		if m and m.state == "LAUNCH_PENDING" and m.launchOperation == operation and m.launchCancelled then
			m.state = "HOME"; m.version += 1; m.voyage = nil; m.launchOperation = nil; m.launchCancelled = nil
		end
		return m
	end)
end

function VoyageService:_prepareLaunch(monster)
	local operation, owner = monster.launchOperation, monster.ownerId
	if monster.launchCancelled then self:_cancelLaunch(monster); return end
	local now = self.clock.now()
	local p = self.storage:updateProfile(owner, function(profile)
		if not profile then return nil end
		if (profile.launchFloor[monster.id] or 0) >= monster.launchVersion then return profile end
		if profile.launchReservations[operation] then return profile end
		local capacity = self.config.OutgoingCapacity + (if self:level(profile) >= self.config.ExtraOutgoingLevel then 1 else 0)
		if monster.voyage.practice and (profile.practiceActive or profile.tutorial.practice) then return profile end
		if count(profile.outgoing) >= capacity or profile.currency < monster.voyage.deposit or now - profile.lastLaunchAt < self.config.DispatchCooldown then return profile end
		profile.currency -= monster.voyage.deposit; profile.lastLaunchAt = now
		profile.launchReservations[operation] = {amount = monster.voyage.deposit, monsterId = monster.id, status = "reserved"}
		profile.outgoing[monster.id] = operation
		if monster.voyage.practice then profile.practiceActive = operation end
		return profile
	end)
	if not p or not p.launchReservations[operation] then
		local cancelled = self.storage:updateMonster(monster.id, function(m)
			if m and m.state == "LAUNCH_PENDING" and m.launchOperation == operation then m.launchCancelled = true end
			return m
		end)
		if cancelled and cancelled.launchCancelled then self:_cancelLaunch(cancelled) end
		return
	end
	local queued = self.storage:updateMonster(monster.id, function(m)
		if not m or m.launchOperation ~= operation then return nil end
		if m.state == "LAUNCH_PENDING" and not m.launchCancelled then m.state = "QUEUED"; m.version += 1; m.voyageNumber += 1 end
		return m
	end)
	if queued and queued.launchCancelled then self:_cancelLaunch(queued); return end
	if not queued or not queued.voyage or queued.state == "LAUNCH_PENDING" then return end
	self.storage:updateProfile(owner, function(profile)
		local reservation = profile and profile.launchReservations[operation]
		if reservation and reservation.status == "reserved" then reservation.status = "finalized" end
		return profile
	end)
	self.storage:enqueue(monster.id, now)
end

function VoyageService:_repairInbox(id)
	local profile = self.storage:getProfile(id)
	if not profile then return end
	local now = self.clock.now()
	for monsterId, reference in pairs(profile.inbox) do
		local m = self.storage:getMonster(monsterId)
		local valid = m and m.state == "HELD" and m.voyage and m.voyage.holderId == id and m.voyage.claimToken == reference.token
		-- Fresh reservations remain until their claimant finishes or timeout; do not race it.
		if not valid and (reference.expires or 0) <= now then
			self.storage:updateProfile(id, function(p)
				if p and p.inbox[monsterId] and p.inbox[monsterId].token == reference.token then p.inbox[monsterId] = nil end
				return p
			end)
		end
	end
end

function VoyageService:_match(monster)
	if monster.state ~= "QUEUED" or monster.voyage.practice then return false end
	local now = self.clock.now()
	local entries = self.storage:listPresence(now)
	for i = #entries, 2, -1 do local j = self.random(1, i); entries[i], entries[j] = entries[j], entries[i] end
	for _, entry in ipairs(entries) do
		local id = entry.id
		if id ~= monster.ownerId and not monster.voyage.visited[id] and entry.value.accept and entry.value.available > 0 then
			local token = self.newId()
			local reserve = self.storage:updateProfile(id, function(p)
				if not p or not p.settings.acceptVisitors or count(p.inbox) >= self.config.IncomingCapacity or p.inbox[monster.id] then return nil end
				p.inbox[monster.id] = {token = token, voyageId = monster.voyage.id, expires = now + 60}
				return p
			end)
			if reserve and reserve.inbox[monster.id] and reserve.inbox[monster.id].token == token then
				local held = self.storage:updateMonster(monster.id, function(m)
					if not m or m.state ~= "QUEUED" or m.version ~= monster.version or m.voyage.id ~= monster.voyage.id or m.voyage.deadline <= now or m.voyage.visited[id] then return nil end
					m.state = "HELD"; m.version += 1; m.voyage.holderId = id; m.voyage.claimToken = token; m.voyage.holdUntil = math.min(now + self.config.HoldSeconds, m.voyage.deadline)
					return m
				end)
				if held and held.state == "HELD" and held.voyage.claimToken == token then
					self.storage:updateProfile(id, function(p) if p and p.inbox[monster.id] and p.inbox[monster.id].token == token then p.inbox[monster.id].expires = held.voyage.holdUntil end; return p end)
					self.storage:removeHint(monster.id)
					return true
				end
				self:_removeInbox(id, monster.id, token)
			end
		end
	end
	return false
end

function VoyageService:_removeInbox(id, monsterId, token)
	self.storage:updateProfile(id, function(p) if p and p.inbox[monsterId] and p.inbox[monsterId].token == token then p.inbox[monsterId] = nil end; return p end)
end

function VoyageService:_repairHeld(monster)
	local v = monster.voyage
	if monster.state ~= "HELD" or not v or v.holdUntil <= self.clock.now() then return end
	local profile = self.storage:getProfile(v.holderId)
	if not profile then return end
	local existing = profile.inbox[monster.id]
	if existing and existing.token == v.claimToken then return end
	local reservationExpiry = self.clock.now() + 60
	local repaired = self.storage:updateProfile(v.holderId, function(p)
		if not p then return nil end
		local ref = p.inbox[monster.id]
		if ref and ref.token == v.claimToken then return p end
		if ref or count(p.inbox) >= self.config.IncomingCapacity then return nil end
		p.inbox[monster.id] = { token = v.claimToken, voyageId = v.id, expires = reservationExpiry }
		return p
	end)
	if repaired and repaired.inbox[monster.id] and repaired.inbox[monster.id].token == v.claimToken then return end
	if v.tutorial then return end
	-- A reservation may expire before a delayed canonical claim commits. If its
	-- slot has since filled, revoke that exact claim and put the traveler back.
	self.storage:updateMonster(monster.id, function(m)
		if not m or m.state ~= "HELD" or m.version ~= monster.version or not m.voyage
			or m.voyage.claimToken ~= v.claimToken then return nil end
		m.operations["release:" .. v.claimToken] = { kind = "inbox", target = v.holderId, token = v.claimToken }
		m.voyage.holderId = nil; m.voyage.claimToken = nil; m.voyage.holdUntil = nil
		m.state = "QUEUED"; m.version += 1
		return m
	end)
end

function VoyageService:_forward(id, payload, release)
	expect(str(payload.monsterId) and str(payload.voyageId) and type(payload.version) == "number", "That visitor request is invalid.")
	local profile = self.storage:getProfile(id)
	local ref = profile and profile.inbox[payload.monsterId]
	expect(ref, "This visitor has already moved on. Refresh your mailbox.")
	local souvenir = self.catalog.Souvenirs[payload.souvenirId]
	if not release then expect(souvenir and self:level(profile) >= souvenir.level, "Choose an unlocked souvenir.") end
	local now = self.clock.now()
	self:_readMonster(payload.monsterId)
	local stamp = self.catalog.StampOrder[self.random(1, #self.catalog.StampOrder)]
	local country = nil
	if not release and profile.settings.shareCountry and self.options.countryFor then local ok, result = pcall(self.options.countryFor, id); if ok and type(result) == "string" and #result <= 3 then country = result end end
	local updated = self.storage:updateMonster(payload.monsterId, function(m)
		local v = m and m.voyage
		if not m or m.state ~= "HELD" or m.version ~= payload.version or not v or v.id ~= payload.voyageId or v.holderId ~= id or v.claimToken ~= ref.token or v.holdUntil <= now or v.deadline <= now or v.visited[id] or m.ownerId == id then return nil end
		if release and v.tutorial then return nil end
		local oldToken = v.claimToken
		v.holderId = nil; v.claimToken = nil; v.holdUntil = nil
		m.version += 1
		m.operations["release:" .. oldToken] = {kind = "inbox", target = id, token = oldToken}
		if release then m.state = "QUEUED"; return m end
		m.slots[souvenir.slot] = souvenir.id; m.earned[souvenir.id] = true
		if v.tutorial then
			m.state = "RETURNING"
			table.insert(v.events, {kind = "NPC", at = now, label = "NPC tutorial visitor forwarded", souvenirId = souvenir.id, stampId = stamp})
			m.operations["tutorial:" .. v.id] = {kind = "tutorial", target = id, at = now, souvenirId = souvenir.id, stampId = stamp}
		else
			v.visited[id] = true; v.humanHops += 1; m.lifetimeHops += 1
			local index = #v.events + 1
			table.insert(v.events, {kind = "HUMAN", at = now, label = "Anonymous courier " .. v.humanHops, souvenirId = souvenir.id, stampId = stamp, country = country, humanHop = true, rewardEligible = false})
			m.operations["carrier:" .. v.id .. ":" .. v.humanHops] = {kind = "carrier", target = id, at = now, souvenirId = souvenir.id, stampId = stamp, eventIndex = index}
			m.operations["owner:" .. v.id .. ":" .. v.humanHops] = {kind = "ownerAllocation", target = m.ownerId, at = now, eventIndex = index}
			m.state = if v.humanHops >= v.hopTarget then "RETURNING" else "QUEUED"
		end
		return m
	end)
	expect(updated and updated.version == payload.version + 1, "This visitor changed, its hold expired, or it needs the free tutorial souvenir. Refresh and retry.")
	self:_process(payload.monsterId)
	return {kind = "forward", monsterId = payload.monsterId, free = true, released = release}
end

function VoyageService:_compactReceipts(p)
	if count(p.receipts) < 192 then return end
	p.receiptEpoch += 1
	for id, receipt in pairs(p.receipts) do if receipt.acknowledged then p.receipts[id] = nil end end
	expect(count(p.receipts) < 256, "Reward recovery is busy. Please retry shortly.")
end

function VoyageService:_allocateCap(p, family, day, limit)
	local buckets = p.caps[family]
	if day <= (p.capFloor[family] or -1) then return false end
	local key = tostring(day)
	local used = buckets[key] or 0
	local eligible = used < limit
	if eligible then buckets[key] = used + 1 end
	-- Close historical days conservatively; delayed allocation cannot bypass a cap.
	if count(buckets) > 64 then
		local oldest = math.huge
		for recorded in pairs(buckets) do oldest = math.min(oldest, tonumber(recorded)) end
		buckets[tostring(oldest)] = nil; p.capFloor[family] = math.max(p.capFloor[family] or -1, oldest)
	end
	return eligible
end

function VoyageService:_deliver(monsterId, operationId)
	local monster = self.storage:getMonster(monsterId)
	local op = monster and monster.operations[operationId]
	if not op then return end
	if op.kind == "inbox" then
		self:_removeInbox(op.target, monsterId, op.token)
		self.storage:updateMonster(monsterId, function(m) if m then m.operations[operationId] = nil end; return m end)
		return
	end
	local p = self.storage:getProfile(op.target)
	if not p then return end
	-- Persist an epoch before delivery. Compaction fences already-running stale workers.
	if op.epoch ~= p.receiptEpoch and not p.receipts[operationId] then
		monster = self.storage:updateMonster(monsterId, function(m)
			local existing = m and m.operations[operationId]
			if existing and not existing.delivered then existing.epoch = p.receiptEpoch end
			return m
		end)
		op = monster and monster.operations[operationId]
		if not op then return end
	end
	if not op.delivered then
		local result = self.storage:updateProfile(op.target, function(profile)
			if not profile then return nil end
			if profile.receipts[operationId] then return profile end
			if profile.receiptEpoch ~= op.epoch then return nil end
			self:_compactReceipts(profile)
			-- Compaction may have advanced the epoch; retry through canonical fencing.
			if profile.receiptEpoch ~= op.epoch then return profile end
			local receipt = {amount = 0, eligible = false, acknowledged = false}
			local day = self.config.day(op.at)
			if op.kind == "carrier" then
				receipt.eligible = self:_allocateCap(profile, "carrier", day, self.config.CarrierDailyCap)
				receipt.amount = if receipt.eligible then self.config.CarrierReward else 0
				profile.xp += self.config.ForwardXP; profile.stats.forwards += 1
				if profile.requests.day ~= day and day >= profile.requests.day then profile.requests = {day = day, counters = {}, claimed = {}} end
				if profile.requests.day == day then profile.requests.counters.forwards = (profile.requests.counters.forwards or 0) + 1 end
			elseif op.kind == "ownerAllocation" then
				receipt.eligible = self:_allocateCap(profile, "owner", day, self.config.OwnerDailyHopCap)
			elseif op.kind == "homecoming" then
				receipt.amount = op.amount; profile.xp += self.config.HomecomingXP
				if profile.outgoing[monsterId] == op.launchOperation then profile.outgoing[monsterId] = nil end
				profile.launchReservations[op.launchOperation] = nil
				profile.launchFloor[monsterId] = math.max(profile.launchFloor[monsterId] or 0, op.launchVersion or 0)
				if profile.practiceActive == op.launchOperation then profile.practiceActive = nil end
				if op.practice then profile.tutorial.practice = true end
			elseif op.kind == "tutorial" then profile.tutorial.visitor = true end
			if op.souvenirId then profile.album[op.souvenirId] = {at = op.at, context = if op.kind == "tutorial" then "NPC tutorial visitor" else "A visitor you helped"} end
			if op.stampId then profile.stamps[op.stampId] = {at = op.at, context = "Fictional postal destination"} end
			if op.discoveries then for item in pairs(op.discoveries) do profile.album[item] = profile.album[item] or {at = op.at, context = if op.practice then "Practice NPC postcard" else "Homecoming souvenir"} end end
			if op.stamps then for item in pairs(op.stamps) do profile.stamps[item] = profile.stamps[item] or {at = op.at, context = "Fictional postal destination"} end end
			profile.currency += receipt.amount
			profile.receipts[operationId] = receipt
			return profile
		end)
		local receipt = result and result.receipts[operationId]
		if not receipt then return end
		monster = self.storage:updateMonster(monsterId, function(m)
			local existing = m and m.operations[operationId]
			if not existing or existing.delivered then return m end
			existing.delivered = true; existing.result = copy(receipt)
			if existing.kind == "ownerAllocation" and existing.result.eligible then
				m.voyage.rewardHops += 1
				m.voyage.events[existing.eventIndex].rewardEligible = true
			end
			return m
		end)
	end
	-- Acknowledgment follows canonical delivery, so only safely completed receipts compact.
	self.storage:updateProfile(op.target, function(profile)
		if profile and profile.receipts[operationId] then profile.receipts[operationId].acknowledged = true end
		return profile
	end)
	self.storage:updateMonster(monsterId, function(m) if m and m.operations[operationId] and m.operations[operationId].delivered then m.operations[operationId] = nil end; return m end)
end

function VoyageService:_drain(monsterId)
	local monster = self.storage:getMonster(monsterId)
	if not monster then return end
	for operationId in pairs(monster.operations or {}) do
		if not self.storage:hasBudget() then return end
		self:_deliver(monsterId, operationId)
	end
end

function VoyageService:_recall(id, payload)
	local now = self.clock.now()
	local changed = self.storage:updateMonster(payload.monsterId, function(m)
		if not m or m.ownerId ~= id or not m.voyage or m.voyage.id ~= payload.voyageId or m.voyage.tutorial or m.state == "HOME" or m.state == "LAUNCH_PENDING" then return nil end
		if now - m.voyage.startedAt < self.config.EarlyReturnSeconds then return nil end
		if m.state ~= "RETURNING" then
			if m.voyage.holderId then m.operations["release:" .. m.voyage.claimToken] = {kind = "inbox", target = m.voyage.holderId, token = m.voyage.claimToken} end
			m.voyage.holderId = nil; m.voyage.claimToken = nil; m.voyage.holdUntil = nil; m.state = "RETURNING"; m.version += 1
		end
		return m
	end)
	expect(changed and changed.ownerId == id and changed.state == "RETURNING", "This voyage changed, or early return needs ten minutes after departure. Refresh tracking and retry.")
	self:_process(payload.monsterId)
	return {kind = "return", monsterId = payload.monsterId}
end

function VoyageService:_npc(monster)
	local now = self.clock.now()
	local interval = if monster.voyage.practice then self.config.PracticeNpcInterval else self.config.NpcInterval
	if monster.voyage.npcCount >= self.config.MaxNpcPostcards or now - monster.voyage.lastNpcAt < interval then return end
	local eventTime = monster.voyage.lastNpcAt + interval
	local index = monster.voyage.npcCount + 1
	local variation = if monster.voyage.practice then 0 else (monster.voyageNumber - 1) % 4
	local souvenirId = self.catalog.SouvenirOrder[({1, 5, 9})[index] + variation]
	local souvenir = self.catalog.Souvenirs[souvenirId]
	local stamp = self.catalog.StampOrder[(monster.seed + index + (monster.voyageNumber - 1) * 3) % #self.catalog.StampOrder + 1]
	self.storage:updateMonster(monster.id, function(m)
		if not m or m.state ~= "QUEUED" or m.version ~= monster.version then return nil end
		m.voyage.npcCount += 1; m.voyage.lastNpcAt = eventTime; m.version += 1
		m.slots[souvenir.slot] = souvenirId; m.earned[souvenirId] = true
		table.insert(m.voyage.events, {kind = "NPC", at = eventTime, label = self.catalog.NpcNames[index] .. " — fictional postal stop", souvenirId = souvenirId, stampId = stamp, humanHop = false, rewardEligible = false})
		return m
	end)
end

function VoyageService:_return(monster)
	if count(monster.operations) > 0 then return end
	local now = self.clock.now()
	self.storage:updateMonster(monster.id, function(m)
		if not m or m.state ~= "RETURNING" or count(m.operations) > 0 then return nil end
		local v = m.voyage
		if v.tutorial then m.state = "HOME"; m.version += 1; m.voyage = nil; return m end
		local families, hasHat, discoveries, stamps = {}, false, {}, {}
		for _, event in ipairs(v.events) do
			if event.souvenirId then
				local item = self.catalog.Souvenirs[event.souvenirId]; families[item.family] = true; hasHat = hasHat or item.family == "hat"; discoveries[item.id] = true
			end
			if event.stampId then stamps[event.stampId] = true end
		end
		local achieved = v.npcCount >= self.config.MaxNpcPostcards or (v.objective == "hat" and hasHat) or (v.objective == "families" and count(families) >= 2)
		local objectiveReward = if achieved and not v.practice then self.config.Objectives[v.objective].reward else 0
		local payout = v.deposit + v.rewardHops * self.config.OwnerHopReward + objectiveReward
		table.insert(v.events, {kind = "RETURN", at = now, label = "Home sweet home"})
		local book = {id = v.id, number = m.voyageNumber, plan = v.plan, practice = v.practice, events = copy(v.events), slotsBefore = v.slotsBefore, slotsAfter = copy(m.slots),
			humanHops = v.humanHops, rewardHops = v.rewardHops, startedAt = v.startedAt, returnedAt = now, deposit = v.deposit, payout = payout, objectiveReward = objectiveReward, claimed = false}
		table.insert(m.books, book)
		while #m.books > self.config.BookRetention do table.remove(m.books, 1) end
		m.voyagesCompleted += 1
		if v.practice then m.practiceVoyagesCompleted = (m.practiceVoyagesCompleted or 0) + 1
		else m.normalVoyagesCompleted = (m.normalVoyagesCompleted or 0) + 1 end
		m.state = "HOME"; m.version += 1; m.voyage = nil
		m.operations["return:" .. v.id] = {kind = "homecoming", target = m.ownerId, at = now, amount = payout, practice = v.practice, launchOperation = m.launchOperation, launchVersion = m.launchVersion, discoveries = discoveries, stamps = stamps}
		return m
	end)
end

function VoyageService:_process(monsterId)
	local monster = self:_readMonster(monsterId)
	if not monster then return end
	if monster.state == "HOME" and count(monster.operations) == 0 then return end
	if monster.state == "LAUNCH_PENDING" then self:_prepareLaunch(monster); monster = self.storage:getMonster(monsterId) end
	self:_drain(monsterId)
	monster = self.storage:getMonster(monsterId)
	if not monster or not monster.voyage then return end
	if monster.state == "HELD" then self:_repairHeld(monster); monster = self.storage:getMonster(monsterId) end
	local now = self.clock.now()
	if monster.state == "QUEUED" and monster.voyage.practice and not monster.voyage.tutorial then
		for _ = 1, self.config.MaxNpcPostcards do self:_npc(monster); monster = self.storage:getMonster(monsterId) end
	end
	if not monster.voyage.tutorial and (monster.voyage.deadline <= now or (monster.state == "HELD" and monster.voyage.holdUntil <= now)) then
		self.storage:updateMonster(monsterId, function(m)
			if not m or m.version ~= monster.version or not m.voyage then return nil end
			local v = m.voyage
			if v.holderId then m.operations["release:" .. v.claimToken] = {kind = "inbox", target = v.holderId, token = v.claimToken} end
			v.holderId = nil; v.claimToken = nil; v.holdUntil = nil
			m.state = if v.deadline <= now then "RETURNING" else "QUEUED"; m.version += 1
			return m
		end)
		self:_drain(monsterId)
		monster = self.storage:getMonster(monsterId)
	end
	if monster.state == "RETURNING" then self:_return(monster); self:_drain(monsterId)
	elseif monster.state == "QUEUED" then
		self.storage:enqueue(monsterId, now)
		if not self:_match(monster) then self:_npc(monster) end
	end
end

function VoyageService:_claim(id, payload)
	local changed = self.storage:updateMonster(payload.monsterId, function(m)
		if not m or m.ownerId ~= id then return nil end
		for _, book in ipairs(m.books) do if book.id == payload.bookId then book.claimed = true; return m end end
		return nil
	end)
	expect(changed and changed.ownerId == id, "That homecoming is not available.")
	local practice = false
	for _, book in ipairs(changed.books) do if book.id == payload.bookId then practice = book.practice end end
	if practice then self.storage:updateProfile(id, function(p) if p then p.tutorial.claimed = true; p.cosmetics["decor:welcome"] = true end; return p end) end
	self:_drain(payload.monsterId)
	return {kind = "homecoming", monsterId = payload.monsterId, bookId = payload.bookId}
end

function VoyageService:_skip(id)
	self.storage:updateProfile(id, function(p)
		if p then p.tutorial.skipped = true; p.tutorial.claimed = true; p.cosmetics["decor:welcome"] = true end
		return p
	end)
	return {kind = "notice", message = "Guidance skipped. Your free first hatch, 40 starting Postage, and welcome pennant are yours."}
end

function VoyageService:publicMonster(monster, visitor)
	local m = copy(monster)
	m.ownerId = nil; m.operations = nil; m.launchOperation = nil; m.launchVersion = nil; m.launchCancelled = nil; m.tutorialFor = nil
	if m.voyage then m.voyage.visited = nil; m.voyage.holderId = nil; m.voyage.claimToken = nil end
	if visitor then m.books = {} end
	return m
end

function VoyageService:snapshot(userId)
	local id = tostring(userId)
	local profile = self.storage:getProfile(id)
	expect(profile, "Your profile is still loading. Please retry.")
	local monsters, visitors = {}, {}
	for _, monsterId in ipairs(profile.owned) do local m = self.storage:getMonster(monsterId); if m and m.ownerId == id then table.insert(monsters, self:publicMonster(m)) end end
	for monsterId, ref in pairs(profile.inbox) do
		local m = self.storage:getMonster(monsterId)
		if m and m.state == "HELD" and m.voyage and m.voyage.holderId == id and m.voyage.claimToken == ref.token and m.voyage.holdUntil > self.clock.now() then table.insert(visitors, self:publicMonster(m, true)) end
	end
	local public = copy(profile)
	public.pendingEggs = count(profile.pendingHatches)
	public.id = nil; public.receipts = nil; public.receiptEpoch = nil; public.launchReservations = nil; public.pendingHatches = nil; public.inbox = nil; public.capFloor = nil; public.launchFloor = nil; public.practiceActive = nil; public.activitySession = nil; public.activityReceipt = nil
	public.level = self:level(profile)
	local day = tostring(self.config.day(self.clock.now()))
	public.daily = {carrier = profile.caps.carrier[day] or 0, owner = profile.caps.owner[day] or 0, carrierLimit = self.config.CarrierDailyCap, ownerLimit = self.config.OwnerDailyHopCap}
	public.caps = nil
	self.profiles[id] = copy(profile)
	return {profile = public, monsters = monsters, visitors = visitors, serverTime = self.clock.now(), simulation = self.storage.simulation}
end

function VoyageService:handle(userId, action, payload)
	local id = tostring(userId)
	payload = payload or {}
	local ok, result = pcall(function()
		local effect
		if action == "Snapshot" then return {ok = true, data = self:snapshot(id)}
		elseif action == "Hatch" then effect = self:_hatch(id, payload)
		elseif action == "Launch" then effect = self:_launch(id, payload)
		elseif action == "Forward" then effect = self:_forward(id, payload, false)
		elseif action == "ReleaseVisitor" then effect = self:_forward(id, payload, true)
		elseif action == "Recall" then effect = self:_recall(id, payload)
		elseif action == "ClaimHomecoming" then effect = self:_claim(id, payload)
		elseif action == "SkipTutorial" then effect = self:_skip(id)
		else return {ok = false, error = "Unknown action."} end
		return {ok = true, effect = effect, data = self:snapshot(id)}
	end)
	if not ok then return {ok = false, error = tostring(result)} end
	return result
end

function VoyageService:tick()
	local now = self.clock.now()
	local function workerBudget() return self.storage:hasBudget(self.config.BackgroundReadReserve, self.config.BackgroundWriteReserve) end
	if not workerBudget() then return end
	if now - self.lastPresence >= 30 then
		for id in pairs(self.active) do
			if not workerBudget() then return end
			local profile = self.storage:getProfile(id)
			if profile then
				if next(profile.pendingHatches) then self:_recoverHatches(id) end
				if profile.tutorial.hatched and not profile.tutorial.visitor and not profile.tutorial.skipped then self:_ensureTutorialVisitor(id) end
				if next(profile.inbox) then self:_repairInbox(id) end
				self:_presence(id, profile)
			end
		end
		self.lastPresence = now
	end
	if not workerBudget() then return end
	local processed = {}
	for _, monsterId in ipairs(self.storage:listHints(self.config.RecoveryBatchSize)) do
		if not workerBudget() then return end
		processed[monsterId] = true
		if self.storage:lease("m:" .. monsterId, self.workerId, now, self.config.LeaseSeconds) then
			self:_process(monsterId)
			local m = self.storage:getMonster(monsterId)
			if not m or m.state == "HOME" or m.state == "HELD" then self.storage:removeHint(monsterId) end
		end
	end
	if now - self.lastRecovery >= self.config.RecoveryInterval then
		local partition = self.recoveryPartition
		local checkpointName = "enumerator:" .. tostring(partition)
		self.recoveryPartition = partition % (self.storage.recoveryPartitions or 1) + 1
		if not self.storage:lease(checkpointName, self.workerId, now, self.config.LeaseSeconds) then return end
		local checkpoint = self.storage:getCheckpoint(checkpointName) or {}
		local ids, cursor = self.storage:listMonsterIds(checkpoint.cursor, self.config.RecoveryBatchSize, partition)
		for _, monsterId in ipairs(ids) do
			if not workerBudget() then return end
			if not processed[monsterId] then self:_process(monsterId) end
		end
		-- Advance only after the complete page succeeds. A crash replays this page safely.
		self.storage:setCheckpoint(checkpointName, {cursor = cursor, at = now})
		self.lastRecovery = now
	end
end

return VoyageService
