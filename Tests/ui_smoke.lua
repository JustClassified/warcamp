-- Tests/ui_smoke.lua — headless smoke test for the UI kit, main window, Camp tab and minimap button.
--   lua Tests/ui_smoke.lua
-- Loads Core + fixture data + the real engine + UI\Kit/Frame/Camp/Minimap against permissive frame stubs,
-- then drives every path once (show, refresh, tick, tooltips, clicks, menus, report, models).
-- Not in the toc. Catches Lua errors (nil calls, typos, bad arithmetic), not visual problems.

unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan
local here = (arg and arg[0] or "Tests/ui_smoke.lua"):match("^(.*)[/\\]") or "."
local ROOT = here .. "/../"

local ERRORS = 0
NOW = 1793865600
function time() return math.floor(NOW) end
function date(fmt, t) return os.date("!" .. (fmt or "%c"):gsub("^!", ""), math.floor(t or NOW)) end
function geterrorhandler() return function(e) ERRORS = ERRORS + 1; print("ERROR: " .. tostring(e)) end end
WarcampDB = nil

----------------------------------------------------------------------------------------------------
-- frame stubs
----------------------------------------------------------------------------------------------------
local Obj = {}
local function noop() end
local meta = { __index = function(t, k)
    local v = Obj[k]
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^[A-Z]") then return noop end   -- unknown WoW method
    return nil
end }

