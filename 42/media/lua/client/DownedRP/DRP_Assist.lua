--
-- DownedRP - assisted walk (方案B).
--

DRP = DRP or {}

DRP.Assist = DRP.Assist or {}
local A = DRP.Assist

A._followTasks = A._followTasks or {}

--------------------------------------------------------------------------------
-- Client-side follow logic
--------------------------------------------------------------------------------

if isClient() then
    local function isAssisted(player)
        local md = player and player:getModData()
        return md and md.drp_assisted == true
    end

    local function getAssister(player)
        local md = player and player:getModData()
        if not md or not md.drp_assisterId then return nil end
        return getPlayerByOnlineID(md.drp_assisterId)
    end

    local function stopAssist(player)
        local md = player and player:getModData()
        if not md then return end
        md.drp_assisted = false
        md.drp_assisterId = nil
        if player and player.setSpeedMod then player:setSpeedMod(1.0) end
        local task = A._followTasks[player]
        if task then
            if ISTimedActionQueue and ISTimedActionQueue.remove then
                ISTimedActionQueue.remove(task)
            elseif task.stop then
                task:stop()
            end
            A._followTasks[player] = nil
        end
    end

    -- Periodic check
    local _assistTickAccumulator = 0
    local function onAssistTick()
        _assistTickAccumulator = _assistTickAccumulator + 1
        if _assistTickAccumulator < 10 then return end
        _assistTickAccumulator = 0

        local me = getPlayer()
        if me == nil then return end
        if not isAssisted(me) then return end

        local assister = getAssister(me)
        if assister == nil then
            stopAssist(me)
            sendClientCommand(me, "DRPKnock", "assiststop", {})
            return
        end

        local dist = math.sqrt((me:getX() - assister:getX())^2 + (me:getY() - assister:getY())^2)
        local breakDist = (DRP.Config and DRP.Config.assistBreakDistance) or 5
        local followDist = (DRP.Config and DRP.Config.assistFollowDistance) or 2

        if dist > breakDist then
            stopAssist(me)
            sendClientCommand(me, "DRPKnock", "assiststop", {})
            return
        end

        local mod = ((DRP.Config and DRP.Config.assistSpeedModifier) or 60) / 100.0
        if me.setSpeedMod then me:setSpeedMod(mod) end
        if assister.setSpeedMod then assister:setSpeedMod(mod) end

        if dist > followDist then
            if A._followTasks[me] == nil or not A._followTasks[me]:isValid() then
                if DRPAssistFollow then
                    local action = DRPAssistFollow:new(me, assister)
                    if ISTimedActionQueue and ISTimedActionQueue.add then
                        ISTimedActionQueue.add(action)
                    end
                    A._followTasks[me] = action
                end
            end
        else
            if A._followTasks[me] then
                if ISTimedActionQueue and ISTimedActionQueue.remove then
                    ISTimedActionQueue.remove(A._followTasks[me])
                end
                A._followTasks[me] = nil
            end
        end
    end
    if Events.OnTick then Events.OnTick.Add(onAssistTick) end

    -- Context menu: Release Assist
    local function onFillAssistContext(playerIndex, context, worldObjects)
        local player = getSpecificPlayer(playerIndex)
        if player == nil then return end
        if not isAssisted(player) then return end
        context:addOption(getText("IGUI_DRP_ReleaseAssist"), player, function(p)
            stopAssist(p)
            sendClientCommand(p, "DRPKnock", "assiststop", {})
        end)
    end
    if Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(onFillAssistContext)
    end

    -- Clean up on death
    local function onPlayerDeathCleanup(player)
        if player ~= getPlayer() then return end
        stopAssist(player)
    end
    if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeathCleanup) end

    local function onCreatePlayerReset(idx, player)
        player = player or getSpecificPlayer(idx)
        if player == nil or not player:isLocalPlayer() then return end
        local md = player:getModData()
        md.drp_assisted = false
        md.drp_assisterId = nil
    end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayerReset) end
end

