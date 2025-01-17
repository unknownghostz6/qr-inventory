--#region Variables

local QRCore = exports['qr-core']:GetCoreObject()
local Drops = {}
local Stashes = {}
local ShopItems = {}

--#endregion Variables

--#region Functions

---Loads the inventory for the player with the citizenid that is provided
---@param source number Source of the player
---@param citizenid string CitizenID of the player
---@return { [number]: { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } } loadedInventory Table of items with slot as index
local function LoadInventory(source, citizenid)
    local inventory = MySQL.prepare.await('SELECT inventory FROM players WHERE citizenid = ?', { citizenid })
	local loadedInventory = {}
    local missingItems = {}

    if not inventory then return loadedInventory end

	inventory = json.decode(inventory)
	if table.type(inventory) == "empty" then return loadedInventory end

	for _, item in pairs(inventory) do
		if item then
			local itemInfo = QRCore.Shared.Items[item.name:lower()]
			if itemInfo then
				loadedInventory[item.slot] = {
					name = itemInfo['name'],
					amount = item.amount,
					info = item.info or '',
					label = itemInfo['label'],
					description = itemInfo['description'] or '',
					weight = itemInfo['weight'],
					type = itemInfo['type'],
					unique = itemInfo['unique'],
					useable = itemInfo['useable'],
					image = itemInfo['image'],
					shouldClose = itemInfo['shouldClose'],
					slot = item.slot,
					combinable = itemInfo['combinable']
				}
			else
				missingItems[#missingItems + 1] = item.name:lower()
			end
		end
	end

    if #missingItems > 0 then
        print(("The following items were removed for player %s as they no longer exist"):format(GetPlayerName(source)))
		QRCore.Debug(missingItems)
    end

    return loadedInventory
end

exports("LoadInventory", LoadInventory)

---Saves the inventory for the player with the provided source or PlayerData is they're offline
---@param source number | table Source of the player, if offline, then provide the PlayerData in this argument
---@param offline boolean Is the player offline or not, if true, it will expect a table in source
local function SaveInventory(source, offline)
	local PlayerData
	if not offline then
		local Player = QRCore.Functions.GetPlayer(source)

		if not Player then return end

		PlayerData = Player.PlayerData
	else
		PlayerData = source -- for offline users, the playerdata gets sent over the source variable
	end

    local items = PlayerData.items
    local ItemsJson = {}
    if items and table.type(items) ~= "empty" then
        for slot, item in pairs(items) do
            if items[slot] then
                ItemsJson[#ItemsJson+1] = {
                    name = item.name,
                    amount = item.amount,
                    info = item.info,
                    type = item.type,
                    slot = slot,
                }
            end
        end
        MySQL.prepare('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode(ItemsJson), PlayerData.citizenid })
    else
        MySQL.prepare('UPDATE players SET inventory = ? WHERE citizenid = ?', { '[]', PlayerData.citizenid })
    end
end

exports("SaveInventory", SaveInventory)

---Gets the totalweight of the items provided
---@param items { [number]: { amount: number, weight: number } } Table of items, usually the inventory table of the player
---@return number weight Total weight of param items
local function GetTotalWeight(items)
	local weight = 0
    if not items then return 0 end
    for _, item in pairs(items) do
        weight += item.weight * item.amount
    end
    return tonumber(weight)
end

exports("GetTotalWeight", GetTotalWeight)

---Gets the slots that the provided item is in
---@param items { [number]: { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } } Table of items, usually the inventory table of the player
---@param itemName string Name of the item to the get the slots from
---@return number[] slotsFound Array of slots that were found for the item
local function GetSlotsByItem(items, itemName)
    local slotsFound = {}
    if not items then return slotsFound end
    for slot, item in pairs(items) do
        if item.name:lower() == itemName:lower() then
            slotsFound[#slotsFound+1] = slot
        end
    end
    return slotsFound
end

exports("GetSlotsByItem", GetSlotsByItem)

---Get the first slot where the item is located
---@param items { [number]: { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } } Table of items, usually the inventory table of the player
---@param itemName string Name of the item to the get the slot from
---@return number | nil slot If found it returns a number representing the slot, otherwise it sends nil
local function GetFirstSlotByItem(items, itemName)
    if not items then return nil end
    for slot, item in pairs(items) do
        if item.name:lower() == itemName:lower() then
            return tonumber(slot)
        end
    end
    return nil
end

exports("GetFirstSlotByItem", GetFirstSlotByItem)

---Add an item to the inventory of the player
---@param source number The source of the player
---@param item string The item to add to the inventory
---@param amount? number The amount of the item to add
---@param slot? number The slot to add the item to
---@param info? table Extra info to add onto the item to use whenever you get the item
---@return boolean success Returns true if the item was added, false it the item couldn't be added
local function AddItem(source, item, amount, slot, info)
	local Player = QRCore.Functions.GetPlayer(source)

	if not Player then return false end

	local totalWeight = GetTotalWeight(Player.PlayerData.items)
	local itemInfo = QRCore.Shared.Items[item:lower()]
	if not itemInfo and not Player.Offline then
		QRCore.Functions.Notify(source, "Item does not exist", 'error')
		return false
	end

	amount = tonumber(amount) or 1
	slot = tonumber(slot) or GetFirstSlotByItem(Player.PlayerData.items, item)
	info = info or {}

	if itemInfo['type'] == 'weapon' then
		info.serie = info.serie or tostring(QRCore.Shared.RandomInt(2) .. QRCore.Shared.RandomStr(3) .. QRCore.Shared.RandomInt(1) .. QRCore.Shared.RandomStr(2) .. QRCore.Shared.RandomInt(3) .. QRCore.Shared.RandomStr(4))
		info.quality = info.quality or 100
	end
	if (totalWeight + (itemInfo['weight'] * amount)) <= Config.MaxInventoryWeight then
		if (slot and Player.PlayerData.items[slot]) and (Player.PlayerData.items[slot].name:lower() == item:lower()) and (itemInfo['type'] == 'item' and not itemInfo['unique']) then
			Player.PlayerData.items[slot].amount = Player.PlayerData.items[slot].amount + amount
			Player.Functions.SetPlayerData("items", Player.PlayerData.items)

			if Player.Offline then return true end

			TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'AddItem', 'green', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** got item: [slot:' .. slot .. '], itemname: ' .. Player.PlayerData.items[slot].name .. ', added amount: ' .. amount .. ', new total amount: ' .. Player.PlayerData.items[slot].amount)

			return true
		elseif not itemInfo['unique'] and slot or slot and Player.PlayerData.items[slot] == nil then
			Player.PlayerData.items[slot] = { name = itemInfo['name'], amount = amount, info = info or '', label = itemInfo['label'], description = itemInfo['description'] or '', weight = itemInfo['weight'], type = itemInfo['type'], unique = itemInfo['unique'], useable = itemInfo['useable'], image = itemInfo['image'], shouldClose = itemInfo['shouldClose'], slot = slot, combinable = itemInfo['combinable'] }
			Player.Functions.SetPlayerData("items", Player.PlayerData.items)

			if Player.Offline then return true end

			TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'AddItem', 'green', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** got item: [slot:' .. slot .. '], itemname: ' .. Player.PlayerData.items[slot].name .. ', added amount: ' .. amount .. ', new total amount: ' .. Player.PlayerData.items[slot].amount)

			return true
		elseif itemInfo['unique'] or (not slot or slot == nil) or itemInfo['type'] == 'weapon' then
			for i = 1, Config.MaxInventorySlots, 1 do
				if Player.PlayerData.items[i] == nil then
					Player.PlayerData.items[i] = { name = itemInfo['name'], amount = amount, info = info or '', label = itemInfo['label'], description = itemInfo['description'] or '', weight = itemInfo['weight'], type = itemInfo['type'], unique = itemInfo['unique'], useable = itemInfo['useable'], image = itemInfo['image'], shouldClose = itemInfo['shouldClose'], slot = i, combinable = itemInfo['combinable'] }
					Player.Functions.SetPlayerData("items", Player.PlayerData.items)

					if Player.Offline then return true end

					TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'AddItem', 'green', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** got item: [slot:' .. i .. '], itemname: ' .. Player.PlayerData.items[i].name .. ', added amount: ' .. amount .. ', new total amount: ' .. Player.PlayerData.items[i].amount)

					return true
				end
			end
		end
	elseif not Player.Offline then
		QRCore.Functions.Notify(source, "Inventory too full", 'error')
	end
	return false
end

exports("AddItem", AddItem)

---Remove an item from the inventory of the player
---@param source number The source of the player
---@param item string The item to remove from the inventory
---@param amount? number The amount of the item to remove
---@param slot? number The slot to remove the item from
---@return boolean success Returns true if the item was remove, false it the item couldn't be removed
local function RemoveItem(source, item, amount, slot)
	local Player = QRCore.Functions.GetPlayer(source)

	if not Player then return false end

	amount = tonumber(amount) or 1
	slot = tonumber(slot)

	if slot then
		if Player.PlayerData.items[slot].amount > amount then
			Player.PlayerData.items[slot].amount = Player.PlayerData.items[slot].amount - amount
			Player.Functions.SetPlayerData("items", Player.PlayerData.items)

			if not Player.Offline then
				TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. slot .. '], itemname: ' .. Player.PlayerData.items[slot].name .. ', removed amount: ' .. amount .. ', new total amount: ' .. Player.PlayerData.items[slot].amount)
			end

			return true
		elseif Player.PlayerData.items[slot].amount == amount then
			Player.PlayerData.items[slot] = nil
			Player.Functions.SetPlayerData("items", Player.PlayerData.items)

			if Player.Offline then return true end

			TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. slot .. '], itemname: ' .. item .. ', removed amount: ' .. amount .. ', item removed')

			return true
		end
	else
		local slots = GetSlotsByItem(Player.PlayerData.items, item)
		local amountToRemove = amount

		if not slots then return false end

		for _, _slot in pairs(slots) do
			if Player.PlayerData.items[_slot].amount > amountToRemove then
				Player.PlayerData.items[_slot].amount = Player.PlayerData.items[_slot].amount - amountToRemove
				Player.Functions.SetPlayerData("items", Player.PlayerData.items)

				if not Player.Offline then
					TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. _slot .. '], itemname: ' .. Player.PlayerData.items[_slot].name .. ', removed amount: ' .. amount .. ', new total amount: ' .. Player.PlayerData.items[_slot].amount)
				end

				return true
			elseif Player.PlayerData.items[_slot].amount == amountToRemove then
				Player.PlayerData.items[_slot] = nil
				Player.Functions.SetPlayerData("items", Player.PlayerData.items)

				if Player.Offline then return true end

				TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'RemoveItem', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** lost item: [slot:' .. _slot .. '], itemname: ' .. item .. ', removed amount: ' .. amount .. ', item removed')

				return true
			end
		end
	end
	return false
