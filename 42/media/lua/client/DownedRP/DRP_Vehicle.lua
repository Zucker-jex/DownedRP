--
-- DownedRP - Vehicle enter/exit while downed (low priority, optional).
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--
-- Allows a downed player to enter a vehicle as a passenger (not driver).
-- When exiting, the player remains downed.
--

DRP = DRP or {}

DRP.Vehicle = DRP.Vehicle or {}

if isClient() then
    -- Hook ISVehicleMenu.onEnter to allow downed players as passengers
    local vanillaOnEnter = ISVehicleMenu.onEnter
    function ISVehicleMenu.onEnter(playerObj, vehicle, seat)
        local md = playerObj:getModData()
        if md.drp_downed then
            -- Only allow passenger seats
            if seat == 0 then return end  -- seat 0 is driver
            -- Let the vanilla code handle the rest
        end
        return vanillaOnEnter(playerObj, vehicle, seat)
    end

    -- Hook ISVehicleMenu.onExit to keep downed state
    local vanillaOnExit = ISVehicleMenu.onExit
    function ISVehicleMenu.onExit(playerObj)
        local md = playerObj:getModData()
        if md.drp_downed then
            -- Player stays downed after exiting
            -- The vanilla exit will handle the animation
        end
        return vanillaOnExit(playerObj)
    end

    -- Prevent driving while downed
    Events.OnPlayerUpdate.Add(function(player)
        if player ~= getPlayer() then return end
        local md = player:getModData()
        if md.drp_downed and player:getVehicle() then
            local seat = player:getVehicle():getSeat(player)
            if seat == 0 then
                -- Force exit driver seat
                player:getVehicle():exit(player)
            end
        end
    end)
end