local ADDON, ns = ...

ns.D = ns.D or {}
ns.Game = ns.Game or {}
ns.UI = ns.UI or {}
ns.Util = ns.Util or {}
ns.VERSION = "1.0.0"

local U = ns.Util

-- event bus: engine fires, UI listens; handlers run synchronously in registration order
local listeners = {}
function ns.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- "2h 05m", "14m 03s", "45s"; days shown past 24 h
function U.Duration(secs)
    secs = math.max(0, math.floor(secs or 0))
    local d, h, m, s = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60), secs % 60
    if d > 0 then return string.format("%dd %02dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

function U.Clock(t)
    return date("%H:%M", t)
end

function U.Copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = U.Copy(v) end
    return c
end

function U.Clamp(x, a, b)
    if x < a then return a elseif x > b then return b end
    return x
end

function U.Round(x)
    return math.floor(x + 0.5)
end

function U.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Fisher-Yates; rng(n) must return 1..n (defaults to math.random)
function U.Shuffle(t, rng)
    rng = rng or math.random
    for i = #t, 2, -1 do
        local j = rng(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Sets an atlas when the client has it; false lets the caller fall back to a plain texture
function ns.Atlas(tex, name, useAtlasSize)
    if not (tex and name) then return false end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if not ok or not info then return false end
    end
    local ok = pcall(tex.SetAtlas, tex, name, useAtlasSize)
    return ok
end

local QUALITY_FALLBACK = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
-- r, g, b, hex ("ffa335ee") for an item quality
function ns.QUALITY_COLOR(q)
    q = q or 1
    if C_Item and C_Item.GetItemQualityColor then
        local ok, r, g, b, hex = pcall(C_Item.GetItemQualityColor, q)
        if ok and r then return r, g, b, hex end
    end
    local c = QUALITY_FALLBACK[q] or QUALITY_FALLBACK[1]
    return c[1], c[2], c[3], string.format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local iconCache = {}
-- icon fileID for an item, cached; falls back to the given path, then the question mark
function ns.ItemIcon(itemID, fallback)
    if itemID and iconCache[itemID] then return iconCache[itemID] end
    local icon
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, r = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = r end
    end
    if icon then iconCache[itemID] = icon end
    return icon or fallback or 134400
end

-- data race keys are compact ("NightElf", "BloodElf"); this gives the name players read
local RACE_NAMES = { NightElf = "Night Elf", BloodElf = "Blood Elf", Undead = "Forsaken" }
function U.RaceName(race)
    return RACE_NAMES[race] or race or ""
end
