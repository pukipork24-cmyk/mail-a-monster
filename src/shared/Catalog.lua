--!strict
-- Original, locally generated art only. IDs are stable save-data keys.
local Catalog = {}
Catalog.Names = { "Gerald", "Pickle", "Noodle", "Miso", "Wobble", "Peep", "Biscuit", "Mochi", "Puddle", "Sprout", "Tumble", "Pip" }
Catalog.Bodies = { "slug", "puff", "sprout", "bean" }
Catalog.Faces = { "smile", "sleepy", "wink", "surprised" }
Catalog.Personalities = { "Curious", "Sleepy", "Dramatic", "Mischievous" }
Catalog.PaletteOrder = { "cream", "teal", "coral", "lavender", "sky", "lemon" }
Catalog.Palettes = {
	cream = { name = "Vanilla cream", rgb = { 255, 231, 187 } },
	teal = { name = "Lagoon teal", rgb = { 92, 196, 177 } },
	coral = { name = "Peach postcard", rgb = { 255, 143, 133 } },
	lavender = { name = "Lavender cloud", rgb = { 181, 162, 226 } },
	sky = { name = "Sky blue", rgb = { 126, 197, 235 } },
	lemon = { name = "Lemon stamp", rgb = { 247, 215, 107 } },
}
Catalog.SouvenirOrder = { "sunhat", "postcap", "crown", "sproutcap", "bow", "satchel", "scarf", "wings", "starpatch", "heartpatch", "freckles", "cloudpatch" }
Catalog.Souvenirs = {
	sunhat = { id = "sunhat", name = "Sunny straw hat", slot = "hat", family = "hat", level = 1, rgb = { 247, 215, 107 }, description = "A little shade for a big adventure." },
	postcap = { id = "postcap", name = "Postmaster cap", slot = "hat", family = "hat", level = 1, rgb = { 57, 153, 155 }, description = "Officially unofficial postal business." },
	crown = { id = "crown", name = "Paper crown", slot = "hat", family = "hat", level = 3, rgb = { 255, 172, 114 }, description = "Royalty of the sorting room." },
	sproutcap = { id = "sproutcap", name = "Traveling sprout", slot = "hat", family = "hat", level = 5, rgb = { 122, 197, 119 }, description = "A harmless leafy hairdo." },
	bow = { id = "bow", name = "Parcel bow", slot = "accessory", family = "accessory", level = 1, rgb = { 244, 134, 153 }, description = "Every monster is a gift." },
	satchel = { id = "satchel", name = "Mini mail satchel", slot = "accessory", family = "accessory", level = 2, rgb = { 190, 132, 83 }, description = "Room for a very tiny letter." },
	scarf = { id = "scarf", name = "Cloud-knit scarf", slot = "accessory", family = "accessory", level = 3, rgb = { 176, 153, 226 }, description = "For chilly journeys above the clouds." },
	wings = { id = "wings", name = "Paper wings", slot = "accessory", family = "accessory", level = 6, rgb = { 237, 239, 218 }, description = "Folded for style, not flight." },
	starpatch = { id = "starpatch", name = "Gold star patch", slot = "patch", family = "patch", level = 1, rgb = { 250, 208, 95 }, description = "A gold star for showing up." },
	heartpatch = { id = "heartpatch", name = "Heart stamp", slot = "patch", family = "patch", level = 2, rgb = { 245, 121, 142 }, description = "A small reminder that you are loved." },
	freckles = { id = "freckles", name = "Confetti freckles", slot = "patch", family = "patch", level = 4, rgb = { 149, 129, 207 }, description = "A reversible sprinkle of celebration." },
	cloudpatch = { id = "cloudpatch", name = "Cloud stamp", slot = "patch", family = "patch", level = 5, rgb = { 186, 226, 247 }, description = "A cloud you can take home." },
}
Catalog.StampOrder = { "teacup", "button", "cloudberry", "puddle", "moonbun", "pillow", "tangerine", "moss", "windmill", "peppermint", "paperboat", "starling" }
Catalog.Stamps = {
	teacup = { id = "teacup", name = "Teacup Cay", symbol = "TC" },
	button = { id = "button", name = "Button Bay", symbol = "BB" },
	cloudberry = { id = "cloudberry", name = "Cloudberry Quay", symbol = "CQ" },
	puddle = { id = "puddle", name = "Puddle Post", symbol = "PP" },
	moonbun = { id = "moonbun", name = "Moonbun Isle", symbol = "MI" },
	pillow = { id = "pillow", name = "Pillow Point", symbol = "PL" },
	tangerine = { id = "tangerine", name = "Tangerine Terrace", symbol = "TT" },
	moss = { id = "moss", name = "Moss & Mail", symbol = "MM" },
	windmill = { id = "windmill", name = "Windmill Wharf", symbol = "WW" },
	peppermint = { id = "peppermint", name = "Peppermint Pier", symbol = "PM" },
	paperboat = { id = "paperboat", name = "Paperboat Port", symbol = "PB" },
	starling = { id = "starling", name = "Starling Station", symbol = "SS" },
}
Catalog.DecorationOrder = { "welcome", "planter", "bench", "lantern", "mushrooms", "birdbath", "windchime", "arch", "fountain", "telescope", "balloons", "statue" }
Catalog.Decorations = {
	welcome = { id = "welcome", name = "Welcome pennant", cost = 50, level = 1, rgb = { 92, 196, 177 } },
	planter = { id = "planter", name = "Postal daisies", cost = 50, level = 1, rgb = { 255, 180, 145 } },
	bench = { id = "bench", name = "Cloud bench", cost = 75, level = 1, rgb = { 184, 214, 230 } },
	lantern = { id = "lantern", name = "Letter lantern", cost = 80, level = 2, rgb = { 247, 215, 107 } },
	mushrooms = { id = "mushrooms", name = "Mushroom trio", cost = 100, level = 2, rgb = { 255, 143, 133 } },
	birdbath = { id = "birdbath", name = "Stamp birdbath", cost = 110, level = 2, rgb = { 126, 197, 235 } },
	windchime = { id = "windchime", name = "Envelope chimes", cost = 130, level = 3, rgb = { 181, 162, 226 } },
	arch = { id = "arch", name = "Postal archway", cost = 150, level = 3, rgb = { 92, 196, 177 } },
	fountain = { id = "fountain", name = "Teacup fountain", cost = 175, level = 4, rgb = { 126, 197, 235 } },
	telescope = { id = "telescope", name = "Voyage telescope", cost = 200, level = 4, rgb = { 220, 173, 112 } },
	balloons = { id = "balloons", name = "Welcome balloons", cost = 250, level = 5, rgb = { 255, 143, 133 } },
	statue = { id = "statue", name = "Golden courier", cost = 300, level = 6, rgb = { 247, 215, 107 } },
}
Catalog.CannonOrder = { "classic", "coral", "starlight" }
Catalog.Cannons = {
	classic = { id = "classic", name = "Teal express", cost = 0, level = 1, rgb = { 57, 153, 155 } },
	coral = { id = "coral", name = "Coral cannon", cost = 100, level = 2, rgb = { 245, 132, 123 } },
	starlight = { id = "starlight", name = "Starlight dispatch", cost = 200, level = 4, rgb = { 155, 139, 211 } },
}
Catalog.MailboxOrder = { "classic", "cottage", "cloud" }
Catalog.Mailboxes = {
	classic = { id = "classic", name = "Classic postbox", cost = 0, level = 1, rgb = { 242, 126, 116 } },
	cottage = { id = "cottage", name = "Cottage mailbox", cost = 100, level = 2, rgb = { 138, 186, 143 } },
	cloud = { id = "cloud", name = "Cloud mailbox", cost = 200, level = 4, rgb = { 168, 198, 238 } },
}
Catalog.Shop = {}
for id, item in pairs(Catalog.Decorations) do
	Catalog.Shop["decor:" .. id] = { id = "decor:" .. id, kind = "decoration", assetId = id, name = item.name, cost = item.cost, level = item.level }
end
for id, item in pairs(Catalog.Cannons) do
	Catalog.Shop["cannon:" .. id] = { id = "cannon:" .. id, kind = "cannon", assetId = id, name = item.name, cost = item.cost, level = item.level }
end
for id, item in pairs(Catalog.Mailboxes) do
	Catalog.Shop["mailbox:" .. id] = { id = "mailbox:" .. id, kind = "mailbox", assetId = id, name = item.name, cost = item.cost, level = item.level }
end
Catalog.NpcNames = { "NPC Pippa Post", "NPC Captain Crumpet", "NPC Mallow Mail" }
return Catalog
