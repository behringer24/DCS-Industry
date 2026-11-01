--- F10 menu "Industry" for every player group, including dynamic slots.

local tarmac = require("tarmac")
local economy = require("industry.economy")
local production = require("industry.production")
local tickets = require("industry.tickets")

local menu = {}

--- Text of the statistics message.
function menu.statistics()
    local blue, red = production.report(2), production.report(1)
    return string.format(
        "BLUE Fact: %2d   Labs: %2d    Stor: %2d    Res: %4d\n" ..
        "RED   Fact: %2d   Labs: %2d    Stor: %2d    Res: %4d\n" ..
        "Tickets: BLUE %d    RED %d",
        blue.factories, blue.labs, blue.storages, economy.resources(2),
        red.factories, red.labs, red.storages, economy.resources(1),
        tickets.get(2), tickets.get(1))
end

local function showStatistics(groupId)
    trigger.action.outTextForGroup(groupId, menu.statistics(), 20)
end

function menu.setup()
    tarmac.menu.forPlayers(function(player)
        local root = missionCommands.addSubMenuForGroup(player.groupId, "Industry")
        missionCommands.addCommandForGroup(player.groupId, "Get current statistics", root, showStatistics, player.groupId)
        return root
    end)
end

return menu
