--- Resources (tons) per coalition. Storages limit how much can be held.

local tarmac = require("tarmac")

local log = tarmac.log.new("industry.economy")
local side = tarmac.side

local economy = {}

local cfg
local resources = { [1] = 0, [2] = 0 }
local storages = { [1] = 0, [2] = 0 }

function economy.capacity(coalitionId)
    return storages[coalitionId] * cfg.production.storageCapacity
end

function economy.resources(coalitionId)
    return resources[side.id(coalitionId)] or 0
end

function economy.storages(coalitionId)
    return storages[side.id(coalitionId)] or 0
end

function economy.setStorages(coalitionId, amount)
    storages[coalitionId] = amount
end

--- Adds tons to a coalition (id or name), limited by storage capacity.
-- Returns the amount actually stored.
function economy.add(coalitionId, tons, reason)
    local id = side.id(coalitionId)
    if resources[id] == nil then
        log:warn("cannot add resources to unknown coalition %s (%s)", coalitionId, reason)
        return 0
    end
    local before = resources[id]
    resources[id] = math.max(resources[id] + tons, 0)
    local capacity = economy.capacity(id)
    if resources[id] > capacity then
        resources[id] = capacity
        trigger.action.outText(string.format("Storages of %s are full", side.name(id)), 3)
    end
    log:info("%s %+d tons (%s), now %d", side.name(id), resources[id] - before, reason, resources[id])
    return resources[id] - before
end

function economy.canAfford(coalitionId, tons)
    return economy.resources(coalitionId) >= tons
end

--- Removes tons if available. Returns true on success.
function economy.spend(coalitionId, tons, reason)
    local id = side.id(coalitionId)
    if not economy.canAfford(id, tons) then
        return false
    end
    resources[id] = resources[id] - tons
    log:info("%s spent %d tons (%s), now %d", side.name(id), tons, reason, resources[id])
    return true
end

--- A storage was destroyed: the resources it held are lost. Resources are
-- spread evenly over all storages that existed before the loss.
function economy.storageLost(coalitionId, storagesBefore)
    if storagesBefore <= 0 then
        return 0
    end
    local lost = math.floor(resources[coalitionId] / storagesBefore)
    resources[coalitionId] = resources[coalitionId] - lost
    storages[coalitionId] = storagesBefore - 1
    return lost
end

function economy.setup(configuration, initialStorages)
    cfg = configuration
    for _, id in ipairs(side.BOTH) do
        resources[id] = cfg.startResources
        storages[id] = initialStorages[id] or 0
    end
end

return economy
