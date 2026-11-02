-- Warcamp: the Market tab, styled after the auction house.
-- Left: category + tier filter. Centre: dense item rows (owned, buy, sell, 24 h trend), sortable.
-- Right: the selected item with a 24 h price chart, buy/sell buttons, and the gear bag (sell gear).

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D

local NAV_W = 150
local DETAIL_W = 300
local ROW_H = 20
local CHART_W, CHART_H = 284, 96
local CHART_N, CHART_SPAN = 48, 86400

-- category order; kinds as in D.ITEMS
local CATEGORIES = {
    { key = "ALL", name = "All goods" },
    { key = "ORE", name = "Ore" }, { key = "HERB", name = "Herbs" }, { key = "LEATHER", name = "Leather" },
    { key = "FISH", name = "Fish" }, { key = "CLOTH", name = "Cloth" }, { key = "BAR", name = "Bars" },
    { key = "POTION", name = "Potions" }, { key = "FOOD", name = "Food" }, { key = "RARE", name = "Rare" },
}
local KIND_NAME = {}
for _, c in ipairs(CATEGORIES) do KIND_NAME[c.key] = c.name end

local P = { cat = "ALL", tier = nil, sort = "name", desc = false, ticks = 0 }

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function TierName(t)
    local d = D.TIERS and D.TIERS[t]
    return d and d.name or ("Tier " .. tostring(t or "?"))
end

local function Trend(key)
    local h = Kit.Call("PriceHistory", key, 2, CHART_SPAN)
    if type(h) ~= "table" or not h[1] or not h[2] or h[1] <= 0 then return 0 end
    return (h[2] - h[1]) / h[1]
end

local function FillEntry(e, now)
    local buy, sell = Kit.Call("Price", e.key, now)
    e.buy, e.sell = buy or 0, sell or 0
    e.owned = Kit.Call("Count", e.key) or 0
    e.trend = Trend(e.key)
end

local function TrendText(tr)
    local pct = tr * 100
    if math.abs(pct) < 0.05 then return "|cff9d9d9d0.0%|r" end
    if pct > 0 then return string.format("|cff40ff40+%.1f%%|r", pct) end
    return string.format("|cffff4040%.1f%%|r", pct)
end

-- the auction house sort arrow, tinted; fallback a small coloured square
local function SetTrendArrow(tex, tr)
    if math.abs(tr) < 0.0005 then tex:Hide(); return end
    tex:Show()
    if not tex.wcAtlas then
        tex.wcAtlas = Kit.Atlas(tex, "auctionhouse-ui-sortarrow") and 1 or 0
    end
    if tex.wcAtlas == 1 then
        if tr > 0 then tex:SetTexCoord(0, 1, 1, 0) else tex:SetTexCoord(0, 1, 0, 1) end
        if tr > 0 then tex:SetVertexColor(0.25, 1, 0.25) else tex:SetVertexColor(1, 0.25, 0.25) end
    else
        if tr > 0 then tex:SetColorTexture(0.25, 1, 0.25, 0.9) else tex:SetColorTexture(1, 0.25, 0.25, 0.9) end
    end
end

------------------------------------------------------------------------
-- data
------------------------------------------------------------------------

local SORTERS = {
    name = function(a, b) return (a.item.name or a.key) < (b.item.name or b.key) end,
    owned = function(a, b) return a.owned < b.owned end,
    buy = function(a, b) return a.buy < b.buy end,
    sell = function(a, b) return a.sell < b.sell end,
    trend = function(a, b) return a.trend < b.trend end,
}

