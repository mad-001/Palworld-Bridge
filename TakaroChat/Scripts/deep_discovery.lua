-- Deep property discovery for inventory and guild data
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local DeepDiscovery = {}

-- Helper to safely enumerate properties with :get() support
local function DeepEnumerate(obj, path, useGet)
    if not obj then
        logger:log(2, string.format("%s: nil", path))
        return
    end

    -- Try :get() if requested
    local targetObj = obj
    if useGet then
        local getSuccess, getResult = pcall(function()
            return obj:get()
        end)
        if getSuccess and getResult then
            logger:log(2, string.format("%s:get() SUCCESS", path))
            targetObj = getResult
        else
            logger:log(1, string.format("%s:get() FAILED: %s", path, tostring(getResult)))
            return
        end
    end

    -- Check IsValid
    local validSuccess, isValid = pcall(function()
        return targetObj:IsValid()
    end)
    logger:log(2, string.format("%s IsValid: %s", path, tostring(isValid)))

    -- Enumerate properties regardless of IsValid
    logger:log(2, string.format("\n=== PROPERTIES OF %s ===", path))
    local propCount = 0

    local enumSuccess = pcall(function()
        if targetObj.type then
            local objType = targetObj:type()
            if objType and objType.ForEachProperty then
                objType:ForEachProperty(function(property)
                    local nameSuccess, propName = pcall(function()
                        if property and property.GetName then
                            return property:GetName()
                        end
                        return nil
                    end)

                    if nameSuccess and propName then
                        propCount = propCount + 1

                        -- Try to get the property value
                        local valSuccess, propVal = pcall(function()
                            return targetObj[propName]
                        end)

                        if valSuccess and propVal ~= nil then
                            local valType = type(propVal)
                            if valType == "userdata" then
                                -- Check if it's valid
                                local subValid = pcall(function()
                                    return propVal:IsValid()
                                end)
                                logger:log(2, string.format("  %s: userdata (IsValid: %s)", propName, tostring(subValid)))
                            else
                                logger:log(2, string.format("  %s: %s (%s)", propName, tostring(propVal), valType))
                            end
                        else
                            logger:log(2, string.format("  %s: <access failed>", propName))
                        end
                    end
                end)
            end
        end
    end)

    logger:log(2, string.format("Total properties found: %d\n", propCount))
    return targetObj
end

-- Discover inventory chain
local function DiscoverInventory(player, playerName)
    logger:log(2, "\n" .. string.rep("=", 60))
    logger:log(2, "INVENTORY DISCOVERY: " .. playerName)
    logger:log(2, string.rep("=", 60))

    -- Level 1: InventoryComponent
    local invSuccess, invComponent = pcall(function()
        return player.InventoryComponent
    end)

    if not invSuccess or not invComponent then
        logger:log(1, "Cannot access InventoryComponent")
        return
    end

    logger:log(2, "\n--- LEVEL 1: InventoryComponent ---")
    DeepEnumerate(invComponent, "InventoryComponent", false)

    -- Level 2: InventoryComponent:get()
    logger:log(2, "\n--- LEVEL 2: InventoryComponent:get() ---")
    local invObj = DeepEnumerate(invComponent, "InventoryComponent", true)
    if not invObj then return end

    -- Level 3: Try to access Container
    logger:log(2, "\n--- LEVEL 3: Container ---")
    local containerSuccess, container = pcall(function()
        return invObj.Container
    end)

    if containerSuccess and container then
        logger:log(2, "Container accessed successfully!")
        DeepEnumerate(container, "Container", false)

        -- Level 4: Container:get()
        logger:log(2, "\n--- LEVEL 4: Container:get() ---")
        local containerObj = DeepEnumerate(container, "Container", true)
        if not containerObj then return end

        -- Level 5: Try to access Slots
        logger:log(2, "\n--- LEVEL 5: Slots ---")
        local slotsSuccess, slots = pcall(function()
            return containerObj.Slots
        end)

        if slotsSuccess and slots then
            logger:log(2, "Slots accessed successfully!")
            logger:log(2, string.format("Slots type: %s", type(slots)))

            -- Try to iterate slots
            for i = 0, 10 do -- Just check first 10 slots
                local slotSuccess, slot = pcall(function()
                    return slots[i]
                end)

                if slotSuccess and slot then
                    logger:log(2, string.format("\n--- SLOT %d ---", i))
                    DeepEnumerate(slot, string.format("Slot[%d]", i), false)

                    -- Try slot:get()
                    local slotObj = DeepEnumerate(slot, string.format("Slot[%d]", i), true)
                    if slotObj then
                        -- Try to access ItemData
                        local itemSuccess, itemData = pcall(function()
                            return slotObj.ItemData
                        end)

                        if itemSuccess and itemData then
                            logger:log(2, string.format("\n--- SLOT %d ITEMDATA ---", i))
                            DeepEnumerate(itemData, string.format("Slot[%d].ItemData", i), false)
                            DeepEnumerate(itemData, string.format("Slot[%d].ItemData", i), true)
                        end
                    end
                end
            end
        else
            logger:log(1, "Cannot access Slots")
        end
    else
        logger:log(1, "Cannot access Container")
    end
