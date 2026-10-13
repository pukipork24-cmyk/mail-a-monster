--!strict
-- All client requests are intents. The server decides custody, costs and rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("MailAMonster"):WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local MonsterFactory = require(Shared.MonsterFactory)
local W = require(script.Parent.Widgets)
local Theme = require(script.Parent.Theme)
local Effects = require(script.Parent.Effects)

local Controller = {}
Controller.__index = Controller

local function count(map: any): number
	local total = 0
	for _ in pairs(map or {}) do total += 1 end
	return total
end

local function duration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
	if seconds >= 60 then return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60) end
	return tostring(seconds) .. "s"
end

local function pretty(value: any): string
	return tostring(value or "Unknown"):gsub("_", " ")
end

local function copyMonster(monster: any, slots: any): any
	local copy = table.clone(monster)
	copy.slots = table.clone(slots or {})
	return copy
end

local function lastBook(monster: any): any
	local books = monster.books or {}
	return books[#books]
end

local function bookById(monster: any, id: string?): any
	for _, book in ipairs(monster.books or {}) do
		if book.id == id then return book end
	end
	return lastBook(monster)
end

local function tutorialText(profile: any): (string, string)
	local t = profile.tutorial or {}
	if t.skipped or t.claimed then return "", "Collection" end
	if not t.hatched then return "1 / 6 · Meet your little monster. Hatch your free egg!", "Hatch" end
	if not t.visitor then return "2 / 6 · Open your mailbox. Give the NPC practice visitor a souvenir and send a smile.", "Mailbox" end
	if not t.activity then return "3 / 6 · Earn Postage! Try a short postal activity on your island.", "Activities" end
	if not t.practice then return "4 / 6 · Launch your monster on a free Practice Voyage. Three fictional NPC stops, about 75 seconds.", "Collection" end
	return "5 / 6 · Watch your monster come home, then claim your welcome decoration.", "Collection"
end

function Controller.new()
	local self: any = setmetatable({}, Controller)
	self.snapshot = nil
	self.route = ""
	self.args = {}
	self.busy = false
	self.clockReceived = os.clock()
	self.connections = {}
	self.renderCleanups = {}
	self.replayGeneration = 0
	self.selectedName = Catalog.Names[1]
	self.selectedSouvenir = Catalog.SouvenirOrder[1]
	self.selectedObjective = "hat"
	self.selectedAnchor = "1"
	self.selectedDecoration = "welcome"
	self.toastGeneration = 0
	self.seenVisitors = {}
	self.photo = false
	self.remotes = ReplicatedStorage.MailAMonster:WaitForChild("Remotes")
	self:_build()
	return self
end

function Controller:now(): number
	return if self.snapshot then (self.snapshot.serverTime or os.time()) + (os.clock() - self.clockReceived) else os.time()
end

function Controller:settings(): any
	return if self.snapshot then self.snapshot.profile.settings or {} else {}
end

function Controller:monster(id: string?): any
	if not self.snapshot then return nil end
	for _, group in ipairs({ self.snapshot.monsters or {}, self.snapshot.visitors or {} }) do
		for _, monster in ipairs(group) do
			if monster.id == id then return monster end
		end
	end
	return nil
end

function Controller:_build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("MailAMonsterUI")
	if old then old:Destroy() end
	self.gui = W.create("ScreenGui", {
		Name = "MailAMonsterUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 20,
	}, playerGui)
	self.hud = W.create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, self.gui)
	local header = W.create("Frame", { Size = UDim2.new(1, -24, 0, 74), Position = UDim2.fromOffset(12, 6), BackgroundColor3 = Theme.Cream, BorderSizePixel = 0 }, self.hud)
	W.corner(header, 16)
	self.title = W.create("TextLabel", { Size = UDim2.new(0.57, -14, 1, -12), Position = UDim2.fromOffset(14, 6), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 19, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Ink, Text = "MAIL A MONSTER\nLittle monster. Big adventure." }, header)
	self.balance = W.create("TextLabel", { Size = UDim2.new(0.43, -14, 1, -12), Position = UDim2.new(0.57, 0, 0, 6), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Teal, Text = "Opening the post office…" }, header)
	self.simulation = W.create("TextLabel", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 84), BackgroundColor3 = Theme.Lavender, BorderSizePixel = 0, TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Theme.Ink, TextWrapped = true, Visible = false, Text = "Studio simulation — progress is not saved" }, self.hud)
	W.corner(self.simulation, 10)
	self.guidance = W.create("TextButton", { Size = UDim2.new(1, -24, 0, 72), Position = UDim2.fromOffset(12, 122), BackgroundColor3 = Theme.Cream, BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = Theme.Ink, TextWrapped = true, Text = "", Visible = false, Selectable = true }, self.hud)
	W.corner(self.guidance)
	W.padding(self.guidance, 10)
	self.guidance.Activated:Connect(function()
		if self.snapshot then local _, route = tutorialText(self.snapshot.profile) self:open(route) end
	end)
	local nav = W.create("ScrollingFrame", { Size = UDim2.new(0.82, 0, 0, 64), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Theme.Cream, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 3 }, self.hud)
	W.corner(nav)
	W.padding(nav, 7)
	W.list(nav, 7, true)
	for _, entry in ipairs({ { "Monsters", "Collection" }, { "Mailbox", "Mailbox" }, { "Activities", "Activities" }, { "Journal", "Album" }, { "Requests", "Requests" }, { "Shop", "Shop" }, { "Decorate", "Decorations" }, { "Settings", "Settings" }, { "Help", "Tutorial" } }) do
		local button = W.button(nav, entry[1], function() self:open(entry[2]) end, true)
		button.Size = UDim2.fromOffset(112, 48)
	end
	self.shade = W.create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Ink, BackgroundTransparency = 0.52, Visible = false, ZIndex = 10, Active = false }, self.gui)
	self.window = W.create("Frame", { Size = UDim2.fromScale(0.94, 0.82), Position = UDim2.fromScale(0.5, 0.48), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Cream, BorderSizePixel = 0, ZIndex = 11, Visible = false }, self.gui)
	W.corner(self.window, 20)
	W.create("UISizeConstraint", { MaxSize = Vector2.new(850, 900), MinSize = Vector2.new(260, 180) }, self.window)
	self.windowTitle = W.create("TextLabel", { Size = UDim2.new(1, -85, 0, 55), Position = UDim2.fromOffset(18, 0), BackgroundTransparency = 1, Text = "", TextColor3 = Theme.Ink, Font = Enum.Font.GothamBold, TextSize = 22, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left }, self.window)
	local close = W.button(self.window, "×", function() self:close() end, true)
	close.Position, close.Size = UDim2.new(1, -57, 0, 7), UDim2.fromOffset(48, 44)
	self.content = W.create("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -65), Position = UDim2.fromOffset(12, 56), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 5, ScrollBarImageColor3 = Theme.Teal }, self.window)
	self.toast = W.create("TextLabel", { Size = UDim2.new(0.9, 0, 0, 88), Position = UDim2.fromScale(0.5, 0.02), AnchorPoint = Vector2.new(0.5, 0), TextWrapped = true, BackgroundColor3 = Theme.Teal, TextColor3 = Theme.White, Font = Enum.Font.GothamMedium, TextSize = 17, BorderSizePixel = 0, Visible = false, ZIndex = 50 }, self.gui)
	W.create("UISizeConstraint", { MaxSize = Vector2.new(700, 100) }, self.toast)
	W.corner(self.toast)
	W.padding(self.toast, 12)
	self.busyLabel = W.create("TextLabel", { Size = UDim2.new(0.7, 0, 0, 48), Position = UDim2.fromScale(0.5, 0.9), AnchorPoint = Vector2.new(0.5, 1), Text = "Waiting for the post office…", TextWrapped = true, BackgroundColor3 = Theme.Lavender, TextColor3 = Theme.Ink, Font = Enum.Font.GothamMedium, TextSize = 17, Visible = false, ZIndex = 45 }, self.gui)
	W.corner(self.busyLabel)
	self.photoExit = W.button(self.gui, "Exit Photo View · B / Esc", function() self:setPhoto(false) end, true)
	self.photoExit.Size, self.photoExit.Position = UDim2.fromOffset(230, 48), UDim2.fromOffset(12, 12)
	self.photoExit.Visible, self.photoExit.ZIndex = false, 60
end

function Controller:notice(message: string, failure: boolean?)
	self.toastGeneration += 1
	local generation = self.toastGeneration
	self.toast.Text, self.toast.BackgroundColor3 = message, if failure then Theme.Danger else Theme.Teal
	self.toast.Visible = true
	task.delay(if failure then 8 else 5, function()
		if self.toastGeneration == generation then self.toast.Visible = false end
	end)
end

function Controller:_hud()
	if not self.snapshot then return end
	local profile = self.snapshot.profile
	self.balance.Text = tostring(profile.currency or 0) .. " Postage\nCourier level " .. tostring(profile.level or Config.level(profile.xp or 0)) .. "  ·  " .. #self.snapshot.visitors .. "/" .. Config.IncomingCapacity .. " visitors"
	self.simulation.Visible = self.snapshot.simulation == true and not self.photo
	local text = tutorialText(profile)
	self.guidance.Text = text
	self.guidance.Position = UDim2.fromOffset(12, if self.snapshot.simulation then 122 else 86)
	self.guidance.Visible = text ~= "" and self.route == "" and not self.photo
end

function Controller:_snapshot(snapshot: any)
	if type(snapshot) ~= "table" or type(snapshot.profile) ~= "table" then return end
	snapshot.monsters, snapshot.visitors = snapshot.monsters or {}, snapshot.visitors or {}
	local hadSnapshot = self.snapshot ~= nil
	self.snapshot, self.clockReceived = snapshot, os.clock()
	for _, visitor in ipairs(snapshot.visitors) do
		if not self.seenVisitors[visitor.id] and hadSnapshot then
			self:notice((if visitor.voyage and visitor.voyage.practice then "NPC practice visitor" else "A visitor") .. " arrived! Open your mailbox.")
			Effects.mailbox(self:settings())
		end
		self.seenVisitors[visitor.id] = true
	end
	self:_hud()
	self:_audio()
end

function Controller:request(action: string, payload: any?, onSuccess: ((any) -> ())?)
	if self.busy then self:notice("Your last request is still being checked. Please wait a moment.") return end
	self.busy, self.busyLabel.Visible = true, true
	task.spawn(function()
		local ok, response = pcall(function() return self.remotes.Request:InvokeServer(action, payload or {}) end)
		self.busy, self.busyLabel.Visible = false, false
		if not ok or type(response) ~= "table" then
			self:notice("The post office could not be reached. Your last accepted progress is safe; tap Retry or try that action again.", true)
			if not self.snapshot then self:open("Connection") end
			return
		end
		if response.data then self:_snapshot(response.data) end
		if response.ok ~= true then
			self:notice(tostring(response.error or "That action could not be completed. Please refresh and try again."), true)
			if not self.snapshot then self:open("Connection") elseif self.route ~= "Replay" then self:render() end
			return
		end
		if onSuccess then onSuccess(response) elseif self.route ~= "Replay" then self:render() end
	end)
end

function Controller:_audio()
	local settings = self:settings()
	if self.music then self.music.Volume = (settings.musicVolume or 0) * 0.3 end
end

function Controller:setPhoto(enabled: boolean)
	self.photo = enabled
	self.hud.Visible = not enabled
	self.window.Visible = not enabled and self.route ~= ""
	self.shade.Visible = not enabled and self.route ~= "" and self.route ~= "Activity"
	self.photoExit.Visible = enabled
	self.toast.Visible = false
	self:_hud()
end

function Controller:close()
	if self.photo then self:setPhoto(false) return end
	self.route, self.args = "", {}
	self.replayGeneration += 1
	self:render()
end

function Controller:open(route: string, args: any?)
	if self.photo then self:setPhoto(false) end
	self.replayGeneration += 1
	self.route, self.args = route, args or {}
	self:render()
end

function Controller:_clear()
	for _, cleanup in ipairs(self.renderCleanups) do cleanup() end
	self.renderCleanups = {}
	self.content:ClearAllChildren()
	W.padding(self.content, 3)
	W.list(self.content, 12)
end

function Controller:render()
	self:_clear()
	self.window.Visible = self.route ~= "" and not self.photo
	self.shade.Visible = self.window.Visible and self.route ~= "Activity"
	self.window.Size = if self.route == "Activity" then UDim2.new(0.9, 0, 0, 350) else UDim2.fromScale(0.94, 0.82)
	self.window.Position = if self.route == "Activity" then UDim2.new(0.5, 0, 0, 8) else UDim2.fromScale(0.5, 0.48)
	self.window.AnchorPoint = if self.route == "Activity" then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5)
	self:_hud()
	if self.route == "" then return end
	if not self.snapshot then
		self.windowTitle.Text = "Connecting to the post office"
		W.label(self.content, "We are checking your saved progress. If the service is unavailable, progress will not be replaced with a new account.")
		W.button(self.content, "Retry connection", function() self:request("Snapshot", {}, function() self:open("Tutorial") end) end)
		return
	end
	local method = (self :: any)["screen" .. self.route]
	if method then method(self) else self:screenCollection() end
	self.content.CanvasPosition = Vector2.zero
	if UserInputService.GamepadEnabled then
		for _, object in ipairs(self.content:GetDescendants()) do
			if object:IsA("GuiButton") and object.Selectable then GuiService.SelectedObject = object; break end
		end
	end
