--
-- DownedRP - client knockdown state machine.
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--

DRP = DRP or {}

DRP.Knockdown = DRP.Knockdown or {}
local K = DRP.Knockdown

K._localHolding      = K._localHolding or false
K._awaitingEnter     = K._awaitingEnter or false
K._dyingForReal      = K._dyingForReal or false
K._reviverName       = K._reviverName or nil
K._dragDeath         = K._dragDeath or false
K._realKillAt        = K._realKillAt or nil
K._deathWatchAt      = K._deathWatchAt or nil
K._triggerGrace      = K._triggerGrace or 0
K._awaitEnterUntil   = K._awaitEnterUntil or 0
K._downSet           = K._downSet or {}
K._panel             = K._panel or nil
K._wasDowned         = K._wasDowned or false

local cfg = DRP.cfg

local TRIGGER_GRACE_MS         = 3000
local ENTER_VERDICT_TIMEOUT_MS = 5000
local REAL_KILL_DELAY_MS       = 1000
local FALL_TIMEOUT_MS          = 1500

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function setMovementLocked(player, locked)
    if player == nil then return end
    if player.setBlockMovement  then player:setBlockMovement(locked) end
    if player.setIgnoreMovement then player:setIgnoreMovement(locked) end
end
DRP.Knockdown.setMovementLocked = setMovementLocked

local function setUntargetable(player, down)
    if player == nil then return end
    local C = cfg()
    if player.setShootable then
        player:setShootable((not down) or C.downedPlayerKill == true)
    end
    if player.setZombiesDontAttack then
        player:setZombiesDontAttack(down and C.downedZombieKill ~= true)
    end
end

local function applyCrawlSpeed(player)
    if player == nil then return end
    local pct = cfg().knockdownCrawlSpeedPct or 30
    pct = tonumber(pct) or 30
    if pct < 1 then pct = 1 elseif pct > 100 then pct = 100 end
    if player.setSpeedMod then player:setSpeedMod(pct / 100.0) end
end
DRP.Knockdown.applyCrawlSpeed = applyCrawlSpeed

local function restoreNormalSpeed(player)
    if player == nil then return end
    if player.setSpeedMod then player:setSpeedMod(1.0) end
end
DRP.Knockdown.restoreNormalSpeed = restoreNormalSpeed

local function forceDie(player)
    if player == nil or player.die == nil then return false end
    player:die()
    return true
end
DRP.Knockdown.forceDie = forceDie

local function isDragDown(player)
    if player == nil then return false end
    return player:isDeathDragDown() or player:getHitReaction() == "EndDeath"
end
DRP.Knockdown.isDragDown = isDragDown

local function markDragDeath(player)
    if K._dragDeath then return end
    K._dragDeath = true
    if isClient() and player ~= nil then
        sendClientCommand(player, "DRPKnock", "realdeath", {})
    end
end
DRP.Knockdown.markDragDeath = markDragDeath

local function clearDeathResidue(player, keepOnFloor)
    if player == nil then return end
    if player.setHitReaction       then player:setHitReaction("") end
    if player.setDeathDragDown     then player:setDeathDragDown(false) end
    if player.setPlayingDeathSound then player:setPlayingDeathSound(false) end
    if not keepOnFloor and player.setOnFloor then player:setOnFloor(false) end
    if player.setOnKillDone        then player:setOnKillDone(false) end
    if player.setOnDeathDone       then player:setOnDeathDone(false) end
    if player.setReanimateTimer    then player:setReanimateTimer(0) end
end
DRP.Knockdown.clearDeathResidue = clearDeathResidue

--------------------------------------------------------------------------------
-- Enter downed state
--------------------------------------------------------------------------------

function K.enter(player)
    if player == nil then return end
    local md = player:getModData()
    if md.drp_downed or player:isDead() then return end
    if DRP.nowMs() < (K._triggerGrace or 0) then return end
    if isDragDown(player) then markDragDeath(player); return end
    if K._awaitingEnter then
        if DRP.nowMs() < (K._awaitEnterUntil or 0) then return end
        K._awaitingEnter = false
    end
    DRP.DeathWounds.capture(player)
    clearDeathResidue(player, true)
    DRP.enterDownedHealth(player)
    K._awaitingEnter = true
    K._awaitEnterUntil = DRP.nowMs() + ENTER_VERDICT_TIMEOUT_MS
    if isClient() then
        sendClientCommand(player, "DRPKnock", "requestdown", {})
    else
        K._awaitingEnter = false
        K.enterConfirmed(player)
    end
