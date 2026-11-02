--[[ Warcamp options: a page in Options > AddOns, plus the export / import window.

  ns.UI.OpenOptions()            opens Options > AddOns > Warcamp
  ns.UI.ShowSaveDialog(mode)     mode "export" (string ready to copy) or "import" (paste box)
]]

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util

local category

local function DB()
    if type(WarcampDB) ~= "table" then return nil end
    if type(WarcampDB.ui) ~= "table" then WarcampDB.ui = {} end
    return WarcampDB.ui
end

-- a button that asks for a second click within 4 s before doing something it cannot take back
local function ConfirmButton(parent, text, w, confirmText, fn)
    local b
    b = Kit.Button(parent, text, w, 22, function()
        if b.armed and GetTime() - b.armed < 4 then
            b.armed = nil
            b:SetText(text)
            fn()
        else
            b.armed = GetTime()
            b:SetText(confirmText)
            C_Timer.After(4, function()
                if b.armed and GetTime() - b.armed >= 3.9 then b.armed = nil; b:SetText(text) end
            end)
        end
    end)
    return b
end

------------------------------------------------------------------------
-- export / import window
------------------------------------------------------------------------

local dialog

local function BuildDialog()
    -- named only so Escape closes it (UISpecialFrames takes names)
    local ok, f = pcall(CreateFrame, "Frame", "WarcampSaveFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", nil, UIParent)
        Kit.Backdrop(f, 0.9)
    end
    f:SetSize(520, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if UISpecialFrames then tinsert(UISpecialFrames, "WarcampSaveFrame") end

    f.Title = Kit.Text(f, "GameFontNormal", "CENTER")
    f.Title:SetPoint("TOP", 0, -5)

    f.Help = Kit.Text(f, "GameFontHighlightSmall")
    f.Help:SetPoint("TOPLEFT", 14, -30)
    f.Help:SetPoint("RIGHT", -14, 0)
    f.Help:SetWordWrap(true)
    f.Help:SetJustifyV("TOP")
    f.Help:SetHeight(28)

    local inset = Kit.Inset(f)
    inset:SetPoint("TOPLEFT", 10, -62)
    inset:SetPoint("BOTTOMRIGHT", -10, 40)

    local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontSmall or GameFontHighlightSmall)
    edit:SetWidth(460)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.Edit = edit

    -- export mode keeps its text: typing into it puts the string back
    edit:SetScript("OnTextChanged", function(self, user)
        if f.mode == "export" and user and f.exportText then
            self:SetText(f.exportText)
            self:HighlightText()
        elseif f.mode == "import" then
            f.Status:SetText("")
        end
    end)

    f.Status = Kit.Text(f, "GameFontNormalSmall")
    f.Status:SetPoint("BOTTOMLEFT", 14, 16)
    f.Status:SetPoint("RIGHT", f, "RIGHT", -280, 0)

    f.Close2 = Kit.Button(f, CLOSE or "Close", 90, 22, function() f:Hide() end)
    f.Close2:SetPoint("BOTTOMRIGHT", -12, 10)

    f.Action = ConfirmButton(f, "Import", 170, "Click again to replace camp", function()
        local text = edit:GetText()
        local okDo, err = Kit.Do("ImportString", text)
        if okDo then
            f:Hide()
            ns.Say("save imported. Your old camp is kept as a backup in the options.")
            UI.Show()
        else
            f.Status:SetText("|cffff6060" .. tostring(err or "Import failed.") .. "|r")
        end
    end)
    f.Action:SetPoint("RIGHT", f.Close2, "LEFT", -6, 0)

    f.Select = Kit.Button(f, "Select all", 120, 22, function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    f.Select:SetPoint("RIGHT", f.Close2, "LEFT", -6, 0)

    f:SetScript("OnHide", function()
        edit:SetText("")
        f.exportText = nil
        edit:ClearFocus()
    end)
    f:Hide()
    return f
end

function UI.ShowSaveDialog(mode)
    dialog = dialog or BuildDialog()
    local f = dialog
    f.mode = mode
    f.Status:SetText("")
    f:Show()
    if mode == "export" then
        local text = Kit.Call("ExportString") or ""
        f.exportText = text
        f.Title:SetText("Warcamp - Export save")
        f.Help:SetText("This is your whole camp. Press Ctrl+C to copy it and keep it somewhere safe, or paste it into Import on another computer.")
        f.Action:Hide()
        f.Select:Show()
        f.Edit:SetText(text)
        f.Status:SetText(string.format("|cff9a927f%d characters|r", #text))
        f.Edit:SetFocus()
        f.Edit:HighlightText()
    else
        f.exportText = nil
        f.Title:SetText("Warcamp - Import save")
        f.Help:SetText("Paste a save string (Ctrl+V), then click Import twice. This replaces your current camp; the current one is kept as a backup in the options.")
        f.Select:Hide()
        f.Action:Show()
        f.Edit:SetText("")
        f.Edit:SetFocus()
    end
end

------------------------------------------------------------------------
-- options page (Options > AddOns > Warcamp)
------------------------------------------------------------------------

local function BuildPanel()
    local p = CreateFrame("Frame")
    p.name = "Warcamp"

    local title = Kit.Text(p, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Warcamp |cff9a927f" .. (ns.VERSION or "") .. "|r")

    local sub = Kit.Text(p, "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("An idle camp for while you wait. Open it with /warcamp or the minimap button.")

    local open = Kit.Button(p, "Open Warcamp", 140, 22, function() UI.Show() end)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)

    -- display
    local h1 = Kit.Header(p, "Display", 560)
    h1:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -16)

    local mm = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    mm:SetSize(24, 24)
    mm:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -4)
    local mmText = Kit.Text(p, "GameFontHighlight")
    mmText:SetPoint("LEFT", mm, "RIGHT", 2, 0)
    mmText:SetText("Show the minimap button")
    mm:SetScript("OnClick", function(self) UI.SetMinimapShown(self:GetChecked() and true or false) end)

    local scaleText = Kit.Text(p, "GameFontHighlight")
    scaleText:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 4, -10)
    scaleText:SetWidth(170)
    local function showScale()
        local db = DB()
        scaleText:SetText(string.format("Window scale: %d%%", U.Round(((db and db.scale) or 1) * 100)))
    end
    local smaller = Kit.Button(p, "-", 26, 20, function()
        local db = DB(); UI.SetScale(((db and db.scale) or 1) - 0.05); showScale()
    end)
    smaller:SetPoint("LEFT", scaleText, "RIGHT", 4, 0)
    local larger = Kit.Button(p, "+", 26, 20, function()
        local db = DB(); UI.SetScale(((db and db.scale) or 1) + 0.05); showScale()
    end)
    larger:SetPoint("LEFT", smaller, "RIGHT", 2, 0)
    local resetScale = Kit.Button(p, "Reset", 60, 20, function() UI.SetScale(1); showScale() end)
    resetScale:SetPoint("LEFT", larger, "RIGHT", 6, 0)

    -- progress
    local h2 = Kit.Header(p, "Your progress", 560)
    h2:SetPoint("TOPLEFT", scaleText, "BOTTOMLEFT", -4, -18)

    local info = Kit.Text(p, "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -6)
    info:SetWidth(560)
    info:SetWordWrap(true)
    info:SetJustifyV("TOP")
    info:SetText("Your camp is saved for the whole account in WTF\\Account\\<account>\\SavedVariables\\Warcamp.lua. "
        .. "Updating the addon never touches that file, and an update that changes the save keeps a backup first. "
        .. "Export gives you a text copy of your camp to keep safe or move to another computer.")

    local export = Kit.Button(p, "Export save", 140, 22, function() UI.ShowSaveDialog("export") end)
    export:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -10)
    local import = Kit.Button(p, "Import save", 140, 22, function() UI.ShowSaveDialog("import") end)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)

    local backupText = Kit.Text(p, "GameFontHighlightSmall")
    backupText:SetPoint("TOPLEFT", export, "BOTTOMLEFT", 0, -12)
    backupText:SetWidth(380)

    local restore = ConfirmButton(p, "Restore backup", 160, "Click again to restore", function()
        local ok, err = Kit.Do("RestoreBackup")
        if ok then ns.Say("backup restored. The camp it replaced is now the backup.") end
        p:Refresh()
        if not ok and err then ns.Say(err) end
    end)
    restore:SetPoint("TOPLEFT", backupText, "BOTTOMLEFT", 0, -6)

    local reset = ConfirmButton(p, "Reset camp", 160, "Click again to reset", function()
        Kit.Do("ResetAll")
        ns.Say("your camp has been reset. The old one is kept as a backup.")
        p:Refresh()
    end)
    reset:SetPoint("LEFT", restore, "RIGHT", 6, 0)

    function p:Refresh()
        local db = DB()
        mm:SetChecked(not (db and db.minimapHide))
        showScale()
        local b = Kit.Call("GetBackup")
        if b then
            backupText:SetText(string.format("Backup: %s |cff9a927f(%s)|r", date("%Y-%m-%d %H:%M", b.at or 0), b.reason or "saved"))
            restore:Enable()
        else
            backupText:SetText("|cff9a927fNo backup yet. One is made before every import, restore, reset and save update.|r")
            restore:Disable()
        end
    end
    p:SetScript("OnShow", p.Refresh)
    p.OnRefresh = p.Refresh
    return p
end

local function Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local ok, err = pcall(function()
        local panel = BuildPanel()
        category = Settings.RegisterCanvasLayoutCategory(panel, "Warcamp")
        Settings.RegisterAddOnCategory(category)
    end)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

function UI.OpenOptions()
    Register()
    if category and Settings.OpenToCategory then
        pcall(Settings.OpenToCategory, category:GetID())
    end
end

Register()
