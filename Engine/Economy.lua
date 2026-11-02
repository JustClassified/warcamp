local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Economy.lua — inventory, market, crafting, buildings (+ passive storage), inn recruits
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
-- market: mid = base * (1 + A1 sin(2pi t/P1 + phase1) + A2 sin(2pi t/P2 + phase2)) * (1 - supply)
local MARKET_A1, MARKET_P1 = 0.12, 19 * 3600
local MARKET_A2, MARKET_P2 = 0.07, 74 * 3600
local MARKET_A3, MARKET_P3 = 0.03, 4.3 * 3600
local BUY_SPREAD = 0.25               -- buy = mid * 1.25
local SELL_SPREAD = 0.15              -- sell = mid * 0.85
local SUPPLY_PER_UNIT = 0.0025        -- each unit you sell pushes the price down 0.25% ...
local SUPPLY_MAX = 0.40               -- ... up to 40% ...
local SUPPLY_TAU = 8 * 3600           -- ... and recovers with this time constant
local TRADING_POST_SPREAD = 0.015     -- per level: buy cheaper and sell dearer
local TRADING_POST_SPREAD_MAX = 0.12
-- buildings
local BUILD_QUEUE = 1                 -- constructions at once
local BUILD_QUEUE_TH = 6              -- + 1 queue at this Town Hall level
-- fallback per-level effects; when the data gives def.stat + levels[n].value (see STAT_KIND), the data wins
local BUILDING_FX = {
    STABLES          = { SPEED = 0.025 },
    TRAINING_GROUNDS = { XP = 0.04 },
    TREASURY         = { GOLD = 0.04 },
    TRADING_POST     = { MARKET = TRADING_POST_SPREAD },
    FORGE            = { CRAFT_SPEED = 0.05 },
    ALCHEMY_LAB      = { CRAFT_SPEED = 0.05 },
    KITCHEN          = { CRAFT_SPEED = 0.05 },
    INN              = { RECRUIT = 1 },
    BARRACKS         = { HEROES = 1 },
}
local STAT_KIND = {                   -- D.BUILDINGS[k].stat -> bonus kind fed by levels[n].value
    MISSION_SPEED = "SPEED", XP_BONUS = "XP", GOLD_BONUS = "GOLD", MARKET_BONUS = "MARKET",
}
local LEVEL_FIELD_KIND = { collectBonus = "COLLECT" }   -- extra per-level fields
local STORAGE = {                     -- passive producers: material kind of the current tier
    MINE   = { mat = "ORE",  perHour = 4, hours = 12 },
    GARDEN = { mat = "HERB", perHour = 4, hours = 12 },
}
local CRAFT_SPEED_CAP = 0.5
local CRAFT_ILVL_POS = 0.62           -- crafted gear sits a bit above dungeon difficulty
local CRAFT_QUALITY_ILVL = 4
-- inn
local INN_OFFERS = 3
local INN_REFRESH = 4 * 3600
local INN_REFRESH_PER_LEVEL = 900     -- each Inn level refreshes 15 min sooner
local INN_REFRESH_MIN = 2 * 3600
local INN_QUALITY = { [2] = 70, [3] = 25, [4] = 5 }   -- fallback without levels[n].rareChance/epicChance
local INN_BASE_RARE, INN_BASE_EPIC = 0.05, 0.0         -- Inn not built (data-driven Inn)
local INN_BASE_REFRESH_HOURS = 6
local INN_QUALITY_PER_LEVEL = { [3] = 4, [4] = 1.5 }
local RECRUIT_COST_HOURS = { [2] = 1.5, [3] = 5, [4] = 14 }   -- x GoldRate(tier)
local RECRUIT_COST_ROSTER = 0.12      -- +12% per recruit above 3
local REROLL_COST_HOURS = 0.5
local INN_REROLL_DISCOUNT = 0.05      -- per Inn level

----------------------------------------------------------------------------------------------------
-- inventory
----------------------------------------------------------------------------------------------------
function Game:Gold() return self.db.gold end

function Game:Count(itemKey) return self.db.inventory[itemKey] or 0 end

