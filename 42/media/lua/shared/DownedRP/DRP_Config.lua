--
-- DownedRP - shared configuration.
--
-- Based on Down But Not Out by phasmoware (Workshop ID 3774055538).
-- Original code licensed under MIT. See LICENSE_DBNO.txt.
--
-- PLACEHOLDER defaults only. Authoritative values come from
-- SandboxVars.DownedRP via DRP_Core.lua's reloadSandbox(), reached lazily
-- through DRP.cfg(). Do not read DRP.Config fields directly from mod code.
--

DRP = DRP or {}

DRP.Config = DRP.Config or {}
local C = DRP.Config

C.dataRoot = C.dataRoot or "DownedRP"

C.knockdownEnable      = true
C.knockdownAutoTrigger = true
C.knockdownThreshold   = 10

C.knockdownHoldHp      = 10
C.knockdownReviveHp    = 30
C.knockdownDurationSec = 300
C.knockdownDebugMenu   = true
C.knockdownCounters    = true
C.bleedoutTimer        = true
C.moveWhileDowned      = true
C.knockdownCrawlSpeedPct = 30

C.knockdownStrikeLimit = 3
C.knockdownWindowSec   = 300
C.knockdownReviveTime  = 200
C.knockdownHoldMode    = "on"

C.knockdownDrainHpPerMin  = 2
C.knockdownCrawlDrainMult = 2

C.downedPlayerKill = false
C.downedZombieKill = false

C.selfTreatFirstAidLevel = -1

C.assistEnable         = true
C.assistFollowDistance = 2
C.assistBreakDistance  = 5
C.assistSpeedModifier  = 60

-- Lazy accessor. DRP_Core.lua installs DRP.Config.ensureSandboxLoaded.
function DRP.cfg()
    if DRP.Config.ensureSandboxLoaded then
        DRP.Config.ensureSandboxLoaded()
    end
    return DRP.Config or {}
end