-- Inventory tracking module
-- Fixed to use PlayerState:GetInventoryData() instead of InventoryComponent

local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Inventory = {}

-- Send inventory data to bridge
local function SendInventoryToBridge(playerName, inventoryData)
    if not config.EnableBridge then
        return
    end

    local bridgeHost = config.BridgeURL:match("http://([^/]+)")
    if not bridgeHost then
        logger:log(1, "[INVENTORY] Could not extract bridge host from URL")
        return
    end

    local json = string.format(
        '{"type":"inventory","playerName":"%s","timestamp":"%s","inventory":%s}',
        Utils.EscapeJSON(playerName),
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        inventoryData
    )

    local jsonEscaped = json:gsub('"', '\\"')
    local curlCommand = string.format(
        'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/chat',
        jsonEscaped,
        bridgeHost
    )

    -- Execute synchronously
    local handle = io.popen(curlCommand .. ' 2>&1')
    if handle then
        local result = handle:read("*a")
        local success = handle:close()

        if success and result:match('"success"%s*:%s*true') then
            logger:log(3, string.format("[INVENTORY] Sent inventory for: %s", playerName))
        else
            logger:log(1, string.format("[INVENTORY] Failed to send for %s: %s", playerName, result))
        end
    end
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
                local playerState = player.PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState.PlayerNamePrivate:ToString()

                    -- Discover PlayerState properties
                    local PlayerStateClass = playerState:GetClass()
                    if PlayerStateClass and PlayerStateClass:IsValid() then
                        PlayerStateClass:ForEachProperty(function(Property)
                            local propName = Property:GetFName():ToString()
                            if propName:lower():find("inventory") then
                                logger:log(3, string.format("[INVENTORY] Found inventory-related property on PlayerState: %s (type: %s)",
                                    propName, Property:GetClass():GetFName():ToString()))
                            end
                        end)
                    end

                    -- Try to get inventory data
                    local inventoryData = nil
                    local invSuccess, invResult = pcall(function() return playerState:GetInventoryData() end)
                    if invSuccess and invResult and invResult:IsValid() then
                        inventoryData = invResult
                        logger:log(3, string.format("[INVENTORY] Got inventory data for %s via GetInventoryData()", playerName))
                    else
                        -- Try direct property access as fallback
                        local propSuccess, propResult = pcall(function() return playerState.InventoryData end)
                        if propSuccess and propResult and propResult:IsValid() then
                            inventoryData = propResult
                            logger:log(3, string.format("[INVENTORY] Got inventory data for %s via InventoryData property", playerName))
                        end
                    end

                    if inventoryData and inventoryData:IsValid() then
                        local items = {}

                        -- Discover inventory data structure
                        local InventoryDataClass = inventoryData:GetClass()
                        if InventoryDataClass and InventoryDataClass:IsValid() then
                            logger:log(3, string.format("[INVENTORY] Discovering InventoryData properties for %s...", playerName))
                            InventoryDataClass:ForEachProperty(function(Property)
                                local propName = Property:GetFName():ToString()
                                logger:log(3, string.format("[INVENTORY] InventoryData property: %s (type: %s)",
                                    propName, Property:GetClass():GetFName():ToString()))
                            end)
                        end

                        -- Access inventory containers
                        local containers = nil
                        local contSuccess, contResult = pcall(function() return inventoryData.InventoryMultiHelper.Containers end)
                        if contSuccess and contResult then
                            containers = contResult
                        else
                            -- Try alternative paths
                            local altSuccess, altResult = pcall(function() return inventoryData.Containers end)
                            if altSuccess and altResult then
                                containers = altResult
                            end
                        end

                        if containers then
                            -- Iterate through containers (0 = main inventory, 1+ = other slots)
                            for containerIdx = 0, 10 do
                                local containerSuccess, container = pcall(function() return containers[containerIdx] end)
                                if containerSuccess and container then
                                    -- Iterate through slots in this container
                                    for slotIdx = 0, 50 do
                                        local slotSuccess, slot = pcall(function() return container:Get(slotIdx) end)
                                        if slotSuccess and slot then
                                            local itemId = slot:GetItemId()
                                            local stackCount = slot:GetStackCount()

                                            if itemId and stackCount and stackCount > 0 then
                                                local itemIdStr = tostring(itemId.StaticId:ToString())
                                                table.insert(items, string.format(
                                                    '{"id":"%s","count":%d,"container":%d,"slot":%d}',
                                                    itemIdStr,
                                                    stackCount,
                                                    containerIdx,
                                                    slotIdx
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
        logger:log(1, "[INVENTORY] Error updating inventories: " .. tostring(err))
    end
end

-- Initialize inventory tracking
function Inventory.Initialize()
    if not config.EnableInventoryTracking then
        logger:log(2, "[INVENTORY] Inventory tracking is disabled in config")
        return
    end

    logger:log(2, "[INVENTORY] Starting inventory tracking (using PlayerState:GetInventoryData)...")

    LoopAsync(config.InventoryUpdateInterval * 1000, function()
        UpdatePlayerInventories()
        return false
    end)

    logger:log(2, string.format("[INVENTORY] Inventory tracking started (every %ds)", config.InventoryUpdateInterval))
end

return Inventory