local ALL = {}
local function new(kind, parent, template)
    local o = setmetatable({ _kind = kind, _parent = parent, _shown = true, _w = 10, _h = 10, _scripts = {}, _enabled = true, _text = "" }, meta)
    ALL[#ALL + 1] = o
    return o
end

function Obj:Show() self._shown = true; local s = self._scripts.OnShow; if s then s(self) end end
function Obj:Hide() local was = self._shown; self._shown = false; local s = self._scripts.OnHide; if was and s then s(self) end end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return self._shown end
function Obj:IsVisible() if not self._shown then return false end; if self._parent and self._parent.IsVisible then return self._parent:IsVisible() end; return true end
function Obj:SetSize(w, h) self._w, self._h = w, h end
function Obj:SetWidth(w) self._w = w end
function Obj:SetHeight(h) self._h = h end
function Obj:GetWidth() return self._w end
function Obj:GetHeight() return self._h end
function Obj:SetText(t) self._text = t end
function Obj:GetText() return self._text end
function Obj:GetStringWidth() return #(tostring(self._text or "")) * 6 end
function Obj:GetTextWidth() return self:GetStringWidth() end
function Obj:IsTruncated() return false end
function Obj:SetScript(k, fn) self._scripts[k] = fn end
function Obj:GetScript(k) return self._scripts[k] end
function Obj:HookScript(k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end; fn(...) end end
function Obj:Fire(k, ...) local s = self._scripts[k]; if s then return s(self, ...) end end
function Obj:IsEnabled() return self._enabled end
function Obj:SetEnabled(v) self._enabled = v and true or false end
function Obj:Enable() self._enabled = true end
function Obj:Disable() self._enabled = false end
function Obj:GetFrameLevel() return 1 end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:GetCenter() return 100, 100 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetParent() return self._parent end
function Obj:GetModelFileID() return 123 end
function Obj:CreateTexture() return new("Texture", self) end
function Obj:CreateFontString() return new("FontString", self) end
function Obj:CreateMaskTexture() return new("MaskTexture", self) end
function Obj:SetAtlas(name) self._atlas = name end
function Obj:GetAtlas() return self._atlas end
function Obj:NumLines() return self._lines or 0 end
function Obj:AddLine() self._lines = (self._lines or 0) + 1 end
function Obj:AddDoubleLine() self._lines = (self._lines or 0) + 1 end
function Obj:SetOwner() self._lines = 0 end
function Obj:GetRGB() return 1, 0.5, 0.2 end

local function scrollBoxMethods(box)
    function box:SetDataProvider(dp)
        self._frames = self._frames or {}
        for i = 1, math.min(12, #dp.arr) do
            local f = self._frames[i] or new("Button", self)
            self._frames[i] = f
            local data = dp.arr[i]
            f.GetElementData = function() return data end
            f.GetElementDataIndex = function() return i end
            self._view._init(f, data)
        end
        for i = #dp.arr + 1, #self._frames do self._frames[i] = nil end
    end
    function box:ForEachFrame(fn) for _, f in ipairs(self._frames or {}) do fn(f, f:GetElementData()) end end
end

function CreateFrame(kind, name, parent, template)
    local o = new(kind, parent, template)
    if name then _G[name] = o end
    if template == "WowScrollBoxList" then scrollBoxMethods(o) end
    if template == "PortraitFrameTemplate" then
        o.PortraitContainer = { portrait = new("Texture", o) }
        o.CloseButton = new("Button", o)
        o.SetTitle = noop
    end
    if template == "PanelTabButtonTemplate" then
        o.Text, o.Left, o.Right = new("FontString", o), new("Texture", o), new("Texture", o)
    end
    if template == "UIPanelButtonTemplate" then o.Text = new("FontString", o) end
    return o
end

UIParent = new("Frame")
Minimap = new("Frame"); Minimap._w = 140
GameTooltip = new("GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
OKAY = "Okay"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
function UnitFactionGroup() return "Horde" end
function GetCursorPosition() return 10, 10 end
function GetMinimapShape() return "ROUND" end
function GetCoinTextureString(c) return string.format("%dg", math.floor(c / 10000)) end
C_Texture = { GetAtlasInfo = function(n) return { width = 10, height = 10 } end }
C_Item = { GetItemQualityColor = function(q) return 1, 1, 1, "ffffffff" end, GetItemIconByID = function(id) return 1000 + id end }
C_ClassColor = { GetClassColor = function() return setmetatable({}, meta) end }
C_MountJournal = { GetMountInfoExtraByID = function(id) return 5000 end, GetMountInfoByID = function(id) return "Mount" .. id, 1, 2222 end }
C_PetJournal = { GetPetInfoBySpeciesID = function(id) return "Pet" .. id, 3333, 1, 77, "", "", false, true, true, false, true, 8888 end }
local timers = {}
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.dead = true end }; C_Timer._ticker = t; return t end,
}
local function flush() local list = timers; timers = {}; for _, fn in ipairs(list) do fn() end end
function PanelTemplates_SetNumTabs(f, n) f.numTabs = n end
function PanelTemplates_SetTab(f, i) f.selectedTab = i end
function PanelTemplates_TabResize() end
CreateScrollBoxListLinearView = function()
    local v = {}
    function v:SetElementExtent() end
    function v:SetElementInitializer(_, fn) self._init = fn end
    return v
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box._view = view end }
CreateDataProvider = function(arr) return { arr = arr } end
ScrollBoxConstants = { RetainScrollPosition = true }
CreateColor = function() return {} end
local lastMenu
MenuUtil = { CreateContextMenu = function(owner, gen)
    local root = { items = {} }
    function root:CreateTitle() end
    function root:CreateDivider() end
    function root:SetScrollMode() end
    function root:CreateButton(text, fn)
        local b = { text = text, fn = fn }
        function b:SetEnabled() end
        function b:SetTooltip(t) self.tip = t end
        self.items[#self.items + 1] = b
        return b
    end
    gen(owner, root)
    lastMenu = root
end }

----------------------------------------------------------------------------------------------------
-- load
----------------------------------------------------------------------------------------------------
local function load(path, ...)
    local fn, err = loadfile(ROOT .. path)
    if not fn then error("cannot load " .. path .. ": " .. tostring(err)) end
    return fn(...)
end
local ns = {}
load("Core/Init.lua", "Warcamp", ns)
load("Core/Serialize.lua", "Warcamp", ns)
load("Tests/fixture_data.lua", "Warcamp", ns, 2)
for _, f in ipairs({ "State", "Heroes", "Board", "Tasks", "Economy", "Progress", "Save" }) do load("Engine/" .. f .. ".lua", "Warcamp", ns) end
for _, f in ipairs({ "Kit", "Frame", "Camp", "Minimap" }) do load("UI/" .. f .. ".lua", "Warcamp", ns) end

-- ==== ui-b: Crafting / Market / Collection (load + stubs) ========================================
function Obj:CreateLine() return new("Line", self) end   -- Market price chart
for _, f in ipairs({ "Crafting", "Market", "Collection" }) do load("UI/" .. f .. ".lua", "Warcamp", ns) end
-- ==== end ui-b load ===============================================================================

-- ==== ui-a: Heroes / Missions / Dungeons (load + EJ stubs) ======================================
local EJ_FAIL = false
function EJ_GetInstanceInfo(id)
    if EJ_FAIL then error("bad journal id") end
    return "Journal " .. id, "A journal description.", 1001, 1002, 1003, 1004, 37, "link"
end
function EJ_SelectInstance(id) if EJ_FAIL then error("bad journal id") end end
function EJ_GetEncounterInfoByIndex(i, id)
    if EJ_FAIL or i > 3 then return nil end
    return ({ "Boss A", "Boss B", "Journal Only" })[i], "Boss text " .. i, 500 + i, 1, "link"
end
function EJ_GetCreatureInfo(i, enc) return 1, "Creature", "", 9000 + enc, 7000 end
for _, f in ipairs({ "Heroes", "Missions", "Dungeons" }) do load("UI/" .. f .. ".lua", "Warcamp", ns) end
-- ==== end ui-a load ===============================================================================

local Game, UI, Kit = ns.Game, ns.UI, ns.UI.Kit
Game:Init()
local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then ERRORS = ERRORS + 1; print("FAIL " .. label .. ": " .. tostring(err)) else print("ok   " .. label) end
end

step("minimap create + tooltip", function()
    UI.UpdateMinimap()
    Warcamp_OnAddonCompartmentEnter(nil, UIParent)
    Warcamp_OnAddonCompartmentLeave()
end)

-- start a few tasks
step("start tasks", function()
    Game.db.gold = 10000000
    local zones = Game:GetZones()
    local z = zones[1].zone.key
    for _, kind in ipairs({ "GATHER", "QUEST" }) do
        local board = Game:GetBoard(kind, z)
        local o = board[1]
        local ids = Game:Suggest(o.key)
        if ids and #ids > 0 then Game:Start(o.key, { ids[1] }, kind == "GATHER") end
    end
    Game:Upgrade("TOWN_HALL")
end)

step("show camp", function() UI.Show("CAMP"); flush() end)
step("refresh coalesced", function() UI.Refresh(); UI.Refresh(); flush() end)
step("ticker", function() for _ = 1, 12 do C_Timer._ticker.fn() end; flush() end)

local frame = WarcampFrame
step("tooltips everywhere", function()
    local function walk(o, depth)
        if depth > 8 or type(o) ~= "table" then return end
        if o._scripts and o._scripts.OnEnter then o:Fire("OnEnter"); o:Fire("OnLeave") end
        for k, v in pairs(o) do
            if type(v) == "table" and k ~= "_parent" and getmetatable(v) == meta then walk(v, depth + 1) end
        end
    end
    -- rows and tiles live on the camp panel's widget tables
    walk(frame, 0)
end)

step("enter + click every frame", function()
    print(string.format("     %d tasks, %d heroes, %d frames", #Game:GetTasks(), #Game:GetHeroes(), #ALL))
    local n, c = 0, 0
    for i = 1, #ALL do
        local o = ALL[i]
        if o._scripts.OnEnter then o:Fire("OnEnter"); o:Fire("OnLeave"); n = n + 1 end
    end
    for i = 1, #ALL do
        local o = ALL[i]
        if o._scripts.OnClick and o ~= UI.frame.CloseButton then o:Fire("OnClick", "LeftButton"); c = c + 1 end
    end
    flush()
    print(string.format("     entered %d, clicked %d", n, c))
    UI.Show("CAMP"); flush()
end)

step("finish tasks, collect via row button", function()
    NOW = NOW + 6 * 3600
    Game:Update(NOW)
    C_Timer._ticker.fn(); flush()
    Kit.Tick(time())
end)

step("collect all + report", function()
    local rep = Kit.Do("CollectAll")
    flush()
    UI.ShowReport({ success = 2, fail = 1, tasks = 3, gold = 12345, xp = { [1] = 10 }, items = { HEALING_POTION = 2 },
        gear = { { slot = "HEAD", ilvl = 20, quality = 3, name = "Hat", itemID = 1 } }, mounts = { 999 }, pets = { 55 }, lines = { "A line." } })
    UI.ShowReport({ welcome = true, away = 3600, ready = 2, success = 0, fail = 0, tasks = 0, gold = 0, lines = { "You were away." } })
end)

step("party picker + menu", function()
    local p = Kit.PartyPicker(UIParent, { slots = 3 })
    p.slots[1]:Fire("OnClick", "LeftButton")
    if lastMenu and lastMenu.items[1] then lastMenu.items[1].fn(); if lastMenu.items[1].tip then lastMenu.items[1].tip(GameTooltip) end end
    assert(#p:GetHeroes() == 1, "picked one hero")
    p.slots[1]:Fire("OnClick", "RightButton")
    assert(#p:GetHeroes() == 0, "removed")
    p:SetSlots(5); p:SetEnabled(false); p:SetHeroes({ Game:GetHeroes()[1].id })
end)

step("model view", function()
    local m = Kit.ModelView(UIParent, 200, 200, { caption = true, hint = true })
    m:SetDisplay(123, 134400); m:SetCreature(456); m:SetMount(10); m:SetPet(20); m:SetIcon(1); m:SetCaption("x"); m:Clear()
    m:Fire("OnMouseDown", "LeftButton"); m:Fire("OnUpdate", 0.1); m:Fire("OnMouseUp"); m:Fire("OnMouseWheel", 1)
    flush()
end)

step("widgets", function()
    local c = Kit.ChanceMeter(UIParent); c:SetChance(0.9); c:SetChance(0.4); c:SetChance(nil)
    local t = Kit.ThreatIcons(UIParent); t:SetThreats({ "MAGIC_DEBUFF", "CASTER" }, { CASTER = true }); t.icons[1]:Fire("OnEnter")
    local b = Kit.HeroBadge(UIParent); b:SetHero(Game:GetHeroes()[1]); b:Clear()
    local i = Kit.ItemButton(UIParent); i:SetItemKey("HEALING_POTION", 3); i:Fire("OnEnter"); i:SetItemKey("NOPE"); i:Clear()
    local bar = Kit.ProgressBar(UIParent, 100); bar:SetTimes(time() - 10, time() + 10); bar:SetValueText(3, 9)
    Kit.Menu(UIParent, "T", { { text = "a", func = function() end }, { divider = true }, { text = "b", disabled = true, tooltip = "x" } })
    local saved = MenuUtil; MenuUtil = nil
    Kit.Menu(UIParent, "T", { { text = "a", func = function() end } })
    MenuUtil = saved
    local l = Kit.List(UIParent, { selectable = true, key = function(d) return d.id end, update = function() end })
    l:SetData({ { id = 1 }, { id = 2 } }); l:SetSelected(2); assert(l:GetSelected().id == 2); l:Refresh(); l:ScrollToTop()
end)

step("inn recruit + reroll + building upgrade buttons", function()
    UI.Show("CAMP"); flush()
    Kit.Do("Recruit", 1); flush()
    Kit.Do("RerollRecruits"); flush()
    NOW = NOW + 30 * 86400
    Game:Update(NOW); flush()
    C_Timer._ticker.fn(); flush()
end)

step("toggle / scale / hide", function()
    UI.SetScale(1.2); UI.Toggle(); assert(not UI.IsShown()); UI.Toggle(); assert(UI.IsShown()); UI.Show("NOPE"); UI.Hide()
    UI.SetMinimapShown(false); UI.SetMinimapShown(true)
end)

-- ==== ui-b: Crafting / Market / Collection steps ================================================
do
    -- enter + leave + click every visible frame (= the shown tab); the tab panels may
    -- already exist (the generic "click every frame" step above clicks the tab buttons), so filter by
    -- visibility rather than creation order. Twice by default: two-click confirms.
    local function inPanel(o)   -- inside the window, but not its own children (bottom tabs, close button)
        if o._parent == UI.frame then return false end
        local p = o._parent
        while p do
            if p == UI.frame then return true end
            p = p._parent
        end
        return false
    end
    local function poke(from, times)
        for _ = 1, times or 2 do
            local n = #ALL
            for i = from, n do
                local o = ALL[i]
                if o._scripts.OnEnter and o:IsVisible() and inPanel(o) then o:Fire("OnEnter"); o:Fire("OnLeave") end
            end
            for i = from, n do
                local o = ALL[i]
                -- only inside the window (the minimap button would toggle it, bottom tabs would switch tabs)
                if o._scripts.OnClick and o:IsVisible() and inPanel(o) then o:Fire("OnClick", "LeftButton") end
            end
            flush()
        end
    end
    local function editBoxes(from, text)
        for i = from, #ALL do
            local o = ALL[i]
            if o._kind == "EditBox" and o:IsVisible() then
                o:SetText(text); o:Fire("OnEnterPressed"); o:SetText("0"); o:Fire("OnEditFocusLost"); o:Fire("OnEscapePressed")
            end
        end
        flush()
    end
    local function stockUp()
        Game.db.gold = 50000000
        for _, k in ipairs({ "HERB_T1", "FISH_T1", "ORE_T1", "LEATHER_T1", "CLOTH_T1" }) do Game:AddItem(k, 60) end
        for _, b in ipairs({ "FORGE", "ALCHEMY_LAB", "KITCHEN", "TRADING_POST" }) do Game.db.buildings[b].level = 2 end
        Game:Changed("all")
    end

    local mark
    step("ui-b crafting: show, select, quantity, craft", function()
        stockUp()
        mark = 1
        UI.Show("CRAFTING"); flush()
        editBoxes(mark, "3")
        poke(mark)                      -- rows (select + collapse/expand), -/+/Max, Craft, queue button
        UI.Show("CRAFTING"); flush()
        poke(mark, 1)                   -- headers again: expand what the first pass collapsed
        local crafting = 0
        for _, t in ipairs(Game:GetTasks()) do if t.kind == "CRAFT" then crafting = crafting + 1 end end
        print(string.format("     %d craft task(s) queued", crafting))
        assert(crafting > 0, "a craft was queued")
        for _ = 1, 4 do C_Timer._ticker.fn() end; flush()
    end)

    step("ui-b crafting: finish + collect from the queue row", function()
        NOW = NOW + 3 * 3600
        Game:Update(NOW); flush()
        C_Timer._ticker.fn(); flush()
        UI.Show("CRAFTING"); flush()
        poke(mark, 1)
        stockUp()
        UI.Refresh(); flush()
        Game.db.inventory = {}; Game:Changed("inventory"); UI.Refresh(); flush()   -- empty storage path
        stockUp(); UI.Refresh(); flush()
    end)

    step("ui-b market: show, filter, sort, select, buy/sell, chart, gear", function()
        stockUp()
        local g = Game:MakeGear(1, "HEAD", 20, 3); Game:AddGear(g)
        local g2 = Game:MakeGear(1, "ANY", 18, 2); Game:AddGear(g2)
        mark = 1
        -- the first CreateLine fails (exercises the bar fallback), later ones work
        local savedLine, calls = Obj.CreateLine, 0
        Obj.CreateLine = function(self, ...) calls = calls + 1; if calls == 1 then error("no lines") end; return savedLine(self, ...) end
        UI.Show("MARKET"); flush()
        Obj.CreateLine = savedLine
        local gold0 = Game:Gold()
        poke(mark)                      -- categories, tier button (menu), sort headers, rows, buy/sell, gear sell
        if lastMenu and lastMenu.items[2] then lastMenu.items[2].fn(); flush() end
        if lastMenu and lastMenu.items[1] then lastMenu.items[1].fn(); flush() end
        poke(mark, 1)
        for _ = 1, 40 do C_Timer._ticker.fn() end; flush()   -- 10 s re-price tick
        print(string.format("     gold %d -> %d, %d gear left", gold0, Game:Gold(), #Game:GetGearBag()))
    end)

    step("ui-b market: Potions category + Use button", function()
        Game:AddItem("HEALING_POTION", 3)
        UI.Show("MARKET"); flush()
        for i = 1, #ALL do
            local o = ALL[i]
            if o._text == "Potions" and o._parent and o._parent:IsVisible() then
                -- the nav button's label is a FontString; click its button
                if o._parent._scripts.OnClick then o._parent:Fire("OnClick", "LeftButton") end
            end
        end
        flush()
        local before = Game:Count("HEALING_POTION")
        for i = 1, #ALL do   -- select the potion row
            local o = ALL[i]
            if o:IsVisible() and o.data and o.data.key == "HEALING_POTION" and o._scripts.OnClick then o:Fire("OnClick", "LeftButton") end
        end
        flush()
        for i = 1, #ALL do
            local o = ALL[i]
            if o._text == "Use" and o:IsVisible() and o._scripts.OnClick then o:Fire("OnClick", "LeftButton"); o:Fire("OnEnter"); o:Fire("OnLeave") end
        end
        flush()
        print(string.format("     potions %d -> %d, %d buff(s)", before, Game:Count("HEALING_POTION"), #Game:GetBuffs()))
        assert(Game:Count("HEALING_POTION") == before - 1, "a potion was used")
    end)

    step("ui-b collection: mounts & pets + achievements + era", function()
        Game:AddMount(ns.D.MOUNTS[1].mountID, "Dungeon 1.2", NOW)
        Game:AddPet(ns.D.PETS[1].speciesID, "Dungeon 1.1", NOW)
        Game:AddPet(ns.D.PETS[1].speciesID, "Dungeon 1.1", NOW)
        Game.db.stats.TASKS = 50
        Game:CheckAchievements(nil, NOW)
        mark = 1
        UI.Show("COLLECTION"); flush()
        poke(mark)                      -- sub-tabs, filter cycle, rows, model; achievements view + era button
        UI.Show("COLLECTION"); flush()
        poke(mark, 3)                   -- filter all the way round, both views
        -- era: make it possible, then two-click Advance Era from the Achievements view
        Game.db.finalCleared = true
        local era0 = Game.db.era
        UI.Refresh(); flush()
        for i = mark, #ALL do
            local o = ALL[i]
            if o._text == "Achievements" and o._scripts.OnClick and o:IsVisible() then o:Fire("OnClick", "LeftButton") end
        end
        flush()
        for i = mark, #ALL do
            local o = ALL[i]
            if o._text == "Advance Era" and o._scripts.OnClick and o:IsVisible() then o:Fire("OnClick", "LeftButton"); o:Fire("OnClick", "LeftButton") end
        end
        flush()
        print(string.format("     era %d -> %d, %d mounts kept", era0, Game.db.era, ns.Util.Count(Game.db.collection.mounts)))
        assert(Game.db.era == era0 + 1, "era advanced")
        for _ = 1, 12 do C_Timer._ticker.fn() end; flush()
        UI.Show("CRAFTING"); flush(); UI.Show("MARKET"); flush(); UI.Show("COLLECTION"); flush()
    end)
end
-- ==== end ui-b steps ==============================================================================

-- ==== ui-a: Heroes / Missions / Dungeons steps ====================================================
do
    local function under(o, panel)
        local p = o._parent
        while p do if p == panel then return true end; p = p._parent end
        return false
    end
    -- enter/leave + click every visible frame inside one tab panel (twice: two-click confirms)
    local function poke(panel)
        for _ = 1, 2 do
            local n = #ALL
            for i = 1, n do
                local o = ALL[i]
                if o._scripts.OnEnter and o:IsVisible() and under(o, panel) then o:Fire("OnEnter"); o:Fire("OnLeave") end
            end
            for i = 1, n do
                local o = ALL[i]
                if o._scripts.OnClick and o:IsVisible() and under(o, panel) then o:Fire("OnClick", "LeftButton") end
            end
            flush()
        end
    end
    local function rows(list) return (list.box and list.box._frames) or list.rows or {} end
    local function clickRow(list, pred, button)
        for _, r in ipairs(rows(list)) do
            if r.data ~= nil and (not pred or pred(r.data)) then
                r:Fire("OnEnter"); r:Fire("OnLeave"); r:Fire("OnClick", button or "LeftButton"); flush()
                return r
            end
        end
    end
    local function ticks(n) for _ = 1, n or 4 do C_Timer._ticker.fn() end; flush() end
    local function freeHeroes(n, keepTasks)
        for _ = 1, n do Game:AddHero(Game:GenerateHero(3, 1)) end
        if keepTasks then flush(); return end
        for _, h in ipairs(Game:GetHeroes()) do
            if h.taskId then Game:Cancel(h.taskId) end
        end
        flush()
    end

    step("ui-a heroes tab", function()
        Game.db.gold = 50000000
        freeHeroes(3)
        for _ = 1, 6 do Game:AddGear(Game:RollGear(1, 30, 3)) end
        Game:AddGear(Game:RollGear(1, 30, 4))
        UI.Show("HEROES"); flush()
        local P = UI._heroes
        assert(P.selId, "a hero is selected")
        for _, b in pairs(P.filters) do b:Fire("OnClick", "LeftButton"); flush() end
        for _, b in pairs(P.sorts) do b:Fire("OnClick", "LeftButton"); flush() end
        P.filters.ALL:Fire("OnClick", "LeftButton"); flush()
        local r = clickRow(P.list, function(h) return h.id ~= P.selId end)
        assert(r and P.selId == r.data.id, "selection follows the click")
        local keep = P.selId
        UI.Refresh(); flush()
        assert(P.selId == keep, "selection kept across refresh")
        -- paperdoll: tooltip, menu pick, right-click unequip
        local slot = P.slots[1]
        slot:Fire("OnEnter"); slot:Fire("OnLeave")
        local before = Game:GetHero(keep).gear[slot.slot]
        slot:Fire("OnClick", "RightButton"); flush()
        assert(Game:GetHero(keep).gear[slot.slot] == nil, "unequipped")
        slot:Fire("OnEnter"); slot:Fire("OnLeave")
        lastMenu = nil
        slot:Fire("OnClick", "LeftButton")
        assert(lastMenu and lastMenu.items[1], "slot menu opened")
        if lastMenu.items[1].tip then lastMenu.items[1].tip(GameTooltip) end
        lastMenu.items[1].fn(); flush()
        assert(Game:GetHero(keep).gear[slot.slot] ~= nil, "equipped from the menu")
        -- bag rows: equip + sell (epic needs two clicks)
        local nBag = #Game:GetGearBag()
        local row = clickRow(P.bag)
        row.Equip:Fire("OnClick", "LeftButton"); flush()
        row = rows(P.bag)[1]
        local id = row.data.id
        row.Sell:Fire("OnClick", "LeftButton"); flush()
        if Game.db.bag[id] then row.Sell:Fire("OnClick", "LeftButton"); flush() end
        assert(not Game.db.bag[id], "sold")
        assert(#Game:GetGearBag() < nBag + 1, "bag shrank")
        P.auto:Fire("OnClick", "LeftButton"); flush()
        P.equipAll:Fire("OnClick", "LeftButton"); flush()
        -- dismiss: first click asks, second dismisses
        local n0 = #Game:GetHeroes()
        P.dismiss:Fire("OnClick", "LeftButton"); flush()
        assert(P.dismiss._text == "Sure?", "first click asks")
        P.dismiss:Fire("OnClick", "LeftButton"); flush()
        assert(#Game:GetHeroes() == n0 - 1, "dismissed")
        ticks(6)
        poke(P.right:GetParent())
        ticks(2)
    end)

    step("ui-a missions tab", function()
        freeHeroes(2)
        UI.Show("MISSIONS"); flush()
        local P = UI._missions
        assert(P.zoneKey and P.offerKey, "zone and offer selected")
        clickRow(P.zones, function(d) return d.header end)
        clickRow(P.zones, function(d) return not d.header and not d.unlocked end)
        clickRow(P.zones, function(d) return not d.header and d.unlocked end)
        assert(P.zoneKey, "zone kept")
        -- gather: select, auto-fill, repeat, start
        clickRow(P.gather)
        P.enc.auto:Fire("OnClick", "LeftButton"); flush()
        P.enc.repeatBox:Fire("OnClick", "LeftButton"); flush()
        local t0 = #Game:GetTasks()
        P.enc.start:Fire("OnClick", "LeftButton"); flush()
        assert(#Game:GetTasks() == t0 + 1, "gather started")
        -- quest: select, start, then the in-progress row is selected
        clickRow(P.quest, function(e) return not e.inProgress end)
        P.enc.auto:Fire("OnClick", "LeftButton"); flush()
        P.enc.start:Fire("OnClick", "LeftButton"); flush()
        assert(#Game:GetTasks() == t0 + 2, "quest started")
        assert(P.offerKey:match("^T:"), "in-progress quest selected")
        clickRow(P.quest, function(e) return e.inProgress end)
        P.picker.slots[1]:Fire("OnEnter"); P.picker.slots[1]:Fire("OnLeave")
        ticks(6)
        for _, b in ipairs(P.enc.rewards) do b:Fire("OnEnter"); b:Fire("OnLeave") end
        poke(P.zones:GetParent())
    end)

    step("ui-a dungeons tab", function()
        freeHeroes(6)
        UI.Show("DUNGEONS"); flush()
        local P = UI._dungeons
        assert(P.key, "an instance is selected")
        clickRow(P.list, function(d) return d.header end)
        clickRow(P.list, function(d) return not d.header and d.offer.kind == "RAID" end)
        assert(P.raidPicker:IsShown(), "raid picker shown")
        clickRow(P.list, function(d) return not d.header and d.offer.kind == "DUNGEON" and d.offer.rewards.mount end)
        assert(#P.bosses:GetData() == 3, "journal boss list used")
        clickRow(P.bosses)
        for _, c in ipairs(P.chase) do
            c:Fire("OnEnter"); c:Fire("OnClick", "LeftButton"); c:Fire("OnLeave"); c:Fire("OnClick", "LeftButton")
        end
        for _, b in ipairs(P.rewards) do b:Fire("OnEnter"); b:Fire("OnLeave") end
        P.auto:Fire("OnClick", "LeftButton"); flush()
        local t0 = #Game:GetTasks()
        P.start:Fire("OnClick", "LeftButton"); flush()
        assert(#Game:GetTasks() == t0 + 1, "dungeon started")
        assert(P.start._text == "Inside", "shows the party inside")
        -- a raid
        freeHeroes(8, true)
        clickRow(P.list, function(d) return not d.header and d.offer.kind == "RAID" and not d.offer.locked end)
        P.auto:Fire("OnClick", "LeftButton"); flush()
        P.start:Fire("OnClick", "LeftButton"); flush()
        assert(#Game:GetTasks() == t0 + 2, "raid started")
        -- the Encounter Journal failing: data alone
        EJ_FAIL = true
        ns.D.DUNGEONS[1].journalID = 64
        clickRow(P.list, function(d) return not d.header and d.offer.instance == ns.D.DUNGEONS[1].key end)
        assert(#P.bosses:GetData() == #ns.D.DUNGEONS[1].bosses, "data boss list")
        clickRow(P.bosses)
        EJ_FAIL = false
        ticks(6)
        poke(P.list:GetParent())
        NOW = NOW + 20 * 3600; Game:Update(NOW); ticks(2)
        UI.Show("HEROES"); flush(); UI.Show("MISSIONS"); flush(); UI.Show("DUNGEONS"); flush()
    end)
end
-- ==== end ui-a steps ==============================================================================

-- ==== bags =======================================================================================
load("UI/Bags.lua", "Warcamp", ns)
step("bags tab: grid, select, use, sell, gear", function()
    UI.Show("BAGS"); flush()
    local P = UI._bags
    for _, k in ipairs({ "HERB_T1", "ORE_T1", "LEATHER_T1" }) do Game:AddItem(k, 25) end
    Game:AddItem("HEALING_POTION", 2)
    flush()
    -- click every visible slot, then the potion
    P.grid:ForEachRow(function(row)
        for _, b in ipairs(row.Slots) do
            if b.spec then b:Fire("OnEnter"); b:Fire("OnClick", "LeftButton"); b:Fire("OnLeave") end
        end
    end)
    flush()
    P.sel = "HEALING_POTION"; flush()
    local R = P.detail
    R.use:Fire("OnClick", "LeftButton"); flush()
    assert(Game:Count("HEALING_POTION") == 1, "potion used")
    P.sel = "ORE_T1"; flush()
    local before = Game:Count("ORE_T1")
    R.sell1:Fire("OnClick", "LeftButton"); flush()
    assert(Game:Count("ORE_T1") == before - 1, "sold one")
    R.sellAll:Fire("OnClick", "LeftButton"); R.sellAll:Fire("OnClick", "LeftButton"); flush()
    assert(Game:Count("ORE_T1") == 0, "sold all")
    -- gear slots: select each, equip on the best recruit or sell it
    local gearIds = {}
    for _, g in ipairs(Game:GetGearBag() or {}) do gearIds[#gearIds + 1] = g.id end
    for _, id in ipairs(gearIds) do
        P.sel, P.selGear = nil, id; flush()
        if R.equip:IsEnabled() then R.equip:Fire("OnClick", "LeftButton") else
            R.sellGear:Fire("OnClick", "LeftButton"); R.sellGear:Fire("OnClick", "LeftButton") end
        flush()
    end
    for _, id in ipairs(gearIds) do
        assert(not (Game.db.bag or {})[id], "gear slot equipped or sold")
    end
    print(string.format("     bags: %d gear slots handled", #gearIds))
    local empties = 0
    P.grid:ForEachRow(function(row) for _, b in ipairs(row.Slots) do if not b.spec then empties = empties + 1 end end end)
    assert(empties > 0, "bag padded with empty slots")
    R.market:Fire("OnClick", "LeftButton"); flush()
    UI.Show("BAGS"); flush()
end)
-- ==== end bags ===================================================================================

-- ==== options + save window =====================================================================
local registered
Settings = { RegisterCanvasLayoutCategory = function(panel, name) registered = panel
                 return { GetID = function() return 42 end } end,
             RegisterAddOnCategory = function() end, OpenToCategory = function() end }
ns.Say = ns.Say or function() end
load("UI/Options.lua", "Warcamp", ns)
step("options page and save export / import", function()
    assert(registered, "options panel registered")
    registered:Fire("OnShow")
    UI.OpenOptions()
    local gold = Game:Gold()
    UI.ShowSaveDialog("export")
    local f = WarcampSaveFrame or nil
    local str = Game:ExportString()
    assert(#str > 100, "export string")
    UI.ShowSaveDialog("import")
    assert(Game:ImportString(str), "import from dialog path")
    assert(Game:Gold() == gold, "gold kept through import")
    assert(Game:GetBackup(), "backup after import")
    registered:Fire("OnShow")
    flush()
    UI.Show("CAMP"); flush()
    UI.Show("HEROES"); flush()
end)

print(ERRORS == 0 and "UI SMOKE: all good" or ("UI SMOKE: " .. ERRORS .. " error(s)"))
os.exit(ERRORS == 0 and 0 or 1)
