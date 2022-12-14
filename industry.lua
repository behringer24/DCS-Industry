-- Industry script by puni5her

if (industry ~= nil) then return 0 end
industry = {}

industry.config = {
    startRessources = 200,
    factoryProduction = 30,
    storageCapacity = 1000,
    labsboost = 20,
    productionLoopTime = 300,
    respawnLoopTime = 60,
    checkDeadGroupsTime = 300,
    respawnRetriesOnQueue = 2,
    winCountdownLength = 600,
    tickets = 100,
}

industry.version = "v0.9.0"
industry.ressources = {red = 200, blue = 200}
industry.factories = {red= 1, blue = 1}
industry.storages = {red= 1, blue = 1}
industry.labs = {red = 0, blue = 0}
industry.hq = {red = 1, blue = 1}
industry.tickets = {red = 100, blue = 100}
industry.respawnGroup = {}
industry.respawnTriesBlue = 0
industry.respawnTriesRed = 0
industry.winner = nil
industry.winCountdown = 600

---------------------------------------------------------
-- Queue implementation
-- element needs to have a name field to block from
-- adding elements to queue multiple times
---------------------------------------------------------
industry.Queue = function()
    local queue = {}
    local lock = {}
    local head = 0
    local last = -1

    function queue.push(element)
        if (lock[element.name]) then return end
        last = last + 1
        queue[last] = element
        lock[element.name] = true
        env.info("Pushed "..element.name.." to queue")
    end

    function queue.get()
        if (head > last) then return nil end
        env.info("Read "..queue[head].name.." in queue")
        return queue[head]
    end
    
    function queue.pop()
        if (head > last) then return nil end
        local _result = queue[head]
        lock[_result.name] = nil
        queue[head] = nil
        head = head + 1
        env.info("Poped ".._result.name.." from queue")
        return _result
    end

    return queue
end

industry.respawnQueueRed = industry.Queue()
industry.respawnQueueBlue = industry.Queue()
industry.respawnQueueRedFree = industry.Queue()
industry.respawnQueueBlueFree = industry.Queue()

---------------------------------------------------------
-- Get group name of unit
-- Uses MIST so it also works on dead groups
---------------------------------------------------------
function industry.getGroupNameByUnitName(unitname)
    if (mist.DBs.unitsByName[unitname]) then
        return mist.DBs.unitsByName[unitname].groupName
    else
        return nil
    end
end

---------------------------------------------------------
-- Get coalition of group by groupname
-- Uses MIST so it also works on dead groups
---------------------------------------------------------
function industry.getCoalitionByGroupname(groupname)
    if (mist.DBs.groupsByName[groupname]) then
        return mist.DBs.groupsByName[groupname].coalition
    else
        return nil
    end
end

---------------------------------------------------------
-- Destroy group without triggering events
---------------------------------------------------------
function industry.destroy(gpName)
    local _group = Group.getByName(gpName)
    Group.destroy(_group)
end

---------------------------------------------------------
-- Queue group for respawn
-- If costs = 0 then the unit is added to the free respawn
---------------------------------------------------------
function industry.queueRespawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)

    if (costs == 0) then
        if (groupdata.coalition == "red") then
            industry.respawnQueueRedFree.push({name = gpName, cost = 0})
        else
            industry.respawnQueueBlueFree.push({name = gpName, cost = 0})
        end
    else
        if (groupdata.coalition == "red") then
            industry.respawnQueueRed.push({name = gpName, cost = costs})
        else
            industry.respawnQueueBlue.push({name = gpName, cost = costs})
        end
    end
end

---------------------------------------------------------
-- Respan unit only if ressources are available
-- returns true on success
---------------------------------------------------------
function industry.respawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)

    if (groupdata.coalition == "red") then
        if industry.ressources.red >= costs then
            industry.ressources.red = industry.ressources.red - costs
            mist.respawnGroup(gpName, true)
            if (costs > 0) then
                trigger.action.outText(string.format("Respawned red group %s for %d tons of ressources", gpName, costs), 10)
            else
                trigger.action.outText(string.format("Respawned red group %s", gpName), 10)
            end
            return true
        end
    else
        if industry.ressources.blue >= costs then
            industry.ressources.blue = industry.ressources.blue - costs
            mist.respawnGroup(gpName, true)
            if (costs > 0) then
                trigger.action.outText(string.format("Respawned blue group %s for %d tons of ressources", gpName, costs), 10)
            else
                trigger.action.outText(string.format("Respawned blue group %s", gpName), 10)
            end
            return true
        end
    end
    return false
