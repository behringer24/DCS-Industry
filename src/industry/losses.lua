--- Reactions to lost units: destroyed player aircraft cost tickets,
-- destroyed ground vehicles keep burning for a while.

local tarmac = require("tarmac")
local tickets = require("industry.tickets")

local log = tarmac.log.new("industry.losses")
local object, db = tarmac.object, tarmac.db

local losses = {}

local cfg

local function coalitionOf(unit)
    local coalitionId = object.coalition(unit)
    if coalitionId == nil then
        local record = db.unit(object.name(unit) or "")
        coalitionId = record and record.coalition
    end
    return coalitionId
end

local function onUnitLost(event)
    local unit = event.initiator
    local category = object.unitCategory(unit)

    if category == Unit.Category.GROUND_UNIT and cfg.losses.vehicleSmoke then
        local point = object.point(unit)
        if point then
            trigger.action.effectSmokeBig(point, 1, 0.5)
        end
    end

    local playerName = object.playerName(unit)
    if playerName and object.isAircraft(unit) then
        local coalitionId = coalitionOf(unit)
        log:info("player %s (%s) lost", playerName, tostring(object.name(unit)))
        tickets.reduce(coalitionId, cfg.losses.playerTickets, "player " .. playerName .. " lost")
    end
end

function losses.setup(configuration)
    cfg = configuration
    tarmac.events.on("UNIT_LOST", onUnitLost)
end

return losses
