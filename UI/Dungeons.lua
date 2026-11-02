-- Warcamp: the Dungeons & Raids tab.
-- Left: dungeons and raids grouped by tier (raids show the weekly lockout).
-- Right: the instance page over its Encounter Journal art: boss list + big boss model with threats,
-- the mount/pet chase, rewards, and the party (role hints, Auto-fill, chance, Start).
-- The Encounter Journal is read at runtime (pcall'd, cached); without it the page runs on ns.D alone.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D
local floor = math.floor

local LIST_W = 220
local RX = LIST_W + 10
local Y0 = -80                    -- top of the boss / model / side columns inside the page
local MODEL_X, MODEL_S = 206, 262
local SIDE_X = 478
local REWARD_BUTTONS = 6
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local DUNGEON_ICON = "Interface\\Icons\\INV_Sword_04"
local RAID_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"

local P = { repeatOn = false }
UI._dungeons = P   -- for the headless smoke test

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

-- rewards row (mount and pet live in the Chase box, so they are left out here)
local function FillRewards(buttons, r, tier)
    r = r or {}
    local n = 0
    local function put(fn)
        n = n + 1
        local b = buttons[n]
        if b then fn(b); b:Show() end
    end
    if r.gear and (r.gear.chance or 0) > 0 then
        local g = r.gear
        put(function(b)
            b:SetItem({ icon = GearIcon(tier), quality = g.quality or 3, count = (g.n or 1) > 1 and g.n or nil,
                name = string.format("%s gear", D.QUALITY and D.QUALITY[g.quality or 3] or ""),
                lines = { { "Item level about " .. (g.ilvl or 0), 1, 0.82, 0 },
                          { (g.n or 1) > 1 and (g.n .. " pieces, random slots") or "Random slot", 1, 1, 1 },
                          { "Chance " .. Pct(g.chance), 0.6, 0.8, 1 } } })
        end)
    end
    if r.rare and r.rare.item then
        put(function(b) b:SetItemKey(r.rare.item, nil, { { "Chance " .. Pct(r.rare.chance), 0.6, 0.8, 1 } }) end)
    end
    for _, k in ipairs(SortedItemKeys(r.items)) do put(function(b) b:SetItemKey(k, r.items[k]) end) end
    for i = n + 1, #buttons do buttons[i]:Clear(); buttons[i]:Hide() end
end

local function Collection()
    return Kit.Call("GetCollection") or { mounts = {}, pets = {} }
end

------------------------------------------------------------------------
-- Encounter Journal (runtime, pcall'd, cached per journal instance)
------------------------------------------------------------------------

local ej = {}

local function EJOpen()
    local f = EncounterJournal
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown
end

local function EJData(journalID)
    if not journalID then return nil end
    local c = ej[journalID]
    if c and c.done then return c end
    c = c or {}
    ej[journalID] = c
    if not c.triedInfo then
        c.triedInfo = true
        if type(EJ_GetInstanceInfo) == "function" then
            local ok, name, desc, bg, button1, lore, button2, areaMapID, link = pcall(EJ_GetInstanceInfo, journalID)
            if ok and name then
                c.name, c.desc, c.bg, c.lore, c.button, c.link = name, desc, bg, lore, button1, link
            end
        end
    end
    -- selecting an instance moves Blizzard's journal too: never do it while the journal is open
    if not c.bosses and type(EJ_SelectInstance) == "function" and type(EJ_GetEncounterInfoByIndex) == "function" and not EJOpen() then
        local ok = pcall(EJ_SelectInstance, journalID)
        local list = {}
        if ok then
            for i = 1, 40 do
                local ok2, name, desc, encounterID = pcall(EJ_GetEncounterInfoByIndex, i, journalID)
                if not ok2 or not encounterID or encounterID <= 0 then break end
                local b = { name = name, desc = desc, encounterID = encounterID }
                if type(EJ_GetCreatureInfo) == "function" then
                    local ok3, _, _, _, display, icon = pcall(EJ_GetCreatureInfo, 1, encounterID)
                    if ok3 then b.display = (display and display > 0) and display or nil; b.icon = icon end
                end
                list[#list + 1] = b
            end
        end
        c.bosses = list
    end
    if c.triedInfo and (c.bosses or type(EJ_SelectInstance) ~= "function") then c.done = true end
    return c
end

-- boss rows: the journal's list when it has one (threats matched from data by name, else by position),
-- else the data list
local function BossRows(ins)
    local data = ins and ins.bosses or {}
    local e = ins and EJData(ins.journalID)
    local eb = e and e.bosses
    local rows = {}
    if eb and #eb > 0 then
        local byName, matched = {}, 0
        for _, b in ipairs(data) do if b.name then byName[string.lower(b.name)] = b end end
        for i, x in ipairs(eb) do
            local d = x.name and byName[string.lower(x.name)]
            if d then matched = matched + 1 end
            rows[i] = { x = x, d = d }
        end
        if matched == 0 and #data > 0 and #data ~= #eb then
            rows = nil
        else
            for i, r in ipairs(rows) do if not r.d and #data == #eb then r.d = data[i] end end
        end
    else
        rows = nil
    end
    if not rows then
        rows = {}
        for i, d in ipairs(data) do rows[i] = { d = d } end
    end
    local out = {}
    for i, r in ipairs(rows) do
        local x, d = r.x, r.d
        out[i] = { key = i, name = (x and x.name) or (d and d.name) or ("Boss " .. i), desc = x and x.desc,
                   display = (x and x.display) or (d and d.display), icon = x and x.icon,
                   threats = d and d.threats or {}, encounterID = x and x.encounterID }
    end
    return out
end

------------------------------------------------------------------------
-- instance list
------------------------------------------------------------------------

local function InstanceRows()
    local tasks = Kit.Call("GetTasks") or {}
    local byOffer = {}
    for _, t in ipairs(tasks) do if t.offerKey then byOffer[t.offerKey] = t end end
    local byTier, tiers = {}, {}
    local function add(o)
        local t = o.tier or 1
        if not byTier[t] then byTier[t] = {}; tiers[#tiers + 1] = t end
        table.insert(byTier[t], { key = o.key, offer = o, task = byOffer[o.key] })
    end
    for _, o in ipairs(Kit.Call("GetBoard", "DUNGEON") or {}) do add(o) end
    for _, o in ipairs(Kit.Call("GetBoard", "RAID") or {}) do add(o) end
    table.sort(tiers)
    local rows = {}
    for _, t in ipairs(tiers) do
        local tier = D.TIERS and D.TIERS[t] or {}
        local unlocked = Kit.Call("TierUnlockReason", t) == nil
        rows[#rows + 1] = { header = true, key = "H:" .. t, text = tier.name or ("Tier " .. t), range = tier.level, locked = not unlocked }
        local list = byTier[t]
        table.sort(list, function(a, b)
            if a.offer.kind ~= b.offer.kind then return a.offer.kind == "DUNGEON" end
            if (a.offer.level or 0) ~= (b.offer.level or 0) then return (a.offer.level or 0) < (b.offer.level or 0) end
            return a.key < b.key
        end)
        for _, r in ipairs(list) do rows[#rows + 1] = r end
    end
    return rows
end

local function TierLocked(o)
    return o.locked and o.lockReason and not o.weeklyDone and Kit.Call("TierUnlockReason", o.tier or 1) ~= nil
end

local function DefaultInstance(rows)
    local best = 0
    for _, h in ipairs(Kit.Call("GetHeroes") or {}) do best = math.max(best, h.level or 1) end
    local pick, first
    for _, r in ipairs(rows) do
        if not r.header and r.offer.kind == "DUNGEON" and not TierLocked(r.offer) then
            first = first or r.key
            if (r.offer.level or 1) <= best + 2 then pick = r.key end
        end
    end
    return pick or first or (rows[2] and rows[2].key)
end

local function BuildInstanceRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 10, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Busy = row:CreateTexture(nil, "OVERLAY")
    row.Busy:SetSize(10, 10)
    row.Busy:SetPoint("BOTTOMRIGHT", row.Icon, 3, -3)
    if not Kit.Atlas(row.Busy, "groupfinder-waitdot") then row.Busy:SetColorTexture(0.4, 0.7, 1, 1) end
    row.Lock = row:CreateTexture(nil, "ARTWORK")
    row.Lock:SetSize(12, 14)
    row.Lock:SetPoint("RIGHT", -2, 0)
    if not Kit.Atlas(row.Lock, "groupfinder-icon-lock") then Kit.Atlas(row.Lock, nil, "Interface\\PetBattles\\PetBattle-LockIcon") end
    row.Right = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Right:SetPoint("RIGHT", row.Lock, "LEFT", -2, 0)
    row.Right:SetWidth(76)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row.Name:SetPoint("RIGHT", row.Right, "LEFT", -2, 0)
end

local function UpdateInstanceRow(row, d)
    if d.header then
        row.Icon:Hide(); row.Busy:Hide()
        row.Name:ClearAllPoints()
        row.Name:SetPoint("LEFT", 2, 0)
        row.Name:SetPoint("RIGHT", row.Right, "LEFT", -2, 0)
        row.Name:SetFontObject("GameFontNormalSmall")
        row.Name:SetText(d.text)
        row.Name:SetTextColor(1, 0.82, 0)
        row.Right:SetText(d.range and string.format("%d-%d", d.range[1] or 1, d.range[2] or 1) or "")
        row.Right:SetTextColor(0.6, 0.5, 0.2)
        row.Lock:SetShown(d.locked)
        row.Stripe:Hide()
        return
    end
    local o, now = d.offer, time()
    row.Icon:Show()
    row.Icon:SetTexture(o.kind == "RAID" and RAID_ICON or DUNGEON_ICON)
    local tierLocked = TierLocked(o)
    row.Icon:SetDesaturated(tierLocked)
    row.Name:ClearAllPoints()
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
    row.Name:SetPoint("RIGHT", row.Right, "LEFT", -2, 0)
    row.Name:SetFontObject("GameFontHighlightSmall")
    row.Name:SetText(o.name or "?")
    if tierLocked then row.Name:SetTextColor(0.45, 0.45, 0.45)
    elseif d.task then row.Name:SetTextColor(0.4, 0.73, 1)
    else row.Name:SetTextColor(1, 1, 1) end
    row.Busy:SetShown(d.task ~= nil)
    row.Lock:SetShown(tierLocked)
    if d.task then
        row.Right:SetText(now >= d.task.endAt and "|cff40ff40Ready|r" or ("|cff66bbff" .. U.Duration(d.task.endAt - now) .. "|r"))
    elseif o.kind == "RAID" then
        row.Right:SetText(o.weeklyDone and "|cff9d9d9dWeekly: done|r" or "|cff40ff40Weekly: available|r")
    else
        row.Right:SetText("Lv " .. (o.level or 1))
        row.Right:SetTextColor(tierLocked and 0.4 or 0.8, tierLocked and 0.4 or 0.8, tierLocked and 0.4 or 0.8)
    end
end

local function InstanceTooltip(tt, row, d)
    if d.header then
        tt:SetText(d.text, 1, 0.82, 0)
        if d.range then tt:AddLine(string.format("Levels %d-%d", d.range[1] or 1, d.range[2] or 1), 1, 1, 1) end
        return
    end
    local o = d.offer
    tt:SetText(o.name or "?", 1, 0.82, 0)
    tt:AddLine(string.format("%s  -  level %d  -  item level %d", o.kind == "RAID" and "Raid" or "Dungeon", o.level or 1, o.ilvl or 0), 1, 1, 1)
    tt:AddLine(string.format("%s  -  %d-%d heroes  -  %s bosses", U.Duration(o.duration or 0), o.minHeroes or 1, o.maxHeroes or 5, tostring(o.bosses or "?")), 0.8, 0.8, 0.8)
    local r = o.rewards or {}
    if r.mount then
        local name = MountInfo(r.mount.mountID)
        tt:AddDoubleLine("Mount: " .. name, Pct1(r.mount.chance), 1, 1, 1, 0.6, 0.8, 1)
    end
    if r.pet then
        local name = PetInfo(r.pet.speciesID)
        tt:AddDoubleLine("Pet: " .. name, Pct1(r.pet.chance), 1, 1, 1, 0.6, 0.8, 1)
    end
    if o.kind == "RAID" then
        tt:AddLine(o.weeklyDone and "Defeated this week" or "Weekly lockout: available", o.weeklyDone and 0.6 or 0.3, o.weeklyDone and 0.6 or 1, o.weeklyDone and 0.6 or 0.3)
    end
    if d.task then
        local now = time()
        tt:AddLine(now >= d.task.endAt and "Your party is done: collect it" or ("Your party is inside: " .. U.Duration(d.task.endAt - now) .. " left"), 0.4, 0.73, 1)
    end
    if o.locked and o.lockReason and not d.task and not o.weeklyDone then tt:AddLine(o.lockReason, 1, 0.3, 0.3, true) end
end

------------------------------------------------------------------------
-- page
------------------------------------------------------------------------

local function Current() return P.key and P.rowByKey and P.rowByKey[P.key] end
local function CurrentInstance()
    local d = Current()
    return d and d.offer and Kit.Call("InstanceByKey", d.offer.instance)
end

local function ActivePicker()
    local d = Current()
    return (d and d.offer.kind == "RAID") and P.raidPicker or P.dungeonPicker
end

local function ShowBossModel()
    local b = P.bossKey and P.bossByKey and P.bossByKey[P.bossKey]
    if not b then P.model:Clear(); P.model:SetCaption(""); return end
    P.model:SetDisplay(b.display, b.icon or SKULL)
    P.model:SetCaption(b.name)
end

local function ShowChaseModel(which)
    local d = Current()
    local r = d and d.offer.rewards or {}
    if which == "MOUNT" and r.mount then
        P.model:SetMount(r.mount.mountID)
        P.model:SetCaption((MountInfo(r.mount.mountID)))
    elseif which == "PET" and r.pet then
        P.model:SetPet(r.pet.speciesID)
        P.model:SetCaption((PetInfo(r.pet.speciesID)))
    else
        ShowBossModel()
    end
end

local function UpdateBoss()
    local b = P.bossKey and P.bossByKey and P.bossByKey[P.bossKey]
    local p = P.preview or {}
    if b then
        P.bossThreats:SetThreats(b.threats or {}, p.countered or {})
        P.bossNoThreats:SetShown(#(b.threats or {}) == 0)
        P.bossDesc:SetText(b.desc or "")
    else
        P.bossThreats:SetThreats({}, {})
        P.bossNoThreats:SetShown(false)
        P.bossDesc:SetText("")
    end
    if not P.pinned then ShowBossModel() end
end

local function RoleHints(picker, offer, ids)
    local hints = {}
    for _, role in ipairs(ROLE_ORDER) do
        for _ = 1, (offer.roles and offer.roles[role]) or 0 do hints[#hints + 1] = role end
    end
    local have = {}
    for _, id in ipairs(ids) do
        local h = Kit.Hero(id)
        if h and h.role then have[h.role] = (have[h.role] or 0) + 1 end
    end
    for i, tex in ipairs(picker.hints) do
        local role = hints[i]
        if role and i <= picker.n then
            Kit.RoleIcon(tex, role)
            tex.role = role
            if (have[role] or 0) > 0 then
                have[role] = have[role] - 1
                tex:SetVertexColor(1, 1, 1)
                tex:SetAlpha(0.45)
            else
                tex:SetVertexColor(1, 1, 1)
                tex:SetAlpha(1)
            end
            tex:Show()
        else
            tex:Hide()
        end
    end
end

local function UpdateChase(o, p)
    local r = (p and p.rewards) or o.rewards or {}
    local col = Collection()
    for _, c in ipairs(P.chase) do
        local spec = c.kind == "MOUNT" and r.mount or r.pet
        c.spec = spec
        if spec then
            local id = c.kind == "MOUNT" and spec.mountID or spec.speciesID
            local name, icon
            if c.kind == "MOUNT" then name, icon = MountInfo(id) else name, icon = PetInfo(id) end
            c.Icon:SetTexture(icon or 134400)
            c.Icon:SetDesaturated(false)
            c.Name:SetText(name)
            c.Name:SetTextColor(c.kind == "MOUNT" and 0.64 or 0, c.kind == "MOUNT" and 0.21 or 0.44, c.kind == "MOUNT" and 0.93 or 0.87)
            local have = c.kind == "MOUNT" and col.mounts and col.mounts[id] or (col.pets and col.pets[id])
            c.collected = have and true or false
            c.Check:SetShown(c.collected)
            c.Chance:SetText(c.collected and "|cff40ff40Collected|r" or Pct1(spec.chance))
            c.Pin:SetShown(P.pinned == c.kind)
            c:Show()
        else
            c.Icon:SetTexture(134400)
            c.Icon:SetDesaturated(true)
            c.Name:SetText(c.kind == "MOUNT" and "No mount here" or "No pet here")
            c.Name:SetTextColor(0.45, 0.45, 0.45)
            c.Chance:SetText("")
            c.Check:Hide()
            c.Pin:Hide()
            c:Show()
        end
    end
end

local function UpdateParty()
    local d = Current()
    if not d then return end
    local o = d.offer
    local picker = ActivePicker()
    local ids = picker:GetHeroes()
    local p
    if not d.task then p = Kit.Call("Preview", o.key, ids) end
    p = p or {}
    P.preview = p
    P.threats:SetThreats(o.threats or {}, p.countered or {})
    RoleHints(picker, o, ids)
    local r = (#ids > 0 and p.rewards) or o.rewards
    FillRewards(P.rewards, r, o.tier)
    P.gold:SetCopper(r and r.gold or 0, true)
    local xp = (#ids > 0 and p.xpEach) or (o.rewards and o.rewards.xp) or 0
    P.xp:SetText(string.format("|cff9a9aff+%d XP|r%s", xp, #ids > 1 and " each" or ""))
    UpdateChase(o, (#ids > 0) and p or nil)

    local lines, chance = {}, nil
    if d.task then
        chance = d.task.chance
        lines[1] = { "Your party is inside.", 0.4, 0.73, 1 }
    else
        if #ids > 0 then chance = p.chance end
        if p.reason then lines[#lines + 1] = { p.reason, 1, 0.35, 0.3 } end
        for _, n in ipairs(p.notes or {}) do lines[#lines + 1] = { n, 0.85, 0.85, 0.85 } end
        if p.power and p.offerPower and #ids > 0 then
            local good = p.power >= p.offerPower
            lines[#lines + 1] = { string.format("Party power %d vs %d", p.power, p.offerPower), good and 0.4 or 1, good and 1 or 0.45, good and 0.4 or 0.3 }
        end
        if #ids == 0 and not p.reason then lines[#lines + 1] = { "Pick heroes or use Auto-fill.", 0.6, 0.6, 0.6 } end
    end
    P.chance:SetChance(chance)
    local dur = (d.task and d.task.endAt and d.task.startAt and (d.task.endAt - d.task.startAt)) or p.duration or o.duration or 0
    P.time:SetText(U.Duration(dur))
    for i, fs in ipairs(P.notes) do
        local l = lines[i]
        if l then fs:SetText(l[1]); fs:SetTextColor(l[2], l[3], l[4]) else fs:SetText("") end
    end

    local canRepeat = o.kind ~= "RAID" and not d.task
    P.repeatBox:SetUsable(canRepeat, o.kind == "RAID" and "Raids are weekly: they cannot repeat" or "Already running")
    P.repeatBox:SetOn(canRepeat and P.repeatOn)
    if d.task then
        P.start:SetText("Inside")
        local now = time()
        P.start:SetEnabledTip(false, now >= d.task.endAt and "Done: collect it on the Camp tab" or ("Back in " .. U.Duration(d.task.endAt - now)))
        P.auto:SetEnabledTip(false, "Already running")
    else
        P.start:SetText(o.kind == "RAID" and "Start raid" or "Start")
        local reason = p.reason or (#ids == 0 and "Choose your party") or nil
        P.start:SetEnabledTip(p.ok and true or false, reason or o.lockReason)
        P.start:SetTip(string.format("Send them in for %s", U.Duration(p.duration or o.duration or 0)))
        P.auto:SetEnabledTip(not o.locked, o.lockReason)
    end
    UpdateBoss()
end

local function SetArt(info)
    local tex = P.art
    if info and info.lore then
        tex:SetTexture(info.lore)
        tex:SetTexCoord(0, 0.7617187, 0, 0.65625)
        return
    end
    if info and info.bg then
        tex:SetTexture(info.bg)
        tex:SetTexCoord(0, 0.76953125, 0, 0.830078125)
        return
    end
    tex:SetTexCoord(0, 1, 0, 1)
    -- LFGList.xml: the group finder's dungeon background
    if not Kit.Atlas(tex, "groupfinder-background-dungeons") then tex:SetColorTexture(0.1, 0.08, 0.06, 1) end
end

local function ShowInstance()
    local d = Current()
    P.page:SetShown(d ~= nil)
    P.pageEmpty:SetShown(d == nil)
    if not d then return end
    local o = d.offer
    local ins = CurrentInstance()
    local info = ins and EJData(ins.journalID)
    SetArt(info)

    P.name:SetText((info and info.name) or o.name or "?")
    local tier = D.TIERS and D.TIERS[o.tier or 1]
    P.kind:SetText(string.format("%s  -  %s", o.kind == "RAID" and "Raid" or "Dungeon", tier and tier.name or ""))
    P.desc:SetText((info and info.desc) or "")
    P.stats:SetText(string.format("Level |cffffffff%d|r   Item level |cffffffff%d|r   %s   |cffffffff%d-%d|r heroes   %s",
        o.level or 1, o.ilvl or 0, U.Duration(o.duration or 0), o.minHeroes or 1, o.maxHeroes or 5,
        o.kind == "RAID" and (o.weeklyDone and "|cff9d9d9dDefeated this week|r" or "|cff40ff40Weekly: available|r") or ""))

    -- bosses
    local bosses = BossRows(ins)
    P.bossByKey = {}
    for _, b in ipairs(bosses) do P.bossByKey[b.key] = b end
    if P.bossFor ~= d.key or not P.bossByKey[P.bossKey or 0] then
        P.bossFor = d.key
        P.bossKey = bosses[#bosses] and bosses[#bosses].key or nil   -- the end boss first
        P.pinned = nil
    end
    P.bosses:SetData(bosses)
    P.bosses:SetSelected(P.bossKey)
    P.bossHeader.right:SetText(#bosses > 0 and tostring(#bosses) or "")

    -- party
    local raid = o.kind == "RAID"
    P.dungeonPicker:SetShown(not raid)
    P.raidPicker:SetShown(raid)
    local picker = ActivePicker()
    local n = math.max(1, math.min(raid and 10 or 5, o.maxHeroes or 5))
    if picker.n ~= n then picker:SetSlots(n) end
    P.partyHeader:SetText(string.format("Party  |cff9d9d9d%d-%d|r", o.minHeroes or 1, o.maxHeroes or 5))
    if d.task then
        picker:SetHeroes(d.task.heroes or {})
        picker:SetEnabled(false)
        P.prefillFor = nil
    else
        picker:SetEnabled(not o.locked)
        if P.prefillFor ~= d.key then
            P.prefillFor = d.key
            picker:SetHeroes(o.locked and {} or (Kit.Call("Suggest", o.key) or {}))
        else
            local keep, changed = {}, false
            for _, id in ipairs(picker:GetHeroes()) do
                local h = Kit.Hero(id)
                if h and not h.taskId then keep[#keep + 1] = id else changed = true end
            end
            if changed then picker:SetHeroes(keep) end
        end
    end
    UpdateParty()
end

local function StartSelected()
    local d = Current()
    if not d or d.task then return end
    local o = d.offer
    local task = Kit.Do("Start", o.key, ActivePicker():GetHeroes(), (o.kind ~= "RAID") and P.repeatOn or false)
    if task then
        if UI.Status then UI.Status("Your party enters " .. (o.name or "?"), 0.4, 1, 0.4) end
        P.prefillFor = nil
    end
end

local function AutoFill()
    local d = Current()
    if not d or d.task then return end
    local ids = Kit.Call("Suggest", d.offer.key) or {}
    if #ids == 0 and UI.Status then UI.Status("No idle heroes", 1, 0.3, 0.3) end
    ActivePicker():SetHeroes(ids)
    UpdateParty()
end

------------------------------------------------------------------------
-- build
------------------------------------------------------------------------

local function BuildBossRow(row)
    row.Portrait = row:CreateTexture(nil, "ARTWORK")
    row.Portrait:SetSize(32, 16)
    row.Portrait:SetPoint("LEFT", 2, 0)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 38, 0)
    row.Name:SetPoint("RIGHT", -40, 0)
    row.Threats = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Threats:SetPoint("RIGHT", -2, 0)
    row.Threats:SetWidth(38)
end

local function UpdateBossRow(row, b)
    if b.icon then
        row.Portrait:SetTexture(b.icon)
        row.Portrait:SetTexCoord(0, 1, 0.1, 0.6)
    else
        row.Portrait:SetTexture(SKULL)
        row.Portrait:SetTexCoord(-0.5, 1.5, 0, 1)
    end
    row.Name:SetText(b.name)
    local parts = {}
    for i, k in ipairs(b.threats or {}) do
        if i > 2 then break end
        local t = D.THREATS and D.THREATS[k]
        parts[#parts + 1] = Kit.IconMarkup(t and t.icon, 14)
    end
    row.Threats:SetText(table.concat(parts, ""))
end

local function BossTooltip(tt, row, b)
    tt:SetText(b.name, 1, 0.82, 0)
    if b.desc and b.desc ~= "" then tt:AddLine(b.desc, 1, 1, 1, true) end
    local countered = (P.preview and P.preview.countered) or {}
    for _, k in ipairs(b.threats or {}) do
        local t = D.THREATS and D.THREATS[k]
        local ok = countered[k]
        tt:AddLine(Kit.IconMarkup(t and t.icon, 14) .. " " .. (t and t.name or k) .. (ok and "  |cff40ff40countered|r" or ""), 1, 0.6, 0.5)
    end
end

local function BuildChaseRow(parent, kind)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(212, 22)
    c.kind = kind
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if not Kit.Atlas(hl, "auctionhouse-ui-row-highlight") then hl:SetColorTexture(1, 1, 1, 0.08) end
    c.Icon = c:CreateTexture(nil, "ARTWORK")
    c.Icon:SetSize(20, 20)
    c.Icon:SetPoint("LEFT", 1, 0)
    c.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.Pin = c:CreateTexture(nil, "OVERLAY")
    c.Pin:SetAllPoints(c.Icon)
    c.Pin:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    c.Pin:SetBlendMode("ADD")
    c.Pin:Hide()
    c.Check = c:CreateTexture(nil, "OVERLAY")
    c.Check:SetSize(14, 14)
    c.Check:SetPoint("BOTTOMRIGHT", c.Icon, 4, -3)
    -- Blizzard_SharedXML common check mark
    if not Kit.Atlas(c.Check, "common-icon-checkmark") then Kit.Atlas(c.Check, "GarrMission_CounterCheck", { 0.2, 1, 0.2, 1 }) end
    c.Check:Hide()
    c.Chance = Kit.Text(c, "GameFontHighlightSmall", "RIGHT")
    c.Chance:SetPoint("RIGHT", -2, 0)
    c.Chance:SetWidth(58)
    c.Name = Kit.Text(c, "GameFontHighlightSmall")
    c.Name:SetPoint("LEFT", c.Icon, "RIGHT", 5, 0)
    c.Name:SetPoint("RIGHT", c.Chance, "LEFT", -2, 0)
    c:SetScript("OnEnter", function(self)
        if not self.spec then return end
        ShowChaseModel(self.kind)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local d = Current()
        GameTooltip:SetText(self.Name:GetText() or "", self.kind == "MOUNT" and 0.64 or 0, self.kind == "MOUNT" and 0.21 or 0.44, self.kind == "MOUNT" and 0.93 or 0.87)
        GameTooltip:AddLine(self.kind == "MOUNT" and "Mount" or "Battle pet", 1, 1, 1)
        GameTooltip:AddDoubleLine("Drop chance per clear", Pct1(self.spec.chance), 0.8, 0.8, 0.8, 1, 1, 1)
        if d then GameTooltip:AddLine("Drops in " .. (d.offer.name or "?"), 0.8, 0.8, 0.8) end
        if self.collected then GameTooltip:AddLine("Collected", 0.3, 1, 0.3) end
        GameTooltip:AddLine(P.pinned == self.kind and "Click: back to the boss" or "Click: keep it in the viewer", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ShowChaseModel(P.pinned)
    end)
    c:SetScript("OnClick", function(self)
        if not self.spec then return end
        if P.pinned == self.kind then P.pinned = nil else P.pinned = self.kind end
        for _, x in ipairs(P.chase) do x.Pin:SetShown(P.pinned == x.kind) end
        ShowChaseModel(P.pinned)
    end)
    return c
end

local function MakePicker(parent, slots, size, spacing)
    local picker = Kit.PartyPicker(parent, { slots = slots, size = size, spacing = spacing, onChange = function() UpdateParty() end })
    picker.hints = {}
    for i = 1, slots do
        local s = picker.slots[i]
        -- on the slot, so the hidden picker's hints hide with it (dungeon and raid pickers share a spot)
        local t = s:CreateTexture(nil, "ARTWORK")
        t:SetSize(math.min(14, size - 4), math.min(14, size - 4))
        t:SetPoint("TOP", s, "BOTTOM", 0, -2)
        t:Hide()
        picker.hints[i] = t
    end
    return picker
end

local function Build(panel)
    P.listHeader = Kit.Header(panel, "Dungeons & Raids", LIST_W)
    P.listHeader:SetPoint("TOPLEFT", 0, 0)
    P.list = Kit.List(panel, {
        rowHeight = 20, selectable = true, key = function(d) return d.key end,
        build = BuildInstanceRow, update = UpdateInstanceRow, tooltip = InstanceTooltip,
        onClick = function(row, d, button, list)
            if d.header then list:SetSelected(P.key); return end
            if d.key ~= P.key then
                P.key = d.key
                ShowInstance()
            end
        end,
    })
    P.list:SetPoint("TOPLEFT", 0, -22)
    P.list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", LIST_W, 0)

    local f = Kit.Inset(panel)
    f:SetPoint("TOPLEFT", RX, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    P.frame = f
    P.art = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    P.art:SetPoint("TOPLEFT", 3, -3)
    P.art:SetPoint("BOTTOMRIGHT", -3, 3)
    P.art:SetVertexColor(0.55, 0.55, 0.55)
    local shade = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    shade:SetPoint("TOPLEFT", 3, -3)
    shade:SetPoint("BOTTOMRIGHT", -3, 3)
    shade:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.85), CreateColor(0, 0, 0, 0.55))) then
        shade:SetColorTexture(0, 0, 0, 0.65)
    end
    P.pageEmpty = Kit.Text(f, "GameFontDisable", "CENTER")
    P.pageEmpty:SetPoint("CENTER")
    P.pageEmpty:SetText("Choose a dungeon or raid")

    local c = CreateFrame("Frame", nil, f)
    c:SetAllPoints()
    P.page = c

    -- title block
    P.name = Kit.Text(c, "GameFontNormalLarge")
    P.name:SetPoint("TOPLEFT", 10, -8)
    P.name:SetWidth(440)
    P.kind = Kit.Text(c, "GameFontNormalSmall", "RIGHT")
    P.kind:SetPoint("TOPRIGHT", -10, -11)
    P.kind:SetWidth(230)
    P.desc = Kit.Text(c, "GameFontHighlightSmall")
    P.desc:SetPoint("TOPLEFT", 10, -28)
    P.desc:SetPoint("RIGHT", -10, 0)
    P.desc:SetWordWrap(true)
    P.desc:SetHeight(26)
    P.desc:SetJustifyV("TOP")
    P.desc:SetTextColor(0.85, 0.85, 0.85)
    P.stats = Kit.Text(c, "GameFontNormalSmall")
    P.stats:SetPoint("TOPLEFT", 10, -58)
    P.stats:SetWidth(470)
    P.threats = Kit.ThreatIcons(c, 20, 8)
    P.threats:SetPoint("TOPRIGHT", -10, -54)
    P.threats:SetWidth(8 * 23)
    local tl = Kit.Text(c, "GameFontNormalSmall", "RIGHT")
    tl:SetPoint("RIGHT", P.threats, "LEFT", -4, 0)
    tl:SetText("Threats")

    -- encounters
    P.bossHeader = Kit.Header(c, "Encounters", 190)
    P.bossHeader:SetPoint("TOPLEFT", 8, Y0)
    P.bosses = Kit.List(c, {
        rowHeight = 20, selectable = true, key = function(b) return b.key end,
        build = BuildBossRow, update = UpdateBossRow, tooltip = BossTooltip,
        onClick = function(row, b)
            P.bossKey = b.key
            P.pinned = nil
            for _, x in ipairs(P.chase) do x.Pin:Hide() end
            UpdateBoss()
        end,
    })
    P.bosses:SetPoint("TOPLEFT", 8, Y0 - 20)
    P.bosses:SetSize(190, MODEL_S - 20)

    P.model = Kit.ModelView(c, MODEL_S, MODEL_S, { caption = true, hint = true, bg = false, facing = -0.3 })
    P.model:SetPoint("TOPLEFT", MODEL_X, Y0)
    local btl = Kit.Text(c, "GameFontNormalSmall")
    btl:SetPoint("TOPLEFT", MODEL_X, Y0 - MODEL_S - 10)
    btl:SetText("Boss threats")
    P.bossThreats = Kit.ThreatIcons(c, 20, 6)
    P.bossThreats:SetPoint("TOPLEFT", MODEL_X + 76, Y0 - MODEL_S - 4)
    P.bossNoThreats = Kit.Text(c, "GameFontDisableSmall")
    P.bossNoThreats:SetPoint("TOPLEFT", MODEL_X + 76, Y0 - MODEL_S - 10)
    P.bossNoThreats:SetText("None")
    P.bossDesc = Kit.Text(c, "GameFontHighlightSmall")
    P.bossDesc:SetPoint("TOPLEFT", 10, Y0 - MODEL_S - 32)
    P.bossDesc:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", SIDE_X - 12, 8)
    P.bossDesc:SetWordWrap(true)
    P.bossDesc:SetJustifyV("TOP")
    P.bossDesc:SetTextColor(0.8, 0.8, 0.8)

    -- side column: chase, rewards, party
    local y = Y0
    P.chaseHeader = Kit.Header(c, "Chase", 212)
    P.chaseHeader:SetPoint("TOPLEFT", SIDE_X, y)
    P.chase = {}
    for i, kind in ipairs({ "MOUNT", "PET" }) do
        local row = BuildChaseRow(c, kind)
        row:SetPoint("TOPLEFT", SIDE_X, y - 20 - (i - 1) * 22)
        P.chase[i] = row
    end
    y = y - 20 - 2 * 22 - 6
    P.rewardHeader = Kit.Header(c, "Rewards", 212)
    P.rewardHeader:SetPoint("TOPLEFT", SIDE_X, y)
    P.rewards = {}
    for i = 1, REWARD_BUTTONS do
        local b = Kit.ItemButton(c, 30)
        b:SetPoint("TOPLEFT", SIDE_X + (i - 1) * 35, y - 22)
        b:Hide()
        P.rewards[i] = b
    end
    P.gold = Kit.CoinText(c, "GameFontHighlightSmall")
    P.gold:SetJustifyH("LEFT")
    P.gold:SetPoint("TOPLEFT", SIDE_X, y - 58)
    P.xp = Kit.Text(c, "GameFontHighlightSmall", "RIGHT")
    P.xp:SetPoint("TOPRIGHT", c, "TOPLEFT", SIDE_X + 210, y - 58)
    y = y - 76
    P.partyHeader = Kit.Header(c, "Party", 212)
    P.partyHeader:SetPoint("TOPLEFT", SIDE_X, y)
    P.dungeonPicker = MakePicker(c, 5, 32, 10)
    P.dungeonPicker:SetPoint("TOPLEFT", SIDE_X + 2, y - 22)
    P.raidPicker = MakePicker(c, 10, 19, 2)
    P.raidPicker:SetPoint("TOPLEFT", SIDE_X + 2, y - 26)
    P.raidPicker:Hide()
    y = y - 22 - 32 - 18
    P.auto = Kit.Button(c, "Auto-fill", 66, 20, AutoFill, "Fill the party with the best idle heroes, roles first")
    P.auto:SetPoint("TOPLEFT", SIDE_X, y)
    P.chance = Kit.ChanceMeter(c, 90, 16)
    P.chance:SetPoint("LEFT", P.auto, "RIGHT", 6, 0)
    P.time = Kit.Text(c, "GameFontHighlightSmall", "RIGHT")
    P.time:SetPoint("TOPRIGHT", c, "TOPLEFT", SIDE_X + 210, y - 3)
    P.time:SetWidth(50)
    y = y - 26
    P.notes = {}
    for i = 1, 8 do
        local fs = Kit.Text(c, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", SIDE_X, y - (i - 1) * 13)
        fs:SetWidth(212)
        P.notes[i] = fs
    end
    P.repeatBox = Check(c, "Repeat", function(on) P.repeatOn = on end,
        "Run it again by itself when collected (also while you are away, up to 12 h)")
    P.repeatBox:SetPoint("BOTTOMLEFT", SIDE_X - 2, 8)
    P.start = Kit.Button(c, "Start", 110, 24, StartSelected)
    P.start:SetPoint("BOTTOMRIGHT", -8, 8)
end

local function Refresh(panel)
    local rows = InstanceRows()
    P.rowByKey = {}
    for _, r in ipairs(rows) do if not r.header then P.rowByKey[r.key] = r end end
    if not (P.key and P.rowByKey[P.key]) then P.key = DefaultInstance(rows) end
    P.list:SetData(rows)
    P.list:SetSelected(P.key)
    local done, total = 0, 0
    for _, r in ipairs(rows) do
        if not r.header and r.offer.kind == "RAID" and not TierLocked(r.offer) then
            total = total + 1
            if r.offer.weeklyDone then done = done + 1 end
        end
    end
    P.listHeader.right:SetText(total > 0 and string.format("Raids %d/%d", done, total) or "")
    ShowInstance()
end

local tickN = 0
local function Tick(panel, now)
    tickN = tickN + 1
    if tickN % 2 == 0 then
        P.list:Refresh()
        local d = Current()
        if d and d.task then UpdateParty() end
    end
end

UI.RegisterTab({ key = "DUNGEONS", title = "Dungeons", order = 4, build = Build, refresh = Refresh, tick = Tick })
