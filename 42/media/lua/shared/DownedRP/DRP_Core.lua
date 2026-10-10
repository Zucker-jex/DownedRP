--
-- DownedRP - shared core helpers.
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--

DRP = DRP or {}

-- DeathWounds stub
DRP.DeathWounds = DRP.DeathWounds or {}
DRP.DeathWounds._captured = nil
function DRP.DeathWounds.capture(_player) end
function DRP.DeathWounds.clear() end
function DRP.DeathWounds.isEmpty() return true end

function DRP.nowMs()
    if getTimestampMs then return getTimestampMs() end
    return (getTimestamp() or 0) * 1000
end

function DRP.displayName(ch)
    if ch == nil then return "Someone" end
    local d = ch:getDescriptor()
    local nm = d and d:getForename()
    if nm == nil or nm == "" then nm = tostring(ch:getUsername()) end
    return nm
end

function DRP.accountName(ch)
    if ch == nil or ch.getUsername == nil then return nil end
    if isClient() or isServer() then return ch:getUsername() end
    local d = ch.getDescriptor and ch:getDescriptor()
    if d ~= nil then
        local n = (d:getForename() or "") .. (d:getSurname() or "")
        if n ~= "" then return n end
    end
    return ch:getUsername()
end

function DRP.isAdmin(ch)
    if ch == nil or ch.isAccessLevel == nil then return false end
    return ch:isAccessLevel("admin")
end

--------------------------------------------------------------------------------
-- Health buffer
--------------------------------------------------------------------------------

function DRP.setGeneralHealth(player, target)
    if player == nil then return end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return end
    local count = BodyPartType.ToIndex(BodyPartType.MAX)
    local totalMod = 0
    for i = 0, count - 1 do totalMod = totalMod + BodyPartType.getDamageModifyer(i) end
    if totalMod <= 0 then return end
    local targetDamage = 100.0 - target
    if targetDamage < 0 then targetDamage = 0 end
    local h = 100.0 - (targetDamage / totalMod)
    if h < 0 then h = 0 end
    if h > 100 then h = 100 end
    for i = 0, count - 1 do
        local bp = parts:get(i)
        if bp ~= nil then bp:SetHealth(h) end
    end
end

function DRP.stopBleeding(player)
    if player == nil then return end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return end
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local bp = parts:get(i)
        if bp ~= nil then
            bp:setBleeding(false)
            bp:setBleedingTime(0)
        end
    end
end

function DRP.holdHealth(player, hp)
    if player == nil then return end
    if player.setInvincible then player:setInvincible(true) end
    DRP.setGeneralHealth(player, hp)
    player:setHealth(hp)
end

function DRP.releaseHealth(player)
    if player == nil then return end
    if player.setInvincible then player:setInvincible(false) end
end

function DRP.enterDownedHealth(player)
    if player == nil then return end
    local C = DRP.cfg()
    local hp = C.knockdownHoldHp or 10
    if C.knockdownHoldMode == "off" then
        if player.setInvincible then player:setInvincible(false) end
        DRP.setGeneralHealth(player, hp)
        player:setHealth(hp)
        DRP.stopBleeding(player)
        return
    end
    DRP.holdHealth(player, hp)
end

--------------------------------------------------------------------------------
-- Crawl tracking
--------------------------------------------------------------------------------

DRP.Crawl = DRP.Crawl or {}
DRP.Crawl._at = DRP.Crawl._at or {}

function DRP.Crawl.track(player, startMs)
    if player == nil then return 0 end
    local key = player:getUsername() or tostring(player:getOnlineID())
    local x, y = player:getX(), player:getY()
    local now = DRP.nowMs()
    local st = DRP.Crawl._at[key]
    if st == nil or st.start ~= startMs then
        DRP.Crawl._at[key] = { start = startMs, x = x, y = y, t = now, ms = 0 }
        return 0
    end
    if math.abs(x - st.x) > 0.05 or math.abs(y - st.y) > 0.05 then
        st.ms = st.ms + (now - st.t)
    end
    st.x, st.y, st.t = x, y, now
    return st.ms