end

exports("RemoveItem", RemoveItem)

---Get the item with the slot
---@param source number The source of the player to get the item from the slot
---@param slot number The slot to get the item from
---@return { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } | nil item Returns the item table, if there is no item in the slot, it will return nil
local function GetItemBySlot(source, slot)
	local Player = QRCore.Functions.GetPlayer(source)
	slot = tonumber(slot)
	return Player.PlayerData.items[slot]
end

exports("GetItemBySlot", GetItemBySlot)

---Get the item from the inventory of the player with the provided source by the name of the item
---@param source number The source of the player
---@param item string The name of the item to get
---@return { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } | nil item Returns the item table, if the item wasn't found, it will return nil
local function GetItemByName(source, item)
	local Player = QRCore.Functions.GetPlayer(source)
	item = tostring(item):lower()
	local slot = GetFirstSlotByItem(Player.PlayerData.items, item)
	return Player.PlayerData.items[slot]
end

exports("GetItemByName", GetItemByName)

---Get the item from the inventory of the player with the provided source by the name of the item in an array for all slots that the item is in
---@param source number The source of the player
---@param item string The name of the item to get
---@return { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table }[] item Returns an array of the item tables found, if the item wasn't found, it will return an empty table
local function GetItemsByName(source, item)
	local Player = QRCore.Functions.GetPlayer(source)
	item = tostring(item):lower()
	local items = {}
	local slots = GetSlotsByItem(Player.PlayerData.items, item)
	for _, slot in pairs(slots) do
		if slot then
			items[#items+1] = Player.PlayerData.items[slot]
		end
	end
	return items
end

exports("GetItemsByName", GetItemsByName)

---Clear the inventory of the player with the provided source and filter any items out of the clearing of the inventory to keep (optional)
---@param source number Source of the player to clear the inventory from
---@param filterItems? string | string[] Array of item names to keep
local function ClearInventory(source, filterItems)
	local Player = QRCore.Functions.GetPlayer(source)
	local savedItemData = {}

	if filterItems then
		local filterItemsType = type(filterItems)
		if filterItemsType == "string" then
			local item = GetItemByName(source, filterItems)

			if item then
				savedItemData[item.slot] = item
			end
		elseif filterItemsType == "table" and table.type(filterItems) == "array" then
			for i = 1, #filterItems do
				local item = GetItemByName(source, filterItems[i])

				if item then
					savedItemData[item.slot] = item
				end
			end
		end
	end

	Player.Functions.SetPlayerData("items", savedItemData)

	if Player.Offline then return end

	TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'ClearInventory', 'red', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** inventory cleared')
end

exports("ClearInventory", ClearInventory)

---Sets the items playerdata to the provided items param
---@param source number The source of player to set it for
---@param items { [number]: { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } } Table of items, the inventory table of the player
local function SetInventory(source, items)
	local Player = QRCore.Functions.GetPlayer(source)

	Player.Functions.SetPlayerData("items", items)

	if Player.Offline then return end

	TriggerEvent('qr-log:server:CreateLog', 'playerinventory', 'SetInventory', 'blue', '**' .. GetPlayerName(source) .. ' (citizenid: ' .. Player.PlayerData.citizenid .. ' | id: ' .. source .. ')** items set: ' .. json.encode(items))
end

exports("SetInventory", SetInventory)

---Set the data of a specific item
---@param source number The source of the player to set it for
---@param itemName string Name of the item to set the data for
---@param key string Name of the data index to change
---@param val any Value to set the data to
---@return boolean success Returns true if it worked
local function SetItemData(source, itemName, key, val)
	if not itemName or not key then return false end

	local Player = QRCore.Functions.GetPlayer(source)

	if not Player then return end

	local item = GetItemByName(source, itemName)

	if not item then return false end

	item[key] = val
	Player.PlayerData.items[item.slot] = item
	Player.Functions.SetPlayerData("items", Player.PlayerData.items)

	return true
end

exports("SetItemData", SetItemData)

---Checks if you have an item or not
---@param source number The source of the player to check it for
---@param items string | string[] | table<string, number> The items to check, either a string, array of strings or a key-value table of a string and number with the string representing the name of the item and the number representing the amount
---@param amount? number The amount of the item to check for, this will only have effect when items is a string or an array of strings
---@return boolean success Returns true if the player has the item
local function HasItem(source, items, amount)
    local Player = QRCore.Functions.GetPlayer(source)
    if not Player then return false end
    local isTable = type(items) == 'table'
    local isArray = isTable and table.type(items) == 'array' or false
    local totalItems = #items
    local count = 0
    local kvIndex = 2
    if isTable and not isArray then
        totalItems = 0
        for _ in pairs(items) do totalItems += 1 end
        kvIndex = 1
    end
    if isTable then
        for k, v in pairs(items) do
            local itemKV = {k, v}
            local item = GetItemByName(source, itemKV[kvIndex])
            if item and ((amount and item.amount >= amount) or (not isArray and item.amount >= v) or (not amount and isArray)) then
                count += 1
            end
        end
        if count == totalItems then
            return true
        end
    else -- Single item as string
        local item = GetItemByName(source, items)
        if item and (not amount or (item and amount and item.amount >= amount)) then
            return true
        end
    end
    return false
end

exports("HasItem", HasItem)

---Create a usable item with a callback on use
---@param itemName string The name of the item to make usable
---@param data any
local function CreateUsableItem(itemName, data)
	QRCore.Functions.CreateUseableItem(itemName, data)
end

exports("CreateUsableItem", CreateUsableItem)

---Get the usable item data for the specified item
---@param itemName string The item to get the data for
---@return any usable_item
local function GetUsableItem(itemName)
	return QRCore.Functions.CanUseItem(itemName)
end

exports("GetUsableItem", GetUsableItem)

---Use an item from the QRCore.UsableItems table if a callback is present
---@param itemName string The name of the item to use
---@param ... any Arguments for the callback, this will be sent to the callback and can be used to get certain values
local function UseItem(itemName, ...)
	local itemData = GetUsableItem(itemName)
	local callback = type(itemData) == 'table' and (rawget(itemData, '__cfx_functionReference') and itemData or itemData.cb or itemData.callback) or type(itemData) == 'function' and itemData
	if not callback then return end
	callback(...)
end

exports("UseItem", UseItem)

---Check if a recipe contains the item
---@param recipe table The recipe of the item
---@param fromItem { name: string, amount: number, info?: table, label: string, description: string, weight: number, type: string, unique: boolean, useable: boolean, image: string, shouldClose: boolean, slot: number, combinable: table } The item to check
---@return boolean success Returns true if the recipe contains the item
local function recipeContains(recipe, fromItem)
	for _, v in pairs(recipe.accept) do
		if v == fromItem.name then
			return true
		end
	end

	return false
end

---Setup the shop items
---@param shopItems table
---@return table items
local function SetupShopItems(shopItems)
	local items = {}
	if shopItems and next(shopItems) then
		for _, item in pairs(shopItems) do
			local itemInfo = QRCore.Shared.Items[item.name:lower()]
			if itemInfo then
				items[item.slot] = {
					name = itemInfo["name"],
					amount = tonumber(item.amount),
					info = item.info or "",
					label = itemInfo["label"],
					description = itemInfo["description"] or "",
					weight = itemInfo["weight"],
					type = itemInfo["type"],
					unique = itemInfo["unique"],
					useable = itemInfo["useable"],
					price = item.price,
					image = itemInfo["image"],
					slot = item.slot,
				}
			end
		end
	end
	return items
end

---Get items in a stash
---@param stashId string The id of the stash to get
---@return table items
local function GetStashItems(stashId)
	local items = {}
	local result = MySQL.scalar.await('SELECT items FROM stashitems WHERE stash = ?', {stashId})
	if not result then return items end

	local stashItems = json.decode(result)
	if not stashItems then return items end

	for _, item in pairs(stashItems) do
		local itemInfo = QRCore.Shared.Items[item.name:lower()]
		if itemInfo then
			items[item.slot] = {
				name = itemInfo["name"],
				amount = tonumber(item.amount),
				info = item.info or "",
				label = itemInfo["label"],
				description = itemInfo["description"] or "",
				weight = itemInfo["weight"],
				type = itemInfo["type"],
				unique = itemInfo["unique"],
				useable = itemInfo["useable"],
				image = itemInfo["image"],
				slot = item.slot,
			}
		end
	end
	return items
end

---Save the items in a stash
---@param stashId string The stash id to save the items from
---@param items table items to save
local function SaveStashItems(stashId, items)
	if Stashes[stashId].label == "Stash-None" or not items then return end

	for _, item in pairs(items) do
		item.description = nil
	end

	MySQL.insert('INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
		['stash'] = stashId,
		['items'] = json.encode(items)
	})

	Stashes[stashId].isOpen = false
