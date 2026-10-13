--!strict
-- Per-player token bucket. Call before validation so malformed requests count.
-- Use a monotonic server clock (os.clock), and remove buckets on PlayerRemoving.
local RateLimiter = {}
type Bucket = { tokens: number, last: number }

function RateLimiter.new(burst: number?, rate: number?)
	local capacity = burst or 12
	local refillRate = rate or 3
	assert(capacity == capacity and capacity > 0 and capacity < math.huge, "Invalid action burst")
	assert(refillRate == refillRate and refillRate > 0 and refillRate < math.huge, "Invalid action rate")
	local buckets: { [string]: Bucket } = {}
	local limiter = {}
	function limiter:allow(userId: number | string, now: number): boolean
		if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge then return false end
		local key = tostring(userId)
		local bucket = buckets[key]
		if not bucket then
			bucket = { tokens = capacity, last = now }
			buckets[key] = bucket
		end
		-- A clock correction cannot mint tokens or shift the baseline backwards.
		if now > bucket.last then
			bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.last) * refillRate)
			bucket.last = now
		end
		if bucket.tokens < 1 then return false end
		bucket.tokens -= 1
		return true
	end
	function limiter:remove(userId: number | string)
		buckets[tostring(userId)] = nil
	end
	function limiter:clear()
		table.clear(buckets)
	end
	return limiter
end

return RateLimiter