end

function Controller:screenTutorial()
	self.windowTitle.Text = "Welcome to the postal islands"
	W.label(self.content, Config.Tagline, 22, Theme.Teal)
	local text, route = tutorialText(self.snapshot.profile)
	if text ~= "" then W.button(self.content, text, function() self:open(route) end) end
	for _, instruction in ipairs({
		"1. Hatch a free egg. Pick a name, meet its personality, and explore your island.",
		"2. Open your mailbox. The NPC tutorial visitor is clearly marked. Preview one free souvenir, then forward it from your cannon.",
		"3. Try Parcel Sorting, Flower Watering, or Floating Letters. Follow the marked stations to earn Postage.",
		"4. Send your own monster on a free Practice Voyage. Its three fictional NPC stops take about 75 seconds.",
		"5. Open the homecoming in your collection. Watch or skip the replay, claim your welcome decoration, and decorate your island.",
		"6. A normal voyage costs 20 Postage. Ownership always stays with you. Visitors are temporary guests; giving a souvenir and forwarding is always free.",
	}) do W.label(W.card(self.content), instruction) end
	W.label(self.content, "Move with WASD, thumbstick, or touch controls. Use marked prompts or the bottom menu. M opens your monsters; B opens the mailbox; Esc / controller B closes panels.")
	W.label(self.content, "NPC travel is fictional and never earns human-hop income. If every server is offline, overdue voyages are processed when a server next runs.", 15, Theme.Muted)
	if not self.snapshot.profile.tutorial.skipped and not self.snapshot.profile.tutorial.claimed then
		W.button(self.content, "Skip guidance · keep one-time starter benefits", function()
			self:request("SkipTutorial", {}, function() self:notice("Guidance skipped. Your one-time starter benefits are ready.") self:open("Collection") end)
		end, true)
	end
end

