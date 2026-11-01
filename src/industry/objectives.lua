--- Strategic objectives: static objects whose unit name starts with one of
-- the configured prefixes (Factory, Laboratory, Storage, HQ, Secondary).
-- They are registered once at setup with their coalition, so destruction
-- events can be handled even when the object itself is already gone.

local tarmac = require("tarmac")
local economy = require("industry.economy")
local tickets = require("industry.tickets")

local log = tarmac.log.new("industry.objectives")
local side, util, object = tarmac.side, tarmac.util, tarmac.object

local objectives = {}

local cfg
local registry = {} -- [unitName] = { name, kind, coalition, point, markId, destroyed }

objectives.kinds = { "factory", "laboratory", "storage", "hq", "secondary" }

local flagNames = {
    factory = "Factory", laboratory = "Laboratory", storage = "Storage", hq = "HQ", secondary = "Secondary",
}

local markTexts = {
    factory = "Factory of %s producing resources (secondary target)",
    laboratory = "Laboratory of %s boosting factory production",
    storage = "Storage of %s for resources (primary target)",
    hq = "HQ of %s",
    secondary = "Operative target of %s (optional target)",
}

local smokeDensity = { factory = 0.75, laboratory = 0.5, storage = 0.5, hq = 0.5, secondary = 0.75 }

--- Kind of objective for a static name, or nil.
function objectives.classify(name)
    for _, kind in ipairs(objectives.kinds) do
        if util.startsWith(name, cfg.objectives.prefixes[kind]) then
            return kind
        end
    end
    return nil
end

function objectives.get(name)
    return registry[name]
end

-- Names of the statics of a coalition that still work (life above 1).
local function workingStatics(coalitionId)
    local names = {}
    for _, static in ipairs(coalition.getStaticObjects(coalitionId) or {}) do
        local life = object.life(static)
        if life ~= nil and life > 1 then
            local name = object.name(static)
            if name then
                names[name] = true
            end
        end
    end
    return names
end

--- Number of operational objectives of a kind: not destroyed and not
-- heavily damaged.
function objectives.count(coalitionId, kind)
    local working = workingStatics(coalitionId)
    local n = 0
    for name, entry in pairs(registry) do
        if entry.coalition == coalitionId and entry.kind == kind and not entry.destroyed and working[name] then
            n = n + 1
        end
    end
    return n
end

--- Number of objectives of a kind that have not been destroyed.
function objectives.remaining(coalitionId, kind)
    local n = 0
    for _, entry in pairs(registry) do
        if entry.coalition == coalitionId and entry.kind == kind and not entry.destroyed then
            n = n + 1
        end
    end
    return n
end

local function penalty(entry)
    local costs = cfg.objectives.ticketCosts
    local coalitionId, kind = entry.coalition, entry.kind
    if kind == "storage" then
        local before = objectives.remaining(coalitionId, "storage") + 1
        local share = math.ceil(tickets.get(coalitionId) / before)
        economy.storageLost(coalitionId, before)
        tickets.reduce(coalitionId, share, "storage " .. entry.name .. " destroyed")
        if before - 1 == 0 then
            trigger.action.outText(string.format("All %s storages have been destroyed", side.name(coalitionId)), 10)
        else
            trigger.action.outText(string.format("A %s storage has been destroyed. %d tons resources left",
                side.name(coalitionId), economy.resources(coalitionId)), 10)
        end
    elseif kind == "hq" then
        local amount = math.floor(tickets.get(coalitionId) * costs.hqFraction)
        tickets.reduce(coalitionId, amount, "HQ " .. entry.name .. " destroyed")
    else
        tickets.reduce(coalitionId, costs[kind] or 0, kind .. " " .. entry.name .. " destroyed")
    end
end

local destroyedMessages = {
    factory = "Factory of %s coalition destroyed",
    laboratory = "Laboratory of %s coalition destroyed",
    hq = "HQ of %s coalition destroyed",
    secondary = "Secondary Target of %s coalition destroyed",
}

--- Handles the destruction of an objective (once).
function objectives.destroyed(name)
    local entry = registry[name]
    if entry == nil or entry.destroyed then
        return false
    end
    entry.destroyed = true
    log:info("%s objective %s (%s) destroyed", side.name(entry.coalition), name, entry.kind)

    tarmac.marks.remove(entry.markId)
    if entry.point then
        -- a second later, outside the event handler: DCS can trip over
        -- world changes made while it dispatches an event
        tarmac.scheduler.after(1, trigger.action.effectSmokeBig, entry.point, 3, smokeDensity[entry.kind])
    end
    trigger.action.setUserFlag(name .. "_destroyed", true)
    trigger.action.setUserFlag(side.name(entry.coalition) .. flagNames[entry.kind] .. "Destroyed", true)
    if destroyedMessages[entry.kind] then
        trigger.action.outText(string.format(destroyedMessages[entry.kind], side.name(entry.coalition)), 10)
    end
    penalty(entry)
    tarmac.events.emit("industry.objectiveDestroyed", { name = name, kind = entry.kind, coalition = entry.coalition })
    return true
end

--- All objectives, sorted by name.
function objectives.all()
    local list = {}
    for _, entry in pairs(registry) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function onLoss(event)
    local name = object.name(event.initiator)
    if name and registry[name] then
        objectives.destroyed(name)
    end
end

function objectives.setup(configuration)
    cfg = configuration
    local counts = {}
    for _, coalitionId in ipairs(side.BOTH) do
        for _, static in ipairs(coalition.getStaticObjects(coalitionId) or {}) do
            local name = object.name(static)
            local kind = objectives.classify(name)
            if kind then
                local entry = {
                    name = name,
                    kind = kind,
                    coalition = coalitionId,
                    point = object.point(static),
                    destroyed = false,
                }
                -- with reconnaissance, objectives appear on the map once they are reported
                if cfg.objectives.markers and not cfg.intel.enabled and entry.point then
                    entry.markId = tarmac.marks.toCoalition(side.enemy(coalitionId),
                        string.format(markTexts[kind], side.name(coalitionId)), entry.point)
                end
                registry[name] = entry
                counts[kind] = (counts[kind] or 0) + 1
            end
        end
    end
    for _, kind in ipairs(objectives.kinds) do
        log:info("%d %s objectives", counts[kind] or 0, kind)
    end
    tarmac.events.on("UNIT_LOST", onLoss)
    tarmac.events.on("DEAD", onLoss)
end

return objectives
