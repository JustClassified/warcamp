local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\State.lua — WarcampDB lifecycle (create, migrate, reset), ids, seeded RNG, log, stats,
-- reports, and the shared economy scale. Runs headless: only time(), date() and ns.D are used.
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
Game.DB_VERSION = 1
local START_GOLD = 12000              -- copper (1g 20s): enough for the 4th recruit in session 1
local START_RECRUITS = 3
local START_RECRUIT_QUALITY = 2
local LOG_MAX = 250
local RNG_MOD = 2147483647            -- Park-Miller minimal standard (exact in doubles: 16807 * 2^31 < 2^53)
local RNG_MUL = 16807

-- the shared money scale: copper one hero earns per hour of missions at a tier (everything that
-- costs or pays gold is a multiple of this, so one knob moves the whole economy)
local GOLD_RATE_BASE = 5500           -- tier 1: 55 silver / hero-hour
local GOLD_RATE_GROWTH = 1.50         -- per tier (tier 12 ~ 48g / hero-hour; data building costs ~x2 per level)

-- weekly reset: Wednesday 2024-01-03 07:00 UTC, then every 7 days
Game.WEEK_EPOCH = 1704265200
Game.WEEK = 604800

Game.PROFESSIONS = { "MINING", "HERBALISM", "SKINNING", "FISHING" }
Game.PROF_MAT = { MINING = "ORE", HERBALISM = "HERB", SKINNING = "LEATHER", FISHING = "FISH" }

----------------------------------------------------------------------------------------------------
-- clock
----------------------------------------------------------------------------------------------------
function Game:Now()
    return time()
end

function Game:WeekIndex(t)
    return math.floor(((t or self:Now()) - Game.WEEK_EPOCH) / Game.WEEK)
end

function Game:WeekResetAt(t)
    return Game.WEEK_EPOCH + (self:WeekIndex(t) + 1) * Game.WEEK
end

