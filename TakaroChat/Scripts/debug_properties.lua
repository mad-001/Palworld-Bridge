-- Debug script to discover UE4 object properties
-- Run this to find correct property names for inventory and guilds

local Utils = require("utils")
local logger = Utils.Logger:new()

local Debug = {}

-- Helper to safely get property names
local function GetPropertyNames(object, objectName)
    if not object or not object:IsValid() then
        logger:log(1, string.format("[DEBUG] %s is invalid", objectName))
        return
    end

    logger:log(2, string.format("[DEBUG] === %s Properties ===", objectName))

    -- Try to iterate properties (method varies by UE4SS version)
    local success, err = pcall(function()
        local props = object:GetProperties()
        if props then
            for i, prop in ipairs(props) do
                logger:log(2, string.format("[DEBUG]   [%d] %s", i, tostring(prop)))
            end
        end
    end)

    if not success then
        logger:log(1, string.format("[DEBUG] Could not iterate properties: %s", tostring(err)))
    end
end

-- Discover GameState properties
local function DiscoverGameState()
    local GameState = FindFirstOf("PalGameStateInGame")
    if GameState then
        GetPropertyNames(GameState, "PalGameStateInGame")

        -- Try to find guild manager
        logger:log(2, "[DEBUG] Attempting to find GuildManager...")
        local possibleNames = {"GroupGuildManager", "GuildManager", "GroupManager", "GuildSystem"}
        for _, name in ipairs(possibleNames) do
            local success, manager = pcall(function() return GameState[name] end)
            if success and manager then
                logger:log(2, string.format("[DEBUG] Found: %s = %s", name, tostring(manager)))
                if manager:IsValid() then
                    GetPropertyNames(manager, name)
                end
            end
        end
    else
        logger:log(1, "[DEBUG] Could not find PalGameStateInGame")
    end
end

-- Discover PlayerState/Inventory properties
local function DiscoverPlayerInventory()
    local players = FindAllOf("PalPlayerCharacter")
    if not players or #players == 0 then
        logger:log(1, "[DEBUG] No players found")
        return
    end

    local player = players[1]
    if player and player:IsValid() then
        logger:log(2, "[DEBUG] === Player Character ===")
        GetPropertyNames(player, "PalPlayerCharacter")

        local playerState = player.PlayerState
        if playerState and playerState:IsValid() then
            logger:log(2, "[DEBUG] === Player State ===")
            GetPropertyNames(playerState, "PlayerState")

            -- Try to find inventory
            logger:log(2, "[DEBUG] Attempting to find Inventory...")
            local invNames = {"InventoryData", "Inventory", "InventoryComponent", "PlayerInventory"}
            for _, name in ipairs(invNames) do
                local success, inv = pcall(function() return playerState[name] end)
                if success and inv then
                    logger:log(2, string.format("[DEBUG] Found: %s = %s", name, tostring(inv)))
                    if type(inv.IsValid) == "function" and inv:IsValid() then
                        GetPropertyNames(inv, name)
                    end
                end
            end

            -- Try GetInventoryData() method
            local methodSuccess, invData = pcall(function() return playerState:GetInventoryData() end)
            if methodSuccess and invData then
                logger:log(2, string.format("[DEBUG] GetInventoryData() returned: %s", tostring(invData)))
                if invData:IsValid() then
                    GetPropertyNames(invData, "InventoryData (from method)")
                end
            end
        end
    end
end

-- Run discovery
function Debug.RunDiscovery()
    logger:log(2, "[DEBUG] ===== STARTING PROPERTY DISCOVERY =====")

    DiscoverGameState()
    logger:log(2, "[DEBUG] ---")
    DiscoverPlayerInventory()

    logger:log(2, "[DEBUG] ===== DISCOVERY COMPLETE =====")
    logger:log(2, "[DEBUG] Check UE4SS.log for full output")
end

return Debug
