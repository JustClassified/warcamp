-- Warcamp: the Camp tab. Left: active tasks (collect / cancel) over the camp log.
-- Right: the 12 buildings (upgrade, timers, Mine/Garden storage) over the Inn (3 recruits with models).

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D

local LEFT_W = 452          -- tasks + log column
local TOP_H = 268           -- tasks + buildings block
local TILE_W, TILE_H = 226, 39

local KIND_ICON = {
    GATHER = "Interface\\Icons\\Trade_Mining", QUEST = "Interface\\Icons\\INV_Misc_Map_01",
    DUNGEON = "Interface\\Icons\\INV_Sword_04", RAID = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    CRAFT = "Interface\\Icons\\Trade_BlackSmithing", BUILD = "Interface\\Icons\\Trade_Engineering",
}
local PROF_ICON = {
    MINING = "Interface\\Icons\\Trade_Mining", HERBALISM = "Interface\\Icons\\Trade_Herbalism",
    SKINNING = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", FISHING = "Interface\\Icons\\Trade_Fishing",
}
local KIND_NAME = { GATHER = "Gathering", QUEST = "Quest", DUNGEON = "Dungeon", RAID = "Raid", CRAFT = "Crafting", BUILD = "Construction" }

local P = {}   -- this tab's widgets

local function TaskIcon(t)
    return t.icon or (t.profession and PROF_ICON[t.profession]) or KIND_ICON[t.kind] or 134400
end

------------------------------------------------------------------------
-- active tasks
------------------------------------------------------------------------

local function UpdateTaskButton(row, now)
    local t, btn = row.data, row.Btn
    if not t then return end
    now = now or time()
    local ready = now >= (t.endAt or 0)
    if btn.confirmFor == t.id and now <= (btn.confirmUntil or 0) then
        btn:SetText("Sure?")
        btn:SetEnabledTip(true)
        btn:SetTip("Click again to cancel: the heroes come home with nothing")
        return
    end
    btn.confirmFor = nil
    if t.kind == "BUILD" then
        btn:SetText(ready and "Done" or "Cancel")
        btn:SetEnabledTip(not ready, "Finishing...")
        btn:SetTip(not ready and "Stop the construction (the cost is refunded)" or nil)
    elseif ready then
        btn:SetText("Collect")
        btn:SetEnabledTip(true)
        btn:SetTip("Collect the rewards")
    else
        btn:SetText("Cancel")
        btn:SetEnabledTip(true)
        btn:SetTip(t.kind == "CRAFT" and "Stop crafting (materials are refunded)" or "Call the heroes back (no rewards)")
    end
end

local function TaskButtonClick(btn)
    local row = btn:GetParent()
    local t = row.data
    if not t then return end
    local now = time()
    if t.kind ~= "BUILD" and now >= t.endAt then
        Kit.Do("Collect", t.id)
    elseif btn.confirmFor == t.id and now <= (btn.confirmUntil or 0) then
        btn.confirmFor = nil
        Kit.Call("Cancel", t.id)
    else
        btn.confirmFor, btn.confirmUntil = t.id, now + 3
        UpdateTaskButton(row, now)
    end
end

local function BuildTaskRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(18, 18)
    row.Icon:SetPoint("LEFT", 3, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 5, 0)
    row.Name:SetWidth(128)
    row.Heroes = {}
    for i = 1, 5 do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(14, 14)
        t:SetPoint("LEFT", 158 + (i - 1) * 15, 0)
        row.Heroes[i] = t
    end
    row.Bar = Kit.ProgressBar(row, 104, 14)
    row.Bar:SetPoint("LEFT", 236, 0)
    row.Chance = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Chance:SetPoint("LEFT", row.Bar, "RIGHT", 2, 0)
    row.Chance:SetWidth(32)
    row.Btn = Kit.Button(row, "Cancel", 58, 18, TaskButtonClick)
    row.Btn:SetPoint("RIGHT", -2, 0)
    Kit.Live(row.Btn, function(btn, now) UpdateTaskButton(btn:GetParent(), now) end)
