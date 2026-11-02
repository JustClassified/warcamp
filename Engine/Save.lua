local ADDON, ns = ...
local Game, U = ns.Game, ns.Util

----------------------------------------------------------------------------------------------------
-- Engine\Save.lua — keeping progress safe: export / import strings, one backup slot, full reset,
-- and Sanitize(), which repairs a save that holds keys a newer data set no longer has.
--   Game:ExportString()          -> "WARCAMP1:<checksum>:<base64>"
--   Game:ParseImport(text)       -> data | nil, err      (validates, changes nothing)
--   Game:ImportString(text)      -> ok, err               (backs up the current camp first)
--   Game:MakeBackup(reason)      stores the current camp in db.backup (one slot)
--   Game:GetBackup()             -> { at, reason, version } | nil
--   Game:RestoreBackup()         -> ok, err               (the camp it replaces becomes the backup)
--   Game:ResetAll()              wipes the camp (backed up first, so a reset can be undone)
----------------------------------------------------------------------------------------------------

local PREFIX = "WARCAMP1"
-- kept per computer / per install, never exported or overwritten by an import
local LOCAL_KEYS = { ui = true, backup = true, verify = true }
-- rebuilt on load, not worth carrying around
local VOLATILE_KEYS = { away = true }

local function plainCopy(db, skip)
    local out = {}
    for k, v in pairs(db) do
        if not skip[k] then out[k] = U.Copy(v) end
    end
    return out
end

local function exportable(db)
    local skip = {}
    for k in pairs(LOCAL_KEYS) do skip[k] = true end
    for k in pairs(VOLATILE_KEYS) do skip[k] = true end
    return plainCopy(db, skip)
end

-- replace the contents of WarcampDB in place: the UI and engine hold references to this table
local function replaceDB(db, data)
    local keep = {}
    for k in pairs(LOCAL_KEYS) do keep[k] = db[k] end
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(data) do
        if not LOCAL_KEYS[k] then db[k] = v end
    end
    for k, v in pairs(keep) do db[k] = v end
end

local function reload(self)
    self._mute, self._muteDepth = nil, 0
    self:Init(self:Now())
    self:Changed("all")
end

-- the client's own deflate (11.1.5+) cuts the string to about a fifth; plain base64 otherwise
local function encoder()
    local E = C_EncodingUtil
    if E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64 then return E end
end

function Game:ExportString()
    local body = U.Serialize(exportable(self.db))
    local sum = U.Checksum(body)
    local E = encoder()
    if E then
        local ok, packed = pcall(function() return E.EncodeBase64(E.CompressString(body)) end)
        if ok and type(packed) == "string" and packed ~= "" then
            return PREFIX .. "Z:" .. sum .. ":" .. packed
        end
    end
    return PREFIX .. ":" .. sum .. ":" .. U.Base64Encode(body)
end

function Game:ParseImport(text)
    if type(text) ~= "string" then return nil, "Nothing to import." end
    text = text:gsub("%s", "")
    local prefix, packed, sum, b64 = text:match("^(WARCAMP%d+)(Z?):(%x+):(.+)$")
    if not prefix then return nil, "That is not a Warcamp save string." end
    if prefix ~= PREFIX then return nil, "That save comes from a newer Warcamp. Update the addon first." end
    local body
    if packed == "Z" then
        local E = encoder()
        if not E then return nil, "This game client cannot unpack that save string." end
        local ok, r = pcall(function() return E.DecompressString(E.DecodeBase64(b64)) end)
        body = ok and type(r) == "string" and r or nil
    else
        body = U.Base64Decode(b64)
    end
    if not body then return nil, "The save string is damaged (bad characters)." end
    if U.Checksum(body) ~= sum then return nil, "The save string is incomplete or damaged. Copy all of it." end
    local data, err = U.Deserialize(body)
    if type(data) ~= "table" then return nil, "The save could not be read: " .. tostring(err) end
    if type(data.heroes) ~= "table" or type(data.gold) ~= "number" then
        return nil, "That save has no camp in it."
    end
    if (data.version or 1) > Game.DB_VERSION then
        return nil, "That save comes from a newer Warcamp. Update the addon first."
    end
    return data
end

