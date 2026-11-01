--- Stranded aircraft. A damaged AI aircraft that ends up on the ground
-- without crashing (an emergency landing in a field, a damaged helicopter
-- that set down, a wreck left on a runway) raises no further event. DCS
-- still counts it as alive, so its group would never respawn. Every
-- respawn.deadCheckInterval seconds the aircraft of respawn groups are
-- checked: one that is damaged, on the ground and not moving at two checks
-- in a row is removed and counts as lost. Object.destroy does not always
-- remove a damaged aircraft, so one that is still there at the next check
-- is blown up.
--
-- An AI aircraft whose crew died or ejected may come down without crashing
-- too, like a helicopter that settles in a field, and keeps drawing enemy
-- fire. It is watched until it rests on the ground and then blown up.
-- Player aircraft stay: the player leaves the slot himself.

local tarmac = require("tarmac")
local respawn = require("industry.respawn")

local log = tarmac.log.new("industry.stranded")
local db, tracker, object = tarmac.db, tarmac.tracker, tarmac.object

local stranded = {}

-- below this speed in m/s an aircraft counts as not moving
local STILL_SPEED = 1
-- seconds between two looks at an aircraft without crew, and how often
local WRECK_INTERVAL = 10
local WRECK_LOOKS = 60
local WRECK_EXPLOSION = 400

local damaged = {}  -- [unitName] = true after a hit or an aborted mission
local suspects = {} -- [unitName] = true when found stranded at the last check
local removed = {}  -- [unitName] = unit removed at the last check
local wrecks = {}   -- [unitName] = true while an aircraft without crew is watched

local function speed(unit)
    local velocity = object.call(unit, "getVelocity")
    if velocity == nil then
        return nil
    end
    return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
end

local function isDamaged(unit, unitName)
    if damaged[unitName] then
        return true
    end
    local life, life0 = object.life(unit), object.call(unit, "getLife0")
    return life ~= nil and life0 ~= nil and life < life0
end

--- True for an AI aircraft that is damaged, on the ground and not moving.
function stranded.isStranded(unit)
    local unitName = object.name(unit)
    if unitName == nil or not object.isAircraft(unit) or object.playerName(unit) ~= nil then
        return false
    end
    if object.call(unit, "isActive") == false or object.call(unit, "inAir") ~= false then
        return false
    end
    local current = speed(unit)
    return current ~= nil and current < STILL_SPEED and isDamaged(unit, unitName)
end

local function blowUpLeftovers()
    for unitName, unit in pairs(removed) do
        local point = object.exists(unit) and object.point(unit)
        if point then
            trigger.action.explosion(point, 400)
            log:info("%s was not removed, blown up", unitName)
        end
    end
    removed = {}
end

--- One check of all aircraft of respawn groups.
function stranded.check()
    blowUpLeftovers()
    local found = {}
    for _, groupName in ipairs(respawn.groups()) do
        local record = db.group(groupName)
        if record and (record.category == "plane" or record.category == "helicopter") then
            for _, unitName in ipairs(tracker.aliveUnits(groupName)) do
                local unit = Unit.getByName(unitName)
                if unit and stranded.isStranded(unit) then
                    if suspects[unitName] then
                        log:info("%s is damaged and has not moved on the ground since the last check, removed", unitName)
                        removed[unitName] = unit
                        tracker.destroyUnit(unit)
                    else
                        found[unitName] = true
                    end
                end
            end
        end
    end
    suspects = found
end

local function removeLeftover(unit, unitName)
    if object.exists(unit) then
        log:info("%s survived the explosion, removed", unitName)
        tracker.destroyUnit(unit)
    end
end

local function watchWreck(unit, unitName, looks)
    if not object.exists(unit) then
        return
    end
    if object.call(unit, "inAir") == false then
        local current, point = speed(unit), object.point(unit)
        if current ~= nil and current < STILL_SPEED and point then
            trigger.action.explosion(point, WRECK_EXPLOSION)
            log:info("%s rests on the ground without crew, blown up", unitName)
            tarmac.scheduler.after(WRECK_INTERVAL, removeLeftover, unit, unitName)
            return
        end
    end
    if looks >= WRECK_LOOKS then
        log:info("%s without crew did not come to rest, left alone", unitName)
        return
    end
    tarmac.scheduler.after(WRECK_INTERVAL, watchWreck, unit, unitName, looks + 1)
end

-- the crew of an aircraft died or ejected
local function onCrewGone(event)
    local unit = event.initiator
    local unitName = object.name(unit)
    if unitName == nil or wrecks[unitName] or not object.isAircraft(unit) or object.playerName(unit) ~= nil then
        return
    end
    wrecks[unitName] = true
    tarmac.scheduler.after(WRECK_INTERVAL, watchWreck, unit, unitName, 1)
end

local function markDamaged(unit)
    local unitName = object.name(unit)
    if unitName and object.isAircraft(unit) then
        damaged[unitName] = true
    end
end

function stranded.setup(configuration)
    if not configuration.respawn.removeStranded then
        return
    end
    tarmac.events.on("HIT", function(event)
        markDamaged(event.target)
    end)
    tarmac.events.on("AI_ABORT_MISSION", function(event)
        markDamaged(event.initiator)
    end)
    -- a respawned unit reuses the name of the old one
    tarmac.events.on("BIRTH", function(event)
        local unitName = object.name(event.initiator)
        if unitName then
            damaged[unitName] = nil
            suspects[unitName] = nil
            wrecks[unitName] = nil
        end
    end)
    tarmac.events.on("PILOT_DEAD", onCrewGone)
    tarmac.events.on("EJECTION", onCrewGone)
    local interval = configuration.respawn.deadCheckInterval
    tarmac.scheduler.every(interval, stranded.check, { delay = interval + 8, name = "industry.stranded" })
end

return stranded
