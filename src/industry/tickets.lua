--- Tickets limit the length of a mission and decide who wins. Both sides
-- lose tickets over time; losses and destroyed objectives cost extra.
-- When one side has no tickets left the side with more tickets wins, a
-- countdown runs and the next mission is loaded.

local tarmac = require("tarmac")

local log = tarmac.log.new("industry.tickets")
local side = tarmac.side

local tickets = {}

local cfg
local count = { [1] = 0, [2] = 0 }
local winner = nil
local countdown = 0
local finished = false

local winFlags = { [0] = "missionWinNeutral", [1] = "missionWinRed", [2] = "missionWinBlue" }
local lowFlags = { [1] = "ticketsLowRed", [2] = "ticketsLowBlue" }

local function announce(duration)
    trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", count[2], count[1]), duration or 10)
end

local function countdownTick()
    if countdown > 10 then
        if countdown % 60 == 0 then
            local minutes = countdown / 60
            if winner == side.NEUTRAL then
                trigger.action.outText(string.format("MISSION DRAW. No winner. RTB. Mission ends in %d minutes", minutes), 10)
            else
                trigger.action.outTextForCoalition(winner,
                    string.format("MISSION ACCOMPLISHED. RTB. Mission ends in %d minutes", minutes), 10)
                trigger.action.outTextForCoalition(side.enemy(winner),
                    string.format("MISSION FAILED. RTB. Mission ends in %d minutes", minutes), 10)
            end
        end
    elseif countdown >= 0 then
        trigger.action.outText(string.format("Mission ends in %d seconds", countdown), 3)
    end

    countdown = countdown - 1
    if countdown < 0 then
        finished = true
        trigger.action.setUserFlag(winFlags[winner], true)
        log:info("mission finished, winner %s", side.name(winner))
        if net and net.load_next_mission then
            net.load_next_mission()
        end
        return false
    end
end

--- Ends the war. Called automatically when tickets run out.
function tickets.declareWinner(coalitionId)
    if winner ~= nil then
        return
    end
    winner = coalitionId
    countdown = cfg.tickets.winCountdown
    log:info("winner: %s", side.name(winner))
    tarmac.scheduler.every(1, countdownTick, { delay = 0, name = "industry.tickets.countdown" })
end

local function evaluate()
    if count[1] <= 0 or count[2] <= 0 then
        if count[1] > count[2] then
            tickets.declareWinner(side.RED)
        elseif count[2] > count[1] then
            tickets.declareWinner(side.BLUE)
        else
            tickets.declareWinner(side.NEUTRAL)
        end
    end
    for coalitionId, flag in pairs(lowFlags) do
        if count[coalitionId] <= cfg.tickets.low then
            trigger.action.setUserFlag(flag, true)
        end
    end
end

--- Removes tickets from a coalition (id or name). reason is logged.
function tickets.reduce(coalitionId, amount, reason)
    local id = side.id(coalitionId)
    if count[id] == nil then
        log:warn("cannot reduce tickets of unknown coalition %s (%s)", coalitionId, reason)
        return
    end
    if winner ~= nil or amount <= 0 then
        return
    end
    count[id] = math.max(count[id] - amount, 0)
    log:info("%s loses %d tickets: %s", side.name(id), amount, reason)
    trigger.action.outText(string.format("Tickets %s: %d (-%d)", side.name(id), count[id], amount), 10)
    evaluate()
    announce()
end

function tickets.get(coalitionId)
    return count[side.id(coalitionId)] or 0
end

--- Coalition id of the winner, or nil while the war goes on.
function tickets.winner()
    return winner
end

function tickets.isFinished()
    return finished
end

local function tick()
    if winner ~= nil then
        return false
    end
    count[1] = math.max(count[1] - 1, 0)
    count[2] = math.max(count[2] - 1, 0)
    evaluate()
    announce()
end

function tickets.setup(configuration)
    cfg = configuration
    count[1] = cfg.tickets.start
    count[2] = cfg.tickets.start
    tarmac.scheduler.every(cfg.tickets.interval, tick, { name = "industry.tickets.tick" })
end

return tickets