end

---Add items to a stash
---@param stashId string Stash id to save it to
---@param slot number Slot of the stash to save the item to
---@param otherslot number Slot of the stash to swap it to the item isn't unique
---@param itemName string The name of the item
---@param amount? number The amount of the item
---@param info? table The info of the item
local function AddToStash(stashId, slot, otherslot, itemName, amount, info)
	amount = tonumber(amount) or 1
	local ItemData = QRCore.Shared.Items[itemName]
	if not ItemData.unique then
		if Stashes[stashId].items[slot] and Stashes[stashId].items[slot].name == itemName then
			Stashes[stashId].items[slot].amount = Stashes[stashId].items[slot].amount + amount
		else
			local itemInfo = QRCore.Shared.Items[itemName:lower()]
			Stashes[stashId].items[slot] = {
				name = itemInfo["name"],
				amount = amount,
				info = info or "",
				label = itemInfo["label"],
				description = itemInfo["description"] or "",
				weight = itemInfo["weight"],
				type = itemInfo["type"],
				unique = itemInfo["unique"],
				useable = itemInfo["useable"],
				image = itemInfo["image"],
				slot = slot,
			}
		end
	else
		if Stashes[stashId].items[slot] and Stashes[stashId].items[slot].name == itemName then
			local itemInfo = QRCore.Shared.Items[itemName:lower()]
			Stashes[stashId].items[otherslot] = {
				name = itemInfo["name"],
				amount = amount,
				info = info or "",
				label = itemInfo["label"],
				description = itemInfo["description"] or "",
				weight = itemInfo["weight"],
				type = itemInfo["type"],
				unique = itemInfo["unique"],
				useable = itemInfo["useable"],
				image = itemInfo["image"],
				slot = otherslot,
			}
		else
			local itemInfo = QRCore.Shared.Items[itemName:lower()]
			Stashes[stashId].items[slot] = {
				name = itemInfo["name"],
				amount = amount,
				info = info or "",
				label = itemInfo["label"],
				description = itemInfo["description"] or "",
				weight = itemInfo["weight"],
				type = itemInfo["type"],
				unique = itemInfo["unique"],
				useable = itemInfo["useable"],
				image = itemInfo["image"],
				slot = slot,
			}
		end
	end
end

---Remove the item from the stash
---@param stashId string Stash id to remove the item from
---@param slot number Slot to remove the item from
---@param itemName string Name of the item to remove
---@param amount? number The amount to remove
local function RemoveFromStash(stashId, slot, itemName, amount)
	amount = tonumber(amount) or 1
	if Stashes[stashId].items[slot] and Stashes[stashId].items[slot].name == itemName then
		if Stashes[stashId].items[slot].amount > amount then
			Stashes[stashId].items[slot].amount = Stashes[stashId].items[slot].amount - amount
		else
			Stashes[stashId].items[slot] = nil
		end
	else
		Stashes[stashId].items[slot] = nil
		if Stashes[stashId].items == nil then
			Stashes[stashId].items[slot] = nil
		end
	end
end

---Add an item to a drop
---@param dropId integer The id of the drop
---@param slot number The slot of the drop inventory to add the item to
---@param itemName string Name of the item to add
---@param amount? number The amount of the item to add
---@param info? table Extra info to add to the item
local function AddToDrop(dropId, slot, itemName, amount, info)
	amount = tonumber(amount) or 1
	Drops[dropId].createdTime = os.time()
	if Drops[dropId].items[slot] and Drops[dropId].items[slot].name == itemName then
		Drops[dropId].items[slot].amount = Drops[dropId].items[slot].amount + amount
	else
		local itemInfo = QRCore.Shared.Items[itemName:lower()]
		Drops[dropId].items[slot] = {
			name = itemInfo["name"],
			amount = amount,
			info = info or "",
			label = itemInfo["label"],
			description = itemInfo["description"] or "",
			weight = itemInfo["weight"],
			type = itemInfo["type"],
			unique = itemInfo["unique"],
			useable = itemInfo["useable"],
			image = itemInfo["image"],
			slot = slot,
			id = dropId,
		}
	end