end

local function UpdateTaskRow(row, t)
    row.Icon:SetTexture(TaskIcon(t))
    row.Name:SetText(t.name or "?")
    if t.repeatIt then row.Name:SetTextColor(0.55, 0.8, 1) else row.Name:SetTextColor(1, 1, 1) end
    local heroes = t.heroes or {}
    for i, tex in ipairs(row.Heroes) do
        local h = Kit.Hero(heroes[i])
        if h then Kit.ClassIcon(tex, h.class); tex:Show() else tex:Hide() end
    end
    row.Bar:SetTimes(t.startAt, t.endAt)
    if (t.kind == "CRAFT" or t.kind == "BUILD") or not t.chance then
        row.Chance:SetText("")
    else
        local r, g, b = Kit.ChanceColor(t.chance)
        row.Chance:SetText(string.format("%d%%", math.floor(t.chance * 100 + 0.5)))
        row.Chance:SetTextColor(r, g, b)
    end
    UpdateTaskButton(row, time())
end

local function TaskTooltip(tt, row, t)
    tt:SetText(t.name or "?", 1, 0.82, 0)
    tt:AddLine(KIND_NAME[t.kind] or t.kind or "", 0.8, 0.8, 0.8)
    for _, id in ipairs(t.heroes or {}) do
        local h = Kit.Hero(id)
        if h then tt:AddDoubleLine(Kit.ClassMarkup(h.class, 12) .. " " .. Kit.HeroName(h), "level " .. (h.level or 1), 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if t.chance and t.kind ~= "CRAFT" and t.kind ~= "BUILD" then
        local r, g, b = Kit.ChanceColor(t.chance)
        tt:AddDoubleLine("Success chance", string.format("%d%%", math.floor(t.chance * 100 + 0.5)), 1, 1, 1, r, g, b)
    end
    local now = time()
    if now >= t.endAt then
        tt:AddLine(t.kind == "BUILD" and "Finishing..." or "Ready to collect", 0.3, 1, 0.3)
    else
        tt:AddDoubleLine("Done at " .. U.Clock(t.endAt), "in " .. U.Duration(t.endAt - now), 1, 1, 1, 0.6, 0.8, 1)
    end
    if t.repeatIt then tt:AddLine("Repeats when collected (also while you are away, up to 24 h)", 0.55, 0.8, 1, true) end
end

------------------------------------------------------------------------
-- buildings
------------------------------------------------------------------------

local function CostText(cost)
    if not cost then return "" end
    local parts = {}
    if (cost.gold or 0) > 0 then parts[#parts + 1] = Kit.Coin(cost.gold, true) end
    local keys = {}
    for k in pairs(cost.items or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local it = Kit.Item(k)
        parts[#parts + 1] = cost.items[k] .. Kit.IconMarkup(it and ns.ItemIcon(it.itemID, it.icon), 12)
    end
    return table.concat(parts, " ")
end

local function BuildingTooltip(tt, tile)
    local info = tile.info
    if not info then return end
    local def = info.def or {}
    tt:SetText(def.name or info.key, 1, 0.82, 0)
    tt:AddLine(info.level > 0 and string.format("Level %d / %d", info.level, info.max) or "Not built yet", 0.8, 0.8, 0.8)
    if def.desc then tt:AddLine(def.desc, 1, 1, 1, true) end
    if info.level > 0 and info.effect then tt:AddLine("Now: " .. info.effect, 0.3, 1, 0.3, true) end
    if info.storage then
        local s = info.storage
        local it = Kit.Item(s.itemKey)
        tt:AddLine(string.format("Stored: %d / %d %s  (%d per hour)", s.have or 0, s.cap or 0, it and it.name or "", s.perHour or 0), 1, 0.82, 0.5, true)
    end
    if info.upgrading and info.endAt then
        tt:AddLine(string.format("Upgrading: done at %s (in %s)", U.Clock(info.endAt), U.Duration(info.endAt - time())), 0.6, 0.8, 1)
    elseif info.cost and info.level < info.max then
        tt:AddLine(" ")
        tt:AddLine(info.level == 0 and "Build:" or ("Upgrade to level " .. (info.level + 1) .. ":"), 1, 0.82, 0)
        if info.nextEffect then tt:AddLine(info.nextEffect, 0.55, 0.8, 1, true) end
        local gold = Kit.Call("Gold") or 0
        if (info.cost.gold or 0) > 0 then
            local ok = gold >= info.cost.gold
            tt:AddDoubleLine("Gold", Kit.Coin(info.cost.gold), 1, 1, 1, ok and 1 or 1, ok and 1 or 0.3, ok and 1 or 0.3)
        end
        for k, need in pairs(info.cost.items or {}) do
            local it = Kit.Item(k)
            local have = Kit.Call("Count", k) or 0
            local ok = have >= need
            tt:AddDoubleLine(Kit.IconMarkup(it and ns.ItemIcon(it.itemID, it.icon), 14) .. " " .. (it and it.name or k),
                string.format("%d / %d", have, need), 1, 1, 1, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
        end
        if (info.cost.time or 0) > 0 then tt:AddDoubleLine("Time", U.Duration(info.cost.time), 1, 1, 1, 1, 1, 1) end
    end
    if not info.canUpgrade and info.reason and not info.upgrading then tt:AddLine(info.reason, 1, 0.3, 0.3, true) end
end

local function BuildTile(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(TILE_W, TILE_H)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    Kit.RowHighlight(f)
    f:EnableMouse(true)
    Kit.SetTooltip(f, BuildingTooltip)

    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetSize(33, 33)
    f.Icon:SetPoint("LEFT", 3, 0)
    f.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.IconBorder = f:CreateTexture(nil, "OVERLAY")
    f.IconBorder:SetPoint("TOPLEFT", f.Icon, -1, 1)
    f.IconBorder:SetPoint("BOTTOMRIGHT", f.Icon, 1, -1)
    f.Level = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.Level:SetPoint("BOTTOMRIGHT", f.Icon, -1, 1)

    f.Btn = Kit.Button(f, "Upgrade", 62, 18, function(self)
        local info = f.info
        if info then Kit.Do("Upgrade", info.key) end
    end)
    f.Btn:SetPoint("TOPRIGHT", -3, -2)
    f.Cost = Kit.Text(f, "GameFontHighlightSmall", "RIGHT")
    f.Cost:SetPoint("BOTTOMRIGHT", -4, 4)
    f.Cost:SetWidth(96)

    f.Name = Kit.Text(f, "GameFontNormalSmall")
    f.Name:SetPoint("TOPLEFT", f.Icon, "TOPRIGHT", 5, -2)
    f.Name:SetPoint("RIGHT", f.Btn, "LEFT", -4, 0)

    f.Effect = Kit.Text(f, "GameFontDisableSmall")
    f.Effect:SetPoint("BOTTOMLEFT", f.Icon, "BOTTOMRIGHT", 5, 2)
    f.Effect:SetPoint("RIGHT", f.Cost, "LEFT", -2, 0)

    f.Bar = Kit.ProgressBar(f, 88, 12)
    f.Bar:SetPoint("BOTTOMLEFT", f.Icon, "BOTTOMRIGHT", 6, 2)
    f.Bar:Hide()
    f.Take = Kit.IconButton(f, 14, nil, function()
        local info = f.info
        if info then Kit.Do("CollectStorage", info.key) end
    end, "Collect into your bags")
    f.Take:SetPoint("LEFT", f.Bar, "RIGHT", 4, 0)
    f.Take:Hide()
    return f
end

local function UpdateTile(f, info, task)
    f.info = info
    local def = info.def or {}
    f.Icon:SetTexture(def.icon or 134400)
    f.Icon:SetDesaturated(info.level == 0)
    Kit.QualityBorder(f.IconBorder, info.level >= info.max and 4 or (info.level > 0 and 1 or 0))
    f.Level:SetText(info.level > 0 and tostring(info.level) or "")
    f.Name:SetText(string.format("%s |cff9d9d9d%d/%d|r", def.name or info.key, info.level, info.max))

    local barShown, takeShown = false, false
    if info.upgrading and info.endAt then
        local start = task and task.startAt or (info.endAt - ((info.cost and info.cost.time) or 60))
        f.Bar:SetTimes(start, info.endAt)
        barShown = true
    elseif info.storage then
        local s = info.storage
        f.Bar:SetValueText(s.have or 0, s.cap or 1)
        f.Bar:SetBarColor(0.7, 0.5, 0.1)
        barShown = true
        if (s.have or 0) >= 1 then
            local it = Kit.Item(s.itemKey)
            f.Take:SetIcon(it and ns.ItemIcon(it.itemID, it.icon) or 134400)
            takeShown = true
        end
    end
    f.Bar:SetShown(barShown)
    f.Take:SetShown(takeShown)
    f.Effect:SetShown(not barShown)
    if not barShown then
        f.Effect:SetText(info.level > 0 and (info.effect or "") or "Not built")
    end

    if info.upgrading then
        f.Btn:SetText("Building")
        f.Btn:SetEnabledTip(false, info.reason or "Under construction")
        f.Cost:SetText("")
    elseif info.level >= info.max or not info.cost then
        f.Btn:SetText("Max")
        f.Btn:SetEnabledTip(false, "Fully upgraded")
        f.Cost:SetText("")
    else
        f.Btn:SetText(info.level == 0 and "Build" or "Upgrade")
        f.Btn:SetEnabledTip(info.canUpgrade, info.reason)
        f.Btn:SetTip("Costs " .. CostText(info.cost) .. ((info.cost.time or 0) > 0 and ("  -  " .. U.Duration(info.cost.time)) or ""))
        f.Cost:SetText(CostText(info.cost))
        if info.canUpgrade then f.Cost:SetTextColor(1, 1, 1) else f.Cost:SetTextColor(0.6, 0.6, 0.6) end
    end
end

local function RefreshBuildings(tasks)
    local byBuilding = {}
    for _, t in ipairs(tasks or Kit.Call("GetTasks") or {}) do
        if t.kind == "BUILD" and t.building then byBuilding[t.building] = t end
    end
    local list = Kit.Call("GetBuildings") or {}
    for i, info in ipairs(list) do
        local tile = P.tiles[i]
        if not tile then
            tile = BuildTile(P.buildings)
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            tile:SetPoint("TOPLEFT", col * (TILE_W + 6), -22 - row * (TILE_H + 2))
            P.tiles[i] = tile
        end
        UpdateTile(tile, info, byBuilding[info.key])
        tile:Show()
    end
    for i = #list + 1, #P.tiles do P.tiles[i]:Hide() end
    local th
    for _, info in ipairs(list) do if info.key == "TOWN_HALL" then th = info.level end end
    P.buildHeader.right:SetText(th and ("Town Hall level " .. th) or "")
end

------------------------------------------------------------------------
-- inn
------------------------------------------------------------------------

local function CountersLine(class)
    local def = D.CLASSES and D.CLASSES[class]
    if not def or not def.counters then return "" end
    local parts = {}
    for _, k in ipairs(def.counters) do
        local t = D.THREATS and D.THREATS[k]
        if t then parts[#parts + 1] = Kit.IconMarkup(t.icon, 13) end
    end
    return "Counters " .. table.concat(parts, " ")
end

local function BuildCard(parent, i)
    local c = Kit.Inset(parent)
    c:SetSize(186, 222)
    c.Model = Kit.ModelView(c, 180, 104)
    c.Model:SetPoint("TOP", 0, -3)
    c.Name = Kit.Text(c, "GameFontNormal", "CENTER")
    c.Name:SetPoint("TOPLEFT", 4, -110)
    c.Name:SetPoint("TOPRIGHT", -4, -110)
    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetSize(160, 3)
    line:SetPoint("TOP", c.Name, "BOTTOM", 0, -2)
    if not Kit.Atlas(line, "Headhunter_LineHeader") then line:SetColorTexture(1, 0.82, 0, 0.25) end
    c.Info = Kit.Text(c, "GameFontHighlightSmall", "CENTER")
    c.Info:SetPoint("TOPLEFT", 4, -130)
    c.Info:SetPoint("TOPRIGHT", -4, -130)
    c.Role = Kit.Text(c, "GameFontHighlightSmall", "CENTER")
    c.Role:SetPoint("TOPLEFT", 4, -144)
    c.Role:SetPoint("TOPRIGHT", -4, -144)
    c.Traits = {}
    for j = 1, 3 do
        local t = Kit.Text(c, "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", 8, -158 - (j - 1) * 13)
        t:SetPoint("RIGHT", -6, 0)
        c.Traits[j] = t
    end
    c.Cost = Kit.CoinText(c, "GameFontHighlightSmall")
    c.Cost:SetJustifyH("LEFT")
    c.Cost:SetPoint("BOTTOMLEFT", 8, 8)
    c.Btn = Kit.Button(c, "Recruit", 70, 18, function() Kit.Do("Recruit", c.index) end)
    c.Btn:SetPoint("BOTTOMRIGHT", -5, 5)
    c.Gone = Kit.Text(c, "GameFontDisable", "CENTER")
    c.Gone:SetPoint("CENTER", 0, -20)
    c.Gone:SetText("This recruit joined you")
    c.Gone:Hide()
    -- tooltip over the text part (the model keeps drag-to-turn)
    local hover = CreateFrame("Frame", nil, c)
    hover:SetPoint("TOPLEFT", 0, -108)
    hover:SetPoint("BOTTOMRIGHT", 0, 26)
    hover:EnableMouse(true)
    Kit.SetTooltip(hover, function(tt)
        if c.offer then
            Kit.HeroTooltip(tt, c.offer, { noStatus = true })
            tt:AddLine(" ")
            tt:AddDoubleLine("Cost", Kit.Coin(c.offer.cost or 0), 1, 0.82, 0, 1, 1, 1)
        end
    end)
    c.index = i
    return c
end

local function UpdateCard(c, offer, i, full, gold)
    c.index, c.offer = i, offer
    if not offer then
        c.Model:Clear()
        c.Name:SetText(""); c.Info:SetText(""); c.Role:SetText(""); c.Cost:SetText("")
        for _, t in ipairs(c.Traits) do t:SetText("") end
        c.Btn:Hide()
        c.Gone:Show()
        return
    end
    c.Gone:Hide()
    c.Btn:Show()
    local look = Kit.Call("HeroLook", offer)
    local display = look and look.display
    if not display then
        local looks = D.LOOKS and D.LOOKS[offer.class]
        local l = looks and (looks[offer.look or 1] or looks[1])
        display = l and l.display
    end
    local icon = offer.class and ("Interface\\Icons\\ClassIcon_" .. offer.class) or nil
    c.Model:SetDisplay(display, icon)
    local r, g, b = Kit.ClassColor(offer.class)
    c.Name:SetText(offer.name or "?")
    c.Name:SetTextColor(r, g, b)
    local q = offer.quality or 2
    local cls = D.CLASSES and D.CLASSES[offer.class]
    c.Info:SetText(string.format("|c%sLevel %d %s|r %s %s", Kit.QualityHex(q), offer.level or 1, D.QUALITY and D.QUALITY[q] or "",
        ns.Util.RaceName(offer.race), cls and cls.name or (offer.class or "")))
    local role = D.ROLES and D.ROLES[offer.role]
    c.Role:SetText(Kit.RoleMarkup(offer.role, 13) .. " " .. (role and role.name or "") .. "   " .. CountersLine(offer.class))
    local traits = offer.traits or {}
    for j, t in ipairs(c.Traits) do
        local def = traits[j] and D.TRAITS and D.TRAITS[traits[j]]
        if def then
            t:SetText(Kit.IconMarkup(def.icon, 12) .. " " .. (def.name or traits[j]))
            if (def.value or 0) < 0 then t:SetTextColor(1, 0.45, 0.4) else t:SetTextColor(0.45, 1, 0.45) end
        else
            t:SetText("")
        end
    end
    c.Cost:SetCopper(offer.cost or 0, true)
    local reason
    if full then reason = "The barracks are full. Upgrade the Barracks or dismiss a hero."
    elseif gold < (offer.cost or 0) then reason = "Not enough gold." end
    c.Btn:SetEnabledTip(reason == nil, reason)
    if reason then c.Cost:SetTextColor(1, 0.4, 0.4) else c.Cost:SetTextColor(1, 1, 1) end
end

local function RefreshInn()
    local data = Kit.Call("GetRecruitOffers") or {}
    local offers = data.offers or {}
    P.innRefreshAt = data.refreshAt
    local heroes = Kit.Call("GetHeroes") or {}
    local maxH = Kit.Call("MaxHeroes") or 0
    local full = maxH > 0 and #heroes >= maxH
    local gold = Kit.Call("Gold") or 0
    for i = 1, 3 do UpdateCard(P.cards[i], offers[i], i, full, gold) end
    P.innHeader:SetText(string.format("The Inn  |cff9d9d9d- heroes %d / %d|r", #heroes, maxH))
    local cost = Kit.Call("RerollCost") or 0
    P.reroll:SetTip("New faces now for " .. Kit.Coin(cost))
    P.reroll:SetEnabledTip(gold >= cost, "Not enough gold (" .. Kit.Coin(cost) .. ")")
end

local function InnTimer(now)
    if P.innRefreshAt then
        P.innHeader.right:SetText("New faces in " .. U.Duration(P.innRefreshAt - (now or time())))
    else
        P.innHeader.right:SetText("")
    end
end

------------------------------------------------------------------------
-- tab
------------------------------------------------------------------------

local function Build(panel)
    -- tasks (top left)
    P.taskHeader = Kit.Header(panel, "Active tasks", LEFT_W)
    P.taskHeader:SetPoint("TOPLEFT", 0, 0)
    P.collectAll = Kit.Button(panel, "Collect all", 80, 18, function()
        local rep = Kit.Do("CollectAll")
        if type(rep) == "table" then UI.ShowReport(rep, "Collected") end
    end)
    P.collectAll:SetPoint("TOPRIGHT", P.taskHeader, "TOPRIGHT", 0, 1)
    P.taskHeader.right:ClearAllPoints()
    P.taskHeader.right:SetPoint("RIGHT", P.collectAll, "LEFT", -8, 0)
    P.tasks = Kit.List(panel, { rowHeight = 22, build = BuildTaskRow, update = UpdateTaskRow, tooltip = TaskTooltip })
    P.tasks:SetPoint("TOPLEFT", 0, -22)
    P.tasks:SetSize(LEFT_W, TOP_H - 22)
    P.taskEmpty = Kit.Text(panel, "GameFontDisable", "CENTER")
    P.taskEmpty:SetPoint("CENTER", P.tasks, "CENTER", 0, 10)
    P.taskEmpty:SetText("Nobody is out. Send heroes from the Missions or Dungeons tab.")

    -- camp log (bottom left)
    P.logHeader = Kit.Header(panel, "Camp log", LEFT_W)
    P.logHeader:SetPoint("TOPLEFT", 0, -TOP_H - 6)
    P.log = Kit.List(panel, {
        rowHeight = 18,
        build = function(row)
            row.Time = Kit.Text(row, "GameFontDisableSmall")
            row.Time:SetPoint("LEFT", 4, 0)
            row.Time:SetWidth(36)
            row.Text = Kit.Text(row, "GameFontHighlightSmall")
            row.Text:SetPoint("LEFT", row.Time, "RIGHT", 4, 0)
            row.Text:SetPoint("RIGHT", -4, 0)
        end,
        update = function(row, e)
            row.Time:SetText(e.t and U.Clock(e.t) or "")
            row.Text:SetText(e.text or "")
        end,
        tooltip = function(tt, row, e)
            if row.Text:IsTruncated() then
                tt:SetText(e.t and date("%a %H:%M", e.t) or "", 0.6, 0.6, 0.6)
                tt:AddLine(e.text or "", 1, 1, 1, true)
            end
        end,
    })
    P.log:SetPoint("TOPLEFT", 0, -TOP_H - 28)
    P.log:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", LEFT_W, 0)

    -- buildings (top right)
    P.buildings = CreateFrame("Frame", nil, panel)
    P.buildings:SetPoint("TOPLEFT", LEFT_W + 12, 0)
    P.buildings:SetPoint("TOPRIGHT", 0, 0)
    P.buildings:SetHeight(TOP_H)
    P.buildHeader = Kit.Header(P.buildings, "Buildings", TILE_W * 2 + 6)
    P.buildHeader:SetPoint("TOPLEFT", 0, 0)
    P.tiles = {}

    -- inn (bottom right)
    P.inn = CreateFrame("Frame", nil, panel)
    P.inn:SetPoint("TOPLEFT", LEFT_W + 12, -TOP_H - 6)
    P.inn:SetPoint("BOTTOMRIGHT", 0, 0)
    P.innHeader = Kit.Header(P.inn, "The Inn", TILE_W * 2 + 6)
    P.innHeader:SetPoint("TOPLEFT", 0, 0)
    P.reroll = Kit.Button(P.inn, "Reroll", 64, 18, function() Kit.Do("RerollRecruits") end)
    P.reroll:SetPoint("TOPRIGHT", P.innHeader, "TOPRIGHT", 0, 1)
    P.innHeader.right:ClearAllPoints()
    P.innHeader.right:SetPoint("RIGHT", P.reroll, "LEFT", -8, 0)
    P.cards = {}
    for i = 1, 3 do
        local c = BuildCard(P.inn, i)
        c:SetPoint("TOPLEFT", (i - 1) * 153, -22)
        c:SetWidth(149)
        c.Model:SetWidth(143)
        P.cards[i] = c
    end
end

local function Refresh(panel)
    local now = time()
    local tasks = Kit.Call("GetTasks") or {}
    P.tasks:SetData(tasks)
    P.taskEmpty:SetShown(#tasks == 0)
    local ready, nextAt = 0, nil
    for _, t in ipairs(tasks) do
        local e = t.endAt or 0
        if t.kind ~= "BUILD" and now >= e then ready = ready + 1
        elseif now < e and (not nextAt or e < nextAt) then nextAt = e end
    end
    P.taskHeader.right:SetText(string.format("%d running%s", #tasks, nextAt and ("  -  next in " .. U.Duration(nextAt - now)) or ""))
    P.nextAt = nextAt
    P.collectAll:SetEnabledTip(ready > 0, "Nothing is finished yet")

    local log = Kit.Call("GetLog") or {}
    if #log > 200 then
        local cut = {}
        for i = 1, 200 do cut[i] = log[i] end
        log = cut
    end
    P.log:SetData(log)

    RefreshBuildings(tasks)
    RefreshInn()
    InnTimer(now)
end

local tickCount = 0
local function Tick(panel, now)
    tickCount = tickCount + 1
    InnTimer(now)
    if P.nextAt then
        P.taskHeader.right:SetText(string.format("%d running  -  next in %s", #(P.tasks:GetData() or {}), U.Duration(P.nextAt - now)))
    end
    -- storage fills slowly; the inn turns over on its own clock
    if tickCount % 10 == 0 then RefreshBuildings() end
    if P.innRefreshAt and now >= P.innRefreshAt then RefreshInn() end
end

UI.RegisterTab({ key = "CAMP", title = "Camp", order = 1, build = Build, refresh = Refresh, tick = Tick })
