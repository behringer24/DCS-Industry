--- Landed AI aircraft. When an AI aircraft shuts down its engines it has
-- finished its mission: transports deliver their cargo, the flag
-- "<unit name>_landed" is set for mission editor triggers and the aircraft
-- is removed, which frees the parking spot and lets the group respawn.

local tarmac = require("tarmac")
local logistics = require("industry.logistics")

local log = tarmac.log.new("industry.airfield")
local object = tarmac.object

local airfield = {}

local cfg

local function onEngineShutdown(event)
    local unit = event.initiator
    local unitName = object.name(unit)
    if unitName == nil or object.playerName(unit) ~= nil then
        return
    end
    logistics.landed(unit)
    trigger.action.setUserFlag(unitName .. "_landed", true)
    if cfg.respawn.despawnLandedAI then
        log:info("%s shut down its engines, removed", unitName)
        tarmac.tracker.destroyUnit(unit)
    end
end

function airfield.setup(configuration)
    cfg = configuration
    tarmac.events.on("ENGINE_SHUTDOWN", onEngineShutdown)
end

return airfield