end

---------------------------------------------------------
-- Add ressources to coalition from transports
-- Used e.g. from landing trigger in mission editor when
-- air units reach destination
---------------------------------------------------------
function industry.addRessourcesTransport(coalition, tons)
    trigger.action.outText(string.format("A %s transport with %d tons of ressources arrived at its destination", coalition, tons), 5)
    industry.addRessources(coalition, tons)
end

---------------------------------------------------------
-- Add ressources to coalition
-- Central function to add ressources
-- Limits ressources to storage space
---------------------------------------------------------
function industry.addRessources(coalition, tons)
    if (string.match(coalition, "red")) then
        industry.ressources.red = industry.ressources.red + tons
        if (industry.ressources.red > industry.storages.red * industry.config.storageCapacity) then
            industry.ressources.red = industry.storages.red * industry.config.storageCapacity
            trigger.action.outText("RED storages are full", 3)
        end
    else
        industry.ressources.blue = industry.ressources.blue + tons
        if (industry.ressources.blue > industry.storages.blue * industry.config.storageCapacity) then
            industry.ressources.blue = industry.storages.blue * industry.config.storageCapacity
            trigger.action.outText("BLUE storages are full", 3)
        end
    end
end

---------------------------------------------------------
-- Add ressources from convoy
-- multiplys tonsEach with (still) existing units of type
-- to add to ressources. E.g. without trucks 0 delivery
---------------------------------------------------------
function industry.addRessourcesConvoy(groupName, truckTypeName, tonsEach)
    local _group = Group.getByName(groupName)
    local _addRessources = 0

    if (_group) then
        -- not using Group.getUnits() due to DCS bug with some unit types        
        for i=1,_group:getSize() do
            local _unit = _group:getUnit(i)
            env.info(string.format("Convoy %s arrived. Unit %d: %s", groupName, i, _unit:getTypeName()), false)
            if (string.match(_unit:getTypeName(), truckTypeName) and _unit:getLife() > 1) then
                _addRessources = _addRessources + tonsEach
            end
        end

        if (_group:getCoalition() == 1) then
            trigger.action.outText(string.format("A RED convoy with %d tons of ressources arrived at its destination", _addRessources), 5)
            industry.addRessources("red", _addRessources)
        else            
            trigger.action.outText(string.format("A BLUE convoy with %d tons of ressources arrived at its destination", _addRessources), 5)
            industry.addRessources("blue", _addRessources)
        end
    end
end

---------------------------------------------------------
-- Called when all storages are destroyed on one side
-- Loops to update countdown until restart
---------------------------------------------------------
function industry.winMission(winner)
    if (industry.winner == nil) then
        industry.winner = winner

        if (industry.winner == coalition.side.RED) then
            industry.loser = coalition.side.BLUE
        else if (industry.winner == coalition.side.BLUE) then
                industry.loser = coalition.side.RED
            else
                industry.loser = coalition.side.NEUTRAL
            end
        end

        industry.winCountdown = industry.config.winCountdownLength

        -- self schedule every second
        mist.scheduleFunction(industry.winMission,{industry.winner} , timer.getTime() + 1, 1)
    end

    if (industry.winCountdown > 10) then
        if (industry.winCountdown % 60 == 0) then
            if (industry.winner == coalition.side.NEUTRAL) then
                trigger.action.outText(string.format("MISSION DRAW. No winner. RTB. Mission ends in %d minutes", industry.winCountdown / 60), 10)
            else
                trigger.action.outTextForCoalition(industry.winner, string.format("MISSION ACCOMPLISHED. RTB. Mission ends in %d minutes", industry.winCountdown / 60), 10)
                trigger.action.outTextForCoalition(industry.loser,  string.format("MISSION FAILED. RTB. Mission ends in %d minutes", industry.winCountdown / 60), 10)
            end
        end
    else
        trigger.action.outText(string.format("Mission ends in %d seconds", industry.winCountdown), 3)
    end

    industry.winCountdown = industry.winCountdown - 1

    if (industry.winCountdown < 0) then
        if (industry.winner == coalition.side.RED) then
            trigger.action.setUserFlag('missionWinRed', true)
        else if (industry.winner == coalition.side.RED) then
                trigger.action.setUserFlag('missionWinBlue', true)
            else
                trigger.action.setUserFlag('missionWinNeutral', true)
            end
        end
        -- net.missionlist_set_loop(true)
        net.load_next_mission()
    end
