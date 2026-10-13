--!strict
-- All persistent changes use canonical conditional updates. Activity objectives are
-- issued by the server; a client can request a step, never submit a completion.
local GameplayService = {}
GameplayService.__index = GameplayService

local function failure(message)
	return { ok = false, error = message }
end

local function success()
	return { ok = true }
end

local function boundedString(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= maximum
end

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function collectionCount(profile, stat)
	local amount = 0
	for _ in pairs(profile[stat] or {}) do amount += 1 end
	return amount
end

local function resetDay(profile, day)
	if type(profile.requests) ~= "table" or (profile.requests.day or -1) < day then
		profile.requests = { day = day, counters = {}, claimed = {} }
	end
	-- An old worker must never roll the board back and reopen paid claims.
	if profile.requests.day > day then return nil end
	profile.requests.counters = profile.requests.counters or {}
	profile.requests.claimed = profile.requests.claimed or {}
	return profile.requests
end

function GameplayService.new(voyages, world, options)
	options = options or {}
	local config, catalog = options.config, options.catalog
	if not config or not catalog then
		if script then
			local shared = game:GetService("ReplicatedStorage"):WaitForChild("MailAMonster"):WaitForChild("Shared")
			config = config or require(shared.Config)
			catalog = catalog or require(shared.Catalog)
		else
			config = config or require("../shared/Config")
			catalog = catalog or require("../shared/Catalog")
		end
	end
	local self = setmetatable({}, GameplayService)
	self.voyages, self.world = voyages, world
	self.storage, self.clock = voyages.storage, voyages.clock
	self.config, self.catalog = config, catalog
	self.sessions = {}
	self.distance = options.distance
	self.idFactory = options.idFactory
	self.sequence = 0
	return self
end

function GameplayService:_id(userId)
	self.sequence += 1
	if self.idFactory then return self.idFactory(userId, self.sequence) end
	return game:GetService("HttpService"):GenerateGUID(false)
end

function GameplayService:_level(profile)
	return self.config.level(profile.xp or 0)
end

function GameplayService:_profile(userId)
	local ok, profile = pcall(function() return self.storage:getProfile(tostring(userId)) end)
	if not ok or not profile then return nil end
	return profile
end

function GameplayService:_update(userId, transform)
	local ok, profile = pcall(function()
		return self.storage:updateProfile(tostring(userId), transform)
	end)
	if not ok then return nil end
	-- A cancelled UpdateAsync may return either nil or the previous record.
	return profile
end

function GameplayService:_near(player, kind, index)
	local position = self.world:getActivityPosition(player, kind, index)
	if not position then return false end
	local distance
	if self.distance then
		distance = self.distance(player, position)
	else
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		distance = (root.Position - position).Magnitude
	end
	return finite(distance) and distance <= self.config.ActivityDistance
end

function GameplayService:getActivity(userId)
	local session = self.sessions[tostring(userId)]
	if not session then return nil end
	if self.clock.now() >= session.expiresAt then
		self.sessions[tostring(userId)] = nil
		return nil
	end
	return {
		sessionId = session.sessionId, kind = session.kind,
		index = session.index, total = session.total, target = session.targets[session.index],
		startedAt = session.startedAt, readyAt = session.readyAt,
		expiresAt = session.expiresAt, reward = session.reward,
	}
end

function GameplayService:playerLeaving(userId)
	self.sessions[tostring(userId)] = nil
end

function GameplayService:_start(player, payload)
	if not boundedString(payload.kind, 16) then return failure("Choose an island activity.") end
	local definition = self.config.Activities[payload.kind]
	if not definition then return failure("Choose Parcel Sorting, Flower Watering, or Letter Collecting.") end
	local id = tostring(player.UserId)
	local existing = self:getActivity(id)
	if existing then
		if existing.kind == payload.kind then return success() end
		return failure("Finish your current activity first.")
	end
	if not self:_profile(id) then return failure("Your saved profile is unavailable. Please retry.") end
	if not self:_near(player, payload.kind, 1) then
		return failure("Walk to the first marked activity station to begin.")
	end
	local now = self.clock.now()
	local targets = {}
	for index = 1, definition.steps do
		if payload.kind == "sorting" then
			local labels = definition.labels
			-- The sequence is issued by this server and cannot be selected by a client.
			targets[index] = ((index + self.sequence) % #labels) + 1
		else
			targets[index] = index
		end
	end
	local sessionId, kind = self:_id(id), payload.kind
	-- A new server reservation fences every older server's delayed completion.
	-- This bounded record never makes an old receipt payable again.
	local reserved = self:_update(id, function(current)
		if not current then return nil end
		current.activitySession = { id = sessionId, kind = kind, startedAt = now, complete = false }
		return current
	end)
	if not reserved or not reserved.activitySession or reserved.activitySession.id ~= sessionId then
		return failure("This activity could not be started. Please retry.")
	end
	self.sessions[id] = {
		sessionId = sessionId, kind = kind, index = 1,
		total = definition.steps, targets = targets, reward = definition.reward,
		startedAt = now, readyAt = now + definition.stepSeconds,
		expiresAt = now + self.config.ActivitySessionSeconds, busy = false,
	}
	return success()
end

function GameplayService:_step(player, payload)
	if not boundedString(payload.sessionId, 128) then return failure("That activity session is invalid.") end
	local id = tostring(player.UserId)
	local public = self:getActivity(id)
	local session = self.sessions[id]
	if not public or payload.sessionId ~= session.sessionId then
		return failure("This activity session ended. Start again at its first station.")
	end
	if session.busy then return failure("Your activity reward is still being saved. Please retry shortly.") end
	if payload.target ~= session.targets[session.index] then
		return failure("Choose the matching label or visit the next numbered objective.")
	end
	local now = self.clock.now()
	if now < session.readyAt then return failure("Give this step a moment, then try again.") end
	local locationIndex = if session.kind == "sorting" then 1 else session.index
	if not self:_near(player, session.kind, locationIndex) then
		return failure("Move closer to your marked objective to complete this step.")
	end
	if session.index < session.total then
		session.index += 1
		session.readyAt = now + self.config.Activities[session.kind].stepSeconds
		return success()
	end
	-- Keep the completed final step available on storage failure. The stable
	-- receipt prevents an acknowledged-or-not retry from paying twice.
	session.busy = true
	local receipt, kind, reward = session.sessionId, session.kind, session.reward
	local day = math.floor(now / 86400)
	local xp = self.config.ActivityXP
	local profile = self:_update(id, function(current)
		if not current then return nil end
		if not current.activitySession or current.activitySession.id ~= receipt then return nil end
		if current.activitySession.complete then return current end
		current.activitySession.complete = true
		current.currency += reward
		current.xp = (current.xp or 0) + xp
		current.stats = current.stats or {}
		current.stats.activities = (current.stats.activities or 0) + 1
		current.stats[kind] = (current.stats[kind] or 0) + 1
		current.tutorial = current.tutorial or {}
		current.tutorial.activity = true
		local requests = resetDay(current, day)
		if requests then
			requests.counters.activities = (requests.counters.activities or 0) + 1
			requests.counters[kind] = (requests.counters[kind] or 0) + 1
		end
		return current
	end)
	session.busy = false
	if not profile or not profile.activitySession or profile.activitySession.id ~= receipt
		or not profile.activitySession.complete then
		local fresh = self:_profile(id)
		if fresh and (not fresh.activitySession or fresh.activitySession.id ~= receipt) then
			self.sessions[id] = nil
			return failure("A newer activity replaced this session. Start again at the first station.")
		end
		return failure("Post office storage is unavailable. Retry this final step to claim your reward.")
	end
	self.sessions[id] = nil
	return { ok = true, effect = { kind = "activity", postage = reward } }
end

function GameplayService:getDaily(profile)
	local day = math.floor(self.clock.now() / 86400)
	local counters, claimed = {}, {}
	if profile.requests and profile.requests.day == day then
		counters = profile.requests.counters or {}
		claimed = profile.requests.claimed or {}
	end
	local definitions, result = self.config.dailyRequests(self.clock.now()), {}
	for _, definition in ipairs(definitions) do
		local progressA = counters[definition.stat] or 0
		local progressB = counters[definition.alternative] or 0
		table.insert(result, {
			id = definition.id, title = definition.name, description = definition.description,
			reward = self.config.RequestPostage, progressA = progressA, targetA = definition.target,
			progressB = progressB, targetB = definition.alternativeTarget,
			complete = progressA >= definition.target or progressB >= definition.alternativeTarget,
			claimed = claimed[definition.id] == true,
		})
	end
	return result
end

function GameplayService:_claimRequest(player, payload)
	if not boundedString(payload.requestId, 64) then return failure("Choose a request from today's board.") end
	local profile = self:_profile(player.UserId)
	if not profile then return failure("Your saved profile is unavailable. Please retry.") end
	local selected
	for _, request in ipairs(self:getDaily(profile)) do
		if request.id == payload.requestId then selected = request end
	end
	if not selected then return failure("That request is not on today's board.") end
	if selected.claimed then return success() end
	if not selected.complete then return failure("Complete either goal on this request before claiming it.") end
	local definition
	for _, request in ipairs(self.config.Requests) do
		if request.id == selected.id then definition = request end
	end
	local day = math.floor(self.clock.now() / 86400)
	local committed = self:_update(player.UserId, function(current)
		if not current then return nil end
		local requests = resetDay(current, day)
		if not requests then return nil end
		if requests.claimed[definition.id] then return current end
		if (requests.counters[definition.stat] or 0) < definition.target
			and (requests.counters[definition.alternative] or 0) < definition.alternativeTarget then return nil end
		requests.claimed[definition.id] = true
		current.currency += self.config.RequestPostage
		current.xp = (current.xp or 0) + self.config.RequestXP
		return current
	end)
	if not committed or not committed.requests or committed.requests.day ~= day
		or not committed.requests.claimed[definition.id] then
		return failure("This request could not be saved. Please retry.")
	end
	return success()
end

function GameplayService:_milestone(player, payload)
	local definition = nil
	for _, milestone in ipairs(self.config.Milestones) do if milestone.id == payload.milestoneId then definition = milestone end end
	if not definition then return failure("Choose a milestone from your collection journal.") end
	local profile = self:_update(player.UserId, function(current)
		if not current then return nil end
		current.milestones = current.milestones or {}
		if current.milestones[definition.id] then return current end
		if collectionCount(current, definition.stat) < definition.target then return nil end
		current.milestones[definition.id] = true
		current.cosmetics[definition.cosmetic] = true
		current.xp = (current.xp or 0) + definition.xp
		return current
	end)
	if not profile or not profile.milestones or not profile.milestones[definition.id] then
		return failure("Complete this collection milestone first, then retry its reward.")
	end
	return success()
end

function GameplayService:_settings(player, payload)
	local booleanSettings = {
		reducedMotion = true, cameraShake = true, shareCountry = true, acceptVisitors = true,
	}
	if not boundedString(payload.key, 32) then return failure("That setting is unavailable.") end
	if booleanSettings[payload.key] then
		if type(payload.value) ~= "boolean" then return failure("Choose on or off for this setting.") end
	elseif payload.key == "musicVolume" or payload.key == "sfxVolume" then
		if not finite(payload.value) or payload.value < 0 or payload.value > 1 then
			return failure("Volume must be between zero and one.")
		end
	else return failure("That setting is unavailable.") end
	local key, value = payload.key, payload.value
	local profile = self:_update(player.UserId, function(current)
		if not current then return nil end
		current.settings = current.settings or {}
		current.settings[key] = value
		return current
	end)
	if not profile or not profile.settings or profile.settings[key] ~= value then
		return failure("Your setting could not be saved. Please retry.")
	end
	return success()
end

function GameplayService:_buy(player, payload)
	if not boundedString(payload.itemId, 64) then return failure("Choose an item from the shop.") end
	local item = self.catalog.Shop[payload.itemId]
	if not item then return failure("That item is not in the Postage shop.") end
	local initial = self:_profile(player.UserId)
	if not initial then return failure("Your saved profile is unavailable. Please retry.") end
	if initial.cosmetics and initial.cosmetics[payload.itemId] then return success() end
	if self:_level(initial) < item.level then return failure("Reach courier level " .. item.level .. " to unlock this item.") end
	if initial.currency < item.cost then return failure("You need " .. item.cost .. " Postage for this item.") end
	local itemId = payload.itemId
	local profile = self:_update(player.UserId, function(current)
		if not current then return nil end
		current.cosmetics = current.cosmetics or {}
		if current.cosmetics[itemId] then return current end
		if self:_level(current) < item.level or current.currency < item.cost then return nil end
		current.currency -= item.cost
		current.cosmetics[itemId] = true
		return current
	end)
	if not profile or not profile.cosmetics or not profile.cosmetics[itemId] then
		return failure("The purchase could not be saved. Check your balance and retry.")
	end
	return success()
end

function GameplayService:_place(player, payload)
	if type(payload.anchor) ~= "string" or not string.match(payload.anchor, "^[1-8]$")
		or type(payload.itemId) ~= "string" or #payload.itemId > 64 then
		return failure("Choose one of your island's eight decoration anchors.")
	end
	local plot = self.world:getPlot(player)
	if not plot or tostring(plot.ownerId) ~= tostring(player.UserId) then
		return failure("Only the owner can decorate this island.")
	end
	local item = self.catalog.Decorations[payload.itemId]
	if payload.itemId ~= "" and not item then
		return failure("Choose an owned island decoration.")
	end
	local anchor, itemId = payload.anchor, payload.itemId
	local profile = self:_update(player.UserId, function(current)
		if not current then return nil end
		if itemId ~= "" and (not current.cosmetics or not current.cosmetics["decor:" .. itemId]) then return nil end
		current.placements = current.placements or {}
		current.placements[anchor] = if itemId == "" then nil else itemId
		return current
	end)
	local expected = if itemId == "" then nil else itemId
	if not profile or not profile.placements or profile.placements[anchor] ~= expected then
		return failure("This decoration could not be placed. Check ownership and retry.")
	end
	return success()
end

function GameplayService:_style(player, payload)
	if (payload.kind ~= "cannon" and payload.kind ~= "mailbox") or not boundedString(payload.itemId, 64) then
		return failure("Choose a cannon finish or mailbox style.")
	end
	local item = self.catalog.Shop[payload.kind .. ":" .. payload.itemId]
	if not item or item.kind ~= payload.kind then return failure("That style does not fit this object.") end
	local kind, itemId = payload.kind, payload.itemId
	local profile = self:_update(player.UserId, function(current)
		if not current or not current.cosmetics or not current.cosmetics[kind .. ":" .. itemId] then return nil end
		current[kind] = itemId
		return current
	end)
	if not profile or profile[kind] ~= itemId then return failure("Own this style before equipping it, then retry.") end
	return success()
end

function GameplayService:_equip(player, payload)
	if not boundedString(payload.monsterId, 128) or not boundedString(payload.souvenirId, 64) then
		return failure("Choose a home monster and one of its earned appearances.")
	end
	local souvenir = self.catalog.Souvenirs[payload.souvenirId]
	if not souvenir then return failure("That souvenir design is unavailable.") end
	local ownerId, itemId = tostring(player.UserId), payload.souvenirId
	local ok, monster = pcall(function()
		return self.storage:updateMonster(payload.monsterId, function(current)
			if not current or tostring(current.ownerId) ~= ownerId or current.state ~= "HOME"
				or not current.earned or not current.earned[itemId] then return nil end
			current.slots = current.slots or {}
			if current.slots[souvenir.slot] ~= itemId then
				current.slots[souvenir.slot] = itemId
				current.version += 1
			end
			return current
		end)
	end)
	if not ok or not monster or tostring(monster.ownerId) ~= ownerId or monster.state ~= "HOME"
		or not monster.earned or not monster.earned[itemId] or monster.slots[souvenir.slot] ~= itemId then
		return failure("Only your home monster can equip a souvenir it earned on a voyage.")
	end
	return success()
end

function GameplayService:_display(player, payload)
	if not boundedString(payload.monsterId, 96) or not finite(payload.perch)
		or payload.perch % 1 ~= 0 or payload.perch < 1 or payload.perch > 3 then
		return failure("Choose a home monster and display perch 1, 2, or 3.")
	end
	local ownerId = tostring(player.UserId)
	local ok, monster = pcall(function() return self.storage:getMonster(payload.monsterId) end)
	if not ok or not monster or monster.ownerId ~= ownerId or monster.state ~= "HOME" then
		return failure("Only your own home monster can be selected for display.")
	end
	local perch, monsterId = tostring(payload.perch), payload.monsterId
	local profile = self:_update(ownerId, function(current)
		if not current then return nil end
		local owned = false
		for _, id in ipairs(current.owned or {}) do if id == monsterId then owned = true end end
		if not owned then return nil end
		current.displaySlots = current.displaySlots or {}
		for key, id in pairs(current.displaySlots) do if id == monsterId then current.displaySlots[key] = nil end end
		current.displaySlots[perch] = monsterId
		return current
	end)
	if not profile or not profile.displaySlots or profile.displaySlots[perch] ~= monsterId then
		return failure("Your display choice could not be saved. Please retry.")
	end
	return success()
end

function GameplayService:handle(player, action, payload)
	if not player or not finite(player.UserId) or type(payload) ~= "table" then
		return failure("This request is malformed.")
	end
	if action == "ActivityStart" then return self:_start(player, payload)
	elseif action == "ActivityStep" then return self:_step(player, payload)
	elseif action == "ClaimRequest" then return self:_claimRequest(player, payload)
	elseif action == "ClaimMilestone" then return self:_milestone(player, payload)
	elseif action == "Settings" then return self:_settings(player, payload)
	elseif action == "Buy" then return self:_buy(player, payload)
	elseif action == "Place" then return self:_place(player, payload)
	elseif action == "Style" then return self:_style(player, payload)
	elseif action == "Display" then return self:_display(player, payload)
	elseif action == "Equip" then return self:_equip(player, payload) end
	return failure("That action is unavailable.")
end

return GameplayService
