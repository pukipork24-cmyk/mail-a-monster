--!strict
-- All live writes fail closed. The simulation implements the same CAS contract.
local Storage = {}

local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = clone(item) end
	return result
end
Storage.clone = clone

-- Canonical keys are discoverable without a secondary registration write.
-- Sixteen prefixes allow independent bounded recovery walks in live servers.
function Storage.partitionFor(id, partitions)
	local value = 0
	for index = 1, #id do value = (value * 33 + string.byte(id, index)) % (partitions or 16) end
	return value + 1
end

function Storage.createSimulation(options)
	options = options or {}
	local backend = { simulation = true, recoveryPartitions = options.partitions or 1, profiles = {}, monsters = {}, hints = {}, online = {}, leases = {}, checkpoints = {}, failures = {} }
	local function guard(name)
		local count = backend.failures[name] or 0
		if count > 0 then backend.failures[name] = count - 1; error("Simulated storage failure: " .. name) end
	end
	function backend:failNext(name, count) self.failures[name] = count or 1 end
	function backend:getProfile(id) guard("getProfile"); return clone(self.profiles[tostring(id)]) end
	function backend:updateProfile(id, transform)
		guard("updateProfile")
		id = tostring(id)
		local result = transform(clone(self.profiles[id]))
		if result == nil then return nil end
		self.profiles[id] = clone(result)
		return clone(result)
	end
	function backend:getMonster(id) guard("getMonster"); return clone(self.monsters[id]) end
	function backend:updateMonster(id, transform)
		guard("updateMonster")
		local result = transform(clone(self.monsters[id]))
		if result == nil then return nil end
		self.monsters[id] = clone(result)
		return clone(result)
	end
	function backend:createMonster(record)
		return self:updateMonster(record.id, function(old) return old or clone(record) end)
	end
	function backend:listMonsterIds(cursor, limit, partition)
		guard("listMonsterIds")
		local keys = {}
		for key in pairs(self.monsters) do
			if (not cursor or key > cursor) and (not partition or Storage.partitionFor(key, self.recoveryPartitions) == partition) then table.insert(keys, key) end
		end
		table.sort(keys)
		local result = {}
		for index = 1, math.min(limit or 20, #keys) do table.insert(result, keys[index]) end
		return result, if #keys > #result then result[#result] else nil
	end
	function backend:presence(id, value, now)
		guard("presence")
		if value then self.online[tostring(id)] = { value = clone(value), expires = now + 90 } else self.online[tostring(id)] = nil end
	end
	function backend:listPresence(now)
		guard("listPresence")
		local values = {}
		for id, entry in pairs(self.online) do if entry.expires > now then table.insert(values, { id = id, value = clone(entry.value) }) end end
		return values
	end
	function backend:enqueue(id, now) guard("enqueue"); self.hints[id] = now end
	function backend:removeHint(id) self.hints[id] = nil end
	function backend:listHints(limit)
		guard("listHints")
		local values = {}
		for id in pairs(self.hints) do table.insert(values, id) end
		table.sort(values)
		while #values > (limit or 20) do table.remove(values) end
		return values
	end
	function backend:lease(name, owner, now, seconds)
		local old = self.leases[name]
		if old and old.expires > now and old.owner ~= owner then return false end
		self.leases[name] = { owner = owner, expires = now + seconds }
		return true
	end
	function backend:getCheckpoint(name) return clone(self.checkpoints[name]) end
	function backend:setCheckpoint(name, value) guard("setCheckpoint"); self.checkpoints[name] = clone(value) end
	function backend:hasBudget() return true end
	function backend:reset()
		self.profiles = {}; self.monsters = {}; self.hints = {}; self.online = {}; self.leases = {}; self.checkpoints = {}; self.failures = {}
	end
	return backend
end

function Storage.createLive(options)
	options = options or {}
	local dataService = game:GetService("DataStoreService")
	local memoryService = game:GetService("MemoryStoreService")
	local namespace = options.namespace or "MAM_v1"
	assert(namespace:match("^[%w_%-]+$") and #namespace <= 32, "Invalid storage namespace")
	local records = dataService:GetDataStore(namespace .. "_Records")
	local profiles = dataService:GetDataStore(namespace .. "_Profiles")
	local recovery = dataService:GetDataStore(namespace .. "_Recovery")
	local presence = memoryService:GetSortedMap(namespace .. "_Presence")
	local queue = memoryService:GetSortedMap(namespace .. "_Queue")
	local leases = memoryService:GetSortedMap(namespace .. "_Leases")
	local backend = { simulation = false, namespace = namespace, recoveryPartitions = 16 }
	local function recordPrefix(partition) return string.format("m:%02x:", partition - 1) end
	local function recordKey(id) return recordPrefix(Storage.partitionFor(id, 16)) .. id end
	local function request(label, fn)
		local lastError
		for attempt = 1, 3 do
			local ok, value = pcall(fn)
			if ok then return value end
			lastError = tostring(value)
			if attempt < 3 then task.wait(0.3 * 2 ^ (attempt - 1) + math.random() * 0.2) end
		end
		warn("MAIL A MONSTER storage operation paused: " .. label)
		error("Storage is temporarily unavailable. Please retry. [" .. label .. "] " .. tostring(lastError), 0)
	end
	function backend:getProfile(id) return request("profile read", function() return profiles:GetAsync("p:" .. tostring(id)) end) end
	function backend:updateProfile(id, transform) return request("profile update", function() return profiles:UpdateAsync("p:" .. tostring(id), transform) end) end
	function backend:getMonster(id) return request("monster read", function() return records:GetAsync(recordKey(id)) end) end
	function backend:updateMonster(id, transform) return request("monster update", function() return records:UpdateAsync(recordKey(id), transform) end) end
	function backend:createMonster(record) return self:updateMonster(record.id, function(old) return old or clone(record) end) end
	function backend:listMonsterIds(cursor, limit, partition)
		return request("enumeration", function()
			local prefix = if partition then recordPrefix(partition) else "m:"
			local pages = records:ListKeysAsync(prefix, limit or 12, cursor or "", true)
			local ids = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do table.insert(ids, string.sub(entry.KeyName, 6)) end
			return { ids, if pages.IsFinished or pages.Cursor == "" then nil else pages.Cursor }
		end)
	end
	-- The live list wrapper preserves both result values across pcall retries.
	local enumerate = backend.listMonsterIds
	function backend:listMonsterIds(cursor, limit, partition)
		local result = enumerate(self, cursor, limit, partition)
		return result[1], result[2]
	end
	function backend:presence(id, value, now)
		return request("presence", function()
			if value then presence:SetAsync(tostring(id), value, 90, math.random()) else presence:RemoveAsync(tostring(id)) end
		end)
	end
	function backend:listPresence(now)
		return request("presence sampling", function()
			local entries = presence:GetRangeAsync(Enum.SortDirection.Descending, 100)
			local result = {}
			for _, entry in ipairs(entries) do table.insert(result, { id = entry.key, value = entry.value }) end
			return result
		end)
	end
	function backend:enqueue(id, now) return request("queue hint", function() queue:SetAsync(id, true, 3600, now) end) end
	function backend:removeHint(id) return request("queue removal", function() queue:RemoveAsync(id) end) end
	function backend:listHints(limit)
		return request("queue sampling", function()
			local result = {}
			for _, entry in ipairs(queue:GetRangeAsync(Enum.SortDirection.Ascending, limit or 12)) do table.insert(result, entry.key) end
			return result
		end)
	end
	function backend:lease(name, owner, now, seconds)
		local result = request("worker lease", function()
			return leases:UpdateAsync(name, function(old)
				if old and old.expires > now and old.owner ~= owner then return old end
				return { owner = owner, expires = now + seconds }
			end, seconds + 5)
		end)
		return result and result.owner == owner
	end
	function backend:getCheckpoint(name) return request("checkpoint read", function() return recovery:GetAsync(name) end) end
	function backend:setCheckpoint(name, value) return request("checkpoint update", function() return recovery:UpdateAsync(name, function() return value end) end) end
	function backend:hasBudget(minReads, minUpdates)
		return dataService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) >= (minUpdates or 8)
			and dataService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) >= (minReads or 8)
	end
	return backend
end

return Storage