end

---------------------------------------------------------
-- Destroy storage space and remove ressources
---------------------------------------------------------
function industry.destroyStorage(coa)
    if (string.match(coa, "red") and industry.storages.red > 0) then
        industry.ressources.red = industry.ressources.red - math.floor(industry.ressources.red / industry.storages.red)
        industry.reduceTickets("red", math.ceil(industry.tickets.red / industry.storages.red))
        industry.storages.red = industry.storages.red - 1

        if (industry.storages.red == 0) then
            -- industry.winMission(coalition.side.BLUE)
            trigger.action.outText(string.format("All RED storages have been destroyed", industry.ressources.red), 10)
        else
            trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 10)   
        end
    end

    if (string.match(coa, "blue") and industry.storages.blue > 0) then
        industry.ressources.blue = industry.ressources.blue - math.floor(industry.ressources.blue / industry.storages.blue)
        industry.reduceTickets("blue", math.ceil(industry.tickets.blue / industry.storages.blue))
        industry.storages.blue = industry.storages.blue - 1

        if (industry.storages.blue == 0) then
            -- industry.winMission(coalition.side.RED)
            trigger.action.outText(string.format("All BLUE storages have been destroyed", industry.ressources.red), 10)
        else
            trigger.action.outText(string.format("A BLUE storage has been destroyed. %d tons ressources left", industry.ressources.blue), 10)  
        end 
    end
end

---------------------------------------------------------
-- Add group to automatically respawn handler
-- Used from mision editor and/or init script
---------------------------------------------------------
function industry.addRespawnGroup(name, cost)
    industry.respawnGroup[name] = cost
end

---------------------------------------------------------
-- Production loop
-- adds ressources from factories
-- also counts factories and storages
---------------------------------------------------------
function industry.productionLoop()
    trigger.action.outText("Industry ressources arrived", 5)

    local _redObjects = coalition.getStaticObjects(1)
    local _countRedFactories = 0
    local _countRedStorages = 0
    local _countRedLabs = 0
    local _addRessourcesRed = 1
    local _labsBonusRed = 0
    for k, v in pairs(_redObjects) do
        local _name = v:getName()
        local _type = v:getTypeName()
        local _health = v:getLife()

        if (string.match(_name, "Laboratory.*") and _health > 1) then
            _countRedLabs = _countRedLabs + 1
		end

        if (string.match(_name, "Factory.*") and _health > 1) then
            _addRessourcesRed = _addRessourcesRed + industry.config.factoryProduction
            _countRedFactories = _countRedFactories + 1;   
		end

        if (string.match(_name, "Storage.*") and _health > 1) then            
            _countRedStorages = _countRedStorages + 1;   
		end
    end
    _labsBonusRed = _addRessourcesRed * (industry.config.labsboost / 100) * _countRedLabs
    industry.factories.red = _countRedFactories
    industry.storages.red = _countRedStorages
    industry.labs.red = _countRedLabs
    industry.addRessources("red", _addRessourcesRed + _labsBonusRed)

    local _blueObjects = coalition.getStaticObjects(2)
    local _countBlueFactories = 0
    local _countBlueStorages = 0
    local _countBlueLabs = 0
    local _addRessourcesBlue = 1
    local _labsBonusBlue = 0
    for k, v in pairs(_blueObjects) do
        local _name = v:getName()
        local _type = v:getTypeName()
        local _health = v:getLife()

        if (string.match(_name, "Laboratory.*") and _health > 1) then
            _countBlueLabs = _countBlueLabs + 1
		end

        if (string.match(_name, "Factory.*") and _health > 1) then
            _addRessourcesBlue = _addRessourcesBlue + industry.config.factoryProduction 
            _countBlueFactories = _countBlueFactories + 1
		end

        if (string.match(_name, "Storage.*") and _health > 1) then            
            _countBlueStorages = _countBlueStorages + 1;   
		end
    end
    _labsBonusBlue = _addRessourcesBlue * (industry.config.labsboost / 100) * _countBlueLabs
    industry.factories.blue = _countBlueFactories
    industry.storages.blue = _countBlueStorages
    industry.labs.blue = _countBlueLabs
    industry.addRessources("blue", _addRessourcesBlue + _labsBonusBlue)

    trigger.action.outText(string.format("New Ressources produced\n"..
        "BLUE %d tons + %d labs-bonus   RED %d tons + %d labs-bonus", _addRessourcesBlue, _labsBonusBlue, _addRessourcesRed, _labsBonusRed), 10)
    trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets.blue, industry.tickets.red), 10)
