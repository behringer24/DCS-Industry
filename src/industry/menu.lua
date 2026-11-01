--- F10 menu "HQ" for every player group, including dynamic slots: radio
-- calls to the own HQ. A coalition whose HQ was destroyed loses the menu.

local tarmac = require("tarmac")
local economy = require("industry.economy")
local objectives = require("industry.objectives")
local intel = require("industry.intel")

local side = tarmac.side

local menu = {}

local cfg
local entry

--- Answer of the HQ to a supply status request: own coalition only.
function menu.supplyStatus(coalitionId)
    return string.format("HQ: Supply status\nStock: %d t of %d t storage capacity\n"
        .. "Operational: %d factories, %d laboratories, %d storages",
        economy.resources(coalitionId), economy.capacity(coalitionId), objectives.count(coalitionId, "factory"),
        objectives.count(coalitionId, "laboratory"), objectives.count(coalitionId, "storage"))
end

local function requestSupplyStatus(player)
    trigger.action.outTextForGroup(player.groupId, menu.supplyStatus(player.coalition), 20)
end

local function sendReport(player)
    intel.report(player.groupName, player.groupId, player.coalition)
end

function menu.setup(configuration)
    cfg = configuration
    entry = tarmac.menu.forPlayers(function(player)
        local coalitionId = player.coalition
        if (coalitionId ~= side.RED and coalitionId ~= side.BLUE) or not intel.hqAlive(coalitionId) then
            return nil
        end
        local root = missionCommands.addSubMenuForGroup(player.groupId, "HQ")
        if cfg.intel.enabled then
            missionCommands.addCommandForGroup(player.groupId, "Send recon report", root, sendReport, player)
        end
        missionCommands.addCommandForGroup(player.groupId, "Request supply status", root, requestSupplyStatus, player)
        return root
    end)
    tarmac.events.on("industry.hqLost", function()
        tarmac.menu.rebuild(entry)
    end)
end

return menu