end

local function snapshotTreatedParts(player, md)
    md.drp_preTreated = {}
    if not md.drp_noSelfTreat then return end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return end
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local bp = parts:get(i)
        if bp ~= nil then
            md.drp_preTreated[i] = {
                bandaged = bp:bandaged(),
                stitched = bp:stitched(),
                splint   = bp:isSplint(),
                bullet   = bp:haveBullet(),
                glass    = bp:haveGlass(),
            }
        end
    end
end

local function enterDownedState(player, startMs)
    if player == nil then return end
    local md = player:getModData()
    md.drp_downed = true
    md.drp_downedStart = startMs
    md.drp_fallStart = nil
    md.drp_noSelfTreat = not DRP.selfTreatAllowed(player)
    K._localHolding = true

    snapshotTreatedParts(player, md)

    clearDeathResidue(player, true)
    player:setVariable("knockedd_getup", false)
    player:setVariable("knockedd", false)
    player:setVariable("knockedd_fall", true)

    if player.setPrimaryHandItem    then player:setPrimaryHandItem(nil) end
    if player.setSecondaryHandItem  then player:setSecondaryHandItem(nil) end
    if player.setIsAiming           then player:setIsAiming(false) end
    if player.setBannedAttacking    then player:setBannedAttacking(true) end
    setMovementLocked(player, true)
    if player.setRunning  then player:setRunning(false) end
    if player.setSprinting then player:setSprinting(false) end
    setUntargetable(player, true)

    applyCrawlSpeed(player)
    K._wasDowned = true

    DRP.enterDownedHealth(player)
    if ISTimedActionQueue ~= nil then ISTimedActionQueue.clear(player) end
    if DRP.Knockdown.uiShow then DRP.Knockdown.uiShow() end
end

function K.enterConfirmed(player, strike, limit)
    if player == nil then return end
    local md = player:getModData()
    if md.drp_downed or player:isDead() then return end
    enterDownedState(player, DRP.nowMs())
    md.drp_strike = strike
    md.drp_strikeLimit = limit
end

--------------------------------------------------------------------------------
-- Get up
--------------------------------------------------------------------------------

function K.getUp(player)
    if player == nil then return end
    local md = player:getModData()
    if not md.drp_downed then return end
    md.drp_downed = false
    md.drp_downedStart = nil
    md.drp_fallStart = nil
    md.drp_noSelfTreat = nil
    md.drp_preTreated = nil
    K._localHolding = false
    K._reviverName = nil
    DRP.DeathWounds.clear()
    clearDeathResidue(player)
    player:setVariable("knockedd_fall", false)
    player:setVariable("knockedd_getup", true)
    player:setVariable("knockedd", false)

    DRP.releaseHealth(player)
    if player.setBannedAttacking then player:setBannedAttacking(false) end
    setMovementLocked(player, false)
    setUntargetable(player, false)

    if not md.drp_assisted then restoreNormalSpeed(player) end
    K._wasDowned = false

    local hp = cfg().knockdownReviveHp or 30
    DRP.stopBleeding(player)
    DRP.setGeneralHealth(player, hp)
    player:setHealth(hp)

    K._triggerGrace = DRP.nowMs() + TRIGGER_GRACE_MS

    if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end
    if isClient() then
        sendClientCommand(player, "DRPKnock", "getup", {})
    end
end

--------------------------------------------------------------------------------
-- Final kill
--------------------------------------------------------------------------------

