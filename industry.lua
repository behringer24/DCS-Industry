-- Industry script by puni5her

if (industry ~= nil) then return 0 end
industry = {}

industry.ressources = {red = 200, blue = 200}
industry.factories = {red= 1, blue = 1}
industry.storages = {red= 1, blue = 1}

function industry.destroy(gpName)
    local _group = Group.getByName(gpName)
    Group.destroy(_group)
end

function industry.respawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)

    if (groupdata.coalition == "red") then
        if industry.ressources.red >= costs then
            industry.ressources.red = industry.ressources.red - costs
            mist.respawnGroup(gpName, true)
            trigger.action.outText(string.format("Respawned group %s for %d tons of RED ressources", gpName, costs), 10)
        end
    else
        if industry.ressources.blue >= costs then
            industry.ressources.blue = industry.ressources.blue - costs
            mist.respawnGroup(gpName, true)
            trigger.action.outText(string.format("Respawned group %s for %d tons of BLUE ressources", gpName, costs), 10)
        end
    end
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

    -- not using Group.getUnits() due to DCS bug with some unit types
    for i=1,_group:getSize() do
        local _unit = _group:getUnit(i)
        env.info(string.format("Convoy unit %d arrived: %s (%s)", i, _unit:getName(), _unit:getTypeName()), false)
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

function industry.destroyStorage(coalition)
    if (string.match(coalition, "RED") and industry.storages.red > 0) then
        industry.ressources.red = industry.ressources.red - math.floor(industry.ressources.red / industry.storages.red)
        industry.storages.red = industry.storages.red - 1

        trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 5)   
    end

    if (string.match(coalition, "BLUE") and industry.storages.blue > 0) then
        industry.ressources.blue = industry.ressources.blue - math.floor(industry.ressources.blue / industry.storages.blue)
        industry.storages.blue = industry.storages.blue - 1

        trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 5)   
    end
end

function industry.loop()
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

mist.scheduleFunction(industry.loop,{} , timer.getTime() + 1, 300)

env.info("Industry script initialized")