function Controller:screenHatch()
	self.windowTitle.Text = "The hatchery"
	local profile = self.snapshot.profile
	local first = not profile.tutorial.hatched
	W.label(self.content, if first then "Your first egg is free. A new friend is waiting inside!" else "A new random-trait egg costs " .. Config.EggCost .. " earned Postage. All traits are cosmetic.", 20, Theme.Teal)
	W.label(self.content, "Choose a name", 19)
	for _, name in ipairs(Catalog.Names) do
		W.button(self.content, (if self.selectedName == name then "✓ " else "") .. name, function() self.selectedName = name self:render() end, self.selectedName ~= name)
	end
	W.label(W.card(self.content, "Every egg can hatch…"), "Four bodies: Slug, Puff, Sprout, Bean. Six color palettes. Four faces. Curious, Sleepy, Dramatic, or Mischievous personalities. Traits never change earnings.")
	local reason = if (profile.pendingEggs or 0) > 0 then "Previous egg is recovering; refresh shortly" elseif #(profile.owned or self.snapshot.monsters) >= Config.MaxOwnedMonsters then "Collection full" elseif not first and profile.currency < Config.EggCost then "Need " .. (Config.EggCost - profile.currency) .. " more Postage" else nil
	W.button(self.content, if first then "Hatch my free egg" else "Hatch · " .. Config.EggCost .. " Postage", function()
		local oldIds = {}
		for _, monster in ipairs(self.snapshot.monsters) do oldIds[monster.id] = true end
		self:request("Hatch", { name = self.selectedName, sequence = profile.hatchSeq or 0 }, function()
			for _, monster in ipairs(self.snapshot.monsters) do
				if not oldIds[monster.id] then self:open("HatchReveal", { monsterId = monster.id }) return end
			end
			self:open("Collection")
		end)
	end, false, reason)
end

function Controller:screenHatchReveal()
	self.windowTitle.Text = "Special delivery!"
	local monster = self:monster(self.args.monsterId)
	if not monster then self:screenCollection() return end
	local _, model = W.portrait(self.content, monster, 250)
	if model then MonsterFactory.react(model, "happy", self:settings().reducedMotion) end
	W.label(self.content, "Hello, " .. monster.name .. "!", 28, Theme.Teal)
	W.label(self.content, pretty(monster.personality) .. " · " .. pretty(monster.body) .. " · " .. (Catalog.Palettes[monster.palette] and Catalog.Palettes[monster.palette].name or pretty(monster.palette)), 18)
	W.label(self.content, "A little monster with a lifetime of adventures ahead. Its name and ownership stay with you through every voyage.")
	W.pair(self.content, "Meet my visitor", function() self:open("Mailbox") end, "My collection", function() self:open("Collection") end)
end

