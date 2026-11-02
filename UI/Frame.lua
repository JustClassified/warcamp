--[[ Warcamp main window: "WarcampFrame" (PortraitFrameTemplate), header bar, bottom tabs, loot report.

  ns.UI.RegisterTab{ key="HEROES", title="Heroes", order=2,
                     build=function(panel) end,          -- once, on first show of the tab
                     refresh=function(panel) end,        -- on show and on CHANGED (coalesced, once per frame)
                     tick=function(panel, now) end }     -- optional: every 0.5 s while the tab is visible
  ns.UI.Show(tabKey?)  ns.UI.Toggle()  ns.UI.IsShown()  ns.UI.Refresh()
  ns.UI.ShowReport(report, title?)   loot summary inside the window (also from ns.On("REPORT"))
  ns.UI.Status(text, r?, g?, b?)     one-line message in the header, fades after a few seconds (no sound)
  ns.UI.SetScale(scale)              0.6 .. 1.4, saved in WarcampDB.ui.scale
  ns.UI.frame                        the window (nil until first shown)
  Panels fill the inset area: about 920 x 520.
]]

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util

local W, H = 940, 600
local tabs, tabByKey = {}, {}
local main, content, header, reportFrame
local current            -- current tab def
local dirty = true       -- something changed while hidden
local refreshQueued = false
local ticker, tickN, lastReady = nil, 0, nil
local pendingReport, pendingTitle

local function report(err)
    local h = geterrorhandler and geterrorhandler()
    if h then h(err) end
end

-- WarcampDB.ui, or nil before the engine created the saved variables
local function DB()
    if type(WarcampDB) ~= "table" then return nil end
    if type(WarcampDB.ui) ~= "table" then WarcampDB.ui = {} end
    return WarcampDB.ui
end

local function Faction()
    local ok, f = pcall(UnitFactionGroup, "player")
    return ok and f == "Alliance" and "Alliance" or "Horde"
end
UI.Faction = Faction

------------------------------------------------------------------------
-- tab registry
------------------------------------------------------------------------

local BuildTabs

