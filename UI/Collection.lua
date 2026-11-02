-- Warcamp: the Collection tab. Two sub-views:
--   Mounts & Pets: every D.MOUNTS / D.PETS entry (collected in colour with the date, missing greyed with
--                  where it drops and the chance), a big 3D model of the selection.
--   Achievements:  achievement-frame look (parchment rows, icon frame, points shield, progress), total
--                  points, and the New Era (prestige) panel with a two-click Advance Era.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D

local ROW_H = 22
local LIST_W = 470
local ERA_W = 300

-- Blizzard_AchievementUI/Mainline (file textures, not atlases; tex coords from Blizzard_AchievementUI.lua)
local ACH = "Interface\\AchievementFrame\\"
local PARCHMENT = ACH .. "UI-Achievement-Parchment-Horizontal"
local PARCHMENT_GREY = ACH .. "UI-Achievement-Parchment-Horizontal-Desaturated"
local ICON_FRAME = ACH .. "UI-Achievement-IconFrame"            -- 0, 0.5625, 0, 0.5625
local SHIELDS = ACH .. "UI-Achievement-Shields"                 -- earned 0,.5,0,.5  unearned .5,1,0,.5
local SHIELDS_NOPOINTS = ACH .. "UI-Achievement-Shields-NoPoints"
local TINY_SHIELD = "|T" .. ACH .. "UI-Achievement-TinyShield:16:16:0:-1:32:32:0:20:0:20|t"

local GOLD_STATS = { GOLD = true, GOLD_EARNED = true }

local P = { view = "MP", filter = "ALL" }

------------------------------------------------------------------------
-- names, icons, sources
------------------------------------------------------------------------

local nameCache = {}

local function MountInfo(id)
    local c = nameCache["M" .. id]
    if c then return c[1], c[2] end
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local ok, name, _, icon = pcall(C_MountJournal.GetMountInfoByID, id)
        if ok and name then
            nameCache["M" .. id] = { name, icon or 134400 }
            return name, icon or 134400
        end
    end
    return "Mount #" .. tostring(id), 134400
end

local function PetInfo(id)
    local c = nameCache["P" .. id]
    if c then return c[1], c[2] end
    if C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name, icon = pcall(C_PetJournal.GetPetInfoBySpeciesID, id)
        if ok and name then
            nameCache["P" .. id] = { name, icon or 134400 }
            return name, icon or 134400
        end
    end
    return "Pet #" .. tostring(id), 134400
end

-- drop chances from the instance tables: mountID / speciesID -> {chance, instance name}
local drops
local function Drops()
    if drops then return drops end
    drops = { M = {}, P = {} }
    for _, list in ipairs({ D.DUNGEONS or {}, D.RAIDS or {} }) do
        for _, ins in ipairs(list) do
            if ins.mount and ins.mount.mountID then drops.M[ins.mount.mountID] = { ins.mount.chance, ins.name } end
            if ins.pet and ins.pet.speciesID then drops.P[ins.pet.speciesID] = { ins.pet.chance, ins.name } end
        end
    end
    return drops
end

local function ChanceText(c)
    if not c then return nil end
    local pct = c * 100
    if pct >= 1 and math.floor(pct) == pct then return string.format("%d%%", pct) end
    return string.format("%.1f%%", pct)
end

local function SourceText(kind, entry)
    local d = Drops()[kind][entry.id]
    local src = entry.source or (d and d[2]) or "Unknown"
    local chance = entry.chance or (d and d[1])
    if chance and not src:find("^Achievement") then return src .. " — " .. ChanceText(chance) end
    return src
end

local function RewardAchievement(kind, id)
    for _, a in ipairs(D.ACHIEVEMENTS or {}) do
        local rw = a.reward
        if rw and ((kind == "M" and rw.mountID == id) or (kind == "P" and rw.speciesID == id)) then return a end
    end
end

local function DateText(t)
    return t and date("%d %b %Y", t) or ""
