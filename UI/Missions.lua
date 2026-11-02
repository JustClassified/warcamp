-- Warcamp: the Missions tab (gathering + quests).
-- Left: zones by tier (locked ones greyed, reason in the tooltip).
-- Right top: the mission-table "encounter" for the selected offer: enemy model, threats, rewards | party, chance, Start.
-- Right bottom: the zone's offer board, split into Gathering (one row per node type) and Quests.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D
local floor = math.floor

local ZONE_W = 200
local RX = ZONE_W + 10           -- right column x
local ENC_H = 246                -- encounter area height
local GATHER_W = 300
local PARTY_X = 446              -- party column inside the encounter
local REWARD_BUTTONS = 7

local PROF_ICON = {
    MINING = "Interface\\Icons\\Trade_Mining", HERBALISM = "Interface\\Icons\\Trade_Herbalism",
    SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", FISHING = "Interface\\Icons\\Trade_Fishing",
}
local QUEST_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local REPEATABLE = { GATHER = true, QUEST = true, DUNGEON = true }
-- Warlords mission page stage art (Blizzard_GarrisonMissionUI.lua / .xml: GarrisonMissionStage_SetBack)
local STAGES = { "_GarrMissionLocation-FrostfireRidge-Back", "_GarrMissionLocation-ShadowmoonValley-Back", "_GarrMissionLocation-TannanJungle-Back" }

local P = { repeatOn = false }
UI._missions = P   -- for the headless smoke test

local function Cap(s) return s and (s:sub(1, 1) .. s:sub(2):lower()) or "" end
local function Pct(x) return string.format("%d%%", floor((x or 0) * 100 + 0.5)) end
local function Pct1(x)
    x = (x or 0) * 100
    if x < 10 then return string.format("%.1f%%", x) end
    return string.format("%d%%", floor(x + 0.5))
end

------------------------------------------------------------------------
-- small local widgets / helpers
------------------------------------------------------------------------

