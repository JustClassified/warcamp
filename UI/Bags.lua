-- Warcamp: the Bags tab - everything the camp owns in one place.
-- Left: one bag of slots like the game's own bags - spare gear first, then materials and consumables
-- (sorted by kind, newest tier first), padded with empty slots. Right: the selected slot - value,
-- what it is used for, where it comes from; Use / Sell, or for gear Equip on the best recruit / Sell.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local D = ns.D

local LEFT_W = 580
local SLOT, GAP = 37, 3
local PER_ROW = math.floor((LEFT_W - 22) / (SLOT + GAP))
local MIN_ROWS = 13                     -- empty slots fill the bag to at least this many rows
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local KINDS = {
    { key = "ORE", name = "Ore" }, { key = "HERB", name = "Herbs" }, { key = "LEATHER", name = "Leather" },
    { key = "FISH", name = "Fish" }, { key = "CLOTH", name = "Cloth" }, { key = "BAR", name = "Bars" },
    { key = "RARE", name = "Rare finds" }, { key = "POTION", name = "Potions" }, { key = "FOOD", name = "Food" },
    { key = "MISC", name = "Other" },
}
local KIND_NAME = {}
for _, k in ipairs(KINDS) do KIND_NAME[k.key] = k.name end
local GATHERED_BY = { ORE = "MINING", HERB = "HERBALISM", LEATHER = "SKINNING", FISH = "FISHING" }
local PROF_NAME = { MINING = "Mining", HERBALISM = "Herbalism", SKINNING = "Skinning", FISHING = "Fishing" }
local SLOT_NAME = {
    HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs",
    FEET = "Feet", WEAPON = "Weapon", TRINKET = "Trinket",
}

local P = { filter = "ALL", sort = 1, search = "" }

-- filter bar: which kinds each button shows (gear is its own group)
local FILTERS = {
    { key = "ALL", name = "All" },
    { key = "GEAR", name = "Gear" },
    { key = "MATS", name = "Materials", kinds = { ORE = true, HERB = true, LEATHER = true, FISH = true, CLOTH = true, BAR = true } },
    { key = "USE", name = "Consumables", kinds = { POTION = true, FOOD = true } },
    { key = "RARE", name = "Rare", kinds = { RARE = true, MISC = true } },
}
local FILTER_BY_KEY = {}
for _, f in ipairs(FILTERS) do FILTER_BY_KEY[f.key] = f end
local SORTS = { "Type", "Value", "Name", "Amount" }

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function TierName(t)
    local d = D.TIERS and D.TIERS[t]
    return d and d.name or ("Tier " .. tostring(t or "?"))
end

local function SellPrice(key)
    local _, sell = Kit.Call("Price", key)
    return sell or 0
end

-- the idle-or-busy hero this piece would raise the most, and by how much
local function BestUpgrade(g)
    local best, gain
    for _, h in ipairs(Kit.Call("GetHeroes") or {}) do
        local cur = h.gear and h.gear[g.slot]
        local d = (g.ilvl or 0) - (cur and cur.ilvl or 0)
        if d > 0 and (not gain or d > gain) then best, gain = h, d end
    end
    return best, gain
end

