-- Run with: .tools/bin/luau tests/validation.luau
local Validation = require("../src/shared/Validation")
local RateLimiter = require("../src/server/RateLimiter")
local checks = 0
local function expect(condition, label)
	assert(condition, label)
	checks += 1
end
local function valid(action, payload)
	local ok, err = Validation.validate(action, payload)
	expect(ok and err == nil, action .. " should be accepted: " .. tostring(err))
end
local function invalid(action, payload)
	local ok, err = Validation.validate(action, payload)
	expect(not ok and type(err) == "string", tostring(action) .. " should be rejected")
end

local examples = {
	Snapshot = {}, Hatch = { name = "Gerald", sequence = 0 }, Display = { monsterId = "monster-1", perch = 1 }, ClaimMilestone = { milestoneId = "first_suitcase" },
	Launch = { monsterId = "m:123", plan = "ShortHop", objective = "hat", version = 1 },
	Forward = { monsterId = "m:123", voyageId = "v:1", version = 7, souvenirId = "sunhat" },
	Recall = { monsterId = "m:123", voyageId = "v:1" },
	ReleaseVisitor = { monsterId = "m:123", voyageId = "v:1", version = 7 },
	ClaimHomecoming = { monsterId = "m:123", bookId = "book:1" },
	Equip = { monsterId = "m:123", souvenirId = "sunhat" },
	Settings = { key = "shareCountry", value = false }, SkipTutorial = {},
	ActivityStart = { kind = "sorting" }, ActivityStep = { sessionId = "a:1", target = 3 },
	Buy = { itemId = "decor:welcome" }, Place = { anchor = "1", itemId = "welcome" },
	Style = { kind = "cannon", itemId = "classic" }, ClaimRequest = { requestId = "garden" },
}
for action, payload in pairs(examples) do
	valid(action, payload)
	local forged = table.clone(payload)
	forged.reward = 99999
	invalid(action, forged)
	for field in pairs(payload) do
		local nested = table.clone(payload)
		nested[field] = { arbitrary = true }
		invalid(action, nested)
	end
end
valid("Launch", { monsterId = "m", plan = "Practice", version = 1 })
valid("Place", { anchor = "1", itemId = "" })
for _, key in ipairs({ "reducedMotion", "cameraShake", "shareCountry", "acceptVisitors" }) do
	valid("Settings", { key = key, value = true })
	valid("Settings", { key = key, value = false })
	invalid("Settings", { key = key, value = 1 })
end
for _, key in ipairs({ "musicVolume", "sfxVolume" }) do
	for _, value in ipairs({ 0, 0.5, 1 }) do valid("Settings", { key = key, value = value }) end
	for _, value in ipairs({ -0.1, 1.1, math.huge, -math.huge, 0 / 0, true, "1" }) do
		invalid("Settings", { key = key, value = value })
	end
end
invalid("Settings", { key = "admin", value = true })
invalid("Hatch", { name = string.rep("a", 25) })
invalid("Hatch", { name = "Gerald\n" })
invalid("Hatch", { name = "" })
invalid("Hatch", {})
invalid("Hatch", { name = function() end })
invalid("Hatch", { name = coroutine.create(function() end) })
invalid("Snapshot", { [1] = "array" })
invalid("Snapshot", { [false] = 1 })
invalid("Snapshot", setmetatable({}, {}))
invalid("Snapshot", setmetatable({}, { __metatable = false }))
local cycle = {}; cycle.name = cycle
invalid("Hatch", cycle)
for _, bad in ipairs({ false, 0, "payload" }) do invalid("Snapshot", bad) end
invalid("Snapshot", nil)
invalid("Unknown", {})
invalid({}, {})
invalid(nil, {})
invalid(string.rep("A", 100000), {})
invalid("Launch", { monsterId = string.rep("a", 97), plan = "ShortHop" })
invalid("Launch", { monsterId = "m", plan = "ShortHop", recipient = 5 })
invalid("Launch", { monsterId = "m", plan = "ShortHop", objective = "" })
invalid("Forward", { monsterId = "m", voyageId = "v", version = 1, souvenirId = "sunhat", country = "GB" })
for _, bad in ipairs({ -1, 1.5, math.huge, -math.huge, 0 / 0, 2147483648, "1" }) do
	invalid("Forward", { monsterId = "m", voyageId = "v", version = bad, souvenirId = "sunhat" })
end
invalid("ActivityStart", { kind = "grant" })
invalid("ActivityStep", { sessionId = "s", target = 0 })
invalid("ActivityStep", { sessionId = "s", target = 1.5 })
invalid("ActivityStep", { sessionId = "s", target = math.huge })
invalid("ActivityStep", { sessionId = "s", target = 17 })
invalid("Style", { kind = "island", itemId = "classic" })

local limiter = RateLimiter.new(12, 3)
for _ = 1, 12 do expect(limiter:allow(1, 100), "Initial burst is available") end
expect(not limiter:allow(1, 100), "Burst exhaustion blocks spam")
expect(limiter:allow(2, 100), "Players have independent buckets")
expect(not limiter:allow(1, 100.25), "Partial token is insufficient")
expect(limiter:allow(1, 100.5), "Elapsed time refills tokens")
expect(not limiter:allow(1, 100.5), "Fractional remainder cannot grant an action")
expect(not limiter:allow(1, 99), "Clock rollback does not refill")
expect(not limiter:allow(1, 100.5), "Clock rollback does not shift refill baseline")
expect(not limiter:allow(1, math.huge), "Infinite clock is refused")
expect(not limiter:allow(1, 0 / 0), "NaN clock is refused")
for _ = 1, 12 do expect(limiter:allow(1, 200), "Idle refill restores at most one burst") end
expect(not limiter:allow(1, 200), "Idle refill is bounded")
limiter:remove(1)
expect(limiter:allow(1, 200), "Leaving removes the player's bucket")
limiter:clear()
expect(limiter:allow(1, 200), "Clear resets all buckets")
for _, config in ipairs({ { 0, 3 }, { 12, 0 }, { math.huge, 3 }, { 12, 0 / 0 } }) do
	expect(not pcall(RateLimiter.new, config[1], config[2]), "Invalid rate config is rejected")
end
print("PASS: " .. checks .. " network validation and rate-limit checks")
