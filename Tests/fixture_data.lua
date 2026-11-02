-- Tests/fixture_data.lua — a small, schema-complete ns.D for the headless harness.
-- Called as loadfile(path)("Warcamp", ns, nTiers). nTiers defaults to 2; the harness's "fixture12"
-- mode asks for 12 synthetic tiers so balance can be judged before the real data exists.
-- IDs here are placeholders for tests only (never shipped: Tests\ is not in the toc).
local ADDON, ns, nTiers = ...
nTiers = nTiers or 2
local D = ns.D

D.ROLES = {
    TANK = { name = "Tank", atlas = "roleicon-tank" },
    HEALER = { name = "Healer", atlas = "roleicon-healer" },
    DAMAGER = { name = "Damage", atlas = "roleicon-dps" },
}

D.THREATS = {
    MAGIC_DEBUFF = { name = "Magic Debuff", icon = 135894, desc = "Dispellable magic." },
    GROUP_DAMAGE = { name = "Group Damage", icon = 135808, desc = "Heavy damage to everyone." },
    MASSIVE_STRIKE = { name = "Massive Strike", icon = 132355, desc = "A huge hit on the tank." },
    WILD_AGGRESSION = { name = "Wild Aggression", icon = 132278, desc = "Adds that need picking up." },
    CASTER = { name = "Spellcaster", icon = 136071, desc = "Interruptible casts." },
}

D.CLASSES = {
    WARRIOR = { name = "Warrior", roles = { "TANK", "DAMAGER" }, counters = { "MASSIVE_STRIKE", "WILD_AGGRESSION" }, gather = "MINING" },
    PRIEST  = { name = "Priest", roles = { "HEALER", "DAMAGER" }, counters = { "MAGIC_DEBUFF", "GROUP_DAMAGE" }, gather = "HERBALISM" },
    HUNTER  = { name = "Hunter", roles = { "DAMAGER" }, counters = { "CASTER", "WILD_AGGRESSION" }, gather = "SKINNING" },
}

D.TRAITS = {
    MINER = { name = "Miner's Luck", desc = "More ore.", icon = 134708, kind = "GATHER_YIELD", value = 0.15, filter = "MINING" },
    HERBALIST = { name = "Green Thumb", desc = "More herbs.", icon = 136065, kind = "GATHER_YIELD", value = 0.15, filter = "HERBALISM" },
    QUICK = { name = "Quick", desc = "Faster missions.", icon = 132307, kind = "SPEED", value = 0.08 },
    STUDIOUS = { name = "Studious", desc = "More experience.", icon = 133743, kind = "XP", value = 0.10 },
    GREEDY = { name = "Greedy", desc = "More gold.", icon = 133784, kind = "GOLD", value = 0.10 },
    VETERAN = { name = "Dungeon Veteran", desc = "Better odds in dungeons.", icon = 132344, kind = "CHANCE", value = 0.05, filter = "DUNGEON" },
    LUCKY = { name = "Lucky", desc = "More loot.", icon = 134400, kind = "LOOT", value = 0.10 },
    LAZY = { name = "Lazy", desc = "Slower missions.", icon = 136090, kind = "SPEED", value = -0.06 },
    CLUMSY = { name = "Clumsy", desc = "Worse odds.", icon = 132093, kind = "CHANCE", value = -0.03 },
}

D.LOOKS = {}
for _, c in ipairs({ "WARRIOR", "PRIEST", "HUNTER" }) do
    D.LOOKS[c] = {
        { display = 1000, race = "Human", sex = "M", faction = "Alliance", npc = "Guard" },
        { display = 1001, race = "Orc", sex = "F", faction = "Horde", npc = "Grunt" },
        { display = 1002, race = "Orc", sex = "M", faction = "Horde", npc = "Grunt" },
    }
end

D.NAMES = {
    Human = { M = { "Aldric", "Bren", "Corwin", "Dain" }, F = { "Elsa", "Fiora" }, last = { "Ashford", "Brightwater" } },
    Orc = { M = { "Grosh", "Urzag", "Mokra" }, F = { "Shara", "Zagra", "Kurra" }, last = { "Bloodfang", "Ironhide" } },
}

D.QUALITY = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
D.GEAR_SLOTS = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "WEAPON", "TRINKET" }

