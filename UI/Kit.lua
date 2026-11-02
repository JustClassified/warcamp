--[[ Warcamp UI kit: the shared widget library. Every tab builds on these; nothing here talks to the
     engine except through Kit.Call / Kit.Do (pcall'd, errors go to the error handler, never break the UI).

  LOOK HELPERS
  Kit.Atlas(tex, atlas, fallback, useAtlasSize)  -> true if the atlas was set; else sets fallback
                                                   ({r,g,b,a} colour, or file path / fileID, or nil = clear)
  Kit.Text(parent, template?, justify?, layer?)  -> FontString (default "GameFontHighlightSmall", "LEFT")
  Kit.Inset(parent)                              -> InsetFrameTemplate frame (the standard sunken panel)
  Kit.Backdrop(frame, alpha?)                    -> dark fill texture behind a frame's content
  Kit.ClassColor(class)                          -> r, g, b, hex ("ffc79c6e")
  Kit.QualityHex(q)                              -> "ffa335ee" (item quality 0-7)
  Kit.HeroName(hero)                             -> "|cff..Name|r" class coloured
  Kit.ClassIcon(tex, class)  Kit.RoleIcon(tex, role)  Kit.QualityBorder(tex, q)   set a texture
  Kit.ClassMarkup(class, size?)  Kit.RoleMarkup(role, size?)  Kit.IconMarkup(icon, size?)  -> inline |A|/|T| strings
  Kit.Coin(copper, short?)                       -> coin texture string (short: drops silver/copper >= 100g)
  Kit.TimeLeft(endAt, now?)                      -> "12m 04s" or "Ready!"
  Kit.Now()                                      -> time()
  Kit.ChanceColor(chance)                        -> r, g, b (green >= 0.8, yellow >= 0.5, red below, grey for nil)
  ns.UI.Faction()                                -> "Horde" | "Alliance" (defined in UI\Frame.lua)

  ENGINE ACCESS
  Kit.Call("Method", ...)      -> results of ns.Game:Method(...) or nil (missing method / error)
  Kit.Do("Method", ...)        -> ok, err  for mutators; a failure text goes to ns.UI.Status(err)
  Kit.Hero(id)  Kit.Item(key)  -> hero table / D.ITEMS entry (nil-safe)

  TOOLTIPS
  Kit.Tip(owner, title, lines?, anchor?, r?, g?, b?)  shows GameTooltip. lines: "text" | {text, r,g,b}
       | {left, right, lr,lg,lb, rr,rg,rb} (double line) | " " (spacer)
  Kit.AddLines(tooltip, lines)
  Kit.SetTooltip(frame, fn)    fn(tooltip, frame) fills GameTooltip on enter (owner already set, anchor frame.tipAnchor or ANCHOR_RIGHT)
  Kit.HeroTooltip(tooltip, hero, opts?)   adds a full hero block (name, class, level, ilvl, power, traits, skills, status);
                                         opts = { noStatus=true } for recruits that are not in the camp yet
  Kit.ItemTooltip(tooltip, spec)   spec as ItemButton:SetItem

  WIDGETS (all return the frame; methods listed after the constructor)
  Kit.Button(parent, text, w?, h?, onClick?, tip?)     UIPanelButtonTemplate, default 80x20.
       :SetTip(textOrFn)  :SetEnabledTip(enabled, reasonText)   (disabled buttons still show their reason)
  Kit.IconButton(parent, size, icon, onClick?, tip?)    small square icon button with highlight.  :SetIcon(icon)
  Kit.Header(parent, text, width?)                      gold section title + LFG divider line, 18 px.  :SetText(t)  .right (FontString on the right)
  Kit.List(parent, opts)                                scrolling row list with a row pool (ScrollBox + MinimalScrollBar).
       opts = { rowHeight=20, build=function(row, list) end, update=function(row, data, index, list) end,
                onClick=function(row, data, button, list) end, tooltip=function(tooltip, row, data) end,
                selectable=true|false, key=function(data) return data.id end, stripes=true }
       :SetData(array)  :Refresh() (re-runs update on visible rows only, cheap for timers)  :GetData()
       :SetSelected(data|key)  :GetSelected()  :ForEachRow(fn(row, data))  :ScrollToTop()
       rows get .data, .index, .Stripe, .Select textures; anything built in opts.build stays on the pooled row.
  Kit.ItemButton(parent, size?)                         icon + quality border + count + tooltip (default 32).
       :SetItem{ icon=, itemID=, quality=, count=, name=, lines={...}, onClick= }   :SetItemKey(key, count?, lines?)
       :SetGear(gear)  :SetCount(n)  :SetQuality(q)  :Clear()  :SetDesaturated(bool)
  Kit.HeroBadge(parent, width?, height?)                one-line hero: class icon, class-coloured name, level, ilvl, role icon, status.
       :SetHero(hero, statusText?, r?, g?, b?)  :Clear()   (put one inside a List row for a hero list)
  Kit.ModelView(parent, w, h, opts?)                    PlayerModel, drag to turn, wheel zoom, idle spin, icon fallback.
       :SetDisplay(displayID, fallbackIcon?)  :SetCreature(npcID, fallbackIcon?)  :SetMount(mountID)  :SetPet(speciesID)
       :SetIcon(icon)  :SetCaption(text)  :Clear()  :SetSpin(bool)  :ResetView()      opts = { caption=true, hint=true, bg=true }
  Kit.ProgressBar(parent, w, h?)                        status bar with Blizzard art (default height 14).
       :SetTimes(startAt, endAt)  (auto-updates with the window ticker; text "12m 04s" / "Ready!")
       :SetProgress(frac, text?, r?, g?, b?)  :SetValueText(cur, max, fmt?)  :SetBarColor(r,g,b)  :IsReady()
  Kit.CoinText(parent, template?)                       FontString.  :SetCopper(copper, short?)
  Kit.ChanceMeter(parent, w?, h?)                       small bar + % text, green >= 80, yellow >= 50, else red.  :SetChance(0..1 | nil)
  Kit.ThreatIcons(parent, size?, max?)                  row of threat icons, green tick when countered.
       :SetThreats(threatKeys, countered)  (countered = {[key]=true})   :GetWidthUsed()
  Kit.PartyPicker(parent, opts)                         N hero slots; click opens a menu of idle heroes.
       opts = { slots=3, size=30, spacing=4, onChange=function(ids, picker) end,
                candidates=function(picker) return heroArray end,  -- default: idle heroes
                label=function(hero) return text end }              -- extra text in the menu row
       :SetSlots(n)  :SetHeroes(ids)  :GetHeroes() -> ids (no gaps)  :Clear()  :SetEnabled(bool)
  Kit.Menu(owner, title, entries)    context menu (MenuUtil if present, else own dropdown).
       entries = { {text=, func=, disabled=, tooltip=, title=true, divider=true}, ... }

  LIVE UPDATES
  Kit.Live(frame, fn)        fn(frame, now) runs on every window tick (0.5 s) while frame is visible.
  Kit.Tick(now)              called by UI\Frame.lua's ticker; runs all live functions.
]]

local ADDON, ns = ...
ns.UI = ns.UI or {}
local Kit = {}
ns.UI.Kit = Kit

local U = ns.Util
local floor, max, min = math.floor, math.max, math.min

------------------------------------------------------------------------
-- look helpers
------------------------------------------------------------------------

function Kit.Now() return time() end

function Kit.Atlas(tex, atlas, fallback, useAtlasSize)
    if atlas and ns.Atlas(tex, atlas, useAtlasSize) then return true end
    if type(fallback) == "table" then
        tex:SetColorTexture(fallback[1] or 0, fallback[2] or 0, fallback[3] or 0, fallback[4] or 1)
    elseif fallback then
        tex:SetTexture(fallback)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexture(nil)
    end
    return false
end

function Kit.Text(parent, template, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function Kit.Inset(parent)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
    if not ok then
        f = CreateFrame("Frame", nil, parent)
        Kit.Backdrop(f, 0.6)
    end
    return f
end

function Kit.Backdrop(frame, alpha)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    t:SetAllPoints()
    t:SetColorTexture(0.03, 0.025, 0.02, alpha or 0.75)
    return t
end

function Kit.ClassColor(class)
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, class)
        if ok and c then
            local r, g, b = c:GetRGB()
            return r, g, b, string.format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
        end
    end
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b, c.colorStr or string.format("ff%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5)) end
    return 1, 1, 1, "ffffffff"
end

function Kit.QualityHex(q)
    local _, _, _, hex = ns.QUALITY_COLOR(q)
    if hex and #hex == 6 then hex = "ff" .. hex end
    return hex or "ffffffff"
end

function Kit.HeroName(h)
    if not h then return "?" end
    local _, _, _, hex = Kit.ClassColor(h.class)
    return "|c" .. hex .. (h.name or "?") .. "|r"
end

local CLASS_FILE_ICON = "Interface\\TargetingFrame\\UI-Classes-Circles"
function Kit.ClassIcon(tex, class)
    if class and ns.Atlas(tex, "classicon-" .. string.lower(class)) then return true end
    local tc = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class]
    if tc then
        tex:SetTexture(CLASS_FILE_ICON)
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetTexture(134400)
        tex:SetTexCoord(0, 1, 0, 1)
    end
    return false
end

-- verified in Blizzard_SharedXMLBase/TextureUtil.lua (LFGRoleIcons)
local ROLE_ATLAS = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }
local ROLE_COLOR = { TANK = { 0.3, 0.5, 1 }, HEALER = { 0.3, 1, 0.4 }, DAMAGER = { 1, 0.35, 0.3 } }
function Kit.RoleIcon(tex, role)
    if role and ns.Atlas(tex, ROLE_ATLAS[role]) then return true end
    local def = ns.D.ROLES and role and ns.D.ROLES[role]
    if def and def.atlas and ns.Atlas(tex, def.atlas) then return true end
    local c = ROLE_COLOR[role] or { 0.5, 0.5, 0.5 }
    tex:SetColorTexture(c[1], c[2], c[3], 0.9)
    return false
