# DCS-Industry
Industry Wars script for DCS World — resources, respawns and tickets.

> **Version 2 is in development** on this branch. It no longer needs MIST and is configured with one
> Lua table. The last 1.x release is tagged `v1.5.1`; its documentation is in the README of that tag.

## Description
Industry adds a resource management and respawn system to DCS missions. All AI units need resources to
respawn. If the mission is well balanced this leads to a very dynamic battlefield where the player(s) make
the difference: whoever cuts the supply of the enemy also cuts its respawns. Industry can be used for
single- or multiplayer missions.

Resources are produced by factories, boosted by laboratories and kept in storages. All of them are static
objects of your choice, they only need the right name prefix. Convoys and air transports deliver additional
resources.

Discuss on Discord: https://discord.gg/bTzjqZKa

## Features
- Regular production of resources in factories, boosted by laboratories, limited by storages
- Deliveries by convoys (no script in the mission editor needed) and air transports (no trigger needed)
- Respawn of AI groups for resources, with a strict queue so expensive groups are not starved
- Tickets that limit the mission time and decide the winner
- Strategic objectives (factories, laboratories, storages, HQs, secondary targets) marked on the F10 map
- Automatic combat search and rescue missions for pilots that landed with the parachute
- F10 statistics menu for every player, including dynamic slots
- Robust against units that disappear without events (emergency landings, despawned wrecks)

