local ADDON, ns = ...
local Game, D = ns.Game, ns.D

-- Every event is registered here at file scope; handlers never register or unregister anything.
local f = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT",
    "LFG_COMPLETION_REWARD", "CHALLENGE_MODE_COMPLETED", "SCENARIO_COMPLETED",
}
for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end

local loaded, started = false, false

local function say(msg)
    print("|cffe0b050Warcamp|r: " .. msg)
end
ns.Say = say

-- the minimap count needs a refresh even when nothing changed, as tasks finish with time
local function tick()
    pcall(Game.Update, Game)
    if ns.UI.UpdateMinimap then pcall(ns.UI.UpdateMinimap) end
end

-- real-world play feeds the camp: a finished dungeon, Mythic+ or delve rallies the recruits
local RALLY_EVENTS = { LFG_COMPLETION_REWARD = true, CHALLENGE_MODE_COMPLETED = true, SCENARIO_COMPLETED = true }
local RALLY_BUFF = "RALLYING_CRY"

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if loaded or arg1 ~= ADDON then return end
        loaded = true
        -- recruits wear looks from the player's own faction (plus neutral ones)
        local ok, faction = pcall(UnitFactionGroup, "player")
        if ok and (faction == "Alliance" or faction == "Horde") then Game.faction = faction end
        local okInit, err = pcall(Game.Init, Game)
        if not okInit then
            if geterrorhandler then geterrorhandler()(err) end
            say("|cffff6060could not load your camp.|r Your save is untouched; please report this error.")
        end
    elseif event == "PLAYER_LOGIN" then
        if started then return end
        started = true
        tick()
        C_Timer.NewTicker(5, tick)
        local ok, welcome = pcall(Game.Welcome, Game)
        if ok and welcome then ns.Fire("REPORT", welcome) end
        local ready = Game:ReadyCount()
        if ready and ready > 0 then
            say(string.format("%d task%s ready at camp. |cff9a927f/warcamp|r", ready, ready == 1 and " is" or "s are"))
        end
    elseif event == "PLAYER_LOGOUT" then
        if WarcampDB then WarcampDB.lastSeen = time() end
    elseif RALLY_EVENTS[event] then
        if started and D.BUFFS and D.BUFFS[RALLY_BUFF] then pcall(Game.GrantBuff, Game, RALLY_BUFF) end
    end
end)

