--- Production cycle: factories produce resources, laboratories boost the
-- production, storages limit what can be kept.

local tarmac = require("tarmac")
local economy = require("industry.economy")
local objectives = require("industry.objectives")

local side = tarmac.side

local production = {}

local cfg
local lastReport = {}

--- Runs one production cycle for both coalitions.
function production.run()
    trigger.action.outText("Industry resources arrived", 5)
    for _, coalitionId in ipairs(side.BOTH) do
        local factories = objectives.count(coalitionId, "factory")
        local labs = objectives.count(coalitionId, "laboratory")
        local storages = objectives.count(coalitionId, "storage")

        local produced = cfg.production.base + cfg.production.perFactory * factories
        local bonus = math.floor(produced * cfg.production.labBoost / 100 * labs)

        economy.setStorages(coalitionId, storages)
        economy.add(coalitionId, produced + bonus, "production")
        lastReport[coalitionId] = { factories = factories, labs = labs, storages = storages }

        trigger.action.outText(string.format("New resources produced %s %d tons + %d labs-bonus",
            side.name(coalitionId), produced, bonus), 10)
    end
end

--- Counts of the last production cycle: { factories, labs, storages }.
function production.report(coalitionId)
    return lastReport[coalitionId] or {
        factories = objectives.count(coalitionId, "factory"),
        labs = objectives.count(coalitionId, "laboratory"),
        storages = objectives.count(coalitionId, "storage"),
    }
end

function production.setup(configuration)
    cfg = configuration
    tarmac.scheduler.every(cfg.production.interval, production.run, { delay = 1, name = "industry.production" })
end

return production