## Requirements
Nothing but DCS World. Industry 2 is built on [DCS Tarmac](https://github.com/behringer24/DCS-Tarmac), which is
included in `dist/industry.lua`. MIST is not needed any more. If a mission also loads Tarmac on its own,
Industry uses that copy.

## Installation
1. Download `dist/industry.lua` from this repository.
2. Write the mission configuration, e.g. `init.lua` (see [examples/init.lua](examples/init.lua)).
3. In the mission editor add a trigger *ONCE*, condition *TIME MORE (1)*, with two *DO SCRIPT FILE* actions:
   first `industry.lua`, then `init.lua`.

`init.lua` calls `industry.setup({...})`, which starts Industry. If `setup` is never called, Industry writes
an error to `dcs.log` and shows a message after ten seconds.

## Mission setup

### Objectives
Static objects become objectives when their **unit name starts with** one of these prefixes:

| Prefix       | Effect                                                   | Tickets lost when destroyed          |
|--------------|----------------------------------------------------------|--------------------------------------|
| `Factory`    | produces `production.perFactory` tons per cycle          | 10                                   |
| `Laboratory` | adds `production.labBoost` percent of factory production | 5                                    |
| `Storage`    | holds `production.storageCapacity` tons                  | its share of the remaining tickets   |
| `HQ`         | —                                                        | half of the remaining tickets        |
| `Secondary`  | optional target                                          | 1                                    |

The prefixes are matched at the start of the name only (`HQ Blue` is an HQ, `BlueHQ` is not) and can be
changed in `objectives.prefixes`. Resources are spread evenly over all storages; a destroyed storage loses
its share. Without storages a coalition cannot keep any resources.

### Respawning groups
Every AI group listed in `respawn.groups` respawns at its original position when its last unit is lost:

```lua
respawn = {
    groups = {
        ["RedCAP-1"] = 400,             -- costs 400 tons
        ["TankPlatoonRed-1"] = {},      -- default cost of its category (respawn.costs)
        ["RedArty-1"] = { cost = 200 },
    },
},
```

Do not list player groups.

### Convoys
Ground groups whose name starts with `Convoy` (e.g. `Convoy-Red-1`) are convoys. Give them a route; when
they reach the **last waypoint**, every surviving truck delivers `logistics.tonsPerTruck` tons. Trucks are
the units with the DCS attribute *Trucks* — or the types listed in `logistics.truckTypes`. Industry adds
the waypoint action itself, so the mission editor needs no script. The convoy then respawns for free.

### Air transports
Aircraft groups whose name starts with `Transport` (e.g. `Transport-Red-1`) are transports. Send them to a
friendly airbase with a landing waypoint. When a transport shuts down its engines it delivers
`logistics.tonsPerTransport` tons (nothing if it landed at an enemy airbase), is removed and respawns for free.

Groups with other names can get a role and an individual amount:

```lua
logistics = {
    groups = {
        ["RedTransport-1"] = { role = "transport", tons = 1200 },
        ["Supply North"] = { role = "convoy", tons = 150 },  -- tons per truck
    },
},
```

### Landed AI aircraft
AI aircraft that shut down their engines are removed (`respawn.despawnLandedAI`), which frees the parking
spot and lets respawn groups come back. The flag `<unit name>_landed` is set for your own triggers.

### Search and rescue
Place one helicopter group named `TPL-SAR-Red` (rescues red pilots) and one named `TPL-SAR-Blue` (rescues blue
pilots) with *uncontrolled* ticked, usually parked at an airbase. They may belong to any coalition — put them on
the neutral side so the rescue flights fly for neither side. The names can be changed in `csar.templates`.
When a pilot (player or AI) lands with the parachute on land, the pilot becomes a soldier on the ground and a
copy of the template flies to him, lands and picks him up. Scenery
objects within `csar.clearRadius` meters of the landing point are removed. Players that shoot down a rescue
helicopter cost their own coalition `csar.killTickets` tickets.

### F10 menu
Every player group gets *Industry → Get current statistics*, also in dynamic slots.

## Configuration
`industry.setup()` takes one table. Everything you leave out uses these defaults. Unknown keys are reported
in `dcs.log`.

```lua
industry.setup({
    startResources = 200,
    tickets = {
        start = 100,          -- tickets per coalition
        interval = 60,        -- both coalitions lose one ticket every interval seconds
        low = 20,             -- flags ticketsLowRed / ticketsLowBlue below this value
        winCountdown = 600,   -- seconds until the next mission is loaded
    },
    production = {
        interval = 300,       -- seconds per production cycle
        perFactory = 30,
        base = 1,             -- added once per cycle
        labBoost = 20,        -- percent of the factory production per laboratory
        storageCapacity = 1000,
    },
    respawn = {
        interval = 60,        -- seconds per respawn cycle
        retries = 2,          -- cycles to wait for wrecks before the respawn is forced
        deadCheckInterval = 300,
        costs = { plane = 200, helicopter = 200, vehicle = 50, ship = 400 },
        groups = {},
        despawnLandedAI = true,
    },
    logistics = {
        convoyPrefix = "Convoy",
        transportPrefix = "Transport",
        tonsPerTruck = 100,
        truckTypes = nil,     -- e.g. { "M 818", "KAMAZ Truck" }
        tonsPerTransport = 800,
        groups = {},
    },
    objectives = {
        prefixes = { factory = "Factory", laboratory = "Laboratory", storage = "Storage",
                     hq = "HQ", secondary = "Secondary" },
        ticketCosts = { factory = 10, laboratory = 5, secondary = 1, hqFraction = 0.5 },
        markers = true,
    },
    losses = {
        playerTickets = 1,    -- tickets per destroyed player aircraft
        vehicleSmoke = true,
    },
    csar = {
        enabled = true,
        templates = { red = "TPL-SAR-Red", blue = "TPL-SAR-Blue" },
        clearRadius = 50,
        killTickets = 1,
    },
})
```

## How it works

### Tickets
Tickets limit the length of a mission. Both coalitions lose one ticket per `tickets.interval`. Destroyed player
aircraft and objectives cost extra (see above). When one coalition has no tickets left, the coalition with more
tickets wins (equal tickets: draw), a countdown runs and the next mission of the server's mission list is loaded.

### Respawn queues
Each coalition has a queue for groups that cost resources and one for free respawns. Every `respawn.interval`
seconds the first group of each queue is respawned if possible. The paid queue is strict on purpose: if the
first group cannot be paid yet, the groups behind it wait. Otherwise cheap groups would use up all resources
and expensive ones would never return.

A group is queued when its last unit is lost. It respawns only once DCS has removed it from the world, so a
wreck falling from the sky is not replaced in mid-air; after `respawn.retries` cycles the respawn is forced.
Every `respawn.deadCheckInterval` seconds Industry also looks for respawn groups that vanished without any event.

## Flags
| Flag                                   | Set when                                        |
|----------------------------------------|-------------------------------------------------|
| `<unit name>_destroyed`                | an objective was destroyed                       |
| `red/blue` + `Factory/Laboratory/Storage/HQ/Secondary` + `Destroyed` (e.g. `blueStorageDestroyed`) | an objective of that kind was destroyed |
| `ticketsLowRed`, `ticketsLowBlue`      | tickets fell to `tickets.low`                    |
| `<unit name>_landed`                   | an AI aircraft shut down its engines             |
| `<group name>_respawned`               | a group was respawned                            |
| `missionWinRed`, `missionWinBlue`, `missionWinNeutral` | the countdown after the end of the war ran out |

Reset class flags such as `blueStorageDestroyed` in your triggers if you want to react to them more than once.

### Ending the mission and mission goals
When the countdown after the end of the war has run out, Industry sets `missionWinRed`, `missionWinBlue` or
`missionWinNeutral` (draw) and loads the next mission of the server's mission list. Mission goals cannot be set
from a script, so let the mission editor react to these flags:

- **Triggers:** one trigger per flag, *ONCE*, condition *FLAG IS TRUE* (`missionWinRed`, ...), action
  *END MISSION* with the winning coalition, plus sounds if you like.
- **Mission goals** (for the debriefing result, campaigns and single player logbooks): a goal *Red Wins* for
  RED, 100 points, condition *FLAG IS TRUE* `missionWinRed`, and the same for BLUE with `missionWinBlue`. A draw
  needs no goal.

Do not use Lua expressions on Industry internals in goals; they break when the internals change.

## Script API
```lua
industry.setup(config)                   -- start Industry (once)
industry.addResources("blue", 300)       -- add resources (coalition name or id)
industry.addRespawnGroup("RedCAP-9", 400)
industry.queueRespawn("RedCAP-9")        -- cost optional, 0 = free queue
industry.convoyArrived("Convoy-Red-1")   -- what the convoy waypoint action calls
```

## Migrating from 1.x
- Remove MIST from the mission and load `dist/industry.lua` instead of the old `industry.lua`.
- Turn `industry.addRespawnGroup(...)` calls and `industry.config.*` assignments into one `industry.setup({...})` table.
- Rename convoys to `Convoy...` and transports to `Transport...` (or list them in `logistics.groups`), then delete
  the convoy waypoint scripts and the `_landed` triggers that called `addRessourcesTransport`.
- Rename the rescue helicopters `blueSAR` / `redSAR` to `TPL-SAR-Blue` / `TPL-SAR-Red`.
- Static objectives keep their names, but the prefix must now be at the start of the unit name.

## Development
The sources are Lua modules in `src/industry`. They are bundled with Tarmac into `dist/industry.lua` by the
`tarmac` tool, which also runs the tests in `test/` against a DCS API mock (Lua 5.1, no DCS needed).

```bash
git clone https://github.com/behringer24/DCS-Tarmac ../DCS-Tarmac
go -C ../DCS-Tarmac install ./cmd/tarmac
tarmac test
```

`tarmac.json` expects the Tarmac checkout next to this repository (`../DCS-Tarmac`).

Never edit `dist/industry.lua` by hand; change the modules and run `tarmac build`.