function K.finalKill(player)
    if player == nil then return end
    K._dyingForReal = true

    if isClient() then
        sendClientCommand(player, "DRPKnock", "realdeath", {})
    end
    K._localHolding = false
    K._reviverName = nil
    K._awaitingEnter = false
    K._realKillAt = nil

    local md = player:getModData()
    md.drp_downed = false
    md.drp_downedStart = nil
    md.drp_fallStart = nil
    md.drp_noSelfTreat = nil
    md.drp_preTreated = nil

    player:setVariable("knockedd", false)
    player:setVariable("knockedd_fall", false)
    player:setVariable("knockedd_getup", false)

    if DRP.DeathWounds.isEmpty(DRP.DeathWounds._captured) then
        DRP.DeathWounds.capture(player)
    end

    clearDeathResidue(player)
    DRP.releaseHealth(player)
    if player.setGodMod          then player:setGodMod(false) end
    if player.setBannedAttacking then player:setBannedAttacking(false) end
    setMovementLocked(player, false)
    if not md.drp_assisted then restoreNormalSpeed(player) end
    K._wasDowned = false
    setUntargetable(player, false)
    if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end

    DRP.setGeneralHealth(player, 0)
    player:setHealth(0)

    if isClient() then
        sendClientCommand(player, "DRPKnock", "forcedeath", {})
    end

    K._deathWatchAt = DRP.nowMs()
end

function K.deathWatchdog(player)
    if player == nil then return end
    local at = K._deathWatchAt
    if at == nil then return end
    if player:isOnDeathDone() then
        K._deathWatchAt = nil
        return
    end
    if not player:isDead() then
        DRP.releaseHealth(player)
        if player.setGodMod then player:setGodMod(false) end
        DRP.setGeneralHealth(player, 0)
        player:setHealth(0)
    end

    local since = DRP.nowMs() - at

    if since >= 1200 and player.setOnFloor and not player:isOnFloor() then
        player:setOnFloor(true)
    end
    if since >= 2200 then
        K._deathWatchAt = nil
        forceDie(player)
    end
end

function K.realDeath(player)
    if player == nil then return end
    K._dyingForReal = true

    if isClient() then sendClientCommand(player, "DRPKnock", "realdeath", {}) end
    local md = player:getModData()
    md.drp_downed = false
    md.drp_downedStart = nil
    md.drp_fallStart = nil
    md.drp_noSelfTreat = nil
    md.drp_preTreated = nil
    K._localHolding = false
    player:setVariable("knockedd", false)
    player:setVariable("knockedd_fall", false)
    player:setVariable("knockedd_getup", false)
    setMovementLocked(player, false)
    if not md.drp_assisted then restoreNormalSpeed(player) end
    K._wasDowned = false
    setUntargetable(player, false)
    if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end
    if isClient() then
        sendClientCommand(player, "DRPKnock", "getup", {})
    end
    if player.setInvincible then player:setInvincible(true) end
    K._realKillAt = DRP.nowMs() + REAL_KILL_DELAY_MS
end

function K.resume(player, start)
    enterDownedState(player, start)
    if isClient() then
        sendClientCommand(player, "DRPKnock", "resumed", {})
    end
end

--------------------------------------------------------------------------------
-- Self get-up
--------------------------------------------------------------------------------

function K.selfGetUp(player)
    if player == nil then return end
    local md = player:getModData()
    if not md.drp_downed then return end
    if not DRP.canStandUp(player) then
        local suffix = DRP.standUpBlockReason(player) or "Unknown"
        local reason = getText("IGUI_DRP_Reason" .. suffix)
        local p = getPlayer()
        if p and HaloTextHelper and HaloTextHelper.addText then
            HaloTextHelper.addText(p, getText("IGUI_DRP_CannotStandUp") .. " (" .. reason .. ")")
        end
        return
    end
    K.getUp(player)
end

--------------------------------------------------------------------------------
-- Downed-state helpers, split out of onPlayerUpdate so no single function
-- accumulates enough locals to trip LuaJ's 200-slot limit.
--------------------------------------------------------------------------------

local function updateSpeedState(player, md)
    local isDownedNow = md.drp_downed == true
    if isDownedNow ~= K._wasDowned then
        if isDownedNow then
            applyCrawlSpeed(player)
        else
            if not md.drp_assisted then restoreNormalSpeed(player) end
        end
        K._wasDowned = isDownedNow
    end
end

