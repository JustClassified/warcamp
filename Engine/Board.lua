local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Board.lua — mission offers (gather / quest per zone, dungeons, raids), preview, chance,
-- suggested party
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
-- durations in seconds: { tier-1 {lo,hi}, last-tier {lo,hi} }, interpolated by tier
local DURATION = {
    GATHER  = { { 60, 300 },    { 1500, 5400 } },
    QUEST   = { { 150, 600 },   { 2400, 7200 } },
    DUNGEON = { { 3600, 4800 }, { 10800, 14400 } },
    RAID    = { { 28800, 36000 }, { 36000, 43200 } },
}
local REFRESH = { GATHER = 3 * 3600, QUEST = 4 * 3600 }     -- epoch-aligned board windows
local QUESTS_PER_ZONE = 4
local KIND_XP   = { GATHER = 0.75, QUEST = 1.00, DUNGEON = 1.35, RAID = 1.6 }
local KIND_GOLD = { GATHER = 0.55, QUEST = 1.00, DUNGEON = 1.10, RAID = 1.4 }   -- x GoldRate x hours x party
local GATHER_PER_HOUR = 30            -- mats per hour of gathering (before skill/yield bonuses)
local QUEST_CLOTH_PER_HOUR = 10
local DUNGEON_CLOTH = 6
local RAID_CLOTH = 20
local SKILL_YIELD = 0.004             -- +0.4% yield per skill point
local CLASS_GATHER_YIELD = 0.10       -- the class's own profession
local GEAR = {                        -- reward gear: chance, ilvl position in tier, base quality, pieces
    GATHER  = { chance = 0.05, pos = nil, quality = 2, n = 1 },
    QUEST   = { chance = 0.30, pos = nil, quality = 2, n = 1 },
    DUNGEON = { chance = 1.00, pos = 0.78, quality = 3, n = 2 },
    RAID    = { chance = 1.00, pos = 1.08, quality = 4, n = 4 },
}
local ZONE_ILVL_SPAN = 0.45           -- zone gear runs from the tier floor up to this fraction of the tier range
local DUNGEON_ILVL_POS = 0.50         -- dungeon difficulty ilvl inside the tier range
local RAID_ILVL_POS = 0.82
local RARE_CHANCE = { DUNGEON = 0.35, RAID = 1.0 }
-- success chance
local BASE_CHANCE = { GATHER = 0.88, QUEST = 0.74, DUNGEON = 0.66, RAID = 0.58 }
local MAX_CHANCE  = { GATHER = 0.99, QUEST = 0.97, DUNGEON = 0.95, RAID = 0.93 }
local MIN_CHANCE = 0.05
local LEVEL_W_UNDER, LEVEL_DIFF_MIN = 0.08, -12   -- per level the party is below the offer ...
local LEVEL_W_OVER, LEVEL_DIFF_MAX = 0.03, 5       -- ... and above it
local ILVL_W, ILVL_DIFF_MIN, ILVL_DIFF_MAX = 0.025, -12, 6
local THREAT_COUNTERED = 0.06
local THREAT_OPEN = -0.03
local ROLE_MISSING = -0.12
local EXTRA_HERO = 0.04
local SPEED_CAP = 0.60                -- durations never drop below 40%
local SUGGEST_TARGET = 0.90
local DUNGEON_ROLES = { TANK = 1, HEALER = 1, DAMAGER = 3 }
local RAID_ROLES = { TANK = 2, HEALER = 2, DAMAGER = 4 }
local QUEST_THREAT_CHANCE = 0.6
local TIER_GATE_SLACK = 1             -- tier gate level = tier's top level - this

local function tierPos(tier)
    local n = Game:NumTiers()
    if n <= 1 then return 0 end
    return U.Clamp((tier - 1) / (n - 1), 0, 1)
end

local function durRange(kind, tier)
    local d = DURATION[kind]
    local p = tierPos(tier)
    return d[1][1] + (d[2][1] - d[1][1]) * p, d[1][2] + (d[2][2] - d[1][2]) * p
end

local function roundTo(x, step) return math.max(step, math.floor(x / step + 0.5) * step) end

local function threatKeys()
    return Game:SortedKeys(ns.D.THREATS)
end

