--- Reconnaissance. Enemy targets (objectives and air defence sites) appear
-- on the F10 map of a coalition only after someone spotted them and the
-- report reached the own HQ:
--   * AI units (intel.aiRecon) report what they see right away.
--   * Players get a hint and collect what they spotted in a recon package,
--     which they send to HQ with the F10 menu "HQ > Send recon report". The
--     package is lost with the aircraft or when the player leaves it.
--   * Without HQ a coalition is blind: when its last HQ is destroyed, all its
--     reports, packages and map marks are gone and nobody spots anything.
-- Whether an observer spots a target depends on the distance, the line of
-- sight over the terrain, the kind of observer (ground unit, aircraft,
-- reconnaissance aircraft, height above ground), daylight, visibility (fog,
-- dust) and clouds. Sightings, near misses and a periodic summary are
-- logged with the prefix [industry.intel], so dcs.log tells what was seen
-- and why something was not.

local tarmac = require("tarmac")
local objectives = require("industry.objectives")

local log = tarmac.log.new("industry.intel")
local side, util, db, object, marks, sight =
    tarmac.side, tarmac.util, tarmac.db, tarmac.object, tarmac.marks, tarmac.sight

local intel = {}

local cfg
local targets = {}                  -- [key] = target
local known = { [1] = {}, [2] = {} } -- [coalitionId][key] = report that reached HQ
local packages = {}                 -- [unitName] = recon package of a player
local hasHQ = { [1] = false, [2] = false }
local hqLost = { [1] = false, [2] = false }
local nearMisses = {}               -- [observer|target] = time of the last log line
local pendingGroups = {}            -- [groupName] = true while a birth check is scheduled
local crewless = {}                 -- [unitName] = true after the crew ejected or died
local stats = { checks = 0, pairs = 0, lineOfSight = 0, observers = { [1] = {}, [2] = {} } }

-- a target is looked at this many meters above its base
local STATIC_HEIGHT = 10
local VEHICLE_HEIGHT = 3
-- eye height of ground observers
local GROUND_EYE = 2
-- near misses are logged up to this factor beyond the range
local NEAR_MISS_FACTOR = 1.25
-- seconds before the same near miss (observer, target, reason) of an
-- aircraft is logged again; ground units do not move, theirs only once
local NEAR_MISS_REPEAT = 600

local THREAT_COLOR = { 1, 0, 0, 0.8 }
local THREAT_FILL = { 1, 0, 0, 0.08 }
local DESTROYED_COLOR = { 0.5, 0.5, 0.5, 0.8 }
local NO_FILL = { 0, 0, 0, 0 }

local objectiveLabels = {
    factory = "Factory", laboratory = "Laboratory", storage = "Storage", hq = "HQ", secondary = "Military target",
}

-- air defence classes by DCS attribute, first match wins
local airDefenceClasses = {
    { attribute = "LR SAM", label = "SAM site (long range)" },
    { attribute = "MR SAM", label = "SAM site (medium range)" },
    { attribute = "SR SAM", label = "SAM site (short range)" },
    { attribute = "AAA", label = "AAA site" },
    { attribute = "EWR", label = "Early warning radar" },
}

-- Helpers -------------------------------------------------------------------