local function handleFallPose(player, md)
    if player:getVariableBoolean("knockedd_fall") then
        if not md.drp_fallStart then
            md.drp_fallStart = DRP.nowMs()
        elseif DRP.nowMs() - md.drp_fallStart > FALL_TIMEOUT_MS then
            player:setVariable("knockedd_fall", false)
            player:setVariable("knockedd", true)
            md.drp_fallStart = nil
        end
    else
        md.drp_fallStart = nil
    end
end

local function undoForbiddenTreatment(player, md)
    if not md.drp_noSelfTreat then return end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return end
    local pre = md.drp_preTreated or {}
    local undone = false
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local bp = parts:get(i)
        if bp ~= nil then
            local s = pre[i] or {}
            if bp:bandaged() and not s.bandaged then
                bp:setBandaged(false, false); undone = true
            end
            if bp:stitched() and not s.stitched then
                bp:setStitched(false); undone = true
            end
            if bp:isSplint() and not s.splint then
                bp:setSplint(false, 0); undone = true
            end
            if bp:haveBullet() and not s.bullet then
                bp:setHaveBullet(false, 0); undone = true
            end
            if bp:haveGlass() and not s.glass then
                bp:setHaveGlass(false); undone = true
            end
        end
    end
    if undone and DRP.notifySelfTreatBlocked then
        DRP.notifySelfTreatBlocked(player)
    end
end

local function handleDownedMovement(player, C)
    local isFalling = player:getVariableBoolean("knockedd_fall")
    local isGetup   = player:getVariableBoolean("knockedd_getup")
    local canMove   = (C.moveWhileDowned ~= false) and (not isFalling) and (not isGetup)
    if canMove then
        if player.setBlockMovement  then player:setBlockMovement(false) end
        if player.setIgnoreMovement then player:setIgnoreMovement(false) end
        if player.setOnFloor and player:isOnFloor() then
            player:setOnFloor(false)
        end
        if not player:getVariableBoolean("knockedd") then
            player:setVariable("knockedd", true)
        end
        applyCrawlSpeed(player)
    else
        if player.setBlockMovement  then player:setBlockMovement(true) end
        if player.setIgnoreMovement then player:setIgnoreMovement(true) end
    end
end

local function checkBleedout(player, md, C)
    if DRP.nowMs() < (K._triggerGrace or 0) then return end
    local start = md.drp_downedStart or DRP.nowMs()
    local dur = (C.bleedoutTimer ~= false) and (C.knockdownDurationSec or 300) * 1000 or 0
    if dur > 0 and (DRP.nowMs() - start) >= dur then
        K.realDeath(player)
        return
    end
    local crawled = DRP.Crawl.track(player, start)
    if not DRP.tickDownedHealth(player, start, crawled) then
        K.realDeath(player)
        return
    end
    local dur2 = (C.bleedoutTimer ~= false) and (C.knockdownDurationSec or 300) * 1000 or 0
    if dur2 > 0 and md.drp_downedStart and (DRP.nowMs() - md.drp_downedStart) >= dur2 then
        K.realDeath(player)
    end
end

--------------------------------------------------------------------------------
-- OnPlayerUpdate
--------------------------------------------------------------------------------

function K.onPlayerUpdate(player)
    if player == nil or player ~= getPlayer() then return end
    if K._deathWatchAt then K.deathWatchdog(player) end
    if K._realKillAt then
        if DRP.nowMs() >= K._realKillAt then K.finalKill(player) end
        return
    end
    if player:isDead() then
        if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end
        return
    end

    local C = cfg()
    if C.knockdownEnable == false then return end

    if K._dyingForReal and not player:isDead() then
        K._dyingForReal = false
    end
    if K._dyingForReal then return end

    local md = player:getModData()

    updateSpeedState(player, md)

    if md.drp_downed then
        handleFallPose(player, md)
        if DRP.nowMs() < (K._triggerGrace or 0) then return end
        checkBleedout(player, md, C)
        undoForbiddenTreatment(player, md)
        if player:isOnKillDone() or player:isOnDeathDone()
           or player:isDeathDragDown()
           or (player:getHitReaction() == "EndDeath") then
            clearDeathResidue(player, true)
        end
        if player:isSneaking()  and player.setSneaking  then player:setSneaking(false) end
        if player:isRunning()   and player.setRunning   then player:setRunning(false) end
        if player:isSprinting() and player.setSprinting then player:setSprinting(false) end
        handleDownedMovement(player, C)
        return
    end

    -- Not downed -------------------------------------------------------------
    if K._awaitingEnter then
        if DRP.nowMs() < (K._awaitEnterUntil or 0) then
            clearDeathResidue(player, true)
            DRP.enterDownedHealth(player)
            return
        end
        K._awaitingEnter = false
        if player.setInvincible then player:setInvincible(false) end
    end

    if isDragDown(player) then
        markDragDeath(player)
        return
    end

    if DRP.nowMs() < (K._triggerGrace or 0) then return end

    if C.knockdownAutoTrigger ~= false then
        local hp = player:getBodyDamage():getOverallBodyHealth()
        if hp < (C.knockdownThreshold or 10) and not player:isDead() then
            K.enter(player)
        end
    end
