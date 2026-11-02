local ADDON, ns = ...
local D = ns.D

local I = "Interface\\Icons\\"

-- Mounts: Mount.db2 IDs (C_MountJournal). Instance drops first, then achievement rewards.
D.MOUNTS = {
    { mountID = 69,   source = "Stratholme" },                       -- Rivendare's Deathcharger
    { mountID = 185,  source = "Sethekk Halls" },                    -- Raven Lord
    { mountID = 213,  source = "Magisters' Terrace" },               -- Swift White Hawkstrider
    { mountID = 183,  source = "Tempest Keep: The Eye" },            -- Ashes of Al'ar
    { mountID = 264,  source = "Utgarde Pinnacle" },                 -- Blue Proto-Drake
    { mountID = 363,  source = "Icecrown Citadel" },                 -- Invincible
    { mountID = 397,  source = "The Stonecore" },                    -- Vitreous Stone Drake
    { mountID = 395,  source = "The Vortex Pinnacle" },              -- Drake of the North Wind
    { mountID = 411,  source = "Zul'Gurub" },                        -- Swift Zulian Panther
    { mountID = 415,  source = "Firelands" },                        -- Pureblood Fire Hawk
    { mountID = 531,  source = "Throne of Thunder" },                -- Spawn of Horridon
    { mountID = 613,  source = "Blackrock Foundry" },                -- Ironhoof Destroyer
    { mountID = 875,  source = "Return to Karazhan" },               -- Midnight
    { mountID = 954,  source = "Antorus, the Burning Throne" },      -- Shackled Ur'zul
    { mountID = 995,  source = "Freehold" },                         -- Sharkbait
    { mountID = 1053, source = "The Underrot" },                     -- Underrot Crawg
    { mountID = 1293, source = "Ny'alotha, the Waking City" },       -- Ny'alotha Allseer
    { mountID = 1406, source = "The Necrotic Wake" },                -- Marrowfang
    { mountID = 1481, source = "Tazavesh, the Veiled Market" },      -- Cartel Master's Gearglider
    { mountID = 1471, source = "Sanctum of Domination" },            -- Vengeance
    { mountID = 1818, source = "Amirdrassil, the Dream's Hope" },    -- Anu'relos, Flame's Guidance
    { mountID = 2507, source = "Liberation of Undermine" },          -- Prototype A.S.M.R.
    { mountID = 2805, source = "Windrunner Spire" },                 -- Spectral Hawkstrider
    { mountID = 291,  source = "Achievement: Stable of Ten" },       -- Blue Dragonhawk
    { mountID = 268,  source = "Achievement: Leading the Charge" },  -- Albino Drake
    { mountID = 262,  source = "Achievement: Hero of the Warcamp" }, -- Red Proto-Drake
    { mountID = 391,  source = "Achievement: Delver of the Deep" },  -- Volcanic Stone Drake
    { mountID = 304,  source = "Achievement: Raid Conqueror" },      -- Mimiron's Head
    { mountID = 2607, source = "Achievement: Midnight Falls" },      -- Ashes of Belo'ren
}

-- Pets: BattlePetSpecies.db2 IDs.
D.PETS = {
    { speciesID = 50,   source = "The Deadmines" },                  -- Green Wing Macaw
    { speciesID = 1149, source = "Molten Core" },                    -- Corefire Imp
    { speciesID = 175,  source = "Magisters' Terrace" },             -- Phoenix Hatchling
    { speciesID = 1235, source = "Tempest Keep: The Eye" },          -- Phoenix Hawk Hatchling
    { speciesID = 1966, source = "Icecrown Citadel" },               -- Soulbroken Whelpling
    { speciesID = 2087, source = "Firelands" },                      -- Cinderweb Recluse
    { speciesID = 1200, source = "Throne of Thunder" },              -- Pygmy Direhorn
    { speciesID = 2832, source = "Ny'alotha, the Waking City" },     -- Muar
    { speciesID = 3044, source = "Mists of Tirna Scithe" },          -- Spinemaw Gormling
    { speciesID = 3110, source = "Tazavesh, the Veiled Market" },    -- Gizmo
    { speciesID = 3122, source = "Sanctum of Domination" },          -- Irongrasp
    { speciesID = 4469, source = "Cinderbrew Meadery" },             -- Bop
    { speciesID = 4759, source = "Operation: Floodgate" },           -- Craboom
    { speciesID = 2064, source = "Achievement: Deep Pockets" },      -- Mining Monkey
    { speciesID = 2638, source = "Achievement: Master of the Forge" }, -- Minimancer
    { speciesID = 4816, source = "Achievement: Full Barracks" },     -- Hawkstrider Hatchling
    { speciesID = 4803, source = "Achievement: Midnight Dungeon Hero" }, -- Niblet
}