end

---Remove an item from a drop
---@param dropId integer The id of the drop to remove it from
---@param slot number The slot of the drop inventory
---@param itemName string The name of the item to remove
---@param amount? number The amount to remove
local function RemoveFromDrop(dropId, slot, itemName, amount)
	amount = tonumber(amount) or 1
	Drops[dropId].createdTime = os.time()
	if Drops[dropId].items[slot] and Drops[dropId].items[slot].name == itemName then
		if Drops[dropId].items[slot].amount > amount then
			Drops[dropId].items[slot].amount = Drops[dropId].items[slot].amount - amount
		else
			Drops[dropId].items[slot] = nil
		end
	else
		Drops[dropId].items[slot] = nil
		if Drops[dropId].items == nil then
			Drops[dropId].items[slot] = nil
		end
	end
end

---Creates a new id for a drop
---@return integer
local function CreateDropId()
	if Drops then
		local id = math.random(10000, 99999)
		local dropid = id
		while Drops[dropid] do
			id = math.random(10000, 99999)
			dropid = id
		end
		return dropid
	else
		local id = math.random(10000, 99999)
		local dropid = id
		return dropid
	end
end

---Creates a new drop
---@param source number The source of the player
---@param fromSlot number The slot that the item comes from
---@param toSlot number The slot that the item goes to
---@param itemAmount? number The amount of the item drop to create
local function CreateNewDrop(source, fromSlot, toSlot, itemAmount)
	itemAmount = tonumber(itemAmount) or 1
	local Player = QRCore.Functions.GetPlayer(source)
	local itemData = GetItemBySlot(source, fromSlot)

	if not itemData then return end

	local coords = GetEntityCoords(GetPlayerPed(source))
	if RemoveItem(source, itemData.name, itemAmount, itemData.slot) then
		TriggerClientEvent("inventory:client:CheckWeapon", source, itemData.name)
		local itemInfo = QRCore.Shared.Items[itemData.name:lower()]
		local dropId = CreateDropId()
		Drops[dropId] = {}
		Drops[dropId].coords = coords
		Drops[dropId].createdTime = os.time()

		Drops[dropId].items = {}

		Drops[dropId].items[toSlot] = {
			name = itemInfo["name"],
			amount = itemAmount,
			info = itemData.info or "",
			label = itemInfo["label"],
			description = itemInfo["description"] or "",
			weight = itemInfo["weight"],
			type = itemInfo["type"],
			unique = itemInfo["unique"],
			useable = itemInfo["useable"],
			image = itemInfo["image"],
			slot = toSlot,
			id = dropId,
		}
		TriggerEvent("qr-log:server:CreateLog", "drop", "New Item Drop", "red", "**".. GetPlayerName(source) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..source.."*) dropped new item; name: **"..itemData.name.."**, amount: **" .. itemAmount .. "**")
		TriggerClientEvent("inventory:client:DropItemAnim", source)
		TriggerClientEvent("inventory:client:AddDropItem", -1, dropId, source, coords)
		if itemData.name:lower() == "radio" then
			TriggerClientEvent('Radio.Set', source, false)
		end
	else
		QRCore.Functions.Notify(source, Lang:t("notify.missitem"), "error")
	end
end

--#endregion Functions

--#region Events

AddEventHandler('QRCore:Server:PlayerLoaded', function(Player)
	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "AddItem", function(item, amount, slot, info)
		return AddItem(Player.PlayerData.source, item, amount, slot, info)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "RemoveItem", function(item, amount, slot)
		return RemoveItem(Player.PlayerData.source, item, amount, slot)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemBySlot", function(slot)
		return GetItemBySlot(Player.PlayerData.source, slot)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemByName", function(item)
		return GetItemByName(Player.PlayerData.source, item)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "GetItemsByName", function(item)
		return GetItemsByName(Player.PlayerData.source, item)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "ClearInventory", function(filterItems)
		ClearInventory(Player.PlayerData.source, filterItems)
	end)

	QRCore.Functions.AddPlayerMethod(Player.PlayerData.source, "SetInventory", function(items)
		SetInventory(Player.PlayerData.source, items)
	end)
end)

AddEventHandler('onResourceStart', function(resourceName)
	if resourceName ~= GetCurrentResourceName() then return end
	local Players = QRCore.Functions.GetQRPlayers()
	for k in pairs(Players) do
		QRCore.Functions.AddPlayerMethod(k, "AddItem", function(item, amount, slot, info)
			return AddItem(k, item, amount, slot, info)
		end)

		QRCore.Functions.AddPlayerMethod(k, "RemoveItem", function(item, amount, slot)
			return RemoveItem(k, item, amount, slot)
		end)

		QRCore.Functions.AddPlayerMethod(k, "GetItemBySlot", function(slot)
			return GetItemBySlot(k, slot)
		end)

		QRCore.Functions.AddPlayerMethod(k, "GetItemByName", function(item)
			return GetItemByName(k, item)
		end)

		QRCore.Functions.AddPlayerMethod(k, "GetItemsByName", function(item)
			return GetItemsByName(k, item)
		end)

		QRCore.Functions.AddPlayerMethod(k, "ClearInventory", function(filterItems)
			ClearInventory(k, filterItems)
		end)

		QRCore.Functions.AddPlayerMethod(k, "SetInventory", function(items)
			SetInventory(k, items)
		end)
	end
end)

RegisterNetEvent('QRCore:Server:UpdateObject', function()
    if source ~= '' then return end -- Safety check if the event was not called from the server.
    QRCore = exports['qr-core']:GetCoreObject()
end)

RegisterNetEvent('inventory:server:combineItem', function(item, fromItem, toItem)
	local src = source

	-- Check that inputs are not nil
	-- Most commonly when abusing this exploit, this values are left as
	if fromItem == nil  then return end
	if toItem == nil then return end

	-- Check that they have the items
	fromItem = GetItemByName(src, fromItem)
	toItem = GetItemByName(src, toItem)

	if fromItem == nil  then return end
	if toItem == nil then return end

	-- Check the recipe is valid
	local recipe = QRCore.Shared.Items[toItem.name].combinable

	if recipe and recipe.reward ~= item then return end
	if not recipeContains(recipe, fromItem) then return end

	TriggerClientEvent('inventory:client:ItemBox', src, QRCore.Shared.Items[item], 'add')
	AddItem(src, item, 1)
	RemoveItem(src, fromItem.name, 1)
	RemoveItem(src, toItem.name, 1)
end)

RegisterNetEvent('inventory:server:SetIsOpenState', function(IsOpen, type, id)
	if IsOpen then return end

	if type == "stash" then
		Stashes[id].isOpen = false
	elseif type == "drop" then
		Drops[id].isOpen = false
	end
end)