end

function DRP.tickDownedHealth(player, startMs, crawledMs)
    if player == nil then return true end
    local C = DRP.cfg()
    local mode = C.knockdownHoldMode or "on"
    if mode == "off" then
        DRP.stopBleeding(player)
        return true
    end
    local hp = C.knockdownHoldHp or 10
    if mode == "drain" then
        local rate = C.knockdownDrainHpPerMin or 2
        local mins = (DRP.nowMs() - (startMs or DRP.nowMs())) / 60000
        local bonus = ((C.knockdownCrawlDrainMult or 2) - 1) * ((crawledMs or 0) / 60000)
        hp = hp - rate * (mins + bonus)
        if hp <= 0 then return false end
    end
    DRP.holdHealth(player, hp)
    return true
end

--------------------------------------------------------------------------------
-- Wound state
--------------------------------------------------------------------------------

function DRP.isPartTreated(bp)
    if bp == nil then return true end
    if bp:bleeding() then return false end
    if bp:getBleedingTime() > 0 then return false end
    if bp:isBandageDirty() then return false end
    if bp:haveBullet() then return false end
    if bp:haveGlass() then return false end
    if bp:getFractureTime() > 0 and not bp:isSplint() then return false end
    if bp:isBurnt() and bp:isNeedBurnWash() then return false end
    if bp:isDeepWounded() and not bp:stitched() then return false end
    if bp:isCut() and not bp:stitched() then return false end
    if bp:scratched() and not bp:bandaged() then return false end
    if bp:bitten() and not bp:bandaged() then return false end
    return true
end

function DRP.areWoundsTreated(player)
    local bd = player and player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return true, 0 end
    local count = BodyPartType.ToIndex(BodyPartType.MAX)
    local pending = 0
    for i = 0, count - 1 do
        if not DRP.isPartTreated(parts:get(i)) then pending = pending + 1 end
    end
    return pending == 0, pending
end

function DRP.canStandUp(player)
    if player == nil then return false end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return true end
    local count = BodyPartType.ToIndex(BodyPartType.MAX)
    for i = 0, count - 1 do
        local bp = parts:get(i)
        if bp ~= nil then
            if bp:isDeepWounded() and not bp:stitched() and not bp:bandaged() then return false end
            if bp:isCut()         and not bp:stitched() and not bp:bandaged() then return false end
            if bp:scratched()     and not bp:bandaged() then return false end
            if bp:bitten()        and not bp:bandaged() then return false end
        end
    end
    return true
end

function DRP.standUpBlockReason(player)
    if player == nil then return "Unknown" end
    local bd = player:getBodyDamage()
    local parts = bd and bd:getBodyParts()
    if parts == nil then return nil end
    local count = BodyPartType.ToIndex(BodyPartType.MAX)

    for i = 0, count - 1 do
        local bp = parts:get(i)
        if bp ~= nil and bp:bleeding() then return "Bleeding" end
    end
    for i = 0, count - 1 do
        local bp = parts:get(i)
        if bp ~= nil then
            if bp:isDeepWounded() and not bp:stitched() and not bp:bandaged() then return "DeepWound" end
            if bp:isCut()         and not bp:stitched() and not bp:bandaged() then return "Cut" end
            if bp:scratched()     and not bp:bandaged() then return "Scratch" end
            if bp:bitten()        and not bp:bandaged() then return "Bite" end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Perk resolution
--------------------------------------------------------------------------------

function DRP.firstAidPerk()
    if type(Perks) ~= "table" then return nil end
    return Perks.Doctor or Perks.FirstAid
end

function DRP.getFirstAidLevel(player)
    if player == nil then return 0 end
    local perk = DRP.firstAidPerk()
    if perk == nil then return 0 end
    local ok, lvl = pcall(function() return player:getPerkLevel(perk) end)
    if ok and type(lvl) == "number" then return lvl end
    return 0
end

--------------------------------------------------------------------------------
-- Self-treatment gate
--------------------------------------------------------------------------------