--------------------------------------------------------------------------------
-- Follow timed action (client only)
--------------------------------------------------------------------------------

if isClient() then
    require "TimedActions/ISBaseTimedAction"

    DRPAssistFollow = ISBaseTimedAction:derive("DRPAssistFollow")

    function DRPAssistFollow:isValid()
        local me = self.character
        local assister = self.assister
        if me == nil or assister == nil then return false end
        local md = me:getModData()
        if not md.drp_assisted then return false end
        if md.drp_assisterId ~= assister:getOnlineID() then return false end
        if assister:isDead() then return false end
        return true
    end

    function DRPAssistFollow:waitToStart()
        return false
    end

    function DRPAssistFollow:update()
        local me = self.character
        local assister = self.assister
        if me == nil or assister == nil then return end
        local mod = ((DRP.Config and DRP.Config.assistSpeedModifier) or 60) / 100.0
        if me.setSpeedMod then me:setSpeedMod(mod) end
        if assister.setSpeedMod then assister:setSpeedMod(mod) end
        me:getPathFindBehavior2():pathToLocation(assister:getX(), assister:getY(), assister:getZ())
    end

    function DRPAssistFollow:start()
        self:setActionAnim("Walk")
    end

    function DRPAssistFollow:stop()
        ISBaseTimedAction.stop(self)
    end

    function DRPAssistFollow:perform()
        ISBaseTimedAction.perform(self)
    end

    function DRPAssistFollow:new(character, assister)
        local o = ISBaseTimedAction.new(self, character)
        o.assister = assister
        o.maxTime = -1
        o.stopOnWalk = false
        o.stopOnRun = false
        return o
    end
end

--------------------------------------------------------------------------------
-- Server-side: re-assert assist state on tick
--------------------------------------------------------------------------------

if isServer() then
    local function onAssistServerTick()
        local players = getOnlinePlayers()
        if players == nil then return end
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local md = p and p:getModData()
            if md and md.drp_assisted then
                local assisterId = md.drp_assisterId
                if assisterId then
                    local assister = getPlayerByOnlineID(assisterId)
                    if assister == nil or assister:isDead() then
                        md.drp_assisted = false
                        md.drp_assisterId = nil
                        if p.setSpeedMod then p:setSpeedMod(1.0) end
                    else
                        local dist = math.sqrt((p:getX() - assister:getX())^2 + (p:getY() - assister:getY())^2)
                        local breakDist = (DRP.Config and DRP.Config.assistBreakDistance) or 5
                        if dist > breakDist then
                            md.drp_assisted = false
                            md.drp_assisterId = nil
                            if p.setSpeedMod then p:setSpeedMod(1.0) end
                            if assister.setSpeedMod then assister:setSpeedMod(1.0) end
                            sendServerCommand(p, "DRPKnock", "assiststop", {})
                            sendServerCommand(assister, "DRPKnock", "assiststop", {})
                        else
                            local mod = ((DRP.Config and DRP.Config.assistSpeedModifier) or 60) / 100.0
                            if p.setSpeedMod then p:setSpeedMod(mod) end
                            if assister.setSpeedMod then assister:setSpeedMod(mod) end
                        end
                    end
                end
            end
        end
    end
    if Events.OnTick then Events.OnTick.Add(onAssistServerTick) end

    local function onServerCharDeath(character)
        if not (character and instanceof(character, "IsoPlayer")) then return end
        if character:isAnimal() then return end
        local md = character:getModData()
        if md.drp_assisted then
            local assisterId = md.drp_assisterId
            md.drp_assisted = false
            md.drp_assisterId = nil
            if character.setSpeedMod then character:setSpeedMod(1.0) end
            if assisterId then
                local assister = getPlayerByOnlineID(assisterId)
                if assister then
                    if assister.setSpeedMod then assister:setSpeedMod(1.0) end
                    sendServerCommand(assister, "DRPKnock", "assiststop", {})
                end
            end
            sendServerCommand(character, "DRPKnock", "assiststop", {})
        end
    end
    if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(onServerCharDeath) end
end