--
-- DownedRP - Adrenaline item (low priority, optional).
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--
-- Item: Base.Adrenaline
-- When used while downed, immediately stands the player up (bypassing Help Up).
-- Can only be used once per knockdown episode.
-- After use, the player gets a short speed penalty.
--

DRP = DRP or {}

DRP.Adrenaline = DRP.Adrenaline or {}

if isClient() then
    -- Context menu: use adrenaline while downed
    Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, items)
        local player = getSpecificPlayer(playerIndex)
        if player == nil then return end
        local md = player:getModData()
        if not md.drp_downed then return end
        if md.drp_adrenaline_used then return end

        local adrenaline
        for i = 1, items:size() do
            local item = items:get(i-1)
            if item and item:getFullType() == "Base.Adrenaline" then
                adrenaline = item
                break
            end
        end
        if not adrenaline then return end

        context:addOption(getText("IGUI_DRP_UseAdrenaline"), player, function(p)
            ISTimedActionQueue.add(DRPUseAdrenaline:new(p, adrenaline))
        end)
    end)

    -- Timed action
    require "TimedActions/ISBaseTimedAction"

    DRPUseAdrenaline = ISBaseTimedAction:derive("DRPUseAdrenaline")

    function DRPUseAdrenaline:isValid()
        local md = self.character:getModData()
        return md.drp_downed == true and not md.drp_adrenaline_used
    end

    function DRPUseAdrenaline:update() end

    function DRPUseAdrenaline:start()
        self:setActionAnim("Eat")
        self.character:SetVariable("EatType", "Eat")
    end

    function DRPUseAdrenaline:perform()
        local md = self.character:getModData()
        md.drp_adrenaline_used = true
        self.item:Use()
        DRP.Knockdown.getUp(self.character)

        -- Short speed penalty after adrenaline wears off
                self.character:setSpeedMod(0.7)
        local function resetSpeed()
                    self.character:setSpeedMod(1.0)
        end
        -- Reset after 60 seconds
        local timer = 60000
        local function tick()
            timer = timer - 1000
            if timer <= 0 then
                resetSpeed()
                Events.OnTick.Remove(tick)
            end
        end
        Events.OnTick.Add(tick)

        ISBaseTimedAction.perform(self)
    end

    function DRPUseAdrenaline:new(character, item)
        local o = ISBaseTimedAction.new(self, character)
        o.item = item
        o.maxTime = 50
        o.dbnoBypassLockout = true
        return o
    end
end

-- Reset adrenaline flag when knockdown ends
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "DRPKnock" then return end
    if command == "getup" or command == "forcegetup" then
        local player = getPlayer()
        if player then
            player:getModData().drp_adrenaline_used = false
        end
    end
end)