--- Automatic combat search and rescue. When a pilot lands with the
-- parachute on land, the pilot becomes a soldier on the ground and a
-- rescue helicopter is sent to pick him up. Rescue helicopters are clones of
-- one template group per coalition of the downed pilot (default
-- "TPL-SAR-Red" and "TPL-SAR-Blue"). The template keeps its own coalition,
-- usually neutral, so the clone flies for neither side; tick
-- "uncontrolled" for it. Shooting down a rescue helicopter costs the
-- shooter's coalition tickets.
--
-- Every rescue is checked every few seconds and runs through three states:
--   outbound   the helicopter flies to the pilot and lands where its AI
--              finds a landing site, which may be some distance away
--   boarding   it landed close enough: the pilot walks over and boards
--   returning  it flies home, lands and is removed
-- A helicopter that lands too far away takes off and tries again at the
-- pilot's position. After the last attempt, when the pilot does not reach
-- the helicopter in time or when the pilot is killed, the rescue fails and
-- the helicopter flies home; the soldier stays where he is.

local tarmac = require("tarmac")
local tickets = require("industry.tickets")

local log = tarmac.log.new("industry.csar")
local side, util, db, object, spawn, tracker =
    tarmac.side, tarmac.util, tarmac.db, tarmac.object, tarmac.spawn, tarmac.tracker

local csar = {}

-- seconds between two checks of all rescues
local CHECK_INTERVAL = 5
-- a pilot this close to the helicopter in meters has boarded
local BOARD_DISTANCE = 25
-- walking speed of the pilot in m/s
local WALK_SPEED = 2
-- cruise speed of rescue helicopters in m/s (about 200 km/h)
local FLIGHT_SPEED = 55
-- a returning helicopter that lands this close to its start is removed
local HOME_RADIUS = 3000
-- an outbound helicopter on the ground this close to its start has not left yet
local START_RADIUS = 1000
-- parking spot types helicopters can use (helicopter only, open, open big)
local HELICOPTER_SPOTS = { [40] = true, [72] = true, [104] = true }

local HOT_START = {
    TakeOffParking = { type = "TakeOffParkingHot", action = "From Parking Area Hot" },
    TakeOffGround = { type = "TakeOffGroundHot", action = "From Ground Area Hot" },
}

local cfg
local templates = {}     -- [coalitionId] = template group name
local rescueGroups = {}  -- [groupName] = true for spawned rescue helicopters
local missions = {}      -- [groupName] = state of a running rescue
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

local function speed(unit)
    local velocity = object.call(unit, "getVelocity")
    if velocity == nil then
        return 0
    end
    return math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
end

local function position(unit)
    local point = object.point(unit)
    return point and util.vec2(point)
end

-- Waypoints -----------------------------------------------------------------

local function turningPoint(point, task)
    return {
        type = "Turning Point",
        action = "Turning Point",
        x = point.x,
        y = point.y,
        alt = cfg.csar.altitude,
        alt_type = "RADIO",
        speed = FLIGHT_SPEED,
        task = task,
    }
end

local function landTask(point)
    return {
        id = "ComboTask",
        params = {
            tasks = {
                {
                    number = 1, auto = false, enabled = true, id = "Land",
                    params = { point = { x = point.x, y = point.y }, duration = cfg.csar.waitTime, durationFlag = true },
                },
            },
        },
    }
end

-- Lands a few meters from the pilot, not on top of him.
local function rescueWaypoint(pilotPoint)
    local landPoint = { x = pilotPoint.x + 20, y = pilotPoint.y + 20 }
    return turningPoint(landPoint, landTask(landPoint))
end

-- The way back: to the airbase or FARP of the template, or a landing at its
-- start position for a template that starts from the ground.
local function homeWaypoints(home)
    if home.airdromeId or home.helipadId then
        return {
            turningPoint(home),
            {
                type = "Land",
                action = "Landing",
                x = home.x,
                y = home.y,
                alt = 0,
                alt_type = "RADIO",
                speed = FLIGHT_SPEED,
                airdromeId = home.airdromeId,
                helipadId = home.helipadId,
                linkUnit = home.linkUnit,
            },
        }
    end
    return { turningPoint(home, landTask(home)) }
end

