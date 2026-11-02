local ADDON, ns = ...
local D = ns.D

--[[ Notes for the engine
  Every tier has exactly one item of each kind; look them up through D.TIERS[t].mats / .rare, or
  through D.TIER_ITEMS[t][kind] (built at the bottom of this file):
    raw (gathered/looted):  ORE, HERB, LEATHER, FISH, CLOTH, RARE
    crafted intermediates:  BAR    (Forge smelt: ORE -> BAR; also an input of Forge gear and building upgrades)
                            POTION (Alchemy Lab: HERB -> POTION)
                            FOOD   (Kitchen: FISH + HERB -> FOOD)
  Crafted intermediate keys per tier:
    1 COPPER_BAR / MINOR_HEALING_POTION / BRILLIANT_SMALLFISH
    2 FEL_IRON_BAR / SUPER_HEALING_POTION / SPICY_CRAWDAD
    3 SARONITE_BAR / RUNIC_HEALING_POTION / FISH_FEAST
    4 OBSIDIUM_BAR / MYTHICAL_HEALING_POTION / SEAFOOD_MAGNIFIQUE_FEAST
    5 GHOST_IRON_BAR / MASTER_HEALING_POTION / BANQUET_OF_THE_GRILL
    6 TRUESTEEL_INGOT / HEALING_TONIC / FEAST_OF_BLOOD
    7 INFERNAL_BRIMSTONE / ANCIENT_HEALING_POTION / LAVISH_SURAMAR_FEAST
    8 HYDROCORE / COASTAL_HEALING_POTION / BOUNTIFUL_CAPTAINS_FEAST
    9 SHADOWGHAST_INGOT / SPIRITUAL_HEALING_POTION / FEAST_OF_GLUTTONOUS_HEDONISM
   10 PRIMAL_MOLTEN_ALLOY / REFRESHING_HEALING_POTION / GRAND_BANQUET_OF_THE_KALUAK
   11 CORE_ALLOY / ALGARI_HEALING_POTION / FEAST_OF_THE_DIVINE_DAY
   12 REFULGENT_COPPER_INGOT / SILVERMOON_HEALTH_POTION / BLOOMING_FEAST
  Schema additions: POTION and FOOD items carry `use = <D.BUFFS key>` (consuming one grants that buff).
  price = base copper, roughly x1.9 per tier. All itemIDs checked against ItemSparse (build 12.x).
]]

local I = "Interface\\Icons\\"

D.QUALITY = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

