-- Tests/run.lua — headless harness for the Warcamp engine.
--   lua Tests/run.lua [fixture|fixture12|real] [days]
-- fixture   : Tests/fixture_data.lua with 2 tiers (plumbing)
-- fixture12 : the same fixture stretched to 12 synthetic tiers (balance without real data)
-- real      : Data/*.lua in toc order
-- The addon code is Lua 5.1; this file shims what newer interpreters removed.

unpack = unpack or table.unpack
local MODE = arg and arg[1] or "fixture"
local DAYS = tonumber(arg and arg[2]) or 30

local here = (arg and arg[0] or "Tests/run.lua"):match("^(.*)[/\\]") or "."
local ROOT = here .. "/../"

----------------------------------------------------------------------------------------------------
-- WoW stubs
----------------------------------------------------------------------------------------------------
local START = 1793865600          -- Mon 2026-11-02 08:00 UTC
NOW = START
function time() return math.floor(NOW) end
function date(fmt, t) return os.date("!" .. (fmt or "%c"):gsub("^!", ""), math.floor(t or NOW)) end
local LISTENER_ERRORS = 0
function geterrorhandler() return function(e) LISTENER_ERRORS = LISTENER_ERRORS + 1 print("LISTENER ERROR: " .. tostring(e)) end end
WarcampDB = nil

local function load(path, ...)
    local fn, err = loadfile(ROOT .. path)
    if not fn then error("cannot load " .. path .. ": " .. tostring(err)) end
    return fn(...)
end

local ns = {}
load("Core/Init.lua", "Warcamp", ns)
load("Core/Serialize.lua", "Warcamp", ns)

local DATA_FILES = { "Classes", "Names", "Items", "World", "Instances", "Camp", "Collection" }
if MODE == "real" then
    local n = 0
    for _, f in ipairs(DATA_FILES) do
        local path = "Data/" .. f .. ".lua"
        local fh = io.open(ROOT .. path, "r")
        if fh then
            fh:close()
            load(path, "Warcamp", ns)
            n = n + 1
        else
            print("WARNING: missing " .. path)
        end
    end
    if n == 0 then error("no Data/*.lua files: run with 'fixture'") end
else
    load("Tests/fixture_data.lua", "Warcamp", ns, MODE == "fixture12" and 12 or 2)
end
for _, f in ipairs({ "State", "Heroes", "Board", "Tasks", "Economy", "Progress", "Save" }) do
    load("Engine/" .. f .. ".lua", "Warcamp", ns)
end

local Game, D, U = ns.Game, ns.D, ns.Util
local EVENTS = { CHANGED = 0, REPORT = 0 }
ns.On("CHANGED", function() EVENTS.CHANGED = EVENTS.CHANGED + 1 end)
ns.On("REPORT", function(r) EVENTS.REPORT = EVENTS.REPORT + 1 end)

----------------------------------------------------------------------------------------------------
-- tiny assertion kit
----------------------------------------------------------------------------------------------------
local FAILS, PASSES = 0, 0
local function check(cond, msg)
    if cond then PASSES = PASSES + 1 else FAILS = FAILS + 1 print("  FAIL: " .. msg) end
end
local function isnum(x) return type(x) == "number" end
local function istab(x) return type(x) == "table" end
local function isstr(x) return type(x) == "string" end
local function isbool(x) return type(x) == "boolean" end
local function g(c) return string.format("%.1fg", (c or 0) / 10000) end

----------------------------------------------------------------------------------------------------
-- data schema checks (what the engine relies on); mismatches are reported, not fatal
----------------------------------------------------------------------------------------------------
local SCHEMA = {}
local function schema(cond, msg) if not cond then SCHEMA[#SCHEMA + 1] = msg end end
local function checkData()
    schema(istab(D.TIERS) and #D.TIERS > 0, "D.TIERS missing/empty")
    for i, t in ipairs(D.TIERS or {}) do
        schema(istab(t.level) and isnum(t.level[1]) and isnum(t.level[2]), "TIERS[" .. i .. "].level")
        schema(istab(t.ilvl) and isnum(t.ilvl[1]) and isnum(t.ilvl[2]), "TIERS[" .. i .. "].ilvl")
        schema(istab(t.mats), "TIERS[" .. i .. "].mats")
        for k, v in pairs(t.mats or {}) do schema(D.ITEMS and D.ITEMS[v], "TIERS[" .. i .. "].mats." .. k .. " -> unknown item " .. tostring(v)) end
        if t.rare then schema(D.ITEMS and D.ITEMS[t.rare], "TIERS[" .. i .. "].rare unknown item " .. tostring(t.rare)) end
        if i > 1 then schema(t.level[1] <= D.TIERS[i - 1].level[2] + 1, "TIERS[" .. i .. "] level gap after tier " .. (i - 1)) end
    end
    for _, z in ipairs(D.ZONES or {}) do
        schema(isstr(z.key) and isnum(z.tier) and isnum(z.level), "zone " .. tostring(z.key) .. " key/tier/level")
        schema(istab(z.gather), "zone " .. tostring(z.key) .. " gather")
        for _, p in ipairs(z.gather or {}) do schema(Game.PROF_MAT[p], "zone " .. tostring(z.key) .. " unknown profession " .. tostring(p)) end
    end
    for _, list in ipairs({ { "DUNGEONS", D.DUNGEONS }, { "RAIDS", D.RAIDS } }) do
        for _, ins in ipairs(list[2] or {}) do
            schema(isstr(ins.key) and isnum(ins.tier), list[1] .. " " .. tostring(ins.key) .. " key/tier")
            for _, b in ipairs(ins.bosses or {}) do
                for _, th in ipairs(b.threats or {}) do schema(D.THREATS and D.THREATS[th], ins.key .. " unknown threat " .. tostring(th)) end
            end
        end
    end
    for c, def in pairs(D.CLASSES or {}) do
        for _, th in ipairs(def.counters or {}) do schema(D.THREATS and D.THREATS[th], "class " .. c .. " unknown threat " .. tostring(th)) end
        for _, r in ipairs(def.roles or {}) do schema(D.ROLES and D.ROLES[r], "class " .. c .. " unknown role " .. tostring(r)) end
        schema(D.LOOKS and D.LOOKS[c] and #D.LOOKS[c] > 0, "class " .. c .. " has no LOOKS")
    end
    for k, b in pairs(D.BUILDINGS or {}) do
        schema(istab(b.levels) and #b.levels > 0, "building " .. k .. " levels")
        for L, lv in ipairs(b.levels or {}) do
            for it in pairs(lv.items or {}) do schema(D.ITEMS[it], "building " .. k .. " L" .. L .. " unknown item " .. tostring(it)) end
            schema(isnum(lv.gold) and isnum(lv.time), "building " .. k .. " L" .. L .. " gold/time")
        end
    end
    for _, key in ipairs({ "TOWN_HALL", "BARRACKS", "INN", "MINE", "GARDEN", "FORGE" }) do
        schema(D.BUILDINGS and D.BUILDINGS[key], "missing building " .. key)
    end
    for k, r in pairs(D.RECIPES or {}) do
        schema(D.BUILDINGS and D.BUILDINGS[r.building], "recipe " .. k .. " unknown building " .. tostring(r.building))
        for it in pairs(r.inputs or {}) do schema(D.ITEMS[it], "recipe " .. k .. " unknown input " .. tostring(it)) end
        local o = r.output or {}
        schema(o.item == nil or D.ITEMS[o.item], "recipe " .. k .. " unknown output " .. tostring(o.item))
        schema(o.item or o.gear, "recipe " .. k .. " output has neither item nor gear")
    end
    for k, t in pairs(D.TRAITS or {}) do
        local kind = Game:TraitKind(t)
        schema(({ YIELD = 1, SPEED = 1, XP = 1, GOLD = 1, CHANCE = 1, LOOT = 1, COLLECT = 1 })[kind], "trait " .. k .. " kind " .. tostring(t.kind) .. " has no engine effect")
    end
    for k, b in pairs(D.BUFFS or {}) do
        schema(({ YIELD = 1, SPEED = 1, XP = 1, GOLD = 1, CHANCE = 1, LOOT = 1, COLLECT = 1 })[Game:TraitKind(b)], "buff " .. k .. " kind " .. tostring(b.kind) .. " has no engine effect")
    end
    local known = { TASKS = 1, SUCCESSES = 1, FAILURES = 1, GATHERS = 1, QUESTS = 1, DUNGEONS = 1, RAIDS = 1, BOSSES = 1,
        GOLD_EARNED = 1, GOLD_SPENT = 1, HEROES = 1, MAX_LEVEL = 1, MAX_TIER = 1, MAX_ILVL = 1, LEVELUPS = 1, CRAFTS = 1,
        ITEMS_SOLD = 1, ITEMS_BOUGHT = 1, GEAR = 1, BUILDINGS = 1, BUFFS = 1, MOUNTS = 1, PETS = 1, ERA = 1, LEGACY = 1,
        HEROES_NOW = 1, ACHIEVEMENTS = 1, BUILDING_LEVELS = 1, GOLD = 1, LEVEL = 1, HERO_LEVEL = 1, TIER = 1,
        DUNGEON_CLEARS = 1, RAID_CLEARS = 1, CRAFTED = 1, CRAFT = 1, RECRUITS = 1, MISSIONS = 1, QUESTS_DONE = 1,
        GATHERED = 1, SOLD = 1, ILVL = 1, ERAS = 1, BUILDING_UPGRADES = 1, UPGRADES = 1, SUCCESS = 1, BOSS_KILLS = 1,
        GATHER_TASKS = 1, QUEST_TASKS = 1, HEROES_RECRUITED = 1, HIGHEST_HERO_LEVEL = 1, HIGHEST_TIER = 1, FAILED_TASKS = 1,
        ITEMS_GATHERED = 1, GEAR_CRAFTED_EPIC = 1 }
    for _, a in ipairs(D.ACHIEVEMENTS or {}) do
        local s = tostring(a.stat)
        schema(known[s] or s:match("^BUILDING:") or s:match("^CLEAR:") or s:match("^RAIDS_TIER%d+$"), "achievement " .. tostring(a.key) .. " stat " .. s .. " is not tracked")
    end
end
checkData()

----------------------------------------------------------------------------------------------------
-- 1. contract shape checks
----------------------------------------------------------------------------------------------------
print(string.format("== Warcamp engine harness (%s) ==", MODE))
print("-- 1. contract")
Game:Init()
local db = WarcampDB
check(istab(db) and db.version == Game.DB_VERSION, "Init creates versioned WarcampDB")
check(Game:HeroCount() == 3, "Init seeds 3 recruits")
Game:Update(NOW)
check(Game:Welcome() == nil, "Welcome nil on a fresh camp")

local heroes = Game:GetHeroes()
check(istab(heroes) and #heroes == 3, "GetHeroes array")
local h = heroes[1]
for _, f in ipairs({ "id", "name", "race", "sex", "class", "role", "quality", "level", "xp", "look", "gear", "traits", "skills", "recruitedAt" }) do
    check(h[f] ~= nil, "hero." .. f)
end
check(h.quality == 2, "seed recruits are quality 2")
check(Game:GetHero(h.id) == h, "GetHero")
check(isnum(Game:HeroIlvl(h)) and isnum(Game:HeroPower(h)) and isnum(Game:HeroXPNeeded(h)), "HeroIlvl/Power/XPNeeded numbers")
check(Game:HeroStatus(h) == "IDLE", "HeroStatus IDLE")
local look = Game:HeroLook(h)
check(istab(look) and look.race ~= nil and look.sex ~= nil, "HeroLook")
check(isnum(Game:MaxHeroes()) and isnum(Game:MaxLevel()), "MaxHeroes/MaxLevel")
local ro = Game:GetRecruitOffers()
check(istab(ro.offers) and #ro.offers == 3 and isnum(ro.refreshAt) and isnum(ro.offers[1].cost), "GetRecruitOffers shape")
check(isnum(Game:RerollCost()), "RerollCost")
local gold0 = Game:Gold()
local ok, err = Game:RerollRecruits()
check(ok and Game:Gold() == gold0 - Game:RerollCost(), "RerollRecruits spends gold")
-- gear
local gear = Game:MakeGear(1, "HEAD", 30, 3)
Game:AddGear(gear)
local bag = Game:GetGearBag()
check(#bag == 1 and bag[1].id == gear.id, "GetGearBag")
for _, f in ipairs({ "id", "slot", "tier", "ilvl", "quality", "name" }) do check(gear[f] ~= nil, "gear." .. f) end
local il0 = Game:HeroIlvl(h)
check(Game:Equip(h.id, gear.id) and Game:HeroIlvl(h) > il0, "Equip raises ilvl")
check(#Game:GetGearBag() == 1, "Equip swaps the old piece into the bag")
check(Game:Unequip(h.id, "HEAD") and h.gear.HEAD == nil, "Unequip")
local ok2, n2 = Game:AutoEquip(h.id)
check(ok2 and n2 == 1 and h.gear.HEAD and h.gear.HEAD.id == gear.id, "AutoEquip picks best")
local sb = Game:GetGearBag()[1]
check(isnum(Game:SellGear(sb.id)), "SellGear returns copper")
-- zones / boards
local zones = Game:GetZones()
check(#zones == #D.ZONES and isbool(zones[1].unlocked), "GetZones")
local z1 = zones[1].zone.key
local gb = Game:GetBoard("GATHER", z1)
local qb = Game:GetBoard("QUEST", z1)
local dbd = Game:GetBoard("DUNGEON")
local rbd = Game:GetBoard("RAID")
check(#gb > 0 and #qb > 0 and #dbd == #D.DUNGEONS and #rbd == #D.RAIDS, "GetBoard for all kinds")
local offer = qb[1]
for _, f in ipairs({ "key", "kind", "name", "tier", "level", "ilvl", "minHeroes", "maxHeroes", "duration", "threats", "rewards", "locked" }) do
    check(offer[f] ~= nil, "offer." .. f)
end
check(isnum(offer.rewards.gold) and isnum(offer.rewards.xp) and istab(offer.rewards.items) and istab(offer.rewards.gear), "offer.rewards shape")
check(isbool(rbd[1].weeklyDone), "raid weeklyDone")
local pv = Game:Preview(offer.key, { h.id })
check(pv.ok and isnum(pv.chance) and pv.chance > 0 and pv.chance <= 1 and isnum(pv.duration) and istab(pv.countered)
    and istab(pv.missingRoles) and isnum(pv.xpEach) and istab(pv.rewards) and istab(pv.notes), "Preview shape")
local dpv = Game:Preview(dbd[1].key, { h.id })
check(not dpv.ok and isstr(dpv.reason), "Preview rejects a 1-hero dungeon / locked")
local sug = Game:Suggest(offer.key)
check(istab(sug) and #sug >= 1, "Suggest")
local task, terr = Game:Start(offer.key, { h.id }, false)
check(istab(task) and task.endAt > task.startAt, "Start: " .. tostring(terr))
for _, f in ipairs({ "id", "kind", "offerKey", "name", "heroes", "startAt", "endAt", "chance", "repeatIt" }) do check(task[f] ~= nil, "task." .. f) end
check(Game:HeroStatus(h) == "BUSY", "HeroStatus BUSY")
local s2, e2 = Game:Start(offer.key, { h.id }, false)
check(s2 == nil and isstr(e2), "Start refuses a taken quest / busy hero")
check(#Game:GetTasks() == 1 and not Game:TaskReady(task, NOW) and Game:ReadyCount(NOW) == 0, "GetTasks / TaskReady / ReadyCount")
local c0, ce = Game:Collect(task.id)
check(c0 == nil and isstr(ce), "Collect refuses unfinished")
NOW = task.endAt
check(Game:TaskReady(task, NOW) and Game:ReadyCount(NOW) == 1 and Game:HeroStatus(h) == "READY", "ready after endAt")
local reps0 = EVENTS.REPORT
local rep = Game:Collect(task.id)
check(istab(rep) and isbool(rep.success) and isnum(rep.gold) and istab(rep.xp) and istab(rep.levelUps) and istab(rep.items)
    and istab(rep.gear) and istab(rep.mounts) and istab(rep.pets) and istab(rep.achievements) and istab(rep.lines), "Collect report shape")
check(EVENTS.REPORT == reps0 + 1, "Collect fires REPORT")
check(Game:HeroStatus(h) == "IDLE", "hero idle after collect")
-- cancel
local gofr = Game:GetBoard("GATHER", z1)[1]
local t2 = Game:Start(gofr.key, { h.id }, true)
check(t2 and t2.repeatIt == true, "Start with repeat")
check(Game:Cancel(t2.id) and Game:HeroStatus(h) == "IDLE", "Cancel frees heroes")
check(Game:CollectAll() == nil, "CollectAll nil when nothing ready")
check((Game._muteDepth or 0) == 0 and Game._mute == nil, "batch depth balanced")
local okc, ec = Game:Cancel(-1)
check(okc == false and isstr(ec), "Cancel returns ok, err")
Game:EndBatch() Game:EndBatch()
check((Game._muteDepth or 0) == 0, "EndBatch never goes below 0")
local cBefore = EVENTS.CHANGED
pcall(Game.Batched, Game, function() error("boom") end)
Game:Changed("gold")
check(EVENTS.CHANGED == cBefore + 1, "an error inside a batch does not mute later events")
for k in pairs(Game:GetBuffs()) do check(type(k) == "number", "GetBuffs is a clean array") end
-- economy
check(isnum(Game:Gold()), "Gold")
local mk = D.TIERS[1].mats.ORE
local buy, sell = Game:Price(mk, NOW)
check(isnum(buy) and isnum(sell) and buy > sell and sell > 0, "Price buy > sell")
local b2, s2b = Game:Price(mk, NOW)
check(b2 == buy and s2b == sell, "Price deterministic")
local hist = Game:PriceHistory(mk, 24, 86400)
check(#hist == 24 and isnum(hist[1]), "PriceHistory")
Game:AddItem(mk, 50)
check(Game:Count(mk) == 50, "Count")
local inv = Game:GetInventory()
check(#inv >= 1 and inv[1].key and inv[1].count and inv[1].item, "GetInventory shape")
local gb0 = Game:Gold()
local okS, _, gained = Game:Sell(mk, 20)
check(okS and gained > 0 and Game:Gold() == gb0 + gained and Game:Count(mk) == 30, "Sell")
local _, sellAfter = Game:Price(mk, NOW)
check(sellAfter < sell, "selling pushes the price down")
check(Game:Sell(mk, "ALL") and Game:Count(mk) == 0, "Sell ALL")
local okB = Game:Buy(mk, 2)
check(okB and Game:Count(mk) == 2, "Buy")
local recipes = Game:GetRecipes()
check(#recipes >= 1 and recipes[1].key and recipes[1].recipe and isbool(recipes[1].canCraft) and isnum(recipes[1].maxCraftable), "GetRecipes shape")
local blds = Game:GetBuildings()
check(#blds >= 1 and blds[1].key == "TOWN_HALL", "GetBuildings (Town Hall first)")
local bi = Game:GetBuilding("BARRACKS")
for _, f in ipairs({ "key", "def", "level", "max", "upgrading", "canUpgrade" }) do check(bi[f] ~= nil, "building." .. f) end
check(istab(bi.cost) and isnum(bi.cost.gold), "building.cost")
db.gold = db.gold + 10000000
local maxH0 = Game:MaxHeroes()
local okU, eU = Game:Upgrade("BARRACKS")
check(okU, "Upgrade: " .. tostring(eU))
check(Game:GetBuilding("BARRACKS").upgrading, "building upgrading")
check(not Game:Upgrade("MINE"), "one construction at a time")
NOW = NOW + 2 * 86400
Game:Update(NOW)
check(Game:GetBuilding("BARRACKS").level == 1 and Game:MaxHeroes() >= maxH0, "building finishes in Update")
check(Game:Upgrade("MINE"), "Upgrade MINE")
NOW = NOW + 86400
Game:Update(NOW)
NOW = NOW + 3600 * 5
Game:Update(NOW)
local st = Game:GetBuilding("MINE").storage
check(st and st.have > 0 and st.cap > 0 and st.itemKey, "Mine storage accrues")
local okC = Game:CollectStorage("MINE")
check(okC and Game:Count(st.itemKey) > 0, "CollectStorage")
-- craft
Game:Upgrade("FORGE")
NOW = NOW + 3 * 86400
Game:Update(NOW)
local gr
for _, r in ipairs(Game:GetRecipes()) do if not gr and r.recipe.building == "FORGE" and (r.recipe.tier or 1) <= WarcampDB.tier then gr = r end end
if gr then
    for k, n in pairs(gr.recipe.inputs or {}) do Game:AddItem(k, n * 2) end
    local okCr, eCr = Game:Craft(gr.key, 1)
    check(okCr, "Craft: " .. tostring(eCr))
    local ct
    for _, t in ipairs(Game:GetTasks()) do if t.kind == "CRAFT" then ct = t end end
    check(ct ~= nil, "Craft queues a CRAFT task")
    check(not Game:Craft(gr.key, 1), "one craft per building")
    NOW = ct and ct.endAt or NOW
    local rc = ct and Game:Collect(ct.id)
    check(rc and (#rc.gear > 0 or next(rc.items)), "Collect craft gives output")
end
-- recruit / dismiss
local nH = Game:HeroCount()
local okR, eR = Game:Recruit(1)
check(okR and Game:HeroCount() == nH + 1, "Recruit: " .. tostring(eR))
local newest
for _, x in ipairs(Game:GetHeroes()) do if not newest or x.id > newest.id then newest = x end end
check(Game:Dismiss(newest.id) and Game:HeroCount() == nH, "Dismiss")
-- progress
local bk = next(D.BUFFS or {})
if bk then
    check(Game:GrantBuff(bk) and #Game:GetBuffs() == 1, "GrantBuff / GetBuffs")
    local bb = Game:GetBuffs()[1]
    check(bb.key and bb.def and isnum(bb.expiresAt), "buff shape")
end
local col = Game:GetCollection()
check(istab(col.mounts) and istab(col.pets), "GetCollection")
local ach = Game:GetAchievements()
check(#ach == #(D.ACHIEVEMENTS or {}) and (not ach[1] or (ach[1].def and isnum(ach[1].progress) and isnum(ach[1].goal))), "GetAchievements")
check(isnum(Game:AchievementPoints()), "AchievementPoints")
check(istab(Game:GetStats()) and istab(Game:GetLog()) and (#Game:GetLog() == 0 or (Game:GetLog()[1].t and Game:GetLog()[1].text)), "GetStats / GetLog")
local ei = Game:EraInfo()
check(isnum(ei.era) and isnum(ei.legacy) and isbool(ei.canAdvance) and isstr(ei.reason) and istab(ei.bonus), "EraInfo")
check(not Game:AdvanceEra(), "AdvanceEra refused before the final raid")
db.finalCleared = true
local eraBefore = db.era
local mountsBefore = U.Count(db.collection.mounts)
Game:AddMount(424242, "test")
check(Game:AdvanceEra() and db.era == eraBefore + 1 and db.legacy > 0 and Game:HeroCount() == 3 and db.tier == 1, "AdvanceEra resets the run")
check(U.Count(db.collection.mounts) == mountsBefore + 1, "AdvanceEra keeps the collection")
check(Game:BuildingLevel("BARRACKS") == 0 and Game:BuildingLevel("TOWN_HALL") == 1, "AdvanceEra resets buildings")
check(Game:EraInfo().bonus.xp > 0, "era bonus")
-- migration hook
WarcampDB.version = 0
local ran = false
Game.MIGRATIONS[1] = function(d) ran = true end
Game:Init()
check(ran and WarcampDB.version == Game.DB_VERSION, "migration hook runs")
Game.MIGRATIONS[1] = nil
-- reset (as /camp reset confirm does)
WarcampDB = nil
Game:Init()
check(Game:HeroCount() == 3 and WarcampDB.era == 1, "Init after reset")
check(EVENTS.CHANGED > 0, "CHANGED fired")
-- every contract function exists
local CONTRACT = { "Init", "Update", "Welcome", "GetHeroes", "GetHero", "HeroIlvl", "HeroPower", "HeroXPNeeded", "HeroStatus",
    "HeroLook", "MaxHeroes", "MaxLevel", "GetRecruitOffers", "Recruit", "RerollRecruits", "RerollCost", "Dismiss", "Equip",
    "Unequip", "AutoEquip", "GetGearBag", "SellGear", "GetZones", "GetBoard", "Preview", "Start", "Suggest", "GetTasks",
    "TaskReady", "ReadyCount", "Collect", "CollectAll", "Cancel", "Gold", "Count", "GetInventory", "Price", "PriceHistory",
    "Buy", "Sell", "GetRecipes", "Craft", "GetBuildings", "GetBuilding", "Upgrade", "CollectStorage", "GetBuffs", "GrantBuff",
    "GetCollection", "GetAchievements", "AchievementPoints", "GetStats", "GetLog", "EraInfo", "AdvanceEra" }
local missing = {}
for _, f in ipairs(CONTRACT) do if type(Game[f]) ~= "function" then missing[#missing + 1] = f end end
check(#missing == 0, "contract functions missing: " .. table.concat(missing, ", "))
print(string.format("   %d checks passed, %d failed (%d contract functions present)", PASSES, FAILS, #CONTRACT - #missing))

----------------------------------------------------------------------------------------------------
-- 2. simulated player
----------------------------------------------------------------------------------------------------
local BUILD_PRIORITY = { "TOWN_HALL", "BARRACKS", "TRAINING_GROUNDS", "MINE", "GARDEN", "FORGE", "TREASURY", "STABLES",
    "INN", "TRADING_POST", "ALCHEMY_LAB", "KITCHEN" }
local RESERVE = 20

local function idleHeroes()
    local out = {}
    for _, x in ipairs(Game:GetHeroes()) do if not x.taskId then out[#out + 1] = x end end
    return out
end

local function bestPreview(o)
    local ids = Game:Suggest(o.key)
    if #ids < o.minHeroes then return nil end
    local p = Game:Preview(o.key, ids)
    return p.ok and p or nil, ids
end

-- items the camp wants to keep: next-level building costs + recipe inputs
local function wanted()
    local w = {}
    for _, b in ipairs(Game:GetBuildings()) do
        if b.cost then for k, n in pairs(b.cost.items) do w[k] = (w[k] or 0) + n end end
    end
    for _, r in ipairs(Game:GetRecipes()) do
        if (r.recipe.tier or 1) >= WarcampDB.tier - 1 then
            for k, n in pairs(r.recipe.inputs or {}) do w[k] = (w[k] or 0) + n * 2 end
        end
    end
    return w
end

local function tryBuild()
    for _, key in ipairs(BUILD_PRIORITY) do
        local b = Game:GetBuilding(key)
        if b and b.cost and not b.upgrading then
            local okU = Game:Upgrade(key)
            if okU then return key end
            -- buy missing materials when gold allows (keeps a little for recruits)
            if b.reason and b.reason:match("^Needs") then
                local need, costAll = {}, b.cost.gold
                for k, n in pairs(b.cost.items) do
                    local miss = n - Game:Count(k)
                    if miss > 0 then need[k] = miss costAll = costAll + (Game:Price(k)) * miss end
                end
                if costAll < Game:Gold() * 0.8 then
                    for k, n in pairs(need) do Game:Buy(k, n) end
                    if Game:Upgrade(key) then return key end
                end
            end
        end
    end
end

local function tryRecruit()
    while Game:HeroCount() < Game:MaxHeroes() do
        local ro2 = Game:GetRecruitOffers()
        local roles = {}
        for _, x in ipairs(Game:GetHeroes()) do roles[x.role] = (roles[x.role] or 0) + 1 end
        local best, bi2, bs
        for i, o in ipairs(ro2.offers) do
            if o.cost <= Game:Gold() then
                local score = o.quality * 10 + ((roles[o.role] or 0) == 0 and 15 or 0) + ((o.role ~= "DAMAGER" and (roles[o.role] or 0) < 2) and 6 or 0)
                if not bs or score > bs then best, bi2, bs = o, i, score end
            end
        end
        if not best then return end
        if not Game:Recruit(bi2) then return end
    end
end

local function stale(task)
    if not task.repeatIt then return false end
    local o = task.offer
    for _, id in ipairs(task.heroes) do
        local x = Game:GetHero(id)
        if x and x.level >= Game:MaxLevel() and o.kind ~= "DUNGEON" then return true end
        if x and x.level >= (o.level or 0) + 3 then return true end
    end
    if o.tier < WarcampDB.tier and o.kind == "DUNGEON" then return true end
    return false
end

local function assign()
    -- free heroes for the tier-gate dungeon / raid when a full party (ignoring busy) would do well
    local all = {}
    for id, x in pairs(WarcampDB.heroes) do local c = {} for k, v in pairs(x) do c[k] = v end c.taskId = nil all[id] = c end
    local function gate(list, need)
        for i = #list, 1, -1 do
            local o = list[i]
            if not o.locked and o.tier == WarcampDB.tier then
                local ids = Game:Suggest(o, NOW, all)
                if #ids >= o.minHeroes then
                    local hs = {}
                    for _, id in ipairs(ids) do hs[#hs + 1] = all[id] end
                    local p = Game:PreviewOffer(o, hs, NOW)
                    if p.chance >= need then
                        for _, id in ipairs(ids) do
                            local real = WarcampDB.heroes[id]
                            local rt = real.taskId and WarcampDB.tasks[real.taskId]
                            if rt and rt.offerKey ~= o.key then rt.repeatIt = false end
                        end
                        return
                    end
                end
            end
        end
    end
    gate(Game:GetBoard("RAID"), 0.5)
    gate(Game:GetBoard("DUNGEON"), 0.55)

    -- the tier-gate dungeon first, then raids of the current/previous tier, then the best dungeon farm
    local dlist = Game:GetBoard("DUNGEON")
    local function dungeons(onlyGate)
        for i = #dlist, 1, -1 do
            local o = dlist[i]
            local gateOne = o.tier == WarcampDB.tier and WarcampDB.tier < Game:NumTiers()
            if not o.locked and (gateOne or not onlyGate) then
                local p, ids = bestPreview(o)
                local need = gateOne and 0.5 or 0.7
                if p and p.chance >= need then
                    Game:Start(o.key, ids, true)
                    dlist = Game:GetBoard("DUNGEON")
                end
            end
        end
    end
    dungeons(true)
    for _, o in ipairs(Game:GetBoard("RAID")) do
        if not o.locked and o.tier >= WarcampDB.tier - 1 then
            local p, ids = bestPreview(o)
            if p and p.chance >= 0.5 then Game:Start(o.key, ids, false) end
        end
    end
    dungeons(false)
    -- everyone else: best xp/sec quest or gather
    for _, x in ipairs(idleHeroes()) do
        local best, bestScore
        local capped = x.level >= Game:MaxLevel()
        for _, zi in ipairs(Game:GetZones()) do
            if zi.unlocked and math.abs((zi.zone.level or 0) - x.level) <= 12 then
                for _, kind in ipairs({ "QUEST", "GATHER" }) do
                    for _, o in ipairs(Game:GetBoard(kind, zi.zone.key)) do
                        if not o.locked then
                            local p = Game:Preview(o.key, { x.id })
                            if p.ok then
                                local v = capped and (p.rewards.gold or 0) or (p.xpBy[x.id] or 0)
                                local score = p.chance * v / p.duration
                                if capped and kind == "GATHER" then
                                    for k, n in pairs(p.rewards.items or {}) do score = score + p.chance * n * select(2, Game:Price(k)) / p.duration end
                                end
                                if not bestScore or score > bestScore then best, bestScore = o, score end
                            end
                        end
                    end
                end
            end
        end
        if best then Game:Start(best.key, { x.id }, true) end
    end
end

local function sellSurplus()
    local w = wanted()
    for _, it in ipairs(Game:GetInventory()) do
        local keep = (w[it.key] or 0) + RESERVE
        if it.item.use or it.item.buff then
            Game:UseItem(it.key)
            keep = 99
        end
        if (it.item.tier or 1) < WarcampDB.tier - 1 and not w[it.key] then keep = 0 end
        if it.count > keep then Game:Sell(it.key, it.count - keep) end
    end
    for _, gg in ipairs(Game:GetGearBag()) do Game:SellGear(gg.id) end
end

local function craft()
    for _, r in ipairs(Game:GetRecipes()) do
        if r.canCraft and r.recipe.output and r.recipe.output.gear and (r.recipe.tier or 1) >= WarcampDB.tier - 1 then
            local gc = r.recipe.gold or 0
            if gc < Game:Gold() * 0.25 then Game:Craft(r.key, 1) end
        end
    end
end

local SESSION = { tasks = 0, levelUps = 0, builds = 0 }
-- outcome tally per kind (and chance bucket) for tuning: set WARCAMP_TALLY=1
local TALLY = {}
if os.getenv("WARCAMP_TALLY") then
    local orig = Game.ResolveMission
    Game.ResolveMission = function(self, task, t)
        local r = orig(self, task, t)
        local day = math.floor((t - START) / 86400 / 7) + 1
        local k = string.format("w%d %-7s c%.1f", day, task.kind, math.floor(task.chance * 10) / 10)
        local e = TALLY[k] or { 0, 0 }
        TALLY[k] = e
        e[1] = e[1] + 1
        if not r.success then e[2] = e[2] + 1 end
        if task.chance < 0.1 and os.getenv("WARCAMP_TALLY") == "2" then
            local hh = Game:GetHero(task.heroes[1])
            print("LOW", task.kind, task.name, task.offer.level, task.offer.ilvl, task.offer.tier, hh and hh.level, hh and Game:HeroIlvl(hh), task.repeatIt, task.loops, WarcampDB.tier, (t-START)/86400)
        end
        return r
    end
end
local function checkIn()
    Game:Update(NOW)
    local rep = Game:CollectAll()
    if rep then
        SESSION.tasks = SESSION.tasks + rep.tasks
        for _ in pairs(rep.levelUps) do SESSION.levelUps = SESSION.levelUps + 1 end
    end
    Game:CollectStorage("MINE")
    Game:CollectStorage("GARDEN")
    for _, t in ipairs(Game:GetTasks()) do if stale(t) then Game:SetRepeat(t.id, false) end end
    tryRecruit()
    Game:AutoEquipAll()
    sellSurplus()
    if tryBuild() then SESSION.builds = SESSION.builds + 1 end
    tryRecruit()
    craft()
    assign()
end

local function snapshot()
    local hs = Game:GetHeroes()
    local maxL, il = 0, 0
    for _, x in ipairs(hs) do
        if x.level > maxL then maxL = x.level end
        il = il + Game:HeroIlvl(x)
    end
    local st2 = Game:GetStats()
    return { gold = Game:Gold(), tier = WarcampDB.tier, maxL = maxL, ilvl = #hs > 0 and il / #hs or 0, heroes = #hs,
             blds = st2.BUILDING_LEVELS, dungeons = st2.DUNGEONS or 0, raids = st2.RAIDS or 0, mounts = st2.MOUNTS,
             pets = st2.PETS, ach = U.Count(WarcampDB.achievements), fails = st2.FAILURES or 0, tasks = st2.TASKS or 0, era = WarcampDB.era }
end

print("-- 2. simulated player: check in every 2-4 h while awake (07-23h), " .. DAYS .. " days")
math.randomseed(1234)
WarcampDB = nil
NOW = START
Game:Init()
WarcampDB.rng = 987654321
-- session 1: actively online for 15 minutes, looking every minute
local s1end = NOW + 15 * 60
while NOW <= s1end do checkIn() NOW = NOW + 60 end
local s1 = snapshot()
print(string.format("   session 1 (15 min): %d tasks done, %d level-ups, %d building upgrade(s) started (%d finished), %d recruits, max level %d, %s",
    WarcampDB.stats.TASKS or 0, WarcampDB.stats.LEVELUPS or 0, SESSION.builds, WarcampDB.stats.BUILDINGS or 0, s1.heroes, s1.maxL, g(s1.gold)))

local function printDay(day, s)
    print(string.format("   %3d  %-9s %4d %6d %7.1f %6d %4d %4d %4d %6d %4d %3d %6d %5d", day, g(s.gold), s.tier, s.maxL, s.ilvl,
        s.heroes, s.blds, s.dungeons, s.raids, s.mounts, s.pets, s.ach, s.tasks, s.fails))
end
-- plays `days` days from NOW; prints a row per day unless quiet; returns tierDays, firstDungeonDay, finalDay
local function playDays(days, quiet)
    local t0 = NOW
    if not quiet then print("   day  gold      tier maxLvl avgIlvl heroes blds dung raid mounts pets ach  tasks fails") end
    local firstDungeonDay, tierDays, finalDay = nil, {}, nil
    local d0 = WarcampDB.stats.DUNGEONS or 0
    local curDay, lastSnap = 1, snapshot()
    while true do
        local nextT = NOW + math.random(2 * 3600, 4 * 3600)
        local nh = tonumber(os.date("!%H", nextT))
        if nh >= 23 or nh < 7 then
            local d = math.floor(nextT / 86400) * 86400
            if nh >= 23 then d = d + 86400 end
            nextT = d + 7 * 3600 + math.random(0, 3600)
        end
        if nextT >= t0 + days * 86400 then break end
        NOW = nextT
        local day = math.floor((NOW - t0) / 86400) + 1
        if day > curDay then
            if not quiet then printDay(curDay, lastSnap) end
            curDay = day
        end
        checkIn()
        local s = snapshot()
        lastSnap = s
        if os.getenv("WARCAMP_PROBE") and day == tonumber(os.getenv("WARCAMP_PROBE")) and not PROBED then
            PROBED = true
            local all = {}
            for id, x in pairs(WarcampDB.heroes) do local c = {} for k, v in pairs(x) do c[k] = v end c.taskId = nil all[id] = c end
            for _, o in ipairs(Game:GetBoard("DUNGEON")) do
                if o.tier == WarcampDB.tier then
                    local ids = Game:Suggest(o, NOW, all)
                    local hs = {}
                    for _, id in ipairs(ids) do hs[#hs + 1] = all[id] end
                    local p = Game:PreviewOffer(o, hs, NOW)
                    print("PROBE", o.name, "lvl", o.level, "ilvl", o.ilvl, "locked", o.locked, o.lockReason, "party", #ids, "chance", p.chance, p.reason)
                    for _, x in ipairs(hs) do print("PROBE   ", x.role, x.level, Game:HeroIlvl(x)) end
                    for _, n in ipairs(p.notes) do print("PROBE   note", n) end
                end
            end
            for _, t in ipairs(Game:GetTasks()) do print("PROBE task", t.kind, t.name, t.repeatIt, #t.heroes) end
        end
        if s.dungeons > d0 and not firstDungeonDay then firstDungeonDay = (NOW - t0) / 86400 end
        if not tierDays[s.tier] then tierDays[s.tier] = (NOW - t0) / 86400 end
        if WarcampDB.finalCleared and not finalDay then
            finalDay = (NOW - t0) / 86400
            if quiet then break end
        end
    end
    if not quiet then printDay(curDay, lastSnap) end
    return tierDays, firstDungeonDay, finalDay
end
local function tierLine(tierDays)
    local tl = {}
    for t = 2, Game:NumTiers() do if tierDays[t] then tl[#tl + 1] = string.format("T%d d%.1f", t, tierDays[t]) end end
    return table.concat(tl, ", ")
end
local tierDays, firstDungeonDay, finalDay = playDays(DAYS)
if next(TALLY) then
    for _, k in ipairs(Game:SortedKeys(TALLY)) do print(string.format("   tally %s  n=%5d  fail=%5d", k, TALLY[k][1], TALLY[k][2])) end
end
print("   tier reached: " .. tierLine(tierDays))
print(string.format("   first dungeon clear: day %s; final raid cleared: %s", firstDungeonDay and string.format("%.2f", firstDungeonDay) or "never",
    finalDay and string.format("day %.1f", finalDay) or "no"))
-- New Era: same player, era 2 (and 3), until the final raid falls again
for era = 2, 3 do
    if not WarcampDB.finalCleared then break end
    local info = Game:EraInfo()
    check(Game:AdvanceEra(), "AdvanceEra after the final raid")
    local td, _, fd = playDays(60, true)
    print(string.format("   era %d (legacy %d, +%d%% xp/gold): %s; final raid day %s", era, WarcampDB.legacy, math.floor(Game:EraInfo().bonus.xp * 100 + 0.5),
        tierLine(td), fd and string.format("%.1f", fd) or "not within 60 days"))
    if not fd then
        local rl = Game:GetBoard("RAID")
        local o = rl[#rl]
        local all = {}
        for id, x in pairs(WarcampDB.heroes) do local c = {} for k, v in pairs(x) do c[k] = v end c.taskId = nil all[id] = c end
        local ids = Game:Suggest(o, NOW, all)
        local hs = {}
        for _, id in ipairs(ids) do hs[#hs + 1] = all[id] end
        local p = Game:PreviewOffer(o, hs, NOW)
        print("   final raid check:", o.name, o.locked, o.lockReason, #ids, p.chance, p.reason, Game:HeroCount(), Game:MaxHeroes())
        for _, n in ipairs(p.notes) do print("     ", n) end
        for _, x in ipairs(hs) do print("     ", x.name, x.role, x.level, Game:HeroIlvl(x)) end
    end
end
local simSnap = snapshot()

----------------------------------------------------------------------------------------------------
-- 3. offline: play a little, set repeats, vanish for 3 days, log in once
----------------------------------------------------------------------------------------------------
print("-- 3. offline 3 days")
WarcampDB = nil
NOW = START
Game:Init()
WarcampDB.rng = 55555
for _ = 1, 6 do checkIn() NOW = NOW + 1800 end
checkIn()
for _, t in ipairs(Game:GetTasks()) do if t.kind ~= "BUILD" and t.kind ~= "CRAFT" and t.kind ~= "RAID" then Game:SetRepeat(t.id, true) end end
local leftAt = NOW
WarcampDB.lastSeen = leftAt              -- PLAYER_LOGOUT
local repeating = 0
for _, t in ipairs(Game:GetTasks()) do if t.repeatIt then repeating = repeating + 1 end end
local goldBefore, tasksBefore = Game:Gold(), WarcampDB.stats.TASKS or 0
check(repeating > 0, "offline test has repeating tasks")
if os.getenv("DBG") then for _, t in ipairs(Game:GetTasks()) do print("DBG task", t.id, t.kind, t.name, t.repeatIt, (t.startAt-leftAt)/3600, (t.endAt-leftAt)/3600) end end
NOW = leftAt + 3 * 86400
Game:Init()                              -- next login: ADDON_LOADED
Game:Update(NOW)                         -- PLAYER_LOGIN tick
local w = Game:Welcome()
check(w ~= nil and w.away and math.abs(w.away - 3 * 86400) < 5, "Welcome after 3 days")
local latestStart, latestEnd = 0, 0
if os.getenv("DBG") then for _, t in ipairs(Game:GetTasks()) do print("DBG after", t.id, t.kind, t.name, t.repeatIt, t.loops, (t.startAt-leftAt)/3600, (t.endAt-leftAt)/3600) end end
for _, t in ipairs(Game:GetTasks()) do
    if t.kind ~= "BUILD" then
        if t.startAt > latestStart then latestStart = t.startAt end
        if t.endAt > latestEnd then latestEnd = t.endAt end
    end
end
local cap = Game:OfflineCap()
check(latestStart < leftAt + cap, string.format("no task restarted after the 12 h cap (latest start %.1f h after logout)", (latestStart - leftAt) / 3600))
check(Game:ReadyCount(NOW) > 0, "tasks wait as READY after the cap")
local loops = (WarcampDB.stats.TASKS or 0) - tasksBefore
print(string.format("   %d repeating tasks at logout; %d auto-collected while away; latest restart %.1f h after logout; %d ready on login",
    repeating, loops, (latestStart - leftAt) / 3600, Game:ReadyCount(NOW)))
print(string.format("   welcome: away %s, %d tasks (%d ok / %d failed), +%s, %d lines", U.Duration(w and w.away or 0), w and w.tasks or 0,
    w and w.success or 0, w and w.fail or 0, g(w and w.gold or 0), w and #w.lines or 0))
check(Game:Welcome() == nil, "Welcome only once per session")
-- determinism
local function quickRun()
    WarcampDB = nil
    NOW = START
    Game:Init()
    WarcampDB.rng = 4242
    math.randomseed(99)
    for _ = 1, 20 do NOW = NOW + 7200 checkIn() end
    return Game:Gold(), WarcampDB.stats.TASKS, WarcampDB.rng
end
local a1, a2, a3 = quickRun()
local b1, b2, b3 = quickRun()
check(a1 == b1 and a2 == b2 and a3 == b3, "simulation is deterministic")
-- Update cheap when nothing is due
local t0 = os.clock()
for _ = 1, 2000 do Game:Update(NOW) end
local per = (os.clock() - t0) / 2000 * 1e6
check(per < 500, string.format("Update is cheap when idle (%.0f us)", per))
print(string.format("   idle Update: %.0f us", per))


-- ==== save: serializer, export / import, backup, reset, sanitize, migration ====
do
    local sample = { a = 1, b = "x\n\"q\"|cffff0000red|r\\", c = { 1, 2, { d = true, e = false } }, [7] = -3.25, big = 1e20, neg = -12 }
    local back = U.Deserialize(U.Serialize(sample))
    check(back and back.b == sample.b and back.c[3].d == true and back.c[3].e == false and back[7] == -3.25
        and back.big == 1e20 and back.neg == -12, "serializer round-trips strings, escapes, numbers, booleans")
    check(U.Deserialize("{[\"a\"]=os.exit()}") == nil, "deserializer rejects code")
    check(U.Deserialize("{[\"a\"]=1") == nil, "deserializer rejects truncated text")
    for _, s in ipairs({ "", "a", "ab", "abc", "abcd", "\0\255\128" }) do
        check(U.Base64Decode(U.Base64Encode(s)) == s, "base64 round-trip " .. #s)
    end

    for _ = 1, 3 do NOW = NOW + 3600 checkIn() end
    local gold, heroes, tasks = Game:Gold(), U.Count(WarcampDB.heroes), U.Count(WarcampDB.tasks)
    local inv = U.Copy(WarcampDB.inventory)
    WarcampDB.ui = { scale = 1.2, minimapHide = true }
    local str = Game:ExportString()
    print(string.format("   export string: %d chars", #str))
    check(str:match("^WARCAMP1:%x+:[%w%+/=]+$") ~= nil, "export string is one copyable line")
    check(not str:find("|", 1, true), "export string has no | (chat escape) characters")

    -- damaged strings are refused and change nothing
    check(Game:ParseImport("hello") == nil, "import rejects junk")
    check(Game:ParseImport(str:sub(1, #str - 40)) == nil, "import rejects a truncated string")
    local tampered = str:sub(1, 30) .. (str:sub(31, 31) == "A" and "B" or "A") .. str:sub(32)
    check(Game:ParseImport(tampered) == nil, "import rejects a changed string (checksum)")
    check(Game:Gold() == gold, "a refused import changes nothing")

    -- reset, then import the export: everything back, per-PC ui settings kept
    Game:ResetAll()
    check(U.Count(WarcampDB.heroes) == 3 and Game:Gold() ~= gold, "reset gives a fresh camp")
    check(Game:GetBackup() and Game:GetBackup().reason == "before reset", "reset keeps a backup")
    check(WarcampDB.ui and WarcampDB.ui.scale == 1.2, "reset keeps window settings")
    local ok = Game:ImportString("  " .. str:sub(1, 50) .. "\n" .. str:sub(51) .. "  \n")
    check(ok, "import accepts the export (with whitespace and line breaks)")
    check(Game:Gold() == gold and U.Count(WarcampDB.heroes) == heroes and U.Count(WarcampDB.tasks) == tasks,
        "import restores gold, heroes and tasks")
    local same = true
    for k, n in pairs(inv) do if WarcampDB.inventory[k] ~= n then same = false end end
    check(same, "import restores the bags")
    check(Game:GetBackup().reason == "before import", "import backs up the camp it replaces")
    check(WarcampDB.ui.minimapHide == true, "import keeps this PC's ui settings")

    -- restore the backup (the fresh camp), then restore again (back to the imported one)
    check(Game:RestoreBackup(), "restore backup works")
    check(U.Count(WarcampDB.heroes) == 3, "restore brings the backed-up camp back")
    check(Game:RestoreBackup() and Game:Gold() == gold, "restoring twice swaps back")
    NOW = NOW + 60 checkIn()

    -- the compressed form (client deflate stubbed as identity) round-trips too
    C_EncodingUtil = { CompressString = function(x) return x end, DecompressString = function(x) return x end,
                       EncodeBase64 = U.Base64Encode, DecodeBase64 = U.Base64Decode }
    local z = Game:ExportString()
    check(z:match("^WARCAMP1Z:") ~= nil and Game:ParseImport(z) ~= nil, "compressed export round-trips")
    C_EncodingUtil = nil
    check(Game:ParseImport(z) == nil, "compressed string is refused cleanly without the client unpacker")

    -- an update that removed data: unknown keys are dropped, not crashed on
    local anyHero
    for _, h in pairs(WarcampDB.heroes) do anyHero = h break end
    WarcampDB.inventory.REMOVED_ITEM = 5
    WarcampDB.inventory.BAD_COUNT = 0 / 0
    WarcampDB.buildings.REMOVED_BUILDING = { level = 3 }
    WarcampDB.buffs.REMOVED_BUFF = NOW + 100
    WarcampDB.heroes[999999] = { id = 999999, class = "REMOVED_CLASS", level = 5, name = "Ghost" }
    WarcampDB.gold = 1 / 0
    anyHero.taskId = 888888
    Game:Init(NOW)
    check(WarcampDB.inventory.REMOVED_ITEM == nil and WarcampDB.inventory.BAD_COUNT == nil, "sanitize drops unknown items")
    check(WarcampDB.buildings.REMOVED_BUILDING == nil and WarcampDB.buffs.REMOVED_BUFF == nil, "sanitize drops unknown buildings and buffs")
    check(WarcampDB.heroes[999999] ~= nil, "sanitize keeps a recruit whose class left the data")
    WarcampDB.heroes[999999] = nil
    check(WarcampDB.gold == 0 and anyHero.taskId == nil, "sanitize fixes bad gold and dangling task ids")
    for _ = 1, 3 do NOW = NOW + 3600 checkIn() end
    check(true, "camp keeps running after a sanitize")

    -- a save from an older layout: backed up, migrated, sanitized
    local oldVersion, oldMig = Game.DB_VERSION, Game.MIGRATIONS[Game.DB_VERSION + 1]
    Game.DB_VERSION = oldVersion + 1
    Game.MIGRATIONS[Game.DB_VERSION] = function(db) db.migratedFlag = true end
    local goldBefore = Game:Gold()
    Game:Init(NOW)
    check(WarcampDB.migratedFlag and WarcampDB.version == Game.DB_VERSION, "migration runs on an older save")
    check(Game:GetBackup() and Game:GetBackup().version == oldVersion, "an update backs up the old save first")
    check(Game:Gold() == goldBefore, "an update keeps the gold")
    Game.DB_VERSION, Game.MIGRATIONS[oldVersion + 1] = oldVersion, oldMig
    WarcampDB.migratedFlag, WarcampDB.version = nil, oldVersion
end

print(string.format("== %d passed, %d failed, %d listener errors, %d schema notes ==", PASSES, FAILS, LISTENER_ERRORS, #SCHEMA))
for _, s in ipairs(SCHEMA) do print("   schema: " .. s) end
os.exit((FAILS == 0 and LISTENER_ERRORS == 0) and 0 or 1)