local function append(points, more)
    for _, point in ipairs(more) do
        points[#points + 1] = point
    end
    return points
end

local function setRoute(groupName, points)
    local controller = object.call(Group.getByName(groupName), "getController")
    if controller then
        object.call(controller, "setTask", { id = "Mission", params = { route = { points = points } } })
    end
end

-- Spawning ------------------------------------------------------------------

local function nearestAirbase(point)
    local ok, airbases = pcall(world.getAirbases)
    local best, bestDistance
    for _, airbase in ipairs(ok and airbases or {}) do
        local airbasePoint = object.point(airbase)
        local distance = airbasePoint and util.distance2D(point, airbasePoint)
        if distance and (bestDistance == nil or distance < bestDistance) then
            best, bestDistance = airbase, distance
        end
    end
    if bestDistance and bestDistance < 5000 then
        return best
    end
    return nil
end

-- The free helicopter parking spot closest to the template's own spot, so
-- that rescues running at the same time do not share one spot.
local function freeParkingSpot(start)
    local airbase = nearestAirbase(start)
    local best, bestDistance
    for _, spot in ipairs(object.call(airbase, "getParking", true) or {}) do
        if HELICOPTER_SPOTS[spot.Term_Type] and spot.vTerminalPos then
            local distance = util.distance2D(start, spot.vTerminalPos)
            if bestDistance == nil or distance < bestDistance then
                best, bestDistance = spot, distance
            end
        end
    end
    return best
end

-- Spawn options for a rescue helicopter starting like its template, but
-- from a free parking spot of its airbase and, with csar.hotStart, with
-- running engines. Without a free spot of its own the helicopter shares
-- the template's spot and keeps the cold start of the template.
local function startOptions(template, start, route)
    local data = db.groupData(template) or {}
    local options = { route = route }
    if start == nil or not util.startsWith(tostring(start.type), "TakeOff") then
        -- no takeoff waypoint: the helicopter starts in the air
        options.uncontrolled = false
        return options, false
    end
    local first = route[1]
    local spot = first.airdromeId and freeParkingSpot(start)
    local hot = spot and cfg.csar.hotStart and HOT_START[first.type]
    if hot then
        first.type, first.action = hot.type, hot.action
        options.uncontrolled = false
    end
    if spot then
        local x, y = spot.vTerminalPos.x, spot.vTerminalPos.z
        first.x, first.y = x, y
        options.modify = function(groupData)
            groupData.x, groupData.y = x, y
            for _, unitData in ipairs(groupData.units or {}) do
                unitData.x, unitData.y = x, y
                unitData.parking = spot.Term_Index
                unitData.parking_id = nil
            end
        end
    end
    return options, not hot and data.uncontrolled == true, spot
end

-- Rescue states -------------------------------------------------------------

local function message(mission, text)
    trigger.action.outTextForCoalition(mission.coalition, text, 10)
end

local function goHome(mission, unit)
    mission.state = "returning"
    mission.airborne = object.call(unit, "inAir") == true
    local here = position(unit)
    if here then
        setRoute(mission.groupName, append({ turningPoint(here) }, homeWaypoints(mission.home)))
    end
end

local function fail(mission, unit, reason)
    log:info("rescue %s failed: %s", mission.groupName, reason)
    message(mission, "SAR mission failed: " .. reason)
    goHome(mission, unit)
end

local function pickUp(mission, unit)
    tracker.destroyGroup(mission.soldier)
    log:info("%s picked up by %s", mission.soldier, mission.groupName)
    message(mission, "Pilot rescued, the SAR helicopter returns to base")
    goHome(mission, unit)
end

local function walkTo(soldierGroup, from, helicopter)
    -- stop a few meters short of the helicopter, away from the rotor
    local distance = util.distance2D(from, helicopter)
    local factor = math.min(10 / distance, 1)
    local target = {
        x = helicopter.x + (from.x - helicopter.x) * factor,
        y = helicopter.y + (from.y - helicopter.y) * factor,
    }
    setRoute(soldierGroup, {
        { type = "Turning Point", action = "Off Road", x = from.x, y = from.y, speed = WALK_SPEED },
        { type = "Turning Point", action = "Off Road", x = target.x, y = target.y, speed = WALK_SPEED },
    })
end

local function landed(mission, unit, pilotPoint, now)
    local here = position(unit)
    local distance = math.floor(util.distance2D(here, pilotPoint) + 0.5)
    if distance <= BOARD_DISTANCE then
        pickUp(mission, unit)
    elseif distance <= cfg.csar.maxWalkDistance then
        mission.state = "boarding"
        mission.deadline = now + 120 + 2 * distance / WALK_SPEED
        walkTo(mission.soldier, pilotPoint, here)
        log:info("%s landed %d m from %s, the pilot walks over", mission.groupName, distance, mission.soldier)
        message(mission, string.format("SAR helicopter landed %d m from the pilot, he is walking over", distance))
    elseif mission.attempts < cfg.csar.landingAttempts then
        mission.attempts = mission.attempts + 1
        mission.airborne = false
        setRoute(mission.groupName,
            append({ turningPoint(here), rescueWaypoint(pilotPoint) }, homeWaypoints(mission.home)))
        log:info("%s landed %d m from %s, landing again", mission.groupName, distance, mission.soldier)
        message(mission, "SAR helicopter could not land near the pilot, it tries again")
    else
        fail(mission, unit, string.format("no landing site near the pilot (%d m away)", distance))
    end
end

local function checkMission(mission, now)
    local unit = Unit.getByName(mission.unitName)
    if unit == nil or not object.exists(unit) then
        if mission.state ~= "returning" then
            log:info("rescue %s failed: helicopter lost", mission.groupName)
            message(mission, "SAR mission failed: the helicopter was lost")
        end
        return false
    end
    if now - mission.started > cfg.csar.timeout then
        log:info("rescue %s took too long, removed", mission.groupName)
        tracker.destroyUnit(unit)
        return false
    end

    local inAir = object.call(unit, "inAir")
    if inAir == true then
        mission.airborne = true
    end
    local onGround = inAir == false and mission.airborne and speed(unit) < 1

    if mission.state == "returning" then
        local here = position(unit)
        if onGround and here and util.distance2D(here, mission.home) <= HOME_RADIUS then
            log:info("%s returned to base, removed", mission.groupName)
            tracker.destroyUnit(unit)
            return false
        end
        return true
    end

    local pilot = Unit.getByName(mission.soldier .. "-1")
    local pilotPoint = pilot and object.exists(pilot) and position(pilot)
    if not pilotPoint then
        fail(mission, unit, "the pilot was lost")
    elseif mission.state == "outbound" then
        -- setting down while hover taxiing at the airbase is no landing
        local here = position(unit)
        if onGround and (util.distance2D(here, mission.home) > START_RADIUS
            or util.distance2D(here, pilotPoint) <= cfg.csar.maxWalkDistance) then
            landed(mission, unit, pilotPoint, now)
        end
    elseif mission.state == "boarding" then
        if inAir == true then
            fail(mission, unit, "the helicopter left before the pilot arrived")
        elseif util.distance2D(position(unit), pilotPoint) <= BOARD_DISTANCE then
            pickUp(mission, unit)
        elseif now > mission.deadline then
            fail(mission, unit, "the pilot did not reach the helicopter")
        end
    end
    return true
end

--- One check of all running rescues.
function csar.check()
    local now = timer.getTime()
    for groupName, mission in pairs(missions) do
        if not checkMission(mission, now) then
            missions[groupName] = nil
        end
    end
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
    clearLandingZone(point)

    local start = (db.route(template) or {})[1]
    local data = db.groupData(template) or {}
    local home = start
        and { x = start.x, y = start.y, airdromeId = start.airdromeId, helipadId = start.helipadId, linkUnit = start.linkUnit }
        or { x = data.x, y = data.y }
    local route = append({ start }, append({ rescueWaypoint(point) }, homeWaypoints(home)))
    local options, needsStart, spot = startOptions(template, start, route)

    missionCounter = missionCounter + 1
    local groupName = string.format("SAR %s #%d", side.label(coalitionId), missionCounter)
    options.name = groupName
    rescueGroups[groupName] = true
    local group, err = spawn.clone(template, options)
    if group == nil then
        log:error("could not spawn rescue helicopter: %s", err)
        return nil
    end
    if needsStart then
        local controller = object.call(group, "getController")
        object.call(controller, "setCommand", { id = "Start", params = {} })
    end
    missions[groupName] = {
        groupName = groupName,
        unitName = object.name(object.call(group, "getUnit", 1)) or (groupName .. "-1"),
        coalition = coalitionId,
        soldier = soldierGroup,
        home = home,
        state = "outbound",
        airborne = false,
        attempts = 1,
        started = timer.getTime(),
    }
    trigger.action.outTextForCoalition(coalitionId,
        string.format("Pilot down, parachute spotted at %s. SAR mission started", util.formatPoint(point, 3)), 10)
    log:info("rescue %s sent for %s%s", groupName, soldierGroup,
        spot and string.format(" from parking spot %s", tostring(spot.Term_Index)) or "")
    return groupName, soldierGroup
end

function csar.isRescueGroup(groupName)
    return rescueGroups[groupName] == true
end

--- State of a running rescue ("outbound", "boarding", "returning") or nil.
function csar.state(groupName)
    local mission = missions[groupName]
    return mission and mission.state
end

-- Replaces a landed parachute by a soldier and sends the rescue.
local function replaceParachute(unit, coalitionId, countryId, point)
    local surface = land.getSurfaceType(point)
    object.destroy(unit)
    if surface == land.SurfaceType.LAND or surface == land.SurfaceType.ROAD or surface == land.SurfaceType.RUNWAY then
        csar.startMission(coalitionId, countryId, point)
    end
end

local function onParachuteLanded(event)
    local unit = event.initiator
    local coalitionId, countryId = pilotIdentity(unit)
    if templates[coalitionId] == nil then
        return
    end
    local point = position(unit)
    if point == nil then
        return
    end
    -- a second later, outside the event handler: DCS can trip over world
    -- changes made while it dispatches an event
    tarmac.scheduler.after(1, replaceParachute, unit, coalitionId, countryId, point)
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
        local name = cfg.csar.templates[side.name(coalitionId)]
        local record = name and db.group(name)
        if record and record.category == "helicopter" then
            templates[coalitionId] = name
            log:info("rescue template for %s pilots: %s", side.name(coalitionId), name)
        elseif name then
            log:info("no rescue helicopter group %s, no rescue missions for %s pilots", name, side.name(coalitionId))
        end
    end
    tarmac.events.on("LANDING_AFTER_EJECTION", onParachuteLanded)
    tarmac.events.on("KILL", onKill)
    tarmac.scheduler.every(CHECK_INTERVAL, csar.check, { delay = CHECK_INTERVAL, name = "industry.csar" })
end

return csar
