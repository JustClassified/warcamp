local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Tasks.lua — start / collect / cancel, repeat loops, offline catch-up, welcome report
----------------------------------------------------------------------------------------------------

-- ===== tuning =====
local OFFLINE_CAP = 24 * 3600         -- repeat loops keep restarting for at most this long after you leave
local WELCOME_MIN_AWAY = 300          -- Welcome() returns nil for shorter absences
local FAIL_XP = 0.40                  -- a failed mission still teaches something ...
local FAIL_GOLD = 0.15                -- ... and pays a little
local SKILL_PER_GATHER = 1            -- + 1 per 30 min of gathering
local MAX_CATCHUP_STEPS = 20000       -- safety valve for one Update()
local REPEATABLE = { GATHER = true, QUEST = true, DUNGEON = true }
local IDLE_XP_STEP = 600              -- idle training xp (Training Grounds levels[n].idleXP per hour) is paid in 10-min steps

----------------------------------------------------------------------------------------------------
-- queries
----------------------------------------------------------------------------------------------------
function Game:GetTasks()
    local list = {}
    for _, t in pairs(self.db.tasks) do list[#list + 1] = t end
    table.sort(list, function(a, b)
        if a.endAt ~= b.endAt then return a.endAt < b.endAt end
        return a.id < b.id
    end)
    return list
end

function Game:GetTask(id) return self.db.tasks[id] end

function Game:TaskReady(task, now)
    return task ~= nil and (now or self:Now()) >= task.endAt
end

-- tasks waiting for a click (missions and crafts; buildings finish by themselves)
function Game:ReadyCount(now)
    now = now or self:Now()
    local n = 0
    for _, t in pairs(self.db.tasks) do
        if t.kind ~= "BUILD" and now >= t.endAt then n = n + 1 end
    end
    return n
end

----------------------------------------------------------------------------------------------------
-- start
----------------------------------------------------------------------------------------------------
local function heroesOf(self, ids)
    local list = {}
    for _, id in ipairs(ids) do
        local h = self.db.heroes[id]
        if h then list[#list + 1] = h end
    end
    return list
end

function Game:StartOffer(o, heroes, t, repeatIt, p)
    local task = {
        id = self:NewId(), kind = o.kind, offerKey = o.key, name = o.name, heroes = {},
        startAt = t, endAt = t + p.duration, chance = p.chance, repeatIt = (repeatIt and REPEATABLE[o.kind]) and true or false,
        display = o.display, icon = nil, zone = o.zone, instance = o.instance, profession = o.profession,
        offer = o, rewards = p.rewards, xpBy = p.xpBy, loops = 0,
    }
    for i, h in ipairs(heroes) do
        task.heroes[i] = h.id
        h.taskId = task.id
    end
    self.db.tasks[task.id] = task
    return task
end

function Game:Start(offerKey, heroIds, repeatIt)
    local now = self:Now()
    local o = self:FindOffer(offerKey, now)
    if not o then return nil, "That offer is gone." end
    local heroes = heroesOf(self, heroIds or {})
    if #heroes ~= #(heroIds or {}) then return nil, "Unknown recruit." end
    local p = self:PreviewOffer(o, heroes, now)
    if not p.ok then return nil, p.reason end
    local snapshot = U.Copy(o)
    snapshot.taken = nil
    local task = self:StartOffer(snapshot, heroes, now, repeatIt, p)
    if o.kind == "QUEST" then self:ReplaceQuest(o) end
    self:Changed("tasks")
    self:Changed("heroes")
    return task
end

function Game:SetRepeat(taskId, on)
    local task = self.db.tasks[taskId]
    if not task then return false, "No such task." end
    if on and not REPEATABLE[task.kind] then return false, "That cannot repeat." end
    task.repeatIt = on and true or false
    self:Changed("tasks")
    return true
end

----------------------------------------------------------------------------------------------------
-- resolution
----------------------------------------------------------------------------------------------------
function Game:EarnGold(c, silent)
    c = tonumber(c) or 0
    if c ~= c or c == math.huge then return 0 end     -- never let NaN/inf reach the save
    c = math.floor(c + 0.5)
    if c <= 0 then return 0 end
    self.db.gold = self.db.gold + c
    self:AddStat("GOLD_EARNED", c)
    self:Changed("gold")
    return c
end

function Game:SpendGold(c)
    c = tonumber(c) or 0
    if c ~= c or c < 0 or c == math.huge then return false end
    c = math.floor(c + 0.5)
    if self.db.gold < c then return false end
    self.db.gold = self.db.gold - c
    self:AddStat("GOLD_SPENT", c)
    self:Changed("gold")
    return true
end

function Game:AddItem(key, n)
    if not key or not n or n == 0 then return end
    local inv = self.db.inventory
    inv[key] = math.max(0, (inv[key] or 0) + n)
    if inv[key] == 0 then inv[key] = nil end
    self:Changed("inventory")
end

local function itemName(key)
    local it = ns.D.ITEMS and ns.D.ITEMS[key]
    return it and it.name or key
end

-- resolve a mission task at time t into a single report (success = bool)
function Game:ResolveMission(task, t)
    local db = self.db
    local o = task.offer or {}
    local r = task.rewards or {}
    local rep = self:NewReport()
    rep.tasks = 1
    rep.taskName = task.name
    rep.kind = task.kind
    local ok = self:Rand() < (task.chance or 0)
    rep.success = ok
    local heroes = heroesOf(self, task.heroes)

    -- xp
    for _, h in ipairs(heroes) do
        local xp = (task.xpBy and task.xpBy[h.id]) or 0
        if not ok then xp = xp * FAIL_XP end
        xp = U.Round(xp)
        if xp > 0 then
            rep.xp[h.id] = xp
            local lv = self:GiveXP(h, xp)
            if lv then
                rep.levelUps[h.id] = lv
                rep.lines[#rep.lines + 1] = string.format("%s reached level %d.", h.name, lv)
            end
        end
    end
    -- gold
    local gold = ok and (r.gold or 0) or U.Round((r.gold or 0) * FAIL_GOLD)
    rep.gold = self:EarnGold(gold)

    self:AddStat("TASKS")
    self:AddStat(ok and "SUCCESSES" or "FAILURES")
    if task.kind == "GATHER" then self:AddStat("GATHERS") elseif task.kind == "QUEST" then self:AddStat("QUESTS") end

    if ok then
        for _, key in ipairs(self:SortedKeys(r.items)) do
            local n = r.items[key]
            self:AddItem(key, n)
            rep.items[key] = (rep.items[key] or 0) + n
            if task.kind == "GATHER" then self:AddStat("ITEMS_GATHERED", n) end
        end
        if r.rare and self:Chance(r.rare.chance) then
            self:AddItem(r.rare.item, 1)
            rep.items[r.rare.item] = (rep.items[r.rare.item] or 0) + 1
            rep.lines[#rep.lines + 1] = "Rare find: " .. itemName(r.rare.item) .. "."
        end
        local g = r.gear
        if g then
            for _ = 1, (g.n or 1) do
                if self:Chance(g.chance or 0) then
                    local gear = self:RollGear(o.tier or 1, g.ilvl or o.ilvl or 1, g.quality or 2)
                    self:AddGear(gear)
                    rep.gear[#rep.gear + 1] = gear
                end
            end
        end
        if r.mount and r.mount.mountID and self:Chance(r.mount.chance) then
            if self:AddMount(r.mount.mountID, task.name, t) then
                rep.mounts[#rep.mounts + 1] = r.mount.mountID
                rep.lines[#rep.lines + 1] = "A mount dropped in " .. task.name .. "!"
            end
        end
        if r.pet and r.pet.speciesID and self:Chance(r.pet.chance) then
            if self:AddPet(r.pet.speciesID, task.name, t) then
                rep.pets[#rep.pets + 1] = r.pet.speciesID
                rep.lines[#rep.lines + 1] = "A pet followed you out of " .. task.name .. "."
            end
        end
        if task.kind == "GATHER" then
            for _, h in ipairs(heroes) do
                self:SkillUp(h, task.profession, SKILL_PER_GATHER + math.floor((o.duration or 0) / 1800))
            end
        elseif task.kind == "DUNGEON" or task.kind == "RAID" then
            local ins = task.instance
            db.clears[ins] = (db.clears[ins] or 0) + 1
            self:AddStat(task.kind == "RAID" and "RAIDS" or "DUNGEONS")
            self:AddStat("BOSSES", o.bosses or 1)
            if task.kind == "RAID" then
                db.raidLocks[ins] = self:WeekIndex(math.min(t, task.endAt or t))   -- the week of the kill, not of the click
                self:AddStat("RAIDS_TIER" .. (o.tier or 1))
                if (o.tier or 1) >= self:NumTiers() and not db.finalCleared then
                    db.finalCleared = true
                    rep.lines[#rep.lines + 1] = "The final raid has fallen. A New Era awaits."
                    self:Log("The final raid has fallen. A New Era awaits.", t)
                end
            end
            -- the tier gate: clearing a dungeon (or raid) of your current tier opens the next one
            local avg = 0
            for _, h in ipairs(heroes) do avg = avg + h.level end
            avg = #heroes > 0 and avg / #heroes or 0
            local gate = self:TierGateLevel(db.tier)
            if (o.tier or 1) >= db.tier and db.tier < self:NumTiers() and avg < gate then
                rep.lines[#rep.lines + 1] = string.format("The way onward stays shut: the party must average level %d.", gate)
            elseif (o.tier or 1) >= db.tier and db.tier < self:NumTiers() then
                db.tier = db.tier + 1
                self:MaxStat("MAX_TIER", db.tier)
                local name = self:Tier(db.tier).name or ("tier " .. db.tier)
                rep.lines[#rep.lines + 1] = "New lands open: " .. name .. "."
                rep.tierUp = db.tier
                self:Log("New lands open: " .. name .. ".", t)
                self:Changed("all")
            end
        end
        rep.lines[#rep.lines + 1] = string.format("%s: success.", task.name)
    else
        rep.lines[#rep.lines + 1] = string.format("%s: failed. The party limps home.", task.name)
    end
    self:Log(string.format("%s %s.", task.name, ok and "succeeded" or "failed"), t)
    self:CheckAchievements(rep, t)
    return rep
end

function Game:FinishCraft(task, t)
    local rep = self:NewReport()
    rep.tasks = 1
    rep.success = true
    rep.kind = "CRAFT"
    rep.taskName = task.name
    local def = ns.D.RECIPES and ns.D.RECIPES[task.recipe]
    if not (def and def.output) then
        -- the recipe was removed by an update: give the materials and gold back instead of nothing
        self:RefundCraft(task)
        rep.lines[1] = string.format("%s: recipe no longer exists, materials returned.", task.name or "Craft")
        self:Log(rep.lines[1], t)
        return rep
    end
    local out = def.output
    local n = task.n or 1
    if out.item then
        self:AddItem(out.item, (out.n or 1) * n)
        rep.items[out.item] = (out.n or 1) * n
    elseif out.gear then
        local tier = out.tier or def.tier or 1
        for _ = 1, n do
            local g = self:MakeGear(tier, out.gear, self:CraftIlvl(tier, out.quality or 3), out.quality or 3)
            if (out.quality or 3) >= 4 then self:AddStat("GEAR_CRAFTED_EPIC") end
            self:AddGear(g)
            rep.gear[#rep.gear + 1] = g
        end
    end
    self:AddStat("CRAFTS", n)
    rep.lines[#rep.lines + 1] = string.format("Crafted %dx %s.", n, def.name or task.name)
    self:Log(rep.lines[#rep.lines], t)
    self:CheckAchievements(rep, t)
    return rep
end

local function releaseHeroes(self, task)
    for _, id in ipairs(task.heroes or {}) do
        local h = self.db.heroes[id]
        if h and h.taskId == task.id then h.taskId = nil end
    end
end

-- internal collect at time t (no event, no ready check)
function Game:CollectAt(task, t)
    local rep
    if task.kind == "CRAFT" then
        rep = self:FinishCraft(task, t)
    elseif task.kind == "BUILD" then
        rep = self:FinishBuilding(task, t)
    else
        rep = self:ResolveMission(task, t)
    end
    self.db.tasks[task.id] = nil
    releaseHeroes(self, task)
    self:Changed("tasks")
    self:Changed("heroes")
    return rep
end

function Game:Collect(taskId)
    local now = self:Now()
    self:Update(now)
    local task = self.db.tasks[taskId]
    if not task then return nil, "No such task." end
    if now < task.endAt then return nil, "Not finished yet." end
    local rep = self:CollectAt(task, now)
    if task.repeatIt then self:RestartTask(task, now) end
    ns.Fire("REPORT", rep)
    return rep
end

function Game:CollectAll()
    local now = self:Now()
    self:Update(now)
    local merged = self:NewReport()
    local any = false
    self:Batched(function()
        for _, task in ipairs(self:GetTasks()) do
            if task.kind ~= "BUILD" and now >= task.endAt then
                self:MergeReport(merged, self:CollectAt(task, now))
                if task.repeatIt then self:RestartTask(task, now) end
                any = true
            end
        end
    end)
    if not any then return nil, "Nothing is ready." end
    ns.Fire("REPORT", merged)
    return merged
end

function Game:Cancel(taskId)
    local task = self.db.tasks[taskId]
    if not task then return false, "No such task." end
    if task.kind == "CRAFT" then
        self:RefundCraft(task)
    elseif task.kind == "BUILD" then
        self:RefundBuilding(task)
    end
    self.db.tasks[taskId] = nil
    releaseHeroes(self, task)
    self:Log(task.name .. " cancelled.")
    self:Changed("tasks")
    self:Changed("heroes")
    return true
end

----------------------------------------------------------------------------------------------------
-- catch-up
----------------------------------------------------------------------------------------------------
-- restart a finished repeat task at time t; returns the new task or nil
function Game:RestartTask(old, t)
    local heroes = heroesOf(self, old.heroes)
    if #heroes ~= #old.heroes then return nil end
    for _, h in ipairs(heroes) do if h.taskId then return nil end end
    local o = old.offer
    if not o then return nil end
    local p = self:PreviewOffer(o, heroes, t, { ignoreLock = true })
    if not p.ok then return nil end
    local task = self:StartOffer(o, heroes, t, true, p)
    task.loops = (old.loops or 0) + 1
    return task
end

function Game:Update(now)
    local db = self.db
    if not db then return end
    now = now or self:Now()
    local prevSeen = db.lastSeen or now
    if now < prevSeen then        -- clock went backwards: don't replay anything
        db.lastSeen = now
        return
    end
    self:Batched(self.CatchUp, now, prevSeen)
end

function Game:CatchUp(now, prevSeen)
    local db = self.db
    local capUntil = prevSeen + OFFLINE_CAP
    local away = db.away and db.away.report

    for _ = 1, MAX_CATCHUP_STEPS do
        -- earliest due task that resolves by itself (building, or a repeat task that may still restart)
        local due
        for _, t in pairs(db.tasks) do
            if t.endAt <= now then
                if t.repeatIt and not t.capped and t.endAt >= capUntil then
                    t.capped = true   -- finished after the offline cap: waits for the player
                end
                if t.kind == "BUILD" or (t.repeatIt and not t.capped) then
                    if not due or t.endAt < due.endAt or (t.endAt == due.endAt and t.id < due.id) then due = t end
                end
            end
        end
        if not due then break end
        local t = due.endAt
        self:AccrueStorage(t)
        self:ExpireBuffs(t)
        local rep = self:CollectAt(due, t)
        if away then self:MergeReport(away, rep) end
        if due.kind ~= "BUILD" then
            local nxt = self:RestartTask(due, t)
            if not nxt and away then
                away.lines[#away.lines + 1] = due.name .. " stopped repeating."
            end
        end
    end

    self:AccrueStorage(now)
    self:ExpireBuffs(now)
    self:IdleTraining(math.min(now, capUntil) - prevSeen)
    self:InnState(now)
    db.lastSeen = now
end

-- Training Grounds: idle recruits earn levels[n].idleXP per hour (offline time counts up to the cap)
function Game:IdleTraining(dt)
    local lv = self:BuildingLevelDef("TRAINING_GROUNDS")
    local rate = lv and lv.idleXP
    if not rate or rate <= 0 or dt <= 0 then return end
    local db = self.db
    db.idleAcc = (db.idleAcc or 0) + dt
    if db.idleAcc < IDLE_XP_STEP then return end
    local xp = rate * db.idleAcc / 3600
    db.idleAcc = 0
    for _, h in pairs(db.heroes) do
        if not h.taskId then self:GiveXP(h, xp) end
    end
    self:Changed("heroes")
end

function Game:Welcome()
    local now = self:Now()
    self:Update(now)
    local s = self.session
    if not s or s.welcomed then return nil end
    s.welcomed = true
    local away = self.db.away
    if not away then return nil end
    local secs = s.start - (away.since or s.start)
    if secs < WELCOME_MIN_AWAY then return nil end
    local rep = away.report
    rep.away = secs
    rep.since = away.since
    rep.welcome = true
    rep.ready = self:ReadyCount(now)
    table.insert(rep.lines, 1, string.format("You were away for %s.", U.Duration(secs)))
    if secs > OFFLINE_CAP then
        table.insert(rep.lines, 2, string.format("Repeating tasks stop %s after you leave.", U.Duration(OFFLINE_CAP)))
    end
    self.db.away = { since = now, report = self:NewReport() }
    return rep
end

function Game:OfflineCap() return OFFLINE_CAP end
