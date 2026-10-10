--
-- DownedRP - server commands.
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--

if isClient() then return end

DRP = DRP or {}

--------------------------------------------------------------------------------
-- Speed helpers
--------------------------------------------------------------------------------

local function applyCrawlSpeed(player)
    if player == nil then return end
    local pct = (DRP.Config and DRP.Config.knockdownCrawlSpeedPct) or 30
    pct = tonumber(pct) or 30
    if pct < 1 then pct = 1 elseif pct > 100 then pct = 100 end
    if player.setSpeedMod then player:setSpeedMod(pct / 100.0) end
end
DRP.applyCrawlSpeed = applyCrawlSpeed

local function restoreNormalSpeed(player)
    if player == nil then return end
    if player.setSpeedMod then player:setSpeedMod(1.0) end
end
DRP.restoreNormalSpeed = restoreNormalSpeed

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function broadcast(initiator, state)
    local players = getOnlinePlayers()
    if players == nil then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p ~= initiator then
            sendServerCommand(p, "DRPKnock", "setstate", { id = initiator:getOnlineID(), state = state })
        end
    end
end

local function setServerFlags(player, down)
    local C = DRP.Config
    player:setZombiesDontAttack(down and C.downedZombieKill ~= true)
    player:setShootable((not down) or C.downedPlayerKill == true)
    if down then
        if C.downedZombieKill ~= true then player:setOnFloor(true) end
        DRP.enterDownedHealth(player)
    else
        player:setOnFloor(false)
        DRP.releaseHealth(player)
    end
end

local function downFile(player)
    return DRP.Paths.knockdownFile(player:getUsername())
end

local function strikeFile(player)
    return DRP.Paths.knockStrikeFile(player:getUsername())
end