function Game:ImportString(text)
    local data, err = self:ParseImport(text)
    if not data then return false, err end
    self:MakeBackup("before import")
    replaceDB(self.db, data)
    reload(self)
    self:Log("A camp was imported from a save string.")
    return true
end

function Game:MakeBackup(reason)
    local db = self.db
    if not db then return end
    db.backup = { at = self:Now(), reason = reason, version = db.version, text = U.Serialize(exportable(db)) }
end

function Game:GetBackup()
    local b = self.db and self.db.backup
    if type(b) ~= "table" or type(b.text) ~= "string" then return nil end
    return { at = b.at, reason = b.reason, version = b.version }
end

function Game:RestoreBackup()
    local b = self.db and self.db.backup
    if type(b) ~= "table" or type(b.text) ~= "string" then return false, "There is no backup." end
    local data = U.Deserialize(b.text)
    if type(data) ~= "table" or type(data.heroes) ~= "table" then return false, "The backup is damaged." end
    self:MakeBackup("before restoring a backup")
    replaceDB(self.db, data)
    reload(self)
    self:Log("The camp was restored from a backup.")
    return true
end

function Game:ResetAll()
    self:MakeBackup("before reset")
    replaceDB(self.db, {})
    reload(self)
    return true
end

----------------------------------------------------------------------------------------------------
-- Sanitize: run on every load after the migrations. Anything the current data set does not know
-- (an item, recipe or zone an update removed) is dropped instead of crashing a tab. Numbers that
-- went bad are reset. It never touches what it recognises.
----------------------------------------------------------------------------------------------------
local function finite(n, default)
    if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then return default end
    return n
end

local function tableField(db, key)
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

function Game:Sanitize(db)
    local D = ns.D
    local fixed = 0
    local function drop(t, k) t[k] = nil; fixed = fixed + 1 end

    db.gold = math.max(0, math.floor(finite(db.gold, 0)))
    db.tier = U.Clamp(math.floor(finite(db.tier, 1)), 1, self:NumTiers())
    db.nextId = math.max(1, math.floor(finite(db.nextId, 1)))
    for _, key in ipairs({ "heroes", "bag", "inventory", "tasks", "buildings", "storage", "boards",
                           "raidLocks", "clears", "sales", "stats", "achievements", "buffs", "log" }) do
        tableField(db, key)
    end

    -- materials and consumables
    if D.ITEMS then
        for k, n in pairs(db.inventory) do
            if not D.ITEMS[k] or type(n) ~= "number" or n ~= n or n <= 0 then drop(db.inventory, k) end
        end
    end
    -- passive production, keyed by building
    for k, s in pairs(db.storage) do
        if type(s) ~= "table" or (D.BUILDINGS and not D.BUILDINGS[k]) then
            drop(db.storage, k)
        else
            s.have = math.max(0, finite(s.have, 0))
            s.last = finite(s.last, self:Now())
        end
    end
    if D.BUILDINGS then
        for k in pairs(db.buildings) do
            if not D.BUILDINGS[k] then drop(db.buildings, k) end
        end
    end
    if D.BUFFS then
        for k in pairs(db.buffs) do
            if not D.BUFFS[k] then drop(db.buffs, k) end
        end
    end

    -- heroes: kept even when their class left the data (the engine and UI fall back); only junk goes
    local maxId = 0
    for id, h in pairs(db.heroes) do
        if type(h) ~= "table" then
            drop(db.heroes, id)
        else
            h.level = math.max(1, math.floor(finite(h.level, 1)))
            h.xp = math.max(0, finite(h.xp, 0))
            if type(id) == "number" and id > maxId then maxId = id end
        end
    end

    -- tasks: a task whose heroes are gone, or that has no end time, is dropped and its heroes freed
    for id, t in pairs(db.tasks) do
        if type(t) ~= "table" or type(t.endAt) ~= "number" then
            drop(db.tasks, id)
        else
            if type(id) == "number" and id > maxId then maxId = id end
        end
    end
    for _, h in pairs(db.heroes) do
        if h.taskId and not db.tasks[h.taskId] then h.taskId = nil; fixed = fixed + 1 end
    end

    if db.nextId <= maxId then db.nextId = maxId + 1 end

    if self.SanitizeExtra then
        local ok, n = pcall(self.SanitizeExtra, self, db)
        if ok and type(n) == "number" then fixed = fixed + n end
    end
    return fixed
end
