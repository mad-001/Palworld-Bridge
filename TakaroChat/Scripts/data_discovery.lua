-- Data Discovery Module - Logs all available Palworld data structures
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local DataDiscovery = {}

-- Recursively dump object properties and methods
local function DumpObject(obj, name, depth, maxDepth, visited)
    depth = depth or 0
    maxDepth = maxDepth or 3
    visited = visited or {}

    if depth > maxDepth then
        return string.format("%s... (max depth reached)", string.rep("  ", depth))
    end

    -- Prevent infinite recursion
    if visited[obj] then
        return string.format("%s... (circular reference)", string.rep("  ", depth))
    end
    visited[obj] = true

    local indent = string.rep("  ", depth)
    local result = {}

    table.insert(result, string.format("%s%s:", indent, name))

    -- Try to get object type
    local success, objType = pcall(function()
        if obj.GetFullName then
            return obj:GetFullName()
        elseif obj.GetClass then
            return obj:GetClass():GetFullName()
        end
        return type(obj)
    end)

    if success and objType then
        table.insert(result, string.format("%s  Type: %s", indent, objType))
    end

    -- Try to enumerate properties
    local propSuccess, propErr = pcall(function()
        -- Check if it's a UObject
        if obj.IsValid and type(obj.IsValid) == "function" then
            local isValid = obj:IsValid()
            table.insert(result, string.format("%s  IsValid: %s", indent, tostring(isValid)))

            if isValid then
                -- Try common properties
                local commonProps = {
                    "PlayerState", "PawnPrivate", "Pawn", "PlayerController",
                    "CharacterMovement", "CharacterParameterComponent",
                    "InventoryComponent", "PlayerNamePrivate", "PlayerUId",
                    "Location", "Rotation", "Controller", "Owner",
                    "HP", "MaxHP", "Level", "Experience"
                }

                for _, prop in ipairs(commonProps) do
                    local propSuccess, propVal = pcall(function()
                        return obj[prop]
                    end)

                    if propSuccess and propVal ~= nil then
                        if type(propVal) == "userdata" then
                            table.insert(result, string.format("%s  %s: <userdata>", indent, prop))
                        elseif type(propVal) == "table" then
                            table.insert(result, string.format("%s  %s: <table>", indent, prop))
                        else
                            table.insert(result, string.format("%s  %s: %s", indent, prop, tostring(propVal)))
                        end
                    end
                end
            end
        end
    end)

    return table.concat(result, "\n")
end

-- Log all player data
function DataDiscovery.LogPlayerData(player, playerName)
    logger:log(2, "=== PLAYER DATA DISCOVERY: " .. playerName .. " ===")

    if not player or not player:IsValid() then
        logger:log(1, "Player object is invalid")
        return
    end

    -- Log player object
    logger:log(2, DumpObject(player, "PalPlayerCharacter", 0, 2))

    -- Log PlayerState
    local success, playerState = pcall(function()
        return player.PlayerState
    end)

    if success and playerState and playerState:IsValid() then
        logger:log(2, "\n=== PlayerState ===")
        logger:log(2, DumpObject(playerState, "PlayerState", 0, 2))

        -- Try to get more PlayerState properties
        local stateProps = {
            "PlayerNamePrivate", "PlayerName", "PlayerUId", "PlayerId",
            "Pawn", "PawnPrivate", "Score", "Ping", "StartTime",
            "bIsABot", "bOnlySpectator", "SavedNetworkAddress"
        }

        for _, prop in ipairs(stateProps) do
            local propSuccess, propVal = pcall(function()
                return playerState[prop]
            end)

            if propSuccess and propVal ~= nil then
                if type(propVal) == "userdata" and propVal.ToString then
                    local strSuccess, strVal = pcall(function()
                        return propVal:ToString()
                    end)
                    if strSuccess then
                        logger:log(2, string.format("  PlayerState.%s: %s", prop, strVal))
                    end
                else
                    logger:log(2, string.format("  PlayerState.%s: %s (%s)", prop, tostring(propVal), type(propVal)))
                end
            end
        end
    end

    -- Try K2_GetActorLocation
    local locSuccess, location = pcall(function()
        return player:K2_GetActorLocation()
    end)

    if locSuccess and location then
        logger:log(2, string.format("\nLocation: X=%.2f, Y=%.2f, Z=%.2f",
            location.X or 0, location.Y or 0, location.Z or 0))
    end

    -- Try K2_GetActorRotation
    local rotSuccess, rotation = pcall(function()
        return player:K2_GetActorRotation()
    end)

    if rotSuccess and rotation then
        logger:log(2, string.format("Rotation: Pitch=%.2f, Yaw=%.2f, Roll=%.2f",
            rotation.Pitch or 0, rotation.Yaw or 0, rotation.Roll or 0))
    end

    -- Try to get CharacterParameterComponent
    local charSuccess, charParam = pcall(function()
        return player.CharacterParameterComponent
    end)

    if charSuccess and charParam and charParam:IsValid() then
        logger:log(2, "\n=== CharacterParameterComponent ===")

        -- Try to get HP and other stats
        local statsSuccess, stats = pcall(function()
            local hp = charParam:GetHP()
            local maxHp = charParam:GetMaxHP()
            local level = charParam.Level or "N/A"

            return string.format("  HP: %s/%s, Level: %s",
                tostring(hp), tostring(maxHp), tostring(level))
        end)

        if statsSuccess then
            logger:log(2, stats)
        end
    end

    logger:log(2, "=== END PLAYER DATA ===\n")
end

-- Log all online players
function DataDiscovery.LogAllPlayers()
    logger:log(2, "\n========================================")
    logger:log(2, "DISCOVERING ALL PALWORLD PLAYER DATA")
    logger:log(2, "========================================\n")

    local success, err = pcall(function()
        local players = FindAllOf("PalPlayerCharacter")
        if not players then
            logger:log(1, "No players found (FindAllOf returned nil)")
            return
        end

        logger:log(2, string.format("Found %d players online\n", #players))

        for i, player in ipairs(players) do
            if player and player:IsValid() then
                local playerState = player.PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState.PlayerNamePrivate:ToString()
                    DataDiscovery.LogPlayerData(player, playerName)
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error during data discovery: " .. tostring(err))
    end

    logger:log(2, "========================================")
    logger:log(2, "DATA DISCOVERY COMPLETE")
    logger:log(2, "========================================\n")
end

-- Initialize discovery module
function DataDiscovery.Initialize()
    logger:log(2, "Data Discovery Module initialized")

    -- Log all player data every 60 seconds
    LoopAsync(60000, function()
        DataDiscovery.LogAllPlayers()
        return false
    end)

    logger:log(2, "Data discovery will run every 60 seconds")
end

return DataDiscovery
