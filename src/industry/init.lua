--- Industry Wars - resource management, respawns and tickets for DCS World.
--
-- Load dist/industry.lua with DO SCRIPT FILE, then configure and start it
-- from the mission (e.g. an init.lua loaded right after it):
--   industry.setup({
--       startResources = 800,
--       respawn = { groups = { ["RedCAP-1"] = 400, ["TankPlatoonRed-1"] = {} } },
--   })
-- See README.md for all options and the mission editor conventions.

local existing = rawget(_G, "industry")
if existing ~= nil then
    env.warning("[industry] Industry is already loaded, the second copy is ignored", false)
    return existing
end

local tarmac = require("tarmac")
local config = require("industry.config")
local tickets = require("industry.tickets")
local economy = require("industry.economy")
local objectives = require("industry.objectives")
local production = require("industry.production")
local respawn = require("industry.respawn")
local logistics = require("industry.logistics")
local airfield = require("industry.airfield")
local csar = require("industry.csar")
local losses = require("industry.losses")
local menu = require("industry.menu")

local log = tarmac.log.new("industry")

local industry = {
    version = "2.0.0-dev",
    tarmac = tarmac,
    tickets = tickets,
    economy = economy,
    objectives = objectives,
    production = production,
    respawn = respawn,
    logistics = logistics,
    csar = csar,
    menu = menu,
}

local started = false

--- Starts Industry with the mission's configuration table.
function industry.setup(given)
    if started then
        log:warn("industry.setup() called more than once, ignored")
        return industry
    end
    started = true
    local cfg = config.build(given)
    industry.config = cfg

    tickets.setup(cfg)
    objectives.setup(cfg)
    local storages = {}
    for _, coalitionId in ipairs(tarmac.side.BOTH) do
        storages[coalitionId] = objectives.count(coalitionId, "storage")
    end
    economy.setup(cfg, storages)
    production.setup(cfg)
    respawn.setup(cfg)
    logistics.setup(cfg)
    airfield.setup(cfg)
    csar.setup(cfg)
    losses.setup(cfg)
    menu.setup()

    log:info("Industry %s started (Tarmac %s)", industry.version, tarmac.version)
    return industry
end

--- Called by the waypoint action that Industry adds to convoy routes.
function industry.convoyArrived(groupName)
    return logistics.convoyArrived(groupName)
end

--- Adds resources to a coalition ("red", "blue", 1 or 2).
function industry.addResources(coalitionId, tons, reason)
    return economy.add(coalitionId, tons, reason or "script")
end

--- Registers a group for respawn after setup (cost optional).
function industry.addRespawnGroup(groupName, cost)
    return respawn.register(groupName, cost)
end

--- Queues a group for respawn (cost optional, 0 = free).
function industry.queueRespawn(groupName, cost)
    return respawn.queue(groupName, cost)
end

_G.industry = industry

tarmac.scheduler.after(10, function()
    if not started then
        log:error("industry.setup() was not called, Industry is not running")
        trigger.action.outText("Industry is loaded but industry.setup() was not called", 30)
    end
end)

log:info("Industry %s loaded", industry.version)

return industry