function Controller:screenCollection()
	self.windowTitle.Text = "Your monster collection"
	local monsters = self.snapshot.monsters
	W.label(self.content, #monsters .. " / " .. Config.MaxOwnedMonsters .. " friends · Permanent ownership, lifetime memories", 16, Theme.Muted)
	W.button(self.content, if not self.snapshot.profile.tutorial.hatched then "Hatch your first friend · FREE" else "Visit hatchery · eggs " .. Config.EggCost .. " Postage", function() self:open("Hatch") end, true)
	if #monsters == 0 then
		W.label(self.content, if (self.snapshot.profile.pendingEggs or 0) > 0 then "Your accepted egg is being safely recovered. Refresh shortly; you do not need to buy it again." else "Your display perches are waiting. Start with your free egg.")
		W.button(self.content, "Refresh collection", function() self:request("Snapshot") end, true)
		return
	end
	for _, monster in ipairs(monsters) do
		local card = W.card(self.content, monster.name)
		W.portrait(card, monster, 155)
		W.label(card, pretty(monster.personality) .. " · " .. (if monster.state == "HOME" then "Home on your island" else "Traveling · " .. pretty(monster.state)), 16)
		W.label(card, (monster.lifetimeHops or 0) .. " lifetime human hops · " .. (monster.voyagesCompleted or 0) .. " completed voyages", 15, Theme.Muted)
		W.label(card, (monster.normalVoyagesCompleted or 0) .. " normal voyages · " .. (monster.practiceVoyagesCompleted or 0) .. " NPC practice voyage", 14, Theme.Muted)
		local pending = nil
		for _, book in ipairs(monster.books or {}) do if not book.claimed then pending = book break end end
		if pending then
			W.button(card, "Open homecoming", function() self:open("Replay", { monsterId = monster.id, bookId = pending.id }) end)
		end
		W.button(card, "Portrait, passport & memories", function() self:open("Monster", { monsterId = monster.id }) end, true)
		if monster.state == "HOME" then W.button(card, "Plan a voyage", function() self:open("Launch", { monsterId = monster.id }) end) end
	end
end

function Controller:screenMonster()
	local monster = self:monster(self.args.monsterId)
	if not monster then self:screenCollection() return end
	self.windowTitle.Text = monster.name .. " · " .. pretty(monster.personality)
	local _, portraitModel = W.portrait(self.content, monster, 230)
	if portraitModel then MonsterFactory.react(portraitModel, "idle", self:settings().reducedMotion) end
	W.label(self.content, "Voyage " .. (monster.voyageNumber or 0) .. " · " .. (monster.lifetimeHops or 0) .. " lifetime human hops · " .. (monster.voyagesCompleted or 0) .. " journeys home")
	W.button(self.content, "Open passport", function() self:open("Passport", { monsterId = monster.id }) end, true)
	if monster.state == "HOME" then
		W.button(self.content, "Plan next voyage", function() self:open("Launch", { monsterId = monster.id }) end)
		W.label(self.content, "Choose a display perch", 20)
		for perch = 1, 3 do
			local selected = (self.snapshot.profile.displaySlots or {})[tostring(perch)] == monster.id
			W.button(self.content, (if selected then "✓ " else "") .. "Display on perch " .. perch, function()
				self:request("Display", { monsterId = monster.id, perch = perch }, function() self:notice(monster.name .. " is on display.") self:render() end)
			end, true)
		end
		W.label(self.content, "Wear an earned souvenir", 20)
		if count(monster.earned) == 0 then W.label(self.content, "Bring home souvenirs to unlock their appearances.", 16, Theme.Muted) end
		for _, id in ipairs(Catalog.SouvenirOrder) do
			if monster.earned and monster.earned[id] then
				local item = Catalog.Souvenirs[id]
				W.button(self.content, item.name .. " · " .. item.slot, function()
					self:request("Equip", { monsterId = monster.id, souvenirId = id }, function() self:notice("Appearance updated on your island.") self:render() end)
				end, true)
			end
		end
	else
		self:_tracking(self.content, monster)
	end
	W.label(self.content, "Recent voyage books", 20)
	if #(monster.books or {}) == 0 then W.label(self.content, "Your first story starts when you launch.", 16, Theme.Muted) end
	for index = #(monster.books or {}), 1, -1 do
		local book = monster.books[index]
		W.button(self.content, "Voyage " .. book.number .. (if book.practice then " · NPC Practice" else " · " .. pretty(book.plan)) .. " · " .. (book.humanHops or 0) .. " human hops", function() self:open("Replay", { monsterId = monster.id, bookId = book.id }) end, true)
	end
	W.button(self.content, "Photo View · hide controls", function() self:setPhoto(true) end, true)
end

function Controller:screenMailbox()
	self.windowTitle.Text = "Your visitor mailbox"
	local visitors = self.snapshot.visitors
	W.label(self.content, #visitors .. " / " .. Config.IncomingCapacity .. " visitor slots · Receiving and forwarding are always free.", 16, Theme.Muted)
	if self:settings().acceptVisitors == false then W.label(self.content, "New visitors are paused in Settings. Existing guests can still be forwarded or returned to the pool.", 17, Theme.Teal) end
	if #visitors == 0 then
		W.label(W.card(self.content, "No visitors just yet"), "Your mailbox will bounce when a traveler arrives. Explore, earn Postage, or send your own monster while you wait.")
		W.button(self.content, "Find an activity", function() self:open("Activities") end)
	elseif #visitors >= Config.IncomingCapacity then
		W.label(self.content, "Your mailbox is full. Forward a visitor to make room. Your own returning monsters always have space.", 16, Theme.Teal)
	end
	for _, monster in ipairs(visitors) do
		local voyage = monster.voyage or {}
		local card = W.card(self.content, monster.name .. (if voyage.practice then " · NPC TUTORIAL VISITOR" else " · Visiting traveler"))
		local _, visitorModel = W.portrait(card, monster, 180)
		if visitorModel then MonsterFactory.react(visitorModel, "startled", self:settings().reducedMotion) end
		W.label(card, "A temporary guest. Its original owner keeps it forever.", 16)
		W.label(card, (voyage.humanHops or 0) .. " human hops · Return in " .. duration((voyage.deadline or self:now()) - self:now()), 15, Theme.Muted)
		W.button(card, "Open parcel & choose souvenir", function() self:open("Visitor", { monsterId = monster.id }) end)
		W.button(card, "Read passport", function() self:open("Passport", { monsterId = monster.id, visitor = true }) end, true)
	end
end

function Controller:screenVisitor()
	local monster = self:monster(self.args.monsterId)
	if not monster or not monster.voyage then self:screenMailbox() return end
	local voyage, profile = monster.voyage, self.snapshot.profile
	self.windowTitle.Text = "A souvenir for " .. monster.name
	W.label(self.content, if voyage.practice then "NPC TUTORIAL VISITOR · A fictional friend learning the postal route." else "A fellow player's visitor · Ownership stays with its original owner.", 18, Theme.Teal)
	local selected = Catalog.Souvenirs[self.selectedSouvenir]
	local slots = table.clone(monster.slots or {})
	if selected and (profile.level or 1) >= selected.level then slots[selected.slot] = selected.id end
	local _, model = W.portrait(self.content, copyMonster(monster, slots), 230)
	if model then MonsterFactory.react(model, "packing", self:settings().reducedMotion) end
	W.label(self.content, "Preview · one gift, always free. Replacing the same visual slot keeps every earlier gift in the passport.", 16, Theme.Muted)
	for _, id in ipairs(Catalog.SouvenirOrder) do
		local souvenir = Catalog.Souvenirs[id]
		W.button(self.content, (if self.selectedSouvenir == id then "✓ " else "") .. souvenir.name .. " · " .. souvenir.slot, function() self.selectedSouvenir = id self:render() end, self.selectedSouvenir ~= id, if profile.level < souvenir.level then "Level " .. souvenir.level else nil)
	end
	local limits = profile.rewardLimits or {}
	if (limits.carrier or 0) >= (limits.carrierLimit or Config.CarrierDailyCap) then
		W.label(self.content, "Daily carrier reward limit reached. You can still forward for free and add to this monster's story.", 17, Theme.Teal)
	else
		W.label(self.content, if voyage.practice then "This NPC tutorial dispatch teaches the loop. It is not a human hop." else "A qualifying human forwarding earns " .. Config.CarrierReward .. " Postage, within your daily limit.", 16, Theme.Muted)
	end
	W.button(self.content, "Attach & fire the cannon · FREE", function()
		self:request("Forward", { monsterId = monster.id, voyageId = voyage.id, version = monster.version, souvenirId = self.selectedSouvenir }, function()
			Effects.dispatch(self:settings())
			self:notice("Souvenir saved. Parcel away! Thanks for sending a smile.")
			self:open("Mailbox")
		end)
	end)
	W.button(self.content, "Read full passport", function() self:open("Passport", { monsterId = monster.id, visitor = true }) end, true)
	W.button(self.content, "Return guest to the courier pool · no reward", function()
		self:request("ReleaseVisitor", { monsterId = monster.id, voyageId = voyage.id, version = monster.version }, function() self:notice("Guest safely returned to the courier pool.") self:open("Mailbox") end)
	end, true, if voyage.tutorial then "Tutorial guest: attach a souvenir" else nil)
end

function Controller:_event(parent: Instance, event: any, index: number)
	local npc = event.kind == "NPC" or event.kind == "npc"
	local card = W.card(parent, string.format("%02d  %s", index, if npc then "NPC · FICTIONAL POSTAL STOP" elseif event.humanHop then "HUMAN COURIER" else pretty(event.kind)))
	W.label(card, event.label or "A new page in the story.", 17)
	if event.souvenirId then
		local item = Catalog.Souvenirs[event.souvenirId]
		W.label(card, "Gift: " .. (if item then item.name else "Souvenir") .. (if item then " · " .. item.slot else ""), 16, Theme.Teal)
	end
	if event.stampId then
		local stamp = Catalog.Stamps[event.stampId]
		W.label(card, "Fictional stamp: " .. (if stamp then stamp.name else pretty(event.stampId)), 15, Theme.Muted)
	end
	if event.country then W.label(card, "Optional courier region: " .. tostring(event.country), 15, Theme.Muted) end
	if event.humanHop then W.label(card, if event.rewardEligible then "Human hop · reward eligible" else "Human hop · no reward credit", 14, Theme.Muted) end
end

function Controller:screenPassport()
	local monster = self:monster(self.args.monsterId)
	if not monster then self:screenCollection() return end
	local voyage = if self.args.bookId then bookById(monster, self.args.bookId) else monster.voyage or lastBook(monster)
	self.windowTitle.Text = monster.name .. "'s passport"
	W.portrait(self.content, monster, 190)
	W.label(self.content, "Voyage " .. (if self.args.bookId and voyage then voyage.number else monster.voyageNumber or 0) .. " · " .. (if self.args.bookId then "Completed memory" else pretty(monster.state)), 21, Theme.Teal)
	if voyage then
		W.label(self.content, (if voyage.practice then "NPC PRACTICE VOYAGE · " else "") .. (voyage.humanHops or 0) .. " human hops", 18)
		if voyage.deadline then W.label(self.content, "Returns in " .. duration(voyage.deadline - self:now()) .. " or at the target of " .. (voyage.hopTarget or 0) .. " human hops.", 16) end
		W.label(self.content, "An illustrated postal story. Fictional island stamps are not an exact real-world route.", 15, Theme.Muted)
		for index, event in ipairs(voyage.events or {}) do self:_event(self.content, event, index) end
	else
		W.label(self.content, "A fresh passport. Its first adventure is waiting!")
	end
	W.button(self.content, if self.args.visitor then "Choose a souvenir" else "Back to monster", function() self:open(if self.args.visitor then "Visitor" else "Monster", { monsterId = monster.id }) end)
end

function Controller:_tracking(parent: Instance, monster: any)
	local voyage = monster.voyage
	if not voyage then W.label(parent, "Your monster is being safely prepared. Refresh shortly.") return end
	local card = W.card(parent, if voyage.practice then "NPC Practice Voyage" else "Out on an adventure")
	local clockLabel = W.label(card, "", 18, Theme.Teal)
	local alive = true
	table.insert(self.renderCleanups, function() alive = false end)
	task.spawn(function()
		while alive and clockLabel.Parent do
			clockLabel.Text = (voyage.humanHops or 0) .. " / " .. (voyage.hopTarget or 0) .. " human hops · " .. duration(voyage.deadline - self:now()) .. " until return"
			task.wait(1)
		end
	end)
	W.label(card, if voyage.practice then "Three unmistakably fictional NPC postal stops. No normal human-hop income." else "Random eligible couriers across the experience. Up to three fictional NPC postcards keep the story moving when human traffic is quiet.", 16)
	local eligibleAt = voyage.startedAt + Config.EarlyReturnSeconds
	W.button(card, "Request early return", function()
		self:request("Recall", { monsterId = monster.id, voyageId = voyage.id }, function() self:notice("Early return accepted. Earned rewards are preserved.") self:open("Collection") end)
	end, true, if self:now() < eligibleAt then "Available in " .. duration(eligibleAt - self:now()) else nil)
	W.button(card, "Refresh tracking", function() self:request("Snapshot") end, true)
end

function Controller:screenVoyages()
	self.windowTitle.Text = "Voyage board"
	W.label(self.content, "Choose a monster from your collection to plan a voyage, or follow an adventure already underway.")
	for _, monster in ipairs(self.snapshot.monsters) do
		local card = W.card(self.content, monster.name)
		if monster.state == "HOME" then
			W.button(card, "Plan voyage", function() self:open("Launch", { monsterId = monster.id }) end)
		else
			self:_tracking(card, monster)
			W.button(card, "Read passport", function() self:open("Passport", { monsterId = monster.id }) end, true)
		end
	end
	if #self.snapshot.monsters == 0 then W.button(self.content, "Hatch your first monster", function() self:open("Hatch") end) end
end

function Controller:screenLaunch()
	local monster = self:monster(self.args.monsterId)
	if not monster then self:screenVoyages() return end
	self.windowTitle.Text = "A big adventure for " .. monster.name
	if monster.state ~= "HOME" then self:_tracking(self.content, monster) return end
	W.portrait(self.content, monster, 180)
	local profile = self.snapshot.profile
	local outgoing = 0
	for _, owned in ipairs(self.snapshot.monsters) do if owned.state ~= "HOME" then outgoing += 1 end end
	local capacity = Config.OutgoingCapacity + (if profile.level >= Config.ExtraOutgoingLevel then 1 else 0)
	W.label(self.content, outgoing .. " / " .. capacity .. " outgoing voyages · A third slot unlocks at level " .. Config.ExtraOutgoingLevel, 16, Theme.Muted)
	W.label(self.content, "Choose a little goal", 21)
	for _, id in ipairs({ "hat", "families" }) do
		local objective = Config.Objectives[id]
		W.button(self.content, (if self.selectedObjective == id then "✓ " else "") .. objective.name, function() self.selectedObjective = id self:render() end, self.selectedObjective ~= id)
	end
	W.label(self.content, Config.Objectives[self.selectedObjective].description .. " Reward: " .. Config.Objectives[self.selectedObjective].reward .. " Postage (normal voyages).", 16, Theme.Muted)
	for _, id in ipairs(Config.PlanOrder) do
		local plan = Config.Plans[id]
		local card = W.card(self.content, plan.name .. (if plan.practice then " · NPC PRACTICE" else ""))
		W.label(card, if plan.practice then "Free once. Three fictional NPC stops, about 75 seconds. No normal hop income." else plan.cost .. " Postage deposit · " .. plan.hops .. " human hops OR " .. duration(plan.seconds) .. ". Deposit refunded at homecoming; eligible human hops add " .. Config.OwnerHopReward .. " each.", 17)
		local reason = if outgoing >= capacity then "Outgoing slots full" elseif profile.level < plan.level then "Unlocks at level " .. plan.level elseif profile.currency < plan.cost then "Need " .. (plan.cost - profile.currency) .. " more Postage" elseif plan.practice and profile.tutorial.practice then "Practice completed" else nil
		W.button(card, "Launch " .. plan.name .. (if plan.cost > 0 then " · " .. plan.cost .. " Postage" else " · FREE"), function()
			self:request("Launch", { monsterId = monster.id, plan = id, objective = self.selectedObjective, version = monster.version }, function()
				Effects.dispatch(self:settings())
				self:notice(monster.name .. " is on the way! Open its passport for updates.")
				self:open("Monster", { monsterId = monster.id })
			end)
		end, false, reason)
	end
end

function Controller:screenReplay()
	local monster = self:monster(self.args.monsterId)
	local book = monster and bookById(monster, self.args.bookId)
	if not monster or not book then self:screenCollection() return end
	self.windowTitle.Text = "Welcome home, " .. monster.name
	W.label(self.content, if book.practice then "NPC PRACTICE MEMORY · Fictional postal islands" else "An illustrated memory · Not an exact geographic route", 16, Theme.Teal)
	local stage = W.card(self.content)
	local portrait, model = W.portrait(stage, copyMonster(monster, book.slotsBefore), 210)
	local caption = W.label(stage, "Packing a little suitcase…", 21)
	local progress = W.label(stage, "Departure", 15, Theme.Muted)
	local routeRow = W.row(stage, 32)
	for index = 1, math.min(8, #(book.events or {}) + 2) do
		local dot = W.create("TextLabel", { Size = UDim2.new(1 / math.min(8, #(book.events or {}) + 2), -8, 1, 0), BackgroundColor3 = Theme.Sky, Text = tostring(index), Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Theme.Ink }, routeRow)
		W.corner(dot, 16)
	end
	local paused = false
	local pauseButton: TextButton
	pauseButton = W.button(self.content, "Pause replay", function() paused = not paused pauseButton.Text = if paused then "Resume replay" else "Pause replay" end, true)
	W.button(self.content, "Skip to homecoming summary", function() self:open("Summary", { monsterId = monster.id, bookId = book.id }) end)
	W.button(self.content, "Always prefer an instant summary · enable Reduced Motion", function()
		self:request("Settings", { key = "reducedMotion", value = true }, function() self:open("Summary", { monsterId = monster.id, bookId = book.id }) end)
	end, true)
	if self:settings().reducedMotion then self:open("Summary", { monsterId = monster.id, bookId = book.id }) return end
	local generation = self.replayGeneration
	local events = book.events or {}
	local frames = { { label = "Departure · A little monster, a big adventure.", slots = table.clone(book.slotsBefore or {}) } }
	local slots = table.clone(book.slotsBefore or {})
	for _, event in ipairs(events) do
		local item = event.souvenirId and Catalog.Souvenirs[event.souvenirId]
		if item then slots[item.slot] = item.id end
		table.insert(frames, { label = (if event.kind == "NPC" then "NPC · " else "") .. (event.label or pretty(event.kind)) .. (if item then "\n+ " .. item.name else ""), slots = table.clone(slots) })
	end
	table.insert(frames, { label = "Home sweet home. Look how far you've come!", slots = book.slotsAfter or slots })
	task.spawn(function()
		for index, frame in ipairs(frames) do
			if self.replayGeneration ~= generation or not caption.Parent then return end
			caption.Text = frame.label
			progress.Text = "Memory " .. index .. " / " .. #frames .. " · " .. (book.humanHops or 0) .. " human hops total"
			if model and model.Parent then MonsterFactory.applySouvenirs(model, frame.slots) MonsterFactory.react(model, if index == #frames then "homecoming" else "happy", false) end
			local elapsed = 0
			while elapsed < 15 / #frames do
				if self.replayGeneration ~= generation or not portrait.Parent then return end
				task.wait(0.1)
				if not paused then elapsed += 0.1 end
			end
		end
		if self.replayGeneration == generation then self:open("Summary", { monsterId = monster.id, bookId = book.id }) end
	end)
end

function Controller:screenSummary()
	local monster = self:monster(self.args.monsterId)
	local book = monster and bookById(monster, self.args.bookId)
	if not monster or not book then self:screenCollection() return end
	self.windowTitle.Text = "A suitcase full of stories"
	local before = W.card(self.content, "Before the adventure")
	W.portrait(before, copyMonster(monster, book.slotsBefore), 165)
	local after = W.card(self.content, "Welcome home, " .. monster.name)
	local _, model = W.portrait(after, copyMonster(monster, book.slotsAfter), 215)
	if model then MonsterFactory.react(model, "homecoming", self:settings().reducedMotion) end
	W.label(after, (if book.practice then "NPC PRACTICE · " else "") .. (book.humanHops or 0) .. " human hops · " .. duration((book.returnedAt or self:now()) - book.startedAt) .. " away", 18)
	local payout = W.card(self.content, "Postage statement")
	W.label(payout, "Dispatch deposit returned: " .. (book.deposit or (if book.practice then 0 else 20)) .. "\nEligible human hops: " .. (book.rewardHops or 0) .. " × " .. Config.OwnerHopReward .. " = " .. ((book.rewardHops or 0) * Config.OwnerHopReward) .. "\nVoyage objective: " .. (book.objectiveReward or 0) .. "\nTotal: " .. (book.payout or 0) .. " Postage", 18)
	W.label(payout, "Rewards are saved once. Replaying a memory never pays again.", 15, Theme.Muted)
	local discoveries = W.card(self.content, "Souvenirs discovered on this journey")
	local seen = {}
	for _, event in ipairs(book.events or {}) do
		if event.souvenirId and not seen[event.souvenirId] then
			seen[event.souvenirId] = true
			local item = Catalog.Souvenirs[event.souvenirId]
			W.label(discoveries, "✓ " .. (if item then item.name else "Souvenir"), 17)
		end
	end
	if count(seen) == 0 then W.label(discoveries, "A quiet trip is still a story. Your dispatch deposit comes home.", 16) end
	if not book.claimed then
		W.button(self.content, if book.practice then "Welcome home · claim starter decoration" else "Welcome home · acknowledge rewards", function()
			self:request("ClaimHomecoming", { monsterId = monster.id, bookId = book.id }, function() self:notice(if book.practice then "Welcome pennant unlocked! Decorate your island." else "Homecoming saved. Welcome back!") self:render() end)
		end)
	else
		W.label(self.content, "✓ Homecoming claimed", 18, Theme.Success)
	end
	W.pair(self.content, "Display & dress up", function() self:open("Monster", { monsterId = monster.id }) end, "Next adventure", function() self:open("Launch", { monsterId = monster.id }) end)
	W.button(self.content, "Replay this memory", function() self:open("Replay", { monsterId = monster.id, bookId = book.id }) end, true)
	W.button(self.content, "Read every passport entry", function() self:open("Passport", { monsterId = monster.id, bookId = book.id }) end, true)
	W.button(self.content, "Photo View · show your island", function() self:setPhoto(true) end, true)
end

function Controller:plot(): Instance?
	local world = workspace:FindFirstChild("MailAMonsterWorld")
	local plots = world and world:FindFirstChild("Plots")
	local index = Players.LocalPlayer:GetAttribute("MAMPlotIndex")
	return plots and plots:FindFirstChild("Plot" .. tostring(index))
end

function Controller:screenActivities()
	self.windowTitle.Text = "A little postal work"
	W.label(self.content, "Short activities earn Postage while your monsters are away. Walk to a marked station on your own island to begin.", 18)
	if self.snapshot.activity then W.button(self.content, "Resume current activity", function() self:open("Activity") end) end
	for _, kind in ipairs({ "sorting", "watering", "letters" }) do
		local activity = Config.Activities[kind]
		local card = W.card(self.content, activity.name)
		W.label(card, (if kind == "sorting" then "Match each parcel's printed shape to Circle, Triangle, or Star. Color is a bonus clue." elseif kind == "watering" then "Follow the numbered flower beds and give each one a patient watering." else "Follow an easy route and collect each numbered floating letter. No difficult jumps.") .. "\nAbout " .. (activity.steps * activity.stepSeconds) .. " seconds · " .. activity.reward .. " Postage", 17)
		W.button(card, "Start " .. activity.name, function()
			self:request("ActivityStart", { kind = kind }, function() self:open("Activity") end)
		end, false, if self.snapshot.activity and self.snapshot.activity.kind ~= kind then "Finish current activity first" else nil)
	end
end

function Controller:_markObjective(activity: any)
	local plot = self:plot()
	if not plot or activity.kind == "sorting" then return end
	for _, part in ipairs(plot:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("MAMActivity") == activity.kind and part:GetAttribute("MAMIndex") == activity.target then
			local highlight = W.create("Highlight", { Adornee = part, FillColor = Theme.Coral, OutlineColor = Theme.White, FillTransparency = 0.55, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, part)
			local billboard = W.create("BillboardGui", { Adornee = part, Size = UDim2.fromOffset(150, 45), StudsOffsetWorldSpace = Vector3.new(0, 4, 0), AlwaysOnTop = true }, self.gui)
			W.create("TextLabel", { Size = UDim2.fromScale(1, 1), Text = "NEXT · " .. activity.target, TextColor3 = Theme.White, BackgroundColor3 = Theme.Teal, Font = Enum.Font.GothamBold, TextSize = 19 }, billboard)
			table.insert(self.renderCleanups, function() highlight:Destroy() billboard:Destroy() end)
			return
		end
	end
end

function Controller:screenActivity()
	local activity = self.snapshot.activity
	if not activity then self:screenActivities() return end
	local definition = Config.Activities[activity.kind]
	self.windowTitle.Text = definition.name
	W.label(self.content, "Step " .. activity.index .. " / " .. activity.total .. " · " .. activity.reward .. " Postage at completion", 17, Theme.Teal)
	local timer = W.label(self.content, "", 16)
	local baseText = if activity.kind == "watering" then "Water flower bed " .. activity.target elseif activity.kind == "letters" then "Collect floating letter " .. activity.target else ""
	if activity.kind == "sorting" then
		local targetLabel = definition.labels[activity.target] or pretty(activity.target)
		W.label(self.content, "This parcel is marked: " .. targetLabel, 23)
	else
		W.label(self.content, baseText .. ". Follow the highlighted NEXT marker on your island.", 18)
	end
	local buttons = {}
	local function send(target: number)
		self:request("ActivityStep", { sessionId = activity.sessionId, target = target }, function()
			if self.snapshot.activity then self:open("Activity") else self:notice("Activity complete! " .. activity.reward .. " Postage earned. Thank you, courier.") self:open("Activities") end
		end)
	end
	if activity.kind == "sorting" then
		for index, label in ipairs(definition.labels) do
			local button = W.button(self.content, label .. " bin", function() send(index) end)
			table.insert(buttons, { button = button, text = label .. " bin" })
		end
	else
		local button = W.button(self.content, baseText, function() send(activity.target) end)
		table.insert(buttons, { button = button, text = baseText })
	end
	W.label(self.content, "You can close this panel to move, then reopen Activities to resume. The server checks your position and each step's timing.", 14, Theme.Muted)
	self:_markObjective(activity)
	local alive = true
	table.insert(self.renderCleanups, function() alive = false end)
	task.spawn(function()
		while alive and timer.Parent do
			local remaining = activity.readyAt - self:now()
			timer.Text = if remaining > 0 then "Preparing… " .. duration(remaining) else "Ready! Complete this step at its marked station."
			for _, item in ipairs(buttons) do
				item.button.Active, item.button.Selectable, item.button.AutoButtonColor = remaining <= 0, remaining <= 0, remaining <= 0
				item.button.BackgroundColor3 = if remaining > 0 then Theme.Line else Theme.Teal
				item.button.TextColor3 = if remaining > 0 then Theme.Ink else Theme.White
				item.button.Text = item.text .. (if remaining > 0 then " · " .. duration(remaining) else "")
			end
			task.wait(0.25)
		end
	end)
end

function Controller:screenRequests()
	self.windowTitle.Text = "Today's postal requests"
	W.label(self.content, "Three daily requests, with an activity alternative for every one. New requests arrive each UTC day. No streaks and no missed-day penalties.", 17)
	local requests = self.snapshot.profile.daily or {}
	if #requests == 0 then W.label(self.content, "Today's request board is loading. Refresh in a moment.") end
	for _, request in ipairs(requests) do
		local card = W.card(self.content, request.title or request.name or request.id)
		W.label(card, request.description or "Help the postal islands.", 17)
		W.label(card, tostring(request.progressA or 0) .. " / " .. tostring(request.targetA or 1) .. "  OR  " .. tostring(request.progressB or 0) .. " / " .. tostring(request.targetB or 1) .. "\nReward: " .. tostring(request.reward or Config.RequestPostage) .. " Postage", 18, Theme.Teal)
		W.button(card, if request.claimed then "✓ Reward claimed" else "Claim request reward", function() self:request("ClaimRequest", { requestId = request.id }, function() self:notice("Request reward saved. Thanks for helping!") self:render() end) end, false, if request.claimed then "Complete" elseif not request.complete then "Finish either objective" else nil)
	end
	local limits = self.snapshot.profile.rewardLimits or {}
	local card = W.card(self.content, "Daily hop reward limits")
	W.label(card, "Carrier rewards: " .. (limits.carrier or 0) .. " / " .. (limits.carrierLimit or Config.CarrierDailyCap) .. " handoffs\nOwner hop bonuses: " .. (limits.owner or 0) .. " / " .. (limits.ownerLimit or Config.OwnerDailyHopCap) .. " credited hops", 17)
	W.label(card, "Historical human hops keep counting after these reward limits. NPC stories and automatic forwarding never earn normal hop income.", 15, Theme.Muted)
	W.button(self.content, "Refresh request board", function() self:request("Snapshot") end, true)
end

function Controller:screenAlbum()
	self.windowTitle.Text = "The souvenir journal"
	local profile = self.snapshot.profile
	W.label(self.content, count(profile.album) .. " / " .. #Catalog.SouvenirOrder .. " souvenirs · " .. count(profile.stamps) .. " / " .. #Catalog.StampOrder .. " fictional stamps", 18, Theme.Teal)
	W.label(self.content, "Discover designs through your deliveries and homecomings. Every stamp below belongs to a fictional postal island.", 16, Theme.Muted)
	for _, milestone in ipairs(Config.Milestones) do
		local progress = count(profile[milestone.stat])
		local claimed = (profile.milestones or {})[milestone.id] == true
		local item = Catalog.Shop[milestone.cosmetic]
		local card = W.card(self.content, milestone.name)
		W.label(card, math.min(progress, milestone.target) .. " / " .. milestone.target .. " · Reward: " .. item.name .. " + " .. milestone.xp .. " courier XP", 16)
		W.button(card, if claimed then "✓ Collection reward claimed" else "Claim collection reward", function()
			self:request("ClaimMilestone", { milestoneId = milestone.id }, function() self:notice("Collection reward saved. A little more color for your island!") self:render() end)
		end, false, if claimed then "Complete" elseif progress < milestone.target then "Keep collecting" else nil)
	end
	for _, id in ipairs(Catalog.SouvenirOrder) do
		local item, context = Catalog.Souvenirs[id], (profile.album or {})[id]
		local card = W.card(self.content, (if context then "✓ " else "? ") .. item.name)
		W.label(card, item.slot .. " · Free courier choice at level " .. item.level .. "\n" .. item.description, 16)
		W.button(card, if context then "View discovery" else "Undiscovered · view design", function() self:open("Discovery", { itemId = id, kind = "souvenir" }) end, true)
	end
	W.label(self.content, "Fictional postal stamps", 22)
	for _, id in ipairs(Catalog.StampOrder) do
		local item, context = Catalog.Stamps[id], (profile.stamps or {})[id]
		W.button(self.content, (if context then "✓ " else "? ") .. "[" .. item.symbol .. "] " .. item.name, function() self:open("Discovery", { itemId = id, kind = "stamp" }) end, true)
	end
end

function Controller:screenDiscovery()
	local stamp = self.args.kind == "stamp"
	local item = (if stamp then Catalog.Stamps else Catalog.Souvenirs)[self.args.itemId]
	if not item then self:screenAlbum() return end
	self.windowTitle.Text = item.name
	local record = (if stamp then self.snapshot.profile.stamps else self.snapshot.profile.album) or {}
	local context = record[item.id]
	if stamp then
		local card = W.card(self.content, "[ " .. item.symbol .. " ]")
		W.label(card, item.name .. "\nFictional postal destination", 28, Theme.Teal)
	else
		local monster = self.snapshot.monsters[1] or { name = "A little preview", body = Catalog.Bodies[1], palette = Catalog.PaletteOrder[1], face = Catalog.Faces[1], personality = "Curious", seed = 1 }
		W.portrait(self.content, copyMonster(monster, { [item.slot] = item.id }), 230)
		W.label(self.content, item.description, 21)
		W.label(self.content, item.slot .. " · Unlocks as a free courier choice at level " .. item.level, 16, Theme.Muted)
	end
	if context then
		W.label(self.content, "✓ Discovered through real gameplay", 19, Theme.Success)
		W.label(self.content, if type(context) == "table" then tostring(context.context or context.label or "A voyage memory") else "A voyage memory", 18)
		if type(context) == "table" and type(context.at) == "number" then W.label(self.content, "Recorded " .. os.date("!%Y-%m-%d", context.at) .. " UTC", 15, Theme.Muted) end
	else W.label(self.content, "Not discovered yet. Send a monster on an adventure or help a visitor to add it to your journal.", 18) end
	W.button(self.content, "Back to journal", function() self:open("Album") end, true)
end

function Controller:_assetPreview(parent: Instance, id: string)
	local assets = ReplicatedStorage.MailAMonster:FindFirstChild("Assets")
	local decorations = assets and assets:FindFirstChild("Decorations")
	local template = decorations and (decorations:FindFirstChild(id) or decorations:FindFirstChild("Decoration_" .. id))
	if not template or not template:IsA("Model") then return end
	local viewport = W.create("ViewportFrame", { Size = UDim2.new(1, 0, 0, 190), BackgroundColor3 = Theme.Sky, BorderSizePixel = 0, Ambient = Color3.fromRGB(205, 205, 205), LightColor = Theme.White, LightDirection = Vector3.new(-1, -1, -1) }, parent)
	W.corner(viewport)
	local world = W.create("WorldModel", {}, viewport)
	local model = template:Clone()
	model:PivotTo(CFrame.new())
	model.Parent = world
	local box, size = model:GetBoundingBox()
	local target = box.Position
	local distance = math.max(7, math.max(size.X, size.Y, size.Z) * 2)
	local camera = W.create("Camera", { CFrame = CFrame.lookAt(target + Vector3.new(distance * 0.7, distance * 0.45, -distance), target), FieldOfView = 35 }, viewport)
	viewport.CurrentCamera = camera
end

function Controller:screenShop()
	self.windowTitle.Text = "The cozy cosmetic shop"
	local profile = self.snapshot.profile
	W.label(self.content, profile.currency .. " Postage · Cosmetics are purchased with earned Postage.", 20, Theme.Teal)
	W.label(self.content, "Decorations and finishes change your island's look. Courier levels unlock choices, never matching priority or earnings.", 16)
	local ids = {}
	for id in pairs(Catalog.Shop) do table.insert(ids, id) end
	table.sort(ids, function(a, b) if Catalog.Shop[a].cost ~= Catalog.Shop[b].cost then return Catalog.Shop[a].cost < Catalog.Shop[b].cost end return a < b end)
	for _, id in ipairs(ids) do
		local item = Catalog.Shop[id]
		local owned = profile.cosmetics and profile.cosmetics[id] == true
		local card = W.card(self.content, item.name)
		if item.kind == "decoration" then self:_assetPreview(card, item.assetId) end
		W.label(card, pretty(item.kind) .. " · " .. item.cost .. " Postage · Level " .. item.level, 16, Theme.Muted)
		if owned then
			W.label(card, "✓ Owned", 17, Theme.Success)
			W.button(card, if item.kind == "decoration" then "Choose a display anchor" else "Use this " .. item.kind .. " style", function()
				if item.kind == "decoration" then self.selectedDecoration = item.assetId self:open("Decorations")
				else self:request("Style", { kind = item.kind, itemId = item.assetId }, function() self:notice("Your " .. item.kind .. " style is ready.") self:render() end) end
			end, true)
		else
			local reason = if profile.level < item.level then "Level " .. item.level elseif profile.currency < item.cost then "Need " .. (item.cost - profile.currency) .. " more Postage" else nil
			W.button(card, "Buy · " .. item.cost .. " Postage", function() self:request("Buy", { itemId = id }, function() self:notice(item.name .. " added to your cosmetics.") self:render() end) end, false, reason)
		end
	end
end

function Controller:_decorationGhost(id: string, anchorId: string)
	local plot = self:plot()
	local anchors = plot and plot:FindFirstChild("DecorationAnchors")
	local anchor = anchors and anchors:FindFirstChild("Anchor" .. anchorId)
	local assets = ReplicatedStorage.MailAMonster:FindFirstChild("Assets")
	local decorations = assets and assets:FindFirstChild("Decorations")
	local template = decorations and (decorations:FindFirstChild(id) or decorations:FindFirstChild("Decoration_" .. id))
	if not anchor or not anchor:IsA("BasePart") or not template or not template:IsA("Model") then return end
	local ghost = template:Clone()
	ghost.Name = "LocalDecorationPreview"
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("BasePart") then part.Transparency = math.max(part.Transparency, 0.45) part.CanCollide, part.CanTouch, part.CanQuery = false, false, false end
	end
	ghost:PivotTo(CFrame.new(anchor.Position))
	ghost.Parent = workspace
	table.insert(self.renderCleanups, function() ghost:Destroy() end)
end

function Controller:screenDecorations()
	self.windowTitle.Text = "Make your island feel like home"
	local profile = self.snapshot.profile
	W.label(self.content, "Choose one of your island's eight fixed anchors, preview an owned decoration, then place or replace it. Only you can edit your island.", 17)
	W.label(self.content, "1. Choose an anchor", 21)
	for index = 1, Config.AnchorCount do
		local id = tostring(index)
		local installed = (profile.placements or {})[id]
		local definition = installed and Catalog.Decorations[installed]
		W.button(self.content, (if id == self.selectedAnchor then "✓ " else "") .. "Anchor " .. id .. " · " .. (if definition then definition.name else "Empty"), function() self.selectedAnchor = id self:render() end, id ~= self.selectedAnchor)
	end
	W.label(self.content, "2. Choose a decoration", 21)
	local owned = {}
	for _, id in ipairs(Catalog.DecorationOrder) do if (profile.cosmetics or {})["decor:" .. id] then table.insert(owned, id) end end
	if #owned == 0 then
		W.label(self.content, "Finish your Practice Voyage for a welcome pennant, or visit the cosmetic shop.")
		W.button(self.content, "Visit cosmetic shop", function() self:open("Shop") end)
		return
	end
	if not (profile.cosmetics or {})["decor:" .. self.selectedDecoration] then self.selectedDecoration = owned[1] end
	for _, id in ipairs(owned) do
		W.button(self.content, (if id == self.selectedDecoration then "✓ " else "") .. Catalog.Decorations[id].name, function() self.selectedDecoration = id self:render() end, id ~= self.selectedDecoration)
	end
	local preview = W.card(self.content, "Preview · " .. Catalog.Decorations[self.selectedDecoration].name)
	self:_assetPreview(preview, self.selectedDecoration)
	W.label(preview, "The translucent preview marks anchor " .. self.selectedAnchor .. " on your island. Save it below.", 16)
	self:_decorationGhost(self.selectedDecoration, self.selectedAnchor)
	W.button(self.content, "Place / replace at anchor " .. self.selectedAnchor, function()
		self:request("Place", { anchor = self.selectedAnchor, itemId = self.selectedDecoration }, function() self:notice("Decoration saved on your island.") self:render() end)
	end)
	W.button(self.content, "Remove decoration at anchor " .. self.selectedAnchor, function()
		self:request("Place", { anchor = self.selectedAnchor, itemId = "" }, function() self:notice("Anchor cleared. You still own the decoration.") self:render() end)
	end, true, if not (profile.placements or {})[self.selectedAnchor] then "Already empty" else nil)
end

function Controller:screenSettings()
	self.windowTitle.Text = "A comfortable little adventure"
	local settings = self:settings()
	for _, entry in ipairs({
		{ "reducedMotion", "Reduced motion", "Use instant homecoming summaries and gentle visual feedback." },
		{ "cameraShake", "Cannon camera shake", "Optional movement for accepted cannon launches. Reduced motion takes priority." },
		{ "shareCountry", "Share a coarse country / region stamp", "Opt in to a broad region code obtained by Roblox on the server. No precise location; sharing is optional and never affects rewards." },
		{ "acceptVisitors", "Accept new visitors", "Turning this off pauses new assignments. Existing guests remain forwardable or can be returned to the pool." },
	}) do
		local key, title, description = entry[1], entry[2], entry[3]
		local card = W.card(self.content, title)
		W.label(card, description, 16)
		W.button(card, if settings[key] then "ON · tap to turn off" else "OFF · tap to turn on", function() self:request("Settings", { key = key, value = not settings[key] }) end, not settings[key])
	end
	for _, entry in ipairs({ { "musicVolume", "Music volume" }, { "sfxVolume", "Sound effects volume" } }) do
		local key, title = entry[1], entry[2]
		local card = W.card(self.content, title .. " · " .. math.floor((settings[key] or 0) * 100) .. "%")
		for _, level in ipairs({ 0, 0.5, 1 }) do
			W.button(card, (if level == 0 then "Mute" else tostring(level * 100) .. "%"), function() self:request("Settings", { key = key, value = level }) end, (settings[key] or 0) ~= level)
		end
	end
	W.label(self.content, "This build uses visual cues for every important event. Optional music and effects stay silent until permitted audio is configured.", 15, Theme.Muted)
	W.button(self.content, "Photo View · hide normal HUD", function() self:setPhoto(true) end, true)
end

function Controller:_prompt(prompt: ProximityPrompt)
	local action = prompt:GetAttribute("MAMAction")
	if type(action) ~= "string" then return end
	local kind, target = prompt:GetAttribute("MAMKind"), prompt:GetAttribute("MAMTarget")
	if action == "ActivityStart" and type(kind) == "string" then
		self:request("ActivityStart", { kind = kind }, function() self:open("Activity") end)
	elseif action == "Decorations" then
		if type(target) == "string" then self.selectedAnchor = target end
		self:open("Decorations")
	elseif action == "Launch" then
		self:open("Voyages")
	elseif action == "Collection" and type(target) == "string" and self:monster(target) then
		self:open("Monster", { monsterId = target })
	elseif action == "Mailbox" and type(target) == "string" and self:monster(target) then
		self:open("Visitor", { monsterId = target })
	else self:open(action) end
end

function Controller:start()
	table.insert(self.connections, self.remotes.Update.OnClientEvent:Connect(function(snapshot)
		local old = self.snapshot
		self:_snapshot(snapshot)
		if not self.snapshot or self.busy or self.route == "Replay" then return end
		local changed = not old or #old.visitors ~= #self.snapshot.visitors or #old.monsters ~= #self.snapshot.monsters
		if old then
			if old.profile.currency ~= self.snapshot.profile.currency or old.profile.xp ~= self.snapshot.profile.xp
				or (old.profile.requests and old.profile.requests.day) ~= (self.snapshot.profile.requests and self.snapshot.profile.requests.day) then changed = true end
			for index, monster in ipairs(self.snapshot.monsters) do
				local previous = old.monsters[index]
				if not previous or previous.version ~= monster.version or previous.state ~= monster.state then changed = true end
				if previous and (previous.voyage and previous.voyage.rewardHops) ~= (monster.voyage and monster.voyage.rewardHops) then changed = true end
				if previous and previous.state ~= "HOME" and monster.state == "HOME" then self:notice(monster.name .. " is home! Open your collection for a homecoming replay.") end
			end
			if (old.activity and old.activity.index) ~= (self.snapshot.activity and self.snapshot.activity.index) then changed = true end
		end
		if changed and self.route ~= "" then self:render() end
	end))
	table.insert(self.connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == nil or player == Players.LocalPlayer then self:_prompt(prompt) end
	end))
	ContextActionService:BindAction("MAMClosePanel", function(_, state)
		if state == Enum.UserInputState.Begin and (self.route ~= "" or self.photo) then self:close() return Enum.ContextActionResult.Sink end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("MAMMonsters", function(_, state)
		if state == Enum.UserInputState.Begin then self:open("Collection") end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M)
	ContextActionService:BindAction("MAMMailbox", function(_, state)
		if state == Enum.UserInputState.Begin then self:open("Mailbox") end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B)
	if Config.Audio.Music ~= "" then
		self.music = W.create("Sound", { Name = "PostalIslandMusic", SoundId = Config.Audio.Music, Looped = true, Volume = 0 }, SoundService)
		self.music:Play()
	end
	self:open("Connection")
	self:request("Snapshot", {}, function()
		local text = tutorialText(self.snapshot.profile)
		if text ~= "" then self:open("Tutorial") else self:close() end
	end)
end

function Controller:destroy()
	self.replayGeneration += 1
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	for _, cleanup in ipairs(self.renderCleanups) do cleanup() end
	for _, name in ipairs({ "MAMClosePanel", "MAMMonsters", "MAMMailbox" }) do ContextActionService:UnbindAction(name) end
	if self.music then self.music:Destroy() end
	self.gui:Destroy()
end

return Controller