-- recipes that take this item as a reagent
local function UsedIn(key)
    local out = {}
    for _, r in pairs(D.RECIPES or {}) do
        if r.inputs and r.inputs[key] then out[#out + 1] = r.name end
    end
    table.sort(out)
    return out
end

local function CraftedBy(key)
    for _, r in pairs(D.RECIPES or {}) do
        if r.output and r.output.item == key then
            local b = D.BUILDINGS and D.BUILDINGS[r.building]
            return r.name, b and b.name or r.building
        end
    end
end

local function Sources(key, it)
    local lines = {}
    local prof = GATHERED_BY[it.kind]
    if prof then
        local zones = {}
        for _, z in ipairs(D.ZONES or {}) do
            if z.tier == it.tier then zones[#zones + 1] = z.name end
        end
        lines[#lines + 1] = PROF_NAME[prof] .. " in " .. (#zones > 0 and table.concat(zones, ", ") or TierName(it.tier))
        if prof == "MINING" then lines[#lines + 1] = "The Mine produces it while you are away" end
        if prof == "HERBALISM" then lines[#lines + 1] = "The Herb Garden grows it while you are away" end
    elseif it.kind == "CLOTH" then
        lines[#lines + 1] = "Quest rewards in " .. TierName(it.tier) .. " zones"
    elseif it.kind == "RARE" then
        lines[#lines + 1] = "A rare find on " .. TierName(it.tier) .. " missions, dungeons and raids"
    end
    local recipe, building = CraftedBy(key)
    if recipe then lines[#lines + 1] = "Crafted at the " .. building .. " (" .. recipe .. ")" end
    lines[#lines + 1] = "Bought on the Market"
    return lines
end

------------------------------------------------------------------------
-- data
------------------------------------------------------------------------

-- one flat list of slots: { gear = g } for spare gear, { entry = e } for a stack
local KIND_ORDER = {}
for i, k in ipairs(KINDS) do KIND_ORDER[k.key] = i end

local function Matches(name, kind)
    if P.search == "" then return true end
    local hay = string.lower((name or "") .. " " .. (KIND_NAME[kind or ""] or "") .. " " .. (SLOT_NAME[kind or ""] or ""))
    return hay:find(P.search, 1, true) ~= nil
end

-- every slot gets the same sort fields: group (gear first), kind order, tier, value, name, amount
local function SortSlots(list)
    local mode = SORTS[P.sort] or "Type"
    table.sort(list, function(a, b)
        if mode == "Value" and a.value ~= b.value then return a.value > b.value end
        if mode == "Name" and a.name ~= b.name then return a.name < b.name end
        if mode == "Amount" and a.amount ~= b.amount then return a.amount > b.amount end
        if a.group ~= b.group then return a.group < b.group end
        if a.order ~= b.order then return a.order < b.order end
        if a.tier ~= b.tier then return a.tier > b.tier end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
end

local function BuildSlots()
    local f = FILTER_BY_KEY[P.filter] or FILTERS[1]
    local slots, total, worth, nGear, shown = {}, 0, 0, 0, 0
    for _, g in ipairs(Kit.Call("GetGearBag") or {}) do
        local value = Kit.Call("GearValue", g) or 0
        worth = worth + value
        nGear = nGear + 1
        if (f.key == "ALL" or f.key == "GEAR") and Matches(g.name, g.slot) then
            slots[#slots + 1] = { gear = g, group = 0, order = 0, tier = g.tier or 0, quality = g.quality or 1,
                value = value, name = g.name or "", amount = 1, id = tostring(g.id or 0) }
        end
    end
    for _, e in ipairs(Kit.Call("GetInventory") or {}) do
        local kind = e.item.kind or "MISC"
        local value = SellPrice(e.key) * e.count
        total = total + e.count
        worth = worth + value
        if (f.key == "ALL" or (f.kinds and f.kinds[kind])) and Matches(e.item.name or e.key, kind) then
            slots[#slots + 1] = { entry = e, group = 1, order = KIND_ORDER[kind] or 99, tier = e.item.tier or 0,
                quality = e.item.quality or 1, value = value, name = e.item.name or e.key, amount = e.count, id = e.key }
        end
    end
    SortSlots(slots)
    return slots, total, worth, nGear
end

local function ToRows(slots)
    local rows = {}
    local n = math.max(#slots, MIN_ROWS * PER_ROW)
    n = math.ceil(n / PER_ROW) * PER_ROW
    for i = 1, n, PER_ROW do
        local r = { first = i }
        for j = 0, PER_ROW - 1 do r[j + 1] = slots[i + j] or false end
        rows[#rows + 1] = r
    end
    return rows
end

------------------------------------------------------------------------
-- grid (left top)
------------------------------------------------------------------------

local function Select(key, gearId)
    P.sel, P.selGear = key, gearId
    P.confirmAll, P.confirmGear = nil, nil
    UI.Refresh()
end

local function BuildGridRow(row)
    row.Slots = {}
    for i = 1, PER_ROW do
        local b = Kit.ItemButton(row, SLOT)
        b:SetPoint("LEFT", 6 + (i - 1) * (SLOT + GAP), 0)
        b.Empty = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.Empty:SetPoint("TOPLEFT", -1, 1)
        b.Empty:SetPoint("BOTTOMRIGHT", 1, -1)
        b.Empty:SetTexture(EMPTY_SLOT)
        b.Sel = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.Sel:SetPoint("TOPLEFT", -3, 3)
        b.Sel:SetPoint("BOTTOMRIGHT", 3, -3)
        b.Sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.Sel:SetBlendMode("ADD")
        b.Sel:Hide()
        row.Slots[i] = b
    end
end

local function UpdateGridRow(row, d)
    if row.Stripe then row.Stripe:Hide() end
    for i, b in ipairs(row.Slots) do
        local s = d[i]
        if s and s.gear then
            local g = s.gear
            b:SetGear(g)
            b.spec.onClick = function() Select(nil, g.id) end
            b.Sel:SetShown(P.selGear == g.id)
            b.Empty:Hide()
        elseif s and s.entry then
            local e = s.entry
            b:SetItemKey(e.key, e.count, { { "Sells for", Kit.Coin(SellPrice(e.key)) .. " each", 0.6, 0.6, 0.6, 1, 1, 1 } })
            b.spec.onClick = function() Select(e.key) end
            b.Sel:SetShown(P.sel == e.key)
            b.Empty:Hide()
        else
            b:Clear()
            b.Sel:Hide()
            b.Empty:Show()
        end
    end
end

------------------------------------------------------------------------
-- detail (right)
------------------------------------------------------------------------

local function BuildDetail(panel)
    local R = CreateFrame("Frame", nil, panel)
    R:SetPoint("TOPLEFT", LEFT_W + 14, 0)
    R:SetPoint("BOTTOMRIGHT", 0, 0)
    P.detail = R
    R.header = Kit.Header(R, "Item")
    R.header:SetPoint("TOPLEFT", 0, 0)
    R.header:SetPoint("RIGHT", 0, 0)

    R.item = Kit.ItemButton(R, 44)
    R.item:SetPoint("TOPLEFT", 4, -26)
    R.name = Kit.Text(R, "GameFontNormalLarge")
    R.name:SetPoint("TOPLEFT", R.item, "TOPRIGHT", 10, -2)
    R.name:SetPoint("RIGHT", -4, 0)
    R.sub = Kit.Text(R, "GameFontHighlightSmall")
    R.sub:SetPoint("TOPLEFT", R.name, "BOTTOMLEFT", 0, -4)

    R.stats = Kit.Text(R, "GameFontHighlightSmall")
    R.stats:SetPoint("TOPLEFT", R.item, "BOTTOMLEFT", 0, -10)
    R.stats:SetPoint("RIGHT", -4, 0)
    R.stats:SetWordWrap(true)
    R.stats:SetJustifyV("TOP")
    R.stats:SetSpacing(3)

    R.use = Kit.Button(R, "Use", 70, 22, function()
        if P.sel then Kit.Do("UseItem", P.sel) end
    end)
    R.use:SetPoint("TOPLEFT", R.stats, "BOTTOMLEFT", 0, -10)
    R.sell1 = Kit.Button(R, "Sell 1", 60, 22, function() if P.sel then Kit.Do("Sell", P.sel, 1) end end)
    R.sell10 = Kit.Button(R, "Sell 10", 64, 22, function() if P.sel then Kit.Do("Sell", P.sel, 10) end end)
    R.sellAll = Kit.Button(R, "Sell all", 70, 22, function(btn)
        if not P.sel then return end
        local now = time()
        if P.confirmAll == P.sel and now <= (btn.confirmUntil or 0) then
            P.confirmAll = nil
            Kit.Do("Sell", P.sel, "ALL")
        else
            P.confirmAll, btn.confirmUntil = P.sel, now + 3
            btn:SetText("Sure?")
        end
    end)
    R.market = Kit.Button(R, "Market", 66, 22, function() UI.Show("MARKET") end, "Open the Market for the price chart and buying.")

    -- gear mode
    R.equip = Kit.Button(R, "Equip", 80, 22, function()
        local g = P.selGear and P.gearById and P.gearById[P.selGear]
        local best = g and BestUpgrade(g)
        if best then Kit.Do("Equip", best.id, g.id) end
    end)
    R.equip:SetPoint("TOPLEFT", R.stats, "BOTTOMLEFT", 0, -10)
    R.sellGear = Kit.Button(R, "Sell", 70, 22, function(btn)
        local g = P.selGear and P.gearById and P.gearById[P.selGear]
        if not g then return end
        local now = time()
        if (g.quality or 1) < 4 or (P.confirmGear == g.id and now <= (btn.confirmUntil or 0)) then
            P.confirmGear = nil
            Kit.Do("SellGear", g.id)
        else
            P.confirmGear, btn.confirmUntil = g.id, now + 3
            btn:SetText("Sure?")
        end
    end)
    R.sellGear:SetPoint("LEFT", R.equip, "RIGHT", 4, 0)
    R.heroes = Kit.Button(R, "Heroes", 70, 22, function() UI.Show("HEROES") end, "Open the Heroes tab to equip it on someone else.")
    R.heroes:SetPoint("LEFT", R.sellGear, "RIGHT", 4, 0)

    R.usedHeader = Kit.Header(R, "Used in")
    R.usedHeader:SetPoint("LEFT", 0, 0)
    R.usedHeader:SetPoint("RIGHT", 0, 0)
    R.used = Kit.Text(R, "GameFontHighlightSmall")
    R.used:SetPoint("TOPLEFT", R.usedHeader, "BOTTOMLEFT", 2, -6)
    R.used:SetPoint("RIGHT", -4, 0)
    R.used:SetWordWrap(true)
    R.used:SetJustifyV("TOP")
    R.used:SetSpacing(2)

    R.srcHeader = Kit.Header(R, "Comes from")
    R.srcHeader:SetPoint("LEFT", 0, 0)
    R.srcHeader:SetPoint("RIGHT", 0, 0)
    R.src = Kit.Text(R, "GameFontHighlightSmall")
    R.src:SetPoint("TOPLEFT", R.srcHeader, "BOTTOMLEFT", 2, -6)
    R.src:SetPoint("RIGHT", -4, 0)
    R.src:SetWordWrap(true)
    R.src:SetJustifyV("TOP")
    R.src:SetSpacing(2)

    R.empty = Kit.Text(R, "GameFontDisable", "CENTER")
    R.empty:SetPoint("CENTER", 0, 20)
    R.empty:SetWidth(280)
    R.empty:SetWordWrap(true)
end

local GEAR_WIDGETS = { "equip", "sellGear", "heroes" }
local ITEM_WIDGETS = { "use", "sell1", "sell10", "sellAll", "market", "usedHeader", "used", "srcHeader", "src" }

local function RefreshGear(R, g)
    R.header:SetText("Gear")
    R.item:SetGear(g)
    R.name:SetText("|c" .. Kit.QualityHex(g.quality or 1) .. (g.name or "?") .. "|r")
    R.sub:SetText((SLOT_NAME[g.slot] or g.slot or "") .. "  -  " .. TierName(g.tier))
    local value = Kit.Call("GearValue", g) or 0
    local best, gain = BestUpgrade(g)
    local lines = {
        string.format("|cffffd100Item level|r  %d", g.ilvl or 0),
        string.format("|cffffd100Sells for|r  %s", Kit.Coin(value)),
    }
    if best then
        lines[#lines + 1] = string.format("|cffffd100Best upgrade|r  %s  |cff40ff40+%d item level|r  (Equip puts it on them)", Kit.HeroName(best), gain)
    else
        lines[#lines + 1] = "|cff9d9d9dEvery recruit already wears something as good in this slot.|r"
    end
    R.stats:SetText(table.concat(lines, "\n"))
    -- the hero is named in the line above; button text is never clipped, so it stays short
    R.equip:SetText("Equip")
    R.equip:SetEnabledTip(best ~= nil, "No recruit would be better off with it.")
    if P.confirmGear ~= g.id or time() > (R.sellGear.confirmUntil or 0) then R.sellGear:SetText("Sell") end
end

local function RefreshDetail()
    local R = P.detail
    local g = P.selGear and P.gearById and P.gearById[P.selGear]
    if P.selGear and not g then P.selGear = nil end
    local it = (not g and P.sel) and Kit.Item(P.sel) or nil
    local have = P.sel and (Kit.Call("Count", P.sel) or 0) or 0
    local isGear, isItem = g ~= nil, it ~= nil
    local show = isGear or isItem
    for _, w in ipairs({ R.item, R.name, R.sub, R.stats }) do w:SetShown(show) end
    for _, k in ipairs(GEAR_WIDGETS) do R[k]:SetShown(isGear) end
    for _, k in ipairs(ITEM_WIDGETS) do R[k]:SetShown(isItem) end
    R.empty:SetShown(not show)
    if not show then
        R.header:SetText("Item")
        R.empty:SetText("Click a slot in your bags to see what it is worth, what it is used for and where to get more.")
        return
    end
    if g then return RefreshGear(R, g) end

    R.header:SetText(KIND_NAME[it.kind or ""] or "Item")
    R.item:SetItemKey(P.sel, have)
    R.name:SetText("|c" .. Kit.QualityHex(it.quality or 1) .. (it.name or P.sel) .. "|r")
    R.sub:SetText(TierName(it.tier) .. "  -  " .. (KIND_NAME[it.kind or ""] or "Item"))

    local buy, sell = Kit.Call("Price", P.sel)
    local lines = {
        string.format("|cffffd100Owned|r  %d", have),
        string.format("|cffffd100Sells for|r  %s each,  %s for all", Kit.Coin(sell or 0), Kit.Coin((sell or 0) * have)),
        string.format("|cffffd100Market buy price|r  %s", Kit.Coin(buy or 0)),
    }
    -- same lookup as Game:UseItem: item.use, item.buff, or an item key that is itself a buff key
    local buffKey = it.use or it.buff or P.sel
    local buff = D.BUFFS and D.BUFFS[buffKey]
    if buff then
        lines[#lines + 1] = string.format("|cff40ff40Use:|r %s - %s (%s)", buff.name or buffKey, buff.desc or "",
            ns.Util.Duration(buff.duration or 0))
    end
    R.stats:SetText(table.concat(lines, "\n"))

    R.use:SetShown(buff ~= nil)
    R.use:SetEnabledTip(have > 0, "You have none.")
    -- one anchor per button, rebuilt every time (stacking SetPoint calls made them overlap)
    R.sell1:ClearAllPoints()
    if buff then
        R.sell1:SetPoint("LEFT", R.use, "RIGHT", 4, 0)
    else
        R.sell1:SetPoint("TOPLEFT", R.stats, "BOTTOMLEFT", 0, -10)
    end
    R.sell10:ClearAllPoints()
    R.sell10:SetPoint("LEFT", R.sell1, "RIGHT", 4, 0)
    R.sellAll:ClearAllPoints()
    R.sellAll:SetPoint("LEFT", R.sell10, "RIGHT", 4, 0)
    R.market:ClearAllPoints()
    R.market:SetPoint("LEFT", R.sellAll, "RIGHT", 4, 0)
    R.sell1:SetEnabledTip(have >= 1, "You have none.")
    R.sell10:SetEnabledTip(have >= 10, "You have fewer than 10.")
    R.sellAll:SetEnabledTip(have >= 1, "You have none.")
    if P.confirmAll ~= P.sel or time() > (R.sellAll.confirmUntil or 0) then R.sellAll:SetText("Sell all") end

    R.usedHeader:ClearAllPoints()
    R.usedHeader:SetPoint("TOPLEFT", R.sell1, "BOTTOMLEFT", 0, -14)
    R.usedHeader:SetPoint("RIGHT", R, "RIGHT", 0, 0)
    local used = UsedIn(P.sel)
    if #used == 0 then
        R.used:SetText(buff and "|cff9d9d9dNothing - use it for its buff, or sell it.|r" or "|cff9d9d9dNo recipe needs it. Sell it.|r")
    else
        R.used:SetText(table.concat(used, "\n"))
    end

    R.srcHeader:ClearAllPoints()
    R.srcHeader:SetPoint("TOPLEFT", R.used, "BOTTOMLEFT", -2, -12)
    R.srcHeader:SetPoint("RIGHT", R, "RIGHT", 0, 0)
    R.src:SetText(table.concat(Sources(P.sel, it), "\n"))
end

------------------------------------------------------------------------
-- tab
------------------------------------------------------------------------

local function Build(panel)
    P.gridHeader = Kit.Header(panel, "Bags", LEFT_W)
    P.gridHeader:SetPoint("TOPLEFT", 0, 0)
    -- filter bar: kind buttons, sort, search
    P.filterButtons = {}
    local prev
    for _, f in ipairs(FILTERS) do
        local b = Kit.Button(panel, f.name, f.key == "USE" and 92 or (f.key == "MATS" and 78 or 52), 20, function()
            P.filter = f.key
            UI.Refresh()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 4, -22) end
        b.key = f.key
        P.filterButtons[#P.filterButtons + 1] = b
        prev = b
    end
    P.sortButton = Kit.Button(panel, "Sort: Type", 100, 20, function()
        P.sort = P.sort % #SORTS + 1
        UI.Refresh()
    end, "Click to sort by type, value, name or amount.")
    P.sortButton:SetPoint("LEFT", prev, "RIGHT", 8, 0)

    local ok, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
    if not ok then box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate") end
    box:SetSize(120, 20)
    box:SetPoint("LEFT", P.sortButton, "RIGHT", 10, 0)
    box:SetPoint("RIGHT", panel, "LEFT", LEFT_W - 4, 0)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self)
        local t = string.lower(strtrim and strtrim(self:GetText() or "") or (self:GetText() or ""))
        if t ~= P.search then
            P.search = t
            UI.Refresh()
        end
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    P.searchBox = box

    P.grid = Kit.List(panel, { rowHeight = SLOT + GAP, build = BuildGridRow, update = UpdateGridRow, stripes = false })
    P.grid:SetPoint("TOPLEFT", 0, -46)
    P.grid:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)
    P.grid:SetWidth(LEFT_W)
    BuildDetail(panel)
end

local function Refresh()
    if not P.grid then return end
    for _, b in ipairs(P.filterButtons) do
        if b.key == P.filter then b:LockHighlight() else b:UnlockHighlight() end
    end
    P.sortButton:SetText("Sort: " .. SORTS[P.sort])
    local slots, total, worth, nGear = BuildSlots()
    P.gearById = {}
    for _, s in ipairs(slots) do if s.gear then P.gearById[s.gear.id] = s.gear end end
    P.grid:SetData(ToRows(slots))
    local filtered = P.filter ~= "ALL" or P.search ~= ""
    P.gridHeader.right:SetText(string.format("%s%d items, %d gear  |cff9d9d9dworth|r %s",
        filtered and string.format("|cffffd100%d shown|r  -  ", #slots) or "", total, nGear, Kit.Coin(worth, true)))
    if P.sel and (Kit.Call("Count", P.sel) or 0) == 0 then P.sel = nil end
    RefreshDetail()
end

UI._bags = P   -- for the headless smoke test
UI.RegisterTab({ key = "BAGS", title = "Bags", order = 1.5, build = Build, refresh = Refresh })
