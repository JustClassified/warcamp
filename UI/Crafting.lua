-- Warcamp: the Crafting tab, laid out like the Blizzard profession window.
-- Left: recipes grouped by building (Forge / Alchemy Lab / Kitchen) then tier, collapsible.
-- Right: the selected recipe (output, reagents have/need, cost, time, quantity, Craft), the building's
-- craft queue, and a small Materials grid of everything in storage.

local ADDON, ns = ...
local UI = ns.UI
local Kit = UI.Kit
local U = ns.Util
local D = ns.D

local LIST_W = 300
local ROW_H = 20
local MAT_SIZE, MAT_GAP, MAT_ROWS = 30, 3, 3
local MAX_REAGENTS = 6
local CRAFT_SPEED_CAP = 0.5        -- mirrors Engine\Economy.lua (display only)

-- building order and fallback icons (verified file paths in the default UI icon set)
local BUILDING_ORDER = { "FORGE", "ALCHEMY_LAB", "KITCHEN" }
local BUILDING_ICON = {
    FORGE = "Interface\\Icons\\Trade_BlackSmithing",
    ALCHEMY_LAB = "Interface\\Icons\\Trade_Alchemy",
    KITCHEN = "Interface\\Icons\\INV_Misc_Food_15",
}
local SLOT_NAME = {
    HEAD = "Head", SHOULDER = "Shoulder", CHEST = "Chest", HANDS = "Hands", LEGS = "Legs",
    FEET = "Feet", WEAPON = "Weapon", TRINKET = "Trinket", ANY = "random slot",
}

local P = { collapsed = {}, qty = 1 }

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

local function BuildingName(key)
    local b = D.BUILDINGS and D.BUILDINGS[key]
    return b and b.name or (key and (key:sub(1, 1) .. key:sub(2):lower():gsub("_", " ")) or "?")
end

local function TierName(t)
    local d = D.TIERS and D.TIERS[t]
    return d and d.name or ("Tier " .. tostring(t or "?"))
end

-- output description: icon, name, quality, itemID, isGear, count
local function OutputInfo(recipe)
    local out = recipe.output or {}
    if out.item then
        local it = Kit.Item(out.item) or {}
        return { icon = recipe.icon or ns.ItemIcon(it.itemID, it.icon), itemID = it.itemID, name = it.name or out.item,
                 quality = it.quality or 1, n = out.n or 1, itemKey = out.item }
    end
    local tier = out.tier or recipe.tier or 1
    local slot = out.gear or "ANY"
    local bases = D.GEAR_BASES and D.GEAR_BASES[tier]
    local base = bases and (bases[slot ~= "ANY" and slot or "WEAPON"] or bases.CHEST)
    base = base and base[1]
    local icon = recipe.icon or (base and ns.ItemIcon(base.itemID)) or BUILDING_ICON[recipe.building] or 134400
    return { icon = icon, itemID = base and base.itemID, name = recipe.name, quality = out.quality or 3, n = 1,
             gear = slot, tier = tier }
end

local function CraftSpeed()
    local b = Kit.Call("Bonus", "CRAFT_SPEED") or 0
    return U.Clamp(b, 0, CRAFT_SPEED_CAP)
end

local function CraftSeconds(recipe, n)
    return math.max(10, U.Round((recipe.time or 60) * (n or 1) * (1 - CraftSpeed())))
end