end

---------------------------------------------------------
-- Checks periodically if units can spawn
-- checks free units (0 cost) independently
-- only one unit per queue spawns until next scheduled run
---------------------------------------------------------
function industry.respawnLoop()
    local _blueGroup = industry.respawnQueueBlue.get()
    if (_blueGroup) then
        if (mist.groupIsDead(_blueGroup.name) or industry.respawnTriesBlue > industry.config.respawnRetriesOnQueue - 1) then
            if (industry.respawn(_blueGroup.name, _blueGroup.cost)) then
                industry.respawnQueueBlue.pop()
                industry.respawnTriesBlue = 0
                trigger.action.setUserFlag(_blueGroup.name .. '_respawn', true)                
            end
        else
            env.info(string.format("Group %s not dead for respawning. Retry no. %d", _blueGroup.name, industry.respawnTriesBlue), false)
            industry.respawnTriesBlue = industry.respawnTriesBlue + 1
        end
    end

    local _blueGroupFree = industry.respawnQueueBlueFree.pop()
    if (_blueGroupFree) then
        industry.respawn(_blueGroupFree.name, 0)
        trigger.action.setUserFlag(_blueGroupFree.name .. '_respawn', true)
    end
    
    local _redGroup = industry.respawnQueueRed.get()
    if (_redGroup) then
        if (mist.groupIsDead(_redGroup.name) or industry.respawnTriesRed > industry.config.respawnRetriesOnQueue - 1) then
            if (industry.respawn(_redGroup.name, _redGroup.cost)) then
                industry.respawnQueueRed.pop()
                industry.respawnTriesRed = 0
                trigger.action.setUserFlag(_redGroup.name .. '_respawn', true)
            end
        else
            env.info(string.format("Group %s not dead for respawning. Retry no. %d", _redGroup.name, industry.respawnTriesRed), false)
            industry.respawnTriesRed = industry.respawnTriesRed + 1
        end
    end

    local _redGroupFree = industry.respawnQueueRedFree.pop()
    if (_redGroupFree) then
        industry.respawn(_redGroupFree.name, 0)
        trigger.action.setUserFlag(_redGroupFree.name .. '_respawn', true)
    end
    
    -- trigger.action.outText(string.format("BLUE (%d/%d/%d): %d tons    RED (%d/%d/%d): %d tons", industry.factories.blue, industry.storages.blue, industry.labs.blue, industry.ressources.blue, industry.factories.red, industry.storages.red, industry.labs.red, industry.ressources.red), 10)
end

---------------------------------------------------------
-- Loop to check for unhandled dead groups
-- Occur when AI did emergency landings and just despawn
---------------------------------------------------------
function industry.checkDeadGroups()
    for _groupname, _cost in pairs(industry.respawnGroup) do
        if (mist.groupIsDead(_groupname)) then
            env.info(string.format("Check group:%s", _groupname), false)
            env.info(string.format("Found unhandled dead group:%s coalition:%s cost:%d, try to requeue", _groupname, industry.getCoalitionByGroupname(_groupname), _cost), false)
            industry.queueRespawn(_groupname, _cost)
        end
    end
end

