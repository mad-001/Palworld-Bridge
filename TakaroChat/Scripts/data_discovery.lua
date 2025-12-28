-- Data Discovery Module - Comprehensive Palworld data structure analysis using UE4SS APIs
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local DataDiscovery = {}

-- Track discovered object classes
local discoveredClasses = {}

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

-- Use UE4SS Reflection API to enumerate all properties of an object
local function EnumerateProperties(obj, objName)
    logger:log(2, string.format("\n=== PROPERTIES OF %s ===", objName))

    local success, err = pcall(function()
        if not obj or not obj:IsValid() then
            logger:log(1, "Object is invalid for property enumeration")
            return
        end

        -- Get the class
        local class = obj:GetClass()
        if not class then
            logger:log(1, "Cannot get class for object")
            return
        end

        logger:log(2, "Class: " .. tostring(class:GetFullName()))

        -- Enumerate properties using ForEachProperty
        local propCount = 0
        class:ForEachProperty(function(property)
            propCount = propCount + 1

            -- Safely get property name and type
            local nameSuccess, propName = pcall(function()
                if property and property.GetName then
                    return property:GetName()
                end
                return tostring(property)
            end)

            local typeSuccess, propType = pcall(function()
                if property and property.GetClass then
                    local propClass = property:GetClass()
                    if propClass and propClass.GetName then
                        return propClass:GetName()
                    end
                end
                return "Unknown"
            end)

            if nameSuccess and propName then
                logger:log(2, string.format("  [%d] %s (%s)", propCount, propName, typeSuccess and propType or "Unknown"))

                -- Try to get the property value
                local valSuccess, propVal = pcall(function()
                    return obj[propName]
                end)

                if valSuccess and propVal ~= nil then
                    if type(propVal) == "userdata" then
                        local strSuccess, strVal = pcall(function()
                            if propVal.ToString then
                                return propVal:ToString()
                            elseif propVal.GetFullName then
                                return propVal:GetFullName()
                            end
                            return "<userdata>"
                        end)
                        if strSuccess then
                            logger:log(2, string.format("      Value: %s", strVal))
                        end
                    else
                        logger:log(2, string.format("      Value: %s", tostring(propVal)))
                    end
                end
            end
        end)

        logger:log(2, string.format("Total properties found: %d", propCount))
    end)

    if not success then
        logger:log(1, "Error enumerating properties: " .. tostring(err))
    end
end

-- Use UE4SS ForEachFunction to enumerate all methods of an object
local function EnumerateFunctions(obj, objName)
    logger:log(2, string.format("\n=== FUNCTIONS OF %s ===", objName))

    local success, err = pcall(function()
        if not obj or not obj:IsValid() then
            logger:log(1, "Object is invalid for function enumeration")
            return
        end

        -- Get the class
        local class = obj:GetClass()
        if not class then
            logger:log(1, "Cannot get class for object")
            return
        end

        -- Enumerate functions using ForEachFunction
        local funcCount = 0
        class:ForEachFunction(function(func)
            -- Safely get function name and details
            local nameSuccess, funcName = pcall(function()
                if func and func.GetName then
                    return func:GetName()
                end
                return nil
            end)

            local fullNameSuccess, funcFullName = pcall(function()
                if func and func.GetFullName then
                    return func:GetFullName()
                end
                return nil
            end)

            if nameSuccess and funcName then
                funcCount = funcCount + 1
                logger:log(2, string.format("  [%d] %s", funcCount, funcName))
                if fullNameSuccess and funcFullName then
                    logger:log(2, string.format("      Full: %s", funcFullName))
                end
            end
        end)

        logger:log(2, string.format("Total functions found: %d", funcCount))
    end)

    if not success then
        logger:log(1, "Error enumerating functions: " .. tostring(err))
    end
end

-- Use UE4SS Reflection API to get detailed object information
local function ReflectObject(obj, objName)
    logger:log(2, string.format("\n=== REFLECTION DATA FOR %s ===", objName))

    local success, err = pcall(function()
        if not obj or not obj:IsValid() then
            logger:log(1, "Object is invalid for reflection")
            return
        end

        -- Use Reflection API
        local reflection = obj:Reflection()
        if reflection then
            logger:log(2, "Reflection data available:")

            -- Try to access reflection properties
            for key, value in pairs(reflection) do
                logger:log(2, string.format("  %s: %s (%s)", tostring(key), tostring(value), type(value)))
            end
        else
            logger:log(1, "No reflection data available")
        end
    end)

    if not success then
        logger:log(1, "Error reflecting object: " .. tostring(err))
    end
end

