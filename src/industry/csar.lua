--- Automatic combat search and rescue. When a pilot lands with the
-- parachute on land, the pilot becomes a soldier on the ground and a
-- rescue helicopter of the pilot's coalition is sent to pick him up.
-- Rescue helicopters are cloned from a template group per coalition whose
-- name starts with the configured prefix ("TPL-SAR..."); use late
-- activation and "uncontrolled" for the template. Shooting down a rescue
-- helicopter costs the shooter's coalition tickets.

local tarmac = require("tarmac")
local tickets = require("industry.tickets")

local log = tarmac.log.new("industry.csar")
local side, util, db, object, spawn = tarmac.side, tarmac.util, tarmac.db, tarmac.object, tarmac.spawn

local csar = {}

local cfg
local templates = {}     -- [coalitionId] = template group name
local rescueGroups = {}  -- [groupName] = true for spawned rescue helicopters
local missionCounter = 0
local pilotCounter = 0

local soldierTypes = { [side.RED] = "Infantry AK", [side.BLUE] = "Soldier M4" }

-- Parachutes sometimes report coalition 0 or a bogus country.
local parachuteDefaults = {
    pilot_f15_parachute = { coalition = side.BLUE, country = 2 },
    pilot_su27_parachute = { coalition = side.RED, country = 0 },
}

local function pilotIdentity(unit)
    local name = object.name(unit) or "unknown"
    local typeName = object.typeName(unit)
    local coalitionId = object.coalition(unit)
    local countryId = object.country(unit)
    if coalitionId == nil or coalitionId == 0 or countryId == nil or countryId > 99 then
        local fallback = parachuteDefaults[typeName] or parachuteDefaults[name]
        if fallback == nil then
            log:warn("parachute %s (%s) without coalition, assuming blue", name, tostring(typeName))
            fallback = { coalition = side.BLUE, country = 2 }
        end
        coalitionId, countryId = fallback.coalition, fallback.country
    end
    return coalitionId, countryId
end

local function spawnSoldier(point, coalitionId, countryId)
    pilotCounter = pilotCounter + 1
    local groupName = string.format("DownedPilot-%d", pilotCounter)
    local group, err = spawn.add("vehicle", countryId, {
        name = groupName,
        task = "Ground Nothing",
        x = point.x + 1,
        y = point.y,
        units = {
            {
                name = groupName .. "-1",
                type = soldierTypes[coalitionId] or soldierTypes[side.BLUE],
                skill = "Average",
                x = point.x + 1,
                y = point.y,
                heading = 0.286,
                playerCanDrive = true,
            },
        },
        route = {},
    }, { coalition = coalitionId })
    if group == nil then
        log:error("could not spawn downed pilot: %s", err)
        return nil
    end
    return groupName
end

local function clearLandingZone(point)
    local radius = cfg.csar.clearRadius
    if radius == nil or radius <= 0 then
        return
    end
    local volume = { id = world.VolumeType.SPHERE, params = { point = util.vec3(point), radius = radius } }
    world.searchObjects(Object.Category.SCENERY, volume, function(found)
        object.destroy(found)
        return true
    end)
end

local function rescueWaypoint(landPoint, soldierGroup)
    local command = string.format(
        "local g = Group.getByName(%q) if g and g:isExist() then g:destroy() end", soldierGroup)
    return {
        type = "Turning Point",
        action = "Turning Point",
        x = landPoint.x,
        y = landPoint.y,
        alt = math.random(200, 400),
        alt_type = "BARO",
        speed = math.random(60, 100),
        task = {
            id = "ComboTask",
            params = {
                tasks = {
                    {
                        number = 1, auto = false, enabled = true, id = "Land",
                        params = { point = { x = landPoint.x, y = landPoint.y }, duration = math.random(20, 120), durationFlag = true },
                    },
                    {
                        number = 2, auto = false, enabled = true, id = "WrappedAction",
                        params = { action = { id = "Script", params = { command = command } } },
                    },
                },
            },
        },
    }
end

--- Starts a rescue mission for a pilot that landed at point (Vec2).
function csar.startMission(coalitionId, countryId, point)
    local template = templates[coalitionId]
    if template == nil then
        return nil
    end
    local soldierGroup = spawnSoldier(point, coalitionId, countryId)
    if soldierGroup == nil then
        return nil
    end
    local landPoint = { x = point.x + 12, y = point.y + 10 }
    clearLandingZone(landPoint)

    local route = db.route(template) or {}
    route[#route + 1] = rescueWaypoint(landPoint, soldierGroup)

    missionCounter = missionCounter + 1
    local groupName = string.format("SAR %s #%d", side.label(coalitionId), missionCounter)
    rescueGroups[groupName] = true
    local group, err = spawn.clone(template, { name = groupName, route = route })
    if group == nil then
        log:error("could not spawn rescue helicopter: %s", err)
        return nil
    end
    local controller = object.call(group, "getController")
    if controller then
        controller:setCommand({ id = "Start", params = {} })
    end
    trigger.action.outTextForCoalition(coalitionId,
        string.format("Pilot down, parachute spotted at %s. SAR mission started", util.formatPoint(point, 3)), 10)
    log:info("rescue %s sent for %s", groupName, soldierGroup)
    return groupName, soldierGroup
end

function csar.isRescueGroup(groupName)
    return rescueGroups[groupName] == true
end

local function onParachuteLanded(event)
    local unit = event.initiator
    local coalitionId, countryId = pilotIdentity(unit)
    if templates[coalitionId] == nil then
        return
    end
    local position = object.point(unit)
    if position == nil then
        return
    end
    local point = util.vec2(position)
    local surface = land.getSurfaceType(point)
    object.destroy(unit)
    if surface == land.SurfaceType.LAND or surface == land.SurfaceType.ROAD or surface == land.SurfaceType.RUNWAY then
        csar.startMission(coalitionId, countryId, point)
    end
end

local function targetGroupName(target)
    local name = object.groupName(target)
    if name then
        return name
    end
    local record = db.unit(object.name(target) or "")
    return record and record.groupName
end

local function onKill(event)
    local playerName = object.playerName(event.initiator)
    if playerName == nil or object.unitCategory(event.target) ~= Unit.Category.HELICOPTER then
        return
    end
    local groupName = targetGroupName(event.target)
    if groupName and rescueGroups[groupName] then
        trigger.action.outText(string.format("Player %s shot down SAR unit %s", playerName, groupName), 10)
        tickets.reduce(object.coalition(event.initiator), cfg.csar.killTickets, "rescue helicopter shot down")
    else
        trigger.action.outText(string.format("Player %s shot down %s", playerName, tostring(groupName)), 10)
    end
end

function csar.setup(configuration)
    cfg = configuration
    if not cfg.csar.enabled then
        return
    end
    for _, coalitionId in ipairs(side.BOTH) do
        local found = db.findGroups({
            prefix = cfg.csar.templatePrefix, coalition = coalitionId, category = "helicopter", source = "mission",
        })
        if found[1] then
            templates[coalitionId] = found[1].name
            log:info("%s rescue template: %s", side.name(coalitionId), found[1].name)
        end
    end
    tarmac.events.on("LANDING_AFTER_EJECTION", onParachuteLanded)
    tarmac.events.on("KILL", onKill)
end

return csar
