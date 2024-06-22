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

industry.version = "v0.11.0"
industry.ressources = {[coalition.side.RED] = 200, [coalition.side.BLUE] = 200}
industry.factories = {[coalition.side.RED] = 1, [coalition.side.BLUE] = 1}
industry.storages = {[coalition.side.RED] = 1, [coalition.side.BLUE] = 1}
industry.labs = {[coalition.side.RED] = 0, [coalition.side.BLUE] = 0}
industry.hq = {[coalition.side.RED] = 1, [coalition.side.BLUE] = 1}
industry.tickets = {[coalition.side.RED] = 100, [coalition.side.BLUE] = 100}
industry.respawnGroup = {}
industry.respawnTries = {[coalition.side.RED] = 0, [coalition.side.BLUE] = 0}
industry.winner = nil
industry.winCountdown = 600
industry.downedPilotCounter = 0
industry.sarmissioncounter = 0

industry.coalitionNameToId = {
    ["neutral"] = 0,
    ["red"] = 1,
    ["blue"] = 2
}

industry.coalitionIdToName = {
    [0] = "neutral",
    [1] = "red",
    [2] = "blue"
}

industry.mapMarkers = {}

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

industry.respawnQueue = {[coalition.side.RED] = industry.Queue(), [coalition.side.BLUE] = industry.Queue()}
industry.respawnQueueFree = {[coalition.side.RED] = industry.Queue(), [coalition.side.BLUE] = industry.Queue()}

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
        return industry.coalitionNameToId[mist.DBs.groupsByName[groupname].coalition]
    else
        return nil
    end
end

---------------------------------------------------------
-- Get coalition of group by groupname
-- Uses DCS directly so unit has to be alive
---------------------------------------------------------
function industry.getCoalitionByUnitname(unitname)
    local _unit = Unit.getByName(unitname)
    if (_unit) then
        return _unit:getCoalition()
    else
        return nil
    end
end

---------------------------------------------------------
-- Clone group by name with new route
-- Uses Mist
---------------------------------------------------------
function industry.cloneGroupNewRoute(gpName, route, newgroupname)
    local vars = {}
    vars.gpName = gpName
    vars.action = 'clone'
    vars.route = route
    vars.newGroupName = newgroupname or nil
    local newGroup = mist.teleportToPoint(vars)
    return newGroup
end

function industry.cloneUnitToInfantry(oldunit, coal, country)    
    local _pos = oldunit:getPoint()   
    local _newtype = ''

    if (coal == coalition.side.RED) then
        _newtype = 'Infantry AK'      
    else
        _newtype = 'Soldier M4'
    end

    industry.downedPilotCounter = industry.downedPilotCounter + 1

    local _groupname = string.format("DownedPilot-%d", industry.downedPilotCounter)

    env.info(string.format("Cloning downed pilot to %s (%s), Country: %s", _groupname, _newtype, country), false)
    
    local _newsoldier = {
        visible = true,
        taskSelected = true,
        route = {
        }, -- end of ["route"]        
        tasks = {
        }, -- end of ["tasks"]
        hidden = false,
        units = {
            [1] = {
                type = _newtype,
                transportable = 
                {
                    ["randomTransportable"] = false,
                }, -- end of ["transportable"]                
                skill = "Average",
                y = _pos.z,
                x = _pos.x + 1,
                name = _groupname .. '-1',
                playerCanDrive = true,
                heading = 0.28605144170571,
            }, -- end of [1]
        }, -- end of ["units"]
        y = _pos.z,
        x = _pos.x + 1,
        name = _groupname,
        start_time = 0,
        task = "Ground Nothing",
    }

    coalition.addGroup(country, Group.Category.GROUND, _newsoldier)
    oldunit:destroy()
    return _groupname
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
    local coal = industry.getCoalitionByGroupname(gpName)

    if (costs == 0) then
        industry.respawnQueueFree[coal].push({name = gpName, cost = 0})
    else
        industry.respawnQueue[coal].push({name = gpName, cost = costs})
    end
end

---------------------------------------------------------
-- Respan unit only if ressources are available
-- returns true on success
---------------------------------------------------------
function industry.respawn(gpName, costs)
    local coal = industry.getCoalitionByGroupname(gpName)

    if industry.ressources[coal] >= costs then
        industry.ressources[coal] = industry.ressources[coal] - costs
        mist.respawnGroup(gpName, true)
        if (costs > 0) then
            trigger.action.outText(string.format("Respawned %s group %s for %d tons of ressources", industry.coalitionIdToName[coal], gpName, costs), 10)
        else
            trigger.action.outText(string.format("Respawned %s group %s", industry.coalitionIdToName[coal], gpName), 10)
        end
        return true
    end
    
    return false