local function readStrikes(player, now)
    local sf = strikeFile(player)
    local windowMs = ((DRP.Config.knockdownWindowSec) or 300) * 1000
    local out = {}
    if sf then
        local raw = DRP.Files.readString(sf)
        if raw and raw ~= "" then
            for t in string.gmatch(raw, "[^,]+") do
                local n = tonumber(t)
                if n and (now - n) < windowMs then out[#out + 1] = n end
            end
        end
    end
    return out, sf
end

--------------------------------------------------------------------------------
-- Knockdown command handlers
--------------------------------------------------------------------------------

local knock = {}

function knock.requestdown(player, args, user)
    local now = getTimestampMs()
    local limit = (DRP.Config.knockdownStrikeLimit) or 3
    local counters = (DRP.Config.knockdownCounters ~= false)
    local recent, sf = readStrikes(player, now)

    if counters then
        if (#recent + 1) > limit then
            sendServerCommand(player, "DRPKnock", "downverdict", { ok = false, strike = #recent + 1, limit = limit })
            return
        end
        recent[#recent + 1] = now
        if sf then DRP.Files.writeString(sf, table.concat(recent, ",")) end
    end
    local df = downFile(player); if df then DRP.Files.writeString(df, tostring(now)) end
    player:getModData().drp_downed = true
    player:getModData().drp_downedStart = now
    setServerFlags(player, true)
    applyCrawlSpeed(player)
    sendServerCommand(player, "DRPKnock", "downverdict",
        { ok = true, strike = counters and #recent or 0, limit = limit })
    broadcast(player, "down")
end

function knock.getup(player)
    player:getModData().drp_downed = false
    player:getModData().drp_downedStart = nil
    setServerFlags(player, false)
    restoreNormalSpeed(player)

    -- Restore HP on the server side. In MP the client's :setHealth() is purely
    -- local; without this the server still sees the downed HP buffer and
    -- re-triggers the knockdown on the next tick.
    local hp = DRP.Config.knockdownReviveHp or 30
    DRP.stopBleeding(player)
    DRP.setGeneralHealth(player, hp)
    player:setHealth(hp)

    local df = downFile(player); if df then DRP.Files.writeString(df, "0") end
    broadcast(player, "up")
end

function knock.resumed(player)
    setServerFlags(player, true)
    applyCrawlSpeed(player)
    broadcast(player, "down")
end

function knock.reviving(player, args)
    if not args or not args.targetId then return end
    local target = getPlayerByOnlineID(args.targetId)
    if target then sendServerCommand(target, "DRPKnock", "revivenotice", { active = true, name = DRP.displayName(player) }) end
end

function knock.revivecancel(player, args)
    if not args or not args.targetId then return end
    local target = getPlayerByOnlineID(args.targetId)
    if target then sendServerCommand(target, "DRPKnock", "revivenotice", { active = false }) end
end

function knock.reviverequest(player, args)
    if not args or not args.targetId then return end
    local target = getPlayerByOnlineID(args.targetId)
    if target == nil then return end
    local down = target:getModData().drp_downed
    if not down then
        local df = downFile(target)
        if df then down = (tonumber(DRP.Files.readString(df) or "0") or 0) > 0 end
    end
    if not down then return end
    if math.abs(player:getX() - target:getX()) > 3 or math.abs(player:getY() - target:getY()) > 3 then return end
    sendServerCommand(target, "DRPKnock", "forcegetup", {})
    if DRP.Config.assistEnable then
        knock.assiststart(player, { targetId = target:getOnlineID() })
    end
end

function knock.realdeath(player, args, user)
    local df = downFile(player); if df then DRP.Files.writeString(df, "0") end
    local sf = strikeFile(player); if sf then DRP.Files.writeString(sf, "") end
end

function knock.forcedeath(player)
    local md = player:getModData()
    md.drp_downed = false
    md.drp_downedStart = nil
    restoreNormalSpeed(player)
    local df = downFile(player); if df then DRP.Files.writeString(df, "0") end

    local sf = strikeFile(player); if sf then DRP.Files.writeString(sf, "") end
    DRP.releaseHealth(player)
    player:setGodMod(false)
    DRP.setGeneralHealth(player, 0)
    player:setHealth(0)
    broadcast(player, "up")

    if not player:isOnDeathDone() then
        player:die()
    end
end

function knock.selfgetup(player)
    local md = player:getModData()
    if not md.drp_downed then return end
    local treated, pending = DRP.areWoundsTreated(player)
    if not treated then return end
    if not DRP.selfTreatAllowed(player) then return end
    knock.getup(player)
end

function knock.assiststart(player, args)
    if not args or not args.targetId then return end
    local target = getPlayerByOnlineID(args.targetId)
    if target == nil then return end
    if not DRP.Config.assistEnable then return end

    local md = target:getModData()
    md.drp_assisted = true
    md.drp_assisterId = player:getOnlineID()

    local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
    if player.setSpeedMod then player:setSpeedMod(mod) end
    if target.setSpeedMod then target:setSpeedMod(mod) end

    sendServerCommand(target, "DRPKnock", "assiststart", { assisterId = player:getOnlineID() })
    sendServerCommand(player, "DRPKnock", "assiststart", { targetId = target:getOnlineID() })
end

function knock.assiststop(player, args)
    local md = player:getModData()
    local assisterId = md.drp_assisterId
    md.drp_assisted = false
    md.drp_assisterId = nil

    if player.setSpeedMod then player:setSpeedMod(1.0) end

    if assisterId then
        local assister = getPlayerByOnlineID(assisterId)
        if assister then
            if assister.setSpeedMod then assister:setSpeedMod(1.0) end
            sendServerCommand(assister, "DRPKnock", "assiststop", {})
        end
    end
    sendServerCommand(player, "DRPKnock", "assiststop", {})
end

function knock.assistsync(player, args)
    if not DRP.Config.assistEnable then return end
    local md = player:getModData()
    if not md.drp_assisted then return end
    local assisterId = md.drp_assisterId
    if not assisterId then return end
    local assister = getPlayerByOnlineID(assisterId)
    if not assister then
        knock.assiststop(player)
        return
    end
    local dist = math.sqrt((player:getX() - assister:getX())^2 + (player:getY() - assister:getY())^2)
    local breakDist = DRP.Config.assistBreakDistance or 5
    if dist > breakDist then
        knock.assiststop(player)
        return
    end
    local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
    if player.setSpeedMod then player:setSpeedMod(mod) end
    if assister.setSpeedMod then assister:setSpeedMod(mod) end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DRPKnock" or player == nil then return end
    local h = knock[command]
    if h then h(player, args, tostring(player:getUsername())) end
end)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DRPKnock" or player == nil then return end
    if command == "forcedeath" then
        knock.forcedeath(player)
    elseif command == "realdeath" then
        knock.realdeath(player, args, tostring(player:getUsername()))
    end
end)

--------------------------------------------------------------------------------
-- Cleanup on character death
--------------------------------------------------------------------------------

Events.OnCharacterDeath.Add(function(character)
    if not (character and instanceof(character, "IsoPlayer")) then return end
    if character:isAnimal() then return end
    local u = character:getUsername()
    if u == nil then return end

    local sf = DRP.Paths.knockStrikeFile(u); if sf then DRP.Files.writeString(sf, "") end
    local df = DRP.Paths.knockdownFile(u);  if df then DRP.Files.writeString(df, "0") end
end)

--------------------------------------------------------------------------------
-- Periodic server-side re-assertion
--------------------------------------------------------------------------------

local _lastDownSync = 0
local _lastHoldSync = 0
local _hadDowned = false

local function downedOnlineIds()
    local ids = {}
    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p:getModData().drp_downed then ids[#ids + 1] = p:getOnlineID() end
        end
    end
    return ids
end

local function reassertHolds()
    local players = getOnlinePlayers()
    if players == nil then return end
    local C = DRP.Config
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local md = p and p:getModData()
        if md and md.drp_downed then
            if C.downedZombieKill ~= true then
                if not p:isZombiesDontAttack() then p:setZombiesDontAttack(true) end
                if not p:isOnFloor() then p:setOnFloor(true) end
                if p:isDeathDragDown() then p:setDeathDragDown(false) end
            end
            applyCrawlSpeed(p)
            local crawled = DRP.Crawl.track(p, md.drp_downedStart)
            if not DRP.tickDownedHealth(p, md.drp_downedStart, crawled) then
                DRP.releaseHealth(p)
            end
        end
    end
end

local function sendDownSet(ids)
    local players = getOnlinePlayers()
    if players == nil then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then sendServerCommand(p, "DRPKnock", "downset", { ids = ids }) end
    end
end

Events.OnTick.Add(function()
    local nowMs = getTimestampMs()
    if (nowMs - _lastHoldSync) >= 250 then
        _lastHoldSync = nowMs
        reassertHolds()
    end

    local now = getTimestamp()
    if (now - _lastDownSync) < 3 then return end
    _lastDownSync = now
    local ids = downedOnlineIds()
    if #ids > 0 then
        sendDownSet(ids)
        _hadDowned = true
    elseif _hadDowned then
        sendDownSet(ids)
        _hadDowned = false
    end
end)

--------------------------------------------------------------------------------
-- Admin commands
--------------------------------------------------------------------------------

local function playerByOnlineId(id)
    local players = getOnlinePlayers()
    if players == nil or id == nil then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getOnlineID() == id then return p end
    end
    return nil
end

local adm = {}

function adm.forceDown(player, args)
    if not DRP.isAdmin(player) then return end
    local t = playerByOnlineId(args and args.id)
    if t == nil or t:getModData().drp_downed then return end

    local now = getTimestampMs()
    local df = downFile(t); if df then DRP.Files.writeString(df, tostring(now)) end
    t:getModData().drp_downed = true
    t:getModData().drp_downedStart = now
    setServerFlags(t, true)
    applyCrawlSpeed(t)
    sendServerCommand(t, "DRPKnock", "forcedown", {})
    broadcast(t, "down")
end

function adm.forceUp(player, args)
    if not DRP.isAdmin(player) then return end
    local t = playerByOnlineId(args and args.id)
    if t == nil or not t:getModData().drp_downed then return end

    knock.getup(t)
    sendServerCommand(t, "DRPKnock", "forcegetup", {})
end

function adm.playerList(player) end
function adm.state(player, args, admin, target) end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DRPAdmin" or player == nil then return end
    if command == "register" then return end
    if not DRP.isAdmin(player) then return end
    local h = adm[command]
    if h then h(player, args, player:getUsername(), args and args.target) end
end)