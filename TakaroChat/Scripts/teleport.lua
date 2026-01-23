-- Player teleport module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Teleport = {}
local teleportQueue = {}

-- Get PalUtility for teleport function (from AdminEngine pattern)
local PalUtilities = nil
local function GetPalUtil()
    if not PalUtilities or not PalUtilities:IsValid() then
        PalUtilities = StaticFindObject("/Script/Pal.Default__PalUtility")
    end
    return PalUtilities
end

-- Add teleport to queue
local function QueueTeleport(playerName, x, y, z)
    table.insert(teleportQueue, {
        playerName = playerName,
        x = x,
        y = y,
        z = z,
        timestamp = os.time()
    })
    logger:log(2, string.format("Queued teleport for %s to (%.1f, %.1f, %.1f)", playerName, x, y, z))
end

-- Process pending teleports
local function ProcessTeleports()
    if #teleportQueue == 0 then
        return
    end

    local success, err = pcall(function()
        local players = FindAllOf("PalPlayerCharacter")
        if not players then
            return
        end

        for _, player in ipairs(players) do
            -- ATOMIC EXTRACTION: Get all data in one tight operation
            -- This minimizes the race condition window to a few CPU cycles
            local playerData = nil
            local extractSuccess = pcall(function()
                -- All validations and extractions happen atomically here
                if player and player:IsValid() and
                   player.PlayerState and player.PlayerState:IsValid() and
                   player.PlayerState.PlayerNamePrivate then
                    playerData = {
                        name = player.PlayerState.PlayerNamePrivate:ToString(),
                        ref = player  -- Store reference only after validation
                    }
                end
            end)

            -- If extraction failed or data is incomplete, skip this player
            if not extractSuccess or not playerData or not playerData.name then
                goto continue
            end

            -- Check if this player has pending teleport (match by name)
            for i = #teleportQueue, 1, -1 do
                local teleport = teleportQueue[i]
                if teleport.playerName == playerData.name then
                    -- Create FVector for new location
                    local NewLocation = {
                        X = teleport.x,
                        Y = teleport.y,
                        Z = teleport.z
                    }

                    -- Create FRotator (default rotation)
                    local NewRotation = {
                        Pitch = 0,
                        Yaw = 0,
                        Roll = 0
                    }

                    -- Teleport using PalUtility with crash protection
                    local palUtil = GetPalUtil()
                    if palUtil and palUtil:IsValid() then
                        -- Re-validate player right before teleport (final safety check)
                        local tpSuccess, tpErr = pcall(function()
                            if playerData.ref and playerData.ref:IsValid() then
                                palUtil:Teleport(playerData.ref, NewLocation, NewRotation, true, false)
                            else
                                error("Player became invalid before teleport")
                            end
                        end)

                        if tpSuccess then
                            logger:log(2, string.format("Teleported %s to (%.1f, %.1f, %.1f)", playerData.name, teleport.x, teleport.y, teleport.z))
                        else
                            logger:log(1, string.format("Teleport failed for %s: %s", playerData.name, tostring(tpErr)))
                        end
                    else
                        logger:log(1, string.format("Failed to get PalUtility for %s", playerData.name))
                    end

                    -- Remove from queue
                    table.remove(teleportQueue, i)
                end
            end
            ::continue::
        end
    end)

    if not success then
        logger:log(1, "Error processing teleports: " .. tostring(err))
    end
end

-- Fetch pending teleports from bridge
local function FetchTeleportQueue()
    -- Silent polling - only log errors and actual activity

    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            return
        end

        local url = string.format('http://%s/teleport-queue', bridgeHost)
        local command = string.format('curl -s %s', url)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "Failed to fetch teleport queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        if result and result ~= "" and result ~= '{"teleports":[]}' then
            -- Parse JSON response for teleports (now includes Steam IDs)

            -- First, try to match coordinate-based teleports (JSON order: sourcePlayer, sourceSteamId, x, y, z)
            for sourcePlayer, sourceSteamId, x, y, z in result:gmatch('"sourcePlayer"%s*:%s*"([^"]+)"%s*,[^}]*"sourceSteamId"%s*:%s*"([^"]+)"%s*,[^}]*"x"%s*:%s*([%d%.%-]+)%s*,[^}]*"y"%s*:%s*([%d%.%-]+)%s*,[^}]*"z"%s*:%s*([%d%.%-]+)') do
                logger:log(2, string.format("[TELEPORT] Coordinate: %s (Steam: %s) -> (%.1f, %.1f, %.1f)", sourcePlayer, sourceSteamId, tonumber(x), tonumber(y), tonumber(z)))
                QueueTeleport(sourcePlayer, tonumber(x), tonumber(y), tonumber(z))
            end

            -- Then, match player-to-player teleports (JSON order: sourcePlayer, sourceSteamId, targetPlayer, targetSteamId)
            for sourcePlayer, sourceSteamId, targetPlayer, targetSteamId in result:gmatch('"sourcePlayer"%s*:%s*"([^"]+)"%s*,[^}]*"sourceSteamId"%s*:%s*"([^"]+)"%s*,[^}]*"targetPlayer"%s*:%s*"([^"]+)"%s*,[^}]*"targetSteamId"%s*:%s*"([^"]+)"') do
                -- Find target player by name
                local PlayersList = FindAllOf("PalPlayerCharacter")
                if not PlayersList then
                    logger:log(1, "[TELEPORT] ERROR: FindAllOf returned nil")
                else
                    local targetFound = false
                    for _, TPlayer in ipairs(PlayersList) do
                        -- ATOMIC EXTRACTION: Get name and location in one operation
                        local targetData = nil
                        local extractSuccess = pcall(function()
                            -- Validate everything and extract atomically
                            if TPlayer and TPlayer:IsValid() and
                               TPlayer.PlayerState and TPlayer.PlayerState:IsValid() and
                               TPlayer.PlayerState.PlayerNamePrivate then
                                local name = TPlayer.PlayerState.PlayerNamePrivate:ToString()
                                -- Get location immediately while object is still valid
                                local loc = TPlayer:K2_GetActorLocation()
                                targetData = {
                                    name = name,
                                    location = loc
                                }
                            end
                        end)

                        -- Check if extraction succeeded and name matches
                        if extractSuccess and targetData and targetData.name == targetPlayer and targetData.location then
                            targetFound = true
                            logger:log(2, string.format("[TELEPORT] %s (Steam: %s) -> %s at (%.1f, %.1f, %.1f)",
                                sourcePlayer, sourceSteamId, targetPlayer,
                                targetData.location.X, targetData.location.Y, targetData.location.Z))
                            QueueTeleport(sourcePlayer, targetData.location.X, targetData.location.Y, targetData.location.Z)
                            break
                        end
                    end
                    if not targetFound then
                        logger:log(1, string.format("[TELEPORT] ERROR: Target player '%s' not found online", targetPlayer))
                    end
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error fetching teleport queue: " .. tostring(err))
    end
end

-- Initialize teleport system
function Teleport.Initialize()
    logger:log(2, "Initializing teleport system...")

    -- Poll bridge for teleports and process them every second
    LoopAsync(1000, function()
        FetchTeleportQueue()
        ProcessTeleports()
        return false
    end)

    logger:log(2, "Teleport system initialized")
end

return Teleport