end

---------------------------------------------------------
-- Add ressources to coalition from transports
-- Used e.g. from landing trigger in mission editor when
-- air units reach destination
---------------------------------------------------------
function industry.addRessourcesTransport(coal, tons)
    trigger.action.outText(string.format("A %s transport with %d tons of ressources arrived at its destination", industry.coalitionIdToName[coal], tons), 5)
    industry.addRessources(coal, tons)
end

---------------------------------------------------------
-- Add ressources to coalition
-- Central function to add ressources
-- Limits ressources to storage space
---------------------------------------------------------
function industry.addRessources(coal, tons)
    industry.ressources[coal] = industry.ressources[coal] + tons
    if (industry.ressources[coal] > industry.storages[coal] * industry.config.storageCapacity) then
        industry.ressources[coal] = industry.storages[coal] * industry.config.storageCapacity
        trigger.action.outText(string.format("Storages of %s are full", industry.coalitionIdToName[coal]), 3)
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

        trigger.action.outText(string.format("A %s convoy with %d tons of ressources arrived at its destination", industry.coalitionIdToName[_group:getCoalition()], _addRessources), 5)
        industry.addRessources(_group:getCoalition(), _addRessources)
    end
end

---------------------------------------------------------
-- Production loop
-- adds ressources from factories
-- also counts factories and storages
---------------------------------------------------------
function industry.PrepareMap()
    trigger.action.outText("Marking map objects", 5)

    for coal=1, 2 do
        local _Objects = coalition.getStaticObjects(coal)
        local _ObjectIds = 0
        local _enemyCoal = 0

        if (coal == 1) then
            _enemyCoal = 2
        else
            _enemyCoal = 1
        end

        for k, v in pairs(_Objects) do
            local _name = v:getName()
            local _type = v:getTypeName()
            local _pos = v:getPoint()
            local _coalition = v:getCoalition()

            if (string.match(_name, "Laboratory.*")) then
                _ObjectIds = _ObjectIds + 1
                trigger.action.markToCoalition(_ObjectIds , string.format("Laboratory of %s boosting factory production", industry.coalitionIdToName[coal]), _pos, _enemyCoal, true)
                env.info(string.format("Object %s marked on Map as %d for coalition %d", _name, _ObjectIds, coal), false)
                industry.mapMarkers[_name] = _ObjectIds
            end

            if (string.match(_name, "Factory.*")) then
                _ObjectIds = _ObjectIds + 1
                trigger.action.markToCoalition(_ObjectIds , string.format("Factory of %s producing ressources (Secondary target)", industry.coalitionIdToName[coal]), _pos, _enemyCoal, true)
                env.info(string.format("Object %s marked on Map as %d for coalition %d", _name, _ObjectIds, coal), false)
                industry.mapMarkers[_name] = _ObjectIds
            end

            if (string.match(_name, "Storage.*")) then            
                _ObjectIds = _ObjectIds + 1
                trigger.action.markToCoalition(_ObjectIds , string.format("Storage of %s for ressources (Primary target)", industry.coalitionIdToName[coal]), _pos, _enemyCoal, true)
                env.info(string.format("Object %s marked on Map as %d for coalition %d", _name, _ObjectIds, coal), false)
                industry.mapMarkers[_name] = _ObjectIds
            end

            if (string.match(_name, "Secondary.*")) then            
                _ObjectIds = _ObjectIds + 1
                trigger.action.markToCoalition(_ObjectIds , string.format("Operative target of %s (optional target)", industry.coalitionIdToName[coal]), _pos, _enemyCoal, true)
                env.info(string.format("Object %s marked on Map as %d for coalition %d", _name, _ObjectIds, coal), false)
                industry.mapMarkers[_name] = _ObjectIds
            end
        end
    end

    trigger.action.outText("Map objects marked", 10)
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
function industry.destroyStorage(coal)
    if (industry.storages[coal] > 0) then
        industry.ressources[coal] = industry.ressources[coal] - math.floor(industry.ressources[coal] / industry.storages[coal])
        industry.reduceTickets(coal, math.ceil(industry.tickets[coal] / industry.storages[coal]))
        industry.storages[coal] = industry.storages[coal] - 1

        if (industry.storages[coal] == 0) then
            trigger.action.outText(string.format("All %s storages have been destroyed", industry.coalitionIdToName[coal], industry.ressources[coal]), 10)
        else
            trigger.action.outText(string.format("A %sstorage has been destroyed. %d tons ressources left", industry.coalitionIdToName[coal], industry.ressources[coal]), 10)   
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

    for coal=1, 2 do
        local _Objects = coalition.getStaticObjects(coal)
        local _countFactories = 0
        local _countStorages = 0
        local _countLabs = 0
        local _addRessources= 1
        local _labsBonus = 0

        for k, v in pairs(_Objects) do
            local _name = v:getName()
            local _type = v:getTypeName()
            local _health = v:getLife()

            if (string.match(_name, "Laboratory.*") and _health > 1) then
                _countLabs = _countLabs + 1
            end

            if (string.match(_name, "Factory.*") and _health > 1) then
                _addRessources = _addRessources + industry.config.factoryProduction
                _countFactories = _countFactories + 1;   
            end

            if (string.match(_name, "Storage.*") and _health > 1) then            
                _countStorages = _countStorages + 1;   
            end
        end

        _labsBonus = _addRessources * (industry.config.labsboost / 100) * _countLabs
        industry.factories[coal] = _countFactories
        industry.storages[coal] = _countStorages
        industry.labs[coal] = _countLabs
        industry.addRessources(coal, _addRessources + _labsBonus)

        trigger.action.outText(string.format("New Ressources produced %s "..
            "%d tons + %d labs-bonus", industry.coalitionIdToName[coal], _addRessources, _labsBonus), 10)
    end