end
if Events.OnPlayerUpdate then Events.OnPlayerUpdate.Add(K.onPlayerUpdate) end

--------------------------------------------------------------------------------
-- OnPlayerGetDamage
--------------------------------------------------------------------------------

local function onPlayerGetDamage(player)
    local p = getPlayer()
    if p == nil or (player ~= nil and player ~= p) then return end
    local C = cfg()
    if C.knockdownEnable == false then return end
    local md = p:getModData()
    if md.drp_downed and not K._dyingForReal then
        DRP.tickDownedHealth(p, md.drp_downedStart, DRP.Crawl.track(p, md.drp_downedStart))
    end
end
if Events.OnPlayerGetDamage then Events.OnPlayerGetDamage.Add(onPlayerGetDamage) end

--------------------------------------------------------------------------------
-- OnWeaponHitCharacter
--------------------------------------------------------------------------------

local function onWeaponHit(attacker, victim)
    local p = getPlayer()
    if p == nil or victim ~= p or attacker == nil or attacker == p then return end
    if K._dyingForReal or K._realKillAt then return end
    local C = cfg()
    if C.knockdownEnable == false then return end
    if not p:getModData().drp_downed then return end

    if attacker:isZombie() then
        if C.downedZombieKill ~= true then return end
    elseif instanceof(attacker, "IsoPlayer") and not attacker:isAnimal() then
        if C.downedPlayerKill ~= true then return end
    else
        return
    end
    K.realDeath(p)
end
if Events.OnWeaponHitCharacter then Events.OnWeaponHitCharacter.Add(onWeaponHit) end

--------------------------------------------------------------------------------
-- OnCreatePlayer
--------------------------------------------------------------------------------

local function onCreatePlayer(idx, player)
    player = player or getSpecificPlayer(idx)
    if player == nil or not player:isLocalPlayer() then return end
    K._localHolding = false
    K._awaitingEnter = false
    K._dyingForReal = false
    K._reviverName = nil
    K._dragDeath = false
    K._realKillAt = nil
    K._deathWatchAt = nil
    K._triggerGrace = DRP.nowMs() + TRIGGER_GRACE_MS
    K._wasDowned = false

    clearDeathResidue(player)
    DRP.releaseHealth(player)
    if player.setBannedAttacking then player:setBannedAttacking(false) end
    setMovementLocked(player, false)
    restoreNormalSpeed(player)
    player:setVariable("knockedd", false)
    player:setVariable("knockedd_fall", false)
    player:setVariable("knockedd_getup", false)
    setUntargetable(player, false)
    if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end
end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end

--------------------------------------------------------------------------------
-- OnPlayerDeath
--------------------------------------------------------------------------------

local function onLocalDeath(player)
    if player ~= getPlayer() then return end
    local md = player:getModData()
    md.drp_downed = false
    md.drp_downedStart = nil
    md.drp_fallStart = nil
    md.drp_noSelfTreat = nil
    md.drp_preTreated = nil
    K._localHolding = false
    K._awaitingEnter = false
    K._reviverName = nil
    K._wasDowned = false
    if not md.drp_assisted then restoreNormalSpeed(player) end
    if DRP.Knockdown.uiHide then DRP.Knockdown.uiHide() end
end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onLocalDeath) end

