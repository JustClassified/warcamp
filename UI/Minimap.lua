--[[ Warcamp minimap button (own small implementation, LibDBIcon geometry) and AddonCompartment functions.

  ns.UI.UpdateMinimap()        creates the button on first call (Main.lua calls it from its 5 s ticker,
                               after Game:Init), then refreshes the ready-count badge
  ns.UI.SetMinimapShown(bool)  saved in WarcampDB.ui.minimapHide
  WarcampDB.ui.minimapAngle    degrees around the minimap (drag to move)
  Globals: Warcamp_OnAddonCompartmentClick / Warcamp_OnAddonCompartmentEnter / Warcamp_OnAddonCompartmentLeave
]]

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util

local button

local function DB()
    if type(WarcampDB) ~= "table" then return nil end
    if type(WarcampDB.ui) ~= "table" then WarcampDB.ui = {} end
    return WarcampDB.ui
end

local function Icon()
    return (UI.Faction and UI.Faction() == "Alliance") and "Interface\\Icons\\INV_BannerPVP_02" or "Interface\\Icons\\INV_BannerPVP_01"
end

-- shared tooltip for the button and the compartment entry
local function FillTooltip(tt)
    tt:SetText("Warcamp", 1, 0.82, 0)
    local now = time()
    local tasks = Kit.Call("GetTasks") or {}
    local ready, running = {}, {}
    for _, t in ipairs(tasks) do
        if t.kind ~= "BUILD" and now >= t.endAt then ready[#ready + 1] = t else running[#running + 1] = t end
    end
    if #ready > 0 then
        tt:AddLine(string.format("%d ready to collect", #ready), 0.3, 1, 0.3)
        for i, t in ipairs(ready) do
            if i > 8 then tt:AddLine(string.format("  ... and %d more", #ready - 8), 0.6, 0.6, 0.6); break end
            tt:AddLine("  " .. (t.name or "?"), 1, 1, 1)
        end
    else
        tt:AddLine("Nothing ready yet", 0.6, 0.6, 0.6)
    end
    if #running > 0 then
        tt:AddLine(" ")
        for i, t in ipairs(running) do
            if i > 5 then tt:AddLine(string.format("  ... and %d more", #running - 5), 0.6, 0.6, 0.6); break end
            tt:AddDoubleLine(t.name or "?", U.Duration(t.endAt - now), 0.8, 0.8, 0.8, 0.6, 0.8, 1)
        end
    end
    local gold = Kit.Call("Gold")
    if gold then tt:AddDoubleLine("Gold", Kit.Coin(gold, true), 1, 0.82, 0, 1, 1, 1) end
    tt:AddLine(" ")
    tt:AddLine("Left-click: open / close", 0.6, 0.6, 0.6)
    tt:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
end

------------------------------------------------------------------------
-- position
------------------------------------------------------------------------

local function Place()
    if not button then return end
    local db = DB()
    local deg = db and db.minimapAngle or 200
    local a = math.rad(deg)
    local x, y = math.cos(a), math.sin(a)
    local r = (Minimap:GetWidth() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- push to the square's edge
        local m = math.max(math.abs(x), math.abs(y))
        if m > 0 then x, y = x / m, y / m end
        r = r - 2
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function DragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local deg = math.deg(math.atan2(cy - my, cx - mx)) % 360
    local db = DB()
    if db then db.minimapAngle = deg end
    Place()
end

------------------------------------------------------------------------
-- button
------------------------------------------------------------------------

local function Create()
    if button or not Minimap then return end
    local b = CreateFrame("Button", nil, Minimap)
    button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetFixedFrameStrata(true)
    b:SetFixedFrameLevel(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture(136477)  -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetTexture(136430)     -- Interface\Minimap\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetTexture(136467)          -- Interface\Minimap\UI-Minimap-Background
    bg:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER")
    b.icon:SetTexture(Icon())
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.badge:SetPoint("BOTTOMRIGHT", 2, 0)
    b.badge:SetTextColor(0.3, 1, 0.3)

    b:SetScript("OnClick", function() UI.Toggle() end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", DragUpdate)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        if self.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local ok, err = pcall(FillTooltip, GameTooltip)
        if not ok and geterrorhandler then geterrorhandler()(err) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

function UI.UpdateMinimap()
    local db = DB()
    if not db then return end
    if db.minimapHide then
        if button then button:Hide() end
        return
    end
    if not button then Create() end
    if not button then return end
    button:Show()
    local n = Kit.Call("ReadyCount", time()) or 0
    button.badge:SetText(n > 0 and tostring(n) or "")
end

function UI.SetMinimapShown(shown)
    local db = DB()
    if db then db.minimapHide = not shown end
    UI.UpdateMinimap()
end

ns.On("CHANGED", function()
    if button then UI.UpdateMinimap() end
end)

------------------------------------------------------------------------
-- addon compartment (TOC: AddonCompartmentFunc / OnEnter / OnLeave)
------------------------------------------------------------------------

function Warcamp_OnAddonCompartmentClick()
    UI.Toggle()
end

function Warcamp_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    local ok, err = pcall(FillTooltip, GameTooltip)
    if not ok and geterrorhandler then geterrorhandler()(err) end
    GameTooltip:Show()
end

function Warcamp_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