local function BuildData()
    local now = time()
    local out = {}
    for key, it in pairs(D.ITEMS or {}) do
        if (P.cat == "ALL" or it.kind == P.cat) and (not P.tier or it.tier == P.tier) then
            local e = { key = key, item = it }
            FillEntry(e, now)
            out[#out + 1] = e
        end
    end
    local f = SORTERS[P.sort] or SORTERS.name
    table.sort(out, function(a, b)
        local ta, tb = a.item.tier or 0, b.item.tier or 0
        if P.sort == "name" and ta ~= tb then
            if P.desc then return ta > tb end
            return ta < tb
        end
        if f(a, b) then return not P.desc end
        if f(b, a) then return P.desc end
        return a.key < b.key
    end)
    return out
end

------------------------------------------------------------------------
-- nav (left)
------------------------------------------------------------------------

local function NavButton(parent, text, onClick, secondary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_W - 8, 20)
    b.Normal = b:CreateTexture(nil, "BACKGROUND")
    b.Normal:SetAllPoints()
    b.Sel = b:CreateTexture(nil, "BORDER")
    b.Sel:SetAllPoints()
    b.Sel:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local base = secondary and "auctionhouse-nav-button-secondary" or "auctionhouse-nav-button"
    Kit.Atlas(b.Normal, base, { 0.15, 0.12, 0.08, 0.9 })
    Kit.Atlas(b.Sel, base .. "-select", { 1, 0.82, 0, 0.25 })
    if Kit.Atlas(hl, base .. "-highlight", { 1, 1, 1, 0.08 }) then hl:SetBlendMode("ADD") end
    b.Text = Kit.Text(b, "GameFontNormalSmall")
    b.Text:SetPoint("LEFT", secondary and 16 or 10, 0)
    b.Text:SetPoint("RIGHT", -6, 0)
    b.Text:SetText(text)
    b:SetScript("OnClick", onClick)
    function b:SetSelected(on)
        self.Sel:SetShown(on)
        if on then self.Text:SetTextColor(1, 1, 1) else self.Text:SetTextColor(1, 0.82, 0) end
    end
    return b
end

local function UpdateNav()
    for _, b in ipairs(P.navs) do b:SetSelected(b.cat == P.cat) end
    P.tierBtn.Text:SetText("Tier: " .. (P.tier and TierName(P.tier) or "All"))
    P.tierBtn:SetSelected(P.tier ~= nil)
end

local function OpenTierMenu(owner)
    local entries = { { text = "All tiers", func = function() P.tier = nil; UI.Refresh() end } }
    for i = 1, #(D.TIERS or {}) do
        local t = i
        entries[#entries + 1] = { text = (P.tier == t and "|cffffffff" or "") .. TierName(t) .. (P.tier == t and "|r" or ""),
            func = function() P.tier = t; UI.Refresh() end }
    end
    Kit.Menu(owner, "Tier", entries)
end

------------------------------------------------------------------------
-- item list (centre)
------------------------------------------------------------------------

local COLS = {   -- x offset, width, justify, sort key, title
    { 24, 144, "LEFT", "name", "Name" },
    { 170, 36, "RIGHT", "owned", "Owned" },
    { 208, 74, "RIGHT", "buy", "Buy" },
    { 284, 74, "RIGHT", "sell", "Sell" },
    { 372, 48, "RIGHT", "trend", "24 h" },
}

local function BuildItemRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Cols = {}
    for i, c in ipairs(COLS) do
        local fs = Kit.Text(row, "GameFontHighlightSmall", c[3])
        fs:SetPoint("LEFT", c[1], 0)
        fs:SetWidth(c[2])
        row.Cols[i] = fs
    end
    row.Arrow = row:CreateTexture(nil, "OVERLAY")
    row.Arrow:SetSize(9, 9)
    row.Arrow:SetPoint("RIGHT", row.Cols[5], "LEFT", -1, 0)
end

local function UpdateItemRow(row, e)
    local it = e.item
    row.Icon:SetTexture(ns.ItemIcon(it.itemID, it.icon))
    local c = row.Cols
    c[1]:SetText(string.format("|c%s%s|r", Kit.QualityHex(it.quality or 1), it.name or e.key))
    c[2]:SetText(e.owned > 0 and tostring(e.owned) or "|cff606060-|r")
    c[3]:SetText(Kit.Coin(e.buy, true))
    c[4]:SetText(Kit.Coin(e.sell, true))
    c[5]:SetText(TrendText(e.trend))
    SetTrendArrow(row.Arrow, e.trend)
end

local function ItemTooltip(tt, row, e)
    local it = e.item
    local r, g, b = ns.QUALITY_COLOR(it.quality or 1)
    tt:SetText(it.name or e.key, r, g, b)
    tt:AddLine((KIND_NAME[it.kind or ""] or it.kind or "") .. "  -  " .. TierName(it.tier), 0.8, 0.8, 0.8)
    tt:AddDoubleLine("Buy", Kit.Coin(e.buy), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Sell", Kit.Coin(e.sell), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Last 24 h", TrendText(e.trend), 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Owned", tostring(e.owned), 1, 1, 1, 1, 1, 1)
end

local function HeaderButton(parent, col)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(col[2] + (col[4] == "name" and 20 or 0), 18)
    b:SetPoint("LEFT", col[1] - (col[4] == "name" and 20 or 0), 0)
    b.Text = Kit.Text(b, "GameFontNormalSmall", col[3])
    b.Text:SetPoint("LEFT", col[4] == "name" and 20 or 0, 0)
    b.Text:SetPoint("RIGHT", 0, 0)
    b.Text:SetText(col[5])
    b.Arrow = b:CreateTexture(nil, "OVERLAY")
    b.Arrow:SetSize(9, 9)
    if col[3] == "RIGHT" then
        b.Arrow:SetPoint("RIGHT", b.Text, "RIGHT", -(b.Text:GetStringWidth() + 2), 0)
    else
        b.Arrow:SetPoint("LEFT", b.Text, "LEFT", b.Text:GetStringWidth() + 3, 0)
    end
    if not Kit.Atlas(b.Arrow, "auctionhouse-ui-sortarrow") then b.Arrow:SetColorTexture(1, 0.82, 0, 0.8) end
    b.Arrow:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.sortKey = col[4]
    b:SetScript("OnClick", function(self)
        if P.sort == self.sortKey then P.desc = not P.desc
        else P.sort, P.desc = self.sortKey, self.sortKey ~= "name" end
        UI.Refresh()
    end)
    return b
end

local function UpdateHeaders()
    for _, b in ipairs(P.headers) do
        local on = b.sortKey == P.sort
        b.Arrow:SetShown(on)
        if on then b.Arrow:SetTexCoord(0, 1, P.desc and 0 or 1, P.desc and 1 or 0) end
        if on then b.Text:SetTextColor(1, 1, 1) else b.Text:SetTextColor(1, 0.82, 0) end
    end
end

------------------------------------------------------------------------
-- price chart
------------------------------------------------------------------------

local function ChartLine(chart, i)
    local l = chart.lines[i]
    if l == false then return nil end
    if not l then
        local ok, obj = pcall(chart.CreateLine, chart, nil, "ARTWORK")
        if not ok or not obj or not pcall(obj.SetThickness, obj, 2) then
            chart.lines[i] = false
            chart.noLines = true
            return nil
        end
        obj:SetColorTexture(1, 1, 1, 1)
        chart.lines[i] = obj
        l = obj
    end
    return l
end

local function DrawChart(chart, hist)
    ChartLine(chart, 1)   -- probe once, so the bar style knows whether lines exist
    local n = #hist
    local lo, hi = math.huge, -math.huge
    for i = 1, n do lo = math.min(lo, hist[i]); hi = math.max(hi, hist[i]) end
    if n < 2 then
        for _, b in ipairs(chart.bars) do b:Hide() end
        for _, l in ipairs(chart.lines) do if l then l:Hide() end end
        chart.hi:SetText(""); chart.lo:SetText("")
        return
    end
    local pad = math.max(1, (hi - lo) * 0.12)
    local vlo, vhi = math.max(0, lo - pad), hi + pad
    local w, h = CHART_W, CHART_H
    local up = hist[n] >= hist[1]
    local r, g, b = up and 0.25 or 1, up and 1 or 0.3, up and 0.3 or 0.25
    local function Y(v) return (v - vlo) / math.max(1, vhi - vlo) * (h - 4) + 2 end
    local step = w / (n - 1)
    -- area bars (always; brighter when lines are not available)
    local bw = math.max(1, w / n)
    for i = 1, n do
        local bar = chart.bars[i]
        if not bar then
            bar = chart:CreateTexture(nil, "BORDER")
            chart.bars[i] = bar
        end
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (i - 1) * (w - bw) / (n - 1), 0)
        bar:SetSize(math.max(1, bw - 1), math.max(1, Y(hist[i])))
        bar:SetColorTexture(r, g, b, chart.noLines and 0.6 or 0.16)
        bar:Show()
    end
    for i = n + 1, #chart.bars do chart.bars[i]:Hide() end
    for i = 1, n - 1 do
        local l = ChartLine(chart, i)
        if l then
            l:ClearAllPoints()
            l:SetStartPoint("BOTTOMLEFT", chart, (i - 1) * step, Y(hist[i]))
            l:SetEndPoint("BOTTOMLEFT", chart, i * step, Y(hist[i + 1]))
            l:SetVertexColor(r, g, b, 1)
            l:Show()
        end
    end
    for i = n, #chart.lines do if chart.lines[i] then chart.lines[i]:Hide() end end
    chart.hi:SetText(Kit.Coin(hi, true))
    chart.lo:SetText(Kit.Coin(lo, true))
end

local function BuildChart(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(CHART_W, CHART_H)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -2, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    bg:SetColorTexture(0, 0, 0, 0.55)
    for i = 0, 2 do
        local gl = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        gl:SetHeight(1)
        gl:SetPoint("LEFT", 0, 0)
        gl:SetPoint("RIGHT", 0, 0)
        gl:SetPoint("BOTTOM", 0, math.floor(i * (CHART_H - 1) / 2))
        gl:SetColorTexture(1, 0.82, 0, 0.12)
    end
    c.lines, c.bars = {}, {}
    c.hi = Kit.Text(c, "GameFontHighlightSmall")
    c.hi:SetPoint("TOPLEFT", 3, -2)
    c.lo = Kit.Text(c, "GameFontHighlightSmall")
    c.lo:SetPoint("BOTTOMLEFT", 3, 2)
    c.hi:SetDrawLayer("OVERLAY", 2); c.lo:SetDrawLayer("OVERLAY", 2)
    local l = Kit.Text(c, "GameFontDisableSmall")
    l:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, -3)
    l:SetText("24 h ago")
    local r = Kit.Text(c, "GameFontDisableSmall", "RIGHT")
    r:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, -3)
    r:SetText("now")
    c:EnableMouse(true)
    Kit.SetTooltip(c, function(tt)
        tt:SetText("Sell price, last 24 hours", 1, 0.82, 0)
        tt:AddLine("Prices drift on their own and fall when you sell a lot; they recover over a few hours.", 1, 1, 1, true)
    end)
    return c