D.ITEMS = {
    -- 1
    COPPER_ORE = { name = "Copper Ore", itemID = 2770, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 1, kind = "ORE", price = 50 },
    PEACEBLOOM = { name = "Peacebloom", itemID = 2447, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 1, kind = "HERB", price = 50 },
    LIGHT_LEATHER = { name = "Light Leather", itemID = 2318, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 1, kind = "LEATHER", price = 55 },
    RAW_BRILLIANT_SMALLFISH = { name = "Raw Brilliant Smallfish", itemID = 6291, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 1, kind = "FISH", price = 45 },
    LINEN_CLOTH = { name = "Linen Cloth", itemID = 2589, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 1, kind = "CLOTH", price = 60 },
    BLACK_LOTUS = { name = "Black Lotus", itemID = 13468, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 2, tier = 1, kind = "RARE", price = 1200 },
    COPPER_BAR = { name = "Copper Bar", itemID = 2840, icon = I .. "INV_Ingot_02", quality = 1, tier = 1, kind = "BAR", price = 140 },
    MINOR_HEALING_POTION = { name = "Minor Healing Potion", itemID = 118, icon = I .. "INV_Potion_51", quality = 1, tier = 1, kind = "POTION", price = 180, use = "STOCKED_INFIRMARY" },
    BRILLIANT_SMALLFISH = { name = "Brilliant Smallfish", itemID = 6290, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 1, kind = "FOOD", price = 170, use = "WELL_FED" },
    -- 2
    FEL_IRON_ORE = { name = "Fel Iron Ore", itemID = 23424, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 2, kind = "ORE", price = 95 },
    FELWEED = { name = "Felweed", itemID = 22785, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 2, kind = "HERB", price = 95 },
    KNOTHIDE_LEATHER = { name = "Knothide Leather", itemID = 21887, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 2, kind = "LEATHER", price = 100 },
    SPOTTED_FELTAIL = { name = "Spotted Feltail", itemID = 27425, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 2, kind = "FISH", price = 86 },
    NETHERWEAVE_CLOTH = { name = "Netherweave Cloth", itemID = 21877, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 2, kind = "CLOTH", price = 110 },
    PRIMAL_MIGHT = { name = "Primal Might", itemID = 23571, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 2, kind = "RARE", price = 2300 },
    FEL_IRON_BAR = { name = "Fel Iron Bar", itemID = 23445, icon = I .. "INV_Ingot_02", quality = 1, tier = 2, kind = "BAR", price = 270 },
    SUPER_HEALING_POTION = { name = "Super Healing Potion", itemID = 22829, icon = I .. "INV_Potion_51", quality = 1, tier = 2, kind = "POTION", price = 340, use = "STOCKED_INFIRMARY" },
    SPICY_CRAWDAD = { name = "Spicy Crawdad", itemID = 27667, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 2, kind = "FOOD", price = 320, use = "WELL_FED" },
    -- 3
    SARONITE_ORE = { name = "Saronite Ore", itemID = 36912, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 3, kind = "ORE", price = 180 },
    GOLDCLOVER = { name = "Goldclover", itemID = 36901, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 3, kind = "HERB", price = 180 },
    BOREAN_LEATHER = { name = "Borean Leather", itemID = 33568, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 3, kind = "LEATHER", price = 200 },
    GLACIAL_SALMON = { name = "Glacial Salmon", itemID = 41809, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 3, kind = "FISH", price = 160 },
    FROSTWEAVE_CLOTH = { name = "Frostweave Cloth", itemID = 33470, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 3, kind = "CLOTH", price = 220 },
    FROZEN_ORB = { name = "Frozen Orb", itemID = 43102, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 3, kind = "RARE", price = 4300 },
    SARONITE_BAR = { name = "Saronite Bar", itemID = 36913, icon = I .. "INV_Ingot_02", quality = 1, tier = 3, kind = "BAR", price = 510 },
    RUNIC_HEALING_POTION = { name = "Runic Healing Potion", itemID = 33447, icon = I .. "INV_Potion_51", quality = 1, tier = 3, kind = "POTION", price = 650, use = "STOCKED_INFIRMARY" },
    FISH_FEAST = { name = "Fish Feast", itemID = 43015, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 3, kind = "FOOD", price = 610, use = "WELL_FED" },
    -- 4
    OBSIDIUM_ORE = { name = "Obsidium Ore", itemID = 53038, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 4, kind = "ORE", price = 340 },
    CINDERBLOOM = { name = "Cinderbloom", itemID = 52983, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 4, kind = "HERB", price = 340 },
    SAVAGE_LEATHER = { name = "Savage Leather", itemID = 52976, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 4, kind = "LEATHER", price = 380 },
    DEEPSEA_SAGEFISH = { name = "Deepsea Sagefish", itemID = 53072, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 4, kind = "FISH", price = 310 },
    EMBERSILK_CLOTH = { name = "Embersilk Cloth", itemID = 53010, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 4, kind = "CLOTH", price = 410 },
    CHAOS_ORB = { name = "Chaos Orb", itemID = 52078, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 4, kind = "RARE", price = 8200 },
    OBSIDIUM_BAR = { name = "Obsidium Bar", itemID = 54849, icon = I .. "INV_Ingot_02", quality = 1, tier = 4, kind = "BAR", price = 960 },
    MYTHICAL_HEALING_POTION = { name = "Mythical Healing Potion", itemID = 57191, icon = I .. "INV_Potion_51", quality = 1, tier = 4, kind = "POTION", price = 1200, use = "STOCKED_INFIRMARY" },
    SEAFOOD_MAGNIFIQUE_FEAST = { name = "Seafood Magnifique Feast", itemID = 62290, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 4, kind = "FOOD", price = 1200, use = "WELL_FED" },
    -- 5
    GHOST_IRON_ORE = { name = "Ghost Iron Ore", itemID = 72092, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 5, kind = "ORE", price = 650 },
    GREEN_TEA_LEAF = { name = "Green Tea Leaf", itemID = 72234, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 5, kind = "HERB", price = 650 },
    MIST_TOUCHED_LEATHER = { name = "Mist-Touched Leather", itemID = 72120, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 5, kind = "LEATHER", price = 720 },
    JADE_LUNGFISH = { name = "Jade Lungfish", itemID = 74856, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 5, kind = "FISH", price = 590 },
    WINDWOOL_CLOTH = { name = "Windwool Cloth", itemID = 72988, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 5, kind = "CLOTH", price = 780 },
    SPIRIT_OF_HARMONY = { name = "Spirit of Harmony", itemID = 76061, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 5, kind = "RARE", price = 16000 },
    GHOST_IRON_BAR = { name = "Ghost Iron Bar", itemID = 72096, icon = I .. "INV_Ingot_02", quality = 1, tier = 5, kind = "BAR", price = 1800 },
    MASTER_HEALING_POTION = { name = "Master Healing Potion", itemID = 76097, icon = I .. "INV_Potion_51", quality = 1, tier = 5, kind = "POTION", price = 2300, use = "STOCKED_INFIRMARY" },
    BANQUET_OF_THE_GRILL = { name = "Banquet of the Grill", itemID = 87226, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 5, kind = "FOOD", price = 2200, use = "WELL_FED" },
    -- 6
    TRUE_IRON_ORE = { name = "True Iron Ore", itemID = 109119, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 6, kind = "ORE", price = 1200 },
    FROSTWEED = { name = "Frostweed", itemID = 109124, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 6, kind = "HERB", price = 1200 },
    RAW_BEAST_HIDE = { name = "Raw Beast Hide", itemID = 110609, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 6, kind = "LEATHER", price = 1400 },
    FAT_SLEEPER_FLESH = { name = "Fat Sleeper Flesh", itemID = 109139, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 6, kind = "FISH", price = 1100 },
    SUMPTUOUS_FUR = { name = "Sumptuous Fur", itemID = 111557, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 6, kind = "CLOTH", price = 1500 },
    PRIMAL_SPIRIT = { name = "Primal Spirit", itemID = 120945, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 2, tier = 6, kind = "RARE", price = 30000 },
    TRUESTEEL_INGOT = { name = "Truesteel Ingot", itemID = 108257, icon = I .. "INV_Ingot_02", quality = 2, tier = 6, kind = "BAR", price = 3500 },
    HEALING_TONIC = { name = "Healing Tonic", itemID = 109223, icon = I .. "INV_Potion_51", quality = 1, tier = 6, kind = "POTION", price = 4500, use = "STOCKED_INFIRMARY" },
    FEAST_OF_BLOOD = { name = "Feast of Blood", itemID = 111457, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 6, kind = "FOOD", price = 4200, use = "WELL_FED" },
    -- 7
    LEYSTONE_ORE = { name = "Leystone Ore", itemID = 123918, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 7, kind = "ORE", price = 2400 },
    AETHRIL = { name = "Aethril", itemID = 124101, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 7, kind = "HERB", price = 2400 },
    STONEHIDE_LEATHER = { name = "Stonehide Leather", itemID = 124113, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 7, kind = "LEATHER", price = 2600 },
    HIGHMOUNTAIN_SALMON = { name = "Highmountain Salmon", itemID = 124109, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 7, kind = "FISH", price = 2100 },
    SHALDOREI_SILK = { name = "Shal'dorei Silk", itemID = 124437, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 7, kind = "CLOTH", price = 2800 },
    BLOOD_OF_SARGERAS = { name = "Blood of Sargeras", itemID = 124124, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 7, kind = "RARE", price = 56000 },
    INFERNAL_BRIMSTONE = { name = "Infernal Brimstone", itemID = 124444, icon = I .. "INV_Ingot_02", quality = 2, tier = 7, kind = "BAR", price = 6600 },
    ANCIENT_HEALING_POTION = { name = "Ancient Healing Potion", itemID = 127834, icon = I .. "INV_Potion_51", quality = 1, tier = 7, kind = "POTION", price = 8500, use = "STOCKED_INFIRMARY" },
    LAVISH_SURAMAR_FEAST = { name = "Lavish Suramar Feast", itemID = 133579, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 7, kind = "FOOD", price = 8000, use = "WELL_FED" },
    -- 8
    MONELITE_ORE = { name = "Monelite Ore", itemID = 152512, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 8, kind = "ORE", price = 4500 },
    RIVERBUD = { name = "Riverbud", itemID = 152505, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 8, kind = "HERB", price = 4500 },
    COARSE_LEATHER = { name = "Coarse Leather", itemID = 152541, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 8, kind = "LEATHER", price = 4900 },
    GREAT_SEA_CATFISH = { name = "Great Sea Catfish", itemID = 152547, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 8, kind = "FISH", price = 4000 },
    TIDESPRAY_LINEN = { name = "Tidespray Linen", itemID = 152576, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 8, kind = "CLOTH", price = 5400 },
    EXPULSOM = { name = "Expulsom", itemID = 152668, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 8, kind = "RARE", price = 110000 },
    HYDROCORE = { name = "Hydrocore", itemID = 162460, icon = I .. "INV_Ingot_02", quality = 3, tier = 8, kind = "BAR", price = 13000 },
    COASTAL_HEALING_POTION = { name = "Coastal Healing Potion", itemID = 152494, icon = I .. "INV_Potion_51", quality = 1, tier = 8, kind = "POTION", price = 16000, use = "STOCKED_INFIRMARY" },
    BOUNTIFUL_CAPTAINS_FEAST = { name = "Bountiful Captain's Feast", itemID = 156526, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 8, kind = "FOOD", price = 15000, use = "WELL_FED" },
    -- 9
    LAESTRITE_ORE = { name = "Laestrite Ore", itemID = 171828, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 9, kind = "ORE", price = 8500 },
    DEATH_BLOSSOM = { name = "Death Blossom", itemID = 169701, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 9, kind = "HERB", price = 8500 },
    DESOLATE_LEATHER = { name = "Desolate Leather", itemID = 172089, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 9, kind = "LEATHER", price = 9300 },
    LOST_SOLE = { name = "Lost Sole", itemID = 173032, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 9, kind = "FISH", price = 7600 },
    SHROUDED_CLOTH = { name = "Shrouded Cloth", itemID = 173202, icon = I .. "INV_Fabric_Linen_01", quality = 1, tier = 9, kind = "CLOTH", price = 10000 },
    ELETHIUM_ORE = { name = "Elethium Ore", itemID = 171833, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 9, kind = "RARE", price = 200000 },
    SHADOWGHAST_INGOT = { name = "Shadowghast Ingot", itemID = 171428, icon = I .. "INV_Ingot_02", quality = 2, tier = 9, kind = "BAR", price = 24000 },
    SPIRITUAL_HEALING_POTION = { name = "Spiritual Healing Potion", itemID = 171267, icon = I .. "INV_Potion_51", quality = 1, tier = 9, kind = "POTION", price = 31000, use = "STOCKED_INFIRMARY" },
    FEAST_OF_GLUTTONOUS_HEDONISM = { name = "Feast of Gluttonous Hedonism", itemID = 172043, icon = I .. "INV_Misc_Food_15", quality = 1, tier = 9, kind = "FOOD", price = 29000, use = "WELL_FED" },
    -- 10
    SEREVITE_ORE = { name = "Serevite Ore", itemID = 190395, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 10, kind = "ORE", price = 16000 },
    HOCHENBLUME = { name = "Hochenblume", itemID = 191460, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 10, kind = "HERB", price = 16000 },
    RESILIENT_LEATHER = { name = "Resilient Leather", itemID = 193208, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 10, kind = "LEATHER", price = 18000 },
    SCALEBELLY_MACKEREL = { name = "Scalebelly Mackerel", itemID = 194730, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 10, kind = "FISH", price = 15000 },
    WILDERCLOTH = { name = "Wildercloth", itemID = 193922, icon = I .. "INV_Fabric_Linen_01", quality = 2, tier = 10, kind = "CLOTH", price = 19000 },
    SPARK_OF_INGENUITY = { name = "Spark of Ingenuity", itemID = 190453, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 4, tier = 10, kind = "RARE", price = 390000 },
    PRIMAL_MOLTEN_ALLOY = { name = "Primal Molten Alloy", itemID = 189541, icon = I .. "INV_Ingot_02", quality = 3, tier = 10, kind = "BAR", price = 45000 },
    REFRESHING_HEALING_POTION = { name = "Refreshing Healing Potion", itemID = 191378, icon = I .. "INV_Potion_51", quality = 1, tier = 10, kind = "POTION", price = 58000, use = "STOCKED_INFIRMARY" },
    GRAND_BANQUET_OF_THE_KALUAK = { name = "Grand Banquet of the Kalu'ak", itemID = 197794, icon = I .. "INV_Misc_Food_15", quality = 3, tier = 10, kind = "FOOD", price = 55000, use = "WELL_FED" },
    -- 11
    BISMUTH = { name = "Bismuth", itemID = 210930, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 11, kind = "ORE", price = 31000 },
    MYCOBLOOM = { name = "Mycobloom", itemID = 210796, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 11, kind = "HERB", price = 31000 },
    STORMCHARGED_LEATHER = { name = "Stormcharged Leather", itemID = 212664, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 11, kind = "LEATHER", price = 34000 },
    BISMUTH_BITTERLING = { name = "Bismuth Bitterling", itemID = 220137, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 11, kind = "FISH", price = 28000 },
    WEAVERCLOTH = { name = "Weavercloth", itemID = 224828, icon = I .. "INV_Fabric_Linen_01", quality = 2, tier = 11, kind = "CLOTH", price = 37000 },
    SPARK_OF_OMENS = { name = "Spark of Omens", itemID = 211296, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 4, tier = 11, kind = "RARE", price = 740000 },
    CORE_ALLOY = { name = "Core Alloy", itemID = 222417, icon = I .. "INV_Ingot_02", quality = 2, tier = 11, kind = "BAR", price = 86000 },
    ALGARI_HEALING_POTION = { name = "Algari Healing Potion", itemID = 211878, icon = I .. "INV_Potion_51", quality = 1, tier = 11, kind = "POTION", price = 110000, use = "STOCKED_INFIRMARY" },
    FEAST_OF_THE_DIVINE_DAY = { name = "Feast of the Divine Day", itemID = 222732, icon = I .. "INV_Misc_Food_15", quality = 4, tier = 11, kind = "FOOD", price = 100000, use = "WELL_FED" },
    -- 12
    REFULGENT_COPPER_ORE = { name = "Refulgent Copper Ore", itemID = 237359, icon = I .. "INV_Ore_Copper_01", quality = 1, tier = 12, kind = "ORE", price = 58000 },
    TRANQUILITY_BLOOM = { name = "Tranquility Bloom", itemID = 236761, icon = I .. "INV_Misc_Flower_02", quality = 1, tier = 12, kind = "HERB", price = 58000 },
    VOID_TEMPERED_LEATHER = { name = "Void-Tempered Leather", itemID = 238511, icon = I .. "INV_Misc_LeatherScrap_03", quality = 1, tier = 12, kind = "LEATHER", price = 64000 },
    LYNXFISH = { name = "Lynxfish", itemID = 238366, icon = I .. "INV_Misc_Fish_02", quality = 1, tier = 12, kind = "FISH", price = 52000 },
    BRIGHT_LINEN = { name = "Bright Linen", itemID = 236963, icon = I .. "INV_Fabric_Linen_01", quality = 2, tier = 12, kind = "CLOTH", price = 70000 },
    NOCTURNAL_LOTUS = { name = "Nocturnal Lotus", itemID = 236780, icon = I .. "INV_Misc_Gem_Pearl_04", quality = 3, tier = 12, kind = "RARE", price = 1400000 },
    REFULGENT_COPPER_INGOT = { name = "Refulgent Copper Ingot", itemID = 238197, icon = I .. "INV_Ingot_02", quality = 2, tier = 12, kind = "BAR", price = 160000 },
    SILVERMOON_HEALTH_POTION = { name = "Silvermoon Health Potion", itemID = 241305, icon = I .. "INV_Potion_51", quality = 1, tier = 12, kind = "POTION", price = 210000, use = "STOCKED_INFIRMARY" },
    BLOOMING_FEAST = { name = "Blooming Feast", itemID = 242273, icon = I .. "INV_Misc_Food_15", quality = 3, tier = 12, kind = "FOOD", price = 200000, use = "WELL_FED" },
}

