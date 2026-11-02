local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Progress.lua — bonuses, buffs, collection, achievements, stats/log, New Era (prestige)
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
local ERA_PACE = 0.10                 -- each era: +10% xp and gold; with Legacy ~ +20% per era (15-20% faster)
local ERA_SPEED = 0.03                -- each era: +3% mission speed
local ERA_SPEED_MAX = 0.20
local LEGACY_XP = 0.0015              -- per Legacy point
local LEGACY_GOLD = 0.0015
local LEGACY_BONUS_MAX = 0.50
local ERA_HERO_EVERY = 2              -- +1 recruit slot every 2 eras ...
local ERA_HERO_MAX = 3                -- ... up to 3
local LEGACY_BASE = 25                -- legacy gained per finished era ...
local LEGACY_PER_POINTS = 50          -- ... + 1 per 50 achievement points ...
local LEGACY_PER_CLEARS = 20          -- ... + 1 per 20 instance clears this era
local LEGACY_PER_MOUNT = 1            -- ... + 1 per mount owned

-- stat aliases, so the data's achievement stat names map onto what the engine counts
local STAT_ALIAS = {
    GOLD = "GOLD_EARNED", LEVEL = "MAX_LEVEL", HERO_LEVEL = "MAX_LEVEL", TIER = "MAX_TIER",
    DUNGEON_CLEARS = "DUNGEONS", RAID_CLEARS = "RAIDS", CRAFTED = "CRAFTS", CRAFT = "CRAFTS",
    RECRUITS = "HEROES", MISSIONS = "TASKS", QUESTS_DONE = "QUESTS", GATHERED = "GATHERS",
    SOLD = "ITEMS_SOLD", ILVL = "MAX_ILVL", ERAS = "ERA", BUILDING_UPGRADES = "BUILDINGS",
    UPGRADES = "BUILDINGS", SUCCESS = "SUCCESSES", BOSS_KILLS = "BOSSES",
    -- the data's names (Data\Collection.lua)
    GATHER_TASKS = "GATHERS", QUEST_TASKS = "QUESTS", HEROES_RECRUITED = "HEROES", HIGHEST_HERO_LEVEL = "MAX_LEVEL",
    HIGHEST_TIER = "MAX_TIER", FAILED_TASKS = "FAILURES",
    -- also counted directly: ITEMS_GATHERED, RAIDS_TIER<n> (e.g. RAIDS_TIER12), GEAR_CRAFTED_EPIC
}

----------------------------------------------------------------------------------------------------
-- bonuses: traits + buffs + buildings + era/legacy, as a fraction (0.15 = +15%)
----------------------------------------------------------------------------------------------------
function Game:EraBonus(kind)
    local db = self.db
    local era, legacy = (db.era or 1) - 1, db.legacy or 0
    if kind == "XP" then
        return era * ERA_PACE + math.min(LEGACY_BONUS_MAX, legacy * LEGACY_XP)
    elseif kind == "GOLD" then
        return era * ERA_PACE + math.min(LEGACY_BONUS_MAX, legacy * LEGACY_GOLD)
    elseif kind == "SPEED" then
        return math.min(ERA_SPEED_MAX, era * ERA_SPEED)
    end
    return 0
end

function Game:EraHeroBonus()
    local db = self.db
    if not db then return 0 end
    return math.min(ERA_HERO_MAX, math.floor(((db.era or 1) - 1) / ERA_HERO_EVERY))
end

function Game:BuffBonus(kind, t)
    local B = ns.D.BUFFS or {}
    local sum = 0
    for key, exp in pairs(self.db.buffs) do
        local def = B[key]
        if def and self:TraitKind(def) == kind and exp > (t or self:Now()) then sum = sum + (def.value or 0) end
    end
    return sum
end

function Game:Bonus(kind, heroes, ctx, t)
    local sum = self:BuffBonus(kind, t) + self:BuildingBonus(kind, ctx) + self:EraBonus(kind)
    if heroes then sum = sum + self:TraitBonus(heroes, kind, ctx) end
    return sum
end

