# DCS-Industry
Industry Wars script for DCS World — resources, respawns and tickets.

> **Version 2.1 is in development** on this branch. Version 2 no longer needs MIST and is configured with
> one Lua table; 2.1 adds reconnaissance and the HQ menu. The last 1.x release is tagged `v1.5.1`; its
> documentation is in the README of that tag.

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
- Strategic objectives (factories, laboratories, storages, HQs, secondary targets)
- Reconnaissance: enemy objectives and air defence sites appear on the F10 map only after AI units or players
  spotted them and reported them to the own HQ — depending on distance, terrain, daylight and weather. Without
  HQ a coalition is blind
- Automatic combat search and rescue missions for pilots that landed with the parachute
- F10 HQ menu for every player, including dynamic slots: send recon reports, request the supply status
- Robust against units that disappear without events (emergency landings, despawned wrecks) and against
  damaged aircraft that are stranded on the ground

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
| `HQ`         | receives recon reports; without HQ a coalition is blind  | half of the remaining tickets        |
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
friendly airbase with a landing waypoint. When a transport shuts down its engines on the ground it delivers
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
AI aircraft that shut down their engines on the ground are removed (`respawn.despawnLandedAI`), which frees
the parking spot and lets respawn groups come back. The flag `<unit name>_landed` is set for your own triggers.
DCS also reports an engine shutdown when a damaged aircraft loses its engines in flight; such aircraft are
left alone until they crash, so the shooter keeps the kill.

### Stranded aircraft
A damaged aircraft that does not crash — an emergency landing in a field, a damaged helicopter that set down, a
wreck left on a runway — raises no further event and would block its respawn group forever. Every
`respawn.deadCheckInterval` seconds Industry checks the AI aircraft of respawn groups. One that is damaged (it was
hit, its AI aborted the mission or it lost life), on the ground and not moving at two checks in a row is removed
and counts as lost. If it is still there at the next check, it is blown up. Players and ground vehicles are never
touched. Switch it off with `respawn.removeStranded = false`.

### Search and rescue
Place one helicopter group named `TPL-SAR-Red` (rescues red pilots) and one named `TPL-SAR-Blue` (rescues blue
pilots) with *uncontrolled* ticked, usually parked at an airbase. They may belong to any coalition — put them on
the neutral side so the rescue flights fly for neither side. The names can be changed in `csar.templates`.