----------------------------------------------------------------------------------------------------
-- zones
----------------------------------------------------------------------------------------------------
function Game:ZoneByKey(key)
    for _, z in ipairs(ns.D.ZONES or {}) do if z.key == key then return z end end
end

function Game:InstanceByKey(key)
    for _, d in ipairs(ns.D.DUNGEONS or {}) do if d.key == key then return d, "DUNGEON" end end
    for _, r in ipairs(ns.D.RAIDS or {}) do if r.key == key then return r, "RAID" end end
end

-- the party that clears a tier's dungeon must average this level for the next tier to open
function Game:TierGateLevel(tier)
    local r = self:Tier(tier).level or { 1, 10 }
    return math.max(r[1], r[2] - TIER_GATE_SLACK)
end

-- the Town Hall level a tier's content needs (the data's Town Hall text: "level n: <tier n> missions open")
function Game:TierHallLevel(tier)
    local th = ns.D.BUILDINGS and ns.D.BUILDINGS.TOWN_HALL
    if th and th.stat == "MAX_BUILDING_LEVEL" and th.levels and #th.levels >= self:NumTiers() then return tier end
    return 0
end

function Game:TierUnlockReason(tier)
    if tier <= (self.db.tier or 1) then
        local need = self:TierHallLevel(tier)
        if self:BuildingLevel("TOWN_HALL") < need then
            return string.format("Requires Town Hall level %d.", need)
        end
        return nil
    end
    local prev = self:Tier(tier - 1)
    return string.format("Reach level %d and clear a %s dungeon to unlock %s.", self:TierGateLevel(tier - 1),
        prev.name or ("tier " .. (tier - 1)), self:Tier(tier).name or ("tier " .. tier))
end

