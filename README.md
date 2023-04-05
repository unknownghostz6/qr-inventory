## UI redesigned by Unknown Ghostz#9131

Press B to open inventory

# qr-inventory

## Dependencies
- [qr-core](https://github.com/QRCore-framework/qr-core)
- [qr-logs](https://github.com/QRCore-framework/qr-logs) - For logging transfer and other history
- [qr-traphouse](https://github.com/QRCore-framework/qr-traphouse) - Trap house system for QRCore
- [qr-radio](https://github.com/QRCore-framework/qr-radio) - Radio system for communication
- [qr-drugs](https://github.com/QRCore-framework/qr-drugs) -  Drugs and Weed Planting System
- [qr-shops](https://github.com/QRCore-framework/qr-shops) - Needed in order to add shops

## Screenshots
![General](https://cdn.discordapp.com/attachments/1093062643641753640/1093062959707729990/Screenshot_6.png)

## Features
- Item crafting
- Weapon attachment crafting
- Stashes (Personal and/or Shared)
- Vehicle Trunk & Glovebox
- Weapon serial number
- Shops
- Item Drops

## Installation
### Manual
- Download the script and put it in the `[qr]` directory.
- Import `qr-inventory.sql` in your database
- Add the following code to your server.cfg/resouces.cfg
```
ensure qr-core
ensure qr-logs
ensure qr-inventory
ensure qr-traphouse
ensure qr-radio
ensure qr-drugs
ensure qr-shops
```

## Configuration
```
Config = {}

Config.UseTarget = GetConvar('UseTarget', 'false') == 'true' -- Use qr-target interactions (don't change this, go to your server.cfg and add `setr UseTarget true` to use this and just that from true to false or the other way around)

Config.MaxInventoryWeight = 120000 -- Max weight a player can carry (default 120kg, written in grams)
Config.MaxInventorySlots = 41 -- Max inventory slots for a player

Config.CleanupDropTime = 15 * 60 -- How many seconds it takes for drops to be untouched before being deleted
Config.MaxDropViewDistance = 12.5 -- The distance in GTA Units that a drop can be seen
Config.UseItemDrop = false -- This will enable item object to spawn on drops instead of markers
Config.ItemDropObject = `p_bag_leather_doctor` -- if Config.UseItemDrop is true, this will be the prop that spawns for the item

```