function UI.RegisterTab(def)
    if type(def) ~= "table" or not def.key then return end
    if tabByKey[def.key] then
        for k, v in pairs(def) do tabByKey[def.key][k] = v end
        return
    end
    def.order = def.order or (#tabs + 1)
    tabs[#tabs + 1] = def
    tabByKey[def.key] = def
    table.sort(tabs, function(a, b) return a.order < b.order end)
    if main then BuildTabs() end
end

------------------------------------------------------------------------
-- status line
------------------------------------------------------------------------

local statusToken = 0
function UI.Status(text, r, g, b)
    if not header then return end
    statusToken = statusToken + 1
    local token = statusToken
    header.status:SetText(text or "")
    header.status:SetTextColor(r or 1, g or 0.82, b or 0)
    header.status:SetAlpha(1)
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function() if token == statusToken and header then header.status:SetText("") end end)
    end
end

------------------------------------------------------------------------
-- header bar: gold, buffs, ready count + Collect all
------------------------------------------------------------------------

local function BuildHeader()
    header = CreateFrame("Frame", nil, main)
    header:SetPoint("TOPLEFT", 60, -22)
    header:SetPoint("TOPRIGHT", -8, -22)
    header:SetHeight(36)

    header.gold = Kit.CoinText(header, "GameFontHighlight")
    header.gold:SetJustifyH("LEFT")
    header.gold:SetPoint("LEFT", 8, 0)

    header.collect = Kit.Button(header, "Collect all", 96, 22, function()
        local rep = Kit.Do("CollectAll")
        if type(rep) == "table" then UI.ShowReport(rep, "Collected") end
    end, "Collect every finished task")
    header.collect:SetPoint("RIGHT", -4, 0)

    header.ready = Kit.Text(header, "GameFontNormal", "RIGHT")
    header.ready:SetPoint("RIGHT", header.collect, "LEFT", -8, 0)

    header.status = Kit.Text(header, "GameFontNormalSmall", "RIGHT")
    header.status:SetPoint("RIGHT", header.ready, "LEFT", -16, 0)
    header.status:SetWidth(250)

    header.buffs = {}
    for i = 1, 8 do
        local b = Kit.IconButton(header, 22, nil)
        b:SetPoint("LEFT", 170 + (i - 1) * 25, 0)
        b:SetTip(function(tt, self)
            local d = self.buff and self.buff.def or {}
            tt:SetText(d.name or "Buff", 1, 0.82, 0)
            if d.desc then tt:AddLine(d.desc, 1, 1, 1, true) end
            if self.buff and self.buff.expiresAt then
                tt:AddLine("Ends in " .. U.Duration(self.buff.expiresAt - time()), 0.6, 0.8, 1)
            end
        end)
        b:Hide()
        header.buffs[i] = b
    end
end

local function RefreshHeader(now)
    now = now or time()
    header.gold:SetCopper(Kit.Call("Gold") or 0, true)
    local n = Kit.Call("ReadyCount", now) or 0
    lastReady = n
    if n > 0 then
        header.ready:SetText(string.format("|cff40ff40%d ready|r", n))
    else
        header.ready:SetText("|cff808080Nothing ready|r")
    end
    header.collect:SetEnabledTip(n > 0, "Nothing is finished yet")
    local buffs = Kit.Call("GetBuffs") or {}
    for i, b in ipairs(header.buffs) do
        local buff = buffs[i]
        if buff then
            b.buff = buff
            b:SetIcon(buff.def and buff.def.icon or 134400)
            b:Show()
        else
            b.buff = nil
            b:Hide()
        end
    end
end

------------------------------------------------------------------------
-- tabs and panels
------------------------------------------------------------------------

local function SelectTabButton(def)
    for i, d in ipairs(tabs) do
        if d == def then PanelTemplates_SetTab(main, i) end
    end
end

BuildTabs = function()
    local list = {}
    for i, def in ipairs(tabs) do
        if not def.tab then
            local t = CreateFrame("Button", nil, main, "PanelTabButtonTemplate")
            t:SetText(def.title or def.key)
            t:SetScript("OnClick", function() UI.Show(def.key) end)
            def.tab = t
        end
        def.tab:SetID(i)
        def.tab:ClearAllPoints()
        list[i] = def.tab
    end
    main.Tabs = list   -- own ordered list (overrides the template's parentArray order)
    if list[1] then list[1]:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 12, 2) end
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(main, #list)
    else
        for i = 2, #list do list[i]:SetPoint("TOPLEFT", list[i - 1], "TOPRIGHT", 3, 0) end
    end
    for _, t in ipairs(list) do pcall(PanelTemplates_TabResize, t, 0) end
    if current then SelectTabButton(current) end
end

local function PanelFor(def)
    if def.panel then return def.panel end
    local p = CreateFrame("Frame", nil, content)
    p:SetPoint("TOPLEFT", 4, -4)
    p:SetPoint("BOTTOMRIGHT", -4, 4)
    p:Hide()
    def.panel = p
    if def.build then
        local ok, err = pcall(def.build, p)
        if not ok then report(err) end
    end
    return p
end

local function RefreshNow()
    refreshQueued = false
    if not (main and main:IsShown()) then dirty = true; return end
    dirty = false
    local now = time()
    local ok, err = pcall(RefreshHeader, now)
    if not ok then report(err) end
    if current and current.refresh and current.panel then
        ok, err = pcall(current.refresh, current.panel)
        if not ok then report(err) end
    end
end

function UI.Refresh()
    if not (main and main:IsShown()) then dirty = true; return end
    if refreshQueued then return end
    refreshQueued = true
    if C_Timer and C_Timer.After then C_Timer.After(0, RefreshNow) else RefreshNow() end
end

------------------------------------------------------------------------
-- ticker (only while the window is shown)
------------------------------------------------------------------------

local function Tick()
    if not (main and main:IsShown()) then return end
    local now = time()
    tickN = tickN + 1
    if tickN % 2 == 0 then Kit.Call("Update", now) end   -- engine catch-up; fires CHANGED if something finished
    Kit.Tick(now)
    local n = Kit.Call("ReadyCount", now) or 0
    if n ~= lastReady then UI.Refresh() end
    if current and current.tick and current.panel and current.panel:IsShown() then
        local ok, err = pcall(current.tick, current.panel, now)
        if not ok then report(err) end
    end
end

------------------------------------------------------------------------
-- loot report popup (inside the window)
------------------------------------------------------------------------

local REPORT_ICONS = 20

local function MountInfo(id)
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local ok, name, _, icon = pcall(C_MountJournal.GetMountInfoByID, id)
        if ok and name then return name, icon end
    end
    return "Mount " .. tostring(id), 134400
end

local function PetInfo(id)
    if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name, icon = pcall(C_PetJournal.GetPetInfoBySpeciesID, id)
        if ok and name then return name, icon end
    end
    return "Pet " .. tostring(id), 134400
end

local function BuildReport()
    local f = CreateFrame("Frame", nil, main)
    f:SetSize(520, 380)
    f:SetPoint("CENTER", content, "CENTER", 0, 10)
    f:SetFrameLevel(main:GetFrameLevel() + 40)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 6, -6)
    bg:SetPoint("BOTTOMRIGHT", -6, 6)
    bg:SetColorTexture(0.05, 0.04, 0.03, 0.97)
    local ok, border = pcall(CreateFrame, "Frame", nil, f, "DialogBorderDarkTemplate")
    if ok and border then border:SetAllPoints() end

    f.title = Kit.Text(f, "GameFontNormalLarge", "CENTER")
    f.title:SetPoint("TOP", 0, -16)
    f.sub = Kit.Text(f, "GameFontHighlightSmall", "CENTER")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetSize(440, 4)
    line:SetPoint("TOP", f.sub, "BOTTOM", 0, -4)
    if not Kit.Atlas(line, "Headhunter_LineHeader") then Kit.Atlas(line, nil, { 1, 0.82, 0, 0.3 }) end

    f.gold = Kit.CoinText(f, "GameFontHighlight")
    f.gold:SetJustifyH("CENTER")
    f.gold:SetPoint("TOP", line, "BOTTOM", 0, -6)

    f.icons = {}
    local size, per = 36, 10
    for i = 1, REPORT_ICONS do
        local b = Kit.ItemButton(f, size)
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        b:SetPoint("TOPLEFT", f, "TOP", -((per * (size + 4) - 4) / 2) + col * (size + 4), -86 - row * (size + 4))
        b:Hide()
        f.icons[i] = b
    end

    -- the text lines (engine lines + xp summary), scrollable, 16 px rows
    f.list = Kit.List(f, {
        rowHeight = 16, stripes = false,
        build = function(row)
            row.Text = Kit.Text(row, "GameFontHighlightSmall")
            row.Text:SetPoint("LEFT", 4, 0)
            row.Text:SetPoint("RIGHT", -4, 0)
        end,
        update = function(row, data) row.Text:SetText(data.text) end,
    })

    f.ok = Kit.Button(f, OKAY or "Okay", 110, 22, function() f:Hide() end)
    f.ok:SetPoint("BOTTOM", 0, 16)
    f:Hide()
    f:SetScript("OnHide", function() pendingReport = nil end)
    return f
end

local function HeroNameById(id)
    local h = Kit.Hero(id)
    return h and Kit.HeroName(h) or "?"
end

-- engine report: success = bool (one task) or a count with fail = count (merged); taskName; welcome/away;
-- lines already describe level-ups, rare finds, mounts, pets, achievements, buildings
function UI.ShowReport(rep, title)
    if type(rep) ~= "table" then return end
    if not (main and main:IsShown()) then pendingReport, pendingTitle = rep, title; return end
    reportFrame = reportFrame or BuildReport()
    local f = reportFrame

    local s, fail, tasks = rep.success, rep.fail or 0, rep.tasks or 0
    local sub = ""
    if rep.welcome then
        f.title:SetText(title or "Welcome back"); f.title:SetTextColor(1, 0.82, 0)
        sub = rep.away and ("Away for " .. U.Duration(rep.away)) or ""
        if (rep.ready or 0) > 0 then sub = sub .. string.format("  -  |cff40ff40%d ready|r", rep.ready) end
    elseif s == true then
        f.title:SetText(title or "Success!"); f.title:SetTextColor(0.3, 1, 0.3)
        sub = rep.taskName or ""
    elseif s == false then
        f.title:SetText(title or "Failed"); f.title:SetTextColor(1, 0.3, 0.25)
        sub = rep.taskName or ""
    else
        f.title:SetText(title or "Collected"); f.title:SetTextColor(1, 0.82, 0)
        if tasks > 0 then
            sub = string.format("%d task%s:  |cff40ff40%d succeeded|r", tasks, tasks == 1 and "" or "s", tonumber(s) or 0)
            if fail > 0 then sub = sub .. string.format(",  |cffff5040%d failed|r", fail) end
        end
    end
    f.sub:SetText(sub)
    f.gold:SetText((rep.gold and rep.gold > 0) and Kit.Coin(rep.gold) or "")

    -- icons: gear, items (best quality first), mounts, pets
    local n, overflow = 0, 0
    local function put(fn)
        n = n + 1
        local b = f.icons[n]
        if b then fn(b); b:Show() else overflow = overflow + 1 end
    end
    for _, g in ipairs(rep.gear or {}) do put(function(b) b:SetGear(g) end) end
    local keys = {}
    for k in pairs(rep.items or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ia, ib = Kit.Item(a), Kit.Item(b)
        local qa, qb = ia and ia.quality or 0, ib and ib.quality or 0
        if qa ~= qb then return qa > qb end
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do put(function(b) b:SetItemKey(k, rep.items[k]) end) end
    for _, id in ipairs(rep.mounts or {}) do
        local name, icon = MountInfo(id)
        put(function(b) b:SetItem({ name = name, icon = icon, quality = 4, lines = { { "New mount for your collection!", 0.3, 1, 0.3 } } }) end)
    end
    for _, id in ipairs(rep.pets or {}) do
        local name, icon = PetInfo(id)
        put(function(b) b:SetItem({ name = name, icon = icon, quality = 3, lines = { { "New pet for your collection!", 0.3, 1, 0.3 } } }) end)
    end
    local used = math.min(n, REPORT_ICONS)
    for i = used + 1, REPORT_ICONS do f.icons[i]:Hide(); f.icons[i]:Clear() end

    -- text: xp summary, then the engine's lines
    local out = {}
    if overflow > 0 then out[#out + 1] = { text = string.format("|cff9d9d9d+%d more rewards|r", overflow) } end
    local xp, same, first = {}, true, nil
    for id, amount in pairs(rep.xp or {}) do
        xp[#xp + 1] = { name = HeroNameById(id), n = amount }
        if first == nil then first = amount elseif first ~= amount then same = false end
    end
    table.sort(xp, function(a, b) return a.n > b.n end)
    if #xp > 0 then
        if same then
            local names = {}
            for _, x in ipairs(xp) do names[#names + 1] = x.name end
            out[#out + 1] = { text = string.format("|cff8080ff+%d XP|r  %s", first, table.concat(names, ", ")) }
        else
            for _, x in ipairs(xp) do out[#out + 1] = { text = string.format("|cff8080ff+%d XP|r  %s", x.n, x.name) } end
        end
    end
    for _, l in ipairs(rep.lines or {}) do out[#out + 1] = { text = l } end
    if #out == 0 and used == 0 and not (rep.gold and rep.gold > 0) then out[1] = { text = "|cff808080Nothing gained.|r" } end

    local rows = math.ceil(used / 10)
    f.list:ClearAllPoints()
    f.list:SetPoint("TOPLEFT", 24, -86 - rows * 40 - (rows > 0 and 4 or 0))
    f.list:SetPoint("BOTTOMRIGHT", -20, 44)
    f.list:SetData(out)
    f.list:ScrollToTop()
    f:Show()
end

------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------

local function SavePosition()
    local db = DB()
    if not db then return end
    local point, _, relPoint, x, y = main:GetPoint(1)
    db.pos = { point, relPoint, x, y }
end

local function BuildMain()
    main = CreateFrame("Frame", "WarcampFrame", UIParent, "PortraitFrameTemplate")
    main:Hide()
    UI.frame = main
    main:SetSize(W, H)
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", function(self) self:StartMoving() end)
    main:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

    local db = DB()
    main:ClearAllPoints()
    if db and type(db.pos) == "table" and db.pos[1] then
        main:SetPoint(db.pos[1], UIParent, db.pos[2] or db.pos[1], db.pos[3] or 0, db.pos[4] or 0)
    else
        main:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
    if db and db.scale then main:SetScale(U.Clamp(db.scale, 0.6, 1.4)) end

    if main.SetTitle then pcall(main.SetTitle, main, "Warcamp") end
    local portrait = main.PortraitContainer and main.PortraitContainer.portrait
    if portrait then
        local fac = Faction()
        -- the garrison report button art (Blizzard_Minimap/Mainline/Minimap.lua)
        if not Kit.Atlas(portrait, "GarrLanding-MinimapIcon-" .. fac .. "-Up") then
            Kit.Atlas(portrait, nil, fac == "Alliance" and "Interface\\Icons\\INV_BannerPVP_02" or "Interface\\Icons\\INV_BannerPVP_01")
        end
    end
    tinsert(UISpecialFrames, "WarcampFrame")
    -- the template's X calls HideUIPanel, which refuses (and shows "action blocked") in combat; a plain Hide never does
    if main.CloseButton then main.CloseButton:SetScript("OnClick", function() main:Hide() end) end

    content = Kit.Inset(main)
    content:SetPoint("TOPLEFT", 4, -60)
    content:SetPoint("BOTTOMRIGHT", -6, 4)

    BuildHeader()
    BuildTabs()

    main:SetScript("OnShow", function()
        tickN = 0
        if ticker then ticker:Cancel() end
        if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(0.5, Tick) end
        Kit.Call("Update", time())
        RefreshNow()
        if pendingReport then UI.ShowReport(pendingReport, pendingTitle) end
    end)
    main:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
        -- only our own tooltip: another addon's may be showing
        local owner = GameTooltip:GetOwner()
        while owner do
            if owner == main then GameTooltip:Hide() break end
            owner = owner.GetParent and owner:GetParent()
        end
    end)
end

function UI.Show(tabKey)
    if not main then BuildMain() end
    if #tabs == 0 then main:Show(); return end
    local db = DB()
    local def = tabKey and tabByKey[tabKey]
    if not def and not current and db and db.tab then def = tabByKey[db.tab] end
    def = def or current or tabs[1]
    local changed = def ~= current
    if current and changed and current.panel then current.panel:Hide() end
    current = def
    if db then db.tab = def.key end
    local p = PanelFor(def)
    p:Show()
    SelectTabButton(def)
    if main:IsShown() then
        if changed then RefreshNow() end
    else
        main:Show()   -- OnShow refreshes
    end
end

function UI.Hide()
    if main then main:Hide() end
end

function UI.Toggle()
    if main and main:IsShown() then main:Hide() else UI.Show() end
end

function UI.IsShown()
    return main ~= nil and main:IsShown()
end

function UI.SetScale(s)
    s = U.Clamp(tonumber(s) or 1, 0.6, 1.4)
    local db = DB()
    if db then db.scale = s end
    if main then main:SetScale(s) end
end

------------------------------------------------------------------------
-- engine events
------------------------------------------------------------------------

ns.On("CHANGED", function()
    if main and main:IsShown() then UI.Refresh() else dirty = true end
end)

ns.On("REPORT", function(rep)
    UI.ShowReport(rep)
end)
