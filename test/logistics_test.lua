-- convoys and air transports

industryFixture.start()

local logistics, economy = industry.logistics, industry.economy

local function lastTask(points)
    local tasks = points[#points].task.params.tasks
    return tasks, tasks[#tasks]
end

local function countArrivalScripts(points)
    local n = 0
    for _, task in ipairs(points[#points].task.params.tasks) do
        if task.id == "WrappedAction" and task.params.action.params.command:find("convoyArrived", 1, true) then
            n = n + 1
        end
    end
    return n
end

test("groups get their logistics role from the name prefix", function()
    expect.equal(logistics.role("Convoy-Red-1"), "convoy")
    expect.equal(logistics.role("Convoy-Blue-1"), "convoy")
    expect.equal(logistics.role("Transport-Red-1"), "transport")
    expect.isNil(logistics.role("RedCAP-1"))
end)

test("convoys placed in the editor get the arrival action on their last waypoint", function()
    local group = dcs.group("Convoy-Red-1")
    local task = group.tasks[#group.tasks]
    expect.equal(task.id, "Mission")
    local points = task.params.route.points
    local tasks, arrival = lastTask(points)
    expect.equal(#tasks, 2, "the existing waypoint task is kept")
    expect.equal(arrival.params.action.params.command, 'if industry then industry.convoyArrived("Convoy-Red-1") end')
end)

test("an arriving convoy delivers per surviving truck and respawns for free", function()
    dcs.kill("Convoy-Red-1-3")
    local before = economy.resources(1)
    local tons = industry.convoyArrived("Convoy-Red-1")
    -- HL_KORD is not a truck, one of three trucks was destroyed
    expect.equal(tons, 200)
    expect.equal(economy.resources(1), before + 200)
    expect.same(industry.respawn.queued(1).free, { "Convoy-Red-1" })
    expect.equal(industry.convoyArrived("Convoy-Red-1"), 0, "a convoy delivers once per trip")
end)

test("a respawned convoy has exactly one arrival action and can deliver again", function()
    dcs.advance(35)
    local spawned = dcs.spawned[#dcs.spawned].data
    expect.equal(spawned.name, "Convoy-Red-1")
    expect.equal(countArrivalScripts(spawned.route.points), 1)
    expect.equal(industry.convoyArrived("Convoy-Red-1"), 300)
    dcs.advance(60)
    spawned = dcs.spawned[#dcs.spawned].data
    expect.equal(countArrivalScripts(spawned.route.points), 1, "the action must not pile up")
end)

test("a transport delivers when it shuts down at a friendly airbase", function()
    local unit = dcs.unit("Transport-Red-1-1")
    local before = economy.resources(1)
    dcs.fire({ id = world.event.S_EVENT_LAND, initiator = unit, place = Airbase.getByName("Krymsk") })
    dcs.fire({ id = world.event.S_EVENT_ENGINE_SHUTDOWN, initiator = unit })
    expect.equal(economy.resources(1), before + 800)
    expect.equal(dcs.flags["Transport-Red-1-1_landed"], 1)
    expect.truthy(unit:isExist(), "nothing is removed inside the event handler")
    dcs.advance(1)
    expect.falsy(unit:isExist(), "the landed aircraft is removed")
    expect.same(industry.respawn.queued(1).free, { "Transport-Red-1" })
end)

test("a transport that landed at an enemy airbase delivers nothing", function()
    dcs.advance(60)
    local unit = dcs.unit("Transport-Red-1-1")
    expect.truthy(unit:isExist(), "transport respawned")
    local before = economy.resources(1)
    dcs.fire({ id = world.event.S_EVENT_LAND, initiator = unit, place = Airbase.getByName("Senaki") })
    dcs.fire({ id = world.event.S_EVENT_ENGINE_SHUTDOWN, initiator = unit })
    expect.equal(economy.resources(1), before)
end)

test("a transport that loses its engines in flight is not removed and delivers nothing", function()
    dcs.advance(60)
    local unit = dcs.unit("Transport-Red-1-1")
    expect.truthy(unit:isExist(), "transport respawned")
    unit.airborne = true
    local before = economy.resources(1)
    dcs.fire({ id = world.event.S_EVENT_ENGINE_SHUTDOWN, initiator = unit })
    expect.truthy(unit:isExist())
    expect.equal(economy.resources(1), before)
    expect.equal(dcs.flags["Transport-Red-1-1_landed"], 1, "flag unchanged from the earlier landing")
    expect.same(industry.respawn.queued(1).free, {})
end)

test("an aircraft hit in flight is handled by its crash, not by the engine shutdown", function()
    local unit = dcs.unit("RedCAP-1-1")
    unit.airborne = true
    dcs.fire({ id = world.event.S_EVENT_ENGINE_SHUTDOWN, initiator = unit })
    expect.truthy(unit:isExist(), "still flying until it crashes")
    expect.isNil(dcs.flags["RedCAP-1-1_landed"])
    dcs.kill("RedCAP-1-1", { events = { "CRASH" } })
    dcs.kill("RedCAP-1-2", { events = { "CRASH" } })
    expect.same(industry.respawn.queued(1).paid, { "RedCAP-1" })
end)

test("players are never removed on engine shutdown", function()
    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet"):getUnit(1)
    dcs.fire({ id = world.event.S_EVENT_ENGINE_SHUTDOWN, initiator = player })
    expect.truthy(player:isExist())
    expect.isNil(dcs.flags["BlueStrike-1-1_landed"])
end)