function Game:GetZones()
    local out = {}
    for _, z in ipairs(ns.D.ZONES or {}) do
        local reason = self:TierUnlockReason(z.tier or 1)
        out[#out + 1] = { zone = z, unlocked = reason == nil, reason = reason }
    end
    return out
end

local function zoneIlvl(zone)
    local lr = Game:Tier(zone.tier or 1).level or { 1, 10 }
    local frac = U.Clamp(((zone.level or lr[1]) - lr[1]) / math.max(1, lr[2] - lr[1]), 0, 1)
    return Game:TierIlvl(zone.tier or 1, frac * ZONE_ILVL_SPAN)
end

local function partySize(o) return (o.minHeroes + o.maxHeroes) / 2 end

local function baseRewards(self, o)
    local hours = o.duration / 3600
    o.rewards = o.rewards or {}
    o.rewards.xp = U.Round(self:XPRate(o.level, o.level) * o.duration * KIND_XP[o.kind])
    o.rewards.gold = U.Round(self:GoldRate(o.tier) * hours * KIND_GOLD[o.kind] * partySize(o))
    o.rewards.items = o.rewards.items or {}
    local g = GEAR[o.kind]
    o.rewards.gear = { chance = g.chance, quality = g.quality, n = g.n,
                       ilvl = U.Round(g.pos and self:TierIlvl(o.tier, g.pos) or (o.ilvl + 2)) }
end

function Game:MakeGatherOffer(zone, prof, window)
    local tier = zone.tier or 1
    local lo, hi = durRange("GATHER", tier)
    local mats = self:Tier(tier).mats or {}
    local mat = mats[Game.PROF_MAT[prof] or ""]
    local o = {
        key = string.format("G:%s:%s:%d", zone.key, prof, window), kind = "GATHER", profession = prof,
        name = (prof:sub(1, 1) .. prof:sub(2):lower()) .. " in " .. (zone.name or zone.key),
        desc = "Work the nodes and bring back what you find.",
        tier = tier, level = zone.level or 1, ilvl = U.Round(zoneIlvl(zone)),
        minHeroes = 1, maxHeroes = 1, duration = roundTo(self:RandRange(lo, hi), 30), threats = {},
        zone = zone.key, display = zone.mobs and zone.mobs[1] and zone.mobs[1].display,
    }
    baseRewards(self, o)
    if mat then o.rewards.items[mat] = math.max(1, U.Round(GATHER_PER_HOUR * o.duration / 3600)) end
    return o
end

function Game:MakeQuestOffer(zone, i, window)
    local tier = zone.tier or 1
    local lr = self:Tier(tier).level or { 1, 10 }
    local lo, hi = durRange("QUEST", tier)
    local mob = zone.mobs and #zone.mobs > 0 and self:Pick(zone.mobs) or {}
    local name = self:Pick(zone.quests or {}) or ("Trouble in " .. (zone.name or zone.key))
    local level = U.Clamp((zone.level or lr[1]) + self:RandInt(-1, 1), lr[1], lr[2])
    local maxH = self:Chance(0.35) and 3 or (self:Chance(0.5) and 2 or 1)
    local threats = {}
    if self:Chance(QUEST_THREAT_CHANCE) then threats[1] = self:Pick(threatKeys()) end
    local o = {
        key = string.format("Q:%s:%d:%d", zone.key, i, window), kind = "QUEST",
        name = name, desc = mob.name and ("Enemies: " .. mob.name) or "",
        tier = tier, level = level, ilvl = U.Round(zoneIlvl(zone)),
        minHeroes = 1, maxHeroes = maxH, duration = roundTo(self:RandRange(lo, hi), 30), threats = threats,
        zone = zone.key, display = mob.display,
    }
    baseRewards(self, o)
    o.rewards.gold = U.Round(self:GoldRate(tier) * o.duration / 3600 * KIND_GOLD.QUEST)  -- solo-paced
    local cloth = (self:Tier(tier).mats or {}).CLOTH
    if cloth then o.rewards.items[cloth] = math.max(1, U.Round(QUEST_CLOTH_PER_HOUR * o.duration / 3600)) end
    return o
end

local function windowOf(kind, now) return math.floor(now / REFRESH[kind]) end

local function genBoard(self, kind, zone, now)
    local w = windowOf(kind, now)
    local board = { offers = {}, window = w, refreshAt = (w + 1) * REFRESH[kind] }
    if kind == "GATHER" then
        for _, prof in ipairs(zone.gather or {}) do
            if Game.PROF_MAT[prof] then board.offers[#board.offers + 1] = self:MakeGatherOffer(zone, prof, w) end
        end
    else
        for i = 1, QUESTS_PER_ZONE do board.offers[#board.offers + 1] = self:MakeQuestOffer(zone, i, w) end
    end
    return board
end

-- a started quest leaves the board and a new one takes its place at once, so a zone never runs dry
function Game:ReplaceQuest(o)
    local zone = o and o.zone and self:ZoneByKey(o.zone)
    local b = zone and self.db.boards["QUEST:" .. zone.key]
    if not b then return end
    for i, x in ipairs(b.offers) do
        if x.key == o.key then table.remove(b.offers, i) break end
    end
    b.next = math.max(b.next or 0, QUESTS_PER_ZONE) + 1
    b.offers[#b.offers + 1] = self:MakeQuestOffer(zone, b.next, b.window or 0)
end

function Game:ZoneBoard(kind, zoneKey, now)
    now = now or self:Now()
    local zone = self:ZoneByKey(zoneKey)
    if not zone then return nil end
    local id = kind .. ":" .. zoneKey
    local b = self.db.boards[id]
    if not b or now >= (b.refreshAt or 0) then
        b = genBoard(self, kind, zone, now)
        self.db.boards[id] = b
    end
    return b
end

----------------------------------------------------------------------------------------------------
-- dungeons and raids (always listed, deterministic)
----------------------------------------------------------------------------------------------------
local function uniqueThreats(bosses)
    local set, list = {}, {}
    for _, b in ipairs(bosses or {}) do
        for _, t in ipairs(b.threats or {}) do
            if not set[t] then set[t] = true list[#list + 1] = t end
        end
    end
    table.sort(list)
    return list
end

function Game:MakeInstanceOffer(ins, kind, now)
    local tier = ins.tier or 1
    local lr = self:Tier(tier).level or { 1, 10 }
    local lo, hi = durRange(kind, tier)
    local bosses = ins.bosses or {}
    local final = bosses[#bosses] or {}
    local o = {
        key = (kind == "RAID" and "R:" or "D:") .. ins.key, kind = kind, instance = ins.key,
        name = ins.name or ins.key, desc = string.format("%d bosses", #bosses),
        tier = tier, level = (kind == "RAID") and lr[2] or (ins.level or lr[2]),
        ilvl = U.Round(self:TierIlvl(tier, kind == "RAID" and RAID_ILVL_POS or DUNGEON_ILVL_POS)),
        minHeroes = kind == "RAID" and 6 or 3, maxHeroes = kind == "RAID" and 10 or 5,
        roles = U.Copy(kind == "RAID" and RAID_ROLES or DUNGEON_ROLES),
        duration = roundTo(lo + (hi - lo) * self:Hash01(ins.key), 60),
        threats = uniqueThreats(bosses), display = final.display, bosses = #bosses,
    }
    baseRewards(self, o)
    local mats = self:Tier(tier).mats or {}
    if mats.CLOTH then o.rewards.items[mats.CLOTH] = kind == "RAID" and RAID_CLOTH or DUNGEON_CLOTH end
    if self:Tier(tier).rare then o.rewards.rare = { item = self:Tier(tier).rare, chance = RARE_CHANCE[kind] } end
    o.rewards.mount = ins.mount and { mountID = ins.mount.mountID, chance = ins.mount.chance or 0.01 }
    o.rewards.pet = ins.pet and { speciesID = ins.pet.speciesID, chance = ins.pet.chance or 0.03 }

    local reason = self:TierUnlockReason(tier)
    if not reason and kind == "RAID" then
        local lock = self.db.raidLocks[ins.key]
        if lock == self:WeekIndex(now) then
            o.weeklyDone = true
            reason = "Defeated this week. Resets " .. (date and date("%a %H:%M", self:WeekResetAt(now)) or "next week") .. "."
        end
    end
    if not reason then
        for _, t in pairs(self.db.tasks) do
            if t.offerKey == o.key then reason = "Your party is already inside." break end
        end
    end
    o.locked, o.lockReason = reason ~= nil, reason
    o.weeklyDone = o.weeklyDone or false
    return o
end

function Game:GetBoard(kind, zoneKey, now)
    now = now or self:Now()
    local out = {}
    if kind == "DUNGEON" or kind == "RAID" then
        for _, ins in ipairs((kind == "RAID" and ns.D.RAIDS or ns.D.DUNGEONS) or {}) do
            out[#out + 1] = self:MakeInstanceOffer(ins, kind, now)
        end
        table.sort(out, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            if a.level ~= b.level then return a.level < b.level end
            return a.key < b.key
        end)
        return out
    end
    local zone = self:ZoneByKey(zoneKey)
    if not zone then return out end
    local reason = self:TierUnlockReason(zone.tier or 1)
    local b = self:ZoneBoard(kind, zoneKey, now)
    for _, o in ipairs(b.offers) do
        if not o.taken then
            o.locked, o.lockReason = reason ~= nil, reason
            out[#out + 1] = o
        end
    end
    return out
end

-- offer by key from any board (dungeon/raid offers are rebuilt)
function Game:FindOffer(key, now)
    if type(key) ~= "string" then return nil end
    local p, rest = key:match("^(%a):(.+)$")
    if p == "D" or p == "R" then
        local ins, kind = self:InstanceByKey(rest)
        if ins then return self:MakeInstanceOffer(ins, kind, now) end
        return nil
    end
    for _, b in pairs(self.db.boards) do
        for _, o in ipairs(b.offers) do
            if o.key == key then
                local reason = self:TierUnlockReason(o.tier or 1)
                o.locked, o.lockReason = reason ~= nil, reason
                return o
            end
        end
    end
end

----------------------------------------------------------------------------------------------------
-- preview / chance
----------------------------------------------------------------------------------------------------
local function ctxOf(o)
    return { kind = o.kind, profession = o.profession, instance = o.instance }
end

-- internal: preview an offer table for hero tables at time t. opts.ignoreTask lets a repeat restart
-- use heroes still bound to the finishing task.
function Game:PreviewOffer(o, heroes, t, opts)
    opts = opts or {}
    local p = { ok = false, chance = 0, duration = o.duration, countered = {}, missingRoles = {}, xpEach = 0,
                xpBy = {}, rewards = U.Copy(o.rewards), notes = {} }
    if o.locked and not opts.ignoreLock then p.reason = o.lockReason or "Locked." return p end
    local n = #heroes
    if n < o.minHeroes then
        p.reason = string.format("Needs %d recruit%s.", o.minHeroes, o.minHeroes == 1 and "" or "s")
    elseif n > o.maxHeroes then
        p.reason = string.format("At most %d recruit%s.", o.maxHeroes, o.maxHeroes == 1 and "" or "s")
    end
    local seen = {}
    for _, h in ipairs(heroes) do
        if seen[h.id] then p.reason = "A recruit is listed twice." end
        seen[h.id] = true
        if h.taskId and h.taskId ~= opts.ignoreTask then p.reason = h.name .. " is busy." end
    end
    if n == 0 then return p end

    local ctx = ctxOf(o)
    -- level and ilvl
    local lv, il, qc = 0, 0, 0
    for _, h in ipairs(heroes) do
        lv = lv + h.level
        il = il + self:HeroIlvl(h)
        qc = qc + self:HeroQualityChance(h)
    end
    lv, il, qc = lv / n, il / n, qc / n
    local chance = BASE_CHANCE[o.kind] or 0.7
    local ld = U.Clamp(lv - o.level, LEVEL_DIFF_MIN, LEVEL_DIFF_MAX)
    chance = chance + (ld < 0 and LEVEL_W_UNDER or LEVEL_W_OVER) * ld
    chance = chance + ILVL_W * U.Clamp((il - o.ilvl) / self:IlvlUnit(o.tier), ILVL_DIFF_MIN, ILVL_DIFF_MAX)
    chance = chance + qc
    p.power, p.offerPower = 0, self:OfferPower(o)
    for _, h in ipairs(heroes) do p.power = p.power + self:HeroPower(h) end
    p.power = U.Round(p.power / n)

    -- threats
    local C = ns.D.CLASSES or {}
    local counters = {}
    for _, h in ipairs(heroes) do
        for _, th in ipairs((C[h.class] or {}).counters or {}) do counters[th] = true end
    end
    for _, th in ipairs(o.threats or {}) do
        if counters[th] then
            p.countered[th] = true
            chance = chance + THREAT_COUNTERED
        else
            chance = chance + THREAT_OPEN
        end
    end
    -- roles
    if o.roles then
        local have = {}
        for _, h in ipairs(heroes) do have[h.role] = (have[h.role] or 0) + 1 end
        for _, role in ipairs(self:SortedKeys(o.roles)) do
            local miss = o.roles[role] - (have[role] or 0)
            if miss > 0 then
                p.missingRoles[role] = miss
                chance = chance + ROLE_MISSING * miss
                p.notes[#p.notes + 1] = string.format("Missing %d %s", miss, (ns.D.ROLES and ns.D.ROLES[role] and ns.D.ROLES[role].name) or role)
            end
        end
    end
    if n > o.minHeroes then chance = chance + EXTRA_HERO * (n - o.minHeroes) end

    -- bonuses (traits, buffs, buildings, era)
    local bChance = self:Bonus("CHANCE", heroes, ctx, t)
    local bSpeed = math.min(SPEED_CAP, self:Bonus("SPEED", heroes, ctx, t))
    local bGold = self:Bonus("GOLD", heroes, ctx, t)
    local bLoot = self:Bonus("LOOT", heroes, ctx, t)
    local bYield = self:Bonus("YIELD", heroes, ctx, t)
    local bCollect = self:Bonus("COLLECT", heroes, ctx, t)
    chance = chance + bChance
    p.chance = U.Clamp(chance, MIN_CHANCE, MAX_CHANCE[o.kind] or 0.95)
    p.duration = math.max(30, U.Round(o.duration * (1 - bSpeed)))

    -- gathering skill
    if o.kind == "GATHER" and o.profession then
        local h = heroes[1]
        local s = (h.skills and h.skills[o.profession]) or 1
        bYield = bYield + s * SKILL_YIELD
        if (C[h.class] or {}).gather == o.profession then
            bYield = bYield + CLASS_GATHER_YIELD
            p.notes[#p.notes + 1] = string.format("%s gathers %s well +%d%%", h.name, o.profession:lower(), U.Round(CLASS_GATHER_YIELD * 100))
        end
    end

    local r = p.rewards
    r.gold = U.Round((r.gold or 0) * (1 + bGold))
    for k, v in pairs(r.items or {}) do r.items[k] = math.max(1, U.Round(v * (1 + bYield))) end
    if r.gear then r.gear.chance = U.Clamp((r.gear.chance or 0) * (1 + bLoot), 0, 1) end
    if r.rare then r.rare.chance = U.Clamp(r.rare.chance * (1 + bLoot), 0, 1) end
    if r.mount then r.mount.chance = U.Clamp(r.mount.chance * (1 + bLoot * 0.5 + bCollect), 0, 0.5) end
    if r.pet then r.pet.chance = U.Clamp(r.pet.chance * (1 + bLoot * 0.5 + bCollect), 0, 0.5) end

    -- xp per hero: earned over the BASE duration (speed bonuses do not cut xp)
    local total = 0
    for _, h in ipairs(heroes) do
        local bx = self:Bonus("XP", { h }, ctx, t)
        local xp = self:XPRate(h.level, o.level) * o.duration * (KIND_XP[o.kind] or 1) * self:HeroXPMult(h) * (1 + bx)
        if h.level >= self:MaxLevel() then xp = 0 end
        p.xpBy[h.id] = U.Round(xp)
        total = total + p.xpBy[h.id]
    end
    p.xpEach = U.Round(total / n)

    -- notes
    local function pct(label, v) if v and math.abs(v) >= 0.005 then p.notes[#p.notes + 1] = string.format("%s %+d%%", label, U.Round(v * 100)) end end
    pct("Success", bChance)
    pct("Speed", bSpeed)
    pct("Gold", bGold)
    pct("Yield", bYield)
    pct("Loot", bLoot)
    pct("Mount and pet chance", bCollect)
    self:TraitNotes(heroes, ctx, p.notes)

    if not p.reason then p.ok = true end
    return p
end

local function heroList(self, ids)
    local list = {}
    for _, id in ipairs(ids or {}) do
        local h = self.db.heroes[id]
        if not h then return nil end
        list[#list + 1] = h
    end
    return list
end

function Game:Preview(offerKey, heroIds, now)
    now = now or self:Now()
    local o = type(offerKey) == "table" and offerKey or self:FindOffer(offerKey, now)
    if not o then return { ok = false, reason = "That offer is gone.", chance = 0, countered = {}, missingRoles = {}, notes = {}, xpEach = 0 } end
    local heroes = heroList(self, heroIds)
    if not heroes then return { ok = false, reason = "Unknown recruit.", chance = 0, countered = {}, missingRoles = {}, notes = {}, xpEach = 0 } end
    return self:PreviewOffer(o, heroes, now)
end

----------------------------------------------------------------------------------------------------
-- suggested party
----------------------------------------------------------------------------------------------------
function Game:Suggest(offerKey, now, pool)
    now = now or self:Now()
    local o = type(offerKey) == "table" and offerKey or self:FindOffer(offerKey, now)
    if not o then return {} end
    local idle = {}
    for _, h in pairs(pool or self.db.heroes) do
        if not h.taskId then idle[#idle + 1] = h end
    end
    local C = ns.D.CLASSES or {}
    local function score(h)
        local s = self:HeroPower(h)
        if o.kind == "GATHER" and o.profession then
            s = (h.skills and h.skills[o.profession] or 1) + (((C[h.class] or {}).gather == o.profession) and 25 or 0)
                - (h.level >= self:MaxLevel() and 0 or 0)
        end
        for _, th in ipairs(o.threats or {}) do
            for _, c in ipairs((C[h.class] or {}).counters or {}) do if c == th then s = s + 15 end end
        end
        return s
    end
    table.sort(idle, function(a, b)
        local sa, sb = score(a), score(b)
        if sa ~= sb then return sa > sb end
        return a.id < b.id
    end)
    local party, used = {}, {}
    local function add(h) party[#party + 1] = h used[h.id] = true end
    if o.roles then
        for _, role in ipairs(self:SortedKeys(o.roles)) do
            local need = o.roles[role]
            for _, h in ipairs(idle) do
                if need <= 0 or #party >= o.maxHeroes then break end
                if not used[h.id] and h.role == role then add(h) need = need - 1 end
            end
        end
    end
    for _, h in ipairs(idle) do
        if #party >= o.minHeroes then break end
        if not used[h.id] then add(h) end
    end
    if #party >= o.minHeroes then
        for _, h in ipairs(idle) do
            if #party >= o.maxHeroes then break end
            if not used[h.id] then
                local p = self:PreviewOffer(o, party, now)
                if p.chance >= SUGGEST_TARGET then break end
                add(h)
            end
        end
    end
    local ids = {}
    for i, h in ipairs(party) do ids[i] = h.id end
    return ids
end
