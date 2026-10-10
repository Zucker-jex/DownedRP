--
-- DownedRP - UI (moodle + knockdown panel).
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--
-- Only the DBNOKnockPanel and the DBNOKnockdowns moodle were kept.
-- Wounds, LastLife, Respawn, Snapshot, Loot and Admin UI were dropped.
--

DRP = DRP or {}

local function notify(msg)
    local p = getPlayer()
    if p == nil then return end
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(p, msg)
    else
        p:Say(msg)
    end
end

--------------------------------------------------------------------------------
-- Moodle
--------------------------------------------------------------------------------

require "MF_ISMoodle"
if MF ~= nil and MF.createMoodle ~= nil then
    local function countToValue(n)
        if n == nil or n <= 0 then return 0.5 end
        if n == 1 then return 0.35 end
        if n == 2 then return 0.25 end
        if n == 3 then return 0.15 end
        return 0.05
    end

    MF.createMoodle("DRPKnockdowns")

    local function configMoodle(m)
        if m == nil then return end
        m:setThresholds(0.1, 0.2, 0.3, 0.4, nil, nil, nil, nil)
    end

    local _known = {}

    local function retire(m)
        if m ~= nil and m.addedToUIManager then
            m:removeFromUIManager()
            m.addedToUIManager = false
        end
    end

    local function isUsable(m, player)
        if m == nil or m.char ~= player or m.disable then return false end
        local md = player:getModData().Moodles
        return md ~= nil and md[m.name] ~= nil
    end

    local function ensureMoodles()
        local player = getSpecificPlayer(0)
        if player == nil then return false end
        local ok = true
        local m = MF.getMoodle("DRPKnockdowns", 0)
        if _known["DRPKnockdowns"] ~= nil and _known["DRPKnockdowns"] ~= m then
            retire(_known["DRPKnockdowns"])
            _known["DRPKnockdowns"] = nil
        end
        if not isUsable(m, player) then
            retire(m)
            MF.ISMoodle:new("DRPKnockdowns", player)
            m = MF.getMoodle("DRPKnockdowns", 0)
            if not isUsable(m, player) then ok = false end
        end
        if m ~= nil and _known["DRPKnockdowns"] ~= m then
            configMoodle(m)
            _known["DRPKnockdowns"] = m
        end
        return ok
    end

    local function applyStatus(k)
        if not ensureMoodles() then return end
        local mk = MF.getMoodle("DRPKnockdowns", 0)
        if mk then mk:setValue(countToValue(k)) end

        DRP.Wounds = DRP.Wounds or {}
        DRP.Wounds.strikes = tonumber(k) or DRP.Wounds.strikes
    end

    local _lastReq = 0
    Events.OnTick.Add(function()
        local p = getPlayer()
        if p == nil then return end
        if not ensureMoodles() then return end
        local now = getTimestampMs()
        if (now - _lastReq) < 2500 then return end
        _lastReq = now
        if isClient() then
            sendClientCommand(p, "DRPMoodle", "statusrequest", {})
        else
            local u = p:getUsername()
            local k = (DRP.Strikes and DRP.Strikes.count and DRP.Strikes.count(u, now)) or 0
            applyStatus(k)
        end
    end)

    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= "DRPMoodle" or command ~= "status" or args == nil then return end
        applyStatus(args.k)
    end)
end

--------------------------------------------------------------------------------
-- Knockdown panel (migrated from DBNOKnockPanel)
--------------------------------------------------------------------------------

if ISPanel ~= nil then
    DRP.Knockdown = DRP.Knockdown or {}
    local K = DRP.Knockdown

    local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BAR_HGT = 14

    local DRPKnockPanel = ISPanel:derive("DRPKnockPanel")

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
        if dur <= 0 then return 0, 0 end
        return left / dur, left
    end

    function DRPKnockPanel:new()
        local w = 340
        local h = UI_BORDER_SPACING
            + FONT_HGT_MEDIUM
            + UI_BORDER_SPACING
            + (timerShown() and (BAR_HGT + 4 + FONT_HGT_SMALL + UI_BORDER_SPACING) or 0)
            + FONT_HGT_SMALL
            + UI_BORDER_SPACING
        local x = (getCore():getScreenWidth() - w) / 2
        local y = getCore():getScreenHeight() * 0.70
        local o = ISPanel:new(x, y, w, h)
        setmetatable(o, self)
        self.__index = self

        o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
        o.borderColor     = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
        o.moveWithMouse   = false
        o.anchorLeft      = false
        o.anchorTop       = false
        return o
    end

    function DRPKnockPanel:render()
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
            K._panel = DRPKnockPanel:new()
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