local function Check(parent, label, onClick, tip)
    local ok, c = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok or not c then c = CreateFrame("CheckButton", nil, parent) end
    c:SetSize(22, 22)
    c.Label = Kit.Text(c, "GameFontHighlightSmall")
    c.Label:SetPoint("LEFT", c, "RIGHT", 1, 1)
    c.Label:SetText(label or "")
    c.on = false
    c:SetMotionScriptsWhileDisabled(true)
    c:SetScript("OnClick", function(self)
        self.on = not self.on
        self:SetChecked(self.on)
        if onClick then onClick(self.on) end
    end)
    c:SetScript("OnEnter", function(self)
        local t = (not self:IsEnabled() and self.reason) or tip
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(t, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function c:SetOn(v) self.on = v and true or false; self:SetChecked(self.on) end
    function c:SetUsable(v, reason)
        self:SetEnabled(v and true or false)
        self.reason = (not v) and reason or nil
        if v then self.Label:SetTextColor(1, 1, 1) else self.Label:SetTextColor(0.5, 0.5, 0.5) end
    end
    return c
end

local function MountInfo(id)
    if id and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local r = { pcall(C_MountJournal.GetMountInfoByID, id) }
        if r[1] and r[2] then return r[2], r[4] end
    end
    return "Mount " .. tostring(id), 134400
end

local function PetInfo(id)
    if id and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name, icon = pcall(C_PetJournal.GetPetInfoBySpeciesID, id)
        if ok and name then return name, icon end
    end
    return "Pet " .. tostring(id), 134400
end

local function GearIcon(tier)
    local GB = D.GEAR_BASES and D.GEAR_BASES[tier or 1]
    local list = GB and (GB.CHEST or GB.WEAPON)
    local b = list and list[1]
    return b and ns.ItemIcon(b.itemID, 132644) or 132644
end

local function SortedItemKeys(items)
    local keys = {}
    for k in pairs(items or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ia, ib = Kit.Item(a), Kit.Item(b)
        local qa, qb = ia and ia.quality or 0, ib and ib.quality or 0
        if qa ~= qb then return qa > qb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- fill a row of ItemButtons from a rewards table (offer.rewards or preview.rewards)
local function FillRewards(buttons, r, tier)
    r = r or {}
    local n = 0
    local function put(fn)
        n = n + 1
        local b = buttons[n]
        if b then fn(b); b:Show() end
    end
    for _, k in ipairs(SortedItemKeys(r.items)) do put(function(b) b:SetItemKey(k, r.items[k]) end) end
    if r.gear and (r.gear.chance or 0) > 0 then
        local g = r.gear
        put(function(b)
            b:SetItem({ icon = GearIcon(tier), quality = g.quality or 2, count = (g.n or 1) > 1 and g.n or nil,
                name = string.format("%s gear", D.QUALITY and D.QUALITY[g.quality or 2] or ""),
                lines = { { "Item level about " .. (g.ilvl or 0), 1, 0.82, 0 },
                          { (g.n or 1) > 1 and (g.n .. " pieces, random slots") or "Random slot", 1, 1, 1 },
                          { "Chance " .. Pct(g.chance), 0.6, 0.8, 1 },
                          { "May roll one quality higher", 0.6, 0.6, 0.6 } } })
        end)
    end
    if r.rare and r.rare.item then
        put(function(b) b:SetItemKey(r.rare.item, nil, { { "Chance " .. Pct(r.rare.chance), 0.6, 0.8, 1 } }) end)
    end
    if r.mount and r.mount.mountID then
        local name, icon = MountInfo(r.mount.mountID)
        put(function(b) b:SetItem({ name = name, icon = icon, quality = 4, lines = { { "Mount", 1, 1, 1 }, { "Chance " .. Pct1(r.mount.chance), 0.6, 0.8, 1 } } }) end)
    end
    if r.pet and r.pet.speciesID then
        local name, icon = PetInfo(r.pet.speciesID)
        put(function(b) b:SetItem({ name = name, icon = icon, quality = 3, lines = { { "Battle pet", 1, 1, 1 }, { "Chance " .. Pct1(r.pet.chance), 0.6, 0.8, 1 } } }) end)
    end
    for i = n + 1, #buttons do buttons[i]:Clear(); buttons[i]:Hide() end
    return n
end

-- a short reward text for a board row
local function RewardSummary(o)
    local r = o.rewards or {}
    if o.kind == "GATHER" then
        for _, k in ipairs(SortedItemKeys(r.items)) do
            local it = Kit.Item(k)
            return string.format("%d %s", r.items[k], Kit.IconMarkup(it and ns.ItemIcon(it.itemID, it.icon), 14))
        end
        return ""
    end
    local s = Kit.Coin(r.gold or 0, true)
    if r.gear and (r.gear.chance or 0) > 0 then s = s .. " " .. Kit.IconMarkup(GearIcon(o.tier), 13) end
    return s
end

local function OfferIcon(o)
    if o.kind == "GATHER" then return PROF_ICON[o.profession] or PROF_ICON.MINING end
    return QUEST_ICON
end

------------------------------------------------------------------------
-- zones
------------------------------------------------------------------------

local function ZoneRows()
    local zones = Kit.Call("GetZones") or {}
    local byTier, tiers = {}, {}
    for _, z in ipairs(zones) do
        local t = z.zone.tier or 1
        if not byTier[t] then byTier[t] = {}; tiers[#tiers + 1] = t end
        table.insert(byTier[t], z)
    end
    table.sort(tiers)
    local rows = {}
    for _, t in ipairs(tiers) do
        local list = byTier[t]
        table.sort(list, function(a, b)
            if (a.zone.level or 0) ~= (b.zone.level or 0) then return (a.zone.level or 0) < (b.zone.level or 0) end
            return tostring(a.zone.key) < tostring(b.zone.key)
        end)
        local tier = D.TIERS and D.TIERS[t] or {}
        local lr = tier.level or { 1, 1 }
        rows[#rows + 1] = { header = true, key = "H:" .. t, tier = t, text = tier.name or ("Tier " .. t), range = lr, locked = not list[1].unlocked }
        for i, z in ipairs(list) do
            local lo = z.zone.level or lr[1]
            local nxt = list[i + 1]
            local hi = nxt and math.max(lo, (nxt.zone.level or lo) - 1) or math.max(lo, lr[2])
            rows[#rows + 1] = { key = z.zone.key, zone = z.zone, unlocked = z.unlocked, reason = z.reason, lo = lo, hi = hi }
        end
    end
    return rows
end

local function DefaultZone(rows)
    local best = 0
    for _, h in ipairs(Kit.Call("GetHeroes") or {}) do best = math.max(best, h.level or 1) end
    local pick, first
    for _, r in ipairs(rows) do
        if not r.header and r.unlocked then
            first = first or r.key
            if (r.lo or 1) <= best then pick = r.key end
        end
    end
    return pick or first or (rows[2] and rows[2].key)
end

local function BuildZoneRow(row)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 6, 0)
    row.Name:SetWidth(120)
    row.Lock = row:CreateTexture(nil, "ARTWORK")
    row.Lock:SetSize(12, 14)
    row.Lock:SetPoint("RIGHT", -2, 0)
    -- LFGList.xml: the lock on unavailable activities
    if not Kit.Atlas(row.Lock, "groupfinder-icon-lock") then Kit.Atlas(row.Lock, nil, "Interface\\PetBattles\\PetBattle-LockIcon") end
    row.Level = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Level:SetPoint("RIGHT", row.Lock, "LEFT", -2, 0)
    row.Level:SetWidth(46)
end

local function UpdateZoneRow(row, d)
    if d.header then
        row.Name:SetPoint("LEFT", 2, 0)
        row.Name:SetFontObject("GameFontNormalSmall")
        row.Name:SetText(d.text)
        row.Name:SetTextColor(1, 0.82, 0)
        row.Level:SetText(string.format("%d-%d", d.range[1] or 1, d.range[2] or 1))
        row.Level:SetTextColor(0.6, 0.5, 0.2)
        row.Lock:SetShown(d.locked)
        row.Stripe:Hide()
        return
    end
    row.Name:SetPoint("LEFT", 12, 0)
    row.Name:SetFontObject("GameFontHighlightSmall")
    row.Name:SetText(d.zone.name or d.key)
    row.Level:SetText(d.lo == d.hi and tostring(d.lo) or string.format("%d-%d", d.lo, d.hi))
    if d.unlocked then
        row.Name:SetTextColor(1, 1, 1)
        row.Level:SetTextColor(0.8, 0.8, 0.8)
    else
        row.Name:SetTextColor(0.45, 0.45, 0.45)
        row.Level:SetTextColor(0.4, 0.4, 0.4)
    end
    row.Lock:SetShown(not d.unlocked)
end

local function ZoneTooltip(tt, row, d)
    if d.header then
        tt:SetText(d.text, 1, 0.82, 0)
        tt:AddLine(string.format("Levels %d-%d", d.range[1] or 1, d.range[2] or 1), 1, 1, 1)
        return
    end
    local z = d.zone
    tt:SetText(z.name or d.key, 1, 0.82, 0)
    local tier = D.TIERS and D.TIERS[z.tier or 1]
    tt:AddLine(string.format("%s  -  level %s", tier and tier.name or "", d.lo == d.hi and d.lo or (d.lo .. "-" .. d.hi)), 1, 1, 1)
    local g = {}
    for _, p in ipairs(z.gather or {}) do g[#g + 1] = Kit.IconMarkup(PROF_ICON[p], 13) .. " " .. Cap(p) end
    if #g > 0 then tt:AddLine(table.concat(g, "  "), 0.8, 0.8, 0.8, true) end
    local mobs = {}
    for _, m in ipairs(z.mobs or {}) do mobs[#mobs + 1] = m.name end
    if #mobs > 0 then tt:AddLine("Enemies: " .. table.concat(mobs, ", "), 0.7, 0.7, 0.7, true) end
    if not d.unlocked and d.reason then tt:AddLine(" "); tt:AddLine(d.reason, 1, 0.3, 0.3, true) end
end

------------------------------------------------------------------------
-- offer board
------------------------------------------------------------------------

local function BoardEntries(zoneKey)
    local tasks = Kit.Call("GetTasks") or {}
    local byOffer, used = {}, {}
    for _, t in ipairs(tasks) do if t.offerKey then byOffer[t.offerKey] = byOffer[t.offerKey] or t end end
    local gather, quest = {}, {}
    for _, o in ipairs(Kit.Call("GetBoard", "GATHER", zoneKey) or {}) do
        local t = byOffer[o.key]
        if t then used[t.id] = true end
        gather[#gather + 1] = { key = o.key, offer = o, task = t }
    end
    for _, o in ipairs(Kit.Call("GetBoard", "QUEST", zoneKey) or {}) do
        quest[#quest + 1] = { key = o.key, offer = o, task = byOffer[o.key] }
    end
    -- running tasks from this zone whose offer left the board (taken quests, older gather windows)
    for _, t in ipairs(tasks) do
        if t.zone == zoneKey and not used[t.id] and (t.kind == "GATHER" or t.kind == "QUEST") and t.offer then
            local e = { key = "T:" .. tostring(t.id), offer = t.offer, task = t, inProgress = true }
            if t.kind == "GATHER" then gather[#gather + 1] = e else quest[#quest + 1] = e end
        end
    end
    return gather, quest
end

local function BuildOfferRow(row, list)
    local quest = list.wcKind == "QUEST"
    row.IconBG = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.IconBG:SetSize(18, 18)
    row.IconBG:SetPoint("LEFT", 2, 0)
    -- the garrison mission list icon backdrop (Blizzard_GarrisonMissionUI.xml: IconBG)
    if not Kit.Atlas(row.IconBG, "Garr_MissionList-IconBG") then row.IconBG:SetColorTexture(0, 0, 0, 0.5) end
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("CENTER", row.IconBG, "CENTER")
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Busy = row:CreateTexture(nil, "OVERLAY")
    row.Busy:SetSize(10, 10)
    row.Busy:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 3, -3)
    -- LFGList.xml: the "waiting" dot
    if not Kit.Atlas(row.Busy, "groupfinder-waitdot") then row.Busy:SetColorTexture(0.4, 0.7, 1, 1) end
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 24, 0)
    row.Name:SetWidth(quest and 150 or 104)
    local x = quest and 178 or 130
    if quest then
        row.party = Kit.Text(row, "GameFontDisableSmall", "RIGHT")
        row.party:SetPoint("LEFT", x, 0)
        row.party:SetWidth(34)
        x = x + 36
    end
    row.Level = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Level:SetPoint("LEFT", x, 0)
    row.Level:SetWidth(26)
    row.Dur = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Dur:SetPoint("LEFT", x + 28, 0)
    row.Dur:SetWidth(56)
    row.Reward = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Reward:SetPoint("RIGHT", -2, 0)
    row.Reward:SetPoint("LEFT", row.Dur, "RIGHT", 2, 0)
end

local function UpdateOfferRow(row, e, _, list)
    local o, now = e.offer, time()
    row.Icon:SetTexture(OfferIcon(o))
    row.Icon:SetDesaturated(o.locked and not e.inProgress)
    row.Name:SetText(o.kind == "GATHER" and Cap(o.profession) or (o.name or "?"))
    if row.party then row.party:SetText((o.minHeroes or 1) == (o.maxHeroes or 1) and ("x" .. (o.maxHeroes or 1)) or ("x" .. (o.minHeroes or 1) .. "-" .. (o.maxHeroes or 1))) end
    row.Level:SetText(tostring(o.level or ""))
    row.Busy:SetShown(e.task ~= nil)
    if e.task then
        local ready = now >= (e.task.endAt or 0)
        row.Dur:SetText(ready and "|cff40ff40Ready|r" or ("|cff66bbff" .. U.Duration(e.task.endAt - now) .. "|r"))
    else
        row.Dur:SetText(U.Duration(o.duration or 0))
    end
    if e.inProgress then
        row.Name:SetTextColor(0.4, 0.73, 1)
        row.Reward:SetText("|cff66bbffIn progress|r")
    else
        if o.locked then row.Name:SetTextColor(0.5, 0.5, 0.5) else row.Name:SetTextColor(1, 1, 1) end
        row.Reward:SetText(RewardSummary(o))
    end
end

local function OfferTooltip(tt, row, e)
    local o = e.offer
    tt:SetText(o.kind == "GATHER" and (o.name or Cap(o.profession)) or (o.name or "?"), 1, 0.82, 0)
    tt:AddLine(string.format("Level %d  -  item level %d  -  %s", o.level or 1, o.ilvl or 0, U.Duration(o.duration or 0)), 1, 1, 1)
    if o.desc and o.desc ~= "" then tt:AddLine(o.desc, 0.8, 0.8, 0.8, true) end
    if (o.maxHeroes or 1) > 1 then tt:AddLine(string.format("Heroes: %d-%d", o.minHeroes or 1, o.maxHeroes), 0.8, 0.8, 0.8) end
    local th = {}
    for _, k in ipairs(o.threats or {}) do
        local t = D.THREATS and D.THREATS[k]
        th[#th + 1] = Kit.IconMarkup(t and t.icon, 13) .. " " .. (t and t.name or k)
    end
    if #th > 0 then tt:AddLine("Threats: " .. table.concat(th, "  "), 1, 0.5, 0.4, true) end
    local r = o.rewards or {}
    tt:AddLine(" ")
    if (r.gold or 0) > 0 then tt:AddDoubleLine("Gold", Kit.Coin(r.gold), 1, 1, 1, 1, 1, 1) end
    if (r.xp or 0) > 0 then tt:AddDoubleLine("Experience", tostring(r.xp), 1, 1, 1, 0.6, 0.6, 1) end
    for _, k in ipairs(SortedItemKeys(r.items)) do
        local it = Kit.Item(k)
        tt:AddDoubleLine(Kit.IconMarkup(it and ns.ItemIcon(it.itemID, it.icon), 13) .. " " .. (it and it.name or k), tostring(r.items[k]), 1, 1, 1, 1, 1, 1)
    end
    if r.gear and (r.gear.chance or 0) > 0 then tt:AddDoubleLine("Gear (ilvl " .. (r.gear.ilvl or 0) .. ")", Pct(r.gear.chance), 1, 1, 1, 0.6, 0.8, 1) end
    if e.task then
        tt:AddLine(" ")
        local names = {}
        for _, id in ipairs(e.task.heroes or {}) do local h = Kit.Hero(id); if h then names[#names + 1] = Kit.HeroName(h) end end
        tt:AddLine("In progress: " .. table.concat(names, ", "), 0.4, 0.73, 1, true)
        local now = time()
        if now >= e.task.endAt then tt:AddLine("Ready to collect", 0.3, 1, 0.3)
        else tt:AddLine("Back in " .. U.Duration(e.task.endAt - now), 0.4, 0.73, 1) end
    end
    if o.locked and o.lockReason and not e.inProgress then tt:AddLine(o.lockReason, 1, 0.3, 0.3, true) end
end

------------------------------------------------------------------------
-- encounter (selected offer)
------------------------------------------------------------------------

local function CurrentEntry() return P.offerKey and P.byKey and P.byKey[P.offerKey] end

local function UpdatePreview()
    local e = CurrentEntry()
    local E = P.enc
    if not e then return end
    local o = e.offer
    local ids = P.picker:GetHeroes()
    local p
    if not e.inProgress then p = Kit.Call("Preview", o.key, ids) end
    p = p or {}
    E.threats:SetThreats(o.threats or {}, p.countered or {})
    E.noThreats:SetShown(#(o.threats or {}) == 0)
    local r = (p.rewards and #ids > 0) and p.rewards or o.rewards
    FillRewards(E.rewards, r, o.tier)
    E.gold:SetCopper((r and r.gold) or 0, true)
    local xp = (#ids > 0 and p.xpEach) or (o.rewards and o.rewards.xp) or 0
    E.xp:SetText(string.format("|cff9a9aff+%d XP|r%s", xp, (#ids > 1) and " each" or ""))

    local lines = {}
    local chance
    if e.inProgress then
        chance = e.task.chance
        lines[1] = { "Already out on this one.", 0.4, 0.73, 1 }
    else
        if #ids > 0 then chance = p.chance end
        if p.reason then lines[#lines + 1] = { p.reason, 1, 0.35, 0.3 } end
        for _, n in ipairs(p.notes or {}) do lines[#lines + 1] = { n, 0.85, 0.85, 0.85 } end
        if #ids == 0 and not p.reason then lines[#lines + 1] = { "Pick heroes or use Auto-fill.", 0.6, 0.6, 0.6 } end
    end
    E.chance:SetChance(chance)
    local dur = (e.inProgress and e.task and e.task.endAt and e.task.startAt and (e.task.endAt - e.task.startAt)) or p.duration or o.duration or 0
    E.time:SetText("Time " .. U.Duration(dur))
    for i, fs in ipairs(E.notes) do
        local l = lines[i]
        if l then fs:SetText(l[1]); fs:SetTextColor(l[2], l[3], l[4]) else fs:SetText("") end
    end
    if p.power and p.offerPower and #ids > 0 then
        local good = p.power >= p.offerPower
        E.power:SetText(string.format("Party power |cff%s%d|r vs %d", good and "40ff40" or "ff6040", p.power, p.offerPower))
    else
        E.power:SetText(string.format("Enemy power %d", Kit.Call("OfferPower", o) or 0))
    end

    -- start / repeat
    local canRepeat = REPEATABLE[o.kind] and not e.inProgress
    E.repeatBox:SetUsable(canRepeat, e.inProgress and "Already running" or "This cannot repeat")
    E.repeatBox:SetOn(canRepeat and P.repeatOn)
    if e.inProgress then
        E.start:SetText("Running")
        local now = time()
        E.start:SetEnabledTip(false, now >= e.task.endAt and "Ready: collect it on the Camp tab" or ("Back in " .. U.Duration(e.task.endAt - now)))
        E.auto:SetEnabledTip(false, "Already running")
    else
        E.start:SetText("Start")
        local reason = p.reason or (#ids == 0 and "Choose at least one hero") or nil
        E.start:SetEnabledTip(p.ok and true or false, reason or o.lockReason)
        E.start:SetTip(string.format("Send them out for %s", U.Duration(p.duration or o.duration or 0)))
        E.auto:SetEnabledTip(not o.locked, o.lockReason)
    end
end

local function ShowOffer()
    local E = P.enc
    local e = CurrentEntry()
    E.content:SetShown(e ~= nil)
    E.empty:SetShown(e == nil)
    if not e then return end
    local o = e.offer
    local zone = Kit.Call("ZoneByKey", o.zone)
    E.model:SetDisplay(o.display, OfferIcon(o))
    E.model:SetCaption(zone and zone.name or "")
    E.name:SetText(o.name or "?")
    if o.locked and not e.inProgress then E.name:SetTextColor(0.6, 0.6, 0.6) else E.name:SetTextColor(1, 0.82, 0) end
    E.desc:SetText(o.desc or "")
    local heroes = (o.minHeroes or 1) == (o.maxHeroes or 1) and tostring(o.maxHeroes or 1) or ((o.minHeroes or 1) .. "-" .. (o.maxHeroes or 1))
    E.stats:SetText(string.format("Level |cffffffff%d|r   Item level |cffffffff%d|r   %s   |cffffffff%s|r hero%s",
        o.level or 1, o.ilvl or 0, U.Duration(o.duration or 0), heroes, (o.maxHeroes or 1) == 1 and "" or "es"))
    E.kind:SetText(o.kind == "GATHER" and (Kit.IconMarkup(PROF_ICON[o.profession], 14) .. " Gathering") or (Kit.IconMarkup(QUEST_ICON, 14) .. " Quest"))

    local n = math.max(1, math.min(5, o.maxHeroes or 1))
    if P.picker.n ~= n then P.picker:SetSlots(n) end
    if e.inProgress then
        P.picker:SetHeroes(e.task.heroes or {})
        P.picker:SetEnabled(false)
        P.prefillFor = nil
    else
        P.picker:SetEnabled(not o.locked)
        if P.prefillFor ~= e.key then
            P.prefillFor = e.key
            P.picker:SetHeroes(o.locked and {} or (Kit.Call("Suggest", o.key) or {}))
        else
            -- keep the chosen party, minus anyone who left on another task meanwhile
            local keep, changed = {}, false
            for _, id in ipairs(P.picker:GetHeroes()) do
                local h = Kit.Hero(id)
                if h and not h.taskId then keep[#keep + 1] = id else changed = true end
            end
            if changed then P.picker:SetHeroes(keep) end
        end
    end
    UpdatePreview()
end

local function StartSelected()
    local e = CurrentEntry()
    if not e or e.inProgress then return end
    local o = e.offer
    local task = Kit.Do("Start", o.key, P.picker:GetHeroes(), P.repeatOn and REPEATABLE[o.kind] or false)
    if task then
        if UI.Status then UI.Status("Sent out: " .. (o.name or "?") .. (type(task) == "table" and task.repeatIt and " (repeating)" or ""), 0.4, 1, 0.4) end
        if o.kind == "QUEST" and type(task) == "table" and task.id then P.offerKey = "T:" .. tostring(task.id) end
        P.prefillFor = nil
    end
end

local function AutoFill()
    local e = CurrentEntry()
    if not e or e.inProgress then return end
    local ids = Kit.Call("Suggest", e.offer.key) or {}
    if #ids == 0 and UI.Status then UI.Status("No idle heroes", 1, 0.3, 0.3) end
    P.picker:SetHeroes(ids)
    UpdatePreview()
end

local function SelectOffer(key)
    P.offerKey = key
    P.gather:SetSelected(key)
    P.quest:SetSelected(key)
    ShowOffer()
end

------------------------------------------------------------------------
-- build
------------------------------------------------------------------------

local function BuildEncounter(parent)
    local E = {}
    local f = Kit.Inset(parent)
    f:SetPoint("TOPLEFT", RX, 0)
    f:SetPoint("TOPRIGHT", 0, 0)
    f:SetHeight(ENC_H)
    E.frame = f
    E.stage = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    E.stage:SetPoint("TOPLEFT", 3, -3)
    E.stage:SetPoint("BOTTOMRIGHT", -3, 3)
    E.shade = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    E.shade:SetPoint("TOPLEFT", 3, -3)
    E.shade:SetPoint("BOTTOMRIGHT", -3, 3)
    E.shade:SetColorTexture(0, 0, 0, 0.55)

    E.empty = Kit.Text(f, "GameFontDisable", "CENTER")
    E.empty:SetPoint("CENTER")
    E.empty:SetText("Choose a mission from the board below")

    local c = CreateFrame("Frame", nil, f)
    c:SetAllPoints()
    E.content = c

    E.model = Kit.ModelView(c, 170, ENC_H - 10, { caption = true, bg = false, facing = -0.4 })
    E.model:SetPoint("LEFT", 5, 0)

    local X = 182
    E.name = Kit.Text(c, "GameFontNormalLarge")
    E.name:SetPoint("TOPLEFT", X, -8)
    E.name:SetWidth(PARTY_X - X - 10)
    E.kind = Kit.Text(c, "GameFontHighlightSmall", "RIGHT")
    E.kind:SetPoint("TOPRIGHT", c, "TOPLEFT", PARTY_X - 12, -11)
    E.desc = Kit.Text(c, "GameFontHighlightSmall")
    E.desc:SetPoint("TOPLEFT", X, -30)
    E.desc:SetWidth(PARTY_X - X - 12)
    E.desc:SetWordWrap(true)
    E.desc:SetHeight(26)
    E.desc:SetJustifyV("TOP")
    E.desc:SetTextColor(0.85, 0.85, 0.85)
    E.stats = Kit.Text(c, "GameFontNormalSmall")
    E.stats:SetPoint("TOPLEFT", X, -58)
    E.stats:SetWidth(PARTY_X - X - 12)

    local tl = Kit.Text(c, "GameFontNormalSmall")
    tl:SetPoint("TOPLEFT", X, -84)
    tl:SetText("Threats")
    E.threats = Kit.ThreatIcons(c, 22, 6)
    E.threats:SetPoint("TOPLEFT", X + 52, -78)
    E.noThreats = Kit.Text(c, "GameFontDisableSmall")
    E.noThreats:SetPoint("TOPLEFT", X + 52, -84)
    E.noThreats:SetText("None")

    local rl = Kit.Text(c, "GameFontNormalSmall")
    rl:SetPoint("TOPLEFT", X, -112)
    rl:SetText("Rewards")
    E.rewards = {}
    for i = 1, REWARD_BUTTONS do
        local b = Kit.ItemButton(c, 30)
        b:SetPoint("TOPLEFT", X + (i - 1) * 34, -128)
        b:Hide()
        E.rewards[i] = b
    end
    E.gold = Kit.CoinText(c, "GameFontHighlight")
    E.gold:SetJustifyH("LEFT")
    E.gold:SetPoint("TOPLEFT", X, -166)
    E.xp = Kit.Text(c, "GameFontHighlight")
    E.xp:SetPoint("LEFT", E.gold, "RIGHT", 14, 0)
    E.power = Kit.Text(c, "GameFontHighlightSmall")
    E.power:SetPoint("TOPLEFT", X, -190)
    E.power:SetWidth(PARTY_X - X - 12)

    -- party column
    local divider = c:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", PARTY_X - 6, -8)
    divider:SetPoint("BOTTOMLEFT", PARTY_X - 6, 8)
    divider:SetWidth(1)
    divider:SetColorTexture(1, 0.82, 0, 0.2)
    E.partyHeader = Kit.Header(c, "Party", 240)
    E.partyHeader:SetPoint("TOPLEFT", PARTY_X, -6)
    E.partyHeader:SetPoint("RIGHT", -8, 0)
    P.picker = Kit.PartyPicker(c, { slots = 3, size = 32, spacing = 5, onChange = function() UpdatePreview() end,
        label = function(h)
            local e = CurrentEntry()
            local o = e and e.offer
            if o and o.kind == "GATHER" and o.profession then
                return string.format("|cff9d9d9d%s %d|r", Cap(o.profession):sub(1, 4), h.skills and h.skills[o.profession] or 0)
            end
            return ""
        end })
    P.picker:SetPoint("TOPLEFT", PARTY_X, -30)
    E.auto = Kit.Button(c, "Auto-fill", 72, 20, AutoFill, "Fill the party with the best idle heroes")
    E.auto:SetPoint("TOPRIGHT", -8, -36)
    local cl = Kit.Text(c, "GameFontNormalSmall")
    cl:SetPoint("TOPLEFT", PARTY_X, -76)
    cl:SetText("Success")
    E.chance = Kit.ChanceMeter(c, 120, 16)
    E.chance:SetPoint("TOPLEFT", PARTY_X + 50, -73)
    E.time = Kit.Text(c, "GameFontHighlightSmall", "RIGHT")
    E.time:SetPoint("TOPRIGHT", -10, -76)
    E.time:SetWidth(80)
    E.notes = {}
    for i = 1, 8 do
        local fs = Kit.Text(c, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", PARTY_X, -96 - (i - 1) * 13)
        fs:SetPoint("RIGHT", -8, 0)
        E.notes[i] = fs
    end
    E.repeatBox = Check(c, "Repeat", function(on) P.repeatOn = on end,
        "Start again by itself when collected (also while you are away, up to 24 h)")
    E.repeatBox:SetPoint("BOTTOMLEFT", PARTY_X - 2, 6)
    E.start = Kit.Button(c, "Start", 110, 24, StartSelected)
    E.start:SetPoint("BOTTOMRIGHT", -8, 8)
    P.enc = E
end

local function Build(panel)
    P.zoneHeader = Kit.Header(panel, "Zones", ZONE_W)
    P.zoneHeader:SetPoint("TOPLEFT", 0, 0)
    P.zones = Kit.List(panel, {
        rowHeight = 18, selectable = true, key = function(d) return d.key end,
        build = BuildZoneRow, update = UpdateZoneRow, tooltip = ZoneTooltip,
        onClick = function(row, d, button, list)
            if d.header then list:SetSelected(P.zoneKey); return end
            if d.key ~= P.zoneKey then
                P.zoneKey = d.key
                P.offerKey = nil
                UI.Refresh()
            end
        end,
    })
    P.zones:SetPoint("TOPLEFT", 0, -22)
    P.zones:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", ZONE_W, 0)

    BuildEncounter(panel)

    local BY = -(ENC_H + 6)
    P.gatherHeader = Kit.Header(panel, "Gathering", GATHER_W)
    P.gatherHeader:SetPoint("TOPLEFT", RX, BY)
    P.gather = Kit.List(panel, { rowHeight = 20, selectable = true, key = function(e) return e.key end,
        build = BuildOfferRow, update = UpdateOfferRow, tooltip = OfferTooltip,
        onClick = function(row, e) SelectOffer(e.key) end })
    P.gather.wcKind = "GATHER"
    P.gather:SetPoint("TOPLEFT", RX, BY - 22)
    P.gather:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", RX + GATHER_W, 0)
    P.gatherEmpty = Kit.Text(panel, "GameFontDisableSmall", "CENTER")
    P.gatherEmpty:SetPoint("TOP", P.gather, "TOP", 0, -20)
    P.gatherEmpty:SetText("No nodes here")

    P.questHeader = Kit.Header(panel, "Quests", 396)
    P.questHeader:SetPoint("TOPLEFT", RX + GATHER_W + 10, BY)
    P.questHeader:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    P.quest = Kit.List(panel, { rowHeight = 20, selectable = true, key = function(e) return e.key end,
        build = BuildOfferRow, update = UpdateOfferRow, tooltip = OfferTooltip,
        onClick = function(row, e) SelectOffer(e.key) end })
    P.quest.wcKind = "QUEST"
    P.quest:SetPoint("TOPLEFT", RX + GATHER_W + 10, BY - 22)
    P.quest:SetPoint("BOTTOMRIGHT", 0, 0)
    P.questEmpty = Kit.Text(panel, "GameFontDisableSmall", "CENTER")
    P.questEmpty:SetPoint("TOP", P.quest, "TOP", 0, -20)
    P.questEmpty:SetText("Every quest here is taken. New ones soon.")
end

local function BoardTimers(now)
    now = now or time()
    for _, kind in ipairs({ "GATHER", "QUEST" }) do
        local b = P.zoneKey and Kit.Call("ZoneBoard", kind, P.zoneKey, now)
        local hdr = kind == "GATHER" and P.gatherHeader or P.questHeader
        hdr.right:SetText(b and b.refreshAt and ("|cff9d9d9dNew in " .. U.Duration(b.refreshAt - now) .. "|r") or "")
    end
end

local function Refresh(panel)
    local rows = ZoneRows()
    local found
    for _, r in ipairs(rows) do if not r.header and r.key == P.zoneKey then found = r end end
    if not found then P.zoneKey = DefaultZone(rows); P.offerKey = nil end
    for _, r in ipairs(rows) do if r.key == P.zoneKey then found = r end end
    P.zones:SetData(rows)
    P.zones:SetSelected(P.zoneKey)
    local zone = found and found.zone
    P.zoneHeader.right:SetText(zone and (D.TIERS and D.TIERS[zone.tier or 1] and D.TIERS[zone.tier or 1].name or "") or "")

    -- stage art follows the zone
    local idx = 1
    for i, r in ipairs(rows) do if r.key == P.zoneKey then idx = i end end
    if not Kit.Atlas(P.enc.stage, STAGES[(idx % #STAGES) + 1]) then
        Kit.Atlas(P.enc.stage, nil, { 0.12, 0.09, 0.06, 1 })
    else
        pcall(P.enc.stage.SetHorizTile, P.enc.stage, true)
    end

    local gather, quest = BoardEntries(P.zoneKey)
    P.byKey = {}
    for _, e in ipairs(gather) do P.byKey[e.key] = e end
    for _, e in ipairs(quest) do P.byKey[e.key] = e end
    if not (P.offerKey and P.byKey[P.offerKey]) then
        local first
        for _, e in ipairs(quest) do if not e.inProgress and not first then first = e end end
        for _, e in ipairs(gather) do if not e.inProgress and not first then first = e end end
        first = first or quest[1] or gather[1]
        P.offerKey = first and first.key or nil
    end
    P.gather:SetData(gather)
    P.quest:SetData(quest)
    P.gather:SetSelected(P.offerKey)
    P.quest:SetSelected(P.offerKey)
    P.gatherEmpty:SetShown(#gather == 0)
    P.questEmpty:SetShown(#quest == 0)
    BoardTimers()
    ShowOffer()
end

local tickN = 0
local function Tick(panel, now)
    tickN = tickN + 1
    if tickN % 2 == 0 then
        P.gather:Refresh()
        P.quest:Refresh()
        BoardTimers(now)
        local e = CurrentEntry()
        if e and e.inProgress then UpdatePreview() end
    end
end

UI.RegisterTab({ key = "MISSIONS", title = "Missions", order = 3, build = Build, refresh = Refresh, tick = Tick })
