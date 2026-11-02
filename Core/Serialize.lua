local ADDON, ns = ...
local U = ns.Util

----------------------------------------------------------------------------------------------------
-- Core\Serialize.lua — plain-data tables <-> text, for save export / import and backups.
--   U.Serialize(value)        -> string (tables, strings, numbers, booleans; keys sorted, deterministic)
--   U.Deserialize(str)        -> value | nil, err   (own parser: never loadstring on pasted text)
--   U.Base64Encode(s) / U.Base64Decode(s)          (Lua 5.1, arithmetic only)
--   U.Checksum(s)             -> 8-hex-digit string
----------------------------------------------------------------------------------------------------

local byte, char, sub, format, floor = string.byte, string.char, string.sub, string.format, math.floor
local concat = table.concat

-- ===== serialize =====
local function numberText(n)
    if n ~= n or n == math.huge or n == -math.huge then return "0" end   -- NaN / inf never reach a save
    if n == floor(n) and math.abs(n) < 2 ^ 53 then return format("%d", n) end
    return format("%.17g", n)
end

local function stringText(s)
    return (format("%q", s):gsub("\\\n", "\\n"))
end

local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end

local function write(v, out, seen)
    local t = type(v)
    if t == "table" then
        if seen[v] then error("cycle in saved data") end
        seen[v] = true
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            local tk = type(k)
            if tk == "string" or tk == "number" or tk == "boolean" then keys[#keys + 1] = k end
        end
        table.sort(keys, keyOrder)
        for _, k in ipairs(keys) do
            local val, tv = v[k], type(v[k])
            if tv == "table" or tv == "string" or tv == "number" or tv == "boolean" then
                out[#out + 1] = "["
                write(k, out, seen)
                out[#out + 1] = "]="
                write(val, out, seen)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
        seen[v] = nil
    elseif t == "string" then
        out[#out + 1] = stringText(v)
    elseif t == "number" then
        out[#out + 1] = numberText(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    else
        out[#out + 1] = "nil"
    end
end

function U.Serialize(v)
    local out = {}
    write(v, out, {})
    return concat(out)
end

-- ===== deserialize: a small recursive-descent parser for exactly what Serialize writes =====
local ESC = { n = "\n", r = "\r", t = "\t", a = "\a", b = "\b", f = "\f", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }
local MAX_DEPTH = 40

function U.Deserialize(s)
    if type(s) ~= "string" then return nil, "no text" end
    local pos, len = 1, #s

    local function fail(msg) error({ msg = msg .. " at " .. pos }, 0) end
    local function skip()
        while pos <= len do
            local c = byte(s, pos)
            if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1 else break end
        end
    end

    local value
    local function readString()
        pos = pos + 1   -- opening quote
        local buf, start = {}, pos
        while true do
            if pos > len then fail("unfinished text") end
            local c = sub(s, pos, pos)
            if c == '"' then
                buf[#buf + 1] = sub(s, start, pos - 1)
                pos = pos + 1
                return concat(buf)
            elseif c == "\\" then
                buf[#buf + 1] = sub(s, start, pos - 1)
                local e = sub(s, pos + 1, pos + 1)
                if e:match("%d") then
                    local digits = s:match("^%d%d?%d?", pos + 1)
                    local n = tonumber(digits)
                    if n > 255 then fail("bad escape") end
                    buf[#buf + 1] = char(n)
                    pos = pos + 1 + #digits
                elseif ESC[e] then
                    buf[#buf + 1] = ESC[e]
                    pos = pos + 2
                else
                    fail("bad escape")
                end
                start = pos
            else
                pos = pos + 1
            end
        end
    end

    local function readTable(depth)
        if depth > MAX_DEPTH then fail("too deep") end
        pos = pos + 1   -- {
        local t = {}
        while true do
            skip()
            local c = sub(s, pos, pos)
            if c == "}" then pos = pos + 1; return t end
            if c ~= "[" then fail("expected [") end
            pos = pos + 1
            skip()
            local k = value(depth + 1)
            skip()
            if sub(s, pos, pos + 1) ~= "]=" then fail("expected ]=") end
            pos = pos + 2
            skip()
            local v = value(depth + 1)
            if k ~= nil and v ~= nil then t[k] = v end
            skip()
            if sub(s, pos, pos) == "," then pos = pos + 1 end
        end
    end

    function value(depth)
        skip()
        local c = sub(s, pos, pos)
        if c == "{" then return readTable(depth) end
        if c == '"' then return readString() end
        if sub(s, pos, pos + 3) == "true" then pos = pos + 4; return true end
        if sub(s, pos, pos + 4) == "false" then pos = pos + 5; return false end
        if sub(s, pos, pos + 2) == "nil" then pos = pos + 3; return nil end
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if num and num ~= "" and num ~= "-" then
            local n = tonumber(num)
            if not n then fail("bad number") end
            pos = pos + #num
            return n
        end
        fail("unexpected '" .. c .. "'")
    end

    local ok, result = pcall(function()
        local v = value(0)
        skip()
        if pos <= len then fail("trailing text") end
        return v
    end)
    if not ok then
        return nil, type(result) == "table" and result.msg or tostring(result)
    end
    return result
end

-- ===== base64 (no bit library needed) =====
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
    local c = sub(B64, i, i)
    ENC[i - 1] = c
    DEC[byte(c)] = i - 1
end

function U.Base64Encode(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = byte(s, i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = floor(v / 262144), floor(v / 4096) % 64
        local c3, c4 = floor(v / 64) % 64, v % 64
        out[#out + 1] = ENC[c1] .. ENC[c2] .. (b and ENC[c3] or "=") .. (c and ENC[c4] or "=")
    end
    return concat(out)
end

function U.Base64Decode(s)
    s = s:gsub("[^%w%+/=]", "")
    if #s % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q1, q2, q3, q4 = byte(s, i, i + 3)
        local a, b = DEC[q1], DEC[q2]
        if not (a and b) then return nil end
        local c = q3 ~= 61 and DEC[q3] or nil
        local d = q4 ~= 61 and DEC[q4] or nil
        if (q3 ~= 61 and not c) or (q4 ~= 61 and not d) then return nil end
        local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        out[#out + 1] = char(floor(v / 65536))
        if c then out[#out + 1] = char(floor(v / 256) % 256) end
        if d then out[#out + 1] = char(v % 256) end
    end
    return concat(out)
end

function U.Checksum(s)
    local h1, h2 = 5381, 0
    for i = 1, #s do
        local c = byte(s, i)
        h1 = (h1 * 33 + c) % 4294967291
        h2 = (h2 + h1) % 65521
    end
    return format("%08x", (h1 + h2 * 65536) % 4294967296)
end