D.GEAR_SLOTS = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "WEAPON", "TRINKET" }

-- Real drops from each tier's dungeons and raid (JournalEncounterItem), used for icon + name.
D.GEAR_BASES = {
    [1] = {
        HEAD = { { itemID = 18870, name = "Helm of the Lifegiver" }, { itemID = 144026, name = "Helm of Rising Flame" }, { itemID = 224740, name = "Forgemaster's Faceshield" } },
        SHOULDER = { { itemID = 144001, name = "Forgotten Bloodmage Mantle" }, { itemID = 13538, name = "Windshrieker Pauldrons" }, { itemID = 13533, name = "Acid-Etched Pauldrons" } },
        CHEST = { { itemID = 10399, name = "Blackened Defias Armor" }, { itemID = 13535, name = "Coldtouch Phantom Wraps" }, { itemID = 143965, name = "Korloff's Raiment" } },
        HANDS = { { itemID = 13539, name = "Banshee's Touch" }, { itemID = 16863, name = "Gauntlets of Might" }, { itemID = 18730, name = "Shadowy Laced Handwraps" } },
        LEGS = { { itemID = 144002, name = "Legguards of the Crimson Magus" }, { itemID = 18861, name = "Flamewaker Legplates" }, { itemID = 13531, name = "Crypt Stalker Leggings" } },
        FEET = { { itemID = 16800, name = "Arcanist Boots" }, { itemID = 16829, name = "Cenarion Boots" }, { itemID = 16837, name = "Earthfury Boots" } },
        WEAPON = { { itemID = 13534, name = "Banshee Finger" }, { itemID = 1937, name = "Buzz Saw" }, { itemID = 18729, name = "Screeching Bow" } },
        TRINKET = { { itemID = 144158, name = "Flashing Steel Talisman" }, { itemID = 18820, name = "Talisman of Ephemeral Power" }, { itemID = 13515, name = "Ramstein's Lightning Bolts" } },
    },
    [2] = {
        HEAD = { { itemID = 27888, name = "Dream-Wing Helm" }, { itemID = 29983, name = "Fel-Steel Warhelm" }, { itemID = 29986, name = "Cowl of the Grand Engineer" } },
        SHOULDER = { { itemID = 133465, name = "Shoulderplates of Everlasting Pain" }, { itemID = 27776, name = "Shoulderpads of Assassination" }, { itemID = 27775, name = "Hallowed Pauldrons" } },
        CHEST = { { itemID = 29921, name = "Fire Crest Breastplate" }, { itemID = 27897, name = "Breastplate of Many Graces" }, { itemID = 27912, name = "Harness of the Deep Currents" } },
        HANDS = { { itemID = 133434, name = "Gauntlets of Divine Blessings" }, { itemID = 27468, name = "Moonglade Handwraps" }, { itemID = 29976, name = "Worldstorm Gauntlets" } },
        LEGS = { { itemID = 133435, name = "Leggings of the Betrayed" }, { itemID = 27936, name = "Greaves of Desolation" }, { itemID = 27908, name = "Leggings of Assassination" } },
        FEET = { { itemID = 27914, name = "Moonstrider Boots" }, { itemID = 27884, name = "Ornate Boots of the Sanctified" }, { itemID = 27915, name = "Sky-Hunter Swift Boots" } },
        WEAPON = { { itemID = 27885, name = "Soul-Wand of the Aldor" }, { itemID = 133433, name = "Sun-Forged Cleaver" }, { itemID = 29924, name = "Netherbane" } },
        TRINKET = { { itemID = 27891, name = "Adamantine Figurine" }, { itemID = 30447, name = "Tome of Fiery Redemption" }, { itemID = 30448, name = "Talon of Al'ar" } },
    },
    [3] = {
        HEAD = { { itemID = 133488, name = "Polished Mirror Helm" }, { itemID = 49952, name = "Snowserpent Mail Helm" }, { itemID = 133501, name = "Skeleton Lord's Cranium" } },
        SHOULDER = { { itemID = 127504, name = "Iron Dwarf Smith Pauldrons" }, { itemID = 127482, name = "Silent Spectator Shoulderpads" }, { itemID = 36982, name = "Mantle of Electrical Charges" } },
        CHEST = { { itemID = 49951, name = "Gendarme's Cuirass" }, { itemID = 133508, name = "Shroud of Rime" }, { itemID = 127502, name = "Ymirjar Physician's Robe" } },
        HANDS = { { itemID = 127506, name = "Traditionally Dyed Handguards" }, { itemID = 127461, name = "Tear-Linked Gauntlets" }, { itemID = 49979, name = "Handguards of Winter's Respite" } },
        LEGS = { { itemID = 127505, name = "Patroller's War-Kilt" }, { itemID = 127483, name = "Sorrowgrave's Breeches" }, { itemID = 49964, name = "Legguards of Lost Hope" } },
        FEET = { { itemID = 49950, name = "Frostbitten Fur Boots" }, { itemID = 127478, name = "Berserker's Sabatons" }, { itemID = 133489, name = "Ice-Steeped Sandals" } },
        WEAPON = { { itemID = 127458, name = "Ritualistic Athame" }, { itemID = 133485, name = "Unspeakable Secret" }, { itemID = 127459, name = "Brazier Igniter" } },
        TRINKET = { { itemID = 50339, name = "Sliver of Pure Ice" }, { itemID = 127512, name = "Winged Talisman" }, { itemID = 252421, name = "Rotting Globule" } },
    },
    [4] = {
        HEAD = { { itemID = 133234, name = "Headcover of Fog" }, { itemID = 171702, name = "Cowl of the Clicking Menace" }, { itemID = 69614, name = "Roaring Mask of Bethekk" } },
        SHOULDER = { { itemID = 133208, name = "Cinnabar Shoulders" }, { itemID = 133235, name = "Fallen Snow Shoulderguards" }, { itemID = 171697, name = "Flickering Shoulders" } },
        CHEST = { { itemID = 171658, name = "Carapace of Imbibed Flame" }, { itemID = 69603, name = "Breastplate of Serenity" }, { itemID = 171703, name = "Robes of Smoldering Devastation" } },
        HANDS = { { itemID = 69630, name = "Handguards of the Tormented" }, { itemID = 69633, name = "Plunderer's Gauntlets" }, { itemID = 69619, name = "Bone Plate Handguards" } },
        LEGS = { { itemID = 69601, name = "Serpentine Leggings" }, { itemID = 171698, name = "Cinderweb Leggings" }, { itemID = 171704, name = "Thoracic Flame Kilt" } },
        FEET = { { itemID = 171696, name = "Arachnaflame Treads" }, { itemID = 69634, name = "Fasc's Preserved Boots" }, { itemID = 133253, name = "Darksky Treads" } },
        WEAPON = { { itemID = 133207, name = "Fist of Pained Senses" }, { itemID = 133233, name = "Biting Wind" }, { itemID = 171664, name = "Mandible of Beth'tilac" } },
        TRINKET = { { itemID = 133206, name = "Key to the Endless Chamber" }, { itemID = 171643, name = "Spidersilk Spindle" }, { itemID = 133252, name = "Rainsong" } },
    },
    [5] = {
        HEAD = { { itemID = 144020, name = "Crest of the Clan Lords" }, { itemID = 144021, name = "Meteoric Greathelm" }, { itemID = 94724, name = "Lightning-Eye Hood" } },
        SHOULDER = { { itemID = 94725, name = "Static-Shot Shoulderguards" }, { itemID = 143969, name = "Fizzy Spaulders" }, { itemID = 94733, name = "Fissure-Split Shoulderwraps" } },
        CHEST = { { itemID = 143957, name = "Nimbletoe Chestguard" }, { itemID = 143961, name = "Azure Serpent Chestguard" }, { itemID = 94723, name = "Chestplate of Violent Detonation" } },
        HANDS = { { itemID = 144106, name = "Gauntlets of Resolute Fury" }, { itemID = 144151, name = "Axebreaker Gauntlets" }, { itemID = 94737, name = "Lightningweaver Gauntlets" } },
        LEGS = { { itemID = 143978, name = "Leggings of the Charging Soul" }, { itemID = 143975, name = "Hopping Mad Leggings" }, { itemID = 94728, name = "Spearman's Jingling Leggings" } },
        FEET = { { itemID = 143989, name = "Barreldodger Boots" }, { itemID = 143992, name = "Glintrok Sollerets" }, { itemID = 143985, name = "Spike-Soled Stompers" } },
        WEAPON = { { itemID = 94722, name = "Worldbreaker's Stormscythe" }, { itemID = 144084, name = "Ook's Hozen Slicer" }, { itemID = 144110, name = "Snowdrift's Bladed Staff" } },
        TRINKET = { { itemID = 94512, name = "Renataki's Soul Charm" }, { itemID = 144119, name = "Empty Fruit Barrel" }, { itemID = 144146, name = "Iron Protector Talisman" } },
    },
    [6] = {
        HEAD = { { itemID = 113880, name = "Acidic Jaws" }, { itemID = 116257, name = "Acid-Munched Greathelm" }, { itemID = 113910, name = "Hardened Greathelm" } },
        SHOULDER = { { itemID = 113884, name = "Unstable Slag Shoulderplates" }, { itemID = 113899, name = "Neckbreaker Shoulderguards" }, { itemID = 113903, name = "Giant Pumpers" } },
        CHEST = { { itemID = 113881, name = "Chestplate of Rolling Fury" }, { itemID = 113898, name = "Eye-Catching Gilded Robe" }, { itemID = 113902, name = "Chestguard of Unending Roars" } },
        HANDS = { { itemID = 113876, name = "Toothbreaker Grips" }, { itemID = 109848, name = "Gauntlets of Burning Focus" }, { itemID = 109849, name = "Bloodfeather Grips" } },
        LEGS = { { itemID = 113875, name = "Corrosion-Proof Legguards" }, { itemID = 109804, name = "Trousers of Arcane Mystery" }, { itemID = 109805, name = "Frost-Touched Legwraps" } },
        FEET = { { itemID = 116021, name = "Chasmwalker Sandals" }, { itemID = 116034, name = "Drop Kickers" }, { itemID = 116238, name = "Heel Protectors" } },
        WEAPON = { { itemID = 113874, name = "Oregorger's Acid-Etched Gutripper" }, { itemID = 116380, name = "Oregorger's Venomous Canine" }, { itemID = 116381, name = "Oregorger's Blackrock Shanker" } },
        TRINKET = { { itemID = 119194, name = "Goren Soul Repository" }, { itemID = 113905, name = "Tablet of Turnbuckle Teamwork" }, { itemID = 109999, name = "Witherbark's Branch" } },
    },
    [7] = {
        HEAD = { { itemID = 151943, name = "Crown of Relentless Annihilation" }, { itemID = 142296, name = "Wikket Witch's Hat" }, { itemID = 134216, name = "Bonespeaker Cowl" } },
        SHOULDER = { { itemID = 151988, name = "Shoulderpads of the Demonic Blitz" }, { itemID = 134213, name = "Tideskorn Mantle" }, { itemID = 139121, name = "Skyhorn Mantle" } },
        CHEST = { { itemID = 137336, name = "Vest of Rupturing Diamonds" }, { itemID = 134179, name = "Skoldiir Breastplate" }, { itemID = 152017, name = "Soul-Tempered Chestplate" } },
        HANDS = { { itemID = 133628, name = "Battleborne Sentinel Gauntlets" }, { itemID = 142205, name = "Jabber Grookin' Gauntlets" }, { itemID = 151998, name = "Heedless Eradication Gauntlets" } },
        LEGS = { { itemID = 134427, name = "Riverrider Legwraps" }, { itemID = 151987, name = "Breach-Blocker Legguards" }, { itemID = 134194, name = "Biornskin Leggings" } },
        FEET = { { itemID = 142204, name = "Boots of False Promises" }, { itemID = 142298, name = "Astonishingly Scarlet Slippers" }, { itemID = 139105, name = "Rivermane Sandals" } },
        WEAPON = { { itemID = 201997, name = "Key to the Halls" }, { itemID = 205973, name = "Rod of Crystalline Energies" }, { itemID = 201998, name = "Fenryr's Bloodstained Fang" } },
        TRINKET = { { itemID = 133642, name = "Horn of Valor" }, { itemID = 151956, name = "Garothi Feedback Conduit" }, { itemID = 151962, name = "Prototype Personnel Decimator" } },
    },
    [8] = {
        HEAD = { { itemID = 174132, name = "Stygian Guise" }, { itemID = 155885, name = "Sea-Brawler's Greathelm" }, { itemID = 155886, name = "Smartly Plumed Cap" } },
        SHOULDER = { { itemID = 174152, name = "Pauldrons of Ill Portent" }, { itemID = 158304, name = "Mantle of Fastidious Machinations" }, { itemID = 159267, name = "Pauldrons of Vile Corruption" } },
        CHEST = { { itemID = 174119, name = "Robes of Unreality" }, { itemID = 155860, name = "Spymaster's Wrap" }, { itemID = 159241, name = "Blood-Drenched Robes" } },
        HANDS = { { itemID = 174153, name = "Ebony Scaled Gauntlets" }, { itemID = 158317, name = "Gauntlets of Eternal Service" }, { itemID = 159344, name = "Underrot Grotto Tenders" } },
        LEGS = { { itemID = 159443, name = "Legplates of Profane Sacrifice" }, { itemID = 158313, name = "Legplates of Beaten Gold" }, { itemID = 174139, name = "Onyx-Imbued Breeches" } },
        FEET = { { itemID = 155862, name = "Kragg's Rigging Scalers" }, { itemID = 155861, name = "Embellished Ritual Sabatons" }, { itemID = 158351, name = "Dashing Bilge Rat Shoes" } },
        WEAPON = { { itemID = 172185, name = "Destroyer's Shadowblade" }, { itemID = 172199, name = "Faralos, Empire's Dream" }, { itemID = 174105, name = "Mish'un, Blade of Tyrants" } },
        TRINKET = { { itemID = 174044, name = "Humming Black Dragonscale" }, { itemID = 158319, name = "My'das Talisman" }, { itemID = 159624, name = "Rotcrusted Voodoo Doll" } },
    },
    [9] = {
        HEAD = { { itemID = 178692, name = "Soulthorn Visage" }, { itemID = 178694, name = "Wrathbark Greathelm" }, { itemID = 178732, name = "Abominable Visage" } },
        SHOULDER = { { itemID = 178696, name = "Ingra Maloch's Mantle" }, { itemID = 178733, name = "Blightbone Spaulders" }, { itemID = 186298, name = "Smuggler's Plundered Pauldrons" } },
        CHEST = { { itemID = 178698, name = "Rainshadow Hauberk" }, { itemID = 186303, name = "Colossus Slayer's Hauberk" }, { itemID = 186296, name = "Mawsworn Eviscerator's Cuirass" } },
        HANDS = { { itemID = 185791, name = "Knuckle-Dusting Handwraps" }, { itemID = 186311, name = "Cavalier Oathbreaker's Grasps" }, { itemID = 185792, name = "Achillite's Unbreakable Grip" } },
        LEGS = { { itemID = 186285, name = "Sorcerer's Headlong Legwraps" }, { itemID = 178739, name = "Legplates of Unholy Frenzy" }, { itemID = 178701, name = "Gormshell Greaves" } },
        FEET = { { itemID = 178731, name = "Viscera-Stitched Footpads" }, { itemID = 186281, name = "Phantasma-Forged Striders" }, { itemID = 186318, name = "Champion's Gruesome Greaves" } },
        WEAPON = { { itemID = 178730, name = "Engorged Worm Smasher" }, { itemID = 178735, name = "Blight Belcher" }, { itemID = 178709, name = "Scithewood Scepter" } },
        TRINKET = { { itemID = 178708, name = "Unbound Changeling" }, { itemID = 178742, name = "Bottled Flayedwing Toxin" }, { itemID = 186422, name = "Tome of Monstrous Constructions" } },
    },
    [10] = {
        HEAD = { { itemID = 207133, name = "Silent Tormentor's Hood" }, { itemID = 193726, name = "Amphibian's Bellowing Crown" }, { itemID = 193765, name = "Blazebound Lieutenant's Helm" } },
        SHOULDER = { { itemID = 207117, name = "Requiem Rootmantle" }, { itemID = 193725, name = "Ancient Hornswog Spaulders" }, { itemID = 207140, name = "Drakestalker's Trophy Pauldrons" } },
        CHEST = { { itemID = 207142, name = "Ancient Haubark" }, { itemID = 193764, name = "Invader's Firestorm Chestguard" }, { itemID = 193720, name = "Bronze Challenger's Robe" } },
        HANDS = { { itemID = 193758, name = "Subjugator's Chilling Grips" }, { itemID = 193746, name = "Gauntlets of Incalculable Power" }, { itemID = 193752, name = "Galerattle Gauntlets" } },
        LEGS = { { itemID = 193759, name = "Egg Tender's Leggings" }, { itemID = 207153, name = "Seared Ironwood Greaves" }, { itemID = 193750, name = "Wind Soarer's Breeches" } },
        FEET = { { itemID = 193728, name = "Scaleguard's Stalwart Greatboots" }, { itemID = 207126, name = "Twisted Blossom Stompers" }, { itemID = 193715, name = "Boots of Explosive Growth" } },
        WEAPON = { { itemID = 193710, name = "Spellboon Saber" }, { itemID = 193711, name = "Spellbane Cutlass" }, { itemID = 193761, name = "Chillworn's Infusion Staff" } },
        TRINKET = { { itemID = 193743, name = "Irideus Fragment" }, { itemID = 193757, name = "Ruby Whelp Shell" }, { itemID = 193762, name = "Blazebinder's Hoof" } },
    },
    [11] = {
        HEAD = { { itemID = 228858, name = "Fullthrottle Facerig" }, { itemID = 221055, name = "Cinderbrew-Soaked Cowl" }, { itemID = 234498, name = "Waterworks Filtration Mask" } },
        SHOULDER = { { itemID = 234500, name = "Mechanized Junkpads" }, { itemID = 221052, name = "Foam-Ridden Pauldrons" }, { itemID = 234503, name = "Skystreak's Hidden Missiles" } },
        CHEST = { { itemID = 228852, name = "Blazer of Glory" }, { itemID = 234502, name = "Bront's Singed Blastcoat" }, { itemID = 234506, name = "Muckdiver's Wading Plate" } },
        HANDS = { { itemID = 221080, name = "Corpseleecher Grips" }, { itemID = 221086, name = "Machinist's Searing Handguards" }, { itemID = 234504, name = "Jumpstarter's Scaffold-Scrapers" } },
        LEGS = { { itemID = 246278, name = "Overpressure Platelegs" }, { itemID = 228865, name = "Pit Doctor's Petticoat" }, { itemID = 221076, name = "E.D.N.A. Stabilizers" } },
        FEET = { { itemID = 234497, name = "Nonconductive Kill-o-Socks" }, { itemID = 228862, name = "Shrapnel-Ridden Sabatons" }, { itemID = 228876, name = "Dragster's Last Stride" } },
        WEAPON = { { itemID = 234491, name = "Sonic Ka-BOOM!-erang" }, { itemID = 221051, name = "Crusher of the Unsettled" }, { itemID = 221074, name = "Augmented Refractor Cannon" } },
        TRINKET = { { itemID = 219300, name = "Skarmorak Shard" }, { itemID = 219297, name = "Cinderbrew Stein" }, { itemID = 232542, name = "Darkfuse Medichopper" } },
    },
    [12] = {
        HEAD = { { itemID = 249306, name = "Devouring Night's Visage" }, { itemID = 251080, name = "Brambledawn Halo" }, { itemID = 251109, name = "Spellsnap Shadowmask" } },
        SHOULDER = { { itemID = 251146, name = "Scavenger's Spaulders" }, { itemID = 249313, name = "Light-Judged Spaulders" }, { itemID = 251085, name = "Mantle of Dark Devotion" } },
        CHEST = { { itemID = 251101, name = "Arcane Guardian's Shell" }, { itemID = 249310, name = "Robes of the Voidbound" }, { itemID = 251147, name = "Hoarded Harvest Wrap" } },
        HANDS = { { itemID = 251081, name = "Embergrove Grasps" }, { itemID = 251152, name = "Season's Turn Gauntlets" }, { itemID = 251089, name = "Grips of Forgotten Honor" } },
        LEGS = { { itemID = 251104, name = "Leggings of Orderly Conduct" }, { itemID = 249323, name = "Leggings of the Devouring Advance" }, { itemID = 251087, name = "Legwraps of Lingering Legacies" } },
        FEET = { { itemID = 251145, name = "Forgotten Tribe Footguards" }, { itemID = 249320, name = "Sabatons of Obscurement" }, { itemID = 251107, name = "Oathsworn Stompers" } },
        WEAPON = { { itemID = 251100, name = "Malfeasance Mallet" }, { itemID = 251077, name = "Roostwarden's Bough" }, { itemID = 249279, name = "Sunstrike Rifle" } },
        TRINKET = { { itemID = 250246, name = "Refueling Orb" }, { itemID = 250144, name = "Emberwing Feather" }, { itemID = 250248, name = "Mycolic Medicine" } },
    },
}

-- D.TIER_ITEMS[tier][kind] = itemKey (schema addition, derived)
D.TIER_ITEMS = {}
for key, item in pairs(D.ITEMS) do
    D.TIER_ITEMS[item.tier] = D.TIER_ITEMS[item.tier] or {}
    D.TIER_ITEMS[item.tier][item.kind] = key
end