end

---------------------------------------------------------
-- Checks periodically if units can spawn
-- checks free units (0 cost) independently
-- only one unit per queue spawns until next scheduled run
---------------------------------------------------------
function industry.respawnLoop()
    for coal = 1, 2 do
        local _group = industry.respawnQueue[coal].get()
        if (_group) then
            if (mist.groupIsDead(_group.name) or industry.respawnTries[coal] > industry.config.respawnRetriesOnQueue - 1) then
                if (industry.respawn(_group.name, _group.cost)) then
                    industry.respawnQueue[coal].pop()
                    industry.respawnTries[coal] = 0
                    trigger.action.setUserFlag(_group.name .. '_respawn', true)                
                end
            else
                env.info(string.format("Group %s not dead for respawning. Retry no. %d", _group.name, industry.respawnTries[coal]), false)
                industry.respawnTries[coal] = industry.respawnTries[coal] + 1
            end
        end

        local _groupFree = industry.respawnQueueFree[coal].pop()
        if (_groupFree) then
            industry.respawn(_groupFree.name, 0)
            trigger.action.setUserFlag(_groupFree.name .. '_respawn', true)
        end
    end
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
            industry.factories[2], industry.labs[2], industry.storages[2], industry.ressources[2],
            industry.factories[1], industry.labs[1], industry.storages[1], industry.ressources[1]
        ), 20)
    trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets[coalition.side.BLUE], industry.tickets[coalition.side.RED]), 20)
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
    if (industry.tickets[coalition.side.RED] <= 0 or industry.tickets[coalition.side.BLUE] <= 0) then
        if (industry.tickets[coalition.side.RED] > industry.tickets[coalition.side.BLUE]) then
            industry.winMission(coalition.side.RED)
        else if (industry.tickets[coalition.side.BLUE] > industry.tickets[coalition.side.RED]) then
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
        industry.tickets[coal] = industry.tickets[coal] - tickets
        if (industry.tickets[coal] < 0) then
            industry.tickets[coal] = 0
        end
        trigger.action.outText(string.format("Tickets %s: %d (-%d)", industry.coalitionIdToName[coal], industry.tickets[coal], tickets), 10)

        industry.evaluateTicketWinner()

        trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets[coalition.side.BLUE], industry.tickets[coalition.side.RED]), 10)
    end
end