function DRP.selfTreatAllowed(player, level)
    if player == nil then return false end
    if level == nil then
        local ns = (type(SandboxVars) == "table") and SandboxVars.DownedRP or nil
        local live = ns and ns.SelfTreatFirstAidLevel
        if type(live) == "number" then
            level = live
        else
            level = DRP.cfg().selfTreatFirstAidLevel
        end
    end
    level = tonumber(level) or -1
    if level < 0 then return false end
    if level == 0 then return true end
    local perk = DRP.firstAidPerk()
    if perk == nil then return true end
    return DRP.getFirstAidLevel(player) >= level
end

--------------------------------------------------------------------------------
-- Self-treat notification
--
-- Shows a HaloText prompt above the player's head when a medical action is
-- blocked because self-treatment is not permitted: either the sandbox forbids
-- it entirely (-1) or the player's First Aid level is too low. Rate limited so
-- repeated clicks do not spam the halo line.
--------------------------------------------------------------------------------

local _lastSelfTreatNote = 0
local SELF_TREAT_NOTE_COOLDOWN_MS = 1500

function DRP.notifySelfTreatBlocked(player)
    if player == nil then return end
    local now = DRP.nowMs()
    if (now - _lastSelfTreatNote) < SELF_TREAT_NOTE_COOLDOWN_MS then return end
    _lastSelfTreatNote = now

    -- Read the sandbox value live, same as selfTreatAllowed does.
    local level = nil
    local ns = (type(SandboxVars) == "table") and SandboxVars.DownedRP or nil
    if ns ~= nil and type(ns.SelfTreatFirstAidLevel) == "number" then
        level = ns.SelfTreatFirstAidLevel
    end
    if level == nil then
        level = DRP.cfg().selfTreatFirstAidLevel
    end

    local msg
    if level == nil or level < 0 then
        msg = getText("IGUI_DRP_CannotSelfTreat")
    else
        msg = getText("IGUI_DRP_NeedFirstAidLevel", tostring(level))
    end

    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(player, msg)
    end
end

--------------------------------------------------------------------------------
-- Timed action classification
--------------------------------------------------------------------------------

DRP.MEDICAL_ACTIONS = {
    ISApplyBandage      = true,
    ISCleanBandage      = true,
    ISDisinfect         = true,
    ISSplint            = true,
    ISStitch            = true,
    ISRemoveBullet      = true,
    ISRemoveGlass       = true,
    ISRemoveBrokenGlass = true,
    ISCleanBurn         = true,
    ISComfreyCataplasm  = true,
    ISGarlicCataplasm   = true,
    ISPlantainCataplasm = true,
    ISTakePillAction    = true,
}

DRP.UI_ACTIONS = {
    HealthPanelAction = true,
}

DRP.MEDICAL_KEYWORDS = {
    "bandage", "splint", "stitch", "disinfect",
    "removebullet", "removeglass", "cleanburn",
    "cataplasm", "medical", "firstaid",
}

DRP.MOVEMENT_KEYWORDS = {
    "walkto", "walk", "path", "move", "travel", "goto",
}

function DRP.actionName(action)
    if action == nil then return nil end
    local t = action.Type
    if type(t) == "string" then return t end
    local mt = getmetatable(action)
    local n = mt and mt.__index
    if type(n) == "string" then return n end
    return nil
end

local function nameMatches(name, keywords)
    if name == nil then return false end
    local lower = string.lower(tostring(name))
    for _, kw in ipairs(keywords) do
        if string.find(lower, string.lower(kw), 1, true) then return true end
    end
    return false
end

function DRP.isMedicalAction(action)
    if action == nil then return false end
    local name = DRP.actionName(action)
    if name ~= nil and DRP.MEDICAL_ACTIONS[name] == true then return true end
    if nameMatches(name, DRP.MEDICAL_KEYWORDS) then return true end
    for _, field in ipairs({ "name", "actionName", "displayName" }) do
        if nameMatches(action[field], DRP.MEDICAL_KEYWORDS) then return true end
    end
    return false
end