end

------------------------------------------------------------------------
-- detail (right)
------------------------------------------------------------------------

local UpdateDetail

local function Selected()
    if not P.selKey then return nil end
    for _, e in ipairs(P.list:GetData() or {}) do
        if e.key == P.selKey then return e end
    end
    local it = D.ITEMS and D.ITEMS[P.selKey]
    if not it then return nil end
    local e = { key = P.selKey, item = it }
    FillEntry(e, time())
    return e
end

local function Trade(isBuy, n)
    local e = Selected()
    if not e then return end
    local before = Kit.Call("Gold") or 0
    local name = e.item.name or e.key
    if isBuy then
        if Kit.Do("Buy", e.key, n) then
            UI.Status(string.format("Bought %dx %s for %s", n, name, Kit.Coin(before - (Kit.Call("Gold") or 0))), 0.3, 1, 0.3)
        end
    else
        local have = Kit.Call("Count", e.key) or 0
        local sold = (n == "ALL") and have or math.min(n, have)
        if Kit.Do("Sell", e.key, n) then
            UI.Status(string.format("Sold %dx %s for %s", sold, name, Kit.Coin((Kit.Call("Gold") or 0) - before)), 0.3, 1, 0.3)
        end
    end
end

local function SellAllLive(btn, now)
    if btn.confirmUntil and now > btn.confirmUntil then
        btn.confirmUntil = nil
        btn:SetText("Sell all")
    end