---------------------------------------------------------
-- Scheduled function to countdown tickets every minute
---------------------------------------------------------
function industry.tickerTickets()
    if (industry.winner == nil) then
        industry.tickets[coalition.side.RED] = industry.tickets[coalition.side.RED] - 1
        industry.tickets[coalition.side.BLUE] = industry.tickets[coalition.side.BLUE] - 1

        industry.evaluateTicketWinner()

        trigger.action.outText(string.format("Tickets: BLUE %d    RED %d", industry.tickets[coalition.side.BLUE], industry.tickets[coalition.side.RED]), 10)
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
            event.id == world.event.S_EVENT_KILL or
            event.id == world.event.S_EVENT_EJECTION or
            event.id == world.event.S_EVENT_LANDING_AFTER_EJECTION) then
        local _name = 'unset'
        if (event.initiator and event.initiator:getName()) then
            _name = event.initiator:getName()
        else if (event.initiator and event.initiator:getTypeName()) then
                _name = event.initiator:getTypeName()
            else
                _name = 'unknown initiator'
            end
        end
        env.info(string.format("Handling event ID %d Unit %s", event.id, _name), false)
        local _groupname = industry.getGroupNameByUnitName(_name)

        -- spawn SAR type heli mission if blueSAR or redSAR exists. has to have a waypoint 2 with the task landing as first task
        if (event.id == world.event.S_EVENT_LANDING_AFTER_EJECTION) then
            local _coalition = event.initiator:getCoalition()            
            local _country = event.initiator:getCountry()
            local _SARname = ''

            -- sanitize weird results where coalition and country (99?) where off in some missions
            if (_coalition == 0 or _country > 99) then
                if (_name == "pilot_f15_parachute") then
                    _coalition = 2
                    _country = 2
                else if (_name == "pilot_su27_parachute") then
                        _coalition = 1
                        _country = 0
                    else
                        env.info(string.format("ERROR unhandled type: %s country: %d coalition: %d", _name, _country, _coalition), false)
                        _coalition = 2
                        _country = 2
                    end
                end
            end

            if (_coalition == 2) then
                _SARname = 'blueSAR'                                
            else
                _SARname = 'redSAR'
            end          

            local _path = mist.getGroupRoute(_SARname, true)
            
            if (_path) then                                
                local _point = mist.utils.makeVec2(event.initiator:getPosition().p)
                local _surface = land.getSurfaceType(_point)
                if (_surface == land.SurfaceType.LAND or _surface == land.SurfaceType.ROAD or _surface == land.SurfaceType.RUNWAY) then
                    local _rescuegroup = industry.cloneUnitToInfantry(event.initiator, _coalition, _country)
                    local _landpoint = _point
                    _landpoint.x = _landpoint.x + 12
                    _landpoint.y = _landpoint.y + 10

                    env.info(string.format("Pilot %s (%s) landed, SAR %s sent to loation", _name, _rescuegroup, _SARname), false)

                    local lat, lon, alt = coord.LOtoLL(_point)
                    trigger.action.outTextForCoalition(_coalition, string.format("Pilot down, parachute spotted at %s. SAR mission started", mist.tostringLL(lat, lon, 3)), 10)

                    _path[#_path+1] = {
                        type = "Turning Point",
                        action = "Turning Point",
                        form = "Turning Point",
                        x = _point.x,
                        y = _point.y,
                        alt = math.random(200, 400),
                        alt_type = "BARO",
                        speed = math.random(60, 100),
                        task = {
                            id = "ComboTask",
                            params = {
                                tasks = {
                                    [1] = {
                                        id = "Land",
                                        params = {
                                            point = _landpoint,
                                            duration = math.random(20, 120),
                                            durationFlag = true
                                        }
                                    },
                                    [2] = {
                                        id = "WrappedAction",
                                        params = {
                                            action = {
                                                id = "Script",
                                                params = {
                                                    command = 'if (Group.getByName(\'' .. _rescuegroup .. '\'):isExist()) then\nGroup.getByName(\'' .. _rescuegroup .. '\'):destroy()\nend'
                                                --    command = ''
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }                    

                    industry.sarmissioncounter = industry.sarmissioncounter + 1
                    local _newsarname = string.format("%s-%d", _SARname, industry.sarmissioncounter)
                    local _grouptable = industry.cloneGroupNewRoute(_SARname, _path, _newsarname)
                    local _group = Group.getByName(_grouptable["name"])
                    
                    _group:getController():setCommand({
                        id = 'Start', 
                        params = {}
                    })
                else
                    event.initiator:destroy()
                end
            end
        end

        if (_groupname) then
            -- player killed SAR unit, reduce tickets
            if (event.id == world.event.S_EVENT_KILL and event.initiator:getPlayerName() ~= nil) then            
                if (event.target and event.target:getDesc().category == Unit.Category.HELICOPTER) then
                    local _targetGroupName = event.target:getGroup():getName()
                    if (string.match(_targetGroupName,'blueSAR.*') or string.match(_targetGroupName,'redSAR.*')) then
                        trigger.action.outText(string.format("Player %s shot down SAR unit %s", event.initiator:getPlayerName(), _targetGroupName), 10)
                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                    else
                        trigger.action.outText(string.format("Player %s shot down %s", event.initiator:getPlayerName(), _targetGroupName), 10)
                    end
                else
                    env.info(string.format("Kill event with no target, no group or no heligroup in %s", _groupname), false)
                end
            end

            -- plane landed and engine shut off. Despawn unit to enable respawn of group
            if (event.id == world.event.S_EVENT_ENGINE_SHUTDOWN) then
                if (industry.respawnGroup[_groupname] or event.initiator:getPlayerName() == nil) then  
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
                if (event.initiator:getDesc() and event.initiator:getDesc().category == Unit.Category.STRUCTURE) then
                    if (industry.mapMarkers[_name]) then
                        trigger.action.removeMark(industry.mapMarkers[_name])
                    end

                    -- handle secondary target destruction
                    if (string.match(_name,'Secondary.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.75)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.setUserFlag(string.format("%sSecondaryDestroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), true)
                        trigger.action.outText(string.format("Secondary Target of %s coalition destroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                    end
                    
                    -- handle factory destruction
                    if (string.match(_name,'Factory.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.75)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.setUserFlag(string.format("%sFactoryDestroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), true)
                        trigger.action.outText(string.format("Factory of %s coalition destroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 10)
                    end

                    -- handle storage destruction
                    if (string.match(_name,'Storage.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.setUserFlag(string.format("%sStorageDestroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), true)
                        industry.destroyStorage(industry.getCoalitionByGroupname(_groupname))
                    end

                    -- handle laboratory destruction
                    if (string.match(_name,'Laboratory.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.setUserFlag(string.format("%sLaboratoryDestroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), true)
                        trigger.action.outText(string.format("Laboratory of %s coalition destroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 5)
                    end

                    -- handle HQ destruction
                    if (string.match(_name,'HQ.*')) then
                        local _pos = event.initiator:getPosition().p
                        trigger.action.effectSmokeBig(_pos, 3, 0.5)
                        trigger.action.setUserFlag(_name .. '_destroyed', true)
                        trigger.action.setUserFlag(string.format("%sHQDestroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), true)
                        trigger.action.outText(string.format("HQ of %s coalition destroyed", industry.coalitionIdToName[industry.getCoalitionByGroupname(_groupname)]), 10)

                        industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), math.floor(industry.tickets[industry.getCoalitionByGroupname(_groupname)] / 2))
                    end
                end

                -- vehicle destruction adds a fire and smoke
                if (event.initiator:getDesc() and event.initiator:getDesc().category == Unit.Category.GROUND_UNIT) then
                    local _pos = event.initiator:getPosition().p
                    if (_pos) then
                        trigger.action.effectSmokeBig(_pos, 1, 0.5)
                        env.info(string.format("Spawn smoke effect at unit location %s", _name))
                    end
                end

                -- player plane destruction reduces tickets
                if (event.initiator:getDesc() and event.initiator:getDesc().category ~= Unit.Category.GROUND_UNIT and event.initiator:getDesc().category ~= Unit.Category.STRUCTURE and event.initiator:getPlayerName() ~= nil) then
                    env.info(string.format("Player %s (%s) killed. Reduce tickets of %s", event.initiator:getPlayerName(), _name, industry.getCoalitionByGroupname(_groupname)))
                    industry.reduceTickets(industry.getCoalitionByGroupname(_groupname), 1)
                end
            end

            -- if group has only this one (now dead) unit left, queue for respawn
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

    industry.ressources[coalition.side.RED] = industry.config.startRessources
    industry.ressources[coalition.side.BLUE] = industry.config.startRessources
    industry.tickets[coalition.side.RED] = industry.config.tickets
    industry.tickets[coalition.side.BLUE] = industry.config.tickets
end

---------------------------------------------------------
-- Init Industry script
---------------------------------------------------------
industry.addRadioMenu()
industry.PrepareMap()
mist.scheduleFunction(industry.scheduleHandlers,{} , timer.getTime() + 5)
env.info('Industry ' .. industry.version .. ' initialized')