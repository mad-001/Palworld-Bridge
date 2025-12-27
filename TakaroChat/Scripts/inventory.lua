-- Inventory tracking module
-- WARNING: DISABLED BY DEFAULT - causes crashes and validation issues
-- To enable: Uncomment require("inventory") in main.lua AND set config.EnableInventoryTracking = true

local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Inventory = {}

-- Send inventory data to bridge
local function SendInventoryToBridge(playerName, inventoryData)
    if not config.EnableBridge then
        return
    end

    local json = string.format(
        '{"type":"inventory","playerName":"%s","timestamp":"%s","inventory":%s}',
        Utils.EscapeJSON(playerName),
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        inventoryData
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute('start /B "" ' .. command .. ' >nul 2>&1')
    logger:log(3, string.format("Sent inventory for: %s", playerName))
end

-- Get player inventory and send to bridge
local function UpdatePlayerInventories()
    local success, err = pcall(function()
        local players = FindAllOf("PalPlayerCharacter")
        if not players then
            return
        end

        for _, player in ipairs(players) do
            if player and player:IsValid() then
                local playerState = player:get().PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState:get().PlayerNamePrivate:ToString()

                    -- Try to get inventory container
                    local inventoryComponent = player:get().InventoryComponent
                    if inventoryComponent and inventoryComponent:IsValid() then
                        local items = {}
                        local container = inventoryComponent:get().Container

                        if container and container:IsValid() then
                            -- Iterate through inventory slots
                            local slots = container:get().Slots
                            if slots then
                                for i = 0, 50 do -- Max 50 slots
                                    local success2, slot = pcall(function() return slots[i] end)
                                    if success2 and slot and slot:IsValid() then
                                        local itemData = slot:get().ItemData
                                        if itemData and itemData:IsValid() then
                                            local staticId = itemData:get().ItemStaticId
                                            local count = itemData:get().Count

                                            if staticId and count and count > 0 then
                                                table.insert(items, string.format(
                                                    '{"id":"%s","count":%d,"slot":%d}',
                                                    tostring(staticId),
                                                    count,
                                                    i
                                                ))
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        local inventoryJson = "[" .. table.concat(items, ",") .. "]"
                        SendInventoryToBridge(playerName, inventoryJson)
                    end
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error updating inventories: " .. tostring(err))
    end
end

-- Initialize inventory tracking
function Inventory.Initialize()
    if not config.EnableInventoryTracking then
        logger:log(1, "Inventory tracking is DISABLED (known to cause crashes)")
        return
    end

    logger:log(2, "Starting inventory tracking...")

    LoopAsync(config.InventoryUpdateInterval * 1000, function()
        UpdatePlayerInventories()
        return false
    end)

    logger:log(2, string.format("Inventory tracking started (every %ds)", config.InventoryUpdateInterval))
end

return Inventory
