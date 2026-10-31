-- tickets, player losses and the end of the mission

industryFixture.start({ tickets = { start = 30, low = 25, winCountdown = 120 } })

local tickets = industry.tickets

test("both sides lose a ticket every interval", function()
    dcs.advance(60)
    expect.equal(tickets.get(1), 29)
    expect.equal(tickets.get(2), 29)
end)

test("a destroyed player aircraft costs its coalition a ticket", function()
    local player = dcs.spawnPlayer("BlueStrike-1-1", "Hornet"):getUnit(1)
    dcs.kill(player:getName())
    expect.equal(tickets.get(2), 28)
    expect.equal(tickets.get(1), 29)
end)

test("a player in a dynamic slot unknown to the mission costs a ticket too", function()
    local group = dcs.spawnPlayer(nil, "Viper", {
        name = "Dynamic Viper #7", category = "plane",
        units = { { name = "Dynamic Viper #7-1", type = "F-16C_50", skill = "Client" } },
    }, country.id.USA)
    dcs.kill(group:getUnit(1):getName())
    expect.equal(tickets.get(2), 27)
end)

test("AI losses do not cost tickets", function()
    dcs.kill("BlueCAP-1-1")
    expect.equal(tickets.get(2), 27)
end)

test("events without initiator are ignored", function()
    dcs.fire({ id = world.event.S_EVENT_UNIT_LOST })
    dcs.fire({ id = world.event.S_EVENT_KILL })
    expect.equal(tickets.get(2), 27)
end)

test("the low ticket flag is set below the threshold", function()
    expect.isNil(dcs.flags["ticketsLowBlue"])
    tickets.reduce("blue", 5, "test")
    expect.equal(dcs.flags["ticketsLowBlue"], 1)
end)

test("unknown coalitions are rejected without an error", function()
    tickets.reduce(nil, 5, "test")
    expect.equal(tickets.get(2), 22)
end)

test("blue wins when red runs out of tickets and the blue flag is set", function()
    tickets.reduce("red", 100, "test")
    expect.equal(tickets.winner(), 2)
    dcs.advance(130)
    expect.equal(dcs.flags["missionWinBlue"], 1)
    expect.isNil(dcs.flags["missionWinRed"])
    expect.isNil(dcs.flags["missionWinNeutral"])
    expect.equal(dcs.missionsLoaded, 1)
    dcs.advance(60)
    expect.equal(dcs.missionsLoaded, 1, "the next mission is loaded only once")
    expect.truthy(#dcs.findMessages("MISSION ACCOMPLISHED") > 0)
end)

test("tickets do not change after the war is over", function()
    local blue = tickets.get(2)
    dcs.advance(600)
    expect.equal(tickets.get(2), blue)
end)