end

------------------------------------------------------------------------
-- mounts & pets
------------------------------------------------------------------------

local function MPData()
    local col = Kit.Call("GetCollection") or {}
    local mounts, pets = col.mounts or {}, col.pets or {}
    local out, total, have = {}, 0, 0
    local sections = {
        { kind = "M", title = "Mounts", list = D.MOUNTS or {}, idKey = "mountID", owned = mounts },
        { kind = "P", title = "Pets", list = D.PETS or {}, idKey = "speciesID", owned = pets },
    }
    local counts = {}
    for _, s in ipairs(sections) do
        local head = { kind = "HEAD", id = "H:" .. s.kind, title = s.title, have = 0, total = 0 }
        out[#out + 1] = head
        local seen = {}
        for _, e in ipairs(s.list) do
            local id = e[s.idKey]
            if id and not seen[id] then
                seen[id] = true
                local got = s.owned[id]
                if got and type(got) ~= "table" then got = {} end   -- tolerate an odd save value
                head.total = head.total + 1
                if got then head.have = head.have + 1 end
                if P.filter == "ALL" or (P.filter == "HAVE" and got) or (P.filter == "MISSING" and not got) then
                    local name, icon
                    if s.kind == "M" then name, icon = MountInfo(id) else name, icon = PetInfo(id) end
                    local d = { kind = s.kind, id = id, key = s.kind .. ":" .. id, name = name, icon = icon,
                                source = e.source, chance = e.chance, got = got }
                    d.sourceText = SourceText(s.kind, d)
                    out[#out + 1] = d
                end
            end
        end
        total, have = total + head.total, have + head.have
        counts[s.kind] = head
    end
    return out, have, total, counts
end

local function BuildMPRow(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(18, 18)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Border = row:CreateTexture(nil, "OVERLAY")
    row.Border:SetPoint("TOPLEFT", row.Icon, -1, 1)
    row.Border:SetPoint("BOTTOMRIGHT", row.Icon, 1, -1)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    row.Name:SetWidth(200)
    row.Right = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Right:SetPoint("RIGHT", -4, 0)
    row.Right:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
    row.Head = Kit.Text(row, "GameFontNormal")
    row.Head:SetPoint("LEFT", 6, 0)
    row.HeadLine = row:CreateTexture(nil, "ARTWORK")
    row.HeadLine:SetPoint("BOTTOMLEFT", 0, 0)
    row.HeadLine:SetPoint("BOTTOMRIGHT", 0, 0)
    -- a plain line: the LFG divider atlas filled the whole row in a blue glow and hid the title
    row.HeadLine:SetHeight(1)
    row.HeadLine:SetColorTexture(1, 0.82, 0, 0.35)
end

local function UpdateMPRow(row, d)
    local head = d.kind == "HEAD"
    row.Icon:SetShown(not head); row.Border:SetShown(not head); row.Name:SetShown(not head); row.Right:SetShown(not head)
    row.Head:SetShown(head); row.HeadLine:SetShown(head)
    if head then
        row.Stripe:Hide()
        row.Head:SetText(string.format("%s  |cffffffff%d / %d|r", d.title, d.have, d.total))
        return
    end
    row.Icon:SetTexture(d.icon)
    row.Icon:SetDesaturated(not d.got)
    if d.got then
        Kit.QualityBorder(row.Border, d.kind == "M" and 4 or 3)
        row.Name:SetText("|c" .. Kit.QualityHex(d.kind == "M" and 4 or 3) .. d.name .. "|r" ..
            ((d.kind == "P" and (d.got.count or 1) > 1) and string.format(" |cff9d9d9dx%d|r", d.got.count) or ""))
        row.Right:SetText("|cff40c040" .. DateText(d.got.at) .. "|r")
        row.Icon:SetAlpha(1)
    else
        Kit.QualityBorder(row.Border, 0)
        row.Name:SetText("|cff808080" .. d.name .. "|r")
        row.Right:SetText("|cff808080" .. (d.sourceText or "") .. "|r")
        row.Icon:SetAlpha(0.75)
    end
end

local function MPTooltip(tt, row, d)
    if d.kind == "HEAD" then return end
    tt:SetText(d.name, 1, 0.82, 0)
    tt:AddLine(d.kind == "M" and "Mount" or "Companion pet", 0.8, 0.8, 0.8)
    if d.got then
        tt:AddLine("Collected " .. DateText(d.got.at), 0.3, 1, 0.3)
        if d.got.source then tt:AddLine("From " .. tostring(d.got.source), 1, 1, 1) end
        if d.kind == "P" and (d.got.count or 1) > 1 then tt:AddLine(string.format("Found %d times", d.got.count), 0.7, 0.7, 0.7) end
    else
        tt:AddLine("Not collected", 1, 0.3, 0.3)
        tt:AddLine(d.sourceText or "", 1, 1, 1, true)
    end
end

local function UpdateMPDetail()
    local V = P.mp
    local d
    for _, x in ipairs(V.list:GetData() or {}) do if x.key == P.mpSel then d = x end end
    if not d then
        V.Model:Clear()
        V.Name:SetText("")
        V.Source:SetText("Select a mount or pet.")
        V.Status:SetText("")
        return
    end
    if d.kind == "M" then V.Model:SetMount(d.id) else V.Model:SetPet(d.id) end
    V.Name:SetText(d.name)
    local q = d.kind == "M" and 4 or 3
    if d.got then
        local r, g, b = ns.QUALITY_COLOR(q)
        V.Name:SetTextColor(r, g, b)
        V.Status:SetText(string.format("|cff40ff40Collected %s|r", DateText(d.got.at)) ..
            ((d.kind == "P" and (d.got.count or 1) > 1) and string.format("  |cff9d9d9d(found %d times)|r", d.got.count) or ""))
    else
        V.Name:SetTextColor(0.6, 0.6, 0.6)
        V.Status:SetText("|cffff5050Not collected yet|r")
    end
    local src = d.sourceText or ""
    local a = RewardAchievement(d.kind, d.id)
    if a then
        for _, e in ipairs(Kit.Call("GetAchievements") or {}) do
            if e.def == a and not e.earnedAt then
                src = string.format("%s  |cffffffff(%s / %s)|r", src, tostring(e.progress or 0), tostring(e.goal or 0))
            end
        end
    end
    V.Source:SetText(src)
end

local function BuildMP(parent)
    local V = CreateFrame("Frame", nil, parent)
    V:SetAllPoints()
    P.mp = V
    local left = Kit.Inset(V)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LIST_W)
    V.list = Kit.List(left, {
        rowHeight = ROW_H, build = BuildMPRow, update = UpdateMPRow, tooltip = MPTooltip,
        key = function(d) return d.key or d.id end,
        onClick = function(row, d, button, L)
            if d.kind == "HEAD" then return end
            P.mpSel = d.key
            L:SetSelected(d.key)
            UpdateMPDetail()
        end,
    })
    V.list:SetPoint("TOPLEFT", 4, -4)
    V.list:SetPoint("BOTTOMRIGHT", -4, 4)
    V.empty = Kit.Text(left, "GameFontDisable", "CENTER")
    V.empty:SetPoint("CENTER")
    V.empty:SetText("Nothing here.")
    V.empty:Hide()

    local right = Kit.Inset(V)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    V.Model = Kit.ModelView(right, 420, 380, { hint = true })
    V.Model:SetPoint("TOPLEFT", 4, -4)
    V.Model:SetPoint("BOTTOMRIGHT", -4, 64)
    V.Name = Kit.Text(right, "GameFontNormalLarge", "CENTER")
    V.Name:SetPoint("BOTTOMLEFT", 6, 44)
    V.Name:SetPoint("BOTTOMRIGHT", -6, 44)
    V.Source = Kit.Text(right, "GameFontHighlightSmall", "CENTER")
    V.Source:SetPoint("BOTTOMLEFT", 6, 26)
    V.Source:SetPoint("BOTTOMRIGHT", -6, 26)
    V.Status = Kit.Text(right, "GameFontHighlightSmall", "CENTER")
    V.Status:SetPoint("BOTTOMLEFT", 6, 10)
    V.Status:SetPoint("BOTTOMRIGHT", -6, 10)
end

local function RefreshMP()
    local V = P.mp
    local data, have, total, counts = MPData()
    V.list:SetData(data)
    V.empty:SetShown(#data <= 2)
    local found = false
    for _, d in ipairs(data) do if d.key and d.key == P.mpSel then found = true end end
    if not found then
        P.mpSel = nil
        for _, d in ipairs(data) do if d.key then P.mpSel = d.key; break end end
    end
    V.list:SetSelected(P.mpSel)
    UpdateMPDetail()
    P.count:SetText(string.format("Collected |cffffffff%d/%d|r   |cff9d9d9dmounts %d/%d, pets %d/%d|r", have, total,
        counts.M.have, counts.M.total, counts.P.have, counts.P.total))
end

------------------------------------------------------------------------
-- achievements
------------------------------------------------------------------------

local function ProgressText(def, cur, goal)
    if GOLD_STATS[def.stat] then
        return string.format("%s / %s", tostring(math.floor((cur or 0) / 10000)), tostring(math.floor((goal or 0) / 10000)) .. "g")
    end
    return string.format("%d / %d", cur or 0, goal or 0)
end

local function RewardText(def)
    local rw = def.reward
    if not rw then return nil end
    if rw.mountID then return "Reward: " .. (MountInfo(rw.mountID)) .. " (mount)" end
    if rw.speciesID then return "Reward: " .. (PetInfo(rw.speciesID)) .. " (pet)" end
    if rw.title then return "Reward: title \"" .. tostring(rw.title) .. "\"" end
end

local function BuildAchRow(row)
    row.Bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.Bg:SetAllPoints()
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(18, 18)
    row.Icon:SetPoint("LEFT", 5, 0)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Frame = row:CreateTexture(nil, "OVERLAY")
    row.Frame:SetSize(25, 25)
    row.Frame:SetPoint("CENTER", row.Icon, "CENTER", -0.5, 1)
    Kit.Atlas(row.Frame, nil, ICON_FRAME)
    row.Frame:SetTexCoord(0, 0.5625, 0, 0.5625)
    row.Name = Kit.Text(row, "GameFontNormalSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 7, 0)
    row.Name:SetWidth(150)
    row.Desc = Kit.Text(row, "GameFontHighlightSmall")
    row.Desc:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
    row.Desc:SetWidth(186)
    row.Bar = Kit.ProgressBar(row, 92, 12)
    row.Bar:SetPoint("LEFT", row.Desc, "RIGHT", 6, 0)
    row.Shield = row:CreateTexture(nil, "ARTWORK")
    row.Shield:SetSize(24, 22)
    row.Shield:SetPoint("LEFT", row.Bar, "RIGHT", 6, 0)
    row.Points = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Points:SetPoint("CENTER", row.Shield, "CENTER", 0, 1)
    row.Date = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Date:SetPoint("RIGHT", -4, 0)
    row.Date:SetPoint("LEFT", row.Shield, "RIGHT", 2, 0)
end

local function UpdateAchRow(row, e)
    local def, earned = e.def, e.earnedAt ~= nil
    row.Stripe:Hide()
    row.Bg:SetTexture(earned and PARCHMENT or PARCHMENT_GREY)
    row.Bg:SetTexCoord(0, 1, 0, 0.18)
    if earned then row.Bg:SetVertexColor(0.42, 0.33, 0.2, 0.9) else row.Bg:SetVertexColor(0.22, 0.22, 0.22, 0.85) end
    row.Icon:SetTexture(def.icon or 134400)
    row.Icon:SetDesaturated(not earned)
    if earned then row.Frame:SetVertexColor(1, 1, 1, 1) else row.Frame:SetVertexColor(0.6, 0.6, 0.6, 1) end
    row.Name:SetText(def.name or def.key or "?")
    if earned then row.Name:SetTextColor(1, 0.82, 0) else row.Name:SetTextColor(0.65, 0.65, 0.65) end
    row.Desc:SetText(def.desc or "")
    if earned then row.Desc:SetTextColor(1, 1, 1) else row.Desc:SetTextColor(0.6, 0.6, 0.6) end
    local goal = math.max(1, e.goal or 1)
    if earned then
        row.Bar:SetProgress(1, "Done", 0.15, 0.55, 0.15)
    else
        row.Bar:SetProgress((e.progress or 0) / goal, ProgressText(def, e.progress, e.goal), 0.2, 0.45, 0.85)
    end
    local pts = def.points or 0
    row.Shield:SetTexture(pts > 0 and SHIELDS or SHIELDS_NOPOINTS)
    if earned then row.Shield:SetTexCoord(0, 0.5, 0, 0.5) else row.Shield:SetTexCoord(0.5, 1, 0, 0.5) end
    row.Points:SetText(pts > 0 and tostring(pts) or "")
    if earned then row.Points:SetTextColor(1, 1, 1) else row.Points:SetTextColor(0.6, 0.6, 0.6) end
    row.Date:SetText(earned and DateText(e.earnedAt) or "")
end

local function AchTooltip(tt, row, e)
    local def = e.def
    tt:SetText(def.name or def.key or "?", 1, 0.82, 0)
    if def.desc then tt:AddLine(def.desc, 1, 1, 1, true) end
    tt:AddDoubleLine("Progress", ProgressText(def, e.progress, e.goal), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddDoubleLine("Points", tostring(def.points or 0), 0.8, 0.8, 0.8, 1, 1, 1)
    local rw = RewardText(def)
    if rw then tt:AddLine(rw, 0.3, 0.8, 1, true) end
    if e.earnedAt then tt:AddLine("Earned " .. date("%d %b %Y %H:%M", e.earnedAt), 0.3, 1, 0.3) end
end

local function Pct(x) return string.format("+%d%%", math.floor((x or 0) * 100 + 0.5)) end

local function BonusText(b)
    if type(b) ~= "table" then return "" end
    return string.format("%s experience, %s gold, %s mission speed, +%d recruit slot%s",
        Pct(b.xp), Pct(b.gold), Pct(b.speed), b.heroes or 0, (b.heroes or 0) == 1 and "" or "s")
end

local KEPT = "Kept: mounts, pets, achievements, Legacy, statistics and the camp log."
local RESET = "Reset: recruits, gold, buildings, materials, gear, active tasks and tier progress. You start again with three new recruits."

local function UpdateEraButton(btn, now)
    local info = P.era
    if not info then return end
    now = now or time()
    if btn.confirmUntil and now <= btn.confirmUntil and info.canAdvance then
        btn:SetText("Click again")
        P.eraWarn:Show()
    else
        btn.confirmUntil = nil
        btn:SetText("Advance Era")
        P.eraWarn:Hide()
    end
end

local function EraClick(btn)
    local info = P.era
    if not (info and info.canAdvance) then return end
    local now = time()
    if btn.confirmUntil and now <= btn.confirmUntil then
        btn.confirmUntil = nil
        if Kit.Do("AdvanceEra") then UI.Status("A new era begins.", 1, 0.82, 0) end
    else
        btn.confirmUntil = now + 5
    end
    UpdateEraButton(btn, now)
end

local function WrapText(parent, template, width)
    local fs = Kit.Text(parent, template)
    fs:SetWordWrap(true)
    fs:SetWidth(width)
    fs:SetJustifyV("TOP")
    return fs
end

local function BuildAch(parent)
    local V = CreateFrame("Frame", nil, parent)
    V:SetAllPoints()
    P.ach = V
    local left = Kit.Inset(V)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", -(ERA_W + 8), 0)
    local bg = left:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    Kit.Atlas(bg, "UI-Background-Rock-Brown", { 0.05, 0.04, 0.03, 0.6 })
    bg:SetAlpha(0.5)
    V.list = Kit.List(left, {
        rowHeight = ROW_H, build = BuildAchRow, update = UpdateAchRow, tooltip = AchTooltip,
        selectable = true, key = function(e) return e.def.key end,
        onClick = function(row, e) P.achSel = e.def.key end,
    })
    V.list:SetPoint("TOPLEFT", 4, -4)
    V.list:SetPoint("BOTTOMRIGHT", -4, 4)
    V.empty = Kit.Text(left, "GameFontDisable", "CENTER")
    V.empty:SetPoint("CENTER")
    V.empty:SetText("No achievements yet.")
    V.empty:Hide()

    -- era panel
    local E = Kit.Inset(V)
    E:SetPoint("TOPRIGHT", 0, 0)
    E:SetPoint("BOTTOMRIGHT", 0, 0)
    E:SetWidth(ERA_W)
    local w = ERA_W - 20
    P.eraHeader = Kit.Header(E, "New Era", ERA_W - 12)
    P.eraHeader:SetPoint("TOPLEFT", 6, -6)
    P.eraTitle = Kit.Text(E, "GameFontNormalLarge")
    P.eraTitle:SetPoint("TOPLEFT", 10, -30)
    P.eraNow = WrapText(E, "GameFontHighlightSmall", w)
    P.eraNow:SetPoint("TOPLEFT", 10, -54)
    local nl = Kit.Text(E, "GameFontNormalSmall")
    nl:SetPoint("TOPLEFT", 10, -100)
    nl:SetText("Advancing now")
    P.eraNext = WrapText(E, "GameFontHighlightSmall", w)
    P.eraNext:SetPoint("TOPLEFT", 10, -116)
    P.eraKept = WrapText(E, "GameFontHighlightSmall", w)
    P.eraKept:SetPoint("TOPLEFT", 10, -170)
    P.eraKept:SetText("|cff40ff40" .. KEPT .. "|r")
    P.eraReset = WrapText(E, "GameFontHighlightSmall", w)
    P.eraReset:SetPoint("TOPLEFT", 10, -206)
    P.eraReset:SetText("|cffff8040" .. RESET .. "|r")
    P.eraReason = WrapText(E, "GameFontHighlightSmall", w)
    P.eraReason:SetPoint("BOTTOMLEFT", 10, 64)
    P.eraWarn = WrapText(E, "GameFontNormalSmall", w)
    P.eraWarn:SetPoint("BOTTOMLEFT", 10, 40)
    P.eraWarn:SetText("|cffff3030Click again to end this era. This cannot be undone.|r")
    P.eraWarn:Hide()
    P.eraBtn = Kit.Button(E, "Advance Era", 140, 22, EraClick)
    P.eraBtn:SetPoint("BOTTOM", 0, 12)
    Kit.Live(P.eraBtn, UpdateEraButton)
end

local function SortAch(list)
    table.sort(list, function(a, b)
        local ea, eb = a.earnedAt ~= nil, b.earnedAt ~= nil
        if ea ~= eb then return not ea end
        if not ea then
            local fa, fb = (a.progress or 0) / math.max(1, a.goal or 1), (b.progress or 0) / math.max(1, b.goal or 1)
            if fa ~= fb then return fa > fb end
        elseif a.earnedAt ~= b.earnedAt then
            return a.earnedAt > b.earnedAt
        end
        return (a.def.name or "") < (b.def.name or "")
    end)
end

local function RefreshAch()
    local V = P.ach
    local list = Kit.Call("GetAchievements") or {}
    SortAch(list)
    V.list:SetData(list)
    V.list:SetSelected(P.achSel)
    V.empty:SetShown(#list == 0)
    local earned, total = 0, 0
    for _, e in ipairs(list) do
        total = total + (e.def.points or 0)
        if e.earnedAt then earned = earned + 1 end
    end
    local pts = Kit.Call("AchievementPoints") or 0
    P.count:SetText(string.format("%s |cffffffff%d|r points  |cff9d9d9d(%d of %d earned, %d possible)|r", TINY_SHIELD, pts, earned, #list, total))

    local info = Kit.Call("EraInfo")
    P.era = info
    if info then
        P.eraTitle:SetText(string.format("Era %d", info.era or 1))
        P.eraHeader.right:SetText(string.format("Legacy |cffffffff%d|r", info.legacy or 0))
        P.eraNow:SetText("Current bonus: " .. BonusText(info.bonus))
        if info.gain then
            P.eraNext:SetText(string.format("|cffffd100+%d Legacy|r, era %d: %s", info.gain, (info.era or 1) + 1, BonusText(info.nextBonus)))
        else
            P.eraNext:SetText("")
        end
        P.eraReason:SetText(info.canAdvance and "|cff40ff40The final raid has fallen. A new era can begin.|r" or ("|cffff5050" .. (info.reason or "") .. "|r"))
        P.eraBtn:SetEnabledTip(info.canAdvance, info.reason)
        P.eraBtn:SetTip(KEPT .. "\n" .. RESET)
    else
        P.eraTitle:SetText("")
        P.eraNow:SetText("")
        P.eraNext:SetText("")
        P.eraReason:SetText("")
        P.eraBtn:SetEnabledTip(false, "Not available")
    end
    UpdateEraButton(P.eraBtn, time())
end

------------------------------------------------------------------------
-- tab
------------------------------------------------------------------------

local FILTERS = { ALL = "Show: all", HAVE = "Show: collected", MISSING = "Show: missing" }
local NEXT_FILTER = { ALL = "HAVE", HAVE = "MISSING", MISSING = "ALL" }

local function ApplyView()
    P.mp:SetShown(P.view == "MP")
    P.ach:SetShown(P.view == "ACH")
    P.filterBtn:SetShown(P.view == "MP")
    for _, b in ipairs(P.subTabs) do
        if b.view == P.view then b:LockHighlight() else b:UnlockHighlight() end
    end
end

local function Build(panel)
    local top = CreateFrame("Frame", nil, panel)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    top:SetHeight(22)
    P.subTabs = {}
    local x = 0
    for _, v in ipairs({ { "MP", "Mounts & Pets" }, { "ACH", "Achievements" } }) do
        local b = Kit.Button(top, v[2], 120, 20, function()
            P.view = v[1]
            ApplyView()
            UI.Refresh()
        end)
        b:SetPoint("LEFT", x, 0)
        b.view = v[1]
        x = x + 124
        P.subTabs[#P.subTabs + 1] = b
    end
    P.filterBtn = Kit.Button(top, FILTERS.ALL, 120, 20, function(self)
        P.filter = NEXT_FILTER[P.filter] or "ALL"
        self:SetText(FILTERS[P.filter])
        UI.Refresh()
    end, "Cycle: all / collected / missing")
    P.filterBtn:SetPoint("LEFT", x + 12, 0)
    P.count = Kit.Text(top, "GameFontNormal", "RIGHT")
    P.count:SetPoint("RIGHT", -6, 0)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, -26)
    body:SetPoint("BOTTOMRIGHT", 0, 0)
    BuildMP(body)
    BuildAch(body)
    ApplyView()
end

local function Refresh(panel)
    ApplyView()
    if P.view == "MP" then RefreshMP() else RefreshAch() end
end

UI.RegisterTab({ key = "COLLECTION", title = "Collection", order = 7, build = Build, refresh = Refresh })
