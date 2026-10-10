--
-- DownedRP - server-side file store.
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--
-- Only the minimum the knockdown module needs was extracted from the original
-- DBNO_Store.lua: the per-account folder, the two knockdown files and the
-- read/write helpers. Snapshots, wounds, respawn points, loot locks, the player
-- index, the audit log and the legacy migration were all dropped.
--
-- Knockdown state lives on disk rather than in memory so that logging out on the
-- death screen cannot reset a player's strike count.
--

if isClient() then return end

DRP = DRP or {}

DRP.Paths = DRP.Paths or {}
DRP.Files = DRP.Files or {}

local Paths = DRP.Paths
local Files = DRP.Files

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

function Paths.safeName(username)
    if username == nil then return nil end
    local s = tostring(username)
    s = s:gsub("[^%w_%- ]", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s
end

function Paths.accountDir(username)
    local safe = Paths.safeName(username)
    if safe == nil then return nil end
    return DRP.Config.dataRoot .. "/" .. safe
end

function Paths.knockdownFile(username)
    local d = Paths.accountDir(username)
    if d == nil then return nil end
    return d .. "/knockdown.txt"
end

function Paths.knockStrikeFile(username)
    local d = Paths.accountDir(username)
    if d == nil then return nil end
    return d .. "/knockstrikes.txt"
end

--------------------------------------------------------------------------------
-- Files
--------------------------------------------------------------------------------

function Files.writeLines(path, lines)
    if path == nil then return false end
    local w = getFileWriter(path, true, false)
    if w == nil then return false end
    for _, line in ipairs(lines) do
        w:write(tostring(line) .. "\n")
    end
    w:close()
    return true
end

function Files.writeString(path, str)
    return Files.writeLines(path, { tostring(str) })
end

function Files.readLines(path)
    if path == nil then return nil end
    local r = getFileReader(path, false)
    if r == nil then return nil end
    local out = {}
    local line = r:readLine()
    while line ~= nil do
        out[#out + 1] = line
        line = r:readLine()
    end
    r:close()
    return out
end

function Files.readString(path)
    local lines = Files.readLines(path)
    if lines == nil or #lines == 0 then return nil end
    return lines[1]
end

function Files.exists(path)
    if path == nil then return false end
    local r = getFileReader(path, false)
    if r == nil then return false end
    local has = r:readLine() ~= nil
    r:close()
    return has
end
