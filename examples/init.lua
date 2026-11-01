-- Industry Wars 3 (Caucasus) - mission configuration.
-- Load this file with a second DO SCRIPT FILE action right after industry.lua.
-- Everything that is not listed here uses the defaults from the README.

industry.setup({
    startResources = 200,

    tickets = {
        start = 150,
        winCountdown = 600,
    },

    production = {
        interval = 600,
        perFactory = 33,
        labBoost = 10,
        storageCapacity = 1500,
    },

    respawn = {
        interval = 300,
        -- ["group name"] = cost in tons; {} uses the default cost of the category.
        -- Convoy-* and Transport-* groups are added automatically and respawn for free.
        groups = {
            ["RedFactoryProtect-1"] = 200,
            ["RedConvoyAttack-1"] = 200,
            ["RedRecon-1"] = 100,
            ["RedCAP-3"] = 200,
            ["RedRotary-1"] = 200,
            ["RedRotary-2"] = 200,
            ["TankPlatoonRed-1"] = 50,
            ["ArmoredInfanteryPlatoonRed-1"] = 50,
            ["ArmoredInfanteryPlatoonRed-2"] = 50,
            ["ArmoredInfanteryPlatoonRed-3"] = 50,
            ["RedArty-1"] = 200,

            ["BlueFactoryProtect-1"] = 200,
            ["BlueConvoyAttack-1"] = 200,
            ["BlueRecon-1"] = 100,
            ["BlueCAP-3"] = 200,
            ["BlueRotary-1"] = 200,
            ["BlueRotary-2"] = 200,
            ["TankPlatoonBlue-1"] = 50,
            ["ArmoredInfanteryPlatoonBlue-1"] = 50,
            ["ArmoredInfanteryPlatoonBlue-2"] = 50,
            ["ArmoredInfanteryPlatoonBlue-3"] = 50,
            ["BlueArty-1"] = 200,
        },
    },

    logistics = {
        tonsPerTruck = 100,
        tonsPerTransport = 800,
    },
})
