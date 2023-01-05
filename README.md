# DCS-Industry
Industry script for DCS World

## Description
Industry adds a ressource management and respawn system to DCS missions. All AI units need ressources to
respawn. If the mission is well balanced this leads to a very dynamic battlefield where the player(s) make
the difference. Industry can be used for single- or multiplayer missions.

Ressources are generated through factories. Production is increased per laboratory and ressources are evenly
stored in storage facilities. All are represented by static units of your choice, they only have to have the correct unit names (see below).

## Features
- Regular production of new ressources in factories
- Delivery of ressources by aerial transport missions or convoys on the ground
- Convoy deliveries are evaluated if the right units (e.g. Trucks and how many of them) are still in the group upon delivery
- Limited storage of ressources in storage facilities
- Respawns (of AI units for now) depending on available ressources
- Automatic handling of AI unit crashes, dead groups, RTB on bingo fuel or out of ammo
- factories, storages and transports can (and should) be destroyed in player or AI missions
- mission ends if no storages are left (limits ressources to 0) and allows a 10 minutes countdown

## Requirements
Industry relies on MIST. The latest tested version to work with Industry is MIST version 4.4.107
- Wiki/Homepage: https://wiki.hoggitworld.com/view/Mission_Scripting_Tools_Documentation
- ED-Forum: https://forum.dcs.world/topic/82178-mission-scripting-tools-mist-enhancing-mission-scripting-lua
- GitHub: https://github.com/mrSkortch/MissionScriptingTools

## Installation
- Download and unpack the MIST .lua file from https://github.com/mrSkortch/MissionScriptingTools/releases
- Download the industry.lua file from this repo
- Copy both files where you will find them in the mission editor file open dialog
- In your DCS mission editor add a trigger with once, time > 1sec and two "do script file" actions.
  In the first action load the MIST .lua file, in the second load the Industry .lua file

## Mission setup
### Adding factories
Factories produce 10 tons of ressources every cycle if they are not destroyed. The amount can be configured (see below).

You can use any static object to use as a factory facility. I prefer to use the oil pump, or some bigger factory-like looking buildings.

To be detected / handled as a factory, the static objects unit name just has to start with "Factory[...]". The rest of the name can be whatever you like.

### Adding laboratories
Labs increase the production of factories by 10% (each, not stacked). The percentage boost can be configured.

Use any static object as a lab. To be handled as a laboratory, the static objects unit name just has to start with "Laboratory[...]".

### Adding storages
Any static object can be used as a storage facility. Just place a static object that looks like a storage (like a liquid-tank or "small werehouse").

To be detected / handled as a storage facility, the static objects unit name just has to start with "Storage[...]".

Storages hold 1000 tons of ressources per default until they are destroyed.

Ressources are distributed evenly between storages. If a storage is destroyed then the ressources are lost in the quota that had been hold in that storage.

### Adding convoys
Create a group that acts as a convoy and set its waypoints.

At the destination waypoint add an "Advanced Waypoint Action" "Perform Command" -> "Script" and add into the text box

``` lua
industry.addRessourcesConvoy("ConvoyBlue-1", "M 818", 100);
industry.queueRespawn("ConvoyBlue-1", 0)
```

* *industry.addRessourcesConvoy* is the command to add ressources of a convoy to the storages
* *ConvoyBlue-1* is the name of the group. The name is just an example, replace this with the name of your group
* *M 818* is the DCS type name of the units in the group that carry the ressources. In this case it is the internal name of the M939 truck.
* *100* is the amount of ressources each unit (M 818 in this case) carries
* *industry.queueRespawn* is the command to put the "*ConvoyBlue-1*" group into the queue for respawning
* *0* is the amount of ressources the respawn will cost. In this case 0 tons. The convoy was not destroyed but reached its destination. more in the chapter about *queues*.

### Adding air transports
Air transports, that deliver ressources, work a bit different than convoys. The reason is that the end waypoint does not allow scripts and air units might land at a different airports due to damages or other AI decisions.

Just add a single air transport unit and send it to your "homebase" airport with a landing waypoint.

You need to create a trigger for each air transport. The Industry script handles the engine shutdown for each air unit and queues them for respawn (if they are in a respawn group, see below). Set the trigger to "Continuous", or this trigger would only work once.

For Rules add "Flag is true" and for the flag name enter then name of the unit (not group!) and append "*_landed*" for example: "*TransportBlue-1-1_landed*".

For "Actions" add a "Do Script" action and enter

``` lua
industry.addRessourcesTransport("blue", 800)
```

* *addRessourcesTransport* is the command to add ressources for a coalition due to this event.
* *"blue"* the coalition to add ressources for, red or blue. But do not forget the quotes.
* *800* the amount in tons to add

You also need to set the Flag back to false via the addidional action "Clear flag" and the name of the flag above, in our example: "*TransportBlue-1-1_landed*". Or this would trigger every second again and again.

### Respawning groups
You can set every group you like as an automatic respawn group. When the group is dead it is queued for respawn. Different events are detected to determine the death of a unit and if it was the last one the whole group.

You can turn every AI group into a respawn group (NOT player/client groups!).

When the mission starts (and after industry script was initialized) you just need to call

```lua
industry.addRespawnGroup("RedCAP-3", 200)
```

* *addRespawnGroup* is the command to add a group to the list of automatically respawning groups
* *RedCAP-3* is the name of your group you want to respawn. The name is just an example, replace this with the name of your group
* *200* are the cost of ressources in tons to respawn this group, can also be 0