When a pilot (player or AI) lands with the parachute on land, the pilot becomes a soldier on the ground and a
copy of the template is sent:
1. **Start:** At an airbase the helicopter takes the free helicopter parking spot closest to the template (without
   a free spot it shares the template's spot). Like its template it makes a cold start and taxis to the runway;
   with `csar.hotStart` it starts with running engines.
2. **Flight:** It flies `csar.altitude` meters above the ground to the pilot and lands where its AI finds a
   landing site.
3. **Boarding:** If it landed up to `csar.maxWalkDistance` meters away, the pilot walks over and boards. A
   helicopter that landed farther away takes off and lands at the pilot again, up to `csar.landingAttempts`
   landings.
4. **Return:** It flies back to the template's airbase (or start position), lands and is removed.

The rescue fails, and the helicopter flies home, when no landing is close enough, when the pilot does not reach the
helicopter in time or when the pilot is killed. The soldier of a failed rescue stays where he is. A rescue
helicopter that has not finished after `csar.timeout` seconds is removed. All steps are announced to the pilot's
coalition and written to `dcs.log`.

Scenery objects within `csar.clearRadius` meters of the pilot are removed (off by default; forests are not
scenery objects). Players that shoot down a rescue helicopter cost their own coalition `csar.killTickets` tickets.

### Reconnaissance and the HQ
With `intel.enabled` (the default) no enemy target is on the map at the start. Targets are all objectives and
the air defence sites: ground groups with a SAM or early warning radar (DCS attributes *SAM SR*, *SAM TR*, *EWR*)
or with at least half air defence units (*Air Defence*, *EWR*), see `intel.airDefenceRadars` and
`intel.airDefenceShare`. A convoy or platoon with a single escort SAM is no site; `dcs.log` lists every group
that was checked. A target appears on the F10 map of a coalition only after it was spotted and the report
reached the coalition's HQ:

- **AI units** (`intel.aiRecon`) report what they see right away. Reconnaissance aircraft — groups with the task
  *Reconnaissance* in the mission editor and the types in `intel.reconTypes` — see farther and from higher up.
- **Players** get a message when they spot something (*Recon: Factory spotted, bearing 312 for 8 km*) and a mark
  that only their group sees. *F10 → HQ → Send recon report* sends everything spotted since the last report.
  What is not sent is lost with the aircraft, on ejection or when the player leaves the slot.
- **Without HQ a coalition is blind.** When its last HQ objective is destroyed, all its reports and marks
  disappear, nobody spots anything any more and the HQ menu is gone. A coalition without any HQ objective in
  the mission does its reconnaissance without HQ.

Whether a target is spotted depends on:

| Factor   | Effect |
|----------|--------|
| Distance | range per target kind (`intel.ranges`): factory 10 km, storage 8 km, laboratory, HQ and air defence 6 km, secondary 5 km |
| Observer | ground units and ships ×0.6, aircraft ×1, reconnaissance aircraft ×2.5 (`intel.observers`) |
| Height   | aircraft more than `intel.maxAltitude` (4000 m) above the ground see nothing, reconnaissance aircraft up to `intel.reconAltitude` (12000 m) |
| Light    | twilight ×0.5, night ×0.2, types in `intel.nightVisionTypes` ×0.6. The sun is computed from the mission date, time and map |
| Weather  | never beyond the mission visibility; fog and dust limit points inside them; overcast clouds between observer and target block the view, broken clouds ×0.5 |
| Terrain  | the line of sight must be free (hills and mountains; trees and buildings do not block it) |

Reported air defence sites get a red threat circle. Its radius is the missile range of the launchers, else
`intel.threatRadius` by DCS attribute (`intel.threatRings`). Destroyed targets stay on the map, marked
destroyed with a grey circle. A site that is rebuilt (respawn) has to be found again.

`dcs.log` tells with the prefix `[industry.intel]` who spotted what with the full range calculation, near misses
(terrain, too high, clouds, just out of range; `intel.verbose`), reports, lost recon packages and a summary every
`intel.summaryInterval` seconds — so the parameters can be tuned with the log of a real mission.

Without reconnaissance (`intel.enabled = false`) all enemy objectives are marked from the start
(`objectives.markers`), as in 2.0.

### F10 menu
Every red and blue player group gets the menu *HQ*, also in dynamic slots, with radio calls to the own HQ:
- *Send recon report* — the targets spotted since the last report (only with reconnaissance).
- *Request supply status* — stock, storage capacity and the operational factories, laboratories and storages of
  the own coalition.

The menu disappears when the coalition's HQ is destroyed.

## Configuration
`industry.setup()` takes one table. Everything you leave out uses these defaults. Unknown keys are reported
in `dcs.log`. Type and attribute lists are sets: add an entry with `["Tornado IDS"] = true`, switch off a
default one with `= false`.

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
        removeStranded = true, -- remove damaged aircraft stranded on the ground
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
        markers = true,       -- mark all enemy objectives from the start (only without reconnaissance)
    },
    intel = {
        enabled = true,       -- false: no reconnaissance, objectives.markers applies
        aiRecon = true,       -- AI units report what they see
        interval = 10,        -- seconds between two checks
        ranges = { factory = 10000, laboratory = 6000, storage = 8000, hq = 6000, secondary = 5000,
                   airDefence = 6000 },
        observers = { ground = 0.6, aircraft = 1, recon = 2.5 },
        maxAltitude = 4000,   -- meters above the ground
        reconAltitude = 12000,
        reconTypes = { ["Su-24MR"] = true, ["MiG-25RBT"] = true },
        light = { day = 1, twilight = 0.5, night = 0.2, nightVision = 0.6 },
        nightVisionTypes = { ["AH-64D_BLK_II"] = true, --[[ ... see src/industry/config.lua ]] },
        brokenClouds = 0.5,
        airDefenceAttributes = { ["Air Defence"] = true, ["EWR"] = true },
        airDefenceRadars = { ["SAM SR"] = true, ["SAM TR"] = true, ["EWR"] = true },
        airDefenceShare = 0.5, -- share of air defence units that makes a group without radar a site
        threatRings = true,
        threatRadius = { ["LR SAM"] = 40000, ["MR SAM"] = 25000, ["SR SAM"] = 8000, ["AAA"] = 3000 },
        verbose = true,       -- log near misses
        summaryInterval = 600,
    },
    losses = {
        playerTickets = 1,    -- tickets per destroyed player aircraft
        vehicleSmoke = true,
    },
    csar = {
        enabled = true,
        templates = { red = "TPL-SAR-Red", blue = "TPL-SAR-Blue" },
        hotStart = false,     -- true: start with running engines instead of a cold start
        altitude = 150,       -- meters above the ground
        waitTime = 1200,      -- seconds a landed helicopter waits for the pilot at most
        maxWalkDistance = 800,
        landingAttempts = 2,
        timeout = 7200,       -- seconds until an unfinished rescue helicopter is removed
        clearRadius = 0,
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
| `<unit name>_landed`                   | an AI aircraft shut down its engines on the ground |
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

Event handlers only read and record. Everything that changes the world — explosions, destroying or spawning
objects, smoke — runs a second later through `tarmac.scheduler.after`, because DCS can trip over world changes
made while it dispatches an event.