local function clock(absTime)
    local seconds = math.floor(absTime or timer.getAbsTime()) % 86400
    return string.format("%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function distance3D(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- True bearing in degrees from one map point to another (x north, z east).
local function bearing(from, to)
    local degrees = math.deg(math.atan2(to.z - from.z, to.x - from.x))
    return math.floor(degrees + 0.5) % 360
end

local function km(meters)
    return string.format("%.1f km", meters / 1000)
end

local function raised(point, height)
    return { x = point.x, y = point.y + height, z = point.z }
end

-- Targets -------------------------------------------------------------------

local function groupPoint(groupName)
    local units = object.call(Group.getByName(groupName), "getUnits") or {}
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, unit in ipairs(units) do
        local p = object.point(unit)
        if p then
            sx, sy, sz, n = sx + p.x, sy + p.y, sz + p.z, n + 1
        end
    end
    if n == 0 then
        return nil
    end
    return { x = sx / n, y = sy / n, z = sz / n }
end

-- The air defence units of a group and the attributes that made them so.
local function airDefenceUnits(units)
    local found, attributes, seen = {}, {}, {}
    for _, unit in ipairs(units) do
        local isAirDefence = false
        for attribute, enabled in pairs(cfg.intel.airDefenceAttributes) do
            if enabled and object.call(unit, "hasAttribute", attribute) == true then
                isAirDefence = true
                if not seen[attribute] then
                    seen[attribute] = true
                    attributes[#attributes + 1] = attribute
                end
            end
        end
        if isAirDefence then
            found[#found + 1] = unit
        end
    end
    table.sort(attributes)
    return found, attributes
end

local function airDefenceClass(units)
    for _, class in ipairs(airDefenceClasses) do
        for _, unit in ipairs(units) do
            if object.call(unit, "hasAttribute", class.attribute) == true then
                return class
            end
        end
    end
    return { label = "Air defence site" }
end

-- Threat radius: the largest threat range of the air defence types in the
-- group (intel.threatRanges, the circles DCS draws in the mission editor).
-- A type missing there makes the class default the lower limit. Returns the
-- radius (nil for none) and where it came from.
local function threatRadius(units, class)
    local best, source, unknown, seen = 0, nil, {}, {}
    for _, unit in ipairs(units) do
        local typeName = object.typeName(unit)
        local range = typeName and cfg.intel.threatRanges[typeName]
        if type(range) == "number" then
            if range > best then
                best, source = range, typeName
            end
        elseif typeName and not seen[typeName] then
            seen[typeName] = true
            unknown[#unknown + 1] = typeName
        end
    end
    if #unknown > 0 then
        local default = class.attribute and cfg.intel.threatDefaults[class.attribute]
        if default and default > best then
            best, source = default, "default for " .. class.attribute
        end
        table.sort(unknown)
        source = (source or "no launcher") .. "; not in intel.threatRanges: " .. table.concat(unknown, ", ")
    end
    if best <= 0 then
        return nil, source or "no launcher"
    end
    return best, source
end

local function hasRadar(units)
    for _, unit in ipairs(units) do
        for attribute, enabled in pairs(cfg.intel.airDefenceRadars) do
            if enabled and object.call(unit, "hasAttribute", attribute) == true then
                return true
            end
        end
    end
    return false
end

-- Registers a ground group as target when it has an air defence radar or
-- consists mainly of air defence units (a convoy with one escort SAM is no
-- site). Returns the target or nil.
local function registerAirDefence(group)
    local groupName = object.name(group)
    local coalitionId = object.coalition(group)
    if groupName == nil or (coalitionId ~= side.RED and coalitionId ~= side.BLUE) then
        return nil
    end
    local units = object.call(group, "getUnits") or {}
    local defenders, attributes = airDefenceUnits(units)
    if #defenders == 0 then
        return nil
    end
    local radar = hasRadar(defenders)
    if not radar and #defenders < #units * cfg.intel.airDefenceShare then
        log:info("%s group %s has %d of %d units with air defence (%s) and no radar, it is no air defence site",
            side.name(coalitionId), groupName, #defenders, #units, table.concat(attributes, ", "))
        return nil
    end
    local class = airDefenceClass(defenders)
    local radius, source = threatRadius(defenders, class)
    local key = "group:" .. groupName
    local target = targets[key] or { key = key, kind = "airDefence", name = groupName, groupName = groupName }
    target.coalition = coalitionId
    target.label = class.label
    target.threat = radius
    target.height = VEHICLE_HEIGHT
    target.destroyed = false
    target.point = groupPoint(groupName)
    targets[key] = target
    log:info("%s air defence site %s: %s (%d of %d units, %s%s), threat ring %s (%s)", side.name(coalitionId),
        groupName, class.label, #defenders, #units, table.concat(attributes, ", "), radar and ", radar" or "",
        radius and km(radius) or "none", source)
    return target
end

local function registerObjective(entry)
    if entry.point == nil then
        log:warn("objective %s has no position, it cannot be spotted", entry.name)
        return
    end
    local key = "objective:" .. entry.name
    targets[key] = {
        key = key,
        kind = entry.kind,
        name = entry.name,
        coalition = entry.coalition,
        label = objectiveLabels[entry.kind] or entry.kind,
        point = entry.point,
        height = STATIC_HEIGHT,
        destroyed = entry.destroyed,
    }
end

-- Map marks -----------------------------------------------------------------

local function markText(target, report)
    if target.destroyed then
        return string.format("%s destroyed (spotted %s)", target.label, clock(report.seenAt))
    end
    return string.format("%s (spotted %s)", target.label, clock(report.seenAt))
end

local function draw(coalitionId, report)
    local target = report.target
    report.markId = marks.toCoalition(coalitionId, markText(target, report), report.point)
    if target.threat and cfg.intel.threatRings then
        report.ringId = marks.circle(coalitionId, report.point, target.threat, {
            color = target.destroyed and DESTROYED_COLOR or THREAT_COLOR,
            fill = target.destroyed and NO_FILL or THREAT_FILL,
            lineType = target.destroyed and 2 or 1,
        })
    end
end

local function erase(report)
    marks.remove(report.markId)
    marks.remove(report.ringId)
    report.markId, report.ringId = nil, nil
end

-- Packages ------------------------------------------------------------------

local function dropItem(package, key)
    local item = package.items[key]
    if item then
        marks.remove(item.markId)
        package.items[key] = nil
        package.count = package.count - 1
    end
end

local function dropPackage(unitName, reason)
    local package = packages[unitName]
    if package == nil then
        return
    end
    if package.count > 0 then
        log:info("%s: recon package of %s (%s) with %d targets lost: %s", side.name(package.coalition),
            tostring(package.playerName), unitName, package.count, reason)
    end
    for key in pairs(package.items) do
        dropItem(package, key)
    end
    packages[unitName] = nil
end

local function packageOf(observer)
    local package = packages[observer.name]
    if package and package.lost then
        dropPackage(observer.name, package.lost)
        package = nil
    end
    if package == nil then
        package = {
            unitName = observer.name,
            coalition = observer.coalition,
            groupId = observer.groupId,
            playerName = observer.player,
            items = {},
            count = 0,
        }
        packages[observer.name] = package
    end
    return package
end

-- Knowledge -----------------------------------------------------------------

--- Adds a sighting to what the HQ of a coalition knows and puts it on the
-- map. Returns false if it was known already.
local function learn(coalitionId, target, sighting)
    if known[coalitionId][target.key] then
        return false
    end
    local report = { target = target, seenAt = sighting.seenAt, point = sighting.point, by = sighting.by }
    known[coalitionId][target.key] = report
    draw(coalitionId, report)
    for _, package in pairs(packages) do
        if package.coalition == coalitionId then
            dropItem(package, target.key)
        end
    end
    return true
end

local function forget(target, reason)
    for _, coalitionId in ipairs(side.BOTH) do
        local report = known[coalitionId][target.key]
        if report then
            erase(report)
            known[coalitionId][target.key] = nil
            log:info("%s: report of %s %s removed: %s", side.name(coalitionId), target.label, target.name, reason)
        end
    end
    for _, package in pairs(packages) do
        dropItem(package, target.key)
    end
end

local function markDestroyed(target)
    if target.destroyed then
        return
    end
    target.destroyed = true
    for _, coalitionId in ipairs(side.BOTH) do
        local report = known[coalitionId][target.key]
        if report then
            marks.remove(report.markId)
            report.markId = marks.toCoalition(coalitionId, markText(target, report), report.point)
            if report.ringId then
                marks.setColor(report.ringId, DESTROYED_COLOR)
                marks.setFill(report.ringId, NO_FILL)
                marks.setLineType(report.ringId, 2)
            end
            log:info("%s: reported %s %s destroyed, map updated", side.name(coalitionId), target.label, target.name)
        end
    end
    for _, package in pairs(packages) do
        dropItem(package, target.key)
    end
end

-- HQ ------------------------------------------------------------------------

--- True while the coalition has an HQ (or never had one in the mission).
function intel.hqAlive(coalitionId)
    if not hasHQ[coalitionId] then
        return true
    end
    return not hqLost[coalitionId]
end

local function onHQLost(coalitionId)
    hqLost[coalitionId] = true
    local count = 0
    for _, report in pairs(known[coalitionId]) do
        erase(report)
        count = count + 1
    end
    known[coalitionId] = {}
    for unitName, package in pairs(packages) do
        if package.coalition == coalitionId then
            dropPackage(unitName, "HQ lost")
        end
    end
    log:info("%s lost its HQ: %d reports removed from the map, the coalition is blind now", side.name(coalitionId), count)
    if cfg.intel.enabled then
        trigger.action.outTextForCoalition(coalitionId, "HQ is not responding. All reconnaissance reports are lost.", 20)
    else
        trigger.action.outTextForCoalition(coalitionId, "HQ is not responding.", 20)
    end
    tarmac.events.emit("industry.hqLost", { coalition = coalitionId })
end

-- Observers -----------------------------------------------------------------

local function describeObserver(observer)
    if observer.player then
        return string.format("player %s (%s, %s, %s)", observer.player, observer.name, observer.typeName, observer.role)
    end
    return string.format("%s (%s, %s)", observer.name, observer.typeName, observer.role)
end

local function observerInfo(unit, coalitionId, playerName)
    local point = object.point(unit)
    local unitName = object.name(unit)
    -- a wreck whose crew is gone sees nothing, even with a player inside
    if point == nil or unitName == nil or crewless[unitName] then
        return nil
    end
    local typeName = object.typeName(unit) or "?"
    local category = object.unitCategory(unit)
    local observer = {
        unit = unit,
        name = unitName,
        groupName = object.groupName(unit),
        typeName = typeName,
        coalition = coalitionId,
        player = playerName,
        point = point,
    }
    if category == Unit.Category.AIRPLANE or category == Unit.Category.HELICOPTER then
        local record = db.group(observer.groupName or "")
        local task = record and record.data and record.data.task
        local recon = task == "Reconnaissance" or cfg.intel.reconTypes[typeName] == true
        observer.role = recon and "recon" or "aircraft"
        observer.height = sight.heightAboveGround(point)
        observer.ceiling = recon and cfg.intel.reconAltitude or cfg.intel.maxAltitude
        observer.eye = point
    else
        observer.role = "ground"
        observer.eye = raised(point, GROUND_EYE)
    end
    observer.factor = cfg.intel.observers[observer.role] or 1
    local light, elevation = sight.light(point)
    local lightFactor = cfg.intel.light[light] or 1
    if light ~= "day" and cfg.intel.nightVisionTypes[typeName] then
        lightFactor = math.max(lightFactor, cfg.intel.light.nightVision or lightFactor)
        light = light .. " with night vision"
    end
    observer.lightName, observer.elevation, observer.light = light, elevation, lightFactor
    observer.visibility = sight.visibility(observer.eye)
    if playerName then
        observer.groupId = object.call(object.group(unit), "getID")
    end
    return observer
end

local function collectObservers(coalitionId)
    local list = {}
    local counts = { players = 0, aircraft = 0, ground = 0 }
    for _, unit in ipairs(coalition.getPlayers(coalitionId) or {}) do
        local observer = observerInfo(unit, coalitionId, object.playerName(unit))
        if observer then
            list[#list + 1] = observer
            counts.players = counts.players + 1
        end
    end
    if cfg.intel.aiRecon then
        for _, group in ipairs(coalition.getGroups(coalitionId) or {}) do
            for _, unit in ipairs(object.call(group, "getUnits") or {}) do
                if object.playerName(unit) == nil and object.call(unit, "isActive") ~= false then
                    local observer = observerInfo(unit, coalitionId, nil)
                    if observer then
                        list[#list + 1] = observer
                        if observer.role == "ground" then
                            counts.ground = counts.ground + 1
                        else
                            counts.aircraft = counts.aircraft + 1
                        end
                    end
                end
            end
        end
    end
    stats.observers[coalitionId] = counts
    return list
end

-- Targets the coalition does not know yet, with their current position.
local function candidates(coalitionId)
    local enemy = side.enemy(coalitionId)
    local list = {}
    for key, target in pairs(targets) do
        if target.coalition == enemy and not target.destroyed and not known[coalitionId][key] then
            if target.groupName then
                target.point = groupPoint(target.groupName)
            end
            if target.point then
                target.view = raised(target.point, target.height)
                target.visibility = sight.visibility(target.view)
                list[#list + 1] = target
            end
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

-- Detection -----------------------------------------------------------------

local function rangeDetails(observer, target, range, clouds)
    return string.format("range %s [base %s, %s x%.1f, %s x%.2f (sun %.0f°), visibility %s, clouds %s]",
        km(range), km(cfg.intel.ranges[target.kind] or 0), observer.role, observer.factor, observer.lightName,
        observer.light, observer.elevation, km(math.min(observer.visibility, target.visibility)), clouds)
end

local function heightText(observer)
    if observer.height then
        return string.format(", %d m above ground", observer.height)
    end
    return ""
end

local function nearMiss(observer, target, reason, distance, range, clouds)
    if not cfg.intel.verbose then
        return
    end
    -- the units of a ground group see the same, one line per group is enough
    local who = observer.role == "ground" and (observer.groupName or observer.name) or observer.name
    local key = who .. "|" .. target.key .. "|" .. reason
    local now = timer.getTime()
    local last = nearMisses[key]
    if last and (observer.role == "ground" or now - last < NEAR_MISS_REPEAT) then
        return
    end
    nearMisses[key] = now
    log:info("%s: %s did not spot %s %s at %s: %s, %s%s", side.name(observer.coalition), describeObserver(observer),
        target.label, target.name, km(distance), reason, rangeDetails(observer, target, range, clouds), heightText(observer))
end

-- Returns true and the distance when the observer sees the target.
local function sees(observer, target)
    local reach = (cfg.intel.ranges[target.kind] or 5000) * observer.factor
    local distance = distance3D(observer.eye, target.view)
    if distance > reach * NEAR_MISS_FACTOR then
        return false
    end
    stats.pairs = stats.pairs + 1
    local range = math.min(reach * observer.light, observer.visibility, target.visibility)
    local clouds = sight.cloudCover(observer.eye, target.view)
    if clouds == "broken" then
        range = range * cfg.intel.brokenClouds
    end
    if distance > range then
        if distance <= range * NEAR_MISS_FACTOR then
            nearMiss(observer, target, "just out of range", distance, range, clouds)
        end
        return false
    end
    if clouds == "overcast" then
        nearMiss(observer, target, "clouds in between", distance, range, clouds)
        return false
    end
    if observer.ceiling and observer.height > observer.ceiling then
        nearMiss(observer, target, string.format("too high (limit %d m)", observer.ceiling), distance, range, clouds)
        return false
    end
    stats.lineOfSight = stats.lineOfSight + 1
    if not sight.lineOfSight(observer.eye, target.view) then
        nearMiss(observer, target, "terrain blocks the view", distance, range, clouds)
        return false
    end
    log:info("%s: %s spotted %s %s at %s, %s%s", side.name(observer.coalition), describeObserver(observer),
        target.label, target.name, km(distance), rangeDetails(observer, target, range, clouds), heightText(observer))
    return true, distance
end

local function notifyPlayer(observer, spotted)
    local lines = {}
    for _, entry in ipairs(spotted) do
        lines[#lines + 1] = string.format("Recon: %s spotted, bearing %03d for %d km.", entry.target.label,
            bearing(observer.point, entry.target.point), math.floor(entry.distance / 1000 + 0.5))
    end
    lines[#lines + 1] = "Send your recon report to HQ (F10 > HQ)."
    trigger.action.outTextForGroup(observer.groupId, table.concat(lines, "\n"), 15)
end

local function announceReports(coalitionId, labels)
    local text
    if #labels <= 3 then
        text = "HQ: New reconnaissance on the map: " .. table.concat(labels, ", ") .. "."
    else
        text = string.format("HQ: Our forces reported %d new targets, see the map.", #labels)
    end
    trigger.action.outTextForCoalition(coalitionId, text, 10)
end

local function cleanupPackages()
    for unitName, package in pairs(packages) do
        local reason = package.lost
        if reason == nil then
            local unit = Unit.getByName(unitName)
            if unit == nil or not object.exists(unit) then
                reason = "aircraft lost"
            elseif object.playerName(unit) ~= package.playerName then
                reason = "player left the aircraft"
            end
        end
        if reason then
            dropPackage(unitName, reason)
        end
    end
end

local function checkCoalition(coalitionId)
    if not intel.hqAlive(coalitionId) then
        return
    end
    local list = candidates(coalitionId)
    local observers = collectObservers(coalitionId)
    if #list == 0 then
        return
    end
    local reported = {}
    local now = timer.getAbsTime()
    for _, observer in ipairs(observers) do
        local spotted = {}
        for _, target in ipairs(list) do
            local package = observer.player and packages[observer.name]
            local pending = package and not package.lost and package.items[target.key]
            if not known[coalitionId][target.key] and not pending then
                local seen, distance = sees(observer, target)
                if seen then
                    local sighting = { seenAt = now, point = target.point, by = describeObserver(observer) }
                    if observer.player then
                        local own = packageOf(observer)
                        own.items[target.key] = {
                            target = target,
                            seenAt = now,
                            point = target.point,
                            by = sighting.by,
                            markId = marks.toGroup(own.groupId, string.format("%s spotted %s, not reported",
                                target.label, clock(now)), target.point),
                        }
                        own.count = own.count + 1
                        spotted[#spotted + 1] = { target = target, distance = distance }
                    elseif learn(coalitionId, target, sighting) then
                        log:info("%s: reported to HQ by %s", side.name(coalitionId), sighting.by)
                        reported[#reported + 1] = target.label
                    end
                end
            end
        end
        if #spotted > 0 then
            notifyPlayer(observer, spotted)
        end
    end
    if #reported > 0 then
        announceReports(coalitionId, reported)
    end
end

--- One check of what every observer of both coalitions can see.
function intel.check()
    stats.checks = stats.checks + 1
    cleanupPackages()
    for _, coalitionId in ipairs(side.BOTH) do
        checkCoalition(coalitionId)
    end
end

-- Reports from players ------------------------------------------------------

--- Sends the recon packages of all players in a group to their HQ (F10
-- menu). Returns the number of targets that were new to the HQ.
function intel.report(groupName, groupId, coalitionId)
    if not intel.hqAlive(coalitionId) then
        trigger.action.outTextForGroup(groupId, "HQ is not responding.", 10)
        return 0
    end
    local new, already, senders = 0, 0, {}
    for _, unit in ipairs(object.call(Group.getByName(groupName), "getUnits") or {}) do
        local unitName = object.name(unit)
        local package = unitName and packages[unitName]
        if package and package.lost then
            dropPackage(unitName, package.lost)
        elseif package and package.count > 0 then
            senders[#senders + 1] = string.format("%s (%s)", tostring(package.playerName), unitName)
            for key, item in pairs(package.items) do
                if learn(coalitionId, item.target, item) then
                    new = new + 1
                else
                    already = already + 1
                end
                dropItem(package, key)
            end
        end
    end
    if #senders == 0 then
        trigger.action.outTextForGroup(groupId, "HQ: Copy, nothing new to report.", 10)
        log:info("%s: %s sent an empty recon report", side.name(coalitionId), groupName)
        return 0
    end
    local text = string.format("HQ: Recon report received, %d new %s on the map", new, new == 1 and "target" or "targets")
    if already > 0 then
        text = text .. string.format(", %d already known", already)
    end
    trigger.action.outTextForGroup(groupId, text .. ".", 10)
    log:info("%s: %s reported to HQ: %d new, %d already known", side.name(coalitionId), table.concat(senders, ", "),
        new, already)
    return new
end

-- Queries -------------------------------------------------------------------

--- Reports the HQ of a coalition has, by target key.
function intel.known(coalitionId)
    return known[coalitionId]
end

--- The recon package of a player unit, or nil.
function intel.package(unitName)
    return packages[unitName]
end

--- All targets, by key ("objective:<unit name>", "group:<group name>").
function intel.targets()
    return targets
end

-- Summary -------------------------------------------------------------------

local function referencePoint()
    local sx, sz, n = 0, 0, 0
    for _, target in pairs(targets) do
        if target.point then
            sx, sz, n = sx + target.point.x, sz + target.point.z, n + 1
        end
    end
    if n == 0 then
        return { x = 0, y = 0, z = 0 }
    end
    return util.vec3({ x = sx / n, y = sz / n })
end

--- Writes a summary of the reconnaissance to dcs.log.
function intel.summary()
    log:info("summary at %s: %s; %d checks, %d observer/target pairs near enough to evaluate, %d line of sight tests",
        clock(), sight.describe(referencePoint()), stats.checks, stats.pairs, stats.lineOfSight)
    for _, coalitionId in ipairs(side.BOTH) do
        local enemy = side.enemy(coalitionId)
        local total, destroyed, reported = 0, 0, 0
        for key, target in pairs(targets) do
            if target.coalition == enemy then
                total = total + 1
                if target.destroyed then
                    destroyed = destroyed + 1
                end
                if known[coalitionId][key] then
                    reported = reported + 1
                end
            end
        end
        local packageCount, items = 0, 0
        for _, package in pairs(packages) do
            if package.coalition == coalitionId and package.count > 0 then
                packageCount, items = packageCount + 1, items + package.count
            end
        end
        local observers = stats.observers[coalitionId]
        log:info("summary %s: HQ %s, observers %d players / %d AI aircraft / %d ground, %d of %d enemy targets "
            .. "reported (%d enemy targets destroyed), %d recon packages with %d targets not reported",
            side.name(coalitionId), intel.hqAlive(coalitionId) and (hasHQ[coalitionId] and "ok" or "none in the mission")
            or "lost", observers.players or 0, observers.aircraft or 0, observers.ground or 0, reported, total, destroyed,
            packageCount, items)
    end
    stats.checks, stats.pairs, stats.lineOfSight = 0, 0, 0
end

-- Setup ---------------------------------------------------------------------

-- A group was born (respawn, late activation, spawn): register air defence
-- sites a second later, when all units exist.
local function checkGroup(groupName)
    pendingGroups[groupName] = nil
    local old = targets["group:" .. groupName]
    if old and not old.destroyed then
        return
    end
    if old then
        forget(old, "the site was rebuilt and must be found again")
    end
    local group = Group.getByName(groupName)
    if group then
        registerAirDefence(group)
    end
end

local function onBirth(event)
    local unit = event.initiator
    local unitName = object.name(unit)
    if unitName and packages[unitName] then
        packages[unitName].lost = "new aircraft"
    end
    if unitName then
        crewless[unitName] = nil
    end
    if object.unitCategory(unit) ~= Unit.Category.GROUND_UNIT then
        return
    end
    local groupName = object.groupName(unit)
    if groupName and not pendingGroups[groupName] then
        local old = targets["group:" .. groupName]
        if old == nil or old.destroyed then
            pendingGroups[groupName] = true
            tarmac.scheduler.after(1, checkGroup, groupName)
        end
    end
end

local function onPlayerGone(event)
    local unitName = object.name(event.initiator)
    local package = unitName and packages[unitName]
    if package and not package.lost then
        package.lost = event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT and "player left the aircraft" or "aircraft lost"
    end
end

local function onCrewGone(event)
    local unitName = object.name(event.initiator)
    if unitName and object.isAircraft(event.initiator) and not crewless[unitName] then
        crewless[unitName] = true
        log:info("crew of %s is gone (%s), it no longer observes", unitName, tarmac.events.nameOf(event.id))
    end
end

local function setupHQ()
    for _, coalitionId in ipairs(side.BOTH) do
        hasHQ[coalitionId] = objectives.remaining(coalitionId, "hq") > 0
        if not hasHQ[coalitionId] then
            log:warn("%s has no HQ objective, its reconnaissance works without HQ", side.name(coalitionId))
        end
    end
    tarmac.events.on("industry.objectiveDestroyed", function(event)
        local target = targets["objective:" .. event.name]
        if target then
            markDestroyed(target)
        end
        local coalitionId = event.coalition
        if event.kind == "hq" and hasHQ[coalitionId] and not hqLost[coalitionId]
                and objectives.remaining(coalitionId, "hq") == 0 then
            onHQLost(coalitionId)
        end
    end)
end

function intel.setup(configuration)
    cfg = configuration
    setupHQ()
    if not cfg.intel.enabled then
        log:info("reconnaissance is off, enemy objectives are marked from the start")
        return
    end
    for _, entry in ipairs(objectives.all()) do
        registerObjective(entry)
    end
    for _, coalitionId in ipairs(side.BOTH) do
        for _, group in ipairs(coalition.getGroups(coalitionId, Group.Category.GROUND) or {}) do
            registerAirDefence(group)
        end
    end
    for _, coalitionId in ipairs(side.BOTH) do
        local counts = {}
        for _, target in pairs(targets) do
            if target.coalition == coalitionId then
                counts[target.kind] = (counts[target.kind] or 0) + 1
            end
        end
        local parts = {}
        for _, kind in ipairs(util.keys(counts)) do
            parts[#parts + 1] = string.format("%d %s", counts[kind], kind)
        end
        log:info("%s targets to be found by %s: %s", side.name(coalitionId), side.name(side.enemy(coalitionId)),
            #parts > 0 and table.concat(parts, ", ") or "none")
    end
    local i = cfg.intel
    log:info("reconnaissance on: AI recon %s, check every %d s, ranges factory %s / laboratory %s / storage %s / "
        .. "hq %s / secondary %s / air defence %s, observers ground x%.1f / aircraft x%.1f / recon x%.1f, "
        .. "height limit %d m (recon %d m)", i.aiRecon and "on" or "off", i.interval, km(i.ranges.factory),
        km(i.ranges.laboratory), km(i.ranges.storage), km(i.ranges.hq), km(i.ranges.secondary), km(i.ranges.airDefence),
        i.observers.ground, i.observers.aircraft, i.observers.recon, i.maxAltitude, i.reconAltitude)
    log:info("environment at start: %s", sight.describe(referencePoint()))

    tarmac.events.on("tarmac.groupDead", function(event)
        local target = targets["group:" .. tostring(event.groupName)]
        if target then
            markDestroyed(target)
        end
    end)
    tarmac.events.on("BIRTH", onBirth)
    for _, name in ipairs({ "EJECTION", "PILOT_DEAD", "CRASH", "UNIT_LOST", "PLAYER_LEAVE_UNIT" }) do
        tarmac.events.on(name, onPlayerGone)
    end
    tarmac.events.on("EJECTION", onCrewGone)
    tarmac.events.on("PILOT_DEAD", onCrewGone)
    tarmac.scheduler.every(i.interval, intel.check, { delay = i.interval, name = "industry.intel" })
    tarmac.scheduler.every(i.summaryInterval, intel.summary, { delay = i.summaryInterval, name = "industry.intel.summary" })
end

return intel