----------------------------------------------------------------------------------------------------
-- small helpers shared by every engine file
----------------------------------------------------------------------------------------------------
function Game:SortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function Game:NumTiers()
    local T = ns.D.TIERS
    return (T and #T > 0) and #T or 1
end

function Game:Tier(i)
    local T = ns.D.TIERS or {}
    return T[i] or T[#T] or { key = "T" .. tostring(i), name = "Tier " .. tostring(i), level = { 1, 10 }, ilvl = { 5, 40 }, mats = {} }
end

-- position along a tier's ilvl range: frac 0 = bottom, 1 = top (may exceed 1)
function Game:TierIlvl(tier, frac)
    local r = self:Tier(tier).ilvl or { 5, 40 }
    return r[1] + (r[2] - r[1]) * frac
end

-- one ilvl "step" of a tier, used to turn an ilvl gap into a success-chance gap
function Game:IlvlUnit(tier)
    local r = self:Tier(tier).ilvl or { 5, 40 }
    return math.max(1, (r[2] - r[1]) / 10)
end

function Game:GoldRate(tier)
    return GOLD_RATE_BASE * GOLD_RATE_GROWTH ^ ((tier or 1) - 1)
end

----------------------------------------------------------------------------------------------------
-- deterministic RNG (state in the db, so a test run is reproducible)
----------------------------------------------------------------------------------------------------
local function seedFrom(n)
    n = math.floor(math.abs(n or 1)) % (RNG_MOD - 1)
    if n < 1 then n = 1 end
    return n
end

-- 0 <= x < 1
function Game:Rand()
    local db = self.db
    local s = (db and db.rng) or self._rng or 1
    s = (s * RNG_MUL) % RNG_MOD
    if db then db.rng = s else self._rng = s end
    return (s - 1) / (RNG_MOD - 1)
end

-- integer a..b inclusive (or 1..a)
function Game:RandInt(a, b)
    if not b then a, b = 1, a end
    if b <= a then return a end
    return a + math.floor(self:Rand() * (b - a + 1))
end

function Game:RandRange(a, b)
    return a + (b - a) * self:Rand()
end

function Game:Chance(p)
    return self:Rand() < (p or 0)
end

function Game:Pick(list)
    if not list or #list == 0 then return nil end
    return list[self:RandInt(1, #list)]
end

-- weights = { [value] = weight, ... } ; keys sorted so the draw is deterministic
function Game:WeightedPick(weights)
    local keys = self:SortedKeys(weights)
    local total = 0
    for _, k in ipairs(keys) do total = total + math.max(0, weights[k]) end
    if total <= 0 then return keys[1] end
    local r = self:Rand() * total
    for _, k in ipairs(keys) do
        r = r - math.max(0, weights[k])
        if r < 0 then return k end
    end
    return keys[#keys]
end

-- stable string hash 0..1 (per-item phases for the market)
function Game:Hash01(s)
    s = tostring(s)
    local h = 7
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end
    return h / 1000003
end

----------------------------------------------------------------------------------------------------
-- ids, change events, log, stats
----------------------------------------------------------------------------------------------------
function Game:NewId()
    local db = self.db
    local id = db.nextId or 1
    db.nextId = id + 1
    return id
end

-- every mutation goes through here; during a catch-up the events are collapsed and fired once
function Game:Changed(what)
    if self._mute then
        self._mute[what or "all"] = true
        return
    end
    ns.Fire("CHANGED", what or "all")
end

-- run fn(...) inside a batch; the batch is closed even if fn errors (the error is re-raised)
function Game:Batched(fn, ...)
    self:BeginBatch()
    local ok, err = pcall(fn, self, ...)
    self:EndBatch()
    if not ok then error(err, 0) end
    return err
end

function Game:BeginBatch()
    self._muteDepth = (self._muteDepth or 0) + 1
    self._mute = self._mute or {}
end

function Game:EndBatch()
    self._muteDepth = math.max(0, (self._muteDepth or 1) - 1)   -- never below 0
    if self._muteDepth > 0 then return end
    local pending = self._mute
    self._mute = nil
    if not pending then return end
    local n = U.Count(pending)
    if n == 0 then return end
    if n > 3 or pending.all then
        ns.Fire("CHANGED", "all")
    else
        for _, what in ipairs(self:SortedKeys(pending)) do ns.Fire("CHANGED", what) end
    end
end

function Game:Log(text, t)
    local log = self.db.log
    table.insert(log, 1, { t = t or self:Now(), text = text })
    for i = #log, LOG_MAX + 1, -1 do log[i] = nil end
    self:Changed("log")
end

function Game:AddStat(key, n)
    local s = self.db.stats
    s[key] = (s[key] or 0) + (n or 1)
end

function Game:MaxStat(key, v)
    local s = self.db.stats
    if (s[key] or 0) < v then s[key] = v end
end

----------------------------------------------------------------------------------------------------
-- reports: one collect -> success=bool; merged reports -> success/fail = counts
----------------------------------------------------------------------------------------------------
function Game:NewReport()
    return { success = 0, fail = 0, tasks = 0, gold = 0, xp = {}, levelUps = {}, items = {}, gear = {},
             mounts = {}, pets = {}, achievements = {}, buildings = {}, lines = {} }
end

function Game:MergeReport(dst, src)
    if not src then return dst end
    if type(src.success) == "boolean" then
        if src.success then dst.success = dst.success + 1 else dst.fail = dst.fail + 1 end
    else
        dst.success = dst.success + (src.success or 0)
        dst.fail = dst.fail + (src.fail or 0)
    end
    dst.tasks = dst.tasks + (src.tasks or 1)
    dst.gold = dst.gold + (src.gold or 0)
    for id, n in pairs(src.xp or {}) do dst.xp[id] = (dst.xp[id] or 0) + n end
    for id, lv in pairs(src.levelUps or {}) do
        if (dst.levelUps[id] or 0) < lv then dst.levelUps[id] = lv end
    end
    for k, n in pairs(src.items or {}) do dst.items[k] = (dst.items[k] or 0) + n end
    for _, g in ipairs(src.gear or {}) do dst.gear[#dst.gear + 1] = g end
    for _, m in ipairs(src.mounts or {}) do dst.mounts[#dst.mounts + 1] = m end
    for _, p in ipairs(src.pets or {}) do dst.pets[#dst.pets + 1] = p end
    for _, a in ipairs(src.achievements or {}) do dst.achievements[#dst.achievements + 1] = a end
    for _, b in ipairs(src.buildings or {}) do dst.buildings[#dst.buildings + 1] = b end
    for _, l in ipairs(src.lines or {}) do
        if #dst.lines < 60 then dst.lines[#dst.lines + 1] = l end
    end
    return dst
end

function Game:ReportEmpty(r)
    return not r or ((r.tasks or 0) == 0 and (r.gold or 0) == 0 and #(r.buildings or {}) == 0
        and next(r.items or {}) == nil and #(r.lines or {}) == 0)
end

----------------------------------------------------------------------------------------------------
-- db lifecycle
----------------------------------------------------------------------------------------------------
-- migrations[v] upgrades a db from version v-1 to v. Add entries here when the layout changes.
Game.MIGRATIONS = {
    -- [2] = function(db) db.newThing = db.newThing or {} end,
}

local function migrate(db)
    local v = tonumber(db.version) or Game.DB_VERSION
    while v < Game.DB_VERSION do
        v = v + 1
        local fn = Game.MIGRATIONS[v]
        if fn then
            local ok, err = pcall(fn, db)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
        db.version = v
    end
    db.version = math.max(v, db.version or v)
end

-- the per-era run state: wiped by a New Era (collection, achievements, stats, log, era, legacy stay)
function Game:ResetRun(db, now, wipe)
    local function fresh(key, value)
        if wipe or db[key] == nil then db[key] = value end
    end
    fresh("gold", START_GOLD)
    fresh("tier", 1)
    fresh("heroes", {})
    fresh("bag", {})
    fresh("inventory", {})
    fresh("tasks", {})
    fresh("buildings", {})
    fresh("storage", {})
    fresh("inn", {})
    fresh("boards", {})
    fresh("raidLocks", {})
    fresh("clears", {})
    fresh("sales", {})
    fresh("eraStart", now)
    fresh("finalCleared", false)
    fresh("seeded", false)
    for _, key in ipairs(self:SortedKeys(ns.D.BUILDINGS)) do
        if not db.buildings[key] then
            db.buildings[key] = { level = (key == "TOWN_HALL") and 1 or 0 }
        end
    end
end

function Game:Init(now)
    now = now or self:Now()
    if type(WarcampDB) ~= "table" then WarcampDB = {} end
    local db = WarcampDB
    self.db = db
    local isNew = db.version == nil
    -- an addon update that changes the save layout keeps a copy of the old camp first
    if not isNew and (tonumber(db.version) or Game.DB_VERSION) < Game.DB_VERSION and self.MakeBackup then
        pcall(self.MakeBackup, self, "before update to save v" .. Game.DB_VERSION)
    end
    if not isNew then migrate(db) end
    db.version = db.version or Game.DB_VERSION
    db.created = db.created or now
    db.lastSeen = db.lastSeen or now
    db.rng = db.rng or seedFrom(now)
    db.nextId = db.nextId or 1
    db.era = db.era or 1
    db.legacy = db.legacy or 0
    db.collection = db.collection or {}
    db.collection.mounts = db.collection.mounts or {}
    db.collection.pets = db.collection.pets or {}
    db.achievements = db.achievements or {}
    db.stats = db.stats or {}
    db.log = db.log or {}
    db.buffs = db.buffs or {}
    -- repair first (bad numbers, keys an update removed), then fill whatever is missing
    if not isNew and self.Sanitize then
        local ok, fixed = pcall(self.Sanitize, self, db)
        if not ok and geterrorhandler then geterrorhandler()(fixed) end
    end
    self:ResetRun(db, now, false)

    if not db.seeded then
        self:SeedRecruits(now)
        db.seeded = true
        self:Log("Your warcamp is pitched. Three recruits await orders.", now)
    end

    -- what happens before the first Welcome() (the offline catch-up) is gathered here
    self.session = { start = now, prevSeen = db.lastSeen, welcomed = false }
    db.away = { since = db.lastSeen, report = self:NewReport() }
    self:Changed("all")
    return true
end

function Game:SeedRecruits(now)
    for _ = 1, START_RECRUITS do
        local h = self:GenerateHero(START_RECRUIT_QUALITY, self.db.tier or 1)
        self:AddHero(h, now)
    end
end
