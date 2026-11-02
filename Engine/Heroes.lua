local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Heroes.lua — recruit generation, xp/levels, gear, power, traits
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
-- Pacing: hours of missions one hero needs to climb through each tier's level range (at offer level =
-- hero level, quest-rate xp). Everything else about xp is derived from this, so it is the main knob
-- for "day 1 tier 2, week 1 tier 6, ~4-5 weeks to the end".
local TIER_HOURS = { 5, 14, 19, 24, 30, 57, 71, 85, 115, 135, 150, 170 }
local TIER_HOURS_GROWTH = 1.08        -- extrapolation past the table
local XP_A, XP_POW, XP_B = 60, 1.6, 140  -- display curve: xp to next level
local LEVEL_RAMP_FIRST = 2.0          -- inside tier 1 the first levels come in minutes (weights i^2) ...
local LEVEL_RAMP = 0.5                -- ... later tiers ramp gently
local XP_HARDER_PER_LEVEL = 0.06      -- more xp for content above your level ...
local XP_HARDER_MAX = 1.30
local XP_EASIER_PER_LEVEL = 0.12      -- ... less for content below it
local XP_EASIER_MIN = 0.20
local QUALITY_XP = { [1] = 0.9, [2] = 1.00, [3] = 1.08, [4] = 1.16, [5] = 1.25 }
local QUALITY_POWER = { [1] = 0.95, [2] = 1.00, [3] = 1.05, [4] = 1.10, [5] = 1.15 }
local QUALITY_CHANCE = { [1] = -0.02, [2] = 0, [3] = 0.025, [4] = 0.05, [5] = 0.07 }  -- per hero, averaged
local TRAITS_BY_QUALITY = { [1] = 1, [2] = 1, [3] = 2, [4] = 3, [5] = 3 }
local NEG_TRAIT_CHANCE = { [1] = 0.5, [2] = 0.30, [3] = 0.12, [4] = 0, [5] = 0 }
local POWER_PER_LEVEL = 10
local POWER_PER_ILVL = 1
local EMPTY_SLOT_ILVL = 1             -- an empty slot drags the average down
local BASE_HEROES = 4                 -- before Barracks
local HEROES_PER_BARRACKS = 1
local HARD_HERO_CAP = 24
local SKILL_START = 1
local SKILL_CLASS_BONUS = 5           -- starting skill in the class's own gathering profession
local SKILL_CAP = 150
local GEAR_BAG_CAP = 80               -- overflow auto-sells the worst piece
local GEAR_QUALITY_ILVL = 4           -- each quality step above uncommon adds this much ilvl
local GEAR_ILVL_JITTER = 2
local GEAR_SELL_HOURS = { [0] = 0.01, [1] = 0.02, [2] = 0.05, [3] = 0.12, [4] = 0.30, [5] = 0.6 }  -- x GoldRate(tier)
local TRAIT_PARTY_CAP = 0.35          -- party-wide trait bonuses of one kind are capped here

local DEFAULT_SLOTS = { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "WEAPON", "TRINKET" }
local TRAIT_KIND_ALIAS = { GATHER_YIELD = "YIELD", DURATION = "SPEED", EXPERIENCE = "XP" }

