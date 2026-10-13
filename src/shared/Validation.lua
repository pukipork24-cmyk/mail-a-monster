--!strict
-- Network shape validation only. Ownership, catalog membership, balances,
-- proximity, timing and custody are checked again by authoritative services.
local Validation = {}

type Predicate = (any) -> boolean
type Schema = { required: { [string]: Predicate }, optional: { [string]: Predicate }? }

local function boundedString(minimum: number, maximum: number): Predicate
	return function(value: any): boolean
		return type(value) == "string" and #value >= minimum and #value <= maximum
			and not string.find(value, "[%c]")
	end
end

local function integer(minimum: number, maximum: number): Predicate
	return function(value: any): boolean
		return type(value) == "number" and value == value and value >= minimum
			and value <= maximum and value % 1 == 0
	end
end

local function oneOf(choices: { string }): Predicate
	local accepted: { [string]: boolean } = {}
	for _, choice in ipairs(choices) do accepted[choice] = true end
	return function(value: any): boolean
		return type(value) == "string" and accepted[value] == true
	end
end

local identifier = boundedString(1, 96)
local itemId = boundedString(1, 48)
local version = integer(0, 2147483647)
local schemas: { [string]: Schema } = {
	Snapshot = { required = {} },
	Hatch = { required = { name = boundedString(1, 24), sequence = integer(0, 2147483647) } },
	Display = { required = { monsterId = identifier, perch = integer(1, 3) } },
	Launch = { required = { monsterId = identifier, plan = boundedString(1, 32), version = version }, optional = { objective = boundedString(1, 32) } },
	Forward = { required = { monsterId = identifier, voyageId = identifier, version = version, souvenirId = itemId } },
	Recall = { required = { monsterId = identifier, voyageId = identifier } },
	ReleaseVisitor = { required = { monsterId = identifier, voyageId = identifier, version = version } },
	ClaimHomecoming = { required = { monsterId = identifier, bookId = identifier } },
	Equip = { required = { monsterId = identifier, souvenirId = itemId } },
	Settings = { required = { key = boundedString(1, 24), value = function(value: any): boolean
		return type(value) == "boolean" or (type(value) == "number" and value == value and value >= 0 and value <= 1)
	end } },
	SkipTutorial = { required = {} },
	ActivityStart = { required = { kind = oneOf({ "sorting", "watering", "letters" }) } },
	ActivityStep = { required = { sessionId = identifier, target = integer(1, 16) } },
	Buy = { required = { itemId = itemId } },
	Place = { required = { anchor = boundedString(1, 16), itemId = boundedString(0, 48) } },
	Style = { required = { kind = oneOf({ "cannon", "mailbox" }), itemId = itemId } },
	ClaimRequest = { required = { requestId = boundedString(1, 32) } },
	ClaimMilestone = { required = { milestoneId = boundedString(1, 32) } },
}

local booleanSettings: { [string]: boolean } = {
	reducedMotion = true, cameraShake = true, shareCountry = true, acceptVisitors = true,
}
local volumeSettings: { [string]: boolean } = { musicVolume = true, sfxVolume = true }

function Validation.validate(action: any, payload: any): (boolean, string?)
	if type(action) ~= "string" or #action > 32 then return false, "Choose a supported action." end
	local schema = schemas[action]
	if not schema then return false, "Choose a supported action." end
	if type(payload) ~= "table" or getmetatable(payload) ~= nil then
		return false, "The request must be a plain table. Please retry."
	end
	-- Exact, flat schemas reject Instances, nested payloads, forged reward data,
	-- arbitrary recipient IDs, arrays, functions and oversized strings.
	for key, value in pairs(payload) do
		if type(key) ~= "string" then return false, "The request contains an unsupported field." end
		local predicate = schema.required[key] or (schema.optional and schema.optional[key])
		if not predicate then return false, "The request contains an unsupported field." end
		if not predicate(value) then return false, "The request contains an invalid value." end
	end
	for key in pairs(schema.required) do
		if rawget(payload, key) == nil then return false, "The request is missing a required field." end
	end
	if action == "Settings" then
		local key, value = payload.key, payload.value
		if booleanSettings[key] then
			if type(value) ~= "boolean" then return false, "This setting needs an on or off value." end
		elseif volumeSettings[key] then
			if type(value) ~= "number" then return false, "Volume must be between zero and one." end
		else
			return false, "That setting is unavailable."
		end
	end
	return true, nil
end

return Validation
