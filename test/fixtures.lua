-- A small Industry Wars 3 style mission used by the tests.
--
-- red:  FactoryRed-1/2, LaboratoryRed-1, StorageRed-1/2, HQ Red, Secondary-1,
--       RedCAP-1 (2 planes), Tanks-Red-1, Convoy-Red-1, Transport-Red-1, TPL-SAR-Red
-- blue: FactoryBlue-1, StorageBlue-1, BlueCAP-1, Convoy-Blue-1, client slot BlueStrike-1
-- neutral: TPL-SAR-Blue (rescues blue pilots)

industryFixture = {}

function industryFixture.mission()
    local m = fixture.mission()
    local RU, US = country.id.RUSSIA, country.id.USA

    fixture.static(m, "red", RU, { name = "FactoryRed-1", x = 100, y = 100 })
    fixture.static(m, "red", RU, { name = "FactoryRed-2", x = 200, y = 100 })
    fixture.static(m, "red", RU, { name = "LaboratoryRed-1", x = 300, y = 100 })
    fixture.static(m, "red", RU, { name = "StorageRed-1", x = 400, y = 100 })
    fixture.static(m, "red", RU, { name = "StorageRed-2", x = 500, y = 100 })
    fixture.static(m, "red", RU, { name = "HQ Red Command Center", x = 600, y = 100 })
    fixture.static(m, "red", RU, { name = "Secondary-1", x = 700, y = 100 })
    fixture.static(m, "red", RU, { name = "Warehouse decoration", x = 800, y = 100 })

    fixture.static(m, "blue", US, { name = "FactoryBlue-1", x = 100, y = 900 })
    fixture.static(m, "blue", US, { name = "StorageBlue-1", x = 200, y = 900 })

    fixture.group(m, "red", RU, "plane", {
        name = "RedCAP-1", units = { { type = "MiG-29S" }, { type = "MiG-29S" } },
    })
    fixture.group(m, "red", RU, "vehicle", { name = "Tanks-Red-1", units = { { type = "T-72B" } } })
    fixture.group(m, "red", RU, "vehicle", {
        name = "Convoy-Red-1", x = 1000, y = 1000,
        units = { { type = "HL_KORD" }, { type = "KAMAZ Truck" }, { type = "KAMAZ Truck" }, { type = "KAMAZ Truck" } },
        route = {
            { x = 1000, y = 1000, action = "On Road", type = "Turning Point" },
            { x = 9000, y = 9000, action = "On Road", type = "Turning Point",
              task = { id = "ComboTask", params = { tasks = { { number = 1, id = "Hold", enabled = true } } } } },
        },
    })
    fixture.group(m, "red", RU, "plane", { name = "Transport-Red-1", units = { { type = "IL-76MD" } } })
    fixture.group(m, "red", RU, "helicopter", {
        name = "TPL-SAR-Red", lateActivation = true, uncontrolled = true, units = { { type = "Mi-8MT" } },
    })

    fixture.group(m, "blue", US, "plane", { name = "BlueCAP-1", units = { { type = "F-16C_50" } } })
    fixture.group(m, "blue", US, "vehicle", {
        name = "Convoy-Blue-1", units = { { type = "M 818" }, { type = "M 818" } },
        route = { { x = 0, y = 0 }, { x = 5000, y = 0 } },
    })
    -- rescue helicopters for blue pilots fly for the neutral coalition
    fixture.group(m, "neutrals", country.id.UN_PEACEKEEPERS, "helicopter", {
        name = "TPL-SAR-Blue", uncontrolled = true, units = { { type = "UH-60A" } },
        route = { { x = 50, y = 50, type = "TakeOffParking", action = "From Parking Area", airdromeId = 1 } },
    })
    fixture.client(m, "blue", US, "plane", { name = "BlueStrike-1" })
    return m
end

-- The configuration used by most tests; overrides are merged on top.
function industryFixture.config(overrides)
    local base = {
        startResources = 500,
        respawn = {
            interval = 60,
            groups = { ["RedCAP-1"] = 400, ["Tanks-Red-1"] = {}, ["BlueCAP-1"] = { cost = 300 } },
        },
    }
    for key, value in pairs(overrides or {}) do
        base[key] = value
    end
    return base
end

-- Log lines written with the error level (failed handlers, tasks, spawns).
function industryFixture.errors()
    local found = {}
    for _, line in ipairs(dcs.logs) do
        if line:find(" ERROR ", 1, true) then
            found[#found + 1] = line
        end
    end
    return found
end

-- True if a log line contains the fragment.
function industryFixture.logged(fragment)
    for _, line in ipairs(dcs.logs) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

-- Starts the fixture mission, loads the bundle and calls industry.setup.
function industryFixture.start(overrides, prepare)
    local m = industryFixture.mission()
    if prepare then
        prepare(m)
    end
    dcs.start(m)
    dcs.addAirbase("Krymsk", 1, 0, 0)
    dcs.addAirbase("Senaki", 2, 50000, 0)
    loadBundle()
    industry.setup(industryFixture.config(overrides))
end
