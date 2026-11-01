-- reconnaissance, recon reports and the HQ

dcs.typeAttributes["SA-11 Buk LN 9A310M1"] = { ["Air Defence"] = true, ["MR SAM"] = true, ["SAM LL"] = true }
dcs.typeAttributes["SA-11 Buk SR 9S18M1"] = { ["Air Defence"] = true, ["MR SAM"] = true, ["SAM SR"] = true }
dcs.typeAttributes["1L13 EWR"] = { ["Air Defence"] = true, ["EWR"] = true }
dcs.typeAttributes["ZSU-23-4 Shilka"] = { ["Air Defence"] = true, ["AAA"] = true }
dcs.typeAttributes["Dog Ear radar"] = { ["Air Defence"] = true, ["SAM SR"] = true }
dcs.typeAttributes["2S6 Tunguska"] = { ["Air Defence"] = true, ["SR SAM"] = true }
dcs.typeAmmo["SA-11 Buk LN 9A310M1"] = { { count = 4, desc = { typeName = "9M38M1", rangeMaxAltMax = 35000 } } }

industryFixture.start({ intel = { aiRecon = false } }, function(m)
    local RU, US = country.id.RUSSIA, country.id.USA
    fixture.static(m, "blue", US, { name = "HQ Blue Command Center", x = -90000, y = 0 })
    fixture.static(m, "red", RU, { name = "FactoryRed-9", x = 40000, y = 5000 })
    fixture.static(m, "red", RU, { name = "LaboratoryRed-9", x = 0, y = 60000 })
    fixture.group(m, "red", RU, "vehicle", {
        name = "SAM-Red-1", x = 30000, y = 0,
        units = { { type = "SA-11 Buk LN 9A310M1" }, { type = "SA-11 Buk SR 9S18M1" } },
    })
    fixture.group(m, "red", RU, "vehicle", { name = "EWR-Red-1", x = 70000, y = 70000, units = { { type = "1L13 EWR" } } })
    fixture.group(m, "red", RU, "vehicle", {
        name = "Shorad-Red-1", x = 95000, y = 95000,
        units = { { type = "Dog Ear radar" }, { type = "2S6 Tunguska" }, { type = "Ural-375" }, { type = "Ural-375" },
                  { type = "Ural-375" } },
    })
    fixture.group(m, "red", RU, "vehicle", {
        name = "Armor-Red-1", x = 90000, y = 90000,
        units = { { type = "T-72B" }, { type = "T-72B" }, { type = "T-72B" }, { type = "ZSU-23-4 Shilka" } },
    })
    fixture.group(m, "blue", US, "plane", {
        name = "BlueRecon-1", task = "Reconnaissance", x = -80000, y = 0, units = { { type = "Tornado IDS", alt = 6000 } },
    })
end)

local intel, logged = industry.intel, industryFixture.logged

-- x is north, z is east, height above the (flat) ground
local function put(unit, x, z, height)
    unit.point = { x = x, y = height or 0, z = z }
end

local player, playerGroupId

local function enterSlot()
    local group = dcs.spawnPlayer("BlueStrike-1-1", "Hornet")
    player, playerGroupId = group:getUnit(1), group:getID()
    player.airborne = true
end

local function reportToHQ()
    dcs.selectMenu("group", playerGroupId, "HQ/Send recon report")
end

