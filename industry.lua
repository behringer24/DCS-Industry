-- Industry script by puni5her

if (industry ~= nil) then return 0 end
industry = {}

industry.version = "v0.3.0"
industry.ressources = {red = 200, blue = 200}
industry.factories = {red= 1, blue = 1}
industry.storages = {red= 1, blue = 1}
industry.respawnGroup = {}

industry.Queue = function()
    local queue = {}
    local head = 0
    local last = -1

    function queue.push(element)
        last = last + 1
        queue[last] = element
    end

    function queue.get()
        if (head > last) then return nil end
        return queue[head]
    end
    
    function queue.pop()
        if (head > last) then return nil end
        local _result = queue[head]
        queue[head] = nil
        head = head + 1        
        return _result
    end

    return queue
end

industry.respawnQueueRed = industry.Queue()
industry.respawnQueueBlue = industry.Queue()
industry.respawnQueueRedFree = industry.Queue()
industry.respawnQueueBlueFree = industry.Queue()

function industry.getGroupNameByUnitName(unitname)
    if (mist.DBs.unitsByName[unitname] == nil) then return nil end
    return mist.DBs.unitsByName[unitname].groupName
end

function industry.getCoalitionByGroupname(groupname)
    if (mist.DBs.groupsByName[groupname] == nil) then return nil end
    return mist.DBs.groupsByName[groupname].coalition
end

function industry.destroy(gpName)
    local _group = Group.getByName(gpName)
    Group.destroy(_group)
end

function industry.queueRespawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)

    if (costs == 0) then
        if (groupdata.coalition == "red") then
            industry.respawnQueueRedFree.push(gpName)
        else
            industry.respawnQueueBlueFree.push(gpName)
        end
    else
        if (groupdata.coalition == "red") then
            industry.respawnQueueRed.push({name = gpName, cost = costs})
        else
            industry.respawnQueueBlue.push({name = gpName, cost = costs})
        end
    end
end

function industry.respawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)

    if (groupdata.coalition == "red") then
        if industry.ressources.red >= costs then
            industry.ressources.red = industry.ressources.red - costs
            mist.respawnGroup(gpName, true)
            if (costs > 0) then
                trigger.action.outText(string.format("Respawned RED group %s for %d tons of ressources", gpName, costs), 10)
            else
                trigger.action.outText(string.format("Respawned RED group %s", gpName), 10)
            end
            return true
        end
    else
        if industry.ressources.blue >= costs then
            industry.ressources.blue = industry.ressources.blue - costs
            mist.respawnGroup(gpName, true)
            if (costs > 0) then
                trigger.action.outText(string.format("Respawned BLUE group %s for %d tons of ressources", gpName, costs), 10)
            else
                trigger.action.outText(string.format("Respawned BLUE group %s", gpName), 10)
            end
            return true
        end
    end
    return false
end

function industry.addRessources(coalition, tons)
    if (string.match(coalition, "RED")) then
        industry.ressources.red = industry.ressources.red + tons
    else
        industry.ressources.blue = industry.ressources.blue + tons
    end

    trigger.action.outText(string.format("A %s transport with %d tons of ressources arrived at its destination", coalition, tons), 5)
end

function industry.addRessourcesConvoy(groupName, truckTypeName, tonsEach)
    local _group = Group.getByName(groupName)
    local _addRessources = 0

    if (_group) then
        -- not using Group.getUnits() due to DCS bug with some unit types        
        for i=1,_group:getSize() do
            local _unit = _group:getUnit(i)
            if (string.match(_unit:getTypeName(), truckTypeName) and _unit:getLife() > 1) then
                _addRessources = _addRessources + tonsEach
            end
        end

        if (_group:getCoalition() == 1) then
            industry.ressources.red = industry.ressources.red + _addRessources
            trigger.action.outText(string.format("A RED convoy with %d tons of ressources arrived at its destination", _addRessources), 5)
        else
            industry.ressources.blue = industry.ressources.blue + _addRessources
            trigger.action.outText(string.format("A BLUE convoy with %d tons of ressources arrived at its destination", _addRessources), 5)
        end
    end
end

function industry.destroyStorage(coalition)
    if (string.match(coalition, "red") and industry.storages.red > 0) then
        industry.ressources.red = industry.ressources.red - math.floor(industry.ressources.red / industry.storages.red)
        industry.storages.red = industry.storages.red - 1

        trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 10)   
    end

    if (string.match(coalition, "blue") and industry.storages.blue > 0) then
        industry.ressources.blue = industry.ressources.blue - math.floor(industry.ressources.blue / industry.storages.blue)
        industry.storages.blue = industry.storages.blue - 1

        trigger.action.outText(string.format("A BLUE storage has been destroyed. %d tons ressources left", industry.ressources.blue), 10)   
    end
end

function industry.addRespawnGroup(name, cost)
    industry.respawnGroup[name] = cost
end