function DRP.isMovementAction(action)
    if action == nil then return false end
    local name = DRP.actionName(action)
    if nameMatches(name, DRP.MOVEMENT_KEYWORDS) then return true end
    for _, field in ipairs({ "name", "actionName", "displayName" }) do
        if nameMatches(action[field], DRP.MOVEMENT_KEYWORDS) then return true end
    end
    return false
end

function DRP.isUIAction(action)
    if action == nil then return false end
    local name = DRP.actionName(action)
    if name ~= nil and DRP.UI_ACTIONS[name] == true then return true end
    return false
end

--------------------------------------------------------------------------------
-- Sandbox
--------------------------------------------------------------------------------

DRP.Sandbox = DRP.Sandbox or {}

local HOLD_MODES = { "off", "on", "drain" }

local SANDBOX_SPECS = {
    { field = "knockdownEnable",      sandboxKey = "KnockdownEnable",       type = "bool", default = true },
    { field = "knockdownCounters",    sandboxKey = "KnockdownCounters",     type = "bool", default = true },
    { field = "bleedoutTimer",        sandboxKey = "BleedoutTimer",         type = "bool", default = true },
    { field = "moveWhileDowned",      sandboxKey = "MoveWhileDowned",       type = "bool", default = true },
    { field = "knockdownDurationSec", sandboxKey = "KnockdownDurationSec",  type = "num",  default = 300 },
    { field = "knockdownWindowSec",   sandboxKey = "KnockdownHealingMin",   type = "num",  default = 5,   transform = function(v) return v * 60 end },
    { field = "knockdownStrikeLimit", sandboxKey = "KnockdownStrikeLimit",  type = "num",  default = 3 },
    { field = "knockdownThreshold",   sandboxKey = "KnockdownThreshold",    type = "num",  default = 10 },
    { field = "knockdownHoldHp",      sandboxKey = "KnockdownHoldHP",       type = "num",  default = 10 },
    { field = "knockdownReviveHp",    sandboxKey = "KnockdownReviveHP",     type = "num",  default = 30 },
    { field = "knockdownReviveTime",  sandboxKey = "KnockdownReviveTime",   type = "num",  default = 200 },
    { field = "knockdownHoldMode",    sandboxKey = "KnockdownHoldMode",     type = "enum", default = 2,   enumValues = HOLD_MODES },
    { field = "knockdownDrainHpPerMin", sandboxKey = "KnockdownDrainHpPerMin", type = "num", default = 2 },
    { field = "knockdownCrawlSpeedPct", sandboxKey = "KnockdownCrawlSpeedPct", type = "num", default = 30 },
    { field = "downedPlayerKill",     sandboxKey = "DownedPlayerKill",      type = "bool", default = false },
    { field = "downedZombieKill",     sandboxKey = "DownedZombieKill",      type = "bool", default = false },
    { field = "selfTreatFirstAidLevel", sandboxKey = "SelfTreatFirstAidLevel", type = "num", default = -1 },
    { field = "assistEnable",         sandboxKey = "AssistEnable",          type = "bool", default = true },
    { field = "assistFollowDistance", sandboxKey = "AssistFollowDistance",  type = "num",  default = 2 },
    { field = "assistBreakDistance",  sandboxKey = "AssistBreakDistance",   type = "num",  default = 5 },
    { field = "assistSpeedModifier",  sandboxKey = "AssistSpeedModifier",   type = "num",  default = 60 },
}

local function getNamespace()
    if type(SandboxVars) ~= "table" then return nil end
    return SandboxVars.DownedRP
end

local function isNamespaceAvailable()
    return type(SandboxVars) == "table"
        and type(SandboxVars.DownedRP) == "table"
end

local function isValidValue(spec, value)
    if value == nil then return false end
    if spec.type == "num" then
        if type(value) ~= "number" or value ~= value then return false end
        if spec.integer and value ~= math.floor(value) then return false end
        if spec.min and value < spec.min then return false end
        if spec.max and value > spec.max then return false end
        return true
    elseif spec.type == "bool" then
        return type(value) == "boolean"
    elseif spec.type == "enum" then
        if type(value) == "number" then
            return value % 1 == 0 and spec.enumValues[value] ~= nil
        end
        if type(value) == "string" then
            for _, v in ipairs(spec.enumValues) do if v == value then return true end end
        end
        return false
    end
    return true