function Game:Slots()
    local s = ns.D.GEAR_SLOTS
    return (s and #s > 0) and s or DEFAULT_SLOTS
end

----------------------------------------------------------------------------------------------------
-- xp and levels
----------------------------------------------------------------------------------------------------
function Game:XPNeeded(level)
    return U.Round(XP_A * (level or 1) ^ XP_POW + XP_B)
end

-- the tier whose pacing applies to levelling FROM `level` (tiers may have gaps: {1,8},{9,15}: 8->9 is tier 2)
function Game:TierOfLevel(level)
    local T = ns.D.TIERS or {}
    for i = 1, #T do
        local r = T[i].level or { 1, 10 }
        if level < r[2] then return i end
    end
    return math.max(1, #T)
end

-- level a tier's pacing starts from: the previous tier's top (or this tier's floor)
local function tierBase(self, t)
    if t > 1 then return (self:Tier(t - 1).level or { 1, 10 })[2] end
    return (self:Tier(t).level or { 1, 10 })[1]
end

function Game:TierHours(t)
    if TIER_HOURS[t] then return TIER_HOURS[t] end
    return TIER_HOURS[#TIER_HOURS] * TIER_HOURS_GROWTH ^ (t - #TIER_HOURS)
end

-- seconds of quest-rate missions per level at this level
local rampCache = {}
function Game:SecsPerLevel(level)
    local t = self:TierOfLevel(level)
    local r = self:Tier(t).level or { 1, 10 }
    local base = tierBase(self, t)
    local span = math.max(1, r[2] - base)
    local ramp = (t == 1) and LEVEL_RAMP_FIRST or LEVEL_RAMP
    local ck = t .. ":" .. span
    local sum = rampCache[ck]
    if not sum then
        sum = 0
        for i = 1, span do sum = sum + i ^ ramp end
        rampCache[ck] = sum
    end
    local i = U.Clamp(level - base + 1, 1, span)
    return self:TierHours(t) * 3600 * (i ^ ramp) / sum
end

-- xp/second a hero of `level` earns on content of `offerLevel` (before kind/quality/bonus multipliers)
function Game:XPRate(level, offerLevel)
    local base = self:XPNeeded(level) / self:SecsPerLevel(level)
    local diff = (offerLevel or level) - level
    local f
    if diff >= 0 then
        f = math.min(XP_HARDER_MAX, 1 + XP_HARDER_PER_LEVEL * diff)
    else
        f = math.max(XP_EASIER_MIN, 1 + XP_EASIER_PER_LEVEL * diff)
    end
    return base * f
end

function Game:MaxLevel()
    local db = self.db
    local r = self:Tier(db and db.tier or 1).level or { 1, 10 }
    return r[2]
end

function Game:HeroXPNeeded(h)
    return self:XPNeeded(h.level)
end

function Game:HeroXPMult(h)
    return QUALITY_XP[h.quality or 2] or 1
end

-- adds xp, returns the new level if the hero levelled
function Game:GiveXP(h, xp)
    local cap = self:MaxLevel()
    local before = h.level
    h.xp = (h.xp or 0) + math.floor(xp + 0.5)
    while h.level < cap and h.xp >= self:XPNeeded(h.level) do
        h.xp = h.xp - self:XPNeeded(h.level)
        h.level = h.level + 1
    end
    if h.level >= cap then
        h.xp = math.min(h.xp, self:XPNeeded(h.level) - 1)
    end
    if h.level > before then
        self:MaxStat("MAX_LEVEL", h.level)
        self:AddStat("LEVELUPS", h.level - before)
        return h.level
    end
end

----------------------------------------------------------------------------------------------------
-- roster
----------------------------------------------------------------------------------------------------
function Game:MaxHeroes()
    local lvl = self:BuildingLevel("BARRACKS")
    local v = lvl > 0 and self:BuildingValue("BARRACKS", lvl)
    local n = (v and math.max(BASE_HEROES, v) or (BASE_HEROES + HEROES_PER_BARRACKS * lvl)) + self:EraHeroBonus()
    return math.min(HARD_HERO_CAP, n)
end

local function heroSort(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
    return a.id < b.id
end

function Game:GetHeroes()
    local list = {}
    for _, h in pairs(self.db.heroes) do list[#list + 1] = h end
    table.sort(list, heroSort)
    return list
end

function Game:GetHero(id)
    return self.db.heroes[id]
end

function Game:HeroCount()
    return U.Count(self.db.heroes)
end

function Game:HeroIlvl(h)
    local sum, n = 0, 0
    for _, slot in ipairs(self:Slots()) do
        local g = h.gear and h.gear[slot]
        sum = sum + (g and g.ilvl or EMPTY_SLOT_ILVL)
        n = n + 1
    end
    return n > 0 and math.floor(sum / n * 10 + 0.5) / 10 or 0
end

function Game:HeroPower(h)
    local q = QUALITY_POWER[h.quality or 2] or 1
    return U.Round((h.level * POWER_PER_LEVEL + self:HeroIlvl(h) * POWER_PER_ILVL) * q)
end

-- the same scale for an offer, so the UI can show "your 412 vs 450"
function Game:OfferPower(offer)
    return U.Round((offer.level or 1) * POWER_PER_LEVEL + (offer.ilvl or 0) * POWER_PER_ILVL)
end

function Game:HeroQualityChance(h)
    return QUALITY_CHANCE[h.quality or 2] or 0
end

function Game:HeroStatus(h, now)
    if not h or not h.taskId then return "IDLE" end
    local task = self.db.tasks[h.taskId]
    if not task then h.taskId = nil return "IDLE" end
    return self:TaskReady(task, now) and "READY" or "BUSY"
end

function Game:HeroLook(h)
    local looks = ns.D.LOOKS and ns.D.LOOKS[h.class]
    local l = looks and (looks[h.look or 1] or looks[1])
    return { display = l and l.display, race = (l and l.race) or h.race, sex = (l and l.sex) or h.sex,
             faction = l and l.faction, npc = l and l.npc }
end

----------------------------------------------------------------------------------------------------
-- generation
----------------------------------------------------------------------------------------------------
local function namePick(self, race, sex)
    local N = ns.D.NAMES or {}
    local set = N[race] or N[self:Pick(self:SortedKeys(N)) or ""] or {}
    local first = self:Pick(set[sex] or set.M or set.F or {}) or "Recruit"
    local last = self:Pick(set.last or {})
    return first, last
end

local function nameTaken(self, name)
    for _, h in pairs(self.db.heroes) do if h.name == name then return true end end
    return false
end

function Game:PickTraits(quality)
    local T = ns.D.TRAITS or {}
    local pos, neg = {}, {}
    for _, k in ipairs(self:SortedKeys(T)) do
        if (T[k].value or 0) < 0 then neg[#neg + 1] = k else pos[#pos + 1] = k end
    end
    local out, used = {}, {}
    local n = TRAITS_BY_QUALITY[quality] or 1
    for _ = 1, n do
        for _ = 1, 8 do
            local k = self:Pick(pos)
            if not k then break end
            if not used[k] then used[k] = true out[#out + 1] = k break end
        end
    end
    if #neg > 0 and self:Chance(NEG_TRAIT_CHANCE[quality] or 0) then
        out[#out + 1] = self:Pick(neg)
    end
    return out
end

-- a hero-like table without id/gear (recruit offers); AddHero makes it real
function Game:GenerateHero(quality, tier)
    local C = ns.D.CLASSES or {}
    local classes = self:SortedKeys(C)
    local class = self:Pick(classes) or "WARRIOR"
    local def = C[class] or { roles = { "DAMAGER" } }
    local role = self:Pick(def.roles or { "DAMAGER" }) or "DAMAGER"

    local looks = (ns.D.LOOKS and ns.D.LOOKS[class]) or {}
    local candidates = {}
    for i, l in ipairs(looks) do
        if not self.faction or not l.faction or l.faction == self.faction or l.faction == "Neutral" then
            candidates[#candidates + 1] = i
        end
    end
    if #candidates == 0 then for i = 1, #looks do candidates[i] = i end end
    local lookIndex = self:Pick(candidates) or 1
    local look = looks[lookIndex] or {}
    local race, sex = look.race or "Human", look.sex or "M"

    local first, last
    for _ = 1, 6 do
        first, last = namePick(self, race, sex)
        if not nameTaken(self, first) then break end
    end

    local skills = {}
    for _, p in ipairs(Game.PROFESSIONS) do skills[p] = SKILL_START end
    if def.gather and skills[def.gather] then skills[def.gather] = skills[def.gather] + SKILL_CLASS_BONUS end

    local lr = self:Tier(tier or 1).level or { 1, 10 }
    local h = {
        name = first, surname = last, race = race, sex = sex, class = class, role = role,
        quality = quality or 2, level = lr[1], xp = 0, look = lookIndex, gear = {},
        traits = self:PickTraits(quality or 2), skills = skills,
    }
    self:StarterGear(h)
    return h
end

-- a full set of common gear at the floor of the hero's tier (so offers already show a real ilvl)
function Game:StarterGear(h)
    local tier = self:TierOfLevel(h.level)
    for _, slot in ipairs(self:Slots()) do
        if not h.gear[slot] then
            h.gear[slot] = self:MakeGear(tier, slot, self:TierIlvl(tier, 0), 1)
        end
    end
end

function Game:AddHero(h, now)
    h.id = self:NewId()
    h.recruitedAt = now or self:Now()
    h.gear = h.gear or {}
    h.cost = nil
    self:StarterGear(h)
    self.db.heroes[h.id] = h
    self:AddStat("HEROES")
    self:MaxStat("MAX_LEVEL", h.level)
    self:Changed("heroes")
    return h
end

function Game:Dismiss(heroId)
    local h = self.db.heroes[heroId]
    if not h then return false, "No such recruit." end
    if h.taskId and self.db.tasks[h.taskId] then return false, "That recruit is on a task." end
    if self:HeroCount() <= 1 then return false, "You cannot dismiss your last recruit." end
    for slot, g in pairs(h.gear or {}) do
        if g.quality and g.quality > 1 then self:AddGear(g) end
    end
    self.db.heroes[heroId] = nil
    self:Log(string.format("%s left the camp.", h.name))
    self:Changed("heroes")
    return true
end

----------------------------------------------------------------------------------------------------
-- gear
----------------------------------------------------------------------------------------------------
local function gearBase(tier, slot)
    local GB = ns.D.GEAR_BASES or {}
    for d = 0, 12 do
        for _, t in ipairs({ tier - d, tier + d }) do
            local list = GB[t] and GB[t][slot]
            if list and #list > 0 then return list end
        end
    end
end

function Game:MakeGear(tier, slot, ilvl, quality)
    if slot == nil or slot == "ANY" then slot = self:Pick(self:Slots()) end
    quality = quality or 2
    local list = gearBase(tier, slot)
    local base = list and self:Pick(list) or {}
    return {
        id = self:NewId(), slot = slot, tier = tier, quality = quality,
        ilvl = math.max(1, math.floor(ilvl + 0.5)),
        name = base.name or (slot:sub(1, 1) .. slot:sub(2):lower()), itemID = base.itemID,
    }
end

-- rolled gear for a reward: center ilvl, base quality (may roll one step up)
function Game:RollGear(tier, center, quality, slot)
    quality = quality or 2
    if quality < 4 and self:Chance(0.15) then quality = quality + 1 end
    local ilvl = center + (quality - 2) * GEAR_QUALITY_ILVL + self:RandInt(-GEAR_ILVL_JITTER, GEAR_ILVL_JITTER)
    return self:MakeGear(tier, slot or "ANY", ilvl, quality)
end

function Game:GearValue(g)
    return U.Round(self:GoldRate(g.tier or 1) * (GEAR_SELL_HOURS[g.quality or 1] or 0.02) * (1 + (g.ilvl or 1) / 400))
end

function Game:AddGear(g)
    local bag = self.db.bag
    bag[g.id] = g
    self:AddStat("GEAR")
    if U.Count(bag) > GEAR_BAG_CAP then
        local worst
        for _, x in pairs(bag) do
            if not worst or x.ilvl < worst.ilvl or (x.ilvl == worst.ilvl and x.id < worst.id) then worst = x end
        end
        if worst then
            bag[worst.id] = nil
            self:EarnGold(self:GearValue(worst), true)
        end
    end
    self:Changed("inventory")
end

function Game:GetGearBag()
    local list = {}
    for _, g in pairs(self.db.bag) do list[#list + 1] = g end
    table.sort(list, function(a, b)
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.id < b.id
    end)
    return list
end

function Game:Equip(heroId, gearId)
    local h = self.db.heroes[heroId]
    if not h then return false, "No such recruit." end
    local g = self.db.bag[gearId]
    if not g then return false, "That item is not in your bags." end
    local old = h.gear[g.slot]
    self.db.bag[gearId] = nil
    h.gear[g.slot] = g
    if old then self.db.bag[old.id] = old end
    self:MaxStat("MAX_ILVL", math.floor(self:HeroIlvl(h)))
    self:Changed("heroes")
    return true
end

function Game:Unequip(heroId, slot)
    local h = self.db.heroes[heroId]
    if not h then return false, "No such recruit." end
    local g = h.gear[slot]
    if not g then return false, "Nothing equipped there." end
    h.gear[slot] = nil
    self.db.bag[g.id] = g
    self:Changed("heroes")
    return true
end

-- best ilvl per slot from the bag; returns ok, number of pieces equipped
function Game:AutoEquip(heroId)
    local h = self.db.heroes[heroId]
    if not h then return false, "No such recruit." end
    local n = 0
    for _, slot in ipairs(self:Slots()) do
        local cur = h.gear[slot]
        local best
        for _, g in pairs(self.db.bag) do
            if g.slot == slot and g.ilvl > (cur and cur.ilvl or 0) and (not best or g.ilvl > best.ilvl) then best = g end
        end
        if best then
            self.db.bag[best.id] = nil
            h.gear[slot] = best
            if cur then self.db.bag[cur.id] = cur end
            n = n + 1
        end
    end
    if n > 0 then
        self:MaxStat("MAX_ILVL", math.floor(self:HeroIlvl(h)))
        self:Changed("heroes")
    end
    return true, n
end

-- convenience: everyone, highest level first
function Game:AutoEquipAll()
    local n = 0
    for _, h in ipairs(self:GetHeroes()) do
        local _, k = self:AutoEquip(h.id)
        n = n + (k or 0)
    end
    return true, n
end

function Game:SellGear(gearId)
    local g = self.db.bag[gearId]
    if not g then return nil, "That item is not in your bags." end
    self.db.bag[gearId] = nil
    local copper = self:GearValue(g)
    self:EarnGold(copper)
    self:Changed("inventory")
    return copper
end

----------------------------------------------------------------------------------------------------
-- traits
----------------------------------------------------------------------------------------------------
-- does a trait apply to this context? ctx = {kind=, profession=, instance=}
local function traitApplies(def, ctx)
    local f = def.filter
    if not f then return true end
    if not ctx then return false end
    return f == ctx.kind or f == ctx.profession or f == ctx.instance or f == ctx.mat
end

function Game:TraitKind(def)
    return TRAIT_KIND_ALIAS[def.kind] or def.kind
end

-- summed trait value of `kind` across heroes (party kinds capped); for "XP" pass a single hero
function Game:TraitBonus(heroes, kind, ctx)
    local T = ns.D.TRAITS or {}
    local sum = 0
    for _, h in ipairs(heroes or {}) do
        for _, key in ipairs(h.traits or {}) do
            local def = T[key]
            if def then
                if self:TraitKind(def) == kind and traitApplies(def, ctx) then sum = sum + (def.value or 0) end
                local dr = def.drawback      -- optional second, negative effect
                if dr and self:TraitKind(dr) == kind and traitApplies(dr, ctx) then sum = sum + (dr.value or 0) end
            end
        end
    end
    return U.Clamp(sum, -TRAIT_PARTY_CAP, TRAIT_PARTY_CAP)
end

function Game:TraitNotes(heroes, ctx, notes)
    local T = ns.D.TRAITS or {}
    for _, h in ipairs(heroes or {}) do
        for _, key in ipairs(h.traits or {}) do
            local def = T[key]
            if def and traitApplies(def, ctx) and (def.value or 0) ~= 0 then
                notes[#notes + 1] = string.format("%s: %s %+d%%", h.name, def.name or key, U.Round((def.value or 0) * 100))
            end
            local dr = def and def.drawback
            if dr and traitApplies(dr, ctx) and (dr.value or 0) ~= 0 then
                notes[#notes + 1] = string.format("%s: %s %+d%%", h.name, (def.name or key) .. " (drawback)", U.Round((dr.value or 0) * 100))
            end
        end
    end
end

function Game:SkillUp(h, prof, n)
    if not prof then return end
    h.skills = h.skills or {}
    h.skills[prof] = math.min(SKILL_CAP, (h.skills[prof] or SKILL_START) + (n or 1))
end

function Game:SkillCap() return SKILL_CAP end