--------------------------------------------------------------------------------
-- Debug context menu
--------------------------------------------------------------------------------

local function onFillDebugContext(playerIndex, context, worldObjects)
    if cfg().knockdownDebugMenu == false then return end
    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end
    if not (DRP.isAdmin(player) or (isDebugEnabled and isDebugEnabled())) then return end
    if player:getModData().drp_downed then
        context:addOption("Get up (DEBUG)", player, function(p) K.getUp(p) end)
        if DRPTestRevive then
            context:addOption("Get up - slow/revive timer (DEBUG)", player,
                function(p) ISTimedActionQueue.add(DRPTestRevive:new(p)) end)
        end
    else
        context:addOption("Knock down (DEBUG)", player, function(p) K.enter(p) end)
    end
end
if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(onFillDebugContext) end

--------------------------------------------------------------------------------
-- Server commands
--------------------------------------------------------------------------------

local function onServerCommand(module, command, args)
    if module ~= "DRPKnock" then return end
    if command == "setstate" and args and args.id then
        local p = getPlayerByOnlineID(args.id)
        if p and p ~= getPlayer() then
            p:getModData().drp_remoteState = args.state
        end
        if K._downSet == nil then K._downSet = {} end
        if args.state == "down" then K._downSet[args.id] = true
        elseif args.state == "up" then K._downSet[args.id] = nil end
    elseif command == "downset" and args then
        local set = {}
        for _, id in ipairs(args.ids or {}) do set[id] = true end
        K._downSet = set
    elseif command == "revivenotice" and args then
        K._reviverName = (args.active and args.name) or nil
    elseif command == "forcedown" then
        local me = getPlayer()
        if me and not me:getModData().drp_downed then
            K._triggerGrace = nil
            K.enterConfirmed(me, 0, 0)
        end
    elseif command == "forcegetup" then
        K._reviverName = nil
        local me = getPlayer()
        if me and me:getModData().drp_downed then K.getUp(me) end
    elseif command == "downverdict" and args then
        K._awaitingEnter = false
        local player = getPlayer()
        if player == nil or player:isDead() then return end
        if args.ok then
            K.enterConfirmed(player, args.strike, args.limit)
        else
            K.finalKill(player)
        end
    elseif command == "assiststart" and args then
        local me = getPlayer()
        if me and (args.assisterId or args.targetId) then
            local md = me:getModData()
            md.drp_assisted = true
            md.drp_assisterId = args.assisterId or args.targetId
            local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
            if me.setSpeedMod then me:setSpeedMod(mod) end
        end
    elseif command == "assiststop" then
        local me = getPlayer()
        if me then
            local md = me:getModData()
            md.drp_assisted = false
            md.drp_assisterId = nil
            if me.setSpeedMod then me:setSpeedMod(1.0) end
        end
    end
end
if Events.OnServerCommand then Events.OnServerCommand.Add(onServerCommand) end

--------------------------------------------------------------------------------
-- OnTick - sync remote downed players
--------------------------------------------------------------------------------

local function onTickSync()
    local me = getPlayer()
    if me == nil then return end
    local players = getOnlinePlayers()
    if players == nil then return end
    local downSet = K._downSet
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p ~= me then
            local md = p:getModData()
            local down
            if downSet ~= nil then
                down = (downSet[p:getOnlineID()] == true)
                md.drp_downed = down
            else
                down = (md.drp_downed == true) or (md.drp_remoteState == "down")
                if md.drp_remoteState == "up" then down = false end
            end
            local showing = p:getVariableBoolean("knockedd") or p:getVariableBoolean("knockedd_fall")
            if down and not showing then
                p:setVariable("knockedd_fall", true)
                if p.setShootable then p:setShootable(false) end
            elseif (not down) and showing and not p:getVariableBoolean("knockedd_getup") then
                p:setVariable("knockedd_getup", true)
                if p.setShootable then p:setShootable(true) end
                md.drp_downed = false
                md.drp_remoteState = nil
            end
        end
    end
end
if isClient() and Events.OnTick then Events.OnTick.Add(onTickSync) end

--------------------------------------------------------------------------------
-- UI Panel fallback
--------------------------------------------------------------------------------