----------------------------------------------------------------------------------------------------
-- buffs
----------------------------------------------------------------------------------------------------
function Game:GetBuffs()
    local now = self:Now()
    local B = ns.D.BUFFS or {}
    local out = {}
    for _, key in ipairs(self:SortedKeys(self.db.buffs)) do
        local exp = self.db.buffs[key]
        if exp > now and B[key] then out[#out + 1] = { key = key, def = B[key], expiresAt = exp } end
    end
    table.sort(out, function(a, b) return a.expiresAt < b.expiresAt end)
    return out
end

function Game:GrantBuff(key)
    local def = ns.D.BUFFS and ns.D.BUFFS[key]
    if not def then return false, "Unknown buff." end
    local now = self:Now()
    local exp = now + (def.duration or 3600)
    if (self.db.buffs[key] or 0) < exp then self.db.buffs[key] = exp end
    self:AddStat("BUFFS")
    self:Log((def.name or key) .. " is active.")
    self:Changed("all")
    return true
end

function Game:ExpireBuffs(t)
    local changed = false
    for key, exp in pairs(self.db.buffs) do
        if exp <= t then
            self.db.buffs[key] = nil
            changed = true
        end
    end
    if changed then self:Changed("all") end
end

----------------------------------------------------------------------------------------------------
-- collection
----------------------------------------------------------------------------------------------------
function Game:AddMount(mountID, source, t)
    local m = self.db.collection.mounts
    if m[mountID] then return false end
    m[mountID] = { at = t or self:Now(), source = source }
    self:Log("New mount: " .. tostring(source or mountID) .. ".", t)
    self:Changed("collection")
    return true
end

function Game:AddPet(speciesID, source, t)
    local p = self.db.collection.pets
    if p[speciesID] then
        p[speciesID].count = (p[speciesID].count or 1) + 1
        return false
    end
    p[speciesID] = { at = t or self:Now(), source = source, count = 1 }
    self:Log("New pet from " .. tostring(source or speciesID) .. ".", t)
    self:Changed("collection")
    return true
end

function Game:GetCollection()
    return { mounts = self.db.collection.mounts, pets = self.db.collection.pets }
end

----------------------------------------------------------------------------------------------------
-- stats, achievements, log
----------------------------------------------------------------------------------------------------
function Game:StatValue(stat)
    local db = self.db
    stat = STAT_ALIAS[stat] or stat
    if stat == "MOUNTS" then return U.Count(db.collection.mounts) end
    if stat == "PETS" then return U.Count(db.collection.pets) end
    if stat == "ERA" then return db.era or 1 end
    if stat == "LEGACY" then return db.legacy or 0 end
    if stat == "MAX_TIER" then return math.max(db.stats.MAX_TIER or 1, db.tier or 1) end
    if stat == "HEROES_NOW" then return self:HeroCount() end
    if stat == "ACHIEVEMENTS" then return U.Count(db.achievements) end
    if stat == "BUILDING_LEVELS" then
        local n = 0
        for _, b in pairs(db.buildings) do n = n + (b.level or 0) end
        return n
    end
    local b = stat:match("^BUILDING:(.+)$")
    if b then return self:BuildingLevel(b) end
    local ins = stat:match("^CLEAR:(.+)$")
    if ins then return db.clears[ins] or 0 end
    return db.stats[stat] or 0
end

function Game:GetStats()
    local out = U.Copy(self.db.stats)
    out.MOUNTS = self:StatValue("MOUNTS")
    out.PETS = self:StatValue("PETS")
    out.ERA = self.db.era
    out.LEGACY = self.db.legacy
    out.TIER = self.db.tier
    out.MAX_TIER = self:StatValue("MAX_TIER")
    out.HEROES_NOW = self:HeroCount()
    out.BUILDING_LEVELS = self:StatValue("BUILDING_LEVELS")
    out.ACHIEVEMENT_POINTS = self:AchievementPoints()
    out.GOLD = self.db.gold
    return out
end

function Game:GetLog()
    return self.db.log
end

function Game:CheckAchievements(rep, t)
    local A = ns.D.ACHIEVEMENTS or {}
    local got = self.db.achievements
    for _, def in ipairs(A) do
        if def.key and not got[def.key] and def.stat and (def.value or 0) > 0 and self:StatValue(def.stat) >= def.value then
            got[def.key] = { at = t or self:Now() }
            local line = "Achievement: " .. (def.name or def.key)
            if rep then
                rep.achievements[#rep.achievements + 1] = def.key
                rep.lines[#rep.lines + 1] = line .. "."
            end
            self:Log(line .. ".", t)
            local rw = def.reward
            if rw and rw.mountID and self:AddMount(rw.mountID, "Achievement: " .. (def.name or def.key), t) and rep then
                rep.mounts[#rep.mounts + 1] = rw.mountID
            end
            if rw and rw.speciesID and self:AddPet(rw.speciesID, "Achievement: " .. (def.name or def.key), t) and rep then
                rep.pets[#rep.pets + 1] = rw.speciesID
            end
            if rw and rw.title then
                self.db.titles = self.db.titles or {}
                self.db.titles[rw.title] = true
            end
            self:Changed("collection")
        end
    end
end

function Game:GetAchievements()
    local A = ns.D.ACHIEVEMENTS or {}
    local out = {}
    for _, def in ipairs(A) do
        local e = def.key and self.db.achievements[def.key]
        out[#out + 1] = { def = def, earnedAt = e and e.at or nil,
                          progress = math.min(def.value or 0, def.stat and self:StatValue(def.stat) or 0), goal = def.value or 0 }
    end
    return out
end

function Game:AchievementPoints()
    local A = ns.D.ACHIEVEMENTS or {}
    local n = 0
    for _, def in ipairs(A) do
        if def.key and self.db.achievements[def.key] then n = n + (def.points or 0) end
    end
    return n
end

----------------------------------------------------------------------------------------------------
-- New Era
----------------------------------------------------------------------------------------------------
function Game:LegacyGain()
    local db = self.db
    local clears = 0
    for _, n in pairs(db.clears) do clears = clears + n end
    return LEGACY_BASE + math.floor(self:AchievementPoints() / LEGACY_PER_POINTS)
        + math.floor(clears / LEGACY_PER_CLEARS) + LEGACY_PER_MOUNT * U.Count(db.collection.mounts)
end

function Game:EraInfo()
    local db = self.db
    local last = self:Tier(self:NumTiers())
    local reason
    if not db.finalCleared then
        local raid
        for _, r in ipairs(ns.D.RAIDS or {}) do if (r.tier or 0) >= self:NumTiers() then raid = r end end
        reason = "Defeat " .. ((raid and raid.name) or ("the " .. (last.name or "final") .. " raid")) .. " to begin a New Era."
    end
    local nextEra = db.era + 1
    local function at(e, legacy)
        return { xp = (e - 1) * ERA_PACE + math.min(LEGACY_BONUS_MAX, legacy * LEGACY_XP),
                 gold = (e - 1) * ERA_PACE + math.min(LEGACY_BONUS_MAX, legacy * LEGACY_GOLD),
                 speed = math.min(ERA_SPEED_MAX, (e - 1) * ERA_SPEED),
                 heroes = math.min(ERA_HERO_MAX, math.floor((e - 1) / ERA_HERO_EVERY)) }
    end
    local gain = self:LegacyGain()
    return { era = db.era, legacy = db.legacy, canAdvance = reason == nil, reason = reason,
             bonus = at(db.era, db.legacy), gain = gain, nextBonus = at(nextEra, db.legacy + gain) }
end

function Game:AdvanceEra()
    local info = self:EraInfo()
    if not info.canAdvance then return false, info.reason end
    local db = self.db
    local now = self:Now()
    db.legacy = db.legacy + info.gain
    db.era = db.era + 1
    self:MaxStat("ERA", db.era)
    db.buffs = {}
    self:ResetRun(db, now, true)
    self:SeedRecruits(now)
    db.seeded = true
    self:Log(string.format("Era %d begins. Legacy %d.", db.era, db.legacy), now)
    self:CheckAchievements(nil, now)
    self:Changed("all")
    return true
end