end

local function resolveSpec(spec)
    local ns = getNamespace()
    local raw
    if ns ~= nil then
        raw = ns[spec.sandboxKey]
    end
    local authoritative = isValidValue(spec, raw)
    local value = spec.default
    if authoritative then value = raw end
    if spec.type == "enum" and type(value) == "number" then
        value = spec.enumValues[value]
    end
    if spec.transform then
        local ok, transformed = pcall(spec.transform, value)
        if ok and transformed ~= nil then value = transformed else value = spec.default end
    end
    return value, authoritative
end

local function applySandboxDefaults(reportFallback)
    local problemCount = 0
    local C = DRP.Config
    for _, spec in ipairs(SANDBOX_SPECS) do
        local value, authoritative = resolveSpec(spec)
        if not authoritative then problemCount = problemCount + 1 end
        C[spec.field] = value
    end
    if C.knockdownHoldHp < C.knockdownThreshold then
        C.knockdownHoldHp = C.knockdownThreshold
    end
    if C.knockdownReviveHp <= C.knockdownThreshold then
        C.knockdownReviveHp = math.min(100, C.knockdownThreshold + 10)
    end
    if reportFallback and problemCount > 0 then
        print("[DownedRP] Sandbox config: " .. problemCount .. " key(s) used fallback defaults")
    end
    return problemCount
end

applySandboxDefaults(false)
DRP.Config._sandboxAuthoritative = false

function DRP.Config.reloadSandbox()
    if not isNamespaceAvailable() then
        DRP.Config._sandboxAuthoritative = false
        return false
    end
    local problems = applySandboxDefaults(true)
    DRP.Config._sandboxAuthoritative = true
    print(string.format(
        "[DownedRP] Sandbox loaded (fallbacks=%d): SelfTreatFirstAidLevel=%s BleedoutTimer=%s KnockdownCounters=%s KnockdownEnable=%s CrawlSpeed=%s%%",
        problems,
        tostring(DRP.Config.selfTreatFirstAidLevel),
        tostring(DRP.Config.bleedoutTimer),
        tostring(DRP.Config.knockdownCounters),
        tostring(DRP.Config.knockdownEnable),
        tostring(DRP.Config.knockdownCrawlSpeedPct)
    ))
    return true
end

function DRP.Config.isSandboxAuthoritative()
    return DRP.Config._sandboxAuthoritative == true
end

function DRP.Config.ensureSandboxLoaded()
    if DRP.Config._sandboxAuthoritative then return true end
    if not isNamespaceAvailable() then return false end
    return DRP.Config.reloadSandbox()
end

--------------------------------------------------------------------------------
-- Robust boot
--------------------------------------------------------------------------------

local _sandboxDone = false

local function tryLoadOnce()
    if _sandboxDone then return true end
    if DRP.Config == nil or DRP.Config.reloadSandbox == nil then return false end
    local ok = DRP.Config.reloadSandbox()
    if ok then
        _sandboxDone = true
        return true
    end
    return false
end

local function startRetryTicker(maxTries)
    local tries = 0
    local acc = 0
    local function tick()
        if _sandboxDone then
            Events.OnTick.Remove(tick)
            return
        end
        acc = acc + 1
        if acc < 30 then return end
        acc = 0
        tries = tries + 1
        if tryLoadOnce() or tries >= maxTries then
            Events.OnTick.Remove(tick)
        end
    end
    Events.OnTick.Add(tick)
end

local function bootSandbox()
    if tryLoadOnce() then return end
    startRetryTicker(120)
end

if Events.OnServerStarted then
    Events.OnServerStarted.Add(bootSandbox)
end
if Events.OnGameStart then
    Events.OnGameStart.Add(bootSandbox)
end
if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(idx, player) bootSandbox() end)
end
if Events.OnConnected then
    Events.OnConnected.Add(function()
        if DRP.Config and DRP.Config.reloadSandbox then
            DRP.Config.reloadSandbox()
        end
    end)
end