-- Discover all loaded UObjects of interest
function DataDiscovery.DiscoverLoadedObjects()
    logger:log(2, "\n========================================")
    logger:log(2, "DISCOVERING ALL LOADED PALWORLD OBJECTS")
    logger:log(2, "========================================\n")

    local classCount = {}
    local totalObjects = 0

    local success, err = pcall(function()
        -- Use ForEachUObject to iterate all loaded objects
        ForEachUObject(function(obj)
            totalObjects = totalObjects + 1

            local objSuccess, className = pcall(function()
                local class = obj:GetClass()
                if class then
                    return class:GetName()
                end
                return "Unknown"
            end)

            if objSuccess and className then
                classCount[className] = (classCount[className] or 0) + 1
            end
        end)

        -- Log the discovered classes
        logger:log(2, string.format("Total objects scanned: %d", totalObjects))
        logger:log(2, "\nObject classes found:")

        -- Sort classes by count
        local sortedClasses = {}
        for className, count in pairs(classCount) do
            table.insert(sortedClasses, {name = className, count = count})
        end

        table.sort(sortedClasses, function(a, b) return a.count > b.count end)

        -- Log top 50 most common classes
        for i = 1, math.min(50, #sortedClasses) do
            local entry = sortedClasses[i]
            logger:log(2, string.format("  [%d] %s: %d instances", i, entry.name, entry.count))

            -- Track interesting classes
            if string.find(entry.name, "Pal") or string.find(entry.name, "Player") or
               string.find(entry.name, "Character") or string.find(entry.name, "Inventory") then
                discoveredClasses[entry.name] = true
            end
        end
    end)

    if not success then
        logger:log(1, "Error discovering objects: " .. tostring(err))
    end

    logger:log(2, "\n========================================")
    logger:log(2, "OBJECT DISCOVERY COMPLETE")
    logger:log(2, "========================================\n")
end

-- Log all player data
function DataDiscovery.LogPlayerData(player, playerName)
    logger:log(2, "=== PLAYER DATA DISCOVERY: " .. playerName .. " ===")

    if not player or not player:IsValid() then
        logger:log(1, "Player object is invalid")
        return
    end

    -- Log player object (basic dump)
    logger:log(2, DumpObject(player, "PalPlayerCharacter", 0, 2))

    -- GET LOCATION/ROTATION FIRST (before any crashes)
    logger:log(2, "\n=== LOCATION & ROTATION ===")
    local locSuccess, location = pcall(function()
        return player:K2_GetActorLocation()
    end)
    if locSuccess and location then
        logger:log(2, string.format("Location: X=%.2f, Y=%.2f, Z=%.2f", location.X or 0, location.Y or 0, location.Z or 0))
    else
        logger:log(1, "Failed to get location")
    end

    local rotSuccess, rotation = pcall(function()
        return player:K2_GetActorRotation()
    end)
    if rotSuccess and rotation then
        logger:log(2, string.format("Rotation: Pitch=%.2f, Yaw=%.2f, Roll=%.2f", rotation.Pitch or 0, rotation.Yaw or 0, rotation.Roll or 0))
    else
        logger:log(1, "Failed to get rotation")
    end

    -- GET HP/LEVEL DATA EARLY
    logger:log(2, "\n=== STATS ===")
    local charSuccess, charParam = pcall(function()
        return player.CharacterParameterComponent
    end)
    if charSuccess and charParam and charParam:IsValid() then
        local hpSuccess, hp = pcall(function() return charParam:GetHP() end)
        local maxHpSuccess, maxHp = pcall(function() return charParam:GetMaxHP() end)

        if hpSuccess and hp then
            logger:log(2, string.format("HP: %s", tostring(hp)))
        end
        if maxHpSuccess and maxHp then
            logger:log(2, string.format("MaxHP: %s", tostring(maxHp)))
        end

        -- Try to get level
        local levelSuccess, level = pcall(function() return charParam.Level end)
        if levelSuccess and level then
            logger:log(2, string.format("Level: %s", tostring(level)))
        end
    else
        logger:log(1, "CharacterParameterComponent not accessible")
    end

    -- Use UE4SS API to enumerate all properties
    EnumerateProperties(player, playerName .. " (PalPlayerCharacter)")

    -- Use UE4SS API to enumerate all functions
    EnumerateFunctions(player, playerName .. " (PalPlayerCharacter)")

    -- Use Reflection API
    ReflectObject(player, playerName .. " (PalPlayerCharacter)")

    -- Log PlayerState
    local success, playerState = pcall(function()
        return player.PlayerState
    end)

    if success and playerState and playerState:IsValid() then
        logger:log(2, "\n=== PlayerState ===")
        logger:log(2, DumpObject(playerState, "PlayerState", 0, 2))

        -- Use UE4SS API to enumerate PlayerState properties
        EnumerateProperties(playerState, playerName .. " (PlayerState)")

        -- Use UE4SS API to enumerate PlayerState functions
        EnumerateFunctions(playerState, playerName .. " (PlayerState)")

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
                -- Wrap ToString in its own pcall to prevent crashes
                if type(propVal) == "userdata" then
                    local strSuccess, strVal = pcall(function()
                        if propVal.ToString then
                            return propVal:ToString()
                        end
                        return nil
                    end)
                    if strSuccess and strVal then
                        logger:log(2, string.format("  PlayerState.%s: %s", prop, strVal))
                    else
                        logger:log(2, string.format("  PlayerState.%s: <userdata - ToString failed>", prop))
                    end
                else
                    logger:log(2, string.format("  PlayerState.%s: %s (%s)", prop, tostring(propVal), type(propVal)))
                end
            end
        end
    end

    -- CharacterParameterComponent enumeration (already logged stats above)
    if charSuccess and charParam and charParam:IsValid() then
        logger:log(2, "\n=== CharacterParameterComponent Properties ===")
        EnumerateProperties(charParam, playerName .. " (CharacterParameterComponent)")
        EnumerateFunctions(charParam, playerName .. " (CharacterParameterComponent)")
    end

    -- INVENTORY DATA DISCOVERY
    logger:log(2, "\n=== INVENTORY ===")
    local invSuccess, invComponent = pcall(function()
        return player.InventoryComponent
    end)

    logger:log(2, string.format("InventoryComponent pcall success: %s", tostring(invSuccess)))
    logger:log(2, string.format("InventoryComponent value: %s (type: %s)", tostring(invComponent), type(invComponent)))

    if invSuccess and invComponent then
        local validSuccess, isValid = pcall(function()
            return invComponent:IsValid()
        end)
        logger:log(2, string.format("IsValid() call success: %s, result: %s", tostring(validSuccess), tostring(isValid)))

        if validSuccess and isValid then
            logger:log(2, "InventoryComponent is valid - extracting data...")

            -- Try common inventory properties/methods
            local invProps = {
                "Items", "ItemSlots", "Inventory", "Container", "ItemArray",
                "MaxSlots", "SlotCount", "StorageContainer"
            }

            for _, prop in ipairs(invProps) do
                local propSuccess, propVal = pcall(function()
                    return invComponent[prop]
                end)
                if propSuccess and propVal ~= nil then
                    logger:log(2, string.format("  %s: %s (%s)", prop, tostring(propVal), type(propVal)))
                end
            end

            -- Try to enumerate inventory properties
            EnumerateProperties(invComponent, playerName .. " (InventoryComponent)")
            EnumerateFunctions(invComponent, playerName .. " (InventoryComponent)")
        else
            logger:log(1, string.format("InventoryComponent exists but IsValid() = %s", tostring(isValid)))
        end
    else
        logger:log(1, "InventoryComponent pcall failed or returned nil")
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
    logger:log(2, "Data Discovery Module initialized (Enhanced with UE4SS APIs)")

    -- Run initial object discovery after 5 seconds (let the game initialize)
    LoopAsync(5000, function()
        DataDiscovery.DiscoverLoadedObjects()
        return true  -- Only run once
    end)

    -- Log all player data every 60 seconds
    LoopAsync(60000, function()
        DataDiscovery.LogAllPlayers()
        return false
    end)

    -- Register notification for new player objects
    local success, err = pcall(function()
        NotifyOnNewObject("/Script/Pal.PalPlayerCharacter", function(newPlayer)
            logger:log(2, "\n=== NEW PLAYER OBJECT DETECTED ===")
            if newPlayer and newPlayer:IsValid() then
                local playerState = newPlayer.PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState.PlayerNamePrivate:ToString()
                    logger:log(2, "New player joined: " .. playerName)
                    logger:log(2, "Full class name: " .. newPlayer:GetFullName())
                end
            end
        end)
        logger:log(2, "Registered notification for new PalPlayerCharacter objects")
    end)

    if not success then
        logger:log(1, "Failed to register NotifyOnNewObject: " .. tostring(err))
    end

    logger:log(2, "Data discovery will run:")
    logger:log(2, "  - Object scan: Once after 5 seconds")
    logger:log(2, "  - Player data: Every 60 seconds")
    logger:log(2, "  - New player notifications: Real-time")
end

return DataDiscovery
