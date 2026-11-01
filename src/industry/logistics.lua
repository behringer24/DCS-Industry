--- Deliveries of resources by convoys and air transports.
--
-- Convoys: ground groups named "Convoy..." (or listed with role "convoy").
-- When a convoy reaches the last waypoint of its route, every surviving
-- truck delivers its load. Industry adds the waypoint action itself, at
-- mission start and on every respawn, so the mission editor needs no
-- script. The convoy then respawns for free.
--
-- Transports: aircraft groups named "Transport..." (or role "transport").
-- A transport delivers when it shuts down its engines after landing,
-- unless it landed at an enemy airbase.

local tarmac = require("tarmac")
local economy = require("industry.economy")
local respawn = require("industry.respawn")

local log = tarmac.log.new("industry.logistics")
local side, util, db, object, spawn = tarmac.side, tarmac.util, tarmac.db, tarmac.object, tarmac.spawn

local logistics = {}

local cfg
local roles = {}         -- [groupName] = "convoy" | "transport"
local delivered = {}     -- [groupName] = true once a convoy delivered in its current life
local hooked = {}        -- [groupName] = true when the current convoy has the arrival action
local landedAt = {}      -- [unitName] = coalition of the airbase of the last landing

local function override(groupName)
    return cfg.logistics.groups[groupName] or {}
end

function logistics.role(groupName)
    return roles[groupName]
end

local function arrivalCommand(groupName)
    return string.format("if industry then industry.convoyArrived(%q) end", groupName)
end

--- Route of a convoy with the arrival action at its last waypoint.
function logistics.convoyRoute(groupName)
    local points = db.route(groupName)
    if points == nil or #points == 0 then
        return nil
    end
    spawn.addWaypointScript(points[#points], arrivalCommand(groupName))
    return points
end

-- Gives a convoy that is already in the world its route with the arrival
-- action (convoys placed in the editor, late activated convoys).
local function hookConvoy(groupName)
    local group = Group.getByName(groupName)
    local points = logistics.convoyRoute(groupName)
    if group == nil or points == nil then
        return false
    end
    local controller = object.call(group, "getController")
    if controller == nil then
        return false
    end
    controller:setTask({ id = "Mission", params = { route = { points = points } } })
    hooked[groupName] = true
    return true
end

local function isTruck(unit)
    local types = cfg.logistics.truckTypes
    if types then
        local typeName = object.typeName(unit)
        for _, name in ipairs(types) do
            if typeName == name then
                return true
            end
        end
        return false
    end
    return object.call(unit, "hasAttribute", "Trucks") == true
end

--- Called by the waypoint action when a convoy reaches its destination.
function logistics.convoyArrived(groupName)
    if delivered[groupName] then
        return 0
    end
    local group = Group.getByName(groupName)
    if group == nil then
        log:warn("convoy %s arrived but does not exist", groupName)
        return 0
    end
    delivered[groupName] = true
    local coalitionId = object.coalition(group)
    local perTruck = override(groupName).tons or cfg.logistics.tonsPerTruck
    local trucks = 0
    for _, unit in ipairs(object.call(group, "getUnits") or {}) do
        local life = object.life(unit)
        if isTruck(unit) and life and life > 1 then
            trucks = trucks + 1
        end
    end
    local tons = trucks * perTruck
    trigger.action.outText(string.format("A %s convoy with %d tons of resources arrived at its destination",
        side.name(coalitionId), tons), 5)
    economy.add(coalitionId, tons, "convoy " .. groupName)
    respawn.queue(groupName, 0)
    return tons
end

local function landedAtEnemy(unitName, coalitionId)
    local placeCoalition = landedAt[unitName]
    return placeCoalition ~= nil and placeCoalition ~= coalitionId and placeCoalition ~= side.NEUTRAL
end

--- Called when an AI aircraft shut down its engines. Delivers the cargo of
-- transports. Returns the delivered tons.
function logistics.landed(unit)
    local unitName = object.name(unit)
    local groupName = object.groupName(unit)
    if groupName == nil or roles[groupName] ~= "transport" then
        return 0
    end
    local coalitionId = object.coalition(unit)
    if landedAtEnemy(unitName, coalitionId) then
        log:info("transport %s landed at an enemy airbase, cargo lost", unitName)
        return 0
    end
    local tons = override(groupName).tons or cfg.logistics.tonsPerTransport
    trigger.action.outText(string.format("A %s transport with %d tons of resources arrived at its destination",
        side.name(coalitionId), tons), 5)
    economy.add(coalitionId, tons, "transport " .. groupName)
    return tons
end

local function detectRoles()
    for _, record in ipairs(db.findGroups({ source = "mission" })) do
        local name = record.name
        local role = override(name).role
        if role == nil then
            if util.startsWith(name, cfg.logistics.convoyPrefix) and record.category == "vehicle" then
                role = "convoy"
            elseif util.startsWith(name, cfg.logistics.transportPrefix)
                    and (record.category == "plane" or record.category == "helicopter") then
                role = "transport"
            end
        end
        if role then
            roles[name] = role
            if not respawn.isRegistered(name) then
                respawn.register(name, 0)
            end
        end
    end
end

function logistics.setup(configuration)
    cfg = configuration
    detectRoles()

    for name, role in pairs(roles) do
        if role == "convoy" then
            hookConvoy(name)
        end
    end

    -- respawned convoys get the arrival action with their route
    respawn.addModifier(function(groupName, options)
        if roles[groupName] == "convoy" then
            options.route = logistics.convoyRoute(groupName)
            delivered[groupName] = nil
            hooked[groupName] = true
        end
    end)
    tarmac.events.on("tarmac.groupDead", function(event)
        hooked[event.groupName] = nil
    end)
    -- late activated convoys
    tarmac.events.on("BIRTH", function(event)
        local groupName = object.groupName(event.initiator)
        if groupName and roles[groupName] == "convoy" and not hooked[groupName] then
            hooked[groupName] = true
            tarmac.scheduler.after(1, hookConvoy, groupName)
        end
    end)
    tarmac.events.on("LAND", function(event)
        local unitName = object.name(event.initiator)
        if unitName then
            landedAt[unitName] = event.place and object.coalition(event.place) or nil
        end
    end)
    tarmac.events.on("TAKEOFF", function(event)
        local unitName = object.name(event.initiator)
        if unitName then
            landedAt[unitName] = nil
        end
    end)
end

return logistics