end

UpdateDetail = function()
    local R = P.detail
    local e = Selected()
    if not e then
        R.Body:Hide()
        R.Empty:Show()
        return
    end
    R.Empty:Hide()
    R.Body:Show()
    local it = e.item
    R.Icon:SetItemKey(e.key)
    R.Name:SetText(string.format("|c%s%s|r", Kit.QualityHex(it.quality or 1), it.name or e.key))
    R.Sub:SetText((KIND_NAME[it.kind or ""] or it.kind or "") .. "  -  " .. TierName(it.tier))
    local hist = Kit.Call("PriceHistory", e.key, CHART_N, CHART_SPAN) or {}
    DrawChart(R.Chart, hist)
    R.Buy:SetCopper(e.buy)
    R.Sell:SetCopper(e.sell)
    R.Owned:SetText(tostring(e.owned))
    R.Value:SetCopper(e.owned * e.sell)
    R.Trend:SetText(TrendText(e.trend))
    local bonus = Kit.Call("MarketBonus") or 0
    R.Bonus:SetText(bonus > 0 and string.format("Trading Post: %.1f%% better prices", bonus * 100) or "Build a Trading Post for better prices")

    local buffKey = it.use or it.buff
    local buff = buffKey and D.BUFFS and D.BUFFS[buffKey]
    if buff and (it.kind == "POTION" or it.kind == "FOOD") then
        R.Use:Show(); R.UseText:Show()
        R.UseText:SetText(Kit.IconMarkup(buff.icon, 14) .. " " .. (buff.name or buffKey) ..
            (buff.duration and ("  |cff9d9d9d" .. U.Duration(buff.duration) .. "|r") or ""))
        R.Use:SetEnabledTip(e.owned > 0, "You have none")
        R.Use:SetTip(function(tt)
            tt:SetText(buff.name or buffKey, 1, 0.82, 0)
            if buff.desc then tt:AddLine(buff.desc, 1, 1, 1, true) end
            if buff.duration then tt:AddLine("Lasts " .. U.Duration(buff.duration), 0.6, 0.8, 1) end
            tt:AddLine("Uses one " .. (it.name or e.key), 0.6, 0.6, 0.6)
        end)
    else
        R.Use:Hide(); R.UseText:Hide()
    end

    local gold = Kit.Call("Gold") or 0
    for _, b in ipairs(R.buyBtns) do
        local cost = e.buy * b.n
        b:SetEnabledTip(gold >= cost, "Not enough gold (" .. Kit.Coin(cost) .. ")")
        b:SetTip(string.format("Buy %d for %s", b.n, Kit.Coin(cost)))
    end
    for _, b in ipairs(R.sellBtns) do
        local n = b.n == "ALL" and e.owned or math.min(b.n, e.owned)
        b:SetEnabledTip(e.owned > 0, "You have none")
        if e.owned > 0 then
            b:SetTip(string.format("Sell %d for about %s%s", n, Kit.Coin(e.sell * n),
                n >= 20 and "\n|cff9d9d9dSelling many at once lowers the price a little.|r" or ""))
        end
    end
