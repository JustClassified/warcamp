local ADDON, ns = ...
local D = ns.D

local I = "Interface\\Icons\\"

-- Buildings -----------------------------------------------------------------------------
-- levels[n] = cost/time of reaching level n and the effect while at level n.
-- Schema additions (all optional for the UI, useful for the engine):
--   def.stat          what levels[n].value means (see each building)
--   levels[n].value   the number behind the effect text
--   MINE/GARDEN: levels[n].rate (items per hour), levels[n].cap (storage), levels[n].tier (which tier's ore/herb)
-- Gold in copper, time in seconds. Materials of level n come from tier n (D.TIERS[n]).

local GOLD = { 2000, 10000, 30000, 80000, 200000, 450000, 900000, 1800000, 3500000, 6500000, 12000000, 20000000 }
local TIME = { 180, 600, 1200, 2400, 3600, 7200, 10800, 14400, 21600, 32400, 57600, 86400 }

local function tierMat(n, kind)
    local t = D.TIERS[math.min(n, #D.TIERS)]
    if kind == "RARE" then return t.rare end
    if kind == "BAR" then return t.bar end
    return t.mats[kind]
end

-- build levels: cost scale (1 = standard), material kinds used, effect(n) -> text, value
local function makeLevels(maxLevel, scale, kinds, effect)
    local levels = {}
    for n = 1, maxLevel do
        local items = {}
        if n > 1 then
            for i = 1, #kinds do
                local key = tierMat(n - 1, kinds[i])
                if key then items[key] = (items[key] or 0) + 4 + 2 * n end
            end
            if n >= 6 then
                local rare = tierMat(n - 1, "RARE")
                items[rare] = (items[rare] or 0) + math.floor(n / 4)
            end
        end
        local text, value, extra = effect(n)
        local lv = { gold = math.floor(GOLD[n] * scale), items = items, time = math.floor(TIME[n] * (scale > 1 and 1.25 or 1)),
                     effect = text, value = value }
        if extra then for k, v in pairs(extra) do lv[k] = v end end
        levels[n] = lv
    end
    return levels
end

D.BUILDINGS = {
    TOWN_HALL = { name = "Town Hall", icon = I .. "INV_Misc_Flag_01", maxLevel = 12, stat = "MAX_BUILDING_LEVEL",
        desc = "The heart of the warcamp. Every other building may rise only as high as the Town Hall, and each level opens the road to a new age of Azeroth.",
        levels = makeLevels(12, 1.5, { "BAR", "CLOTH" }, function(n)
            return string.format("Buildings up to level %d; %s missions open", n, D.TIERS[n].name), n
        end) },
    BARRACKS = { name = "Barracks", icon = I .. "INV_Helmet_08", maxLevel = 10, stat = "MAX_HEROES",
        desc = "Bunks, racks and a sergeant who never sleeps. More room means more recruits under your banner.",
        levels = makeLevels(10, 1, { "BAR", "LEATHER" }, function(n)
            return string.format("Room for %d recruits", 3 + n), 3 + n
        end) },
    INN = { name = "Inn", icon = I .. "INV_Drink_05", maxLevel = 8, stat = "RECRUIT_QUALITY",
        desc = "Travellers, sellswords and wandering heroes gather by the hearth. A better inn draws better company.",
        levels = makeLevels(8, 0.8, { "CLOTH", "FISH" }, function(n)
            local refresh = math.max(1, 7 - math.floor(n / 2))
            return string.format("New recruits every %dh; %d%% chance of a rare recruit, %d%% epic", refresh, 5 + n * 5, math.max(0, n * 2 - 4)), n,
                { refreshHours = refresh, rareChance = (5 + n * 5) / 100, epicChance = math.max(0, n * 2 - 4) / 100 }
        end) },
    MINE = { name = "Mine", icon = I .. "Trade_Mining", maxLevel = 12, stat = "PASSIVE_ORE",
        desc = "A shaft sunk into the hillside. Peons haul ore up day and night; collect it before the carts overflow.",
        levels = makeLevels(12, 0.7, { "ORE", "LEATHER" }, function(n)
            local rate, cap = 4 + n * 2, 40 + n * 20
            return string.format("%d %s per hour, stores %d", rate, D.ITEMS[D.TIERS[n].mats.ORE].name, cap), rate,
                { rate = rate, cap = cap, tier = n }
        end) },
    GARDEN = { name = "Herb Garden", icon = I .. "Trade_Herbalism", maxLevel = 12, stat = "PASSIVE_HERB",
        desc = "Neat rows of herbs behind a low fence. Tend it well and the alchemists never run dry.",
        levels = makeLevels(12, 0.7, { "HERB", "FISH" }, function(n)
            local rate, cap = 4 + n * 2, 40 + n * 20
            return string.format("%d %s per hour, stores %d", rate, D.ITEMS[D.TIERS[n].mats.HERB].name, cap), rate,
                { rate = rate, cap = cap, tier = n }
        end) },
    FORGE = { name = "Forge", icon = I .. "Trade_BlackSmithing", maxLevel = 12, stat = "RECIPE_TIER",
        desc = "Anvil, bellows and a smith with forearms like tree trunks. Smelts ore and hammers out gear for your recruits.",
        levels = makeLevels(12, 1, { "ORE", "BAR" }, function(n)
            return string.format("Smelting and gear recipes up to %s", D.TIERS[n].name), n
        end) },
    ALCHEMY_LAB = { name = "Alchemy Lab", icon = I .. "Trade_Alchemy", maxLevel = 12, stat = "RECIPE_TIER",
        desc = "Bubbling flasks and a faint smell of singed eyebrows. Brews the potions that keep a party alive.",
        levels = makeLevels(12, 1, { "HERB", "CLOTH" }, function(n)
            return string.format("Potion recipes up to %s", D.TIERS[n].name), n
        end) },
    KITCHEN = { name = "Kitchen", icon = I .. "INV_Misc_Food_15", maxLevel = 12, stat = "RECIPE_TIER",
        desc = "A great iron stove and a cook who will not be rushed. Well-fed heroes gather more and complain less.",
        levels = makeLevels(12, 1, { "FISH", "HERB" }, function(n)
            return string.format("Feast recipes up to %s", D.TIERS[n].name), n
        end) },
    STABLES = { name = "Stables", icon = I .. "Ability_Mount_RidingHorse", maxLevel = 10, stat = "MISSION_SPEED",
        desc = "Fresh mounts at every gate. Recruits reach the front faster, and the stablemaster has an eye for rare beasts.",
        levels = makeLevels(10, 1, { "LEATHER", "HERB" }, function(n)
            return string.format("Missions %d%% faster; +%d%% mount and pet chance", n * 2, n * 5), n * 0.02,
                { collectBonus = n * 0.05 }
        end) },
    TRAINING_GROUNDS = { name = "Training Grounds", icon = I .. "Ability_Warrior_OffensiveStance", maxLevel = 10, stat = "XP_BONUS",
        desc = "Practice dummies, sparring rings and a veteran with a loud voice. Recruits learn faster here.",
        levels = makeLevels(10, 1, { "BAR", "LEATHER" }, function(n)
            return string.format("+%d%% experience; idle recruits train for %d xp per hour", n * 4, n * 10), n * 0.04,
                { idleXP = n * 10 }
        end) },
    TRADING_POST = { name = "Trading Post", icon = I .. "INV_Misc_Coin_01", maxLevel = 10, stat = "MARKET_BONUS",
        desc = "Goblin brokers, sealed ledgers and very little honesty. Better contacts mean better prices.",
        levels = makeLevels(10, 1, { "CLOTH", "BAR" }, function(n)
            return string.format("Buy %d%% cheaper, sell %d%% dearer", n, n * 2), n * 0.01
        end) },
    TREASURY = { name = "Treasury", icon = I .. "INV_Misc_Bag_10", maxLevel = 10, stat = "GOLD_BONUS",
        desc = "An iron-bound strongroom and a clerk who counts twice. Every purse brought home grows a little heavier.",
        levels = makeLevels(10, 1.2, { "BAR", "ORE" }, function(n)
            return string.format("+%d%% gold from missions", n * 3), n * 0.03
        end) },
}

-- Recipes -----------------------------------------------------------------------------------
-- Per tier: smelt (Forge), potion (Alchemy Lab), feast (Kitchen), rare gear and epic gear (Forge).
-- buildingLevel = tier. Gold in copper, times in seconds.
D.RECIPES = {}
local GEAR_NAMES = {
    "Copper-Bound", "Fel Iron", "Saronite", "Obsidium", "Ghost Iron", "Truesteel",
    "Leystone", "Monelite", "Laestrite", "Serevite", "Bismuth", "Refulgent",
}
for t = 1, #D.TIERS do
    local T = D.TIERS[t]
    local m = 1.9 ^ (t - 1)
    local slow = 1 + 0.25 * (t - 1)
    local function gold(x) return math.floor(x * m) end
    local function secs(x) return math.floor(x * slow) end
    D.RECIPES["SMELT_" .. T.key] = { name = "Smelt " .. D.ITEMS[T.bar].name, building = "FORGE", buildingLevel = t, tier = t,
        inputs = { [T.mats.ORE] = 2 }, gold = gold(10), time = secs(60), output = { item = T.bar, n = 1 } }
    D.RECIPES["POTION_" .. T.key] = { name = D.ITEMS[T.potion].name, building = "ALCHEMY_LAB", buildingLevel = t, tier = t,
        inputs = { [T.mats.HERB] = 3 }, gold = gold(25), time = secs(90), output = { item = T.potion, n = 1 } }
    D.RECIPES["FEAST_" .. T.key] = { name = D.ITEMS[T.food].name, building = "KITCHEN", buildingLevel = t, tier = t,
        inputs = { [T.mats.FISH] = 3, [T.mats.HERB] = 1 }, gold = gold(25), time = secs(90), output = { item = T.food, n = 1 } }
    D.RECIPES["GEAR_" .. T.key] = { name = GEAR_NAMES[t] .. " Armaments", building = "FORGE", buildingLevel = t, tier = t,
        inputs = { [T.bar] = 4, [T.mats.LEATHER] = 3, [T.mats.CLOTH] = 2 }, gold = gold(500), time = secs(600),
        output = { gear = "ANY", tier = t, quality = 3 } }
    D.RECIPES["EPIC_" .. T.key] = { name = "Masterwork " .. GEAR_NAMES[t] .. " Armaments", building = "FORGE", buildingLevel = t, tier = t,
        inputs = { [T.bar] = 8, [T.mats.LEATHER] = 5, [T.mats.CLOTH] = 4, [T.rare] = 1 }, gold = gold(3000), time = secs(2700),
        output = { gear = "ANY", tier = t, quality = 4 } }
end

-- Buffs ---------------------------------------------------------------------------------------
-- kind: SPEED | XP | GOLD | CHANCE | YIELD; value = fraction; duration = seconds
D.BUFFS = {
    RALLYING_CRY = { name = "Rallying Cry", icon = I .. "Ability_Warrior_RallyingCry", kind = "SPEED", value = 0.10, duration = 3600,
        desc = "Word of your own victory reaches the camp. Every mission moves 10% faster for an hour." },
    WELL_FED = { name = "Well Fed", icon = I .. "Spell_Misc_Food", kind = "YIELD", value = 0.10, duration = 7200,
        desc = "A hearty feast from the Kitchen. Gathering yields 10% more for two hours." },
    STOCKED_INFIRMARY = { name = "Stocked Infirmary", icon = I .. "INV_Potion_51", kind = "CHANCE", value = 0.05, duration = 7200,
        desc = "Healing potions in every pack. +5% success chance for two hours." },
    RESTED = { name = "Rested", icon = I .. "Spell_Nature_Sleep", kind = "XP", value = 0.15, duration = 14400,
        desc = "The recruits slept in real beds for once. +15% experience for four hours." },
    PIRATES_BOUNTY = { name = "Pirate's Bounty", icon = I .. "INV_Misc_Coin_02", kind = "GOLD", value = 0.15, duration = 3600,
        desc = "A map to a buried chest changed hands at the inn. +15% gold for an hour." },
    WHEE = { name = "WHEE!", icon = I .. "INV_Misc_Ticket_Darkmoon_01", kind = "XP", value = 0.10, duration = 3600,
        desc = "Someone took the recruits to the Darkmoon Faire carousel. +10% experience for an hour." },
}