function Game:GetInventory()
    local I = ns.D.ITEMS or {}
    local list = {}
    for key, n in pairs(self.db.inventory) do
        if n > 0 then list[#list + 1] = { key = key, count = n, item = I[key] or { name = key, quality = 1, tier = 1 } } end
    end
    table.sort(list, function(a, b)
        local ta, tb = a.item.tier or 0, b.item.tier or 0
        if ta ~= tb then return ta > tb end
        if (a.item.kind or "") ~= (b.item.kind or "") then return (a.item.kind or "") < (b.item.kind or "") end
        return a.key < b.key
    end)
    return list
end

-- use a consumable that grants a buff (item.buff = buffKey, or an item key that is also a buff key)
function Game:UseItem(itemKey)
    if self:Count(itemKey) < 1 then return false, "You have none." end
    local it = ns.D.ITEMS and ns.D.ITEMS[itemKey] or {}
    local buff = it.use or it.buff or ((ns.D.BUFFS and ns.D.BUFFS[itemKey]) and itemKey)
    if not buff then return false, "That cannot be used." end
    local ok, err = self:GrantBuff(buff)
    if not ok then return false, err end
    self:AddItem(itemKey, -1)
    return true
end

----------------------------------------------------------------------------------------------------
-- market
----------------------------------------------------------------------------------------------------
local TWO_PI = 2 * math.pi

local function basePrice(self, key)
    local it = ns.D.ITEMS and ns.D.ITEMS[key]
    if it and it.price then return it.price end
    return U.Round(self:GoldRate(it and it.tier or 1) * 0.01)
end

-- units of player-sold supply still weighing on the price at t (decays; never grows if the clock went back)
local function supplyAmt(self, key, t)
    local s = self.db.sales[key]
    if not s or not s.amt or s.amt ~= s.amt then return 0 end
    if t <= (s.t or t) then return math.max(0, s.amt) end
    return math.max(0, s.amt * math.exp(-(t - s.t) / SUPPLY_TAU))
end

local function supplyCut(a)
    return math.min(SUPPLY_MAX, math.max(0, a) * SUPPLY_PER_UNIT)
end

-- mean of (1 - supplyCut(a)) for a from a0 to a1 (exact: linear up to the cap, flat after it)
local function meanFactor(a0, a1)
    if a1 < a0 then a0, a1 = a1, a0 end
    if a1 - a0 < 1e-9 then return 1 - supplyCut(a0) end
    local knee = SUPPLY_MAX / SUPPLY_PER_UNIT
    local function F(a)
        if a <= knee then return a - SUPPLY_PER_UNIT * a * a / 2 end
        return knee - SUPPLY_PER_UNIT * knee * knee / 2 + (a - knee) * (1 - SUPPLY_MAX)
    end
    return (F(a1) - F(a0)) / (a1 - a0)
end

-- mid price before the player's own supply pressure
local function waveMid(self, key, t)
    local h1, h2, h3 = self:Hash01(key), self:Hash01(key .. "#"), self:Hash01("#" .. key)
    local wave = MARKET_A1 * math.sin(TWO_PI * (t / MARKET_P1 + h1))
               + MARKET_A2 * math.sin(TWO_PI * (t / MARKET_P2 + h2))
               + MARKET_A3 * math.sin(TWO_PI * (t / MARKET_P3 + h3))
    return basePrice(self, key) * (1 + wave)
end

function Game:MidPrice(key, t)
    return waveMid(self, key, t) * (1 - supplyCut(supplyAmt(self, key, t)))
end

function Game:MarketBonus()
    return math.min(TRADING_POST_SPREAD_MAX, self:BuildingBonus("MARKET"))
end

-- buy, sell in copper
function Game:Price(itemKey, now)
    now = now or self:Now()
    local mid = self:MidPrice(itemKey, now)
    local tp = self:MarketBonus()       -- buy tp cheaper, sell 2*tp dearer
    local buy = math.max(2, math.ceil(mid * (1 + BUY_SPREAD - tp)))
    local sell = math.max(1, math.floor(mid * (1 - SELL_SPREAD + 2 * tp)))
    if sell >= buy then sell = buy - 1 end
    return buy, sell
end

function Game:PriceHistory(itemKey, n, span)
    n = math.max(2, n or 24)
    span = span or 86400
    local now = self:Now()
    local out = {}
    for i = 1, n do
        local t = now - span + (i - 1) * span / (n - 1)
        local _, sell = self:Price(itemKey, t)
        out[i] = sell
    end
    return out
end

-- Buying soaks up the supply you sold (the price climbs back), priced along the same curve as selling,
-- so "dump a stack, buy it back cheaper" never makes gold.
function Game:Buy(itemKey, n)
    n = tonumber(n) or 1
    if n ~= n or n == math.huge then return false, "Nothing to buy." end
    n = math.floor(n)
    if n < 1 then return false, "Nothing to buy." end
    if not (ns.D.ITEMS and ns.D.ITEMS[itemKey]) then return false, "Unknown item." end
    local now = self:Now()
    local amt = supplyAmt(self, itemKey, now)
    local soaked = math.min(n, amt)
    local f = (soaked > 0 and meanFactor(amt - soaked, amt) * soaked or 0) + (n - soaked)
    local buyMult = 1 + BUY_SPREAD - self:MarketBonus()
    local cost = math.max(2 * n, math.ceil(waveMid(self, itemKey, now) * buyMult * f))
    if not self:SpendGold(cost) then return false, "Not enough gold." end
    if self.db.sales[itemKey] then self.db.sales[itemKey] = { amt = amt - soaked, t = now } end
    self:AddItem(itemKey, n)
    self:AddStat("ITEMS_BOUGHT", n)
    return true, nil, cost
end

-- returns ok, err, copperGained
function Game:Sell(itemKey, n)
    local have = self:Count(itemKey)
    if n == "ALL" then n = have end
    n = tonumber(n) or 0
    if n ~= n then return false, "Nothing to sell." end
    n = math.floor(n)
    if n < 1 or have < 1 then return false, "Nothing to sell." end
    if n > have then n = have end
    local now = self:Now()
    -- price the stack along the supply curve so selling in one go or in parts is fair
    local amt = supplyAmt(self, itemKey, now)
    self.db.sales[itemKey] = { amt = amt + n, t = now }
    local sellMult = 1 - SELL_SPREAD + 2 * self:MarketBonus()
    local gained = math.max(n, U.Round(waveMid(self, itemKey, now) * meanFactor(amt, amt + n) * sellMult * n))
    self:AddItem(itemKey, -n)
    self:EarnGold(gained)
    self:AddStat("ITEMS_SOLD", n)
    self:Changed("inventory")
    return true, nil, gained
end

----------------------------------------------------------------------------------------------------
-- buildings
----------------------------------------------------------------------------------------------------
function Game:BuildingLevel(key)
    local b = self.db and self.db.buildings and self.db.buildings[key]
    return b and b.level or 0
end

-- summed building bonus of a kind (GOLD, XP, SPEED, MARKET, CRAFT_SPEED, ...)
-- levels[level].value from the data (nil when the data has none)
function Game:BuildingValue(key, level)
    local def = ns.D.BUILDINGS and ns.D.BUILDINGS[key]
    local lv = def and def.levels and def.levels[level or self:BuildingLevel(key)]
    return lv and lv.value
end

function Game:BuildingLevelDef(key)
    local def = ns.D.BUILDINGS and ns.D.BUILDINGS[key]
    local lvl = self:BuildingLevel(key)
    return def and def.levels and def.levels[lvl], lvl
end

function Game:BuildingBonus(kind, ctx)
    local sum = 0
    local B = ns.D.BUILDINGS or {}
    for key, def in pairs(B) do
        local lvl = self:BuildingLevel(key)
        if lvl > 0 then
            local lv = def.levels and def.levels[lvl] or {}
            local dataKind = STAT_KIND[def.stat or ""]
            if dataKind and lv.value then
                if dataKind == kind then sum = sum + lv.value end
            else
                local fx = BUILDING_FX[key]
                if fx and fx[kind] then sum = sum + fx[kind] * lvl end
            end
            for field, k in pairs(LEVEL_FIELD_KIND) do
                if k == kind and lv[field] then sum = sum + lv[field] end
            end
        end
    end
    return sum
end

local function fxText(key, level)
    if level <= 0 then return "Not built" end
    local fx = BUILDING_FX[key] or {}
    local parts = {}
    local labels = { GOLD = "gold from missions", SPEED = "mission speed", XP = "experience",
                     MARKET = "better market prices", CRAFT_SPEED = "crafting speed" }
    for _, k in ipairs(Game:SortedKeys(fx)) do
        if labels[k] then parts[#parts + 1] = string.format("+%s%% %s", tostring(U.Round(fx[k] * level * 1000) / 10), labels[k]) end
    end
    if key == "BARRACKS" then parts[#parts + 1] = string.format("%d recruits", Game:MaxHeroesAt(level)) end
    if key == "INN" then parts[#parts + 1] = "better recruits, faster refresh" end
    if key == "TOWN_HALL" then parts[#parts + 1] = string.format("other buildings up to level %d", level) end
    local st = STORAGE[key]
    if st then parts[#parts + 1] = string.format("%d %s/h, holds %d", st.perHour * level, st.mat:lower(), st.perHour * level * st.hours) end
    if key == "TRADING_POST" then parts[#parts + 1] = "better market prices" end
    return table.concat(parts, ", ")
end

function Game:MaxHeroesAt(barracksLevel)
    local cur = self:BuildingLevel("BARRACKS")
    return self:MaxHeroes() - cur + barracksLevel
end

local function buildQueue(self)
    return BUILD_QUEUE + ((self:BuildingLevel("TOWN_HALL") >= BUILD_QUEUE_TH) and 1 or 0)
end

local function buildingsUpgrading(self)
    local n = 0
    for _, t in pairs(self.db.tasks) do if t.kind == "BUILD" then n = n + 1 end end
    return n
end

-- rate/h, cap, tier of a producer at its current level (data levels[n].rate/cap/tier, else constants)
local function producer(self, key)
    local st = STORAGE[key]
    local lvl = self:BuildingLevel(key)
    if not st or lvl <= 0 then return nil end
    local lv = self:BuildingLevelDef(key) or {}
    local rate = lv.rate or st.perHour * lvl
    local cap = lv.cap or rate * st.hours
    local tier = math.min(lv.tier or self.db.tier, self.db.tier)
    local mats = self:Tier(tier).mats or {}
    return rate, cap, mats[st.mat]
end

function Game:StorageInfo(key)
    local rate, cap, item = producer(self, key)
    if not rate then return nil end
    local s = self.db.storage[key] or { have = 0, last = self:Now() }
    return { have = math.floor(s.have), cap = cap, itemKey = item, perHour = rate }
end

function Game:GetBuilding(key)
    local def = ns.D.BUILDINGS and ns.D.BUILDINGS[key]
    if not def then return nil end
    local b = self.db.buildings[key] or { level = 0 }
    self.db.buildings[key] = b
    if b.upgrading then           -- self-heal a flag whose BUILD task is gone (old save, interrupted cancel)
        local found = false
        for _, t in pairs(self.db.tasks) do
            if t.kind == "BUILD" and t.building == key then found = true break end
        end
        if not found then b.upgrading, b.endAt = nil, nil end
    end
    local levels = def.levels or {}
    local max = def.maxLevel or #levels
    local nextDef = levels[b.level + 1]
    local info = {
        key = key, def = def, level = b.level, max = max, upgrading = b.upgrading and true or false, endAt = b.endAt,
        cost = nextDef and { gold = nextDef.gold or 0, items = U.Copy(nextDef.items or {}), time = nextDef.time or 0 } or nil,
        effect = (levels[b.level] and levels[b.level].effect) or fxText(key, b.level),
        nextEffect = nextDef and (nextDef.effect or fxText(key, b.level + 1)) or nil,
        storage = self:StorageInfo(key),
    }
    local reason
    if b.upgrading then
        reason = "Under construction."
    elseif b.level >= max or not nextDef then
        reason = "Fully upgraded."
    elseif key ~= "TOWN_HALL" and b.level + 1 > self:BuildingLevel("TOWN_HALL") then
        reason = string.format("Requires Town Hall level %d.", b.level + 1)
    elseif buildingsUpgrading(self) >= buildQueue(self) then
        reason = "Your builders are busy."
    elseif self.db.gold < (nextDef.gold or 0) then
        reason = "Not enough gold."
    else
        for _, k in ipairs(self:SortedKeys(nextDef.items)) do
            if self:Count(k) < nextDef.items[k] then
                local it = ns.D.ITEMS and ns.D.ITEMS[k]
                reason = string.format("Needs %d %s.", nextDef.items[k], it and it.name or k)
                break
            end
        end
    end
    info.canUpgrade, info.reason = reason == nil, reason
    return info
end

function Game:GetBuildings()
    local out = {}
    local B = ns.D.BUILDINGS or {}
    for _, key in ipairs(self:SortedKeys(B)) do out[#out + 1] = self:GetBuilding(key) end
    table.sort(out, function(a, b)
        if a.key == "TOWN_HALL" then return b.key ~= "TOWN_HALL" end
        if b.key == "TOWN_HALL" then return false end
        return (a.def.name or a.key) < (b.def.name or b.key)
    end)
    return out
end

function Game:Upgrade(key)
    local info = self:GetBuilding(key)
    if not info then return false, "Unknown building." end
    if not info.canUpgrade then return false, info.reason end
    local now = self:Now()
    local cost = info.cost
    self:SpendGold(cost.gold)
    for k, n in pairs(cost.items) do self:AddItem(k, -n) end
    local b = self.db.buildings[key]
    local secs = math.max(10, U.Round((cost.time or 60) * (1 - math.min(0.5, self:Bonus("BUILD_SPEED", nil, nil, now)))))
    local task = {
        id = self:NewId(), kind = "BUILD", building = key, level = b.level + 1, heroes = {},
        name = string.format("%s level %d", info.def.name or key, b.level + 1),
        startAt = now, endAt = now + secs, chance = 1, repeatIt = false, icon = info.def.icon,
        cost = U.Copy(cost),
    }
    self.db.tasks[task.id] = task
    b.upgrading, b.endAt = true, task.endAt
    self:Log("Construction started: " .. task.name .. ".")
    self:Changed("buildings")
    self:Changed("tasks")
    return true
end

function Game:FinishBuilding(task, t)
    local rep = self:NewReport()
    rep.tasks = 0
    local b = self.db.buildings[task.building] or { level = 0 }
    self.db.buildings[task.building] = b
    if STORAGE[task.building] then self:AccrueStorage(t) end
    b.level = math.max(b.level, task.level)
    b.upgrading, b.endAt = nil, nil
    self:AddStat("BUILDINGS")
    rep.buildings[1] = { key = task.building, level = b.level }
    rep.lines[1] = task.name .. " is complete."
    self:Log(rep.lines[1], t)
    self:Changed("buildings")
    self:CheckAchievements(rep, t)
    return rep
end

function Game:RefundBuilding(task)
    local c = task.cost or {}
    self.db.gold = self.db.gold + (c.gold or 0)
    self:Changed("gold")
    for k, n in pairs(c.items or {}) do self:AddItem(k, n) end
    local b = self.db.buildings[task.building]
    if b then b.upgrading, b.endAt = nil, nil end
    self:Changed("buildings")
end

-- passive production up to time t
function Game:AccrueStorage(t)
    for key in pairs(STORAGE) do
        local rate, cap = producer(self, key)
        local s = self.db.storage[key]
        if rate then
            if not s then
                s = { have = 0, last = t }
                self.db.storage[key] = s
            end
            if t > s.last then
                s.have = math.min(cap, s.have + rate * (t - s.last) / 3600)
                s.last = t
            end
        end
    end
end

function Game:CollectStorage(key)
    local info = self:StorageInfo(key)
    if not info then return false, "Nothing is produced here." end
    self:AccrueStorage(self:Now())
    local s = self.db.storage[key]
    local n = math.floor(s.have)
    if n < 1 then return false, "Nothing to collect yet." end
    if not info.itemKey then return false, "Nothing to collect." end
    s.have = s.have - n
    self:AddItem(info.itemKey, n)
    self:Changed("buildings")
    return true, nil, n
end

----------------------------------------------------------------------------------------------------
-- crafting
----------------------------------------------------------------------------------------------------
function Game:CraftIlvl(tier, quality)
    return self:TierIlvl(tier, CRAFT_ILVL_POS) + ((quality or 3) - 3) * CRAFT_QUALITY_ILVL
end

local function buildingBusy(self, building)
    for _, t in pairs(self.db.tasks) do
        if t.kind == "CRAFT" and t.building == building then return t end
    end
end

local function recipeState(self, key, def)
    local bname = (ns.D.BUILDINGS and ns.D.BUILDINGS[def.building] and ns.D.BUILDINGS[def.building].name) or def.building or "?"
    local maxN = 999
    for k, n in pairs(def.inputs or {}) do
        if n > 0 then maxN = math.min(maxN, math.floor(self:Count(k) / n)) end
    end
    if (def.gold or 0) > 0 then maxN = math.min(maxN, math.floor(self.db.gold / def.gold)) end
    local reason
    if (def.tier or 1) > self.db.tier then
        reason, maxN = "Requires " .. (self:Tier(def.tier).name or ("tier " .. def.tier)) .. ".", 0
    elseif self:BuildingLevel(def.building) < (def.buildingLevel or 1) then
        reason, maxN = string.format("Requires %s level %d.", bname, def.buildingLevel or 1), 0
    elseif maxN < 1 then
        reason = (def.gold or 0) > self.db.gold and "Not enough gold." or "Missing materials."
    elseif buildingBusy(self, def.building) then
        reason = bname .. " is busy."
    end
    return reason == nil, math.max(0, maxN), reason
end

function Game:GetRecipes()
    local R = ns.D.RECIPES or {}
    local out = {}
    for _, key in ipairs(self:SortedKeys(R)) do
        local def = R[key]
        local can, maxN, reason = recipeState(self, key, def)
        out[#out + 1] = { recipe = def, key = key, canCraft = can, maxCraftable = maxN, reason = reason }
    end
    table.sort(out, function(a, b)
        if (a.recipe.building or "") ~= (b.recipe.building or "") then return (a.recipe.building or "") < (b.recipe.building or "") end
        if (a.recipe.tier or 0) ~= (b.recipe.tier or 0) then return (a.recipe.tier or 0) < (b.recipe.tier or 0) end
        return a.key < b.key
    end)
    return out
end

function Game:Craft(recipeKey, n)
    local def = ns.D.RECIPES and ns.D.RECIPES[recipeKey]
    if not def then return false, "Unknown recipe." end
    n = math.max(1, math.floor(tonumber(n) or 1))
    local can, maxN, reason = recipeState(self, recipeKey, def)
    if not can then return false, reason end
    if n > maxN then return false, string.format("You can make at most %d.", maxN) end
    local now = self:Now()
    local paid = { gold = (def.gold or 0) * n, items = {} }   -- what this craft took, for an exact refund
    for k, need in pairs(def.inputs or {}) do
        self:AddItem(k, -need * n)
        paid.items[k] = need * n
    end
    self:SpendGold(paid.gold)
    local speed = math.min(CRAFT_SPEED_CAP, self:Bonus("CRAFT_SPEED", nil, nil, now))
    local secs = math.max(10, U.Round((def.time or 60) * n * (1 - speed)))
    local task = {
        id = self:NewId(), kind = "CRAFT", building = def.building, recipe = recipeKey, n = n, heroes = {},
        name = (n > 1 and (n .. "x ") or "") .. (def.name or recipeKey),
        startAt = now, endAt = now + secs, chance = 1, repeatIt = false,
        icon = def.icon, cost = paid,
    }
    self.db.tasks[task.id] = task
    self:Changed("tasks")
    self:Changed("inventory")
    return true
end

-- refunds what the craft actually took (task.cost); older saves without it fall back to the recipe
function Game:RefundCraft(task)
    local c = task.cost
    if not c then
        local def = ns.D.RECIPES and ns.D.RECIPES[task.recipe] or {}
        c = { gold = (def.gold or 0) * (task.n or 1), items = {} }
        for k, need in pairs(def.inputs or {}) do c.items[k] = need * (task.n or 1) end
    end
    for k, n in pairs(c.items or {}) do self:AddItem(k, n) end
    if (c.gold or 0) > 0 then
        self.db.gold = self.db.gold + c.gold
        self:Changed("gold")
    end
end

----------------------------------------------------------------------------------------------------
-- inn
----------------------------------------------------------------------------------------------------
local function innPeriod(self)
    local lv, lvl = self:BuildingLevelDef("INN")
    if lv and lv.refreshHours then return math.max(3600, lv.refreshHours * 3600) end
    if lvl == 0 and ns.D.BUILDINGS and ns.D.BUILDINGS.INN and ns.D.BUILDINGS.INN.levels
        and ns.D.BUILDINGS.INN.levels[1] and ns.D.BUILDINGS.INN.levels[1].refreshHours then
        return INN_BASE_REFRESH_HOURS * 3600
    end
    return math.max(INN_REFRESH_MIN, INN_REFRESH - INN_REFRESH_PER_LEVEL * lvl)
end

local function innWeights(self)
    local lv, lvl = self:BuildingLevelDef("INN")
    local first = ns.D.BUILDINGS and ns.D.BUILDINGS.INN and ns.D.BUILDINGS.INN.levels and ns.D.BUILDINGS.INN.levels[1]
    if (lv and lv.rareChance) or (lvl == 0 and first and first.rareChance) then
        local rare = lv and lv.rareChance or INN_BASE_RARE
        local epic = lv and lv.epicChance or INN_BASE_EPIC
        return { [2] = math.max(0, 1 - rare - epic), [3] = rare, [4] = epic }
    end
    local w = {}
    for q, base in pairs(INN_QUALITY) do w[q] = base + (INN_QUALITY_PER_LEVEL[q] or 0) * lvl end
    return w
end

function Game:RecruitCost(quality)
    local extra = math.max(0, self:HeroCount() - 3)
    return U.Round(self:GoldRate(self.db.tier) * (RECRUIT_COST_HOURS[quality] or 2) * (1 + RECRUIT_COST_ROSTER * extra))
end

local function genInnOffers(self)
    local w = innWeights(self)
    local offers = {}
    for i = 1, INN_OFFERS do
        local q = self:WeightedPick(w)
        local h = self:GenerateHero(q, self.db.tier)
        h.cost = self:RecruitCost(q)
        offers[i] = h
    end
    return offers
end

-- refreshes the inn when its window passed
function Game:InnState(now)
    now = now or self:Now()
    local inn = self.db.inn
    if not inn.refreshAt or now >= inn.refreshAt or not inn.offers then
        local p = innPeriod(self)
        inn.offers = genInnOffers(self)
        inn.refreshAt = (math.floor(now / p) + 1) * p
        self:Changed("inn")
    end
    return inn
end

function Game:GetRecruitOffers()
    local inn = self:InnState(self:Now())
    for _, h in ipairs(inn.offers) do h.cost = self:RecruitCost(h.quality) end
    return { offers = inn.offers, refreshAt = inn.refreshAt }
end

function Game:Recruit(i)
    local inn = self:InnState(self:Now())
    local h = inn.offers[i]
    if not h then return false, "That recruit has moved on." end
    if self:HeroCount() >= self:MaxHeroes() then return false, "The barracks are full." end
    local cost = self:RecruitCost(h.quality)
    if not self:SpendGold(cost) then return false, "Not enough gold." end
    table.remove(inn.offers, i)
    self:AddHero(h, self:Now())
    self:Log(string.format("%s joined the camp.", h.name))
    self:CheckAchievements(nil)
    self:Changed("inn")
    return true, nil, h.id
end

function Game:RerollCost()
    local disc = math.min(0.5, INN_REROLL_DISCOUNT * self:BuildingLevel("INN"))
    return U.Round(self:GoldRate(self.db.tier) * REROLL_COST_HOURS * (1 - disc))
end

function Game:RerollRecruits()
    local cost = self:RerollCost()
    if not self:SpendGold(cost) then return false, "Not enough gold." end
    local inn = self:InnState(self:Now())
    inn.offers = genInnOffers(self)
    self:Changed("inn")
    return true
end