end

------------------------------------------------------------------------
-- gear bag (right, bottom)
------------------------------------------------------------------------

local SLOT_NAME = { HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs", FEET = "Feet", WEAPON = "Weapon", TRINKET = "Trinket" }

local function GearSellLive(btn, now)
    local row = btn:GetParent()
    if btn.confirmFor and (not row.data or btn.confirmFor ~= row.data.id or now > (btn.confirmUntil or 0)) then
        btn.confirmFor = nil
        btn:SetText("Sell")
    end
end

local function BuildGearRow(row)
    row.Item = Kit.ItemButton(row, 18)
    row.Item:SetPoint("LEFT", 2, 0)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Item, "RIGHT", 4, 0)
    row.Name:SetWidth(110)
    row.Ilvl = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Ilvl:SetPoint("LEFT", 134, 0)
    row.Ilvl:SetWidth(26)
    row.Ilvl:SetTextColor(1, 0.82, 0)
    row.Value = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Value:SetPoint("LEFT", 162, 0)
    row.Value:SetWidth(64)
    row.Btn = Kit.Button(row, "Sell", 44, 18, function(btn)
        local g = row.data
        if not g then return end
        local now = time()
        if btn.confirmFor == g.id and now <= (btn.confirmUntil or 0) then
            btn.confirmFor = nil
            btn:SetText("Sell")
            local copper = Kit.Do("SellGear", g.id)
            if copper then UI.Status(string.format("Sold %s for %s", g.name or "gear", Kit.Coin(tonumber(copper) or 0)), 0.3, 1, 0.3) end
        else
            btn.confirmFor, btn.confirmUntil = g.id, now + 3
            btn:SetText("Sure?")
        end
    end)
    row.Btn:SetPoint("RIGHT", -2, 0)
    Kit.Live(row.Btn, GearSellLive)
