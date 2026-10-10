--
-- DownedRP - assisted walk (方案B).
--
-- After a teammate revives a downed player, the rescued player follows the
-- rescuer at reduced speed for both. The hold breaks if they get too far
-- apart, if the rescued player goes down again, or if either uses the
-- "Release Assist" context menu option.
--
-- No new animations are required. The assisted player simply walks normally
-- while pathfinding to the assister.
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
            if player then player:setSpeedMod(1.0) end
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

    -- Periodic check: distance, re-apply speed mod, pathfind to assister
        -- Run every 200ms instead of every frame for performance
        local _assistTickAccumulator = 0
        Events.OnTick.Add(function()
            _assistTickAccumulator = _assistTickAccumulator + 1
            if _assistTickAccumulator < 10 then return end  -- ~200ms at 50fps
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
            local breakDist = DRP.Config.assistBreakDistance or 5
            local followDist = DRP.Config.assistFollowDistance or 2

            if dist > breakDist then
                stopAssist(me)
                sendClientCommand(me, "DRPKnock", "assiststop", {})
                return
            end

            -- Re-apply speed modifier in case it was cleared
            local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
            me:setSpeedMod(mod)
            assister:setSpeedMod(mod)

            -- If far enough, pathfind to assister
            if dist > followDist then
                if A._followTasks[me] == nil or not A._followTasks[me]:isValid() then
                    local action = DRPAssistFollow:new(me, assister)
                    ISTimedActionQueue.add(action)
                    A._followTasks[me] = action
            end
            else
                -- Close enough, stop the follow action if running
                if A._followTasks[me] then
                    ISTimedActionQueue.remove(A._followTasks[me])
                    A._followTasks[me] = nil
                end
            end
        end)

    -- Context menu: Release Assist
    Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects)
        local player = getSpecificPlayer(playerIndex)
        if player == nil then return end
        if not isAssisted(player) then return end

        context:addOption(getText("IGUI_DRP_ReleaseAssist"), player, function(p)
            stopAssist(p)
            sendClientCommand(p, "DRPKnock", "assiststop", {})
        end)
    end)

    -- Clean up on death / disconnect
    Events.OnPlayerDeath.Add(function(player)
        if player ~= getPlayer() then return end
        stopAssist(player)
    end)

    Events.OnCreatePlayer.Add(function(idx, player)
        player = player or getSpecificPlayer(idx)
        if player == nil or not player:isLocalPlayer() then return end
        local md = player:getModData()
        md.drp_assisted = false
        md.drp_assisterId = nil
    end)
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

        -- Re-apply speed modifier
        local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
            me:setSpeedMod(mod)
            assister:setSpeedMod(mod)

        -- Pathfind to assister
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
        o.maxTime = -1  -- run until stopped
        o.stopOnWalk = false
        o.stopOnRun = false
        return o
    end
end

--------------------------------------------------------------------------------
-- Server-side: re-assert assist state on tick
--------------------------------------------------------------------------------

if isServer() then
    Events.OnTick.Add(function()
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
                        p:setSpeedMod(1.0)
                    else
                        local dist = math.sqrt((p:getX() - assister:getX())^2 + (p:getY() - assister:getY())^2)
                        local breakDist = DRP.Config.assistBreakDistance or 5
                        if dist > breakDist then
                            md.drp_assisted = false
                            md.drp_assisterId = nil
                            p:setSpeedMod(1.0)
                            assister:setSpeedMod(1.0)
                            sendServerCommand(p, "DRPKnock", "assiststop", {})
                            sendServerCommand(assister, "DRPKnock", "assiststop", {})
                        else
                            local mod = (DRP.Config.assistSpeedModifier or 60) / 100.0
                            p:setSpeedMod(mod)
                            assister:setSpeedMod(mod)
                        end
                    end
                end
            end
        end
    end)

    -- Clean up on death
    Events.OnCharacterDeath.Add(function(character)
        if not (character and instanceof(character, "IsoPlayer")) then return end
        if character:isAnimal() then return end
        local md = character:getModData()
        if md.drp_assisted then
            local assisterId = md.drp_assisterId
            md.drp_assisted = false
            md.drp_assisterId = nil
            character:setSpeedMod(1.0)
            if assisterId then
                local assister = getPlayerByOnlineID(assisterId)
                if assister then
                    assister:setSpeedMod(1.0)
                    sendServerCommand(assister, "DRPKnock", "assiststop", {})
                end
            end
            sendServerCommand(character, "DRPKnock", "assiststop", {})
        end
    end)
end