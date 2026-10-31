-- respawn queues

industryFixture.start()

local respawn, economy = industry.respawn, industry.economy

local function spawnCount(name)
    local n = 0
    for _, entry in ipairs(dcs.spawned) do
        if entry.data.name == name then
            n = n + 1
        end
    end
    return n
end

test("costs come from the configuration or the category defaults", function()
    expect.equal(respawn.cost("RedCAP-1"), 400)
    expect.equal(respawn.cost("Tanks-Red-1"), 50)
    expect.equal(respawn.cost("BlueCAP-1"), 300)
    expect.equal(respawn.cost("Convoy-Red-1"), 0, "logistics groups respawn for free")
    expect.falsy(industry.addRespawnGroup("Does-Not-Exist", 10))
end)

test("a group is queued only when its last unit is lost", function()
    dcs.kill("RedCAP-1-1")
    expect.same(respawn.queued(1).paid, {})
    dcs.kill("RedCAP-1-2", { keep = true, events = { "UNIT_LOST" } })
    expect.same(respawn.queued(1).paid, { "RedCAP-1" })
end)

test("a wreck that still exists delays the respawn until the retries are used", function()
    dcs.advance(35)
    expect.equal(spawnCount("RedCAP-1"), 0)
    dcs.advance(60)
    expect.equal(spawnCount("RedCAP-1"), 0)
    local before = economy.resources(1)
    dcs.advance(60)
    expect.equal(spawnCount("RedCAP-1"), 1)
    expect.equal(economy.resources(1), before - 400)
    expect.equal(Group.getByName("RedCAP-1"):getSize(), 2)
    expect.equal(dcs.flags["RedCAP-1_respawned"], 1)
end)

test("the paid queue waits for an expensive group instead of skipping it", function()
    dcs.kill("RedCAP-1-1")
    dcs.kill("RedCAP-1-2")
    dcs.kill("Tanks-Red-1-1")
    expect.same(respawn.queued(1).paid, { "RedCAP-1", "Tanks-Red-1" })
    expect.truthy(economy.resources(1) < 400)
    dcs.advance(120)
    expect.equal(spawnCount("RedCAP-1"), 1)
    expect.equal(spawnCount("Tanks-Red-1"), 0, "cheap group must not overtake")

    industry.addResources("red", 1000)
    dcs.advance(60)
    expect.equal(spawnCount("RedCAP-1"), 2)
    expect.equal(spawnCount("Tanks-Red-1"), 0, "one paid respawn per cycle")
    dcs.advance(60)
    expect.equal(spawnCount("Tanks-Red-1"), 1)
end)

test("free respawns do not wait and do not cost resources", function()
    local before = economy.resources(1)
    local count = spawnCount("Convoy-Red-1")
    industry.queueRespawn("Convoy-Red-1", 0)
    dcs.advance(60)
    expect.equal(spawnCount("Convoy-Red-1"), count + 1)
    expect.truthy(economy.resources(1) >= before)
end)

test("groups that vanished without events are found and queued", function()
    local count = spawnCount("Tanks-Red-1")
    dcs.removeGroup(dcs.group("Tanks-Red-1"))
    dcs.advance(400)
    expect.equal(spawnCount("Tanks-Red-1"), count + 1)
end)

test("an ejection destroys the aircraft of a respawn group only, a second later", function()
    dcs.fire({ id = world.event.S_EVENT_EJECTION, initiator = dcs.unit("RedCAP-1-1") })
    expect.equal(#dcs.explosions, 0, "nothing changes inside the event handler")
    dcs.advance(1)
    expect.equal(#dcs.explosions, 1)
    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet")
    dcs.fire({ id = world.event.S_EVENT_EJECTION, initiator = player:getUnit(1) })
    dcs.advance(1)
    expect.equal(#dcs.explosions, 1)
end)

test("no explosion when the aircraft is gone before it follows the ejection", function()
    dcs.fire({ id = world.event.S_EVENT_EJECTION, initiator = dcs.unit("RedCAP-1-2") })
    dcs.kill("RedCAP-1-2", { events = { "CRASH" } })
    dcs.advance(1)
    expect.equal(#dcs.explosions, 1)
end)