I set this into a "Do script" command in the same trigger where I load the MIST and industry .lua files. I prefer creating an additional init.lua file, where i put all of the addRespawnGroup commands and configuration parameters.

### Configuration
Industry supports the following configurations (with its default values).

``` lua
industry.config.startRessources = 200
industry.config.factoryProduction = 30
industry.config.storageCapacity = 1000
industry.config.productionLoopTime = 300
industry.config.respawnLoopTime = 60
industry.config.labsboost = 10
industry.config.checkDeadGroupsTime = 300
industry.config.respawnRetriesOnQueue = 2
industry.config.winCountdownLength = 600
industry.config.tickets = 100
```

#### industry.config.startRessources
how many tons of ressources does each coalition have right from the start of the mission. Has direct consequences how the mission continues after the first wave of spawned ai units have clashed.

#### industry.config.factoryProduction
How many ressources one factory produces each round/loop run. This is later increased by laboratories. This value is increased by 1 for all factories together (to avoid only 10th of increasement and add some variation to the numbers)

#### industry.config.storageCapacity
How many ressources can be stored in each storage facility.

#### industry.config.productionLoopTime
How many seconds does ech production cycle take. After this the ressources are added to the storages. If a factory was destroyed during a production cycle the ressources produced so far (in this factory) are lost.

#### industry.config.respawnLoopTime
How long does a respawn loop take. After this amount of seconds the four queues are checked and tried to respawn. See below for how queues work and retries/force.

#### industry.config.labsboost
A percentage value calculated from the base production of all factories together. So if we have 3 factories producing 30 tons each we have a base production of 90. so each laboratory increases production by 10% of 90 = 9 tons. Five labs would add 45 tons of produced ressources each turn.

#### industry.config.checkDeadGroupsTime
This is more of a technical feature and usually does not need to be changed. This is how often (time in seconds) the script checks for dangling dead groups and adds them to the respawn queue. they still need to be configured as respawn group.

#### industry.config.respawnRetriesOnQueue
This is more of a technical feature and usually does not need to be changed. If a group cannot respawn, because one unit is not (finally) dead like a plane shot down but not already crashed. The respawn is retried and this is the maximum amount of retries.

#### industry.config.winCountdownLength
How many seconds does the RTB countdown take after one side has one (or mission is draw). Should be a multiple of 60 sec (one minute). Only the last seconds are count down and displayed. Until then every full minute is shown.

#### industry.config.tickets
With how many tickets does each side start. Tickets are reduced by one every minute. Tickets are reduced by one with each human player death and by destructions of labs, factories and storages (the infrastructure as primary mission goals).

## How it works
### Tickets
There are two different types of ressources in Industry. The first one are *tons of production ressources* usually only called *ressources* and there are *tickets*. Tickets are limiting the time for one mission, so you server resets after a maximum number of minutes (measured in tickets). They are the main unit to focus on for winning the mission.

Tickets are reduced for both sides by one every minute. So if you set the *industry.config.tickets' config value to 120 the maximum time for the mission is 2 hours (120 minutes).

Each time a human pilot/player is killed (his plane, so ejecting does not help) the number of tickets for his coalition is reduced by one.

Each time a storage, lab or factory is destroyed the amount of tickets is reduced too.

If a HQ is destroyed the remaining tickets are reduced by half of the remaining tickets. So if 48 tickets where left, the tickets are reduced to 24, for example.

Focussing on the mission goals (destroying strategic targets like HQs, labs, factories and storages) and shooting down players makes your side winning.

### Ressources
Ressources are produced by factories, delivered by air-transport or convoys. The mission designer could also set up trains. This totally depends on the mision design.

Factory production is increased per lab by a configured percentage amount.

Ressources are needed to respawn (AI) units that are queued for respawning.

### Queues
Industry uses four respawn queues. One for "free" (0 tons of ressources) respawns and one for respawns that cost more than 0 tons of ressources. And these two queues for red and blue side each.

Respawns are triggered every 60 seconds, this is the default value and can be configured. The process checks the top of each of the four queues and respawns that group if the ressources are available. Then the group is removed from the top of the queue.

New units to respawn (convoy or destroyed groups) are added to the end of the queue (FIFO principle) and wait for their turn.

This is why there is a free queue for blue and red side - they should not wait for groups that can't be afford due to low ressources.

### Find lost groups and retries
The DCS AI has some very special cases where the unit does not exist any more but it is not triggered as a "death". So every 300 seconds / 5 minutes the script checks all respawn groups if there are no more units alive and tries to requeue them for respawn. Like a garbage collection.

If a group is already in the respawn group and ready to respawn, but the group is not dead (still falling plane wreck from the sky) the respawn is postponed - this avoids removing the crashed plane from the middle of its descent and respawn it at its origin. This would look weird. So the respawn will be retried the next loop run. This is retried maximum of 2 times (can be configured), then the respawn is forced (due to crash landed dead but undead wrecks and such).

### Pilot ejects
One of these cases that are not trivial in some cases are pilot ejects from units that are not destroyed (crashed but not destroyed helicopters). Industry script does explode the plane after the pilot ejects to make sure the unit is dead afterwards. This is only done for auto respawning groups.

### Respawning convoys or transports
Just an idea for your mission design: set the respawn costs for convoys and transports to 0, so these can still respawn if this coalition is very low on ressources. Or the coalition would not be able to recover - and nothing respawns. The mission could get stuck or leave them helpless even if the player does nothing.