end

-- Discover guild information
local function DiscoverGuild(player, playerState, playerName)
    logger:log(2, "\n" .. string.rep("=", 60))
    logger:log(2, "GUILD DISCOVERY: " .. playerName)
    logger:log(2, string.rep("=", 60))

    -- Check player for guild properties
    logger:log(2, "\n--- Searching Player for Guild Data ---")
    local guildProps = {
        "Guild", "GuildComponent", "GuildInfo", "GuildData", "GuildId", "GuildName",
        "TeamId", "Team", "TeamComponent", "Faction", "FactionId", "Organization",
        "Group", "GroupId", "Party", "PartyId"
    }

    for _, prop in ipairs(guildProps) do
        local success, val = pcall(function()
            return player[prop]
        end)
        if success and val ~= nil then
            logger:log(2, string.format("Player.%s: %s (type: %s)", prop, tostring(val), type(val)))
            if type(val) == "userdata" then
                DeepEnumerate(val, "Player." .. prop, false)
                DeepEnumerate(val, "Player." .. prop, true)
            end
        end
    end

    -- Check PlayerState for guild properties
    if playerState and playerState:IsValid() then
        logger:log(2, "\n--- Searching PlayerState for Guild Data ---")
        for _, prop in ipairs(guildProps) do
            local success, val = pcall(function()
                return playerState[prop]
            end)
            if success and val ~= nil then
                logger:log(2, string.format("PlayerState.%s: %s (type: %s)", prop, tostring(val), type(val)))
                if type(val) == "userdata" then
                    DeepEnumerate(val, "PlayerState." .. prop, false)
                    DeepEnumerate(val, "PlayerState." .. prop, true)
                end
            end
        end

        -- Try PlayerState:get()
        logger:log(2, "\n--- PlayerState:get() Properties ---")
        local stateObj = DeepEnumerate(playerState, "PlayerState", true)
        if stateObj then
            for _, prop in ipairs(guildProps) do
                local success, val = pcall(function()
                    return stateObj[prop]
                end)
                if success and val ~= nil then
                    logger:log(2, string.format("PlayerState:get().%s: %s (type: %s)", prop, tostring(val), type(val)))
                end
            end
        end
    end
end

-- Main discovery function
local function DiscoverAll()
    logger:log(2, "\n" .. string.rep("=", 70))
    logger:log(2, "DEEP PROPERTY DISCOVERY - INVENTORY & GUILD")
    logger:log(2, string.rep("=", 70))

    local success, err = pcall(function()
        local players = FindAllOf("PalPlayerCharacter")
        if not players then
            logger:log(1, "No players found")
            return
        end

        logger:log(2, string.format("\nFound %d players online\n", #players))

        for _, player in ipairs(players) do
            if player and player:IsValid() then
                local playerState = player.PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState.PlayerNamePrivate:ToString()

                    -- Discover inventory
                    DiscoverInventory(player, playerName)

                    -- Discover guild
                    DiscoverGuild(player, playerState, playerName)

                    -- Only do first player for now
                    break
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Discovery error: " .. tostring(err))
    end

    logger:log(2, "\n" .. string.rep("=", 70))
    logger:log(2, "DISCOVERY COMPLETE")
    logger:log(2, string.rep("=", 70))
end

-- Initialize deep discovery system
function DeepDiscovery.Initialize()
    logger:log(2, "Initializing deep discovery system...")

    -- Run discovery every 60 seconds
    LoopAsync(60000, function()
        DiscoverAll()
        return false
    end)

    logger:log(2, "Deep discovery system initialized (runs every 60s)")
end

return DeepDiscovery