end

-- The auctionhouse atlases are round rings that cover a square icon, so every border uses the
-- square bag-slot frame tinted by quality, as Blizzard's own ItemButton does.
function Kit.QualityBorder(tex, q)
    q = q or 1
    tex:SetTexture("Interface\\Common\\WhiteIconFrame")
    tex:SetTexCoord(0, 1, 0, 1)
    local r, g, b = ns.QUALITY_COLOR(q)
    tex:SetVertexColor(r, g, b, 1)
    return false
end

function Kit.ClassMarkup(class, size)
    size = size or 14
    if class then return string.format("|A:classicon-%s:%d:%d|a", string.lower(class), size, size) end
    return ""
end

function Kit.RoleMarkup(role, size)
    size = size or 14
    if role and ROLE_ATLAS[role] then return string.format("|A:%s:%d:%d|a", ROLE_ATLAS[role], size, size) end
    return ""
end

function Kit.IconMarkup(icon, size)
    if not icon then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(icon), size or 14, size or 14)
end

local function CoinString(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        local ok, s = pcall(C_CurrencyInfo.GetCoinTextureString, copper)
        if ok and s then return s end
    end
    if GetCoinTextureString then
        local ok, s = pcall(GetCoinTextureString, copper)
        if ok and s then return s end
    end
    return string.format("%dg %ds %dc", floor(copper / 10000), floor(copper % 10000 / 100), copper % 100)
end

function Kit.Coin(copper, short)
    copper = floor(tonumber(copper) or 0)
    local neg = copper < 0
    if neg then copper = -copper end
    if short and copper >= 1000000 then copper = copper - copper % 10000 end
    local s = CoinString(copper)
    return neg and ("-" .. s) or s
end

function Kit.TimeLeft(endAt, now)
    now = now or time()
    if not endAt or endAt <= now then return "Ready!" end
    return U.Duration(endAt - now)
end

------------------------------------------------------------------------
-- engine access
------------------------------------------------------------------------

local function report(err)
    local h = geterrorhandler and geterrorhandler()
    if h then h(err) end
end

function Kit.Call(method, ...)
    local g = ns.Game
    local f = g and g[method]
    if type(f) ~= "function" then return nil end
    local function pass(ok, ...)
        if not ok then report((...)); return nil end
        return ...
    end
    return pass(pcall(f, g, ...))
end

function Kit.Do(method, ...)
    local g = ns.Game
    local f = g and g[method]
    if type(f) ~= "function" then
        if ns.UI.Status then ns.UI.Status("Not available yet", 1, 0.3, 0.3) end
        return false, "Not available yet"
    end
    local ok, a, b = pcall(f, g, ...)
    if not ok then report(a); return false, "Error" end
    -- Collect / Start return a table on success, nil + err on failure; others return ok, err
    if a == nil or a == false then
        if b and ns.UI.Status then ns.UI.Status(b, 1, 0.3, 0.3) end
        return false, b
    end
    return a, b
end

function Kit.Hero(id)
    if not id then return nil end
    return Kit.Call("GetHero", id)
end

function Kit.Item(key)
    return key and ns.D.ITEMS and ns.D.ITEMS[key]
end

------------------------------------------------------------------------
-- tooltips
------------------------------------------------------------------------

function Kit.AddLines(tt, lines)
    if not lines then return end
    for i = 1, #lines do
        local l = lines[i]
        if type(l) == "string" then
            tt:AddLine(l, 1, 1, 1, true)
        elseif type(l) == "table" then
            if type(l[2]) == "string" then
                tt:AddDoubleLine(l[1], l[2], l[3] or 1, l[4] or 0.82, l[5] or 0, l[6] or 1, l[7] or 1, l[8] or 1)
            else
                tt:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, l.wrap ~= false)
            end
        end
    end
end

function Kit.Tip(owner, title, lines, anchor, r, g, b)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title or "", r or 1, g or 0.82, b or 0, 1, true)
    Kit.AddLines(GameTooltip, lines)
    GameTooltip:Show()
end

local function tipLeave() GameTooltip:Hide() end