----------------------------------------------------------------------------------------------------
-- /warcamp verify: checks every real Blizzard ID in the data against the client and stores the bad
-- ones in WarcampDB.verify (readable from the SavedVariables file after a /reload).
----------------------------------------------------------------------------------------------------
local function verify()
    local bad, counts = {}, {}
    local function note(kind, id, where)
        bad[#bad + 1] = string.format("%s %s (%s)", kind, tostring(id), where or "?")
    end
    local function check(kind, id, where, fn)
        counts[kind] = (counts[kind] or 0) + 1
        if not id then return end
        local ok, r = pcall(fn, id)
        if not ok or not r then note(kind, id, where) end
    end
    local itemOK = function(id) return C_Item.GetItemInfoInstant(id) end
    for key, it in pairs(D.ITEMS or {}) do check("item", it.itemID, key, itemOK) end
    for tier, slots in pairs(D.GEAR_BASES or {}) do
        for slot, list in pairs(slots) do
            for _, b in ipairs(list) do check("item", b.itemID, "gear t" .. tier .. " " .. slot, itemOK) end
        end
    end
    for _, z in ipairs(D.ZONES or {}) do
        check("map", z.mapID, z.key, function(id) return C_Map.GetMapInfo(id) end)
    end
    local function instances(list)
        for _, ins in ipairs(list or {}) do
            check("journal", ins.journalID, ins.key, function(id) return EJ_GetInstanceInfo(id) end)
            if ins.mount then
                check("mount", ins.mount.mountID, ins.key, function(id) return C_MountJournal.GetMountInfoByID(id) end)
            end
            if ins.pet then
                check("pet", ins.pet.speciesID, ins.key, function(id) return C_PetJournal.GetPetInfoBySpeciesID(id) end)
            end
        end
    end
    instances(D.DUNGEONS); instances(D.RAIDS)
    for _, m in ipairs(D.MOUNTS or {}) do
        check("mount", m.mountID, m.source, function(id) return C_MountJournal.GetMountInfoByID(id) end)
    end
    for _, p in ipairs(D.PETS or {}) do
        check("pet", p.speciesID, p.source, function(id) return C_PetJournal.GetPetInfoBySpeciesID(id) end)
    end

    -- display IDs have no lookup API: load each into a hidden model and see whether a model file arrives
    local displays = {}
    local function addDisplay(id, where) if id then displays[#displays + 1] = { id = id, where = where } end end
    for class, looks in pairs(D.LOOKS or {}) do
        for _, l in ipairs(looks) do addDisplay(l.display, "look " .. class .. " " .. (l.npc or "")) end
    end
    for _, z in ipairs(D.ZONES or {}) do
        for _, m in ipairs(z.mobs or {}) do addDisplay(m.display, z.key .. " " .. (m.name or "")) end
    end
    for _, list in ipairs({ D.DUNGEONS or {}, D.RAIDS or {} }) do
        for _, ins in ipairs(list) do
            for _, b in ipairs(ins.bosses or {}) do addDisplay(b.display, ins.key .. " " .. (b.name or "")) end
        end
    end
    counts.display = #displays

    -- one probe model for the session (a second /warcamp verify reuses it instead of leaking another frame)
    local model = ns.verifyModel
    if not model then
        model = CreateFrame("PlayerModel", nil, UIParent)
        model:SetSize(64, 64)
        model:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)   -- off screen
        ns.verifyModel = model
    end
    model:Show()
    local i, waited = 0, 0
    say(string.format("verifying %d display IDs, this takes a few seconds...", #displays))
    model:SetScript("OnUpdate", function(self, elapsed)
        if i > 0 then
            waited = waited + elapsed
            if waited < 0.15 then return end
            local ok, file = pcall(self.GetModelFileID, self)
            local missing = not ok or not file or file == 0
            if missing and waited < 1 then return end   -- a cold model may still be streaming in
            if missing then note("display", displays[i].id, displays[i].where) end
        end
        i, waited = i + 1, 0
        local d = displays[i]
        if not d then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            WarcampDB.verify = { at = time(), bad = bad, counts = counts }
            local parts = {}
            for k, n in pairs(counts) do parts[#parts + 1] = k .. " " .. n end
            table.sort(parts)
            say("checked " .. table.concat(parts, ", ") .. ".")
            if #bad == 0 then
                say("all IDs are valid.")
            else
                say(string.format("|cffff6060%d bad ID%s|r:", #bad, #bad == 1 and "" or "s"))
                for n = 1, math.min(#bad, 40) do print("   " .. bad[n]) end
                if #bad > 40 then print("   ... and " .. (#bad - 40) .. " more (saved in WarcampDB.verify)") end
            end
            return
        end
        self:ClearModel()
        pcall(self.SetDisplayInfo, self, d.id)
    end)
end

-- not /camp: that is the built-in logout command and always wins
SLASH_WARCAMP1, SLASH_WARCAMP2 = "/warcamp", "/wcamp"
SlashCmdList.WARCAMP = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "verify" then
        verify()
    elseif msg == "reset confirm" then
        Game:ResetAll()
        say("your camp has been reset. The old one is kept as a backup (/warcamp options).")
    elseif msg == "reset" then
        say("this wipes every recruit, item and building. Type |cffffd100/warcamp reset confirm|r to do it.")
    elseif msg == "export" or msg == "import" then
        ns.UI.ShowSaveDialog(msg)
    elseif msg == "options" or msg == "config" or msg == "settings" then
        ns.UI.OpenOptions()
    elseif msg == "help" then
        say("/warcamp (or /wcamp) - open or close the camp")
        say("/warcamp <tab> - camp, bags, heroes, missions, dungeons, crafting, market, collection")
        say("/warcamp options | export | import | verify | reset")
    elseif msg ~= "" then
        ns.UI.Show(msg:upper())
    else
        ns.UI.Toggle()
    end
end
