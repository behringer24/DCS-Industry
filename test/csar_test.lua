-- search and rescue, F10 menu and configuration

industryFixture.start({ logistics = { tonsPerTruk = 1 } })

local csar, tickets = industry.csar, industry.tickets

local function parachute(name, typeName, coalitionId, x, z)
    local group = coalition.addGroup(coalitionId == 1 and country.id.RUSSIA or country.id.USA, Group.Category.GROUND, {
        name = name .. " group", units = { { name = name, type = typeName, x = x, y = z } },
    })
    return group:getUnit(1)
end

test("a landed parachute starts a rescue mission with a soldier on the ground", function()
    dcs.addScenery("house near", 1012, 2010)
    dcs.addScenery("house far", 1500, 2500)
    local pilot = parachute("pilot 1", "pilot_f15_parachute", 2, 1000, 2000)
    dcs.fire({ id = world.event.S_EVENT_LANDING_AFTER_EJECTION, initiator = pilot })

    expect.falsy(pilot:isExist())
    local soldier = Group.getByName("DownedPilot-1")
    expect.notNil(soldier)
    expect.equal(soldier:getUnit(1):getTypeName(), "Soldier M4")

    local rescue = Group.getByName("SAR BLUE #1")
    expect.notNil(rescue)
    expect.truthy(csar.isRescueGroup("SAR BLUE #1"))
    expect.equal(rescue:getCoalition(), 0, "the clone keeps the neutral coalition of its template")
    expect.equal(rescue:getUnit(1):getTypeName(), "UH-60A")
    expect.equal(rescue.commands[1].id, "Start")

    local points = dcs.spawned[#dcs.spawned].data.route.points
    local last = points[#points]
    expect.equal(last.x, 1012)
    expect.equal(last.y, 2010)
    expect.equal(last.task.params.tasks[1].id, "Land")
    expect.contains(last.task.params.tasks[2].params.action.params.command, "DownedPilot-1")

    expect.same(dcs.removedScenery, { "house near" })
    local message = dcs.findMessages("Pilot down, parachute spotted at")[1]
    expect.equal(message.target, 2)
    expect.contains(message.text, tarmac.util.formatPoint({ x = 1000, y = 2000 }, 3))
end)

test("a parachute landing in water does not start a rescue", function()
    dcs.surface = land.SurfaceType.WATER
    local pilot = parachute("pilot 2", "pilot_su27_parachute", 1, 0, 0)
    dcs.fire({ id = world.event.S_EVENT_LANDING_AFTER_EJECTION, initiator = pilot })
    dcs.surface = nil
    expect.falsy(pilot:isExist())
    expect.isNil(Group.getByName("SAR RED #2"))
end)

test("red pilots are rescued by the red template", function()
    local pilot = parachute("pilot 3", "pilot_su27_parachute", 1, 3000, 3000)
    dcs.fire({ id = world.event.S_EVENT_LANDING_AFTER_EJECTION, initiator = pilot })
    local rescue = Group.getByName("SAR RED #2")
    expect.notNil(rescue)
    expect.equal(rescue:getUnit(1):getTypeName(), "Mi-8MT")
    expect.equal(Group.getByName("DownedPilot-2"):getUnit(1):getTypeName(), "Infantry AK")
end)

test("shooting down a rescue helicopter costs the shooter's coalition", function()
    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet"):getUnit(1)
    local before = tickets.get(2)
    dcs.kill("SAR BLUE #1-1", { killer = player })
    expect.equal(tickets.get(2), before - 1)
    expect.equal(#dcs.findMessages("Player Hornet shot down SAR unit SAR BLUE #1"), 1)
end)

test("players get the Industry menu, also in dynamic slots", function()
    local slot = dcs.spawnPlayer(nil, "Viper", {
        name = "Dynamic Viper #1", category = "plane",
        units = { { name = "Dynamic Viper #1-1", type = "F-16C_50", skill = "Client" } },
    }, country.id.USA)
    local groupId = slot:getID()
    expect.same(dcs.menuPaths("group", groupId), { "Industry", "Industry/Get current statistics" })
    dcs.selectMenu("group", groupId, "Industry/Get current statistics")
    local message = dcs.messages[#dcs.messages]
    expect.equal(message.to, "group")
    expect.equal(message.target, groupId)
    expect.contains(message.text, "Tickets: BLUE")
end)

test("unknown configuration keys are reported", function()
    local found = false
    for _, line in ipairs(dcs.logs) do
        if line:find("unknown configuration key 'logistics.tonsPerTruk'", 1, true) then
            found = true
        end
    end
    expect.truthy(found)
end)

test("a second setup call is ignored", function()
    industry.setup({ startResources = 1 })
    expect.equal(industry.config.startResources, 500)
end)
