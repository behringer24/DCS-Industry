--- Reactions to lost units: destroyed player aircraft cost tickets,
-- destroyed ground vehicles keep burning for a while.

local tarmac = require("tarmac")
local tickets = require("industry.tickets")

local log = tarmac.log.new("industry.losses")
local object, db = tarmac.object, tarmac.db

local losses = {}

local cfg
-- [unitName] = true once the loss of a player aircraft was counted; DCS
-- may report a wreck lost again when it is destroyed later
local counted = {}

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
            -- a second later, outside the event handler: DCS can trip over
            -- world changes made while it dispatches an event
            tarmac.scheduler.after(1, trigger.action.effectSmokeBig, point, 1, 0.5)
        end
    end

    local playerName = object.playerName(unit)
    local unitName = object.name(unit)
    if playerName and object.isAircraft(unit) then
        if unitName then
            if counted[unitName] then
                log:info("player %s (%s) reported lost again, not counted", playerName, unitName)
                return
            end
            counted[unitName] = true
        end
        local coalitionId = coalitionOf(unit)
        log:info("player %s (%s) lost", playerName, tostring(object.name(unit)))
        tickets.reduce(coalitionId, cfg.losses.playerTickets, "player " .. playerName .. " lost")
    end
end

function losses.setup(configuration)
    cfg = configuration
    tarmac.events.on("UNIT_LOST", onUnitLost)
    -- a new aircraft in the same slot reuses the unit name
    tarmac.events.on("BIRTH", function(event)
        local unitName = object.name(event.initiator)
        if unitName then
            counted[unitName] = nil
        end
    end)
end

return losses
