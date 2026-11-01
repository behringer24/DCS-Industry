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
        -- damaged AI aircraft of respawn groups that sit on the ground without
        -- moving at two dead checks in a row are removed, so the group respawns
        removeStranded = true,
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
        -- mark all enemy objectives on the F10 map from the start (only
        -- without reconnaissance, see intel.enabled)
        markers = true,
    },

    intel = {
        -- reconnaissance: enemy targets appear on the map only after they were
        -- spotted and reported to the own HQ; without HQ a coalition is blind
        enabled = true,
        -- AI units report what they see to their HQ by themselves
        aiRecon = true,
        -- seconds between two checks of what every observer can see
        interval = 10,
        -- meters from which a target of this kind can be spotted in daylight
        ranges = {
            factory = 10000, laboratory = 6000, storage = 8000, hq = 6000, secondary = 5000, airDefence = 6000,
        },
        -- range factor per observer: ground units and ships, aircraft, and
        -- reconnaissance aircraft (group task "Reconnaissance" or reconTypes)
        observers = { ground = 0.6, aircraft = 1, recon = 2.5 },
        -- aircraft higher than this above the ground in meters see nothing
        maxAltitude = 4000,
        reconAltitude = 12000,
        -- aircraft types that count as reconnaissance aircraft
        reconTypes = { ["Su-24MR"] = true, ["MiG-25RBT"] = true },
        -- range factor for the light; nightVision applies to nightVisionTypes
        -- at twilight and at night
        light = { day = 1, twilight = 0.5, night = 0.2, nightVision = 0.6 },
        nightVisionTypes = {
            ["AH-64D_BLK_II"] = true, ["A-10C"] = true, ["A-10C_2"] = true, ["F-16C_50"] = true,
            ["FA-18C_hornet"] = true, ["F-15ESE"] = true, ["AV8BNA"] = true, ["Ka-50_3"] = true,
            ["Mi-24P"] = true, ["Su-24MR"] = true,
        },
        -- range factor when the line of sight passes broken clouds
        -- (overcast clouds block it, scattered clouds do not matter)
        brokenClouds = 0.5,
        -- ground units with one of these attributes are air defence units; a
        -- group is an air defence site when it has a radar (airDefenceRadars)
        -- or at least airDefenceShare of its units are air defence units
        airDefenceAttributes = { ["Air Defence"] = true, ["EWR"] = true },
        airDefenceRadars = { ["SAM SR"] = true, ["SAM TR"] = true, ["EWR"] = true },
        airDefenceShare = 0.5,
        -- threat circles around reported air defence sites
        threatRings = true,
        -- threat radius in meters by attribute when the missiles do not tell
        threatRadius = { ["LR SAM"] = 40000, ["MR SAM"] = 25000, ["SR SAM"] = 8000, ["AAA"] = 3000 },
        -- log near misses (terrain, height, clouds, slightly out of range)
        verbose = true,
        -- seconds between two summaries in dcs.log
        summaryInterval = 600,
    },

    losses = {
        -- tickets lost when a player aircraft is destroyed
        playerTickets = 1,
        -- burning wrecks for destroyed ground vehicles
        vehicleSmoke = true,
    },

    csar = {
        enabled = true,
        -- rescue helicopter template per coalition of the downed pilot; the
        -- template itself may belong to any coalition (usually neutral)
        templates = { red = "TPL-SAR-Red", blue = "TPL-SAR-Blue" },
        -- rescue helicopters start with running engines instead of a cold start
        hotStart = false,
        -- flight altitude above ground in meters
        altitude = 150,
        -- seconds a landed rescue helicopter waits for the pilot at most
        waitTime = 1200,
        -- the pilot walks to a helicopter that landed up to this many meters away
        maxWalkDistance = 800,
        -- landings near the pilot before the rescue is given up
        landingAttempts = 2,
        -- seconds after which an unfinished rescue helicopter is removed
        timeout = 7200,
        -- scenery objects removed around the pilot, in meters (0 = none)
        clearRadius = 0,
        -- tickets lost by the coalition of a player that shoots down a rescue helicopter
        killTickets = 1,
    },
}

-- Tables whose keys are chosen by the mission designer.
local openTables = {
    ["respawn.groups"] = true,
    ["logistics.groups"] = true,
    ["intel.reconTypes"] = true,
    ["intel.nightVisionTypes"] = true,
    ["intel.airDefenceAttributes"] = true,
    ["intel.airDefenceRadars"] = true,
    ["intel.threatRadius"] = true,
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
