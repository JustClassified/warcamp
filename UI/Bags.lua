-- Warcamp: the Bags tab - everything the camp owns in one place.
-- Left top: bag slots grouped by kind (ore, herbs, ... potions, food). Left bottom: spare gear with
-- the hero it would upgrade most, Equip and Sell. Right: the selected item - value, what it is used
-- for, where it comes from, Use / Sell.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local D = ns.D

local LEFT_W = 580
local SLOT, GAP = 34, 4
local PER_ROW = math.floor((LEFT_W - 16) / (SLOT + GAP))
local GRID_H = 290
local ROW_H = 20

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

local P = {}

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

-- grid rows: { head=kindKey, count=, kinds= } or { items={entry, ...} }
local function BuildGrid()
    local byKind, total, worth = {}, 0, 0
    for _, e in ipairs(Kit.Call("GetInventory") or {}) do
        local kind = KIND_NAME[e.item.kind or ""] and e.item.kind or "MISC"
        byKind[kind] = byKind[kind] or {}
        table.insert(byKind[kind], e)
        total = total + e.count
        worth = worth + SellPrice(e.key) * e.count
    end
    local rows = {}
    for _, k in ipairs(KINDS) do
        local list = byKind[k.key]
        if list then
            table.sort(list, function(a, b)
                if (a.item.tier or 0) ~= (b.item.tier or 0) then return (a.item.tier or 0) > (b.item.tier or 0) end
                return (a.item.name or a.key) < (b.item.name or b.key)
            end)
            local n = 0
            for _, e in ipairs(list) do n = n + e.count end
            rows[#rows + 1] = { head = k.key, count = n, kinds = #list }
            for i = 1, #list, PER_ROW do
                local r = { items = {} }
                for j = i, math.min(i + PER_ROW - 1, #list) do r.items[#r.items + 1] = list[j] end
                rows[#rows + 1] = r
            end
        end
    end
    return rows, total, worth
end

------------------------------------------------------------------------
-- grid (left top)
------------------------------------------------------------------------

local function Select(key)
    P.sel = key
    P.confirmAll = nil
    UI.Refresh()
end

local function BuildGridRow(row)
    row.Head = Kit.Text(row, "GameFontNormal")
    row.Head:SetPoint("BOTTOMLEFT", 4, 3)
    row.HeadRight = Kit.Text(row, "GameFontDisableSmall", "RIGHT")
    row.HeadRight:SetPoint("BOTTOMRIGHT", -6, 4)
    row.Line = row:CreateTexture(nil, "ARTWORK")
    row.Line:SetPoint("BOTTOMLEFT", 0, 0)
    row.Line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.Line:SetHeight(1)
    row.Line:SetColorTexture(1, 0.82, 0, 0.3)
    row.Slots = {}
    for i = 1, PER_ROW do
        local b = Kit.ItemButton(row, SLOT)
        b:SetPoint("LEFT", 4 + (i - 1) * (SLOT + GAP), 0)
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
    local head = d.head ~= nil
    row.Head:SetShown(head); row.HeadRight:SetShown(head); row.Line:SetShown(head)
    if row.Stripe then row.Stripe:Hide() end
    if head then
        row.Head:SetText(KIND_NAME[d.head] or d.head)
        row.HeadRight:SetText(string.format("%d kind%s, %d total", d.kinds, d.kinds == 1 and "" or "s", d.count))
    end
    for i, b in ipairs(row.Slots) do
        local e = not head and d.items[i]
        if e then
            b:SetItemKey(e.key, e.count, { { "Sells for", Kit.Coin(SellPrice(e.key)) .. " each", 0.6, 0.6, 0.6, 1, 1, 1 } })
            b.spec.onClick = function() Select(e.key) end
            b.Sel:SetShown(P.sel == e.key)
            b:Show()
        else
            b:Clear()
            b:Hide()
        end
    end
end

------------------------------------------------------------------------
-- gear (left bottom)
------------------------------------------------------------------------

local function BuildGearRow(row)
    row.Item = Kit.ItemButton(row, ROW_H - 2)
    row.Item:SetPoint("LEFT", 2, 0)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Item, "RIGHT", 6, 0)
    row.Name:SetWidth(170)
    row.Slot = Kit.Text(row, "GameFontDisableSmall")
    row.Slot:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
    row.Slot:SetWidth(54)
    row.Ilvl = Kit.Text(row, "GameFontNormalSmall", "RIGHT")
    row.Ilvl:SetPoint("LEFT", row.Slot, "RIGHT", 0, 0)
    row.Ilvl:SetWidth(30)
    row.Up = Kit.Text(row, "GameFontHighlightSmall")
    row.Up:SetPoint("LEFT", row.Ilvl, "RIGHT", 10, 0)
    row.Up:SetWidth(120)
    row.Sell = Kit.Button(row, "Sell", 50, ROW_H - 2)
    row.Sell:SetPoint("RIGHT", -2, 0)
    row.Equip = Kit.Button(row, "Equip", 54, ROW_H - 2)
    row.Equip:SetPoint("RIGHT", row.Sell, "LEFT", -3, 0)
end

local function UpdateGearRow(row, g)
    row.Item:SetGear(g)
    row.Name:SetText("|c" .. Kit.QualityHex(g.quality or 1) .. (g.name or "?") .. "|r")
    row.Slot:SetText(SLOT_NAME[g.slot] or g.slot or "")
    row.Ilvl:SetText(tostring(g.ilvl or 0))
    local h, gain = BestUpgrade(g)
    if h then
        row.Up:SetText(string.format("|cff40ff40+%d|r %s", gain, Kit.HeroName(h)))
    else
        row.Up:SetText("|cff808080no upgrade|r")
    end
    row.Equip:SetEnabledTip(h ~= nil, h and nil or "Every recruit already wears something as good in this slot.")
    row.Equip:SetScript("OnClick", function()
        local best = BestUpgrade(g)
        if best then Kit.Do("Equip", best.id, g.id) end
    end)
    local value = Kit.Call("GearValue", g) or 0
    row.Sell:SetTip(function(tt) tt:SetText("Sell for " .. Kit.Coin(value), 1, 1, 1) end)
    if row.Sell.confirmFor ~= g.id then row.Sell:SetText("Sell") end
    row.Sell:SetScript("OnClick", function(btn)
        local now = time()
        if (g.quality or 1) < 4 or (btn.confirmFor == g.id and now <= (btn.confirmUntil or 0)) then
            btn.confirmFor = nil
            Kit.Do("SellGear", g.id)
        else
            btn.confirmFor, btn.confirmUntil = g.id, now + 3
            btn:SetText("Sure?")
        end
    end)
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

local function RefreshDetail()
    local R = P.detail
    local it = P.sel and Kit.Item(P.sel)
    local have = P.sel and (Kit.Call("Count", P.sel) or 0) or 0
    local show = it ~= nil
    for _, w in ipairs({ R.item, R.name, R.sub, R.stats, R.use, R.sell1, R.sell10, R.sellAll, R.market,
                         R.usedHeader, R.used, R.srcHeader, R.src }) do w:SetShown(show) end
    R.empty:SetShown(not show)
    if not show then
        R.header:SetText("Item")
        R.empty:SetText("Click an item in your bags to see what it is worth, what it is used for and where to get more.")
        return
    end

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
    if buff then
        R.sell1:SetPoint("LEFT", R.use, "RIGHT", 4, 0)
    else
        R.sell1:ClearAllPoints()
        R.sell1:SetPoint("TOPLEFT", R.stats, "BOTTOMLEFT", 0, -10)
    end
    R.sell10:SetPoint("LEFT", R.sell1, "RIGHT", 4, 0)
    R.sellAll:SetPoint("LEFT", R.sell10, "RIGHT", 4, 0)
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
    P.grid = Kit.List(panel, { rowHeight = SLOT + GAP, build = BuildGridRow, update = UpdateGridRow, stripes = false })
    P.grid:SetPoint("TOPLEFT", 0, -22)
    P.grid:SetSize(LEFT_W, GRID_H)
    P.gridEmpty = Kit.Text(panel, "GameFontDisable", "CENTER")
    P.gridEmpty:SetPoint("CENTER", P.grid, "CENTER", 0, 0)
    P.gridEmpty:SetText("Your bags are empty. Gathering, quests and the Mine fill them.")

    P.gearHeader = Kit.Header(panel, "Spare gear", LEFT_W)
    P.gearHeader:SetPoint("TOPLEFT", 0, -(GRID_H + 30))
    P.gear = Kit.List(panel, { rowHeight = ROW_H, build = BuildGearRow, update = UpdateGearRow })
    P.gear:SetPoint("TOPLEFT", 0, -(GRID_H + 52))
    P.gear:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)
    P.gear:SetWidth(LEFT_W)
    P.gearEmpty = Kit.Text(panel, "GameFontDisable", "CENTER")
    P.gearEmpty:SetPoint("CENTER", P.gear, "CENTER", 0, 0)
    P.gearEmpty:SetText("No spare gear. Quests, dungeons, raids and the Forge drop it.")

    BuildDetail(panel)
end

local function Refresh()
    if not P.grid then return end
    local rows, total, worth = BuildGrid()
    P.grid:SetData(rows)
    P.gridEmpty:SetShown(#rows == 0)
    P.gridHeader.right:SetText(string.format("%d items  |cff9d9d9dworth|r %s", total, Kit.Coin(worth, true)))
    if P.sel and (Kit.Call("Count", P.sel) or 0) == 0 then
        -- keep showing a used-up item only while it still has somewhere to come from
        local still = false
        for _, r in ipairs(rows) do
            for _, e in ipairs(r.items or {}) do if e.key == P.sel then still = true end end
        end
        if not still then P.sel = nil end
    end

    local bag = Kit.Call("GetGearBag") or {}
    P.gear:SetData(bag)
    P.gearEmpty:SetShown(#bag == 0)
    local value = 0
    for _, g in ipairs(bag) do value = value + (Kit.Call("GearValue", g) or 0) end
    P.gearHeader.right:SetText(string.format("%d piece%s  |cff9d9d9dworth|r %s", #bag, #bag == 1 and "" or "s", Kit.Coin(value, true)))

    RefreshDetail()
end

UI._bags = P   -- for the headless smoke test
UI.RegisterTab({ key = "BAGS", title = "Bags", order = 1.5, build = Build, refresh = Refresh })
