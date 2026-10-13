--!strict
-- Every balance/timing constant lives here. Development controls stay server-side.
local Config = {
	Title = "MAIL A MONSTER",
	Tagline = "Little monster. Big adventure. Send a smile.",
	SchemaVersion = 1,
	MaxPlayers = 8,
	StartingPostage = 40,
	EggCost = 80,
	MaxOwnedMonsters = 12,
	IncomingCapacity = 3,
	OutgoingCapacity = 2,
	ExtraOutgoingLevel = 5,
	CarrierReward = 5,
	OwnerHopReward = 5,
	CarrierDailyCap = 20,
	OwnerDailyHopCap = 40,
	HoldSeconds = 24 * 60 * 60,
	EarlyReturnSeconds = 10 * 60,
	NpcInterval = 5 * 60,
	MaxNpcPostcards = 3,
	PracticeSeconds = 75,
	PracticeNpcInterval = 20,
	DispatchCooldown = 10,
	WorkerInterval = 10,
	PresenceTTL = 90,
	LeaseSeconds = 25,
	RecoveryBatchSize = 12,
	RecoveryInterval = 30,
	BackgroundReadReserve = 40,
	BackgroundWriteReserve = 20,
	MaxEvents = 24,
	BookRetention = 10,
	MaxPendingOperations = 48,
	LevelXP = { 0, 20, 50, 90, 140, 200, 275, 365, 470, 590 },
	ForwardXP = 5,
	ActivityXP = 4,
	ActivitySessionSeconds = 600,
	ActivityDistance = 14,
	RequestXP = 2,
	HomecomingXP = 8,
	ObjectivePostage = 5,
	RequestPostage = 10,
	AnchorCount = 8,
	InteractionDistance = 24,
	ActionBurst = 12,
	ActionsPerSecond = 3,
	Plans = {
		ShortHop = { id = "ShortHop", name = "Short Hop", cost = 20, hops = 3, seconds = 6 * 60 * 60, level = 1 },
		GrandTour = { id = "GrandTour", name = "Grand Tour", cost = 20, hops = 5, seconds = 24 * 60 * 60, level = 3 },
		Expedition = { id = "Expedition", name = "Expedition", cost = 20, hops = 8, seconds = 48 * 60 * 60, level = 6 },
		Practice = { id = "Practice", name = "Practice Voyage", cost = 0, hops = 0, seconds = 75, level = 1, practice = true },
	},
	PlanOrder = { "Practice", "ShortHop", "GrandTour", "Expedition" },
	Activities = {
		sorting = { id = "sorting", name = "Parcel Sorting", steps = 6, stepSeconds = 5, reward = 8, labels = { "Circle", "Triangle", "Star" } },
		watering = { id = "watering", name = "Postal Flower Watering", steps = 4, stepSeconds = 8, reward = 8 },
		letters = { id = "letters", name = "Floating Letter Collecting", steps = 6, stepSeconds = 5, reward = 8 },
	},
	Objectives = {
		hat = { id = "hat", name = "Bring home a hat", description = "Receive a hat, or collect three fictional NPC postcards.", reward = 5 },
		families = { id = "families", name = "A colorful suitcase", description = "Collect two souvenir families, or three fictional NPC postcards.", reward = 5 },
	},
	-- All requests have activity alternatives. No streak or missed-day penalties.
	Requests = {
		{ id = "helping", name = "A helping hand", description = "Forward 2 visitors OR complete 3 sorting rounds", stat = "forwards", target = 2, alternative = "sorting", alternativeTarget = 3 },
		{ id = "garden", name = "Postcard garden", description = "Complete 2 watering rounds OR 3 activities", stat = "watering", target = 2, alternative = "activities", alternativeTarget = 3 },
		{ id = "letters", name = "Letters to the sky", description = "Complete 2 letter routes OR forward 3 visitors", stat = "letters", target = 2, alternative = "forwards", alternativeTarget = 3 },
		{ id = "rounds", name = "Postal all-rounder", description = "Complete 4 activities OR 2 sorting rounds", stat = "activities", target = 4, alternative = "sorting", alternativeTarget = 2 },
		{ id = "care", name = "Special delivery", description = "Forward 3 visitors OR complete 2 watering rounds", stat = "forwards", target = 3, alternative = "watering", alternativeTarget = 2 },
	},
	Milestones = {
		{ id = "first_suitcase", name = "A suitcase of smiles", stat = "album", target = 3, cosmetic = "decor:planter", xp = 8 },
		{ id = "stamp_collector", name = "Postcards from the clouds", stat = "stamps", target = 6, cosmetic = "decor:lantern", xp = 8 },
		{ id = "monster_garden", name = "A growing monster garden", stat = "owned", target = 4, cosmetic = "decor:bench", xp = 8 },
	},
	-- Optional sound is deliberately absent until permitted asset IDs are verified.
	Audio = { Music = "", Mail = "", Launch = "", Return = "" },
}

function Config.level(xp: number): number
	local level = 1
	for i, threshold in ipairs(Config.LevelXP) do
		if xp >= threshold then level = i end
	end
	return level
end

function Config.day(now: number): number
	return math.floor(now / 86400)
end

function Config.dailyRequests(now: number)
	local selected = {}
	local day = Config.day(now)
	for i = 1, 3 do table.insert(selected, Config.Requests[(day + i - 1) % #Config.Requests + 1]) end
	return selected
end

return Config
