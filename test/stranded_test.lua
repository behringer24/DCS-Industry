-- damaged aircraft stranded on the ground

industryFixture.start()

local stranded = industry.stranded

local function hit(unitName)
    dcs.fire({ id = world.event.S_EVENT_HIT, initiator = dcs.unit("Tanks-Red-1-1"), target = dcs.unit(unitName) })
end

local function logged(fragment)
    for _, line in ipairs(dcs.logs) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

test("only damaged AI aircraft that sit still on the ground count as stranded", function()
    hit("BlueCAP-1-1")
    expect.truthy(stranded.isStranded(dcs.unit("BlueCAP-1-1")))

    hit("RedCAP-1-1")
    dcs.unit("RedCAP-1-1").airborne = true
    expect.falsy(stranded.isStranded(dcs.unit("RedCAP-1-1")), "still flying")

    hit("RedCAP-1-2")
    dcs.unit("RedCAP-1-2").velocity = { x = 40, y = 0, z = 0 }
    expect.falsy(stranded.isStranded(dcs.unit("RedCAP-1-2")), "taxiing")

    local transport = dcs.unit("Transport-Red-1-1")
    expect.falsy(stranded.isStranded(transport), "parked and undamaged")
    transport.life = 1
    expect.truthy(stranded.isStranded(transport), "damage without a hit event, e.g. a collision")
    transport.life = transport.life0

    dcs.unit("Tanks-Red-1-1").life = 1
    expect.falsy(stranded.isStranded(dcs.unit("Tanks-Red-1-1")), "ground vehicles are left alone")

    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet"):getUnit(1)
    hit("BlueStrike-1-1")
    expect.falsy(stranded.isStranded(player), "players are never removed")
end)

test("a stranded aircraft is removed at the second check and its group respawns", function()
    dcs.advance(310)
    expect.truthy(dcs.unit("BlueCAP-1-1"):isExist(), "first check only remembers it")
    expect.truthy(dcs.unit("RedCAP-1-1"):isExist())
    expect.truthy(dcs.unit("Transport-Red-1-1"):isExist())

    dcs.advance(300)
    expect.falsy(dcs.unit("BlueCAP-1-1"):isExist())
    expect.truthy(logged("BlueCAP-1-1 is damaged and has not moved on the ground since the last check, removed"))
    expect.same(industry.respawn.queued(2).paid, { "BlueCAP-1" })

    dcs.advance(60)
    local respawned = dcs.unit("BlueCAP-1-1")
    expect.truthy(respawned:isExist(), "group respawned")
    expect.falsy(stranded.isStranded(respawned), "the respawned aircraft is not damaged")
    dcs.advance(600)
    expect.truthy(respawned:isExist(), "a healthy parked aircraft stays")
end)

test("an aircraft that survives its removal is blown up at the next check", function()
    local unit = dcs.unit("RedCAP-1-2")
    unit.velocity = nil
    unit.destroy = function() end
    local explosions = #dcs.explosions
    dcs.advance(600)
    expect.truthy(logged("RedCAP-1-2 is damaged and has not moved on the ground since the last check, removed"))
    expect.truthy(unit:isExist(), "destroy did not work")
    expect.equal(#dcs.explosions, explosions)
    expect.same(industry.respawn.queued(1).paid, {}, "RedCAP-1-1 is still flying")

    dcs.advance(300)
    expect.equal(#dcs.explosions, explosions + 1)
    expect.equal(dcs.explosions[#dcs.explosions].power, 400)
    expect.truthy(logged("RedCAP-1-2 was not removed, blown up"))
end)

test("nothing logged an error", function()
    local errors = industryFixture.errors()
    expect.equal(#errors, 0, table.concat(errors, " | "))
end)
