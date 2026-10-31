--- Respawning of AI groups for resources.
-- A registered group is queued when its last unit is lost (tarmac tracker).
-- Each coalition has two FIFO queues: one for groups that cost resources
-- and one for free respawns. The paid queue is strictly ordered on purpose:
-- an expensive group at the head waits until it can be paid, otherwise
-- cheap groups would use up all resources and expensive ones never return.
-- A queued group only respawns once DCS has removed it from the world (no
-- respawn of wrecks still falling from the sky); after the configured
-- number of retries the respawn is forced.

local tarmac = require("tarmac")
local Queue = require("industry.queue")
local economy = require("industry.economy")

local log = tarmac.log.new("industry.respawn")
local side, db, tracker, object = tarmac.side, tarmac.db, tarmac.tracker, tarmac.object

local respawn = {}

local cfg
local registered = {} -- [groupName] = cost
local paid = { [1] = Queue.new(), [2] = Queue.new() }
local free = { [1] = Queue.new(), [2] = Queue.new() }
local modifiers = {}

--- Registers a group for automatic respawn. cost is a number, a table
-- { cost = n } or nil for the category default.
function respawn.register(groupName, cost)
    if type(cost) == "table" then
        cost = cost.cost
    end
    local record = db.group(groupName)
    if record == nil then
        log:error("respawn group %s does not exist in the mission", groupName)
        return false
    end
    if cost == nil then
        cost = cfg.respawn.costs[record.category] or 0
    end
    registered[groupName] = cost
    return true
end

function respawn.isRegistered(groupName)
    return registered[groupName] ~= nil
end

function respawn.cost(groupName)
    return registered[groupName]
end

--- Registers a function(groupName, options) that may adjust the spawn
-- options (e.g. the route) before a group respawns.
function respawn.addModifier(fn)
    modifiers[#modifiers + 1] = fn
end

local function coalitionOf(groupName)
    local record = db.group(groupName)
    return record and record.coalition
end

--- Queues a group. cost defaults to the registered cost; a cost of 0 uses
-- the free queue. Returns true if the group was queued.
function respawn.queue(groupName, cost)
    local coalitionId = coalitionOf(groupName)
    if coalitionId ~= side.RED and coalitionId ~= side.BLUE then
        log:warn("cannot queue %s: unknown coalition", groupName)
        return false
    end
    cost = cost or registered[groupName] or 0
    local queue = cost > 0 and paid[coalitionId] or free[coalitionId]
    if paid[coalitionId]:contains(groupName) or free[coalitionId]:contains(groupName) then
        return false
    end
    queue:push({ name = groupName, cost = cost, tries = 0 })
    log:info("queued %s for %d tons", groupName, cost)
    return true
end

function respawn.queued(coalitionId)
    return { paid = paid[coalitionId]:list(), free = free[coalitionId]:list() }
end

local function spawnGroup(entry)
    local options = {}
    for _, modify in ipairs(modifiers) do
        modify(entry.name, options)
    end
    local group, err = tarmac.spawn.respawn(entry.name, options)
    if group == nil then
        log:error("respawn of %s failed: %s", entry.name, err)
        return false
    end
    trigger.action.setUserFlag(entry.name .. "_respawned", true)
    tarmac.events.emit("industry.respawned", { groupName = entry.name, group = group })
    return true
end

local function runPaid(coalitionId)
    local queue = paid[coalitionId]
    local entry = queue:peek()
    if entry == nil then
        return
    end
    if not tracker.isGone(entry.name) and entry.tries < cfg.respawn.retries then
        entry.tries = entry.tries + 1
        log:info("%s still exists, respawn retry %d", entry.name, entry.tries)
        return
    end
    if not economy.canAfford(coalitionId, entry.cost) then
        return
    end
    queue:pop()
    if spawnGroup(entry) then
        economy.spend(coalitionId, entry.cost, "respawn " .. entry.name)
        trigger.action.outText(string.format("Respawned %s group %s for %d tons of resources",
            side.name(coalitionId), entry.name, entry.cost), 10)
    end
end

local function runFree(coalitionId)
    local entry = free[coalitionId]:pop()
    if entry and spawnGroup(entry) then
        trigger.action.outText(string.format("Respawned %s group %s", side.name(coalitionId), entry.name), 10)
    end
end

--- One respawn cycle: at most one paid and one free group per coalition.
function respawn.run()
    for _, coalitionId in ipairs(side.BOTH) do
        runPaid(coalitionId)
        runFree(coalitionId)
    end
end

--- Queues registered groups that are gone without the tracker noticing,
-- e.g. AI that despawned after an emergency landing.
function respawn.collectDead()
    for groupName in pairs(registered) do
        if tracker.isGone(groupName) then
            if respawn.queue(groupName) then
                log:info("found unhandled dead group %s", groupName)
            end
        end
    end
end

-- A pilot ejected from an aircraft of a respawn group: make sure the
-- aircraft is destroyed so the group can respawn (helicopters that landed
-- damaged would otherwise stay forever).
local function onEjection(event)
    local unit = event.initiator
    local groupName = object.groupName(unit)
    if groupName == nil then
        local record = db.unit(object.name(unit) or "")
        groupName = record and record.groupName
    end
    if groupName and registered[groupName] then
        local point = object.point(unit)
        if point then
            trigger.action.explosion(point, 400)
            log:info("pilot ejected from %s, aircraft destroyed", tostring(object.name(unit)))
        end
    end
end

function respawn.setup(configuration)
    cfg = configuration
    for groupName, cost in pairs(cfg.respawn.groups) do
        respawn.register(groupName, cost)
    end
    tarmac.events.on("tarmac.groupDead", function(event)
        if registered[event.groupName] ~= nil then
            respawn.queue(event.groupName)
        end
    end)
    tarmac.events.on("EJECTION", onEjection)
    tarmac.scheduler.every(cfg.respawn.interval, respawn.run, {
        delay = math.min(35, cfg.respawn.interval), name = "industry.respawn",
    })
    tarmac.scheduler.every(cfg.respawn.deadCheckInterval, respawn.collectDead, {
        delay = cfg.respawn.deadCheckInterval + 4, name = "industry.respawn.collectDead",
    })
end

return respawn