---------------------------------------------------------
-- Called when group asks for industry statistics
---------------------------------------------------------
function industry.radioStatistics(groupId)    
    trigger.action.outTextForGroup(groupId, string.format(
        "BLUE Fact: %2d   Labs: %2d    Stor: %2d    Ress: %4d\n"..
        "RED   Fact: %2d   Labs: %2d    Stor: %2d    Ress: %4d",
            industry.factories.blue, industry.labs.blue, industry.storages.blue, industry.ressources.blue,
            industry.factories.red,  industry.labs.red,  industry.storages.red,  industry.ressources.red
        ), 20)
    trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets.blue, industry.tickets.red), 10)
end

---------------------------------------------------------
-- Add radio menu to all groups with human player slots
---------------------------------------------------------
function industry.addRadioMenu()
    local groups = {}
    for k,v in pairs(mist.DBs.humansByName) do
        groups[v.groupId] = v.groupName;
    end
    
    for k,v in pairs(groups) do
        local main = missionCommands.addSubMenuForGroup(k, 'Industry')
        missionCommands.addCommandForGroup(k, 'Get current statistics', main, industry.radioStatistics, k)
        env.info(string.format("Add radioStatistics command for group %s (%d)", v, k))
    end
end

---------------------------------------------------------
-- Evaluate if one party won by tickets
-- Called internally only
---------------------------------------------------------
function industry.evaluateTicketWinner()
    if (industry.tickets.red <= 0 or industry.tickets.blue <= 0) then
        if (industry.tickets.red > industry.tickets.blue) then
            industry.winMission(coalition.side.RED)
        else if (industry.tickets.blue > industry.tickets.red) then
                industry.winMission(coalition.side.BLUE)
            else
                industry.winMission(coalition.side.NEUTRAL)
            end
        end
    end
end

---------------------------------------------------------
-- Reduce tickets of one coalition
---------------------------------------------------------
function industry.reduceTickets(coal, tickets)
    if (industry.winner == nil) then
        if (coal == "red") then
            industry.tickets.red = industry.tickets.red - tickets
            if (industry.tickets.red < 0) then
                industry.tickets.red = 0
            end
            trigger.action.outText(string.format("Tickets: RED %d (-%d)", industry.tickets.red, tickets), 10)
        else
            industry.tickets.blue = industry.tickets.blue - tickets
            if (industry.tickets.blue < 0) then
                industry.tickets.blue = 0
            end
            trigger.action.outText(string.format("Tickets: BLUE %d (-%d)", industry.tickets.blue, tickets), 10)
        end

        industry.evaluateTicketWinner()

        trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets.blue, industry.tickets.red), 10)
    end
end

---------------------------------------------------------
-- Scheduled function to countdown tickets every minute
---------------------------------------------------------
function industry.tickerTickets()
    if (industry.winner == nil) then
        industry.tickets.red = industry.tickets.red - 1
        industry.tickets.blue = industry.tickets.blue - 1

        industry.evaluateTicketWinner()

        trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets.blue, industry.tickets.red), 10)
    end
end