-- Achievements ---------------------------------------------------------------------------------
-- stat keys the engine should track (counters, or a max for HIGHEST_*):
--   TASKS, GATHER_TASKS, QUEST_TASKS, DUNGEONS, RAIDS, GOLD_EARNED (copper), ITEMS_GATHERED, ITEMS_SOLD,
--   CRAFTS, GEAR_CRAFTED_EPIC, BUILDING_LEVELS (sum of all levels), HEROES_RECRUITED, HIGHEST_HERO_LEVEL,
--   HIGHEST_TIER, MOUNTS, PETS, ERAS, FAILED_TASKS, RAIDS_TIER12
-- reward: nil | {mountID=} | {speciesID=} (schema addition) | {title=}
D.ACHIEVEMENTS = {
    { key = "FIRST_STEPS", name = "First Steps", desc = "Complete your first mission.", points = 5, icon = I .. "Achievement_Quests_Completed_01", stat = "TASKS", value = 1 },
    { key = "BUSY_CAMP", name = "A Busy Camp", desc = "Complete 50 missions.", points = 10, icon = I .. "Achievement_Quests_Completed_03", stat = "TASKS", value = 50 },
    { key = "NEVER_IDLE", name = "Never Idle", desc = "Complete 500 missions.", points = 15, icon = I .. "Achievement_Quests_Completed_06", stat = "TASKS", value = 500 },
    { key = "THE_LONG_WAR", name = "The Long War", desc = "Complete 2,500 missions.", points = 25, icon = I .. "Achievement_Quests_Completed_08", stat = "TASKS", value = 2500,
      reward = { title = "the Tireless" } },
    { key = "ERRAND_RUNNER", name = "Errand Runner", desc = "Complete 25 quests.", points = 10, icon = I .. "INV_Misc_Note_01", stat = "QUEST_TASKS", value = 25 },
    { key = "LOREKEEPER", name = "Lorekeeper", desc = "Complete 300 quests.", points = 20, icon = I .. "INV_Misc_Book_11", stat = "QUEST_TASKS", value = 300,
      reward = { title = "Lorekeeper" } },
    { key = "SWEAT_OF_THE_BROW", name = "Sweat of the Brow", desc = "Complete 50 gathering missions.", points = 10, icon = I .. "Trade_Mining", stat = "GATHER_TASKS", value = 50 },
    { key = "DEEP_POCKETS", name = "Deep Pockets", desc = "Gather 5,000 materials.", points = 15, icon = I .. "INV_Misc_Bag_08", stat = "ITEMS_GATHERED", value = 5000,
      reward = { speciesID = 2064 } },
    { key = "MOUNTAIN_OF_MATERIALS", name = "A Mountain of Materials", desc = "Gather 50,000 materials.", points = 25, icon = I .. "INV_Ore_Mithril_01", stat = "ITEMS_GATHERED", value = 50000 },
    { key = "INTO_THE_DARK", name = "Into the Dark", desc = "Clear your first dungeon.", points = 10, icon = I .. "Achievement_Boss_EdwinVancleef", stat = "DUNGEONS", value = 1 },
    { key = "DUNGEON_REGULAR", name = "Dungeon Regular", desc = "Clear 25 dungeons.", points = 10, icon = I .. "INV_Misc_Key_10", stat = "DUNGEONS", value = 25 },
    { key = "HERO_OF_THE_WARCAMP", name = "Hero of the Warcamp", desc = "Clear 100 dungeons.", points = 25, icon = I .. "Achievement_Dungeon_GloryoftheHERO", stat = "DUNGEONS", value = 100,
      reward = { mountID = 262 } },
    { key = "DELVER_OF_THE_DEEP", name = "Delver of the Deep", desc = "Clear 300 dungeons.", points = 25, icon = I .. "INV_Misc_Key_14", stat = "DUNGEONS", value = 300,
      reward = { mountID = 391 } },
    { key = "FIRST_RAID", name = "Raid Night", desc = "Defeat your first raid.", points = 10, icon = I .. "Achievement_Boss_Ragnaros", stat = "RAIDS", value = 1 },
    { key = "RAID_REGULAR", name = "Raid Regular", desc = "Defeat 10 raids.", points = 15, icon = I .. "Achievement_Dungeon_GloryoftheRaider", stat = "RAIDS", value = 10 },
    { key = "RAID_CONQUEROR", name = "Raid Conqueror", desc = "Defeat 40 raids.", points = 25, icon = I .. "Achievement_Boss_YoggSaron_01", stat = "RAIDS", value = 40,
      reward = { mountID = 304 } },
    { key = "MIDNIGHT_FALLS", name = "Midnight Falls", desc = "Defeat The Voidspire 5 times.", points = 25, icon = I .. "Spell_Shadow_Twilight", stat = "RAIDS_TIER12", value = 5,
      reward = { mountID = 2607 } },
    { key = "MIDNIGHT_DUNGEON_HERO", name = "Midnight Dungeon Hero", desc = "Clear 400 dungeons.", points = 15, icon = I .. "INV_Misc_Key_15", stat = "DUNGEONS", value = 400,
      reward = { speciesID = 4803 } },
    { key = "POCKET_CHANGE", name = "Pocket Change", desc = "Earn 100 gold.", points = 5, icon = I .. "INV_Misc_Coin_04", stat = "GOLD_EARNED", value = 1000000 },
    { key = "WAR_CHEST", name = "War Chest", desc = "Earn 10,000 gold.", points = 10, icon = I .. "INV_Misc_Coin_02", stat = "GOLD_EARNED", value = 100000000 },
    { key = "MERCHANT_PRINCE", name = "Merchant Prince", desc = "Earn 250,000 gold.", points = 25, icon = I .. "INV_Misc_Coin_01", stat = "GOLD_EARNED", value = 2500000000,
      reward = { title = "Merchant Prince" } },
    { key = "MARKET_DAY", name = "Market Day", desc = "Sell 1,000 items at the market.", points = 10, icon = I .. "INV_Misc_Bag_10", stat = "ITEMS_SOLD", value = 1000 },
    { key = "SPARKS_FLY", name = "Sparks Fly", desc = "Craft 25 items.", points = 10, icon = I .. "Trade_BlackSmithing", stat = "CRAFTS", value = 25 },
    { key = "MASTER_OF_THE_FORGE", name = "Master of the Forge", desc = "Craft 10 pieces of epic gear.", points = 20, icon = I .. "INV_Hammer_20", stat = "GEAR_CRAFTED_EPIC", value = 10,
      reward = { speciesID = 2638 } },
    { key = "FOUNDATIONS", name = "Laying Foundations", desc = "Raise buildings a total of 10 levels.", points = 10, icon = I .. "Achievement_Garrison_Tier01_Horde", stat = "BUILDING_LEVELS", value = 10 },
    { key = "STONE_AND_TIMBER", name = "Stone and Timber", desc = "Raise buildings a total of 60 levels.", points = 15, icon = I .. "Achievement_Garrison_Tier02_Horde", stat = "BUILDING_LEVELS", value = 60 },
    { key = "A_FORTRESS", name = "A Fortress Worthy of Legend", desc = "Raise every building to its highest level.", points = 25, icon = I .. "Achievement_Garrison_Tier03_Horde", stat = "BUILDING_LEVELS", value = 130,
      reward = { title = "the Architect" } },
    { key = "THE_FOURTH_RECRUIT", name = "Strength in Numbers", desc = "Recruit 4 heroes.", points = 5, icon = I .. "Achievement_GuildPerk_EverybodysFriend", stat = "HEROES_RECRUITED", value = 4 },
    { key = "FULL_BARRACKS", name = "Full Barracks", desc = "Recruit 25 heroes over time.", points = 15, icon = I .. "INV_Helmet_08", stat = "HEROES_RECRUITED", value = 25,
      reward = { speciesID = 4816 } },
    { key = "SEASONED", name = "Seasoned", desc = "Raise a recruit to level 30.", points = 10, icon = I .. "Achievement_Level_30", stat = "HIGHEST_HERO_LEVEL", value = 30 },
    { key = "VETERAN_OF_AGES", name = "Veteran of Ages", desc = "Raise a recruit to level 60.", points = 15, icon = I .. "Achievement_Level_60", stat = "HIGHEST_HERO_LEVEL", value = 60 },
    { key = "CHAMPION_OF_AZEROTH", name = "Champion of Azeroth", desc = "Raise a recruit to level 90.", points = 25, icon = I .. "Achievement_Level_90", stat = "HIGHEST_HERO_LEVEL", value = 90,
      reward = { title = "Champion of Azeroth" } },
    { key = "THROUGH_THE_PORTAL", name = "Through the Dark Portal", desc = "Reach The Burning Crusade.", points = 10, icon = I .. "Achievement_Zone_HellfirePeninsula_01", stat = "HIGHEST_TIER", value = 2 },
    { key = "NORTHREND_BOUND", name = "Northrend Bound", desc = "Reach Wrath of the Lich King.", points = 10, icon = I .. "Achievement_Zone_BoreanTundra_01", stat = "HIGHEST_TIER", value = 3 },
    { key = "PANDARIA", name = "Beyond the Mists", desc = "Reach Mists of Pandaria.", points = 10, icon = I .. "Achievement_Zone_JadeForest", stat = "HIGHEST_TIER", value = 5 },
    { key = "BROKEN_ISLES", name = "The Broken Isles", desc = "Reach Legion.", points = 10, icon = I .. "Achievement_Zone_Azsuna", stat = "HIGHEST_TIER", value = 7 },
    { key = "SHADOWLANDS", name = "Beyond the Veil", desc = "Reach Shadowlands.", points = 10, icon = I .. "Achievement_Zone_Bastion", stat = "HIGHEST_TIER", value = 9 },
    { key = "KHAZ_ALGAR", name = "Into Khaz Algar", desc = "Reach The War Within.", points = 10, icon = I .. "Achievement_Zone_IsleOfDorn", stat = "HIGHEST_TIER", value = 11 },
    { key = "QUELTHALAS", name = "Light of Quel'Thalas", desc = "Reach Midnight.", points = 15, icon = I .. "Achievement_Zone_EversongWoods", stat = "HIGHEST_TIER", value = 12 },
    { key = "STABLE_OF_TEN", name = "Stable of Ten", desc = "Collect 10 mounts.", points = 10, icon = I .. "Ability_Mount_RidingHorse", stat = "MOUNTS", value = 10,
      reward = { mountID = 291 } },
    { key = "LEADING_THE_CHARGE", name = "Leading the Charge", desc = "Collect 20 mounts.", points = 25, icon = I .. "Ability_Mount_Drake_Twilight", stat = "MOUNTS", value = 20,
      reward = { mountID = 268 } },
    { key = "MENAGERIE", name = "A Little Menagerie", desc = "Collect 10 pets.", points = 10, icon = I .. "INV_Box_PetCarrier_01", stat = "PETS", value = 10,
      reward = { title = "the Beastkeeper" } },
    { key = "NEW_ERA", name = "A New Era", desc = "Begin a New Era.", points = 25, icon = I .. "Spell_Holy_BorrowedTime", stat = "ERAS", value = 1 },
    { key = "AGELESS", name = "Ageless", desc = "Begin five New Eras.", points = 50, icon = I .. "INV_Misc_PocketWatch_01", stat = "ERAS", value = 5,
      reward = { title = "the Timeless" } },
    { key = "BRUISED_NOT_BROKEN", name = "Bruised, Not Broken", desc = "Fail 25 missions and send them out again anyway.", points = 5, icon = I .. "Ability_Warrior_Revenge", stat = "FAILED_TASKS", value = 25 },
}