local function OutputLines(recipe, o)
    local l = {}
    if o.gear then
        local q = D.QUALITY and D.QUALITY[o.quality] or ""
        l[#l + 1] = { string.format("Creates a %s %s item", q, SLOT_NAME[o.gear] or o.gear:lower()), 1, 1, 1 }
        local il = Kit.Call("CraftIlvl", o.tier, o.quality)
        if il then l[#l + 1] = { string.format("Item level about %d", math.floor(il)), 1, 0.82, 0 } end
        l[#l + 1] = { TierName(o.tier), 0.7, 0.7, 0.7 }
    else
        if o.n > 1 then l[#l + 1] = { string.format("Creates %d", o.n), 1, 1, 1 } end
        local it = Kit.Item(o.itemKey)
        local buffKey = it and (it.use or it.buff)   -- D.ITEMS potions/food carry `use` (see Data\Items.lua)
        if buffKey and D.BUFFS and D.BUFFS[buffKey] then
            local b = D.BUFFS[buffKey]
            l[#l + 1] = { "Use: " .. (b.desc or b.name or ""), 0.3, 1, 0.3 }
        end
        local have = Kit.Call("Count", o.itemKey)
        if have then l[#l + 1] = { "In storage", tostring(have), 0.6, 0.6, 0.6, 1, 1, 1 } end
    end
    return l
end

------------------------------------------------------------------------
-- recipe list
------------------------------------------------------------------------

local function BuildRow(row)
    -- building header art (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeList.xml)
    row.HL = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.HL:SetPoint("TOPLEFT", 0, 0)
    row.HL:SetSize(12, ROW_H)
    row.HM = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.HR = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.HR:SetPoint("TOPRIGHT", 0, 0)
    row.HR:SetSize(12, ROW_H)
    row.HM:SetPoint("TOPLEFT", row.HL, "TOPRIGHT")
    row.HM:SetPoint("BOTTOMRIGHT", row.HR, "BOTTOMLEFT")
    local okL = Kit.Atlas(row.HL, "Professions-recipe-header-left")
    local okM = Kit.Atlas(row.HM, "Professions-recipe-header-middle")
    local okR = Kit.Atlas(row.HR, "Professions-recipe-header-right")
    if not (okL and okM and okR) then
        Kit.Atlas(row.HL, nil, { 0.25, 0.18, 0.08, 0.8 })
        Kit.Atlas(row.HM, nil, { 0.25, 0.18, 0.08, 0.8 })
        Kit.Atlas(row.HR, nil, { 0.25, 0.18, 0.08, 0.8 })
    end
    -- profession list selection look
    Kit.Atlas(row.Select, "Professions_Recipe_Active", { 1, 0.82, 0, 0.18 })

    row.Toggle = Kit.Text(row, "GameFontNormal")
    row.Toggle:SetPoint("LEFT", 4, 0)
    row.Toggle:SetWidth(12)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Name = Kit.Text(row, "GameFontHighlightSmall")
    row.Right = Kit.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.Right:SetPoint("RIGHT", -4, 0)
end

local function UpdateRow(row, d)
    local isHeader, isTier = d.kind == "BUILDING", d.kind == "TIER"
    row.HL:SetShown(isHeader); row.HM:SetShown(isHeader); row.HR:SetShown(isHeader)
    if isHeader then row.Stripe:Hide() end
    row.Toggle:SetShown(isHeader)
    row.Icon:ClearAllPoints()
    row.Name:ClearAllPoints()
    if isHeader then
        row.Toggle:SetText(P.collapsed[d.building] and "+" or "-")
        row.Icon:SetPoint("LEFT", 18, 0)
        row.Icon:SetTexture(d.icon)
        row.Icon:SetDesaturated(d.level == 0)
        row.Icon:Show()
        row.Name:SetFontObject("GameFontNormal")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 5, 0)
        row.Name:SetText(d.name)
        row.Name:SetTextColor(1, 0.82, 0)
        row.Right:SetWidth(120)
        row.Right:SetText(d.level > 0 and string.format("|cffffffffLevel %d|r  |cff9d9d9d%d/%d|r", d.level, d.ready, d.total)
            or "|cff9d9d9dNot built|r")
    elseif isTier then
        row.Icon:Hide()
        row.Name:SetFontObject("GameFontNormalSmall")
        row.Name:SetPoint("LEFT", 14, 0)
        row.Name:SetText(d.name)
        row.Name:SetTextColor(0.8, 0.7, 0.45)
        row.Right:SetWidth(80)
        row.Right:SetText("")
    else
        local info, o = d.info, d.out
        row.Icon:SetPoint("LEFT", 22, 0)
        row.Icon:SetTexture(o.icon)
        row.Icon:Show()
        row.Name:SetFontObject("GameFontHighlightSmall")
        row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 5, 0)
        row.Name:SetText(info.recipe.name or info.key)
        local locked = (info.maxCraftable or 0) < 1 and info.reason
        if info.canCraft or (info.maxCraftable or 0) > 0 then
            local r, g, b = ns.QUALITY_COLOR(o.quality)
            row.Name:SetTextColor(r, g, b)
            row.Icon:SetDesaturated(false)
            row.Right:SetWidth(90)
            row.Right:SetText(info.canCraft and string.format("|cffffffff[%d]|r", info.maxCraftable or 0)
                or string.format("|cff9d9d9d%s|r", info.reason or ""))
        else
            row.Name:SetTextColor(0.55, 0.55, 0.55)
            row.Icon:SetDesaturated(true)
            row.Right:SetWidth(130)
            row.Right:SetText(locked and ("|cff808080" .. info.reason .. "|r") or "")
        end
    end
    row.Name:SetPoint("RIGHT", row.Right, "LEFT", -4, 0)
end

local function RowTooltip(tt, row, d)
    if d.kind == "BUILDING" then
        tt:SetText(d.name, 1, 0.82, 0)
        tt:AddLine(d.level > 0 and ("Level " .. d.level) or "Not built yet", 0.8, 0.8, 0.8)
        tt:AddLine(string.format("%d of %d recipes can be crafted now", d.ready, d.total), 1, 1, 1)
        tt:AddLine(P.collapsed[d.building] and "Click to expand" or "Click to collapse", 0.5, 0.5, 0.5)
        return
    end
    if d.kind ~= "RECIPE" then return end
    local info, o = d.info, d.out
    local r, g, b = ns.QUALITY_COLOR(o.quality)
    tt:SetText(info.recipe.name or info.key, r, g, b)
    Kit.AddLines(tt, OutputLines(info.recipe, o))
    tt:AddLine(" ")
    for _, k in ipairs(d.inputs) do
        local need = info.recipe.inputs[k]
        local it = Kit.Item(k)
        local have = Kit.Call("Count", k) or 0
        local ok = have >= need
        tt:AddDoubleLine(Kit.IconMarkup(it and ns.ItemIcon(it.itemID, it.icon), 14) .. " " .. (it and it.name or k),
            string.format("%d / %d", have, need), 1, 1, 1, ok and 0.3 or 1, ok and 1 or 0.3, 0.3)
    end
    if (info.recipe.gold or 0) > 0 then tt:AddDoubleLine("Cost", Kit.Coin(info.recipe.gold), 1, 1, 1, 1, 1, 1) end
    tt:AddDoubleLine("Time", U.Duration(CraftSeconds(info.recipe, 1)), 1, 1, 1, 1, 1, 1)
    if info.reason then tt:AddLine(info.reason, 1, 0.3, 0.3, true) end
end

local function SortedInputs(recipe)
    local keys = {}
    for k in pairs(recipe.inputs or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ia, ib = Kit.Item(a), Kit.Item(b)
        local qa, qb = ia and ia.quality or 0, ib and ib.quality or 0
        if qa ~= qb then return qa < qb end
        return a < b
    end)
    return keys
end

-- flat list: building header, tier sub-header, recipes
local function BuildData()
    local recipes = Kit.Call("GetRecipes") or {}
    local byB, order, seen = {}, {}, {}
    for _, k in ipairs(BUILDING_ORDER) do order[#order + 1] = k; seen[k] = true end
    for _, info in ipairs(recipes) do
        local b = info.recipe and info.recipe.building or "?"
        if not seen[b] then order[#order + 1] = b; seen[b] = true end
        byB[b] = byB[b] or {}
        table.insert(byB[b], info)
    end
    local data, byKey = {}, {}
    for _, b in ipairs(order) do
        local list = byB[b]
        if list then
            local lvl = Kit.Call("BuildingLevel", b) or 0
            local ready = 0
            for _, info in ipairs(list) do if info.canCraft then ready = ready + 1 end end
            local bdef = D.BUILDINGS and D.BUILDINGS[b]
            data[#data + 1] = { kind = "BUILDING", id = "B:" .. b, building = b, name = BuildingName(b), level = lvl,
                                icon = BUILDING_ICON[b] or (bdef and bdef.icon) or 134400, ready = ready, total = #list }
            if not P.collapsed[b] then
                table.sort(list, function(x, y)
                    local tx, ty = x.recipe.tier or 0, y.recipe.tier or 0
                    if tx ~= ty then return tx < ty end
                    local lx, ly = x.recipe.buildingLevel or 0, y.recipe.buildingLevel or 0
                    if lx ~= ly then return lx < ly end
                    return (x.recipe.name or x.key) < (y.recipe.name or y.key)
                end)
                local lastTier
                for _, info in ipairs(list) do
                    local t = info.recipe.tier or 1
                    if t ~= lastTier then
                        data[#data + 1] = { kind = "TIER", id = "T:" .. b .. ":" .. t, name = TierName(t) }
                        lastTier = t
                    end
                    local d = { kind = "RECIPE", id = info.key, info = info, out = OutputInfo(info.recipe), inputs = SortedInputs(info.recipe) }
                    data[#data + 1] = d
                end
            end
            for _, info in ipairs(list) do   -- collapsed recipes stay selectable on the right
                byKey[info.key] = { kind = "RECIPE", id = info.key, info = info, out = OutputInfo(info.recipe), inputs = SortedInputs(info.recipe) }
            end
        end
    end
    -- byKey must point at the same tables the list holds
    for _, d in ipairs(data) do if d.kind == "RECIPE" then byKey[d.id] = d end end
    return data, byKey, recipes
end

------------------------------------------------------------------------
-- detail (right side)
------------------------------------------------------------------------

local UpdateDetail

local function Selected()
    return P.selKey and P.byKey and P.byKey[P.selKey]
end

local function ClampQty(n, d)
    n = math.floor(tonumber(n) or 1)
    local maxN = d and d.info.maxCraftable or 1
    return U.Clamp(n, 1, math.max(1, maxN))
end

local function SetQty(n)
    local d = Selected()
    P.qty = ClampQty(n, d)
    if P.qtyBox and tostring(P.qty) ~= P.qtyBox:GetText() then P.qtyBox:SetText(tostring(P.qty)) end
    UpdateDetail()
end

local function QueueTask(building)
    for _, t in ipairs(Kit.Call("GetTasks") or {}) do
        if t.kind == "CRAFT" and t.building == building then return t end
    end
end

local function UpdateQueueButton(btn, now)
    local t = P.queueTask
    if not t then return end
    now = now or time()
    if now >= (t.endAt or 0) then
        btn:SetText("Collect")
        btn:SetEnabledTip(true)
        btn:SetTip("Collect the finished items")
        btn.confirmUntil = nil
    elseif btn.confirmUntil and now <= btn.confirmUntil then
        btn:SetText("Sure?")
        btn:SetTip("Click again to stop: materials and gold are refunded")
    else
        btn.confirmUntil = nil
        btn:SetText("Cancel")
        btn:SetEnabledTip(true)
        btn:SetTip("Stop crafting (materials and gold are refunded)")
    end
end

local function QueueClick(btn)
    local t = P.queueTask
    if not t then return end
    local now = time()
    if now >= (t.endAt or 0) then
        local rep = Kit.Do("Collect", t.id)
        if type(rep) == "table" then UI.ShowReport(rep) end
    elseif btn.confirmUntil and now <= btn.confirmUntil then
        btn.confirmUntil = nil
        Kit.Do("Cancel", t.id)
    else
        btn.confirmUntil = now + 3
        UpdateQueueButton(btn, now)
    end
end

local function BuildReagent(parent, i)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(270, 34)
    f.Btn = Kit.ItemButton(f, 32)
    f.Btn:SetPoint("LEFT", 0, 0)
    f.Name = Kit.Text(f, "GameFontHighlightSmall")
    f.Name:SetPoint("TOPLEFT", f.Btn, "TOPRIGHT", 6, -3)
    f.Name:SetPoint("RIGHT", -2, 0)
    f.Have = Kit.Text(f, "GameFontHighlightSmall")
    f.Have:SetPoint("BOTTOMLEFT", f.Btn, "BOTTOMRIGHT", 6, 3)
    f.Have:SetPoint("RIGHT", -2, 0)
    return f
end

local function UpdateMaterials()
    local inv = Kit.Call("GetInventory") or {}
    local n = #P.mats
    for i = 1, n do
        local b, e = P.mats[i], inv[i]
        if e and not (i == n and #inv > n) then
            b:SetItemKey(e.key, e.count)
            b:Show()
        else
            b:Clear()
            b:Hide()
        end
    end
    if #inv > n then
        P.more:SetText(string.format("+%d", #inv - n + 1))
        P.more:SetPoint("CENTER", P.mats[n], "CENTER")
        P.more:Show()
    else
        P.more:Hide()
    end
    P.matHeader.right:SetText(#inv == 0 and "Nothing in storage" or string.format("%d kinds", #inv))
end

UpdateDetail = function()
    local d = Selected()
    local R = P.right
    if not d then
        R.Empty:Show()
        R.Body:Hide()
        return
    end
    R.Empty:Hide()
    R.Body:Show()
    local info, recipe, o = d.info, d.info.recipe, d.out
    P.qty = ClampQty(P.qty, d)

    -- output
    R.Out:SetItem({ icon = o.icon, itemID = o.itemID, quality = o.quality, count = o.n * P.qty,
                    name = recipe.name or info.key, lines = OutputLines(recipe, o) })
    R.Name:SetText(recipe.name or info.key)
    local r, g, b = ns.QUALITY_COLOR(o.quality)
    R.Name:SetTextColor(r, g, b)
    R.Sub:SetText(string.format("%s level %d  -  %s", BuildingName(recipe.building), recipe.buildingLevel or 1, TierName(recipe.tier or 1)))
    if o.gear then
        local il = Kit.Call("CraftIlvl", o.tier, o.quality)
        R.Desc:SetText(string.format("Creates a %s %s item%s", D.QUALITY and D.QUALITY[o.quality] or "", SLOT_NAME[o.gear] or o.gear:lower(),
            il and string.format(", item level about |cffffd100%d|r", math.floor(il)) or ""))
    else
        R.Desc:SetText(string.format("Creates %d  -  you have |cffffffff%d|r", o.n, Kit.Call("Count", o.itemKey) or 0))
    end

    -- reagents
    for i, f in ipairs(R.reagents) do
        local k = d.inputs[i]
        if k then
            local need = recipe.inputs[k] * P.qty
            local have = Kit.Call("Count", k) or 0
            local it = Kit.Item(k)
            f.Btn:SetItemKey(k, nil, { { string.format("Need %d for %d craft%s", need, P.qty, P.qty == 1 and "" or "s"), 1, 0.82, 0 } })
            f.Btn:SetDesaturated(have < need)
            f.Name:SetText(it and it.name or k)
            local qr, qg, qb = ns.QUALITY_COLOR(it and it.quality or 1)
            f.Name:SetTextColor(qr, qg, qb)
            f.Have:SetText(string.format("%s%d|r / %d", have >= need and "|cffffffff" or "|cffff3030", have, need))
            f:Show()
        else
            f:Hide()
        end
    end
    R.noReagents:SetShown(#d.inputs == 0)

    -- cost / time
    local goldEach = recipe.gold or 0
    R.Cost:SetCopper(goldEach * P.qty)
    local gold = Kit.Call("Gold") or 0
    if goldEach * P.qty > gold then R.Cost:SetTextColor(1, 0.3, 0.3) else R.Cost:SetTextColor(1, 1, 1) end
    local speed = CraftSpeed()
    R.Time:SetText(U.Duration(CraftSeconds(recipe, P.qty)) ..
        (speed > 0 and string.format("  |cff40ff40(-%d%%)|r", math.floor(speed * 100 + 0.5)) or ""))
    R.Each:SetText(P.qty > 1 and string.format("%s and %s each", Kit.Coin(goldEach), U.Duration(CraftSeconds(recipe, 1))) or "")

    -- quantity + craft
    local maxN = info.maxCraftable or 0
    R.Minus:SetEnabled(P.qty > 1)
    R.Plus:SetEnabled(P.qty < maxN)
    R.Max:SetEnabledTip(maxN > 1, maxN < 1 and (info.reason or "Nothing to craft") or "You can only make one")
    R.Max:SetTip(string.format("Set to the most you can make (%d)", maxN))
    if P.qtyBox:GetText() ~= tostring(P.qty) then P.qtyBox:SetText(tostring(P.qty)) end
    R.Craft:SetEnabledTip(info.canCraft and P.qty <= maxN, info.reason or "You cannot craft that many")
    R.Craft:SetTip(string.format("Queue %dx %s at the %s", P.qty, recipe.name or info.key, BuildingName(recipe.building)))
    R.MaxText:SetText(maxN > 0 and string.format("You can make |cffffffff%d|r", maxN) or ("|cffff5050" .. (info.reason or "Cannot craft") .. "|r"))

    -- queue of this building
    local t = QueueTask(recipe.building)
    P.queueTask = t
    R.QueueHeader:SetText(BuildingName(recipe.building) .. " queue")
    if t then
        R.QIcon:SetTexture(t.icon or (t.recipe and P.byKey[t.recipe] and P.byKey[t.recipe].out.icon) or BUILDING_ICON[recipe.building] or 134400)
        R.QName:SetText(t.name or "?")
        R.QBar:SetTimes(t.startAt, t.endAt)
        R.QIcon:Show(); R.QName:Show(); R.QBar:Show(); R.QBtn:Show()
        R.QEmpty:Hide()
        UpdateQueueButton(R.QBtn, time())
        R.QueueHeader.right:SetText("Done at " .. U.Clock(t.endAt))
    else
        R.QIcon:Hide(); R.QName:Hide(); R.QBar:Hide(); R.QBtn:Hide()
        R.QEmpty:SetText(string.format("The %s is idle.", BuildingName(recipe.building)))
        R.QEmpty:Show()
        R.QueueHeader.right:SetText("One craft at a time")
    end
end

local function DoCraft()
    local d = Selected()
    if not d then return end
    local ok = Kit.Do("Craft", d.info.key, P.qty)
    if ok then
        UI.Status(string.format("Crafting %dx %s", P.qty, d.info.recipe.name or d.info.key), 0.3, 1, 0.3)
        P.qty = 1
    end
end

------------------------------------------------------------------------
-- build / refresh
------------------------------------------------------------------------

local function Build(panel)
    -- left: recipe list
    local left = Kit.Inset(panel)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LIST_W)
    local bg = left:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    if not Kit.Atlas(bg, "Professions-background-summarylist") then bg:Hide() end
    P.listHeader = Kit.Header(left, "Recipes", LIST_W - 12)
    P.listHeader:SetPoint("TOPLEFT", 6, -4)
    P.list = Kit.List(left, {
        rowHeight = ROW_H, build = BuildRow, update = UpdateRow, tooltip = RowTooltip,
        key = function(d) return d.id end,
        onClick = function(row, d, button, L)
            if d.kind == "BUILDING" then
                P.collapsed[d.building] = not P.collapsed[d.building]
                UI.Refresh()
            elseif d.kind == "RECIPE" then
                if P.selKey ~= d.id then P.qty = 1 end
                P.selKey = d.id
                L:SetSelected(d.id)
                UpdateDetail()
            end
        end,
    })
    P.list:SetPoint("TOPLEFT", 4, -26)
    P.list:SetPoint("BOTTOMRIGHT", -4, 4)
    P.listEmpty = Kit.Text(left, "GameFontDisable", "CENTER")
    P.listEmpty:SetPoint("CENTER")
    P.listEmpty:SetText("No recipes known.")
    P.listEmpty:Hide()

    -- right: schematic
    local R = CreateFrame("Frame", nil, panel)
    R:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    R:SetPoint("BOTTOMRIGHT", 0, 0)
    P.right = R
    R.Empty = Kit.Text(R, "GameFontDisable", "CENTER")
    R.Empty:SetPoint("TOP", 0, -120)
    R.Empty:SetText("Select a recipe.")
    R.Body = CreateFrame("Frame", nil, R)
    R.Body:SetPoint("TOPLEFT")
    R.Body:SetPoint("RIGHT")
    R.Body:SetHeight(330)
    local B = R.Body

    R.Out = Kit.ItemButton(B, 46)
    R.Out:SetPoint("TOPLEFT", 4, -4)
    R.Name = Kit.Text(B, "GameFontNormalLarge")
    R.Name:SetPoint("TOPLEFT", R.Out, "TOPRIGHT", 10, -2)
    R.Name:SetPoint("RIGHT", -4, 0)
    R.Sub = Kit.Text(B, "GameFontHighlightSmall")
    R.Sub:SetPoint("TOPLEFT", R.Name, "BOTTOMLEFT", 0, -3)
    R.Sub:SetTextColor(0.75, 0.75, 0.75)
    R.Desc = Kit.Text(B, "GameFontHighlightSmall")
    R.Desc:SetPoint("TOPLEFT", R.Sub, "BOTTOMLEFT", 0, -3)
    R.Desc:SetPoint("RIGHT", -4, 0)

    R.ReagHeader = Kit.Header(B, "Reagents", 580)
    R.ReagHeader:SetPoint("TOPLEFT", 0, -58)
    R.ReagHeader:SetPoint("RIGHT", 0, 0)
    R.reagents = {}
    for i = 1, MAX_REAGENTS do
        local f = BuildReagent(B, i)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        f:SetPoint("TOPLEFT", 4 + col * 290, -80 - row * 36)
        R.reagents[i] = f
    end
    R.noReagents = Kit.Text(B, "GameFontDisableSmall")
    R.noReagents:SetPoint("TOPLEFT", 6, -84)
    R.noReagents:SetText("No reagents needed.")

    -- cost, time, quantity
    local y = -80 - 3 * 36 - 4
    local costL = Kit.Text(B, "GameFontNormalSmall")
    costL:SetPoint("TOPLEFT", 6, y)
    costL:SetText("Cost")
    R.Cost = Kit.CoinText(B, "GameFontHighlight")
    R.Cost:SetJustifyH("LEFT")
    R.Cost:SetPoint("LEFT", costL, "LEFT", 40, 0)
    local timeL = Kit.Text(B, "GameFontNormalSmall")
    timeL:SetPoint("TOPLEFT", 200, y)
    timeL:SetText("Time")
    R.Time = Kit.Text(B, "GameFontHighlight")
    R.Time:SetPoint("LEFT", timeL, "LEFT", 40, 0)
    R.Each = Kit.Text(B, "GameFontDisableSmall", "RIGHT")
    R.Each:SetPoint("TOPRIGHT", -6, y - 1)

    y = y - 26
    R.Minus = Kit.Button(B, "-", 22, 22, function() SetQty(P.qty - 1) end, "One less")
    R.Minus:SetPoint("TOPLEFT", 4, y)
    local box = CreateFrame("EditBox", nil, B, "InputBoxTemplate")
    box:SetSize(40, 20)
    box:SetPoint("LEFT", R.Minus, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(3)
    box:SetJustifyH("CENTER")
    box:SetText("1")
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); SetQty(self:GetText()) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(tostring(P.qty)) end)
    -- hooked, not replaced: InputBoxTemplate's own handler clears the text highlight
    box:HookScript("OnEditFocusLost", function(self) SetQty(self:GetText()) end)
    P.qtyBox = box
    R.Plus = Kit.Button(B, "+", 22, 22, function() SetQty(P.qty + 1) end, "One more")
    R.Plus:SetPoint("LEFT", box, "RIGHT", 4, 0)
    R.Max = Kit.Button(B, "Max", 50, 22, function()
        local d = Selected()
        if d then SetQty(d.info.maxCraftable or 1) end
    end)
    R.Max:SetPoint("LEFT", R.Plus, "RIGHT", 4, 0)
    R.MaxText = Kit.Text(B, "GameFontHighlightSmall")
    R.MaxText:SetPoint("LEFT", R.Max, "RIGHT", 10, 0)
    R.MaxText:SetWidth(200)
    R.Craft = Kit.Button(B, "Craft", 110, 22, DoCraft)
    R.Craft:SetPoint("TOPRIGHT", -4, y)

    -- queue
    y = y - 32
    R.QueueHeader = Kit.Header(B, "Queue", 580)
    R.QueueHeader:SetPoint("TOPLEFT", 0, y)
    R.QueueHeader:SetPoint("RIGHT", 0, 0)
    local q = CreateFrame("Frame", nil, B)
    q:SetPoint("TOPLEFT", 0, y - 22)
    q:SetPoint("RIGHT", 0, 0)
    q:SetHeight(22)
    R.QIcon = q:CreateTexture(nil, "ARTWORK")
    R.QIcon:SetSize(18, 18)
    R.QIcon:SetPoint("LEFT", 4, 0)
    R.QIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    R.QName = Kit.Text(q, "GameFontHighlightSmall")
    R.QName:SetPoint("LEFT", R.QIcon, "RIGHT", 5, 0)
    R.QName:SetWidth(180)
    R.QBar = Kit.ProgressBar(q, 250, 14)
    R.QBar:SetPoint("LEFT", 214, 0)
    R.QBtn = Kit.Button(q, "Cancel", 70, 18, QueueClick)
    R.QBtn:SetPoint("RIGHT", -4, 0)
    Kit.Live(R.QBtn, function(btn, now) UpdateQueueButton(btn, now) end)
    R.QEmpty = Kit.Text(q, "GameFontDisableSmall")
    R.QEmpty:SetPoint("LEFT", 6, 0)
    B:SetHeight(-(y - 22 - 24))

    -- materials grid (bottom)
    local per = math.floor((600 + MAT_GAP) / (MAT_SIZE + MAT_GAP))
    P.matHeader = Kit.Header(R, "Materials", 580)
    P.matHeader:SetPoint("BOTTOMLEFT", 0, MAT_ROWS * (MAT_SIZE + MAT_GAP) + 6)
    P.matHeader:SetPoint("RIGHT", 0, 0)
    P.mats = {}
    for i = 1, per * MAT_ROWS do
        local b = Kit.ItemButton(R, MAT_SIZE)
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        b:SetPoint("BOTTOMLEFT", 2 + col * (MAT_SIZE + MAT_GAP), (MAT_ROWS - 1 - row) * (MAT_SIZE + MAT_GAP) + 2)
        b:Hide()
        P.mats[i] = b
    end
    P.more = Kit.Text(R, "GameFontNormal", "CENTER")
    P.more:Hide()
end

local function Refresh(panel)
    local data, byKey, recipes = BuildData()
    P.byKey = byKey
    -- keep the selection; else the first craftable recipe; else the first recipe
    if not (P.selKey and byKey[P.selKey]) then
        P.selKey = nil
        for _, info in ipairs(recipes) do
            if info.canCraft then P.selKey = info.key; break end
        end
        if not P.selKey and recipes[1] then P.selKey = recipes[1].key end
        P.qty = 1
    end
    -- a collapsed building hides its rows but keeps the selected recipe on the right
    P.list:SetData(data)
    P.list:SetSelected(P.selKey)
    P.listEmpty:SetShown(#recipes == 0)
    local ready = 0
    for _, info in ipairs(recipes) do if info.canCraft then ready = ready + 1 end end
    P.listHeader.right:SetText(string.format("%d ready  -  %d known", ready, #recipes))
    UpdateDetail()
    UpdateMaterials()
end

UI.RegisterTab({ key = "CRAFTING", title = "Crafting", order = 5, build = Build, refresh = Refresh })
