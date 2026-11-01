-- search and rescue, F10 menu and configuration

industryFixture.start({ logistics = { tonsPerTruk = 1 } })

local csar, tickets = industry.csar, industry.tickets

local function landParachute(name, typeName, coalitionId, x, z)
    local group = coalition.addGroup(coalitionId == 1 and country.id.RUSSIA or country.id.USA, Group.Category.GROUND, {
        name = name .. " group", units = { { name = name, type = typeName, x = x, y = z } },
    })
    local pilot = group:getUnit(1)
    dcs.fire({ id = world.event.S_EVENT_LANDING_AFTER_EJECTION, initiator = pilot })
    return pilot
end

-- lands a parachute and waits for the rescue, which starts a second later
local function parachute(name, typeName, coalitionId, x, z)
    local pilot = landParachute(name, typeName, coalitionId, x, z)
    dcs.advance(1)
    return pilot
end

local function fly(unitName)
    dcs.unit(unitName).airborne = true
    dcs.advance(5)
end

local function touchDown(unitName, x, z)
    local unit = dcs.unit(unitName)
    unit.airborne = false
    unit.point = { x = x, y = 0, z = z }
    dcs.advance(5)
end

local function lastRoute(groupName)
    local tasks = dcs.group(groupName).tasks
    local task = tasks[#tasks]
    expect.equal(task.id, "Mission")
    return task.params.route.points
end

local function logged(fragment)
    for _, line in ipairs(dcs.logs) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

test("a landed parachute sends a rescue helicopter from a free parking spot with a cold start", function()
    Airbase.getByName("Krymsk").parking = {
        { Term_Index = 1, Term_Type = 40, vTerminalPos = { x = 50, y = 0, z = 50 }, occupied = true },
        { Term_Index = 2, Term_Type = 68, vTerminalPos = { x = 60, y = 0, z = 50 } },
        { Term_Index = 3, Term_Type = 104, vTerminalPos = { x = 120, y = 0, z = 80 } },
        { Term_Index = 4, Term_Type = 72, vTerminalPos = { x = 900, y = 0, z = 900 } },
    }
    dcs.addScenery("house near", 1012, 2010)
    local pilot = parachute("pilot 1", "pilot_f15_parachute", 2, 1000, 2000)

    expect.falsy(pilot:isExist())
    local soldier = Group.getByName("DownedPilot-1")
    expect.notNil(soldier)
    expect.equal(soldier:getUnit(1):getTypeName(), "Soldier M4")
    expect.same(dcs.removedScenery, {}, "scenery stays by default")

    local rescue = Group.getByName("SAR BLUE #1")
    expect.notNil(rescue)
    expect.truthy(csar.isRescueGroup("SAR BLUE #1"))
    expect.equal(csar.state("SAR BLUE #1"), "outbound")
    expect.equal(rescue:getCoalition(), 0, "the clone keeps the neutral coalition of its template")
    expect.equal(rescue:getUnit(1):getTypeName(), "UH-60A")
    expect.equal(rescue.commands[1].id, "Start", "the uncontrolled template is started")

    local data = dcs.spawned[#dcs.spawned].data
    expect.equal(data.uncontrolled, true)
    expect.equal(data.units[1].parking, 3, "nearest free spot a helicopter can use")
    expect.equal(data.units[1].x, 120)
    expect.equal(data.units[1].y, 80)

    local points = data.route.points
    expect.equal(points[1].type, "TakeOffParking", "taxis to the runway like its template")
    expect.equal(points[1].airdromeId, 1)
    expect.equal(points[2].x, 1020)
    expect.equal(points[2].y, 2020)
    expect.equal(points[2].alt, 150)
    expect.equal(points[2].alt_type, "RADIO")
    local landing = points[2].task.params.tasks[1]
    expect.equal(landing.id, "Land")
    expect.equal(landing.params.duration, 1200)
    expect.equal(points[3].x, 50, "back to the template's airbase")
    expect.equal(points[4].type, "Land")
    expect.equal(points[4].airdromeId, 1)

    local message = dcs.findMessages("Pilot down, parachute spotted at")[1]
    expect.equal(message.target, 2)
    expect.contains(message.text, tarmac.util.formatPoint({ x = 1000, y = 2000 }, 3))
end)

test("the pilot walks to a helicopter that landed nearby, boards it and it flies home", function()
    dcs.advance(10)
    expect.equal(csar.state("SAR BLUE #1"), "outbound", "standing at the parking spot is no landing")
    fly("SAR BLUE #1-1")
    touchDown("SAR BLUE #1-1", 400, 300)
    expect.equal(csar.state("SAR BLUE #1"), "outbound", "setting down while hover taxiing is no landing")
    expect.equal(#dcs.group("SAR BLUE #1").tasks, 0)

    fly("SAR BLUE #1-1")
    touchDown("SAR BLUE #1-1", 1300, 2000)
    expect.equal(csar.state("SAR BLUE #1"), "boarding")
    local walk = lastRoute("DownedPilot-1")
    expect.equal(walk[1].x, 1001)
    expect.truthy(math.abs(walk[2].x - 1290) < 1, "stops short of the rotor")
    expect.equal(walk[2].y, 2000)
    expect.equal(#dcs.findMessages("SAR helicopter landed 299 m from the pilot"), 1)

    dcs.unit("DownedPilot-1-1").point = { x = 1285, y = 0, z = 2000 }
    dcs.advance(5)
    expect.isNil(Group.getByName("DownedPilot-1"), "the pilot boarded")
    expect.equal(csar.state("SAR BLUE #1"), "returning")
    expect.equal(#dcs.findMessages("Pilot rescued"), 1)
    local home = lastRoute("SAR BLUE #1")
    expect.equal(home[1].x, 1300, "takes off where it stands")
    expect.equal(home[#home].type, "Land")

    dcs.advance(30)
    expect.truthy(dcs.unit("SAR BLUE #1-1"):isExist(), "not removed before it took off")
    fly("SAR BLUE #1-1")
    touchDown("SAR BLUE #1-1", 70, 60)
    expect.falsy(dcs.unit("SAR BLUE #1-1"):isExist(), "removed after landing at home")
    expect.isNil(csar.state("SAR BLUE #1"))
    expect.truthy(logged("SAR BLUE #1 returned to base, removed"))
end)

test("a helicopter that lands too far away tries again, then gives up", function()
    parachute("pilot 2", "pilot_f15_parachute", 2, 5000, 5000)
    fly("SAR BLUE #2-1")
    touchDown("SAR BLUE #2-1", 7000, 5000)
    expect.equal(csar.state("SAR BLUE #2"), "outbound")
    local again = lastRoute("SAR BLUE #2")
    expect.equal(again[1].x, 7000)
    expect.equal(again[2].x, 5021, "lands at the pilot again")
    expect.equal(again[2].task.params.tasks[1].id, "Land")
    expect.equal(#dcs.findMessages("it tries again"), 1)

    touchDown("SAR BLUE #2-1", 7000, 5000)
    expect.equal(csar.state("SAR BLUE #2"), "outbound", "a landing needs a takeoff first")
    fly("SAR BLUE #2-1")
    touchDown("SAR BLUE #2-1", 7000, 5000)
    expect.equal(csar.state("SAR BLUE #2"), "returning")
    expect.equal(#dcs.findMessages("SAR mission failed: no landing site near the pilot (1999 m away)"), 1)
    expect.notNil(Group.getByName("DownedPilot-2"), "the pilot stays")
end)

test("shooting down a rescue helicopter costs the shooter's coalition", function()
    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet"):getUnit(1)
    local before = tickets.get(2)
    dcs.kill("SAR BLUE #2-1", { killer = player })
    expect.equal(tickets.get(2), before - 1)
    expect.equal(#dcs.findMessages("Player Hornet shot down SAR unit SAR BLUE #2"), 1)
    dcs.advance(5)
    expect.isNil(csar.state("SAR BLUE #2"))
    expect.equal(#dcs.findMessages("the helicopter was lost"), 0, "it was on its way home")
end)

test("a rescue fails when the pilot does not reach the helicopter in time", function()
    parachute("pilot 3", "pilot_f15_parachute", 2, 10000, 0)
    fly("SAR BLUE #3-1")
    touchDown("SAR BLUE #3-1", 10500, 0)
    expect.equal(csar.state("SAR BLUE #3"), "boarding")
    dcs.advance(600)
    expect.equal(csar.state("SAR BLUE #3"), "boarding")
    dcs.advance(30)
    expect.equal(csar.state("SAR BLUE #3"), "returning")
    expect.equal(#dcs.findMessages("SAR mission failed: the pilot did not reach the helicopter"), 1)
end)

test("a rescue fails when the pilot is killed or the helicopter is lost", function()
    parachute("pilot 4", "pilot_f15_parachute", 2, 20000, 0)
    dcs.kill("DownedPilot-4-1")
    dcs.advance(5)
    expect.equal(csar.state("SAR BLUE #4"), "returning")
    expect.equal(#dcs.findMessages("SAR mission failed: the pilot was lost"), 1)

    parachute("pilot 5", "pilot_f15_parachute", 2, 30000, 0)
    dcs.kill("SAR BLUE #5-1")
    dcs.advance(5)
    expect.isNil(csar.state("SAR BLUE #5"))
    expect.equal(#dcs.findMessages("SAR mission failed: the helicopter was lost"), 1)
end)

test("a rescue helicopter that never finishes is removed after the timeout", function()
    expect.truthy(dcs.unit("SAR BLUE #3-1"):isExist())
    dcs.advance(7200)
    expect.falsy(dcs.unit("SAR BLUE #3-1"):isExist())
    expect.isNil(csar.state("SAR BLUE #3"))
    expect.truthy(logged("rescue SAR BLUE #3 took too long, removed"))
end)

test("a parachute landing in water does not start a rescue", function()
    dcs.surface = land.SurfaceType.WATER
    local pilot = parachute("pilot 6", "pilot_su27_parachute", 1, 0, 0)
    dcs.surface = nil
    expect.falsy(pilot:isExist())
    expect.isNil(Group.getByName("SAR RED #6"))
end)

test("red pilots are rescued by the red template", function()
    parachute("pilot 7", "pilot_su27_parachute", 1, 3000, 3000)
    local rescue = Group.getByName("SAR RED #6")
    expect.notNil(rescue)
    expect.equal(rescue:getUnit(1):getTypeName(), "Mi-8MT")
    expect.equal(Group.getByName("DownedPilot-6"):getUnit(1):getTypeName(), "Infantry AK")
    local data = dcs.spawned[#dcs.spawned].data
    expect.equal(data.uncontrolled, false, "a template without takeoff waypoint starts in the air")
    expect.same(rescue.commands, {})
    expect.equal(data.route.points[2].task.params.tasks[1].id, "Land")
end)

test("with csar.hotStart the helicopter starts with running engines", function()
    industry.config.csar.hotStart = true
    parachute("pilot 8", "pilot_f15_parachute", 2, 40000, 0)
    industry.config.csar.hotStart = false
    local data = dcs.spawned[#dcs.spawned].data
    expect.equal(data.route.points[1].type, "TakeOffParkingHot")
    expect.equal(data.route.points[1].action, "From Parking Area Hot")
    expect.equal(data.uncontrolled, false)
    expect.same(Group.getByName("SAR BLUE #7").commands, {}, "a hot start needs no start command")
end)

test("without a free parking spot the helicopter keeps the cold start of its template", function()
    Airbase.getByName("Krymsk").parking = {
        { Term_Index = 1, Term_Type = 40, vTerminalPos = { x = 50, y = 0, z = 50 }, occupied = true },
    }
    parachute("pilot 9", "pilot_f15_parachute", 2, 50000, 0)
    local data = dcs.spawned[#dcs.spawned].data
    expect.equal(data.route.points[1].type, "TakeOffParking")
    expect.isNil(data.units[1].parking)
    expect.equal(Group.getByName("SAR BLUE #8").commands[1].id, "Start")
end)

test("the parachute is replaced a second after the event handler", function()
    local pilot = landParachute("pilot 10", "pilot_f15_parachute", 2, 60000, 0)
    expect.truthy(pilot:isExist(), "nothing changes inside the event handler")
    expect.isNil(Group.getByName("SAR BLUE #9"))
    dcs.advance(1)
    expect.falsy(pilot:isExist())
    expect.notNil(Group.getByName("DownedPilot-9"))
    expect.notNil(Group.getByName("SAR BLUE #9"))
end)

test("players get the HQ menu, also in dynamic slots", function()
    local slot = dcs.spawnPlayer(nil, "Viper", {
        name = "Dynamic Viper #1", category = "plane",
        units = { { name = "Dynamic Viper #1-1", type = "F-16C_50", skill = "Client" } },
    }, country.id.USA)
    local groupId = slot:getID()
    expect.same(dcs.menuPaths("group", groupId), { "HQ", "HQ/Send recon report", "HQ/Request supply status" })
    dcs.selectMenu("group", groupId, "HQ/Request supply status")
    local message = dcs.messages[#dcs.messages]
    expect.equal(message.to, "group")
    expect.equal(message.target, groupId)
    expect.contains(message.text, "HQ: Supply status")
    expect.contains(message.text, "Operational: 1 factories")
    expect.falsy(message.text:find("Tickets", 1, true), "players hear nothing about tickets")
end)

test("unknown configuration keys are reported", function()
    expect.truthy(logged("unknown configuration key 'logistics.tonsPerTruk'"))
end)

test("a second setup call is ignored", function()
    industry.setup({ startResources = 1 })
    expect.equal(industry.config.startResources, 500)
end)

test("nothing logged an error", function()
    local errors = industryFixture.errors()
    expect.equal(#errors, 0, table.concat(errors, " | "))
end)