RegisterNetEvent('inventory:server:OpenInventory', function(name, id, other)
	local src = source
	local ply = Player(src)
	local Player = QRCore.Functions.GetPlayer(src)
	if not ply.state.inv_busy then
		if name and id then
			local secondInv = {}
			if name == "stash" then
				if Stashes[id] then
					if Stashes[id].isOpen then
						local Target = QRCore.Functions.GetPlayer(Stashes[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Stashes[id].isOpen, name, id, Stashes[id].label)
						else
							Stashes[id].isOpen = false
						end
					end
				end
				local maxweight = 1000000
				local slots = 50
				if other then
					maxweight = other.maxweight or 1000000
					slots = other.slots or 50
				end
				secondInv.name = "stash-"..id
				secondInv.label = "Stash-"..id
				secondInv.maxweight = maxweight
				secondInv.inventory = {}
				secondInv.slots = slots
				if Stashes[id] and Stashes[id].isOpen then
					secondInv.name = "none-inv"
					secondInv.label = "Stash-None"
					secondInv.maxweight = 1000000
					secondInv.inventory = {}
					secondInv.slots = 0
				else
					local stashItems = GetStashItems(id)
					if next(stashItems) then
						secondInv.inventory = stashItems
						Stashes[id] = {}
						Stashes[id].items = stashItems
						Stashes[id].isOpen = src
						Stashes[id].label = secondInv.label
					else
						Stashes[id] = {}
						Stashes[id].items = {}
						Stashes[id].isOpen = src
						Stashes[id].label = secondInv.label
					end
				end
			elseif name == "shop" then
				secondInv.name = "itemshop-"..id
				secondInv.label = other.label
				secondInv.maxweight = 900000
				secondInv.inventory = SetupShopItems(other.items)
				ShopItems[id] = {}
				ShopItems[id].items = other.items
				secondInv.slots = #other.items
			elseif name == "otherplayer" then
				local OtherPlayer = QRCore.Functions.GetPlayer(tonumber(id))
				if OtherPlayer then
					secondInv.name = "otherplayer-"..id
					secondInv.label = "Player-"..id
					secondInv.maxweight = Config.MaxInventoryWeight
					secondInv.inventory = OtherPlayer.PlayerData.items
					if Player.PlayerData.job.name == "police" and Player.PlayerData.job.onduty then
						secondInv.slots = Config.MaxInventorySlots
					else
						secondInv.slots = Config.MaxInventorySlots - 1
					end
					Wait(250)
				end
			else
				if Drops[id] then
					if Drops[id].isOpen then
						local Target = QRCore.Functions.GetPlayer(Drops[id].isOpen)
						if Target then
							TriggerClientEvent('inventory:client:CheckOpenState', Drops[id].isOpen, name, id, Drops[id].label)
						else
							Drops[id].isOpen = false
						end
					end
				end
				if Drops[id] and not Drops[id].isOpen then
					secondInv.coords = Drops[id].coords
					secondInv.name = id
					secondInv.label = "Dropped-"..tostring(id)
					secondInv.maxweight = 100000
					secondInv.inventory = Drops[id].items
					secondInv.slots = 30
					Drops[id].isOpen = src
					Drops[id].label = secondInv.label
					Drops[id].createdTime = os.time()
				else
					secondInv.name = "none-inv"
					secondInv.label = "Dropped-None"
					secondInv.maxweight = 100000
					secondInv.inventory = {}
					secondInv.slots = 0
				end
			end
			TriggerClientEvent("qr-inventory:client:closeinv", id)
			TriggerClientEvent("inventory:client:OpenInventory", src, {}, Player.PlayerData.items, secondInv)
		else
			TriggerClientEvent("inventory:client:OpenInventory", src, {}, Player.PlayerData.items)
		end
	else
		QRCore.Functions.Notify(src, Lang:t("notify.noaccess"), 'error')
	end
end)

RegisterNetEvent('inventory:server:SaveInventory', function(type, id)
	if type == "stash" then
		SaveStashItems(id, Stashes[id].items)
	elseif type == "drop" then
		if Drops[id] then
			Drops[id].isOpen = false
			if Drops[id].items == nil or next(Drops[id].items) == nil then
				Drops[id] = nil
				TriggerClientEvent("inventory:client:RemoveDropItem", -1, id)
			end
		end
	end
end)

-- use item
RegisterNetEvent('inventory:server:UseItemSlot', function(slot)
	local src = source
	local itemData = GetItemBySlot(src, slot)
	if not itemData then return end
	local itemInfo = QRCore.Shared.Items[itemData.name]
	if itemData.type == "weapon" then
		TriggerClientEvent("qr-weapons:client:UseWeapon", src, itemData, itemData.info.quality and itemData.info.quality > 0)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	elseif itemData.useable then
		UseItem(itemData.name, src, itemData)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	end
end)

RegisterNetEvent('inventory:server:UseItem', function(inventory, item)
	local src = source
	if inventory ~= "player" and inventory ~= "hotbar" then return end
	local itemData = GetItemBySlot(src, item.slot)
	if not itemData then return end
	local itemInfo = QRCore.Shared.Items[itemData.name]
	if itemData.type == "weapon" then
		TriggerClientEvent("qr-weapons:client:UseWeapon", src, itemData, itemData.info.quality and itemData.info.quality > 0)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	else
		UseItem(itemData.name, src, itemData)
		TriggerClientEvent('inventory:client:ItemBox', src, itemInfo, "use")
	end
end)

RegisterNetEvent('inventory:server:SetInventoryData', function(fromInventory, toInventory, fromSlot, toSlot, fromAmount, toAmount)
	local src = source
	local Player = QRCore.Functions.GetPlayer(src)
	fromSlot = tonumber(fromSlot)
	toSlot = tonumber(toSlot)

	if (fromInventory == "player" or fromInventory == "hotbar") and (QRCore.Shared.SplitStr(toInventory, "-")[1] == "itemshop") then
		return
	end

	if fromInventory == "player" or fromInventory == "hotbar" then
		local fromItemData = GetItemBySlot(src, fromSlot)
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot(src, toSlot)
				RemoveItem(src, fromItemData.name, fromAmount, fromSlot)
				--TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						RemoveItem(src, toItemData.name, toAmount, toSlot)
						AddItem(src, toItemData.name, toAmount, fromSlot, toItemData.info)
					end
				end
				AddItem(src, fromItemData.name, fromAmount, toSlot, fromItemData.info)
			elseif QRCore.Shared.SplitStr(toInventory, "-")[1] == "otherplayer" then
				local playerId = tonumber(QRCore.Shared.SplitStr(toInventory, "-")[2])
				local OtherPlayer = QRCore.Functions.GetPlayer(playerId)
				local toItemData = OtherPlayer.PlayerData.items[toSlot]
				RemoveItem(src, fromItemData.name, fromAmount, fromSlot)
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					local itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						RemoveItem(playerId, itemInfo["name"], toAmount, fromSlot)
						AddItem(src, toItemData.name, toAmount, fromSlot, toItemData.info)
						TriggerEvent("qr-log:server:CreateLog", "robbing", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | *"..src.."*) swapped item; name: **"..itemInfo["name"].."**, amount: **" .. toAmount .. "** with name: **" .. fromItemData.name .. "**, amount: **" .. fromAmount.. "** with player: **".. GetPlayerName(OtherPlayer.PlayerData.source) .. "** (citizenid: *"..OtherPlayer.PlayerData.citizenid.."* | id: *"..OtherPlayer.PlayerData.source.."*)")
					end
				else
					local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
					TriggerEvent("qr-log:server:CreateLog", "robbing", "Dropped Item", "red", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | *"..src.."*) dropped new item; name: **"..itemInfo["name"].."**, amount: **" .. fromAmount .. "** to player: **".. GetPlayerName(OtherPlayer.PlayerData.source) .. "** (citizenid: *"..OtherPlayer.PlayerData.citizenid.."* | id: *"..OtherPlayer.PlayerData.source.."*)")
				end
				local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
				AddItem(playerId, itemInfo["name"], fromAmount, toSlot, fromItemData.info)
			elseif QRCore.Shared.SplitStr(toInventory, "-")[1] == "stash" then
				local stashId = QRCore.Shared.SplitStr(toInventory, "-")[2]
				local toItemData = Stashes[stashId].items[toSlot]
				RemoveItem(src, fromItemData.name, fromAmount, fromSlot)
				TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					local itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						--RemoveFromStash(stashId, fromSlot, itemInfo["name"], toAmount)
						RemoveFromStash(stashId, toSlot, itemInfo["name"], toAmount)
						AddItem(src, toItemData.name, toAmount, fromSlot, toItemData.info)
						TriggerEvent("qr-log:server:CreateLog", "stash", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) swapped item; name: **"..itemInfo["name"].."**, amount: **" .. toAmount .. "** with name: **" .. fromItemData.name .. "**, amount: **" .. fromAmount .. "** - stash: *" .. stashId .. "*")
					end
				else
					local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
					TriggerEvent("qr-log:server:CreateLog", "stash", "Dropped Item", "red", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) dropped new item; name: **"..itemInfo["name"].."**, amount: **" .. fromAmount .. "** - stash: *" .. stashId .. "*")
				end
				local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
				AddToStash(stashId, toSlot, fromSlot, itemInfo["name"], fromAmount, fromItemData.info)
			else
				-- drop
				toInventory = tonumber(toInventory)
				if toInventory == nil or toInventory == 0 then
					CreateNewDrop(src, fromSlot, toSlot, fromAmount)
				else
					local toItemData = Drops[toInventory].items[toSlot]
					RemoveItem(src, fromItemData.name, fromAmount, fromSlot)
					TriggerClientEvent("inventory:client:CheckWeapon", src, fromItemData.name)
					if toItemData then
						local itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
						toAmount = tonumber(toAmount) or toItemData.amount
						if toItemData.name ~= fromItemData.name then
							AddItem(src, toItemData.name, toAmount, fromSlot, toItemData.info)
							RemoveFromDrop(toInventory, fromSlot, itemInfo["name"], toAmount)
							TriggerEvent("qr-log:server:CreateLog", "drop", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) swapped item; name: **"..itemInfo["name"].."**, amount: **" .. toAmount .. "** with name: **" .. fromItemData.name .. "**, amount: **" .. fromAmount .. "** - dropid: *" .. toInventory .. "*")
						end
					else
						local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
						TriggerEvent("qr-log:server:CreateLog", "drop", "Dropped Item", "red", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) dropped new item; name: **"..itemInfo["name"].."**, amount: **" .. fromAmount .. "** - dropid: *" .. toInventory .. "*")
					end
					local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
					AddToDrop(toInventory, toSlot, itemInfo["name"], fromAmount, fromItemData.info)
					if itemInfo["name"] == "radio" then
						TriggerClientEvent('Radio.Set', src, false)
					end
				end
			end
		else
			QRCore.Functions.Notify(src, Lang:t("notify.missitem"), "error")
		end
	elseif QRCore.Shared.SplitStr(fromInventory, "-")[1] == "otherplayer" then
		local playerId = tonumber(QRCore.Shared.SplitStr(fromInventory, "-")[2])
		local OtherPlayer = QRCore.Functions.GetPlayer(playerId)
		local fromItemData = OtherPlayer.PlayerData.items[fromSlot]
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot(src, toSlot)
				RemoveItem(playerId, itemInfo["name"], fromAmount, fromSlot)
				TriggerClientEvent("inventory:client:CheckWeapon", OtherPlayer.PlayerData.source, fromItemData.name)
				if toItemData then
					itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						RemoveItem(src, toItemData.name, toAmount, toSlot)
						AddItem(playerId, itemInfo["name"], toAmount, fromSlot, toItemData.info)
						TriggerEvent("qr-log:server:CreateLog", "robbing", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) swapped item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** with item; **"..itemInfo["name"].."**, amount: **" .. toAmount .. "** from player: **".. GetPlayerName(OtherPlayer.PlayerData.source) .. "** (citizenid: *"..OtherPlayer.PlayerData.citizenid.."* | *"..OtherPlayer.PlayerData.source.."*)")
					end
				else
					TriggerEvent("qr-log:server:CreateLog", "robbing", "Retrieved Item", "green", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) took item; name: **"..fromItemData.name.."**, amount: **" .. fromAmount .. "** from player: **".. GetPlayerName(OtherPlayer.PlayerData.source) .. "** (citizenid: *"..OtherPlayer.PlayerData.citizenid.."* | *"..OtherPlayer.PlayerData.source.."*)")
				end
				AddItem(src, fromItemData.name, fromAmount, toSlot, fromItemData.info)
			else
				local toItemData = OtherPlayer.PlayerData.items[toSlot]
				RemoveItem(playerId, itemInfo["name"], fromAmount, fromSlot)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
						RemoveItem(playerId, itemInfo["name"], toAmount, toSlot)
						AddItem(playerId, itemInfo["name"], toAmount, fromSlot, toItemData.info)
					end
				end
				itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
				AddItem(playerId, itemInfo["name"], fromAmount, toSlot, fromItemData.info)
			end
		else
			QRCore.Functions.Notify(src, "Item doesn't exist", "error")
		end
	elseif QRCore.Shared.SplitStr(fromInventory, "-")[1] == "stash" then
		local stashId = QRCore.Shared.SplitStr(fromInventory, "-")[2]
		local fromItemData = Stashes[stashId].items[fromSlot]
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot(src, toSlot)
				RemoveFromStash(stashId, fromSlot, itemInfo["name"], fromAmount)
				if toItemData then
					itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						RemoveItem(src, toItemData.name, toAmount, toSlot)
						AddToStash(stashId, fromSlot, toSlot, itemInfo["name"], toAmount, toItemData.info)
						TriggerEvent("qr-log:server:CreateLog", "stash", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) swapped item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** with item; name: **"..fromItemData.name.."**, amount: **" .. fromAmount .. "** stash: *" .. stashId .. "*")
					else
						TriggerEvent("qr-log:server:CreateLog", "stash", "Stacked Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) stacked item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** from stash: *" .. stashId .. "*")
					end
				else
					TriggerEvent("qr-log:server:CreateLog", "stash", "Received Item", "green", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) received item; name: **"..fromItemData.name.."**, amount: **" .. fromAmount.. "** stash: *" .. stashId .. "*")
				end
				SaveStashItems(stashId, Stashes[stashId].items)
				AddItem(src, fromItemData.name, fromAmount, toSlot, fromItemData.info)
			else
				local toItemData = Stashes[stashId].items[toSlot]
				RemoveFromStash(stashId, fromSlot, itemInfo["name"], fromAmount)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
						RemoveFromStash(stashId, toSlot, itemInfo["name"], toAmount)
						AddToStash(stashId, fromSlot, toSlot, itemInfo["name"], toAmount, toItemData.info)
					end
				end
				itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
				AddToStash(stashId, toSlot, fromSlot, itemInfo["name"], fromAmount, fromItemData.info)
			end
		else
			QRCore.Functions.Notify(src, Lang:t("notify.itemexist"), "error")
		end
	elseif QRCore.Shared.SplitStr(fromInventory, "-")[1] == "itemshop" then
		local shopType = QRCore.Shared.SplitStr(fromInventory, "-")[2]
		local itemData = ShopItems[shopType].items[fromSlot]
		local itemInfo = QRCore.Shared.Items[itemData.name:lower()]
		local bankBalance = Player.PlayerData.money["bank"]
		local price = tonumber((itemData.price*fromAmount))

		if QRCore.Shared.SplitStr(shopType, "_")[1] == "Dealer" then
			if QRCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
				price = tonumber(itemData.price)
				if Player.Functions.RemoveMoney("cash", price, "dealer-item-bought") then
					itemData.info.serie = tostring(QRCore.Shared.RandomInt(2) .. QRCore.Shared.RandomStr(3) .. QRCore.Shared.RandomInt(1) .. QRCore.Shared.RandomStr(2) .. QRCore.Shared.RandomInt(3) .. QRCore.Shared.RandomStr(4))
					itemData.info.quality = 100
					AddItem(src, itemData.name, 1, toSlot, itemData.info)
					TriggerClientEvent('qr-drugs:client:updateDealerItems', src, itemData, 1)
					QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
					TriggerEvent("qr-log:server:CreateLog", "dealers", "Dealer item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
				else
					QRCore.Functions.Notify(src, Lang:t("notify.notencash"), "error")
				end
			else
				if Player.Functions.RemoveMoney("cash", price, "dealer-item-bought") then
					AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
					TriggerClientEvent('qr-drugs:client:updateDealerItems', src, itemData, fromAmount)
					QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
					TriggerEvent("qr-log:server:CreateLog", "dealers", "Dealer item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. "  for $"..price)
				else
					QRCore.Functions.Notify(src, "You don't have enough cash..", "error")
				end
			end
		elseif QRCore.Shared.SplitStr(shopType, "_")[1] == "Itemshop" then
			if Player.Functions.RemoveMoney("cash", price, "itemshop-bought-item") then
                if QRCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
                    itemData.info.serie = tostring(QRCore.Shared.RandomInt(2) .. QRCore.Shared.RandomStr(3) .. QRCore.Shared.RandomInt(1) .. QRCore.Shared.RandomStr(2) .. QRCore.Shared.RandomInt(3) .. QRCore.Shared.RandomStr(4))
					itemData.info.quality = 100
                end
				AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
				TriggerClientEvent('qr-shops:client:UpdateShop', src, QRCore.Shared.SplitStr(shopType, "_")[2], itemData, fromAmount)
				QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				TriggerEvent("qr-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
			elseif bankBalance >= price then
				Player.Functions.RemoveMoney("bank", price, "itemshop-bought-item")
                if QRCore.Shared.SplitStr(itemData.name, "_")[1] == "weapon" then
                    itemData.info.serie = tostring(QRCore.Shared.RandomInt(2) .. QRCore.Shared.RandomStr(3) .. QRCore.Shared.RandomInt(1) .. QRCore.Shared.RandomStr(2) .. QRCore.Shared.RandomInt(3) .. QRCore.Shared.RandomStr(4))
					itemData.info.quality = 100
                end
				AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
				TriggerClientEvent('qr-shops:client:UpdateShop', src, QRCore.Shared.SplitStr(shopType, "_")[2], itemData, fromAmount)
				QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				TriggerEvent("qr-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
			else
				QRCore.Functions.Notify(src, "You don't have enough cash..", "error")
			end
		else
			if Player.Functions.RemoveMoney("cash", price, "unkown-itemshop-bought-item") then
				AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
				QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				TriggerEvent("qr-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
			elseif bankBalance >= price then
				Player.Functions.RemoveMoney("bank", price, "unkown-itemshop-bought-item")
				AddItem(src, itemData.name, fromAmount, toSlot, itemData.info)
				QRCore.Functions.Notify(src, itemInfo["label"] .. " bought!", "success")
				TriggerEvent("qr-log:server:CreateLog", "shops", "Shop item bought", "green", "**"..GetPlayerName(src) .. "** bought a " .. itemInfo["label"] .. " for $"..price)
			else
				QRCore.Functions.Notify(src, Lang:t("notify.notencash"), "error")
			end
		end
	else
		-- drop
		fromInventory = tonumber(fromInventory)
		local fromItemData = Drops[fromInventory].items[fromSlot]
		fromAmount = tonumber(fromAmount) or fromItemData.amount
		if fromItemData and fromItemData.amount >= fromAmount then
			local itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
			if toInventory == "player" or toInventory == "hotbar" then
				local toItemData = GetItemBySlot(src, toSlot)
				RemoveFromDrop(fromInventory, fromSlot, itemInfo["name"], fromAmount)
				if toItemData then
					toAmount = tonumber(toAmount) and tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
						RemoveItem(src, toItemData.name, toAmount, toSlot)
						AddToDrop(fromInventory, toSlot, itemInfo["name"], toAmount, toItemData.info)
						if itemInfo["name"] == "radio" then
							TriggerClientEvent('Radio.Set', src, false)
						end
						TriggerEvent("qr-log:server:CreateLog", "drop", "Swapped Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) swapped item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** with item; name: **"..fromItemData.name.."**, amount: **" .. fromAmount .. "** - dropid: *" .. fromInventory .. "*")
					else
						TriggerEvent("qr-log:server:CreateLog", "drop", "Stacked Item", "orange", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) stacked item; name: **"..toItemData.name.."**, amount: **" .. toAmount .. "** - from dropid: *" .. fromInventory .. "*")
					end
				else
					TriggerEvent("qr-log:server:CreateLog", "drop", "Received Item", "green", "**".. GetPlayerName(src) .. "** (citizenid: *"..Player.PlayerData.citizenid.."* | id: *"..src.."*) received item; name: **"..fromItemData.name.."**, amount: **" .. fromAmount.. "** -  dropid: *" .. fromInventory .. "*")
				end
				AddItem(src, fromItemData.name, fromAmount, toSlot, fromItemData.info)
			else
				toInventory = tonumber(toInventory)
				local toItemData = Drops[toInventory].items[toSlot]
				RemoveFromDrop(fromInventory, fromSlot, itemInfo["name"], fromAmount)
				--Player.PlayerData.items[toSlot] = fromItemData
				if toItemData then
					--Player.PlayerData.items[fromSlot] = toItemData
					toAmount = tonumber(toAmount) or toItemData.amount
					if toItemData.name ~= fromItemData.name then
						itemInfo = QRCore.Shared.Items[toItemData.name:lower()]
						RemoveFromDrop(toInventory, toSlot, itemInfo["name"], toAmount)
						AddToDrop(fromInventory, fromSlot, itemInfo["name"], toAmount, toItemData.info)
						if itemInfo["name"] == "radio" then
							TriggerClientEvent('Radio.Set', src, false)
						end
					end
				end
				itemInfo = QRCore.Shared.Items[fromItemData.name:lower()]
				AddToDrop(toInventory, toSlot, itemInfo["name"], fromAmount, fromItemData.info)
				if itemInfo["name"] == "radio" then
					TriggerClientEvent('Radio.Set', src, false)
				end
			end
		else
			QRCore.Functions.Notify(src, "Item doesn't exist??", "error")
		end
	end
end)

RegisterNetEvent('qr-inventory:server:SaveStashItems', function(stashId, items)
    MySQL.insert('INSERT INTO stashitems (stash, items) VALUES (:stash, :items) ON DUPLICATE KEY UPDATE items = :items', {
        ['stash'] = stashId,
        ['items'] = json.encode(items)
    })
end)

RegisterServerEvent("inventory:server:GiveItem", function(target, name, amount, slot)
    local src = source
    local Player = QRCore.Functions.GetPlayer(src)
	target = tonumber(target)
    local OtherPlayer = QRCore.Functions.GetPlayer(target)
    local dist = #(GetEntityCoords(GetPlayerPed(src))-GetEntityCoords(GetPlayerPed(target)))
	if Player == OtherPlayer then return QRCore.Functions.Notify(src, Lang:t("notify.gsitem")) end
	if dist > 2 then return QRCore.Functions.Notify(src, Lang:t("notify.tftgitem")) end
	local item = GetItemBySlot(src, slot)
	if not item then QRCore.Functions.Notify(src, Lang:t("notify.infound")); return end
	if item.name ~= name then QRCore.Functions.Notify(src, Lang:t("notify.iifound")); return end

	if amount <= item.amount then
		if amount == 0 then
			amount = item.amount
		end
		if RemoveItem(src, item.name, amount, item.slot) then
			if AddItem(target, item.name, amount, false, item.info) then
				TriggerClientEvent('inventory:client:ItemBox',target, QRCore.Shared.Items[item.name], "add")
				QRCore.Functions.Notify(target, Lang:t("notify.gitemrec")..amount..' '..item.label..Lang:t("notify.gitemfrom")..Player.PlayerData.charinfo.firstname.." "..Player.PlayerData.charinfo.lastname)
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", target, true)
				TriggerClientEvent('inventory:client:ItemBox',src, QRCore.Shared.Items[item.name], "remove")
				QRCore.Functions.Notify(src, Lang:t("notify.gitemyg") .. OtherPlayer.PlayerData.charinfo.firstname.." "..OtherPlayer.PlayerData.charinfo.lastname.. " " .. amount .. " " .. item.label .."!")
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, true)
				TriggerClientEvent('qr-inventory:client:giveAnim', src)
				TriggerClientEvent('qr-inventory:client:giveAnim', target)
			else
				AddItem(src, item.name, amount, item.slot, item.info)
				QRCore.Functions.Notify(src, Lang:t("notify.gitinvfull"), "error")
				QRCore.Functions.Notify(target, Lang:t("notify.giymif"), "error")
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", src, false)
				TriggerClientEvent("inventory:client:UpdatePlayerInventory", target, false)
			end
		else
			QRCore.Functions.Notify(src, Lang:t("notify.gitydhei"), "error")
		end
	else
		QRCore.Functions.Notify(src, Lang:t("notify.gitydhitt"))
	end
end)

--#endregion Events

--#region Callbacks

QRCore.Functions.CreateCallback('qr-inventory:server:GetStashItems', function(_, cb, stashId)
	cb(GetStashItems(stashId))
end)

QRCore.Functions.CreateCallback('inventory:server:GetCurrentDrops', function(_, cb)
	cb(Drops)
end)

QRCore.Functions.CreateCallback('QRCore:HasItem', function(source, cb, items, amount)
	print("^3QRCore:HasItem is deprecated, please use QRCore.Functions.HasItem, it can be used on both server- and client-side and uses the same arguments.^0")
    local retval = false
    local Player = QRCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    local isTable = type(items) == 'table'
    local isArray = isTable and table.type(items) == 'array' or false
    local totalItems = #items
    local count = 0
    local kvIndex = 2
    if isTable and not isArray then
        totalItems = 0
        for _ in pairs(items) do totalItems += 1 end
        kvIndex = 1
    end
    if isTable then
        for k, v in pairs(items) do
            local itemKV = {k, v}
            local item = GetItemByName(source, itemKV[kvIndex])
            if item and ((amount and item.amount >= amount) or (not amount and not isArray and item.amount >= v) or (not amount and isArray)) then
                count += 1
            end
        end
        if count == totalItems then
            retval = true
        end
    else -- Single item as string
        local item = GetItemByName(source, items)
        if item and not amount or (item and amount and item.amount >= amount) then
            retval = true
        end
    end
    cb(retval)
end)

--#endregion Callbacks

--#region Commands

QRCore.Commands.Add("resetinv", "Reset Inventory (Admin Only)", {{name="type", help="stash/trunk/glovebox"},{name="id/plate", help="ID of stash or license plate"}}, true, function(source, args)
	local invType = args[1]:lower()
	table.remove(args, 1)
	local invId = table.concat(args, " ")
	if invType and invId then
		if invType == "trunk" then
			if Trunks[invId] then
				Trunks[invId].isOpen = false
			end
		elseif invType == "glovebox" then
			if Gloveboxes[invId] then
				Gloveboxes[invId].isOpen = false
			end
		elseif invType == "stash" then
			if Stashes[invId] then
				Stashes[invId].isOpen = false
			end
		else
			QRCore.Functions.Notify(source,  Lang:t("notify.navt"), "error")
		end
	else
		QRCore.Functions.Notify(source,  Lang:t("notify.anfoc"), "error")
	end
end, "admin")

QRCore.Commands.Add("rob", "Rob Player", {}, false, function(source, _)
	TriggerClientEvent("police:client:RobPlayer", source)
end)

QRCore.Commands.Add("giveitem", "Give An Item (Admin Only)", {{name="id", help="Player ID"},{name="item", help="Name of the item (not a label)"}, {name="amount", help="Amount of items"}}, false, function(source, args)
	local id = tonumber(args[1])
	local Player = QRCore.Functions.GetPlayer(id)
	local amount = tonumber(args[3]) or 1
	local itemData = QRCore.Shared.Items[tostring(args[2]):lower()]
	if Player then
			if itemData then
				-- check iteminfo
				local info = {}
				if itemData["name"] == "id_card" then
					info.citizenid = Player.PlayerData.citizenid
					info.firstname = Player.PlayerData.charinfo.firstname
					info.lastname = Player.PlayerData.charinfo.lastname
					info.birthdate = Player.PlayerData.charinfo.birthdate
					info.gender = Player.PlayerData.charinfo.gender
					info.nationality = Player.PlayerData.charinfo.nationality
				elseif itemData["type"] == "weapon" then
					amount = 1
					info.serie = tostring(QRCore.Shared.RandomInt(2) .. QRCore.Shared.RandomStr(3) .. QRCore.Shared.RandomInt(1) .. QRCore.Shared.RandomStr(2) .. QRCore.Shared.RandomInt(3) .. QRCore.Shared.RandomStr(4))
					info.quality = 100
				elseif itemData["name"] == "markedbills" then
					info.worth = math.random(5000, 10000)
				end

				if AddItem(id, itemData["name"], amount, false, info) then
					QRCore.Functions.Notify(source, Lang:t("notify.yhg") ..GetPlayerName(id).." "..amount.." "..itemData["name"].. "", "success")
				else
					QRCore.Functions.Notify(source,  Lang:t("notify.cgitem"), "error")
				end
			else
				QRCore.Functions.Notify(source,  Lang:t("notify.idne"), "error")
			end
	else
		QRCore.Functions.Notify(source,  Lang:t("notify.pdne"), "error")
	end
end, "admin")

QRCore.Commands.Add("randomitems", "Give Random Items (God Only)", {}, false, function(source, _)
	local filteredItems = {}
	for k, v in pairs(QRCore.Shared.Items) do
		if QRCore.Shared.Items[k]["type"] ~= "weapon" then
			filteredItems[#filteredItems+1] = v
		end
	end
	for _ = 1, 10, 1 do
		local randitem = filteredItems[math.random(1, #filteredItems)]
		local amount = math.random(1, 10)
		if randitem["unique"] then
			amount = 1
		end
		if AddItem(source, randitem["name"], amount) then
			TriggerClientEvent('inventory:client:ItemBox', source, QRCore.Shared.Items[randitem["name"]], 'add')
            Wait(500)
		end
	end
end, "god")

QRCore.Commands.Add('clearinv', 'Clear Players Inventory (Admin Only)', { { name = 'id', help = 'Player ID' } }, false, function(source, args)
    local playerId = args[1] ~= '' and tonumber(args[1]) or source
    local Player = QRCore.Functions.GetPlayer(playerId)
    if Player then
        ClearInventory(playerId)
    else
        QRCore.Functions.Notify(source, "Player not online", 'error')
    end
end, 'admin')

--#endregion Commands

--#region Items

CreateUsableItem("id_card", function(source, item)
	local playerPed = GetPlayerPed(source)
	local playerCoords = GetEntityCoords(playerPed)
	local players = QRCore.Functions.GetPlayers()
	for _, v in pairs(players) do
		local targetPed = GetPlayerPed(v)
		local dist = #(playerCoords - GetEntityCoords(targetPed))
		if dist < 3.0 then
			local gender = "Man"
			if item.info.gender == 1 then
				gender = "Woman"
			end
			TriggerClientEvent('chat:addMessage', v,  {
					template = '<div class="chat-message advert"><div class="chat-message-body"><strong>{0}:</strong><br><br> <strong>Civ ID:</strong> {1} <br><strong>First Name:</strong> {2} <br><strong>Last Name:</strong> {3} <br><strong>Birthdate:</strong> {4} <br><strong>Gender:</strong> {5} <br><strong>Nationality:</strong> {6}</div></div>',
					args = {
						"ID Card",
						item.info.citizenid,
						item.info.firstname,
						item.info.lastname,
						item.info.birthdate,
						gender,
						item.info.nationality
					}
				}
			)
		end
	end
end)

--#endregion Items

--#region Threads

CreateThread(function()
	while true do
		for k, v in pairs(Drops) do
			if v and (v.createdTime + Config.CleanupDropTime < os.time()) and not Drops[k].isOpen then
				Drops[k] = nil
				TriggerClientEvent("inventory:client:RemoveDropItem", -1, k)
			end
		end
		Wait(60 * 1000)
	end
end)

--#endregion Threads