if ISPanel ~= nil and K.uiShow == nil then
    local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BAR_HGT = 14

    local DBNOKnockPanel = ISPanel:derive("DBNOKnockPanel")

    local function timerShown()
        return DRP.Config.bleedoutTimer ~= false
    end

    local function remaining()
        local p = getPlayer()
        local md = p and p:getModData()
        local dur = (DRP.Config.bleedoutTimer ~= false)
            and ((DRP.Config.knockdownDurationSec) or 300) * 1000 or 0
        if md == nil or md.drp_downedStart == nil or dur <= 0 then return 0, 0 end
        local left = dur - (DRP.nowMs() - md.drp_downedStart)
        if left < 0 then left = 0 end
        return left / dur, left
    end

    function DBNOKnockPanel:render()
        local BHC = getCore():getBadHighlitedColor()
        local y = UI_BORDER_SPACING

        self:drawTextCentre(getText("IGUI_DRP_YouAreDown"), self.width / 2, y,
            BHC:getR(), BHC:getG(), BHC:getB(), 1, UIFont.Medium)
        y = y + FONT_HGT_MEDIUM + UI_BORDER_SPACING

        if timerShown() then
            local frac, left = remaining()
            local barX, barW = UI_BORDER_SPACING, self.width - UI_BORDER_SPACING * 2
            self:drawRect(barX, y, barW, BAR_HGT, 0.6, 0.0, 0.0, 0.0)
            self:drawRect(barX, y, barW * frac, BAR_HGT, 0.9, 0.65 - 0.35 * frac, 0.12 + 0.30 * frac, 0.10)
            self:drawRectBorder(barX, y, barW, BAR_HGT, 0.5, 0.4, 0.4, 0.4)
            y = y + BAR_HGT + 4

            local secs = math.floor(left / 1000)
            self:drawTextCentre(string.format("%d:%02d", math.floor(secs / 60), secs % 60),
                self.width / 2, y, 1, 1, 1, 1, UIFont.Small)
            y = y + FONT_HGT_SMALL + UI_BORDER_SPACING
        end

        local rn = DRP.Knockdown._reviverName
        local p = getPlayer()
        local md = p and p:getModData()
        if rn then
            self:drawTextCentre(getText("IGUI_DRP_PickingYouUp", tostring(rn)),
                self.width / 2, y, 0.40, 0.90, 0.45, 1, UIFont.Small)
        elseif md and type(md.drp_strike) == "number" and type(md.drp_strikeLimit) == "number"
               and md.drp_strike >= md.drp_strikeLimit then
            self:drawTextCentre(getText("IGUI_DRP_LastChance"),
                self.width / 2, y, 1.0, 0.55, 0.12, 1, UIFont.Small)
        end
    end

    function K.uiShow()
        if K._panel == nil then
            K._panel = DBNOKnockPanel:new()
            K._panel:initialise()
            K._panel:instantiate()
            K._panel:addToUIManager()
        end
        K._panel:setVisible(true)
    end

    function K.uiHide()
        if K._panel then
            K._panel:setVisible(false)
            K._panel:removeFromUIManager()
            K._panel = nil
        end
    end
end

--------------------------------------------------------------------------------
-- ISTimedActionQueue hook
--------------------------------------------------------------------------------

if ISTimedActionQueue ~= nil then
    local _origAdd = ISTimedActionQueue.add
    ISTimedActionQueue.add = function(action)
        local p = getPlayer()
        if p ~= nil then
            local md = p:getModData()
            if md and md.drp_downed and not (action and action.dbnoBypassLockout) then
                if DRP.isMovementAction and DRP.isMovementAction(action) then
                    return _origAdd(action)
                end
                local isUI  = DRP.isUIAction and DRP.isUIAction(action)
                local isMed = DRP.isMedicalAction(action)
                if isUI or isMed then
                    if DRP.selfTreatAllowed(p) then
                        return _origAdd(action)
                    end
                    if DRP.notifySelfTreatBlocked then
                        DRP.notifySelfTreatBlocked(p)
                    end
                    return
                end
                return
            end
        end
        return _origAdd(action)
    end
end

--------------------------------------------------------------------------------
-- Help Up timed action
--------------------------------------------------------------------------------

