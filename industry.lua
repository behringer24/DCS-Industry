-- Industry script by puni5her

if (industry ~= nil) then return 0 end
industry = {}

industry.ressources = {red = 0, blue = 0}
industry.factories = {red= 1, blue = 1}
industry.storages = {red= 1, blue = 1}

function industry.respawn(gpName, costs)
    local groupdata = mist.getGroupData(gpName)
    
    if (groupdata.coalition == 1) then
        if industry.ressources.red >= costs then
            industry.ressources.red = industry.ressources.red - costs
            mist.respawnGroup(gpName, true)
        end
    else
        if industry.ressources.blue >= costs then
            industry.ressources.blue = industry.ressources.blue - costs
            mist.respawnGroup(gpName, true)
        end
    end
end

function industry.addRessources(coalition, tons)
    if (string.match(coalition, "RED")) then
        industry.ressources.red = industry.ressources.red + tons
    else
        industry.ressources.blue = industry.ressources.blue + tons
    end

    trigger.action.outText(string.format("A %s transport with %d tons of ressources arrived its destination", coalition, tons), 10)
end

function industry.destroyStorage(coalition)
    if (string.match(coalition, "RED") and industry.storages.red > 0) then
        trigger.action.outText(string.format("RED had %d storages and %d tons ressources", industry.storages.red, industry.ressources.red), 10)   
        industry.ressources.red = industry.ressources.red - math.floor(industry.ressources.red / industry.storages.red)
        industry.storages.red = industry.storages.red - 1

        trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 10)   
    end

    if (string.match(coalition, "BLUE") and industry.storages.blue > 0) then
        industry.ressources.blue = industry.ressources.blue - math.floor(industry.ressources.blue / industry.storages.blue)
        industry.storages.blue = industry.storages.blue - 1

        trigger.action.outText(string.format("A RED storage has been destroyed. %d tons ressources left", industry.ressources.red), 10)   
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

mist.scheduleFunction(industry.loop,{} , timer.getTime() + 10, 30)

industry.statics = coalition.getStaticObjects(1)

industry.loop()

env.info("Industry script initialized")