test("air defence groups and objectives become targets", function()
    local sam = intel.targets()["group:SAM-Red-1"]
    expect.equal(sam.label, "SAM site (medium range)")
    expect.equal(sam.threat, 35000, "from the missile range")
    expect.equal(intel.targets()["group:EWR-Red-1"].label, "Early warning radar")
    expect.isNil(intel.targets()["group:EWR-Red-1"].threat)
    expect.equal(intel.targets()["objective:FactoryRed-9-1"].label, "Factory")
    expect.isNil(intel.targets()["group:Tanks-Red-1"], "tanks are no air defence")
    expect.isNil(intel.targets()["group:Armor-Red-1"], "one escort AAA does not make an air defence site")
    expect.truthy(logged("red group Armor-Red-1 has 1 of 4 units with air defence (Air Defence) and no radar, it is no air defence site"))
    expect.equal(intel.targets()["group:Shorad-Red-1"].label, "SAM site (short range)", "a radar makes a site")
    expect.truthy(logged("red air defence site Shorad-Red-1: SAM site (short range) (2 of 5 units, Air Defence, radar), threat ring 8.0 km (default for SR SAM)"))
    expect.truthy(logged("red air defence site SAM-Red-1: SAM site (medium range) (2 of 2 units, Air Defence, radar), threat ring 35.0 km (missile range)"))
    expect.truthy(logged("environment at start: sun "))
    expect.equal(#dcs.markErrors, 0)
end)

test("players get the HQ menu", function()
    enterSlot()
    put(player, -200000, 0, 1000)
    expect.same(dcs.menuPaths("group", playerGroupId), { "HQ", "HQ/Send recon report", "HQ/Request supply status" })
end)

test("a player spots a target in range and gets a hint and a personal mark", function()
    put(player, 36000, 5000, 1000)
    dcs.advance(10)
    local package = intel.package("BlueStrike-1-1")
    expect.notNil(package)
    expect.equal(package.count, 1)
    local item = package.items["objective:FactoryRed-9-1"]
    expect.notNil(item)
    local hint = dcs.findMessages("Recon: Factory spotted, bearing 000 for 4 km.")[1]
    expect.notNil(hint)
    expect.equal(hint.target, playerGroupId)
    expect.contains(hint.text, "Send your recon report to HQ")
    local mark = dcs.marks[item.markId]
    expect.equal(mark.to, "group")
    expect.equal(mark.text, "Factory spotted 12:00, not reported")
    expect.isNil(intel.known(2)["objective:FactoryRed-9-1"], "the HQ does not know it yet")
    expect.truthy(logged("blue: player Hornet (BlueStrike-1-1, FA-18C_hornet, aircraft) spotted Factory FactoryRed-9-1 at 4.1 km"))
end)

test("the recon report puts the targets on the coalition map", function()
    local personal = intel.package("BlueStrike-1-1").items["objective:FactoryRed-9-1"].markId
    reportToHQ()
    expect.equal(#dcs.findMessages("HQ: Recon report received, 1 new target on the map."), 1)
    expect.isNil(dcs.marks[personal], "the personal mark is gone")
    local report = intel.known(2)["objective:FactoryRed-9-1"]
    expect.notNil(report)
    local mark = dcs.marks[report.markId]
    expect.equal(mark.to, "coalition")
    expect.equal(mark.coalition, 2)
    expect.equal(mark.text, "Factory (spotted 12:00)")
    expect.equal(intel.package("BlueStrike-1-1").count, 0)
    expect.truthy(logged("blue: Hornet (BlueStrike-1-1) reported to HQ: 1 new, 0 already known"))
end)

test("a reported target is not spotted again and an empty report is acknowledged", function()
    dcs.advance(10)
    expect.equal(intel.package("BlueStrike-1-1").count, 0)
    reportToHQ()
    expect.equal(#dcs.findMessages("HQ: Copy, nothing new to report."), 1)
end)

test("aircraft above the height limit see nothing, lower they do", function()
    put(player, 29000, 0, 4500)
    dcs.advance(10)
    expect.isNil(intel.package("BlueStrike-1-1").items["group:SAM-Red-1"])
    expect.truthy(logged("did not spot SAM site (medium range) SAM-Red-1 at 4.6 km: too high (limit 4000 m)"))
    put(player, 29000, 0, 3000)
    dcs.advance(10)
    expect.notNil(intel.package("BlueStrike-1-1").items["group:SAM-Red-1"])
    expect.equal(#dcs.findMessages("Recon: SAM site (medium range) spotted, bearing 000 for 3 km."), 1)
end)

test("the recon package is lost with the aircraft", function()
    local markId = intel.package("BlueStrike-1-1").items["group:SAM-Red-1"].markId
    dcs.kill("BlueStrike-1-1")
    dcs.advance(10)
    expect.isNil(intel.package("BlueStrike-1-1"))
    expect.isNil(dcs.marks[markId])
    expect.isNil(intel.known(2)["group:SAM-Red-1"])
    expect.truthy(logged("recon package of Hornet (BlueStrike-1-1) with 1 targets lost: aircraft lost"))
end)

test("AI recon reports right away and draws a threat ring", function()
    industry.config.intel.aiRecon = true
    local recon = dcs.unit("BlueRecon-1-1")
    put(recon, 20000, 0, 6000)
    recon.airborne = true
    dcs.advance(10)
    local report = intel.known(2)["group:SAM-Red-1"]
    expect.notNil(report)
    expect.contains(dcs.marks[report.markId].text, "SAM site (medium range) (spotted ")
    local ring = dcs.marks[report.ringId]
    expect.equal(ring.kind, "circle")
    expect.equal(ring.coalition, 2)
    expect.equal(ring.radius, 35000)
    expect.truthy(logged("blue: BlueRecon-1-1 (Tornado IDS, recon) spotted SAM site (medium range) SAM-Red-1 at 11.7 km"))
    expect.truthy(#dcs.findMessages("HQ: Our forces reported") > 0, "the coalition hears about it")
end)

test("a destroyed site turns grey on the map", function()
    dcs.kill("SAM-Red-1-1")
    dcs.kill("SAM-Red-1-2")
    local report = intel.known(2)["group:SAM-Red-1"]
    expect.contains(dcs.marks[report.markId].text, "SAM site (medium range) destroyed (spotted ")
    expect.same(dcs.marks[report.ringId].color, { 0.5, 0.5, 0.5, 0.8 })
    expect.equal(dcs.marks[report.ringId].lineType, 2)
end)

test("a rebuilt site must be found again", function()
    tarmac.spawn.respawn("SAM-Red-1")
    dcs.advance(1)
    expect.isNil(intel.known(2)["group:SAM-Red-1"])
    expect.falsy(intel.targets()["group:SAM-Red-1"].destroyed)
    expect.truthy(logged("report of SAM site (medium range) SAM-Red-1 removed: the site was rebuilt"))
    dcs.advance(10)
    expect.notNil(intel.known(2)["group:SAM-Red-1"], "the recon aircraft is still there")
end)

test("at night only types with night vision see, and not as far", function()
    enterSlot()
    put(player, 0, 55500, 500)
    dcs.absStart = 0
    dcs.advance(10)
    expect.isNil(intel.package("BlueStrike-1-1"), "4.5 km is beyond the night range")
    put(player, 0, 57000, 500)
    dcs.advance(10)
    expect.notNil(intel.package("BlueStrike-1-1").items["objective:LaboratoryRed-9-1"], "3 km with night vision")
    expect.truthy(logged("night with night vision x0.60"))
    dcs.absStart = 43200
end)

test("terrain blocks the line of sight", function()
    put(player, 66000, 70000, 300)
    dcs.isVisible = function() return false end
    dcs.advance(10)
    dcs.isVisible = nil
    expect.isNil(intel.package("BlueStrike-1-1").items["group:EWR-Red-1"])
    expect.truthy(logged("did not spot Early warning radar EWR-Red-1 at 4.0 km: terrain blocks the view"))
end)

test("overcast clouds between observer and target block the sight", function()
    local clouds = env.mission.weather.clouds
    env.mission.weather.clouds = { base = 1000, thickness = 300, preset = "Preset22" }
    put(player, 66000, 70000, 2000)
    dcs.advance(10)
    expect.isNil(intel.package("BlueStrike-1-1").items["group:EWR-Red-1"])
    expect.truthy(logged("EWR-Red-1 at 4.5 km: clouds in between"))
    env.mission.weather.clouds = clouds
    dcs.advance(10)
    expect.notNil(intel.package("BlueStrike-1-1").items["group:EWR-Red-1"])
end)

test("the supply status covers the own coalition only", function()
    dcs.selectMenu("group", playerGroupId, "HQ/Request supply status")
    local message = dcs.messages[#dcs.messages]
    expect.equal(message.target, playerGroupId)
    expect.contains(message.text, "HQ: Supply status")
    expect.contains(message.text, "Operational: 1 factories, 0 laboratories, 1 storages")
end)

test("without HQ the coalition is blind", function()
    local ids = {}
    for _, report in pairs(intel.known(2)) do
        ids[#ids + 1] = report.markId
        ids[#ids + 1] = report.ringId
    end
    expect.truthy(#ids > 0)
    local personal = intel.package("BlueStrike-1-1").items["group:EWR-Red-1"].markId
    dcs.kill("HQ Blue Command Center-1")
    expect.equal(tarmac.util.count(intel.known(2)), 0)
    for _, id in ipairs(ids) do
        expect.isNil(dcs.marks[id])
    end
    expect.isNil(dcs.marks[personal])
    expect.isNil(intel.package("BlueStrike-1-1"))
    expect.same(dcs.menuPaths("group", playerGroupId), {}, "the HQ menu is gone")
    expect.equal(#dcs.findMessages("HQ is not responding. All reconnaissance reports are lost."), 1)
    expect.truthy(logged("blue lost its HQ"))

    put(player, 0, 57000, 500)
    dcs.advance(10)
    expect.isNil(intel.package("BlueStrike-1-1"), "nobody spots anything without HQ")
    enterSlot()
    expect.same(dcs.menuPaths("group", playerGroupId), {}, "new players get no HQ menu either")
end)

test("the summary tells what each coalition knows", function()
    intel.summary()
    expect.truthy(logged("summary blue: HQ lost"))
    expect.truthy(logged("summary red: HQ ok"))
end)

test("nothing logged an error", function()
    local errors = industryFixture.errors()
    expect.equal(#errors, 0, table.concat(errors, " | "))
end)