---------------------------------------------------------
-- Event handler for landings and units lost
-- despawns landed units when engine shuts down
-- Queues groups when last unit of group dies
---------------------------------------------------------
industry.eventHandler = {}
function industry.eventHandler:onEvent(event)
    -- events to handle
    if (event.id == world.event.S_EVENT_ENGINE_SHUTDOWN or 
            event.id == world.event.S_EVENT_UNIT_LOST or
            event.id == world.event.S_EVENT_EJECTION) then
        local _name = event.initiator:getName()
        env.info(string.format("Handling event ID %d Unit %s", event.id, _name), false)
        local _groupname = industry.getGroupNameByUnitName(_name)

        if (_groupname) then
            -- plane landed and engine shut off. Despawn unit to enable respawn of group
            if (event.id == world.event.S_EVENT_ENGINE_SHUTDOWN) then
                if (industry.respawnGroup[_groupname]) then  
                    event.initiator:destroy()
                    trigger.action.setUserFlag(_name .. '_landed', true)
                end
            end

            -- pilot jumps from plane. Explode plane to handle landed helis that do not despawn
            if (event.id == world.event.S_EVENT_EJECTION) then
                if (industry.respawnGroup[_groupname]) then                    
                    trigger.action.explosion(event.initiator:getPosition().p, 400)
                    env.info(string.format("Pilot ejected from unit %s, explode it", _name), false)
                end
            end

            -- unit is lost / pre-destroyed
            if (event.id == world.event.S_EVENT_UNIT_LOST) then                
                if (mist.getGroupData(_groupname) and mist.getGroupData(_groupname).category == 'static') then
                    -- handle factory destruction
                    if (string.match(_name,'Factory.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.75)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.outText(string.format("Factory of %s coalition destroyed", industry.getCoalitionByGroupname(_groupname)), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 5)
                    end

                    -- handle storage destruction
                    if (string.match(_name,'Storage.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        industry.destroyStorage(industry.getCoalitionByGroupname(_groupname))
                    end

                    -- handle laboratory destruction
                    if (string.match(_name,'Laboratory.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.outText(string.format("Laboratory of %s coalition destroyed", industry.getCoalitionByGroupname(_groupname)), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                    end

                    -- handle HQ destruction
                    if (string.match(_name,'HQ.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.outText(string.format("HQ of %s coalition destroyed", industry.getCoalitionByGroupname(_groupname)), 10)

                        if (industry.getCoalitionByGroupname(_groupname) == 'red') then
                            industry.reduceTickets('red', math.floor(industry.tickets.red / 2))
                        else
                            industry.reduceTickets('blue', math.floor(industry.tickets.blue / 2))
                        end
                    end
                end

                -- vehicle destruction adds a fire and smoke
                if (mist.getGroupData(_groupname) and mist.getGroupData(_groupname).category == 'vehicle') then
                    local _pos = event.initiator:getPosition().p
                    if (_pos) then
                        trigger.action.effectSmokeBig(_pos, 1, 0.5)
                        env.info(string.format("Spawn smoke effect at unit location %s", _name))
                    end

                    -- industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                end

                -- player plane destruction reduces tickets
                if (mist.getGroupData(_groupname) and mist.getGroupData(_groupname).category ~= 'vehicle' and mist.getGroupData(_groupname).category ~= 'static' and event.initiator:getPlayerName() ~= nil) then
                    env.info(string.format("Player %s (%s) killed. Reduce tickets of %s", event.initiator:getPlayerName(), _name, industry.getCoalitionByGroupname(_groupname)))
                    industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                end
            end

            -- if group has only this one dead unit left, queue for respawn
            local _group = Group.getByName(_groupname)
            if ((_group == nil or #_group:getUnits() < 2) and industry.respawnGroup[_groupname]) then
                industry.queueRespawn(_groupname, industry.respawnGroup[_groupname])
            end     
        end
    end
end

---------------------------------------------------------
-- Initialize handlers and loops
-- called 5sec deferred to enable settings
-- from mission designer
---------------------------------------------------------
function industry.scheduleHandlers()
    world.addEventHandler(industry.eventHandler)
    env.info('Industry eventHandler initialized')

    mist.scheduleFunction(industry.productionLoop,{} , timer.getTime() + 1, industry.config.productionLoopTime)
    env.info(string.format('Industry productionLoop initialized (%d seconds)', industry.config.productionLoopTime))

    mist.scheduleFunction(industry.respawnLoop,{} , timer.getTime() + 35, industry.config.respawnLoopTime)
    env.info(string.format('Industry respawnLoop initialized (%d seconds)', industry.config.respawnLoopTime))

    mist.scheduleFunction(industry.checkDeadGroups,{} , timer.getTime() + 304, industry.config.checkDeadGroupsTime)    
    env.info(string.format('Industry checkDeadGroups initialized (%d seconds)', industry.config.checkDeadGroupsTime))

    mist.scheduleFunction(industry.tickerTickets,{} , timer.getTime() + 60, 60)    
    env.info(string.format('Industry tickerTickets initialized (%d seconds)', 60))

    industry.ressources.red = industry.config.startRessources
    industry.ressources.blue = industry.config.startRessources
    industry.tickets.red = industry.config.tickets
    industry.tickets.blue = industry.config.tickets
end

---------------------------------------------------------
-- Init Industry script
---------------------------------------------------------
industry.addRadioMenu()
mist.scheduleFunction(industry.scheduleHandlers,{} , timer.getTime() + 5)
env.info('Industry ' .. industry.version .. ' initialized')