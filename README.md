# DCS-Industry
Industry script for DCS World

## Description
Industry adds a ressorce management and respawn system to

## Features
- Regular production of new ressources in factories
- Delivery of ressources by aerial transport missions or convois on the ground
- Limited storage of ressources in storage facilities
- Respawns depending on available ressources
- factories, storages and transports can and should be destroyed in player or AI missions

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
  In the first action load the MIST .lua file, in the second load the Industry .lua

## Mission setup
### Adding factories
You can use any static object to use as a factory facility. I prefer the Oil pump, or factory buildings.

Factories produce 10 tons of ressources every cycle if they are not destroyed.

To be detected / handled as a factory, the static objects unit name just has to start with "Factory[...]".

### Adding storages
Any static object can be used as a storage facility. Just place a static object that looks like a storage (like a liquid-tank or "small werehouse").

To be detected / handled as a storage facility, the static objects unit name just has to start with "Storage[...]".

Storages can hold 1000 tons of ressources until they are destroyed.

Ressources are distributed evenly between storages. If a storage is destroyed then the ressources are lost in the quota that had been hold in that storage.