function Kit.SetTooltip(frame, fn)
    frame.wcTip = fn
    frame:SetScript("OnEnter", function(self)
        if not self.wcTip then return end
        GameTooltip:SetOwner(self, self.tipAnchor or "ANCHOR_RIGHT")
        local ok, err = pcall(self.wcTip, GameTooltip, self)
        if not ok then report(err) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", tipLeave)
end

local STATUS_COLOR = { IDLE = { 0.4, 1, 0.4 }, BUSY = { 0.75, 0.75, 0.75 }, READY = { 1, 0.82, 0 } }
local STATUS_TEXT = { IDLE = "Idle", BUSY = "Busy", READY = "Ready" }

function Kit.HeroTooltip(tt, h, opts)
    if not h then return end
    local r, g, b = Kit.ClassColor(h.class)
    tt:AddLine(h.name or "?", r, g, b)
    local cls = ns.D.CLASSES and ns.D.CLASSES[h.class]
    local qname = ns.D.QUALITY and ns.D.QUALITY[h.quality] or ""
    local qr, qg, qb = ns.QUALITY_COLOR(h.quality or 2)
    tt:AddLine(string.format("Level %d %s %s %s", h.level or 1, qname, ns.Util.RaceName(h.race), cls and cls.name or (h.class or "")), qr, qg, qb)
    local ilvl = floor(Kit.Call("HeroIlvl", h) or 0)
    local power = Kit.Call("HeroPower", h)
    tt:AddDoubleLine(Kit.RoleMarkup(h.role, 12) .. " " .. (ns.D.ROLES and ns.D.ROLES[h.role] and ns.D.ROLES[h.role].name or (h.role or "")),
        string.format("Item level %d", ilvl), 1, 1, 1, 1, 1, 1)
    if power then tt:AddDoubleLine("Power", tostring(U.Round(power)), 0.8, 0.8, 0.8, 1, 1, 1) end
    local need = Kit.Call("HeroXPNeeded", h)
    if need and need > 0 then tt:AddDoubleLine("Experience", string.format("%d / %d", h.xp or 0, need), 0.8, 0.8, 0.8, 1, 1, 1) end
    if h.traits and #h.traits > 0 then
        tt:AddLine(" ")
        for _, key in ipairs(h.traits) do
            local t = ns.D.TRAITS and ns.D.TRAITS[key]
            if t then
                local neg = (t.value or 0) < 0
                tt:AddLine(Kit.IconMarkup(t.icon, 14) .. " " .. (t.name or key), neg and 1 or 0.4, neg and 0.4 or 1, 0.4)
                if t.desc then tt:AddLine("   " .. t.desc, 0.7, 0.7, 0.7, true) end
            end
        end
    end
    if h.skills then
        local parts = {}
        for _, k in ipairs({ "MINING", "HERBALISM", "SKINNING", "FISHING" }) do
            if h.skills[k] and h.skills[k] > 0 then
                parts[#parts + 1] = string.format("%s %d", k:sub(1, 1) .. k:sub(2):lower(), h.skills[k])
            end
        end
        if #parts > 0 then tt:AddLine(table.concat(parts, "  "), 0.6, 0.8, 1, true) end
    end
    local st = not (opts and opts.noStatus) and Kit.Call("HeroStatus", h)
    if st then
        local c = STATUS_COLOR[st] or STATUS_COLOR.BUSY
        tt:AddLine(STATUS_TEXT[st] or st, c[1], c[2], c[3])
    end
end

function Kit.ItemTooltip(tt, spec)
    local q = spec.quality or 1
    local r, g, b = ns.QUALITY_COLOR(q)
    tt:SetText(spec.name or "?", r, g, b, 1, true)
    Kit.AddLines(tt, spec.lines)
    if spec.count and spec.count > 1 then tt:AddLine("Count: " .. spec.count, 0.8, 0.8, 0.8) end
end

------------------------------------------------------------------------
-- live updates (driven by the window's 0.5 s ticker)
------------------------------------------------------------------------

local live = setmetatable({}, { __mode = "k" })

function Kit.Live(frame, fn) live[frame] = fn end

function Kit.Tick(now)
    now = now or time()
    for f, fn in pairs(live) do
        if f:IsVisible() then
            local ok, err = pcall(fn, f, now)
            if not ok then live[f] = nil; report(err) end
        end
    end
end

------------------------------------------------------------------------
-- buttons
------------------------------------------------------------------------

local function ButtonEnter(self)
    local tip = self.wcTipText
    if self.wcReason and not self:IsEnabled() then tip = self.wcReason end
    if not tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if type(tip) == "function" then
        local ok, err = pcall(tip, GameTooltip, self)
        if not ok then report(err) end
    else
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

function Kit.Button(parent, text, w, h, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 80, h or 20)
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", ButtonEnter)
    b:SetScript("OnLeave", tipLeave)
    b.wcTipText = tip
    function b:SetTip(t) self.wcTipText = t end
    function b:SetEnabledTip(enabled, reason)
        self:SetEnabled(enabled and true or false)
        self.wcReason = (not enabled) and reason or nil
    end
    return b
end

function Kit.IconButton(parent, size, icon, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetAllPoints()
    b.Icon:SetTexture(icon or 134400)
    b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    if onClick then b:SetScript("OnClick", onClick) end
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", ButtonEnter)
    b:SetScript("OnLeave", tipLeave)
    b.wcTipText = tip
    function b:SetIcon(i) self.Icon:SetTexture(i or 134400) end
    function b:SetTip(t) self.wcTipText = t end
    return b
end

------------------------------------------------------------------------
-- section header
------------------------------------------------------------------------

function Kit.Header(parent, text, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 200, 18)
    f.Text = Kit.Text(f, "GameFontNormal")
    f.Text:SetPoint("LEFT", 2, 1)
    f.Text:SetText(text or "")
    f.right = Kit.Text(f, "GameFontHighlightSmall", "RIGHT")
    f.right:SetPoint("RIGHT", -2, 1)
    f.Line = f:CreateTexture(nil, "ARTWORK")
    f.Line:SetPoint("BOTTOMLEFT", 0, -2)
    f.Line:SetPoint("BOTTOMRIGHT", 0, -2)
    f.Line:SetHeight(4)
    if not Kit.Atlas(f.Line, "UI-LFG-DividerLine") then
        f.Line:SetHeight(1)
        f.Line:SetColorTexture(1, 0.82, 0, 0.35)
    end
    function f:SetText(t) self.Text:SetText(t or "") end
    return f
end

------------------------------------------------------------------------
-- row list
------------------------------------------------------------------------

local ListMixin = {}

-- hover glow for a row or tile. The atlas is opaque under normal blending and the HIGHLIGHT layer
-- draws above all text, so it must be additive: it can only brighten, never cover.
function Kit.RowHighlight(frame, alpha)
    local hl = frame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if Kit.Atlas(hl, "auctionhouse-ui-row-highlight") then
        hl:SetBlendMode("ADD")
        hl:SetAlpha(alpha or 0.45)
    else
        hl:SetColorTexture(1, 1, 1, 0.08)
    end
    return hl
end

local function RowClick(row, button)
    local L = row.wcList
    if not L then return end
    if L.opts.selectable then L:SetSelected(row.data) end
    if L.opts.onClick then
        local ok, err = pcall(L.opts.onClick, row, row.data, button, L)
        if not ok then report(err) end
    end
end

local function RowEnter(row)
    local L = row.wcList
    if not (L and L.opts.tooltip and row.data) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok, err = pcall(L.opts.tooltip, GameTooltip, row, row.data)
    if not ok then report(err) end
    if GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

function ListMixin:_InitRow(row, data)
    if not row.wcBuilt then
        row.wcBuilt = true
        row.wcList = self
        row:SetHeight(self.rowHeight)
        row.Stripe = row:CreateTexture(nil, "BACKGROUND")
        row.Stripe:SetAllPoints()
        if not Kit.Atlas(row.Stripe, "auctionhouse-rowstripe-1") then row.Stripe:SetColorTexture(1, 1, 1, 0.04) end
        row.Select = row:CreateTexture(nil, "BORDER")
        row.Select:SetAllPoints()
        if not Kit.Atlas(row.Select, "auctionhouse-ui-row-select") then row.Select:SetColorTexture(1, 0.82, 0, 0.18) end
        row.Select:Hide()
        Kit.RowHighlight(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", RowClick)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", tipLeave)
        if self.opts.build then
            local ok, err = pcall(self.opts.build, row, self)
            if not ok then report(err) end
        end
    end
    row.data = data
    row.index = self.indexOf[data] or 0
    row.Stripe:SetShown(self.opts.stripes ~= false and row.index % 2 == 0)
    row.Select:SetShown(self.selectedKey ~= nil and self:_Key(data) == self.selectedKey)
    if self.opts.update then
        local ok, err = pcall(self.opts.update, row, data, row.index, self)
        if not ok then report(err) end
    end
end

function ListMixin:_Key(data)
    if data == nil then return nil end
    if self.opts.key then
        local ok, k = pcall(self.opts.key, data)
        if ok then return k end
    end
    return data
end

function ListMixin:SetData(arr)
    arr = arr or {}
    self.data = arr
    local idx = {}
    for i = 1, #arr do idx[arr[i]] = i end
    self.indexOf = idx
    if self.box then
        local keep = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
        self.box:SetDataProvider(CreateDataProvider(arr), keep)
    else
        self:_FallbackLayout()
    end
end

function ListMixin:GetData() return self.data end

function ListMixin:ForEachRow(fn)
    if self.box then
        self.box:ForEachFrame(function(row) if row.data ~= nil then fn(row, row.data) end end)
    else
        for _, row in ipairs(self.rows) do if row:IsShown() then fn(row, row.data) end end
    end
end

function ListMixin:Refresh()
    self:ForEachRow(function(row, data) self:_InitRow(row, data) end)
end

function ListMixin:SetSelected(dataOrKey)
    if dataOrKey == nil then self.selectedKey = nil
    elseif type(dataOrKey) == "table" and self.indexOf[dataOrKey] then self.selectedKey = self:_Key(dataOrKey)
    else self.selectedKey = dataOrKey end
    self:ForEachRow(function(row, data) row.Select:SetShown(self.selectedKey ~= nil and self:_Key(data) == self.selectedKey) end)
end

function ListMixin:GetSelected()
    if self.selectedKey == nil then return nil end
    for _, d in ipairs(self.data) do
        if self:_Key(d) == self.selectedKey then return d end
    end
end

function ListMixin:ScrollToTop()
    if self.box and self.box.ScrollToBegin then pcall(self.box.ScrollToBegin, self.box)
    else self.offset = 0; self:_FallbackLayout() end
end

-- fallback when the client has no ScrollBox: a fixed pool, mouse wheel scrolls
function ListMixin:_FallbackLayout()
    local h = self:GetHeight()
    local n = max(1, floor(h / self.rowHeight))
    local total = #self.data
    self.offset = U.Clamp(self.offset or 0, 0, max(0, total - n))
    for i = 1, n do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Button", nil, self)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowHeight)
            row:SetPoint("RIGHT", -2, 0)
            self.rows[i] = row
        end
        local d = self.data[self.offset + i]
        if d ~= nil then self:_InitRow(row, d); row:Show() else row:Hide() end
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
end

function Kit.List(parent, opts)
    opts = opts or {}
    local L = CreateFrame("Frame", nil, parent)
    for k, v in pairs(ListMixin) do L[k] = v end
    L.opts = opts
    L.rowHeight = opts.rowHeight or 20
    L.data, L.indexOf, L.rows = {}, {}, {}
    if CreateScrollBoxListLinearView and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar and CreateDataProvider then
        local ok = pcall(function()
            local box = CreateFrame("Frame", nil, L, "WowScrollBoxList")
            box:SetPoint("TOPLEFT")
            box:SetPoint("BOTTOMRIGHT", -12, 0)
            local bar = CreateFrame("EventFrame", nil, L, "MinimalScrollBar")
            bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 3, -2)
            bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 3, 2)
            local view = CreateScrollBoxListLinearView()
            view:SetElementExtent(L.rowHeight)
            view:SetElementInitializer("Button", function(row, data) L:_InitRow(row, data) end)
            ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
            L.box, L.bar = box, bar
        end)
        if not ok then L.box = nil end
    end
    if not L.box then
        L:EnableMouseWheel(true)
        L:SetScript("OnMouseWheel", function(self, delta)
            self.offset = (self.offset or 0) - delta * 3
            self:_FallbackLayout()
        end)
        L:SetScript("OnSizeChanged", function(self) self:_FallbackLayout() end)
    end
    return L
end

------------------------------------------------------------------------
-- item button
------------------------------------------------------------------------

local ItemMixin = {}

function ItemMixin:SetQuality(q)
    self.quality = q
    Kit.QualityBorder(self.IconBorder, q or 1)
    self.IconBorder:Show()
end

function ItemMixin:SetCount(n)
    self.count = n
    if n and n > 1 then
        self.Count:SetText(n >= 10000 and (floor(n / 1000) .. "k") or tostring(n))
        self.Count:Show()
    else
        self.Count:Hide()
    end
end

function ItemMixin:SetItem(spec)
    self.spec = spec
    if not spec then return self:Clear() end
    local icon = spec.icon
    if spec.itemID then icon = ns.ItemIcon(spec.itemID, icon) end
    self.Icon:SetTexture(icon or 134400)
    self.Icon:Show()
    self:SetQuality(spec.quality or 1)
    self:SetCount(spec.count)
    self:Show()
end

function ItemMixin:SetItemKey(key, count, lines)
    local it = Kit.Item(key)
    if not it then
        return self:SetItem({ name = tostring(key), icon = 134400, quality = 1, count = count, lines = lines })
    end
    local l = {}
    if it.kind then l[#l + 1] = { (it.kind:sub(1, 1) .. it.kind:sub(2):lower()) .. (it.tier and ns.D.TIERS and ns.D.TIERS[it.tier] and ("  -  " .. ns.D.TIERS[it.tier].name) or ""), 0.8, 0.8, 0.8 } end
    if lines then for _, x in ipairs(lines) do l[#l + 1] = x end end
    local have = Kit.Call("Count", key)
    if have then l[#l + 1] = { "In storage", tostring(have), 0.6, 0.6, 0.6, 1, 1, 1 } end
    self:SetItem({ name = it.name, itemID = it.itemID, icon = it.icon, quality = it.quality, count = count, lines = l })
    self.itemKey = key
end

function ItemMixin:SetGear(g)
    if not g then return self:Clear() end
    local slot = g.slot and (g.slot:sub(1, 1) .. g.slot:sub(2):lower()) or ""
    self:SetItem({ name = g.name, itemID = g.itemID, quality = g.quality,
        lines = { { "Item level " .. (g.ilvl or 0), 1, 0.82, 0 }, { slot, 1, 1, 1 } } })
    self.gear = g
end

function ItemMixin:Clear()
    self.spec, self.itemKey, self.gear = nil, nil, nil
    self.Icon:SetTexture(nil)
    self.IconBorder:Hide()
    self.Count:Hide()
end

function ItemMixin:SetDesaturated(on)
    self.Icon:SetDesaturated(on and true or false)
end

function Kit.ItemButton(parent, size)
    size = size or 32
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    for k, v in pairs(ItemMixin) do b[k] = v end
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("TOPLEFT", 1, -1)
    b.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.IconBorder = b:CreateTexture(nil, "OVERLAY")
    b.IconBorder:SetAllPoints()
    b.IconBorder:Hide()
    b.Count = b:CreateFontString(nil, "OVERLAY", size >= 30 and "NumberFontNormal" or "NumberFontNormalSmall")
    b.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.Count:SetJustifyH("RIGHT")
    b.Count:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    b:SetScript("OnEnter", function(self)
        if not self.spec then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        Kit.ItemTooltip(GameTooltip, self.spec)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", tipLeave)
    b:SetScript("OnClick", function(self, button)
        if self.spec and self.spec.onClick then
            local ok, err = pcall(self.spec.onClick, self, button)
            if not ok then report(err) end
        end
    end)
    return b
end

------------------------------------------------------------------------
-- hero badge (one line)
------------------------------------------------------------------------

local BadgeMixin = {}

function BadgeMixin:SetHero(h, statusText, r, g, b)
    self.hero = h
    if not h then return self:Clear() end
    Kit.ClassIcon(self.Class, h.class)
    self.Class:Show()
    local qr, qg, qb = ns.QUALITY_COLOR(h.quality or 2)
    self.ClassRing:SetVertexColor(qr, qg, qb, 0.9)
    self.ClassRing:Show()
    local cr, cg, cb = Kit.ClassColor(h.class)
    self.Name:SetText(h.name or "?")
    self.Name:SetTextColor(cr, cg, cb)
    self.Level:SetText(tostring(h.level or 1))
    local il = Kit.Call("HeroIlvl", h)
    self.Ilvl:SetText(il and tostring(floor(il)) or "")
    Kit.RoleIcon(self.Role, h.role)
    self.Role:Show()
    if not statusText then
        local st = Kit.Call("HeroStatus", h) or "IDLE"
        local c = STATUS_COLOR[st] or STATUS_COLOR.BUSY
        statusText, r, g, b = STATUS_TEXT[st] or st, c[1], c[2], c[3]
    end
    self.Status:SetText(statusText or "")
    self.Status:SetTextColor(r or 0.8, g or 0.8, b or 0.8)
end

function BadgeMixin:Clear()
    self.hero = nil
    self.Class:Hide(); self.ClassRing:Hide(); self.Role:Hide()
    self.Name:SetText(""); self.Level:SetText(""); self.Ilvl:SetText(""); self.Status:SetText("")
end

function Kit.HeroBadge(parent, width, height)
    height = height or 20
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 260, height)
    for k, v in pairs(BadgeMixin) do f[k] = v end
    local isz = height - 4
    f.Class = f:CreateTexture(nil, "ARTWORK")
    f.Class:SetSize(isz, isz)
    f.Class:SetPoint("LEFT", 2, 0)
    f.ClassRing = f:CreateTexture(nil, "OVERLAY")
    f.ClassRing:SetPoint("TOPLEFT", f.Class, -1, 1)
    f.ClassRing:SetPoint("BOTTOMRIGHT", f.Class, 1, -1)
    f.ClassRing:SetTexture("Interface\\Common\\WhiteIconFrame")
    f.Status = Kit.Text(f, "GameFontHighlightSmall", "RIGHT")
    f.Status:SetPoint("RIGHT", -2, 0)
    f.Status:SetWidth(54)
    f.Role = f:CreateTexture(nil, "ARTWORK")
    f.Role:SetSize(isz - 2, isz - 2)
    f.Role:SetPoint("RIGHT", f.Status, "LEFT", -4, 0)
    f.Ilvl = Kit.Text(f, "GameFontHighlightSmall", "RIGHT")
    f.Ilvl:SetPoint("RIGHT", f.Role, "LEFT", -4, 0)
    f.Ilvl:SetWidth(30)
    f.Ilvl:SetTextColor(1, 0.82, 0)
    f.Level = Kit.Text(f, "GameFontHighlightSmall", "RIGHT")
    f.Level:SetPoint("RIGHT", f.Ilvl, "LEFT", -4, 0)
    f.Level:SetWidth(20)
    f.Name = Kit.Text(f, "GameFontNormalSmall")
    f.Name:SetPoint("LEFT", f.Class, "RIGHT", 5, 0)
    f.Name:SetPoint("RIGHT", f.Level, "LEFT", -4, 0)
    f:Clear()
    return f
end

------------------------------------------------------------------------
-- model view
------------------------------------------------------------------------

local ModelMixin = {}

function ModelMixin:_Apply()
    pcall(self.model.SetFacing, self.model, self.facing)
    pcall(self.model.SetCamDistanceScale, self.model, self.zoom)
end

function ModelMixin:ResetView()
    self.facing, self.zoom, self.spin = self.baseFacing or 0.35, 1, self.idleSpin
    self:_Apply()
end

function ModelMixin:SetSpin(on) self.idleSpin = on and true or false; self.spin = self.idleSpin end

function ModelMixin:SetIcon(icon)
    self.token = (self.token or 0) + 1
    self.model:Hide()
    self.icon:SetTexture(icon or 134400)
    self.icon:Show()
    if self.hint then self.hint:Hide() end
    self.shownKey = nil
end

function ModelMixin:Clear()
    self.token = (self.token or 0) + 1
    self.shownKey = nil
    pcall(self.model.ClearModel, self.model)
    self.model:Hide()
    self.icon:Hide()
    if self.hint then self.hint:Hide() end
end

-- show a model; method "SetDisplayInfo" | "SetCreature"; checks it really loaded, else the icon
function ModelMixin:_Show(method, id, fallbackIcon)
    if not id then
        if fallbackIcon then self:SetIcon(fallbackIcon) else self:Clear() end
        return false
    end
    local key = method .. ":" .. tostring(id)
    if self.shownKey == key and self.model:IsShown() then return true end
    -- a model that did not load recently: stay on the icon instead of blinking model/icon on every refresh
    local failedAt = self.failed and self.failed[key]
    if failedAt and fallbackIcon and time() - failedAt < 60 then
        self:SetIcon(fallbackIcon)
        return false
    end
    self.token = (self.token or 0) + 1
    local token = self.token
    self.icon:Hide()
    self.model:Show()
    pcall(self.model.ClearModel, self.model)
    local ok = pcall(self.model[method], self.model, id)
    if not ok then
        if fallbackIcon then self:SetIcon(fallbackIcon) else self:Clear() end
        return false
    end
    self.shownKey = key
    pcall(self.model.SetPortraitZoom, self.model, 0)
    self:ResetView()
    if self.hint then self.hint:Show() end
    if C_Timer and C_Timer.After then
        -- a cold model can take longer than 0.6 s to stream in: look twice before giving up on it
        local function check(final)
            if self.token ~= token or not self.model:IsShown() then return end
            local ok2, file = pcall(self.model.GetModelFileID, self.model)
            if ok2 and (file == nil or file == 0) then
                if not final then C_Timer.After(1.5, function() check(true) end)
                elseif fallbackIcon then
                    self.failed = self.failed or {}
                    self.failed[key] = time()
                    self:SetIcon(fallbackIcon)
                end
            end
        end
        C_Timer.After(0.6, function() check(false) end)
    end
    return true
end

function ModelMixin:SetDisplay(displayID, fallbackIcon) return self:_Show("SetDisplayInfo", displayID, fallbackIcon) end
function ModelMixin:SetCreature(npcID, fallbackIcon) return self:_Show("SetCreature", npcID, fallbackIcon) end

function ModelMixin:SetMount(mountID)
    local display, icon
    if mountID and C_MountJournal then
        if C_MountJournal.GetMountInfoExtraByID then
            local ok, d = pcall(C_MountJournal.GetMountInfoExtraByID, mountID)
            if ok and d and d > 0 then display = d end
        end
        if not display and C_MountJournal.GetMountAllCreatureDisplayInfoByID then
            local ok, list = pcall(C_MountJournal.GetMountAllCreatureDisplayInfoByID, mountID)
            if ok and type(list) == "table" and list[1] then display = list[1].creatureDisplayID end
        end
        if C_MountJournal.GetMountInfoByID then
            local ok, _, _, i = pcall(C_MountJournal.GetMountInfoByID, mountID)
            if ok then icon = i end
        end
    end
    return self:SetDisplay(display, icon or 134400)
end

function ModelMixin:SetPet(speciesID)
    local display, creature, icon
    if speciesID and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local r = { pcall(C_PetJournal.GetPetInfoBySpeciesID, speciesID) }
        if r[1] then
            icon, creature, display = r[3], r[5], r[13]
        end
    end
    if display and display > 0 then return self:SetDisplay(display, icon or 134400) end
    if creature and creature > 0 then return self:SetCreature(creature, icon or 134400) end
    self:SetIcon(icon or 134400)
    return false
end

function ModelMixin:SetCaption(text)
    if self.caption then self.caption:SetText(text or "") end
end

function Kit.ModelView(parent, w, h, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 200, h or 200)
    for k, v in pairs(ModelMixin) do f[k] = v end
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    if opts.bg ~= false then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        if CreateColor then
            local ok = pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(0.03, 0.025, 0.02, 0.95), CreateColor(0.2, 0.15, 0.08, 0.7))
            if not ok then bg:SetColorTexture(0.08, 0.06, 0.04, 0.85) end
        else
            bg:SetColorTexture(0.08, 0.06, 0.04, 0.85)
        end
    end
    f.model = CreateFrame("PlayerModel", nil, f)
    f.model:SetPoint("TOPLEFT", 2, -2)
    f.model:SetPoint("BOTTOMRIGHT", -2, opts.caption and 16 or 2)
    f.model:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    local isz = min(64, (min(w or 200, h or 200)) * 0.5)
    f.icon:SetSize(isz, isz)
    f.icon:SetPoint("CENTER", 0, opts.caption and 6 or 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon:Hide()
    if opts.caption then
        f.caption = Kit.Text(f, "GameFontNormalSmall", "CENTER")
        f.caption:SetPoint("BOTTOMLEFT", 4, 3)
        f.caption:SetPoint("BOTTOMRIGHT", -4, 3)
    end
    if opts.hint then
        f.hint = Kit.Text(f, "GameFontDisableSmall")
        f.hint:SetPoint("TOPLEFT", 4, -3)
        f.hint:SetText("Drag to turn, wheel to zoom")
        f.hint:Hide()
    end
    f.idleSpin = opts.spin ~= false
    f.baseFacing = opts.facing or 0.35
    f.facing, f.zoom, f.spin = f.baseFacing, 1, f.idleSpin
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX = GetCursorPosition(); self.spin = false end
    end)
    f:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    f:SetScript("OnHide", function(self) self.dragX = nil end)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = max(0.4, min(3, self.zoom - delta * 0.15))
        self:_Apply()
    end)
    -- OnUpdate only runs while the frame is shown, i.e. while the window is open
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self.model:IsShown() then return end
        if self.dragX then
            local x = GetCursorPosition()
            self.facing = self.facing + (x - self.dragX) * 0.012
            self.dragX = x
            self:_Apply()
        elseif self.spin then
            self.facing = self.facing + elapsed * 0.3
            pcall(self.model.SetFacing, self.model, self.facing)
        end
    end)
    return f
end

------------------------------------------------------------------------
-- progress bar
------------------------------------------------------------------------

local BarMixin = {}
local BAR_RUN = { 0.2, 0.45, 0.85 }
local BAR_READY = { 0.15, 0.7, 0.15 }

function BarMixin:SetBarColor(r, g, b) self:SetStatusBarColor(r, g, b) end

function BarMixin:SetProgress(frac, text, r, g, b)
    self.startAt, self.endAt = nil, nil
    self:SetValue(U.Clamp(frac or 0, 0, 1))
    self.Text:SetText(text or "")
    if r then self:SetStatusBarColor(r, g, b) end
end

function BarMixin:SetValueText(cur, maxv, fmt)
    maxv = max(1, maxv or 1)
    self:SetProgress((cur or 0) / maxv, string.format(fmt or "%d / %d", cur or 0, maxv))
end

function BarMixin:_UpdateTimes(now)
    if not self.endAt then return end
    now = now or time()
    local s, e = self.startAt or now, self.endAt
    if now >= e then
        self:SetValue(1)
        self.Text:SetText("Ready!")
        self.Text:SetTextColor(1, 0.82, 0)
        self:SetStatusBarColor(BAR_READY[1], BAR_READY[2], BAR_READY[3])
    else
        self:SetValue(U.Clamp((now - s) / max(1, e - s), 0, 1))
        self.Text:SetText(U.Duration(e - now))
        self.Text:SetTextColor(1, 1, 1)
        self:SetStatusBarColor(BAR_RUN[1], BAR_RUN[2], BAR_RUN[3])
    end
end

function BarMixin:SetTimes(startAt, endAt)
    self.startAt, self.endAt = startAt, endAt
    self:_UpdateTimes()
end

function BarMixin:IsReady(now) return self.endAt ~= nil and (now or time()) >= self.endAt end

function Kit.ProgressBar(parent, w, h)
    h = h or 14
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetSize(w or 100, h)
    for k, v in pairs(BarMixin) do b[k] = v end
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b:SetStatusBarColor(BAR_RUN[1], BAR_RUN[2], BAR_RUN[3])
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    -- the garrison follower XP bar frame (Blizzard_GarrisonTemplates: GarrisonFollowerXPBarTemplate)
    local l = b:CreateTexture(nil, "OVERLAY")
    local r = b:CreateTexture(nil, "OVERLAY")
    local m = b:CreateTexture(nil, "OVERLAY")
    if Kit.Atlas(l, "GarrMission_XPBarBig-End") and Kit.Atlas(r, "GarrMission_XPBarBig-End") and Kit.Atlas(m, "GarrMission_XPBarBig-Mid") then
        l:SetSize(6, h + 4); l:SetPoint("LEFT", -3, 0); l:SetTexCoord(1, 0, 0, 1)
        r:SetSize(6, h + 4); r:SetPoint("RIGHT", 3, 0)
        m:SetHeight(h + 4); m:SetPoint("LEFT", l, "RIGHT"); m:SetPoint("RIGHT", r, "LEFT")
    else
        l:Hide(); r:Hide(); m:Hide()
    end
    b.Text = b:CreateFontString(nil, "OVERLAY", h >= 14 and "GameFontHighlightSmall" or "GameFontHighlightExtraSmall")
    b.Text:SetPoint("CENTER", 0, 0)
    Kit.Live(b, b._UpdateTimes)
    return b
end

------------------------------------------------------------------------
-- coin text
------------------------------------------------------------------------

function Kit.CoinText(parent, template)
    local fs = Kit.Text(parent, template or "GameFontHighlightSmall", "RIGHT")
    function fs:SetCopper(c, short) self:SetText(Kit.Coin(c, short)) end
    return fs
end

------------------------------------------------------------------------
-- chance meter
------------------------------------------------------------------------

function Kit.ChanceColor(c)
    if not c then return 0.6, 0.6, 0.6 end
    if c >= 0.8 then return 0.25, 1, 0.25 end
    if c >= 0.5 then return 1, 0.85, 0.1 end
    return 1, 0.25, 0.2
end

function Kit.ChanceMeter(parent, w, h)
    local m = Kit.ProgressBar(parent, w or 80, h or 12)
    Kit.Live(m, nil)
    function m:SetChance(c)
        if not c then self:SetProgress(0, "--", 0.4, 0.4, 0.4); return end
        local r, g, b = Kit.ChanceColor(c)
        self:SetProgress(c, string.format("%d%%", floor(c * 100 + 0.5)), r * 0.75, g * 0.75, b * 0.75)
        self.Text:SetTextColor(1, 1, 1)
    end
    m:SetChance(nil)
    return m
end

------------------------------------------------------------------------
-- threat icons
------------------------------------------------------------------------

local function CounterClasses(threat)
    local out = {}
    for class, def in pairs(ns.D.CLASSES or {}) do
        for _, k in ipairs(def.counters or {}) do
            if k == threat then out[#out + 1] = Kit.ClassMarkup(class, 12) .. " " .. (def.name or class) end
        end
    end
    table.sort(out)
    return out
end

function Kit.ThreatIcons(parent, size, maxN)
    size, maxN = size or 18, maxN or 6
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(maxN * (size + 3), size)
    f.icons = {}
    for i = 1, maxN do
        local b = CreateFrame("Frame", nil, f)
        b:SetSize(size, size)
        b:SetPoint("LEFT", (i - 1) * (size + 3), 0)
        b:EnableMouse(true)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetAllPoints()
        b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.Border = b:CreateTexture(nil, "OVERLAY")
        b.Border:SetPoint("TOPLEFT", -1, 1)
        b.Border:SetPoint("BOTTOMRIGHT", 1, -1)
        b.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
        b.Check = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.Check:SetSize(size * 0.7, size * 0.7)
        b.Check:SetPoint("BOTTOMRIGHT", 3, -3)
        if not Kit.Atlas(b.Check, "GarrMission_CounterCheck") then Kit.Atlas(b.Check, "groupfinder-icon-greencheckmark", { 0.2, 1, 0.2, 1 }) end
        Kit.SetTooltip(b, function(tt, self)
            local def = ns.D.THREATS and ns.D.THREATS[self.key] or {}
            tt:SetText(def.name or tostring(self.key), 1, 0.82, 0)
            if def.desc then tt:AddLine(def.desc, 1, 1, 1, true) end
            if self.countered then
                tt:AddLine("Countered by your party", 0.3, 1, 0.3)
            else
                tt:AddLine("Not countered. Bring one of:", 1, 0.4, 0.3)
                for _, s in ipairs(CounterClasses(self.key)) do tt:AddLine("  " .. s, 1, 1, 1) end
            end
        end)
        b:Hide()
        f.icons[i] = b
    end
    function f:SetThreats(list, countered)
        list = list or {}
        self.used = 0
        for i = 1, #self.icons do
            local b, key = self.icons[i], list[i]
            if key then
                local def = ns.D.THREATS and ns.D.THREATS[key] or {}
                b.key = key
                b.countered = countered and countered[key] and true or false
                b.Icon:SetTexture(def.icon or 134400)
                b.Icon:SetDesaturated(false)
                b.Check:SetShown(b.countered)
                if b.countered then b.Border:SetVertexColor(0.3, 1, 0.3) else b.Border:SetVertexColor(0.9, 0.25, 0.2) end
                b:Show()
                self.used = i
            else
                b:Hide()
            end
        end
    end
    function f:GetWidthUsed() return (self.used or 0) * (size + 3) end
    return f
end

------------------------------------------------------------------------
-- menus
------------------------------------------------------------------------

local dropdown
local function OwnDropdown(owner, title, entries)
    if not dropdown then
        dropdown = CreateFrame("Frame", nil, UIParent)
        dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
        dropdown:SetClampedToScreen(true)
        dropdown:EnableMouse(true)
        local ok, border = pcall(CreateFrame, "Frame", nil, dropdown, "DialogBorderDarkTemplate")
        if ok and border then border:SetAllPoints() else Kit.Backdrop(dropdown, 0.95) end
        dropdown.title = Kit.Text(dropdown, "GameFontNormalSmall")
        dropdown.title:SetPoint("TOPLEFT", 12, -10)
        dropdown.buttons = {}
        dropdown:Hide()
    end
    local d = dropdown
    d.title:SetText(title or "")
    local y, width = -26, 160
    local n = 0
    for _, e in ipairs(entries) do
        if not e.divider and not e.title then
            n = n + 1
            if n > 24 then break end
            local b = d.buttons[n]
            if not b then
                b = CreateFrame("Button", nil, d)
                b:SetHeight(16)
                b.Text = Kit.Text(b, "GameFontHighlightSmall")
                b.Text:SetPoint("LEFT", 2, 0)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.12)
                d.buttons[n] = b
            end
            b.Text:SetText(e.text or "")
            b:SetEnabled(not e.disabled)
            b.Text:SetTextColor(e.disabled and 0.5 or 1, e.disabled and 0.5 or 1, e.disabled and 0.5 or 1)
            b:SetScript("OnClick", function() d:Hide(); if e.func then e.func() end end)
            b:SetPoint("TOPLEFT", 12, y)
            b:SetPoint("RIGHT", -12, 0)
            b:Show()
            width = max(width, b.Text:GetStringWidth() + 30)
            y = y - 16
        end
    end
    for i = n + 1, #d.buttons do d.buttons[i]:Hide() end
    d:SetSize(width, -y + 12)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    d:Show()
    owner.wcDropdownOwner = true
    -- closes when its owner hides
    if not owner.wcDropdownHooked then
        owner.wcDropdownHooked = true
        owner:HookScript("OnHide", function() if dropdown then dropdown:Hide() end end)
    end
end

function Kit.Menu(owner, title, entries)
    entries = entries or {}
    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            if title then root:CreateTitle(title) end
            local count = 0
            for _, e in ipairs(entries) do
                if e.divider then root:CreateDivider()
                elseif e.title then root:CreateTitle(e.text or "")
                else
                    count = count + 1
                    local func = e.func
                    local btn = root:CreateButton(e.text or "", function() if func then func() end end)
                    if e.disabled and btn.SetEnabled then btn:SetEnabled(false) end
                    if e.tooltip and btn.SetTooltip then
                        local tip = e.tooltip
                        btn:SetTooltip(function(tooltip)
                            if type(tip) == "function" then tip(tooltip) else tooltip:SetText(tip, 1, 1, 1, 1, true) end
                        end)
                    end
                end
            end
            if count > 18 and root.SetScrollMode then root:SetScrollMode(18 * 20) end
        end)
        if ok then return end
    end
    OwnDropdown(owner, title, entries)
end

------------------------------------------------------------------------
-- party slot picker
------------------------------------------------------------------------

local PickerMixin = {}

local function IdleHeroes()
    local out = {}
    for _, h in ipairs(Kit.Call("GetHeroes") or {}) do
        if (Kit.Call("HeroStatus", h) or "IDLE") == "IDLE" then out[#out + 1] = h end
    end
    return out
end

function PickerMixin:_Changed()
    if self.opts.onChange then
        local ok, err = pcall(self.opts.onChange, self:GetHeroes(), self)
        if not ok then report(err) end
    end
end

function PickerMixin:_UpdateSlot(i)
    local s = self.slots[i]
    local h = Kit.Hero(self.ids[i])
    if h then
        Kit.ClassIcon(s.Icon, h.class)
        s.Icon:Show()
        s.Plus:Hide()
        s.Level:SetText(tostring(h.level or ""))
        local r, g, b = ns.QUALITY_COLOR(h.quality or 2)
        s.Ring:SetVertexColor(r, g, b)
    else
        self.ids[i] = nil
        s.Icon:Hide()
        s.Plus:SetShown(self.enabled)
        s.Level:SetText("")
        s.Ring:SetVertexColor(1, 1, 1)
    end
end

function PickerMixin:_Open(i)
    if not self.enabled then return end
    local chosen = {}
    for j = 1, self.n do if self.ids[j] then chosen[self.ids[j]] = true end end
    local list = self.opts.candidates and self.opts.candidates(self) or IdleHeroes()
    local entries = {}
    if self.ids[i] then
        entries[#entries + 1] = { text = "|cffff6060Remove|r " .. Kit.HeroName(Kit.Hero(self.ids[i])), func = function()
            self.ids[i] = nil; self:_UpdateSlot(i); self:_Changed()
        end }
        entries[#entries + 1] = { divider = true }
    end
    for _, h in ipairs(list) do
        if not chosen[h.id] then
            local extra = self.opts.label and self.opts.label(h) or ""
            local text = string.format("%s %s %s |cffffd100%d|r  |cff9d9d9di%d|r %s", Kit.ClassMarkup(h.class, 14), Kit.RoleMarkup(h.role, 12),
                Kit.HeroName(h), h.level or 1, floor(Kit.Call("HeroIlvl", h) or 0), extra)
            local id = h.id
            entries[#entries + 1] = { text = text, func = function()
                self.ids[i] = id; self:_UpdateSlot(i); self:_Changed()
            end, tooltip = function(tt) Kit.HeroTooltip(tt, Kit.Hero(id)) end }
        end
    end
    if #list == 0 then entries[#entries + 1] = { text = "No idle heroes", disabled = true } end
    Kit.Menu(self.slots[i], "Choose a hero", entries)
end

function PickerMixin:SetSlots(n)
    self.n = n
    local size, sp = self.opts.size or 30, self.opts.spacing or 4
    for i = 1, max(n, #self.slots) do
        local s = self.slots[i]
        if i <= n and not s then
            s = CreateFrame("Button", nil, self)
            s:SetSize(size, size)
            s:SetPoint("LEFT", (i - 1) * (size + sp), 0)
            s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local bg = s:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.6)
            s.Icon = s:CreateTexture(nil, "ARTWORK")
            s.Icon:SetPoint("TOPLEFT", 2, -2)
            s.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
            s.Plus = s:CreateTexture(nil, "ARTWORK", nil, 1)
            s.Plus:SetSize(size * 0.6, size * 0.6)
            s.Plus:SetPoint("CENTER")
            if not Kit.Atlas(s.Plus, "Garr_Building-AddFollowerPlus") then
                Kit.Atlas(s.Plus, nil, "Interface\\PaperDollInfoFrame\\Character-Plus")
            end
            s.Ring = s:CreateTexture(nil, "OVERLAY")
            s.Ring:SetPoint("TOPLEFT", -1, 1)
            s.Ring:SetPoint("BOTTOMRIGHT", 1, -1)
            s.Ring:SetTexture("Interface\\Common\\WhiteIconFrame")
            s.Level = s:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            s.Level:SetPoint("BOTTOMRIGHT", -1, 1)
            local hl = s:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            hl:SetBlendMode("ADD")
            local idx = i
            s:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if self.ids[idx] and self.enabled then self.ids[idx] = nil; self:_UpdateSlot(idx); self:_Changed() end
                else
                    self:_Open(idx)
                end
            end)
            Kit.SetTooltip(s, function(tt)
                local h = Kit.Hero(self.ids[idx])
                if h then
                    Kit.HeroTooltip(tt, h)
                    tt:AddLine("Right-click to remove", 0.5, 0.5, 0.5)
                else
                    tt:SetText("Empty slot", 1, 0.82, 0)
                    tt:AddLine("Click to choose an idle hero", 1, 1, 1)
                end
            end)
            self.slots[i] = s
        end
        if s then
            s:SetShown(i <= n)
            if i > n then self.ids[i] = nil end
        end
    end
    self:SetWidth(n * (size + sp) - sp)
    for i = 1, n do self:_UpdateSlot(i) end
end

function PickerMixin:SetHeroes(ids)
    self.ids = {}
    for i = 1, self.n do self.ids[i] = ids and ids[i] or nil end
    for i = 1, self.n do self:_UpdateSlot(i) end
end

function PickerMixin:GetHeroes()
    local out = {}
    for i = 1, self.n do if self.ids[i] then out[#out + 1] = self.ids[i] end end
    return out
end

function PickerMixin:Clear() self:SetHeroes({}) end

function PickerMixin:SetEnabled(on)
    self.enabled = on and true or false
    for i = 1, self.n do self:_UpdateSlot(i) end
end

function Kit.PartyPicker(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    for k, v in pairs(PickerMixin) do f[k] = v end
    f.opts = opts
    f.slots, f.ids, f.enabled = {}, {}, true
    f:SetHeight(opts.size or 30)
    f:SetSlots(opts.slots or 3)
    return f
end
