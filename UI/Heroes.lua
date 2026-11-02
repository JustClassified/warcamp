-- Warcamp: the Heroes tab. Left: the roster (filter All/Idle/Busy, sort level/ilvl/class).
-- Right: the selected hero (model with an 8-slot paperdoll, traits, gathering skills, current task),
-- under it the gear bag (equip on the selected hero, sell).

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D
local floor = math.floor

local LIST_W = 250
local SLOT = 36
local MODEL_W, MODEL_H = 200, 236
local DOLL_Y = -62
local BAG_Y = -306

-- empty paperdoll slot art (Interface\PaperDoll, the character frame's empty-slot textures)
local SLOT_TEX = {
    HEAD = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", SHOULDER = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    CHEST = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", HANDS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    LEGS = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs", FEET = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    WEAPON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand", TRINKET = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
}
local PROFS = { "MINING", "HERBALISM", "SKINNING", "FISHING" }
local PROF_ICON = {
    MINING = "Interface\\Icons\\Trade_Mining", HERBALISM = "Interface\\Icons\\Trade_Herbalism",
    SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", FISHING = "Interface\\Icons\\Trade_Fishing",
}
local KIND_ICON = {
    GATHER = "Interface\\Icons\\Trade_Mining", QUEST = "Interface\\Icons\\INV_Misc_Map_01",
    DUNGEON = "Interface\\Icons\\INV_Sword_04", RAID = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
}
local TRAIT_KIND_TEXT = {
    GATHER_YIELD = "yield", YIELD = "yield", SPEED = "speed", DURATION = "speed", XP = "experience", EXPERIENCE = "experience",
    GOLD = "gold", CHANCE = "success", LOOT = "loot", COLLECT = "mount and pet chance",
}

local P = { filter = "ALL", sort = "LEVEL" }
UI._heroes = P   -- for the headless smoke test

local function Cap(s) return s and (s:sub(1, 1) .. s:sub(2):lower()) or "" end

local function Slots()
    return Kit.Call("Slots") or D.GEAR_SLOTS or { "HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS", "FEET", "WEAPON", "TRINKET" }
end

local function Selected() return P.selId and Kit.Hero(P.selId) end

------------------------------------------------------------------------
-- roster list
------------------------------------------------------------------------

local function HeroList()
    local all = Kit.Call("GetHeroes") or {}
    local out, ilvl = {}, {}
    for _, h in ipairs(all) do
        local st = Kit.Call("HeroStatus", h) or "IDLE"
        if P.filter == "ALL" or (P.filter == "IDLE" and st == "IDLE") or (P.filter == "BUSY" and st ~= "IDLE") then
            out[#out + 1] = h
            ilvl[h] = Kit.Call("HeroIlvl", h) or 0
        end
    end
    local function byLevel(a, b)
        if (a.level or 1) ~= (b.level or 1) then return (a.level or 1) > (b.level or 1) end
        if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
        return tostring(a.id) < tostring(b.id)
    end
    if P.sort == "ILVL" then
        table.sort(out, function(a, b) if ilvl[a] ~= ilvl[b] then return ilvl[a] > ilvl[b] end return byLevel(a, b) end)
    elseif P.sort == "CLASS" then
        table.sort(out, function(a, b)
            if a.class ~= b.class then return tostring(a.class) < tostring(b.class) end
            return byLevel(a, b)
        end)
    else
        table.sort(out, byLevel)
    end
    return out, #all
end

local function StatusFor(h, now)
    local st = Kit.Call("HeroStatus", h) or "IDLE"
    if st == "IDLE" then return "Idle", 0.4, 1, 0.4 end
    if st == "READY" then return "Ready", 1, 0.82, 0 end
    local t = h.taskId and Kit.Call("GetTask", h.taskId)
    return t and Kit.TimeLeft(t.endAt, now) or "Busy", 0.75, 0.75, 0.75
end

local function BuildHeroRow(row)
    row.Badge = Kit.HeroBadge(row, LIST_W - 16, 20)
    row.Badge:SetPoint("LEFT", 0, 0)
end

local function UpdateHeroRow(row, h)
    row.Badge:SetHero(h, StatusFor(h))
end

local function SetButtonsLit(buttons, current)
    for key, b in pairs(buttons) do
        if key == current then b:LockHighlight() else b:UnlockHighlight() end
    end
end

------------------------------------------------------------------------
-- paperdoll
------------------------------------------------------------------------

local function BagFor(slot)
    local out = {}
    for _, g in ipairs(Kit.Call("GetGearBag") or {}) do
        if g.slot == slot then out[#out + 1] = g end
    end
    return out   -- already ilvl desc
end

local function DiffText(new, cur)
    local d = floor((new or 0) - (cur or 0) + 0.5)
    if d > 0 then return string.format("|cff40ff40+%d|r", d) end
    if d < 0 then return string.format("|cffff5040%d|r", d) end
    return "|cff9d9d9d=|r"
end

local function OpenSlotMenu(btn)
    local h = Selected()
    if not h then return end
    local cur = h.gear and h.gear[btn.slot]
    local entries = {}
    for i, g in ipairs(BagFor(btn.slot)) do
        if i > 20 then break end
        local id = g.id
        entries[#entries + 1] = {
            text = string.format("|c%s%s|r  |cffffd100%d|r  %s", Kit.QualityHex(g.quality), g.name or "?", g.ilvl or 0, DiffText(g.ilvl, cur and cur.ilvl)),
            func = function() Kit.Do("Equip", h.id, id) end,
            tooltip = function(tt)
                local r, gg, b = ns.QUALITY_COLOR(g.quality)
                tt:SetText(g.name or "?", r, gg, b)
                tt:AddLine("Item level " .. (g.ilvl or 0), 1, 0.82, 0)
                tt:AddLine(Cap(g.slot) .. "  -  " .. (D.QUALITY and D.QUALITY[g.quality] or ""), 1, 1, 1)
                if cur then tt:AddLine("Replaces " .. (cur.name or "?") .. " (" .. (cur.ilvl or 0) .. ")", 0.7, 0.7, 0.7) end
            end,
        }
    end
    if #entries == 0 then entries[1] = { text = "Nothing for this slot in your bags", disabled = true } end
    if cur then
        entries[#entries + 1] = { divider = true }
        entries[#entries + 1] = { text = "|cffff6060Unequip|r " .. (cur.name or ""), func = function() Kit.Do("Unequip", h.id, btn.slot) end }
    end
    Kit.Menu(btn, Cap(btn.slot), entries)
end

local function SlotEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.gear and self.spec then
        Kit.ItemTooltip(GameTooltip, self.spec)
    else
        GameTooltip:SetText(Cap(self.slot), 1, 0.82, 0)
        GameTooltip:AddLine("Empty: it counts as item level 1", 0.6, 0.6, 0.6)
    end
    local n = #BagFor(self.slot)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(n > 0 and string.format("Click: choose from %d in your bags", n) or "Nothing for this slot in your bags", 0.6, 0.8, 1)
    if self.gear then GameTooltip:AddLine("Right-click: unequip", 0.6, 0.8, 1) end
    GameTooltip:Show()
end

local function SlotClick(self, button)
    local h = Selected()
    if not h then return end
    if button == "RightButton" then
        if self.gear then Kit.Do("Unequip", h.id, self.slot) end
    else
        OpenSlotMenu(self)
    end
end

local function BuildSlot(parent, slot)
    local b = Kit.ItemButton(parent, SLOT)
    b.slot = slot
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnClick", SlotClick)
    b.Ilvl = Kit.Text(b, "GameFontHighlightSmall")
    b.Ilvl:SetPoint("TOPLEFT", 2, -2)
    b.Ilvl:SetTextColor(1, 0.82, 0)
    b.Up = Kit.Text(b, "GameFontHighlightSmall", "RIGHT")
    b.Up:SetPoint("BOTTOMRIGHT", -1, 2)
    return b
end

local function UpdateSlot(b, h)
    local g = h and h.gear and h.gear[b.slot]
    if g then
        b:SetGear(g)
        b.Ilvl:SetText(tostring(g.ilvl or ""))
    else
        b:Clear()
        b.gear = nil
        b.Icon:SetTexture(SLOT_TEX[b.slot] or 134400)
        b.Ilvl:SetText("")
    end
    -- a green arrow-ish "+" when the bag holds something better for this slot
    local best = BagFor(b.slot)[1]
    if best and (best.ilvl or 0) > (g and g.ilvl or 0) then b.Up:SetText("|cff40ff40+|r") else b.Up:SetText("") end
end

------------------------------------------------------------------------
-- detail
------------------------------------------------------------------------

local function TraitText(def)
    local v = def.value or 0
    local what = TRAIT_KIND_TEXT[def.kind] or string.lower(def.kind or "")
    local s = string.format("%+d%% %s", floor(v * 100 + (v >= 0 and 0.5 or -0.5)), what)
    if def.filter then s = s .. " (" .. string.lower(def.filter) .. ")" end
    return s
end

local function UpdateTraits(h)
    local traits = h and h.traits or {}
    for i, r in ipairs(P.traits) do
        local key = traits[i]
        local def = key and D.TRAITS and D.TRAITS[key]
        r.key = key
        if def then
            r.Icon:SetTexture(def.icon or 134400)
            r.Icon:Show()
            r.Name:SetText(def.name or key)
            local neg = (def.value or 0) < 0
            if neg then r.Name:SetTextColor(1, 0.45, 0.4) else r.Name:SetTextColor(0.45, 1, 0.45) end
            r.Value:SetText(TraitText(def))
            r:Show()
        elseif i == 1 then
            r.Icon:Hide()
            r.Name:SetText("No traits")
            r.Name:SetTextColor(0.5, 0.5, 0.5)
            r.Value:SetText("")
            r:Show()
        else
            r:Hide()
        end
    end
end

local function UpdateSkills(h)
    local cap = Kit.Call("SkillCap") or 150
    local cls = h and D.CLASSES and D.CLASSES[h.class]
    for _, r in ipairs(P.skills) do
        local v = h and h.skills and h.skills[r.prof] or 0
        r.Bar:SetValueText(v, cap)
        local mine = cls and cls.gather == r.prof
        r.Bar:SetBarColor(mine and 0.75 or 0.55, mine and 0.55 or 0.45, mine and 0.1 or 0.2)
        r.Bonus:SetText(mine and "|cff40ff40class +10%|r" or "")
        r.value, r.cap, r.mine = v, cap, mine
    end
end

local function UpdateTask(h)
    local t = h and h.taskId and Kit.Call("GetTask", h.taskId)
    P.task.t = t
    if t then
        P.task.Icon:SetTexture(t.icon or (t.profession and PROF_ICON[t.profession]) or KIND_ICON[t.kind] or 134400)
        P.task.Icon:Show()
        P.task.Name:SetText(t.name or "?")
        P.task.Name:SetTextColor(1, 1, 1)
        P.task.Bar:SetTimes(t.startAt, t.endAt)
        P.task.Bar:Show()
        if t.chance then
            local r, g, b = Kit.ChanceColor(t.chance)
            P.task.Chance:SetText(string.format("%d%%", floor(t.chance * 100 + 0.5)))
            P.task.Chance:SetTextColor(r, g, b)
        else
            P.task.Chance:SetText("")
        end
    else
        P.task.Icon:Hide()
        P.task.Name:SetText("Idle. Send them out from the Missions or Dungeons tab.")
        P.task.Name:SetTextColor(0.5, 0.5, 0.5)
        P.task.Bar:Hide()
        P.task.Chance:SetText("")
    end
end

local function CountersMarkup(class)
    local def = D.CLASSES and D.CLASSES[class]
    if not (def and def.counters) then return "" end
    local parts = {}
    for _, k in ipairs(def.counters) do
        local t = D.THREATS and D.THREATS[k]
        if t then parts[#parts + 1] = Kit.IconMarkup(t.icon, 13) .. " " .. (t.name or k) end
    end
    return "Counters: " .. table.concat(parts, "  ")
end

local function UpdateDismiss(now)
    local h = Selected()
    local b = P.dismiss
    if not h then b:SetText("Dismiss"); b:SetEnabledTip(false, "No hero selected"); return end
    if P.dismissFor == h.id and (now or time()) <= (P.dismissUntil or 0) then
        b:SetText("Sure?")
        b:SetEnabledTip(true)
        b:SetTip((h.name or "?") .. " leaves the camp for good. Equipped gear above common goes to your bags.")
        return
    end
    P.dismissFor = nil
    b:SetText("Dismiss")
    local count = #(Kit.Call("GetHeroes") or {})
    if h.taskId then b:SetEnabledTip(false, "On a task. Wait until they are back.")
    elseif count <= 1 then b:SetEnabledTip(false, "You cannot dismiss your last recruit.")
    else b:SetEnabledTip(true); b:SetTip("Send this recruit away (click twice)") end
end

local function ShowDetail()
    local h = Selected()
    P.detail:SetShown(h ~= nil)
    P.empty:SetShown(h == nil)
    if not h then return end
    local look = Kit.Call("HeroLook", h)
    P.model:SetDisplay(look and look.display, h.class and ("Interface\\Icons\\ClassIcon_" .. h.class) or nil)

    local q = h.quality or 2
    local qr, qg, qb = ns.QUALITY_COLOR(q)
    P.name:SetText((h.name or "?") .. (h.surname and (" |cff9d9d9d" .. h.surname .. "|r") or ""))
    P.name:SetTextColor(qr, qg, qb)
    local cls = D.CLASSES and D.CLASSES[h.class]
    local _, _, _, chex = Kit.ClassColor(h.class)
    P.info:SetText(string.format("Level %d  |c%s%s|r  %s  |c%s%s|r", h.level or 1, Kit.QualityHex(q), D.QUALITY and D.QUALITY[q] or "",
        ns.Util.RaceName(h.race), chex, cls and cls.name or (h.class or "")))
    local role = D.ROLES and D.ROLES[h.role]
    P.role:SetText(Kit.RoleMarkup(h.role, 13) .. " " .. (role and role.name or (h.role or "")) .. "     " .. CountersMarkup(h.class))

    local ilvl = Kit.Call("HeroIlvl", h) or 0
    local power = Kit.Call("HeroPower", h) or 0
    P.stats:SetText(string.format("Item level |cffffffff%.1f|r    Power |cffffffff%d|r", ilvl, power))
    local need = Kit.Call("HeroXPNeeded", h) or 1
    local maxL = Kit.Call("MaxLevel")
    if maxL and (h.level or 1) >= maxL then
        P.xp:SetProgress(1, "Level cap for this tier", 0.5, 0.4, 0.8)
    else
        P.xp:SetValueText(h.xp or 0, need, "%d / %d XP")
        P.xp:SetBarColor(0.55, 0.25, 0.85)
    end

    for _, b in ipairs(P.slots) do UpdateSlot(b, h) end
    UpdateTraits(h)
    UpdateSkills(h)
    UpdateTask(h)
    UpdateDismiss()
    P.auto:SetEnabledTip(true)
end

------------------------------------------------------------------------
-- gear bag
------------------------------------------------------------------------

local function GearValue(g) return Kit.Call("GearValue", g) or 0 end

local function BagSell(btn)
    local g = btn:GetParent().data
    if not g then return end
    local now = time()
    if (g.quality or 0) >= 4 and not (btn.confirmFor == g.id and now <= (btn.confirmUntil or 0)) then
        btn.confirmFor, btn.confirmUntil = g.id, now + 3
        btn:SetText("Sure?")
        return
    end
    btn.confirmFor = nil
    local copper = Kit.Do("SellGear", g.id)
    if copper and UI.Status then UI.Status("Sold " .. (g.name or "") .. " for " .. Kit.Coin(tonumber(copper) or 0), 1, 0.82, 0) end
end

local function BagEquip(btn)
    local g = btn:GetParent().data
    local h = Selected()
    if g and h then Kit.Do("Equip", h.id, g.id) end
end

local function BuildBagRow(row)
    row.Item = Kit.ItemButton(row, 18)
    row.Item:SetPoint("LEFT", 2, 0)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Item, "RIGHT", 5, 0)
    row.Name:SetWidth(220)
    row.Slot = Kit.Text(row, "GameFontDisableSmall")
    row.Slot:SetPoint("LEFT", 250, 0)
    row.Slot:SetWidth(64)
    row.Ilvl = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Ilvl:SetPoint("LEFT", 314, 0)
    row.Ilvl:SetWidth(30)
    row.Ilvl:SetTextColor(1, 0.82, 0)
    row.Diff = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Diff:SetPoint("LEFT", 346, 0)
    row.Diff:SetWidth(30)
    row.Sell = Kit.Button(row, "Sell", 44, 18, BagSell)
    row.Sell:SetPoint("RIGHT", -2, 0)
    row.Equip = Kit.Button(row, "Equip", 50, 18, BagEquip)
    row.Equip:SetPoint("RIGHT", row.Sell, "LEFT", -2, 0)
    row.Value = Kit.CoinText(row)
    row.Value:SetPoint("RIGHT", row.Equip, "LEFT", -6, 0)
    row.Value:SetWidth(110)
    Kit.Live(row.Sell, function(btn, now)
        if btn.confirmFor and now > (btn.confirmUntil or 0) then btn.confirmFor = nil; btn:SetText("Sell") end
    end)
end

local function UpdateBagRow(row, g)
    row.Item:SetGear(g)
    row.Name:SetText(string.format("|c%s%s|r", Kit.QualityHex(g.quality), g.name or "?"))
    row.Slot:SetText(Cap(g.slot))
    row.Ilvl:SetText(tostring(g.ilvl or 0))
    local h = Selected()
    local cur = h and h.gear and h.gear[g.slot]
    row.Diff:SetText(h and DiffText(g.ilvl, cur and cur.ilvl or 0) or "")
    row.Value:SetCopper(GearValue(g), true)
    if row.Sell.confirmFor ~= g.id then row.Sell.confirmFor = nil; row.Sell:SetText("Sell") end
    row.Sell:SetTip("Sell for " .. Kit.Coin(GearValue(g)) .. ((g.quality or 0) >= 4 and " (click twice)" or ""))
    if h then
        row.Equip:SetEnabledTip(true)
        row.Equip:SetTip("Put it on " .. (h.name or "?"))
    else
        row.Equip:SetEnabledTip(false, "Select a hero first")
    end
end

local function BagTooltip(tt, row, g)
    local r, gg, b = ns.QUALITY_COLOR(g.quality)
    tt:SetText(g.name or "?", r, gg, b)
    tt:AddLine("Item level " .. (g.ilvl or 0), 1, 0.82, 0)
    tt:AddLine(Cap(g.slot) .. "  -  " .. (D.QUALITY and D.QUALITY[g.quality] or ""), 1, 1, 1)
    local h = Selected()
    local cur = h and h.gear and h.gear[g.slot]
    if h then
        tt:AddLine(" ")
        if cur then
            tt:AddDoubleLine(Kit.HeroName(h) .. " wears", string.format("|c%s%s|r %d", Kit.QualityHex(cur.quality), cur.name or "?", cur.ilvl or 0), 1, 1, 1, 1, 1, 1)
        else
            tt:AddLine(Kit.HeroName(h) .. " has nothing in this slot", 1, 1, 1)
        end
    end
    tt:AddDoubleLine("Sells for", Kit.Coin(GearValue(g)), 0.8, 0.8, 0.8, 1, 1, 1)
end

local function RefreshBag()
    local bag = Kit.Call("GetGearBag") or {}
    P.bag:SetData(bag)
    P.bagHeader.right:SetText(#bag > 0 and (#bag .. " items") or "")
    P.bagEmpty:SetShown(#bag == 0)
end

------------------------------------------------------------------------
-- tab
------------------------------------------------------------------------

local function Build(panel)
    -- roster (left)
    P.listHeader = Kit.Header(panel, "Heroes", LIST_W)
    P.listHeader:SetPoint("TOPLEFT", 0, 0)
    P.filters, P.sorts = {}, {}
    local fdefs = { { "ALL", "All", "Every hero" }, { "IDLE", "Idle", "Heroes at camp" }, { "BUSY", "Busy", "Heroes out on a task (or ready to collect)" } }
    local sdefs = { { "LEVEL", "Lvl", "Sort by level" }, { "ILVL", "iLvl", "Sort by item level" }, { "CLASS", "Class", "Sort by class" } }
    local x = 0
    for _, f in ipairs(fdefs) do
        local key = f[1]
        local b = Kit.Button(panel, f[2], 40, 18, function()
            P.filter = key
            SetButtonsLit(P.filters, P.filter)
            UI.Refresh()
        end, f[3])
        b:SetPoint("TOPLEFT", x, -20)
        P.filters[key] = b
        x = x + 41
    end
    x = x + 6
    for _, s in ipairs(sdefs) do
        local key = s[1]
        local b = Kit.Button(panel, s[2], 40, 18, function()
            P.sort = key
            SetButtonsLit(P.sorts, P.sort)
            UI.Refresh()
        end, s[3])
        b:SetPoint("TOPLEFT", x, -20)
        P.sorts[key] = b
        x = x + 41
    end
    SetButtonsLit(P.filters, P.filter)
    SetButtonsLit(P.sorts, P.sort)
    P.list = Kit.List(panel, {
        rowHeight = 20, selectable = true, key = function(h) return h.id end,
        build = BuildHeroRow, update = UpdateHeroRow,
        tooltip = function(tt, row, h) Kit.HeroTooltip(tt, h) end,
        onClick = function(row, h)
            P.selId = h.id
            P.dismissFor = nil
            ShowDetail()
            P.bag:Refresh()
        end,
    })
    P.list:SetPoint("TOPLEFT", 0, -42)
    P.list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", LIST_W, 0)
    P.listEmpty = Kit.Text(panel, "GameFontDisable", "CENTER")
    P.listEmpty:SetPoint("TOP", P.list, "TOP", 0, -30)
    P.listEmpty:SetText("No heroes match")

    -- detail (right)
    local d = CreateFrame("Frame", nil, panel)
    d:SetPoint("TOPLEFT", LIST_W + 10, 0)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    P.right = d
    P.empty = Kit.Text(d, "GameFontDisable", "CENTER")
    P.empty:SetPoint("TOP", 0, -120)
    P.empty:SetText("Select a hero")

    local det = CreateFrame("Frame", nil, d)
    det:SetPoint("TOPLEFT")
    det:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", 0, BAG_Y + 4)
    P.detail = det

    local hbg = det:CreateTexture(nil, "BACKGROUND")
    hbg:SetPoint("TOPLEFT", 0, 0)
    hbg:SetPoint("TOPRIGHT", 0, 0)
    hbg:SetHeight(58)
    -- garrison follower page header (Blizzard_GarrisonMissionUI.xml: HeaderBG)
    if not Kit.Atlas(hbg, "GarrMission_FollowerPageHeaderBG") then hbg:SetColorTexture(0, 0, 0, 0.35) end

    P.name = Kit.Text(det, "GameFontNormalLarge")
    P.name:SetPoint("TOPLEFT", 8, -5)
    P.name:SetWidth(330)
    P.info = Kit.Text(det, "GameFontHighlightSmall")
    P.info:SetPoint("TOPLEFT", 8, -26)
    P.info:SetWidth(330)
    P.role = Kit.Text(det, "GameFontHighlightSmall")
    P.role:SetPoint("TOPLEFT", 8, -41)
    P.role:SetWidth(420)

    P.dismiss = Kit.Button(det, "Dismiss", 74, 20, function()
        local h = Selected()
        if not h then return end
        local now = time()
        if P.dismissFor == h.id and now <= (P.dismissUntil or 0) then
            P.dismissFor = nil
            if Kit.Do("Dismiss", h.id) then P.selId = nil end
        else
            P.dismissFor, P.dismissUntil = h.id, now + 3
            UpdateDismiss(now)
        end
    end)
    P.dismiss:SetPoint("TOPRIGHT", -4, -4)
    P.auto = Kit.Button(det, "Auto-equip", 84, 20, function()
        local h = Selected()
        if not h then return end
        local ok, n = Kit.Do("AutoEquip", h.id)
        if ok and UI.Status then
            UI.Status((tonumber(n) or 0) > 0 and string.format("%s equipped %d better piece%s", h.name, n, n == 1 and "" or "s")
                or "Nothing better in your bags", 1, 0.82, 0)
        end
    end, "Equip the highest item level piece from your bags in every slot")
    P.auto:SetPoint("RIGHT", P.dismiss, "LEFT", -4, 0)
    P.stats = Kit.Text(det, "GameFontNormalSmall", "RIGHT")
    P.stats:SetPoint("TOPRIGHT", -6, -27)
    P.stats:SetWidth(220)
    P.xp = Kit.ProgressBar(det, 170, 12)
    P.xp:SetPoint("TOPRIGHT", -8, -42)
    Kit.Live(P.xp, nil)   -- not a timer bar
    local xpl = Kit.Text(det, "GameFontDisableSmall", "RIGHT")
    xpl:SetPoint("RIGHT", P.xp, "LEFT", -6, 0)
    xpl:SetText("XP")

    -- paperdoll: 4 slots left, model, 4 slots right (D.GEAR_SLOTS order)
    local doll = CreateFrame("Frame", nil, det)
    doll:SetPoint("TOPLEFT", 0, DOLL_Y)
    doll:SetSize(SLOT * 2 + MODEL_W + 8, MODEL_H)
    P.model = Kit.ModelView(doll, MODEL_W, MODEL_H, { hint = true })
    P.model:SetPoint("TOPLEFT", SLOT + 4, 0)
    P.slots = {}
    local slots = Slots()
    local per = math.ceil(#slots / 2)
    local step = per > 1 and floor((MODEL_H - SLOT) / (per - 1)) or 0
    for i, slot in ipairs(slots) do
        local b = BuildSlot(doll, slot)
        local col, r = (i <= per) and 0 or 1, (i - 1) % per
        b:SetPoint("TOPLEFT", col == 0 and 0 or (SLOT + MODEL_W + 8), -r * step)
        P.slots[i] = b
    end

    -- traits, skills, task (right of the paperdoll)
    local info = CreateFrame("Frame", nil, det)
    local IX = SLOT * 2 + MODEL_W + 18
    info:SetPoint("TOPLEFT", IX, DOLL_Y)
    info:SetPoint("BOTTOMRIGHT", 0, 0)
    local IW = 380
    P.traitHeader = Kit.Header(info, "Traits", IW)
    P.traitHeader:SetPoint("TOPLEFT", 0, 0)
    P.traits = {}
    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, info)
        r:SetSize(IW, 18)
        r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 18)
        r:EnableMouse(true)
        r.Icon = r:CreateTexture(nil, "ARTWORK")
        r.Icon:SetSize(16, 16)
        r.Icon:SetPoint("LEFT", 2, 0)
        r.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.Name = Kit.Text(r, "GameFontHighlightSmall")
        r.Name:SetPoint("LEFT", r.Icon, "RIGHT", 5, 0)
        r.Name:SetWidth(150)
        r.Value = Kit.Text(r, "GameFontDisableSmall", "RIGHT")
        r.Value:SetPoint("RIGHT", -2, 0)
        r.Value:SetWidth(200)
        Kit.SetTooltip(r, function(tt, self)
            local def = self.key and D.TRAITS and D.TRAITS[self.key]
            if not def then tt:SetText("Traits", 1, 0.82, 0); tt:AddLine("Better recruits (rare, epic) bring more traits.", 1, 1, 1, true) return end
            local neg = (def.value or 0) < 0
            tt:SetText(def.name or self.key, neg and 1 or 0.4, neg and 0.45 or 1, 0.4)
            if def.desc then tt:AddLine(def.desc, 1, 1, 1, true) end
            tt:AddLine(TraitText(def), 0.6, 0.8, 1)
            if def.drawback then tt:AddLine("Drawback: " .. TraitText(def.drawback), 1, 0.45, 0.4) end
        end)
        P.traits[i] = r
    end

    local sy = -20 - 4 * 18 - 6
    P.skillHeader = Kit.Header(info, "Gathering", IW)
    P.skillHeader:SetPoint("TOPLEFT", 0, sy)
    P.skills = {}
    for i, prof in ipairs(PROFS) do
        local r = CreateFrame("Frame", nil, info)
        r:SetSize(IW, 18)
        r:SetPoint("TOPLEFT", 0, sy - 20 - (i - 1) * 18)
        r:EnableMouse(true)
        r.prof = prof
        r.Icon = r:CreateTexture(nil, "ARTWORK")
        r.Icon:SetSize(16, 16)
        r.Icon:SetPoint("LEFT", 2, 0)
        r.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.Icon:SetTexture(PROF_ICON[prof])
        r.Name = Kit.Text(r, "GameFontHighlightSmall")
        r.Name:SetPoint("LEFT", r.Icon, "RIGHT", 5, 0)
        r.Name:SetWidth(70)
        r.Name:SetText(Cap(prof))
        r.Bar = Kit.ProgressBar(r, 190, 12)
        r.Bar:SetPoint("LEFT", 98, 0)
        Kit.Live(r.Bar, nil)
        r.Bonus = Kit.Text(r, "GameFontHighlightSmall", "RIGHT")
        r.Bonus:SetPoint("RIGHT", -2, 0)
        r.Bonus:SetWidth(80)
        Kit.SetTooltip(r, function(tt, self)
            tt:SetText(Cap(self.prof), 1, 0.82, 0)
            tt:AddLine(string.format("Skill %d / %d", self.value or 0, self.cap or 150), 1, 1, 1)
            tt:AddLine(string.format("+%.1f%% yield on %s missions", (self.value or 0) * 0.4, string.lower(self.prof)), 0.6, 0.8, 1)
            if self.mine then tt:AddLine("Class speciality: +10% yield", 0.3, 1, 0.3) end
            tt:AddLine("Rises with every gathering trip.", 0.6, 0.6, 0.6)
        end)
        P.skills[i] = r
    end

    local ty = sy - 20 - 4 * 18 - 6
    P.taskHeader = Kit.Header(info, "Current task", IW)
    P.taskHeader:SetPoint("TOPLEFT", 0, ty)
    local tr = CreateFrame("Frame", nil, info)
    tr:SetSize(IW, 20)
    tr:SetPoint("TOPLEFT", 0, ty - 21)
    tr:EnableMouse(true)
    tr.Icon = tr:CreateTexture(nil, "ARTWORK")
    tr.Icon:SetSize(18, 18)
    tr.Icon:SetPoint("LEFT", 2, 0)
    tr.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tr.Chance = Kit.Text(tr, "GameFontHighlightSmall", "RIGHT")
    tr.Chance:SetPoint("RIGHT", -2, 0)
    tr.Chance:SetWidth(34)
    tr.Bar = Kit.ProgressBar(tr, 110, 14)
    tr.Bar:SetPoint("RIGHT", tr.Chance, "LEFT", -2, 0)
    tr.Name = Kit.Text(tr, "GameFontHighlightSmall")
    tr.Name:SetPoint("LEFT", tr.Icon, "RIGHT", 5, 0)
    tr.Name:SetPoint("RIGHT", tr.Bar, "LEFT", -4, 0)
    Kit.SetTooltip(tr, function(tt, self)
        local t = self.t
        if not t then tt:SetText("Idle", 0.4, 1, 0.4); tt:AddLine("Pick a mission or dungeon for this hero.", 1, 1, 1, true) return end
        tt:SetText(t.name or "?", 1, 0.82, 0)
        for _, id in ipairs(t.heroes or {}) do
            local o = Kit.Hero(id)
            if o then tt:AddLine(Kit.ClassMarkup(o.class, 12) .. " " .. Kit.HeroName(o), 1, 1, 1) end
        end
        local now = time()
        if now >= (t.endAt or 0) then tt:AddLine("Ready to collect (Camp tab or Collect all)", 0.3, 1, 0.3)
        else tt:AddDoubleLine("Done at " .. U.Clock(t.endAt), "in " .. U.Duration(t.endAt - now), 1, 1, 1, 0.6, 0.8, 1) end
        if t.repeatIt then tt:AddLine("Repeats when collected", 0.55, 0.8, 1) end
    end)
    P.task = tr

    -- gear bag (bottom right)
    local bagArea = CreateFrame("Frame", nil, d)
    bagArea:SetPoint("TOPLEFT", 0, BAG_Y)
    bagArea:SetPoint("BOTTOMRIGHT", 0, 0)
    P.bagHeader = Kit.Header(bagArea, "Gear bag", 646)
    P.bagHeader:SetPoint("TOPLEFT", 0, 0)
    P.bagHeader:SetPoint("RIGHT", 0, 0)
    P.equipAll = Kit.Button(bagArea, "Equip everyone", 104, 18, function()
        local ok, n = Kit.Do("AutoEquipAll")
        if ok and UI.Status then UI.Status(string.format("Equipped %d piece%s", tonumber(n) or 0, n == 1 and "" or "s"), 1, 0.82, 0) end
    end, "Auto-equip every hero from the bags, highest level first")
    P.equipAll:SetPoint("TOPRIGHT", P.bagHeader, "TOPRIGHT", 0, 1)
    P.bagHeader.right:ClearAllPoints()
    P.bagHeader.right:SetPoint("RIGHT", P.equipAll, "LEFT", -8, 0)
    P.bag = Kit.List(bagArea, { rowHeight = 20, build = BuildBagRow, update = UpdateBagRow, tooltip = BagTooltip })
    P.bag:SetPoint("TOPLEFT", 0, -22)
    P.bag:SetPoint("BOTTOMRIGHT", 0, 0)
    P.bagEmpty = Kit.Text(bagArea, "GameFontDisable", "CENTER")
    P.bagEmpty:SetPoint("TOP", 0, -60)
    P.bagEmpty:SetText("No spare gear. Quests, dungeons, raids and the Forge drop it.")
end

local function Refresh(panel)
    local list, total = HeroList()
    -- keep the selection; fall back to the first hero shown (or any hero)
    if not (P.selId and Kit.Hero(P.selId)) then
        P.selId = list[1] and list[1].id or nil
        if not P.selId then
            local all = Kit.Call("GetHeroes") or {}
            P.selId = all[1] and all[1].id or nil
        end
    end
    P.list:SetData(list)
    P.list:SetSelected(P.selId)
    P.listEmpty:SetShown(#list == 0)
    P.listHeader.right:SetText(string.format("%d / %d", total, Kit.Call("MaxHeroes") or total))
    ShowDetail()
    RefreshBag()
end

local tickN = 0
local function Tick(panel, now)
    tickN = tickN + 1
    if tickN % 2 == 0 then P.list:Refresh() end
    if P.dismissFor and now > (P.dismissUntil or 0) then UpdateDismiss(now) end
end

UI.RegisterTab({ key = "HEROES", title = "Heroes", order = 2, build = Build, refresh = Refresh, tick = Tick })