D.ITEMS, D.GEAR_BASES, D.TIERS, D.ZONES, D.DUNGEONS, D.RAIDS = {}, {}, {}, {}, {}, {}
local THREATS = { "MAGIC_DEBUFF", "GROUP_DAMAGE", "MASSIVE_STRIKE", "WILD_AGGRESSION", "CASTER" }
local levelTop = { 10, 20, 30, 40, 50, 60, 70, 75, 80, 83, 86, 90 }
local ilvlTop = { 40, 70, 100, 130, 160, 190, 220, 250, 280, 310, 340, 370 }
for t = 1, nTiers do
    local lo = t == 1 and 1 or levelTop[t - 1]
    local hi = levelTop[t]
    local ilo = t == 1 and 5 or ilvlTop[t - 1]
    local mats = {}
    for _, kind in ipairs({ "ORE", "HERB", "LEATHER", "FISH", "CLOTH" }) do
        local key = kind .. "_T" .. t
        D.ITEMS[key] = { name = kind:lower() .. " " .. t, itemID = 2770 + t, icon = 134400, quality = 1, tier = t, kind = kind,
                         price = math.floor(40 * 1.45 ^ (t - 1)) }
        mats[kind] = key
    end
    local rare = "RARE_T" .. t
    D.ITEMS[rare] = { name = "Gem " .. t, itemID = 7909, icon = 134400, quality = 3, tier = t, kind = "RARE", price = math.floor(2000 * 1.45 ^ (t - 1)) }
    D.TIERS[t] = { key = "T" .. t, name = "Tier " .. t, expansion = t - 1, level = { lo, hi }, ilvl = { ilo, ilvlTop[t] }, mats = mats, rare = rare }
    D.GEAR_BASES[t] = {}
    for _, slot in ipairs(D.GEAR_SLOTS) do
        D.GEAR_BASES[t][slot] = { { itemID = 1000 + t, name = slot:lower() .. " of tier " .. t }, { itemID = 2000 + t, name = "fine " .. slot:lower() } }
    end
    for z = 1, 3 do
        D.ZONES[#D.ZONES + 1] = {
            key = "ZONE_" .. t .. "_" .. z, name = "Zone " .. t .. "." .. z, tier = t,
            level = math.floor(lo + (hi - lo) * (z - 1) / 3 + 0.5) + (z == 1 and 1 or 0), mapID = 37,
            mobs = { { display = 2000, name = "Bandit" }, { display = 2001, name = "Wolf" } },
            quests = { "Bandit Trouble", "Wolves at the Door", "Lost Supplies", "A Strange Note", "Patrol", "Ambush" },
            gather = (z == 1) and { "MINING", "HERBALISM", "SKINNING" } or { "MINING", "HERBALISM", "FISHING", "SKINNING" },
        }
    end
    for d = 1, 2 do
        D.DUNGEONS[#D.DUNGEONS + 1] = {
            key = "DUNGEON_" .. t .. "_" .. d, name = "Dungeon " .. t .. "." .. d, tier = t, level = hi - 2 + d, journalID = 63,
            bosses = {
                { name = "Boss A", display = 3000, threats = { THREATS[(t + d) % 5 + 1] } },
                { name = "Boss B", display = 3001, threats = { THREATS[(t + d + 1) % 5 + 1], THREATS[(t + d + 2) % 5 + 1] } },
                { name = "Boss C", display = 3002, threats = { THREATS[(t + d + 3) % 5 + 1] } },
            },
            mount = (d == 2) and { mountID = 100 + t, chance = 0.01 } or nil,
            pet = (d == 1) and { speciesID = 200 + t, chance = 0.03 } or nil,
        }
    end
    D.RAIDS[#D.RAIDS + 1] = {
        key = "RAID_" .. t, name = "Raid " .. t, tier = t, level = hi, journalID = 741,
        bosses = {
            { name = "Raid Boss 1", display = 4000, threats = { "GROUP_DAMAGE" } },
            { name = "Raid Boss 2", display = 4001, threats = { "MASSIVE_STRIKE", "MAGIC_DEBUFF" } },
            { name = "Raid Boss 3", display = 4002, threats = { "CASTER" } },
            { name = "Raid Boss 4", display = 4003, threats = { "WILD_AGGRESSION", "GROUP_DAMAGE" } },
        },
        mount = { mountID = 300 + t, chance = 0.02 }, pet = { speciesID = 400 + t, chance = 0.03 },
    }
end

