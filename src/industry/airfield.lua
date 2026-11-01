--- Landed AI aircraft. When an AI aircraft shuts down its engines on the
-- ground it has finished its mission: transports deliver their cargo, the
-- flag "<unit name>_landed" is set for mission editor triggers and the
-- aircraft is removed, which frees the parking spot and lets the group
-- respawn. DCS also reports an engine shutdown when a damaged aircraft
-- loses its engines in flight; those are left alone, they crash and are
-- handled like any other loss (removing them would cost the shooter the kill).

local tarmac = require("tarmac")
local logistics = require("industry.logistics")

local log = tarmac.log.new("industry.airfield")
local object = tarmac.object

local airfield = {}

local cfg

local function remove(unit, unitName)
    log:info("%s shut down its engines, removed", unitName)
    tarmac.tracker.destroyUnit(unit)
end

local function onEngineShutdown(event)
    local unit = event.initiator
    local unitName = object.name(unit)
    if unitName == nil or object.playerName(unit) ~= nil then
        return
    end
    if object.call(unit, "inAir") ~= false then
        log:info("%s lost its engines in flight, ignored", unitName)
        return
    end
    logistics.landed(unit)
    trigger.action.setUserFlag(unitName .. "_landed", true)
    if cfg.respawn.despawnLandedAI then
        -- a second later, outside the event handler: DCS can trip over world
        -- changes made while it dispatches an event
        tarmac.scheduler.after(1, remove, unit, unitName)
    end
end

function airfield.setup(configuration)
    cfg = configuration
    tarmac.events.on("ENGINE_SHUTDOWN", onEngineShutdown)
end

return airfield