function industry.productionLoop()
    trigger.action.outText("Industry ressources arrived", 5)
    industry.ressources.red = industry.ressources.red + 1
    industry.ressources.blue = industry.ressources.blue + 1

    local _redObjects = coalition.getStaticObjects(1)
    local _countRedFactories = 0;
    local _countRedStorages = 0
    for k, v in pairs(_redObjects) do
        local _name = v:getName()
        local _type = v:getTypeName()
        local _health = v:getLife()

        if (string.match(_name, "Factory.*") and _health > 1) then
            industry.ressources.red = industry.ressources.red + 10	 
            _countRedFactories = _countRedFactories + 1;   
		end

        if (string.match(_name, "Storage.*") and _health > 1) then            
            _countRedStorages = _countRedStorages + 1;   
		end
    end
    industry.factories.red = _countRedFactories
    industry.storages.red = _countRedStorages

    local _blueObjects = coalition.getStaticObjects(2)
    local _countBlueFactories = 0;
    local _countBlueStorages = 0
    for k, v in pairs(_blueObjects) do
        local _name = v:getName()
        local _type = v:getTypeName()
        local _health = v:getLife()

        if (string.match(_name, "Factory.*") and _health > 1) then
            industry.ressources.blue = industry.ressources.blue + 10 
            _countBlueFactories = _countBlueFactories + 1
		end

        if (string.match(_name, "Storage.*") and _health > 1) then            
            _countBlueStorages = _countBlueStorages + 1;   
		end
    end
    industry.factories.blue = _countBlueFactories
    industry.storages.blue = _countBlueStorages

    if (industry.ressources.red > industry.storages.red * 1000) then
        industry.ressources.red = industry.storages.red * 1000
        trigger.action.outText("RED storages are full", 3)
    end

    if (industry.ressources.blue > industry.storages.blue * 1000) then
        industry.ressources.blue = industry.storages.blue * 1000
        trigger.action.outText("BLUE storages are full", 3)
    end

    trigger.action.outText(string.format("BLUE (%d/%d): %d tons    RED (%d/%d): %d tons", industry.factories.blue, industry.storages.blue, industry.ressources.blue, industry.factories.red, industry.storages.red, industry.ressources.red), 10)
end

function industry.respawnLoop()
    local _blueGroup = industry.respawnQueueBlue.get()
    if (_blueGroup and mist.groupIsDead(_blueGroup.name) and industry.respawn(_blueGroup.name, _blueGroup.cost)) then
        industry.respawnQueueBlue.pop()
        trigger.action.setUserFlag(_blueGroup.name .. '_respawn', true)
    end

    local _blueGroupFree = industry.respawnQueueBlueFree.pop()
    if (_blueGroupFree) then
        industry.respawn(_blueGroupFree, 0)
        trigger.action.setUserFlag(_blueGroupFree .. '_respawn', true)
    end
    
    local _redGroup = industry.respawnQueueRed.get()
    if (_redGroup and mist.groupIsDead(_redGroup.name) and industry.respawn(_redGroup.name, _redGroup.cost)) then
        industry.respawnQueueRed.pop()
        trigger.action.setUserFlag(_redGroup.name .. '_respawn', true)
    end

    local _redGroupFree = industry.respawnQueueRedFree.pop()
    if (_redGroupFree) then
        industry.respawn(_redGroupFree, 0)
        trigger.action.setUserFlag(_redGroupFree .. '_respawn', true)
    end
end

industry.eventHandler = {}
function industry.eventHandler:onEvent(event)
    if (event.id == world.event.S_EVENT_ENGINE_SHUTDOWN or event.id == world.event.S_EVENT_UNIT_LOST) then
        local _name = event.initiator:getName()        
        local _groupname = industry.getGroupNameByUnitName(_name)
        local _category = mist.getGroupData(_groupname).category        

        if (event.id == world.event.S_EVENT_ENGINE_SHUTDOWN) then
            if (industry.respawnGroup[_groupname]) then  
                local _unit = Unit.getByName(_name)          
                _unit:destroy()
            end
            trigger.action.setUserFlag(_name .. '_landed', true) 
        end

        if (_category == 'static') then
            if (string.match(_name,'Factory.*')) then
                trigger.action.outText(string.format("Factory of %s coalition destroyed", industry.getCoalitionByGroupname(_groupname)), 10)
            end

            if (string.match(_name,'Storage.*')) then
                industry.destroyStorage(industry.getCoalitionByGroupname(_groupname))
            end
        end

        local _group = Group.getByName(_groupname)
        if ((_group == nil or #_group:getUnits() < 2) and industry.respawnGroup[_groupname]) then
            if (industry.getCoalitionByGroupname(_groupname) == 'red') then
                industry.respawnQueueRed.push({name = _groupname, cost = industry.respawnGroup[_groupname]})
            else if (industry.getCoalitionByGroupname(_groupname) == 'blue') then
                industry.respawnQueueBlue.push({name = _groupname, cost = industry.respawnGroup[_groupname]})
                end
            end        
        end
    end
end

world.addEventHandler(industry.eventHandler)

mist.scheduleFunction(industry.productionLoop,{} , timer.getTime() + 1, 300)
mist.scheduleFunction(industry.respawnLoop,{} , timer.getTime() + 30, 30)

env.info('Industry ' .. industry.version .. ' initialized')