end

local function UpdateGearRow(row, g)
    row.Item:SetGear(g)
    row.Name:SetText(string.format("|c%s%s|r", Kit.QualityHex(g.quality or 1), g.name or "?"))
    row.Ilvl:SetText(tostring(g.ilvl or 0))
    row.Value:SetText(Kit.Coin(Kit.Call("GearValue", g) or 0, true))
    if row.Btn.confirmFor ~= g.id then row.Btn:SetText("Sell") end
end

local function GearTooltip(tt, row, g)
    local r, gg, b = ns.QUALITY_COLOR(g.quality or 1)
    tt:SetText(g.name or "?", r, gg, b)
    tt:AddLine("Item level " .. (g.ilvl or 0), 1, 0.82, 0)
    tt:AddLine(SLOT_NAME[g.slot] or g.slot or "", 1, 1, 1)
    tt:AddDoubleLine("Sells for", Kit.Coin(Kit.Call("GearValue", g) or 0), 1, 1, 1, 1, 1, 1)
    tt:AddLine("Equip gear on the Heroes tab.", 0.5, 0.5, 0.5)
end

------------------------------------------------------------------------
-- build / refresh
------------------------------------------------------------------------

local function Build(panel)
    -- nav
    local nav = Kit.Inset(panel)
    nav:SetPoint("TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    local nbg = nav:CreateTexture(nil, "BACKGROUND", nil, -6)
    nbg:SetPoint("TOPLEFT", 3, -3)
    nbg:SetPoint("BOTTOMRIGHT", -3, 3)
    if not Kit.Atlas(nbg, "auctionhouse-background-categories") then nbg:Hide() end
    P.navs = {}
    for i, c in ipairs(CATEGORIES) do
        local b = NavButton(nav, c.name, function()
            P.cat = c.key
            UI.Refresh()
        end)
        b.cat = c.key
        b:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 21)
        P.navs[i] = b
    end
    P.tierBtn = NavButton(nav, "Tier: All", function(self) OpenTierMenu(self) end, true)
    P.tierBtn:SetPoint("TOPLEFT", 4, -6 - #CATEGORIES * 21 - 8)
    P.tierBtn:SetScript("OnEnter", function(self)
        Kit.Tip(self, "Filter by tier", { "Click to choose a tier." })
    end)
    P.tierBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    P.gold = Kit.CoinText(nav, "GameFontHighlightSmall")
    P.gold:SetPoint("BOTTOMRIGHT", -8, 8)
    local gl = Kit.Text(nav, "GameFontNormalSmall")
    gl:SetPoint("BOTTOMLEFT", 8, 8)
    gl:SetText("Gold")

    -- centre list
    local mid = Kit.Inset(panel)
    mid:SetPoint("TOPLEFT", nav, "TOPRIGHT", 6, 0)
    mid:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(DETAIL_W + 6), 0)
    local mbg = mid:CreateTexture(nil, "BACKGROUND", nil, -6)
    mbg:SetPoint("TOPLEFT", 3, -3)
    mbg:SetPoint("BOTTOMRIGHT", -3, 3)
    if not Kit.Atlas(mbg, "auctionhouse-background-index") then mbg:Hide() end
    local hdr = CreateFrame("Frame", nil, mid)
    hdr:SetPoint("TOPLEFT", 4, -4)
    hdr:SetPoint("TOPRIGHT", -16, -4)
    hdr:SetHeight(18)
    P.headers = {}
    for i, c in ipairs(COLS) do P.headers[i] = HeaderButton(hdr, c) end
    P.list = Kit.List(mid, {
        rowHeight = ROW_H, build = BuildItemRow, update = UpdateItemRow, tooltip = ItemTooltip,
        selectable = true, key = function(e) return e.key end,
        onClick = function(row, e) P.selKey = e.key; UpdateDetail() end,
    })
    P.list:SetPoint("TOPLEFT", 4, -24)
    P.list:SetPoint("BOTTOMRIGHT", -4, 4)
    P.empty = Kit.Text(mid, "GameFontDisable", "CENTER")
    P.empty:SetPoint("CENTER")
    P.empty:SetText("No goods match this filter.")
    P.empty:Hide()

    -- detail
    local R = CreateFrame("Frame", nil, panel)
    R:SetPoint("TOPRIGHT", 0, 0)
    R:SetPoint("BOTTOMRIGHT", 0, 0)
    R:SetWidth(DETAIL_W)
    P.detail = R
    R.Empty = Kit.Text(R, "GameFontDisable", "CENTER")
    R.Empty:SetPoint("TOP", 0, -90)
    R.Empty:SetText("Select an item.")
    R.Body = CreateFrame("Frame", nil, R)
    R.Body:SetPoint("TOPLEFT")
    R.Body:SetPoint("TOPRIGHT")
    R.Body:SetHeight(266)
    local B = R.Body
    local head = B:CreateTexture(nil, "BACKGROUND")
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(46)
    if not Kit.Atlas(head, "auctionhouse-itemheaderframe") then head:SetColorTexture(0, 0, 0, 0.4) end
    R.Icon = Kit.ItemButton(B, 36)
    R.Icon:SetPoint("TOPLEFT", 6, -5)
    R.Name = Kit.Text(B, "GameFontNormal")
    R.Name:SetPoint("TOPLEFT", R.Icon, "TOPRIGHT", 8, -3)
    R.Name:SetPoint("RIGHT", -6, 0)
    R.Sub = Kit.Text(B, "GameFontHighlightSmall")
    R.Sub:SetPoint("TOPLEFT", R.Name, "BOTTOMLEFT", 0, -4)
    R.Sub:SetTextColor(0.75, 0.75, 0.75)

    R.Chart = BuildChart(B)
    R.Chart:SetPoint("TOPLEFT", 8, -54)

    local y = -54 - CHART_H - 20
    local function Line(label, x, yy)
        local l = Kit.Text(B, "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, yy)
        l:SetText(label)
        return l
    end
    Line("Buy", 8, y)
    R.Buy = Kit.CoinText(B)
    R.Buy:SetPoint("TOPRIGHT", B, "TOPLEFT", 146, y)
    Line("Sell", 156, y)
    R.Sell = Kit.CoinText(B)
    R.Sell:SetPoint("TOPRIGHT", B, "TOPLEFT", 292, y)
    y = y - 15
    Line("Owned", 8, y)
    R.Owned = Kit.Text(B, "GameFontHighlightSmall", "RIGHT")
    R.Owned:SetPoint("TOPRIGHT", B, "TOPLEFT", 146, y)
    Line("Worth", 156, y)
    R.Value = Kit.CoinText(B)
    R.Value:SetPoint("TOPRIGHT", B, "TOPLEFT", 292, y)
    y = y - 15
    Line("24 h", 8, y)
    R.Trend = Kit.Text(B, "GameFontHighlightSmall", "RIGHT")
    R.Trend:SetPoint("TOPRIGHT", B, "TOPLEFT", 146, y)
    R.Bonus = Kit.Text(B, "GameFontDisableSmall", "RIGHT")
    R.Bonus:SetPoint("TOPRIGHT", B, "TOPLEFT", 292, y)
    R.Bonus:SetWidth(140)

    y = y - 20
    R.buyBtns, R.sellBtns = {}, {}
    local bx = 8
    for _, n in ipairs({ 1, 10 }) do
        local b = Kit.Button(B, "Buy " .. n, 60, 20, function() Trade(true, n) end)
        b:SetPoint("TOPLEFT", bx, y)
        b.n = n
        bx = bx + 62
        R.buyBtns[#R.buyBtns + 1] = b
    end
    bx = bx + 6
    for _, n in ipairs({ 1, 10 }) do
        local b = Kit.Button(B, "Sell " .. n, 52, 20, function() Trade(false, n) end)
        b:SetPoint("TOPLEFT", bx, y)
        b.n = n
        bx = bx + 54
        R.sellBtns[#R.sellBtns + 1] = b
    end
    local all = Kit.Button(B, "Sell all", 56, 20, function(self)
        local now = time()
        if self.confirmUntil and now <= self.confirmUntil then
            self.confirmUntil = nil
            self:SetText("Sell all")
            Trade(false, "ALL")
        else
            self.confirmUntil = now + 3
            self:SetText("Sure?")
        end
    end)
    all:SetPoint("TOPLEFT", bx, y)
    all.n = "ALL"
    Kit.Live(all, SellAllLive)
    R.sellBtns[#R.sellBtns + 1] = all

    -- potions and food: use one (grants the item's buff)
    R.Use = Kit.Button(B, "Use", 60, 20, function()
        local e = Selected()
        if e and Kit.Do("UseItem", e.key) then UI.Status("Used " .. (e.item.name or e.key), 0.3, 1, 0.3) end
    end)
    R.Use:SetPoint("TOPLEFT", 8, y - 24)
    R.UseText = Kit.Text(B, "GameFontHighlightSmall")
    R.UseText:SetPoint("LEFT", R.Use, "RIGHT", 6, 0)
    R.UseText:SetPoint("RIGHT", B, "LEFT", 292, 0)

    -- gear bag
    P.gearHeader = Kit.Header(R, "Gear bag", DETAIL_W)
    P.gearHeader:SetPoint("TOPLEFT", 0, -272)
    P.gear = Kit.List(R, { rowHeight = ROW_H, build = BuildGearRow, update = UpdateGearRow, tooltip = GearTooltip,
        key = function(g) return g.id end })
    P.gear:SetPoint("TOPLEFT", 0, -294)
    P.gear:SetPoint("BOTTOMRIGHT", 0, 0)
    P.gearEmpty = Kit.Text(R, "GameFontDisableSmall", "CENTER")
    P.gearEmpty:SetPoint("TOP", P.gear, "TOP", 0, -20)
    P.gearEmpty:SetText("No spare gear. Loot and crafted gear lands here.")
end

local function Refresh(panel)
    UpdateNav()
    UpdateHeaders()
    local data = BuildData()
    P.list:SetData(data)
    P.empty:SetShown(#data == 0)
    if not P.selKey and data[1] then P.selKey = data[1].key end
    P.list:SetSelected(P.selKey)
    UpdateDetail()
    P.gold:SetCopper(Kit.Call("Gold") or 0, true)
    local bag = Kit.Call("GetGearBag") or {}
    P.gear:SetData(bag)
    P.gearEmpty:SetShown(#bag == 0)
    local total = 0
    for _, g in ipairs(bag) do total = total + (Kit.Call("GearValue", g) or 0) end
    P.gearHeader.right:SetText(#bag > 0 and string.format("%d items  -  %s", #bag, Kit.Coin(total, true)) or "")
end

-- prices drift: every 10 s re-price the rows in place (no re-sort, so nothing jumps under the mouse)
local function Tick(panel, now)
    P.ticks = P.ticks + 1
    if P.ticks % 20 ~= 0 then return end
    for _, e in ipairs(P.list:GetData() or {}) do FillEntry(e, now) end
    P.list:Refresh()
    UpdateDetail()
end

UI.RegisterTab({ key = "MARKET", title = "Market", order = 6, build = Build, refresh = Refresh, tick = Tick })
