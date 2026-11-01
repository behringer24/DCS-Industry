-- production, storages and objectives

industryFixture.start()

local economy, objectives, tickets = industry.economy, industry.objectives, industry.tickets

test("objectives are detected by prefix at the start of the unit name", function()
    expect.equal(objectives.get("FactoryRed-1-1").kind, "factory")
    expect.equal(objectives.get("LaboratoryRed-1-1").kind, "laboratory")
    expect.equal(objectives.get("StorageRed-2-1").kind, "storage")
    expect.equal(objectives.get("HQ Red Command Center-1").kind, "hq")
    expect.equal(objectives.get("Secondary-1-1").kind, "secondary")
    expect.isNil(objectives.get("Warehouse decoration-1"))
    expect.equal(objectives.get("StorageBlue-1-1").coalition, 2)
end)

test("enemy objectives are marked with unique ids", function()
    local red, blue = 0, 0
    for _, mark in pairs(dcs.marks) do
        if mark.coalition == 2 then
            red = red + 1
        elseif mark.coalition == 1 then
            blue = blue + 1
        end
    end
    expect.equal(red, 7, "red objectives are shown to blue")
    expect.equal(blue, 2, "blue objectives are shown to red")
    expect.equal(#dcs.markErrors, 0)
end)

test("production adds factory output and laboratory bonus", function()
    expect.equal(economy.resources(1), 500)
    dcs.advance(1)
    -- red: 1 + 2 * 30 = 61, one lab adds 20 % = 12
    expect.equal(economy.resources(1), 573)
    -- blue: 1 + 30 = 31, no lab
    expect.equal(economy.resources(2), 531)
    expect.equal(#dcs.findMessages("New resources produced red 61 tons + 12 labs-bonus"), 1)
end)

test("storages limit the resources", function()
    expect.equal(economy.capacity(2), 1000)
    industry.addResources("blue", 5000)
    expect.equal(economy.resources(2), 1000)
    expect.equal(#dcs.findMessages("Storages of blue are full"), 1)
end)

test("a heavily damaged factory does not produce", function()
    dcs.static("FactoryRed-2-1").life = 1
    expect.equal(objectives.count(1, "factory"), 1)
    dcs.static("FactoryRed-2-1").life = 10
end)

test("a destroyed storage loses its share of resources and tickets", function()
    local resources, ticketsBefore = economy.resources(1), tickets.get(1)
    local markId = objectives.get("StorageRed-1-1").markId
    dcs.kill("StorageRed-1-1")
    expect.equal(economy.resources(1), resources - math.floor(resources / 2))
    expect.equal(tickets.get(1), ticketsBefore - math.ceil(ticketsBefore / 2))
    expect.equal(economy.storages(1), 1)
    expect.equal(dcs.flags["StorageRed-1-1_destroyed"], 1)
    expect.equal(dcs.flags["redStorageDestroyed"], 1)
    expect.isNil(dcs.marks[markId])
    expect.equal(#dcs.smokes, 0, "the smoke follows outside the event handler")
    dcs.advance(1)
    expect.equal(#dcs.smokes, 1)
end)

test("destruction is handled once although UNIT_LOST and DEAD both arrive", function()
    local before = tickets.get(1)
    dcs.kill("FactoryRed-1-1")
    expect.equal(tickets.get(1), before - 10)
    dcs.fire({ id = world.event.S_EVENT_UNIT_LOST, initiator = dcs.static("FactoryRed-1-1") })
    expect.equal(tickets.get(1), before - 10)
    expect.equal(dcs.flags["redFactoryDestroyed"], 1)
    expect.equal(objectives.count(1, "factory"), 1)
end)

test("laboratories and secondary targets cost their tickets", function()
    local before = tickets.get(1)
    dcs.kill("LaboratoryRed-1-1")
    dcs.kill("Secondary-1-1")
    expect.equal(tickets.get(1), before - 5 - 1)
    expect.equal(dcs.flags["redSecondaryDestroyed"], 1)
end)

test("an HQ costs half of the remaining tickets", function()
    local before = tickets.get(1)
    dcs.kill("HQ Red Command Center-1")
    expect.equal(tickets.get(1), before - math.floor(before / 2))
    expect.equal(dcs.flags["redHQDestroyed"], 1)
end)

test("other statics do not cost tickets", function()
    local before = tickets.get(1)
    dcs.kill("Warehouse decoration-1")
    expect.equal(tickets.get(1), before)
end)

test("destroying the last storage empties the coalition", function()
    dcs.kill("StorageRed-2-1")
    expect.equal(economy.storages(1), 0)
    expect.equal(economy.resources(1), 0)
    expect.equal(#dcs.findMessages("All red storages have been destroyed"), 1)
    dcs.advance(300)
    expect.equal(economy.resources(1), 0, "production cannot be stored without storages")
end)
