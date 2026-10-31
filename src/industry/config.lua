--- Default configuration and merging of the mission's configuration table.
-- The mission passes one table to industry.setup(); everything not given
-- falls back to the defaults below. Unknown keys are reported in dcs.log,
-- which catches typos early.

local tarmac = require("tarmac")

local log = tarmac.log.new("industry.config")

local config = {}

config.defaults = {
    -- tons of resources each coalition starts with
    startResources = 200,

    tickets = {
        start = 100,
        -- both coalitions lose one ticket every interval seconds
        interval = 60,
        -- flags ticketsLowRed / ticketsLowBlue are set below this value
        low = 20,
        -- seconds between the end of the war and loading the next mission
        winCountdown = 600,
    },

    production = {
        interval = 300,
        perFactory = 30,
        -- added once per cycle on top of all factories
        base = 1,
        -- percent of the factory production added per laboratory
        labBoost = 20,
        storageCapacity = 1000,
    },

    respawn = {
        interval = 60,
        -- respawn is forced after this many loops even if a wreck still exists
        retries = 2,
        -- garbage collection for groups that vanished without events
        deadCheckInterval = 300,
        -- default respawn costs in tons per group category
        costs = { plane = 200, helicopter = 200, vehicle = 50, ship = 400 },
        -- groups that respawn: ["Name"] = cost or { cost = 200 } or {}
        groups = {},
        -- AI aircraft that shut down their engines are removed (parking space)
        despawnLandedAI = true,
    },

    logistics = {
        -- group name prefixes; matching groups respawn for free
        convoyPrefix = "Convoy",
        transportPrefix = "Transport",
        -- tons per surviving truck when a convoy reaches its last waypoint
        tonsPerTruck = 100,
        -- unit types counted as trucks; nil uses the DCS attribute "Trucks"
        truckTypes = nil,
        -- tons per transport aircraft that lands and shuts down its engines
        tonsPerTransport = 800,
        -- per group overrides: ["Name"] = { role = "convoy"|"transport", tons = 150 }
        groups = {},
    },

    objectives = {
        prefixes = {
            factory = "Factory",
            laboratory = "Laboratory",
            storage = "Storage",
            hq = "HQ",
            secondary = "Secondary",
        },
        -- tickets lost when an objective is destroyed; storages cost a share
        -- of the remaining tickets, an HQ the given fraction of them
        ticketCosts = { factory = 10, laboratory = 5, secondary = 1, hqFraction = 0.5 },
        -- mark enemy objectives on the F10 map
        markers = true,
    },

    losses = {
        -- tickets lost when a player aircraft is destroyed
        playerTickets = 1,
        -- burning wrecks for destroyed ground vehicles
        vehicleSmoke = true,
    },

    csar = {
        enabled = true,
        -- helicopter groups with this prefix are the rescue templates
        templatePrefix = "TPL-SAR",
        -- scenery objects removed around the landing point, in meters
        clearRadius = 50,
        -- tickets lost by the coalition of a player that shoots down a rescue helicopter
        killTickets = 1,
    },
}

-- Tables whose keys are chosen by the mission designer.
local openTables = {
    ["respawn.groups"] = true,
    ["logistics.groups"] = true,
}

local function checkKeys(given, defaults, path)
    for key, value in pairs(given) do
        local keyPath = path and (path .. "." .. tostring(key)) or tostring(key)
        local default = defaults and defaults[key]
        if defaults ~= nil and default == nil and not (path and openTables[path]) then
            -- truckTypes defaults to nil but is a valid key
            if keyPath ~= "logistics.truckTypes" then
                log:warn("unknown configuration key '%s'", keyPath)
            end
        elseif type(value) == "table" and type(default) == "table" and not openTables[keyPath] then
            checkKeys(value, default, keyPath)
        end
    end
end

--- Returns the effective configuration for a mission configuration table.
function config.build(given)
    given = given or {}
    checkKeys(given, config.defaults, nil)
    return tarmac.util.merge(config.defaults, given)
end

return config