require "TimedActions/ISBaseTimedAction"
DRP.HelpUp = DRP.HelpUp or {}

local function isDown(p)
    return p ~= nil and (p:getModData().drp_downed == true
        or p:getVariableBoolean("knockedd") or p:getVariableBoolean("knockedd_fall"))
end

DRPHelpUp = ISBaseTimedAction:derive("DRPHelpUp")

function DRPHelpUp:isValid()
    return isDown(self.target)
end

function DRPHelpUp:waitToStart()
    self.character:faceThisObject(self.target)
    return self.character:shouldBeTurning()
end

function DRPHelpUp:update()
    self.character:faceThisObject(self.target)
end

function DRPHelpUp:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    sendClientCommand(self.character, "DRPKnock", "reviving", { targetId = self.target:getOnlineID() })
end

function DRPHelpUp:stop()
    if not self._done then
        sendClientCommand(self.character, "DRPKnock", "revivecancel", { targetId = self.target:getOnlineID() })
    end
    ISBaseTimedAction.stop(self)
end

function DRPHelpUp:perform()
    self._done = true
    sendClientCommand(self.character, "DRPKnock", "reviverequest", { targetId = self.target:getOnlineID() })
    ISBaseTimedAction.perform(self)
end

function DRPHelpUp:new(character, target)
    local o = ISBaseTimedAction.new(self, character)
    o.target = target
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = (DRP.Config.knockdownReviveTime) or 200
    if character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

DRPTestRevive = ISBaseTimedAction:derive("DRPTestRevive")
function DRPTestRevive:isValid() return self.character:getModData().drp_downed == true end
function DRPTestRevive:update() end
function DRPTestRevive:start()
    local nm = "Someone"
    local d = self.character:getDescriptor()
    if d and d.getForename then nm = d:getForename() or nm end
    DRP.Knockdown._reviverName = nm
end
function DRPTestRevive:stop()
    if not self._done then DRP.Knockdown._reviverName = nil end
    ISBaseTimedAction.stop(self)
end
function DRPTestRevive:perform()
    self._done = true
    DRP.Knockdown._reviverName = nil
    DRP.Knockdown.getUp(self.character)
    ISBaseTimedAction.perform(self)
end
function DRPTestRevive:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.maxTime = (DRP.Config.knockdownReviveTime) or 200
    o.forceProgressBar = true
    o.dbnoBypassLockout = true
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

local function onHelpUpSelect(worldobjects, player, target)
    if luautils.walkAdj(player, target:getCurrentSquare()) then
        ISTimedActionQueue.add(DRPHelpUp:new(player, target))
    end
end

local function onFillHelpUp(playerIndex, context, worldObjects)
    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end
    if player:getModData().drp_downed then return end

    local square
    for _, v in ipairs(worldObjects) do
        square = v:getSquare()
        if square then break end
    end
    if square == nil then return end

    local target
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if sq then
                local mos = sq:getMovingObjects()
                if mos then
                    for i = 0, mos:size() - 1 do
                        local o = mos:get(i)
                        if instanceof(o, "IsoPlayer") and not o:isAnimal()
                           and o ~= player and isDown(o) then
                            target = o
                        end
                    end
                end
            end
        end
    end
    if target == nil then return end

    context:addOption("Help Up " .. DRP.displayName(target), worldObjects, onHelpUpSelect, player, target)
end
if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(onFillHelpUp) end

--------------------------------------------------------------------------------
-- Self get-up context menu
--------------------------------------------------------------------------------

local function onFillSelfContext(playerIndex, context, worldObjects)
    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end
    local md = player:getModData()
    if not md.drp_downed then return end

    if DRP.canStandUp(player) then
        context:addOption(getText("IGUI_DRP_StandUp"), player,
            function(p) DRP.Knockdown.selfGetUp(p) end)
    else
        local suffix = DRP.standUpBlockReason(player) or "Unknown"
        local reason = getText("IGUI_DRP_Reason" .. suffix)
        local label  = getText("IGUI_DRP_StandUpBlocked", reason)
        context:addOption(label, player,
            function(p) DRP.Knockdown.selfGetUp(p) end)
    end
end
if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(onFillSelfContext) end