-- buildings: 10 levels each; costs grow along the gold curve, items from the tier that level belongs to
local function levels(goldBase, matKind, n)
    local out = {}
    for L = 1, n do
        local t = math.min(nTiers, math.max(1, math.ceil(L * nTiers / n)))
        local items = {}
        if matKind and L > 1 then items[D.TIERS[t].mats[matKind]] = 8 * L end
        out[L] = { gold = math.floor(goldBase * 2.0 ^ (L - 1)), items = items,
                   time = math.floor(600 * (144) ^ ((L - 1) / (n - 1))), effect = nil }
    end
    return out
end
local B = {
    TOWN_HALL = { "Town Hall", 8000, "ORE" }, BARRACKS = { "Barracks", 5000, "LEATHER" }, INN = { "Inn", 4000, "CLOTH" },
    MINE = { "Mine", 3000, nil }, GARDEN = { "Herb Garden", 3000, nil }, FORGE = { "Forge", 6000, "ORE" },
    ALCHEMY_LAB = { "Alchemy Lab", 6000, "HERB" }, KITCHEN = { "Kitchen", 4000, "FISH" }, STABLES = { "Stables", 7000, "LEATHER" },
    TRAINING_GROUNDS = { "Training Grounds", 7000, "ORE" }, TRADING_POST = { "Trading Post", 5000, "CLOTH" },
    TREASURY = { "Treasury", 9000, "ORE" },
}
D.BUILDINGS = {}
for key, b in pairs(B) do
    D.BUILDINGS[key] = { name = b[1], icon = 134400, desc = b[1] .. ".", maxLevel = 10, levels = levels(b[2], b[3], 10) }
end

D.ITEMS.HEALING_POTION = { name = "Healing Potion", itemID = 118, icon = 134400, quality = 1, tier = 1, kind = "POTION", price = 200, buff = "POTION_LUCK" }
D.ITEMS.FEAST = { name = "Feast", itemID = 2683, icon = 134400, quality = 1, tier = 1, kind = "FOOD", price = 300 }
D.RECIPES = {
    POTION = { name = "Healing Potion", building = "ALCHEMY_LAB", buildingLevel = 1, tier = 1, inputs = { HERB_T1 = 4 }, gold = 100, time = 300,
               output = { item = "HEALING_POTION", n = 1 } },
    FEAST = { name = "Feast", building = "KITCHEN", buildingLevel = 1, tier = 1, inputs = { FISH_T1 = 4 }, gold = 100, time = 300,
              output = { item = "FEAST", n = 1 } },
}
for t = 1, nTiers do
    D.RECIPES["GEAR_T" .. t] = { name = "Forged Gear " .. t, building = "FORGE", buildingLevel = math.max(1, math.ceil(t * 10 / 12)), tier = t,
        inputs = { [D.TIERS[t].mats.ORE] = 10, [D.TIERS[t].mats.LEATHER] = 4 }, gold = math.floor(1500 * 1.42 ^ (t - 1)), time = 1800,
        output = { gear = "ANY", tier = t, quality = 3 } }
end

D.BUFFS = {
    RALLYING_CRY = { name = "Rallying Cry", icon = 132351, desc = "Faster missions.", kind = "SPEED", value = 0.10, duration = 3600 },
    POTION_LUCK = { name = "Lucky Draught", icon = 134400, desc = "Better odds.", kind = "CHANCE", value = 0.05, duration = 7200 },
}

D.MOUNTS, D.PETS = {}, {}
for _, list in ipairs({ D.DUNGEONS, D.RAIDS }) do
    for _, ins in ipairs(list) do
        if ins.mount then D.MOUNTS[#D.MOUNTS + 1] = { mountID = ins.mount.mountID, source = ins.name } end
        if ins.pet then D.PETS[#D.PETS + 1] = { speciesID = ins.pet.speciesID, source = ins.name } end
    end
end
D.MOUNTS[#D.MOUNTS + 1] = { mountID = 999, source = "Achievement: Seasoned" }

D.ACHIEVEMENTS = {
    { key = "FIRST_STEPS", name = "First Steps", desc = "Complete 10 tasks.", points = 5, icon = 134400, stat = "TASKS", value = 10 },
    { key = "RICH", name = "Coin Purse", desc = "Earn 10 gold.", points = 10, icon = 133784, stat = "GOLD_EARNED", value = 100000 },
    { key = "DELVER", name = "Delver", desc = "Clear 5 dungeons.", points = 10, icon = 134400, stat = "DUNGEONS", value = 5 },
    { key = "SEASONED", name = "Seasoned", desc = "Reach level 20.", points = 20, icon = 134400, stat = "MAX_LEVEL", value = 20, reward = { mountID = 999 } },
}
