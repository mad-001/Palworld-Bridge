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
            if player and player:IsValid() then
                -- Use direct property access like AdminEngine
                local playerName = player.PlayerState.PlayerNamePrivate:ToString()

                -- Check if this player has pending teleport
                for i = #teleportQueue, 1, -1 do
                    local teleport = teleportQueue[i]
                    if teleport.playerName == playerName then
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

                        -- Teleport using PalUtility (exact AdminEngine pattern)
                        local palUtil = GetPalUtil()
                        if palUtil and palUtil:IsValid() then
                            palUtil:Teleport(player, NewLocation, NewRotation, true, false)
                            logger:log(2, string.format("Teleported %s to (%.1f, %.1f, %.1f)", playerName, teleport.x, teleport.y, teleport.z))
                        else
                            logger:log(1, "Failed to get PalUtility")
                        end

                        -- Remove from queue
                        table.remove(teleportQueue, i)
                    end
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error processing teleports: " .. tostring(err))
    end
end

-- Fetch pending teleports from bridge
local function FetchTeleportQueue()
    logger:log(2, "[TELEPORT] Polling queue...")

    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            return
        end

        local url = string.format('http://%s/teleport-queue', bridgeHost)
        logger:log(2, string.format("[TELEPORT] Polling URL: %s", url))
        local command = string.format('curl -s %s', url)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "Failed to fetch teleport queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        logger:log(2, string.format("[TELEPORT] Queue response: %s", result or "nil"))

        if result and result ~= "" then
            -- Parse JSON response for sourcePlayer and targetPlayer
            logger:log(2, "[TELEPORT] Parsing response for teleports...")
            -- Use simpler pattern: match each field separately
            for sourcePlayer, targetPlayer in result:gmatch('"sourcePlayer"%s*:%s*"([^"]+)"[^}]*"targetPlayer"%s*:%s*"([^"]+)"') do
                logger:log(2, string.format("[TELEPORT] Found match: %s -> %s", sourcePlayer, targetPlayer))
                -- Find target player using AdminEngine pattern
                local PlayersList = FindAllOf("PalPlayerCharacter")
                if PlayersList then
                    for _, TPlayer in ipairs(PlayersList) do
                        if TPlayer ~= nil and TPlayer and TPlayer:IsValid() then
                            local playerState = TPlayer.PlayerState
                            if playerState and playerState:IsValid() then
                                local targetName = playerState.PlayerNamePrivate:ToString()
                                if targetName == targetPlayer then
                                    -- Get location using AdminEngine pattern
                                    local pawnPrivate = TPlayer.PawnPrivate
                                    if pawnPrivate and pawnPrivate:IsValid() then
                                        local location = pawnPrivate:K2_GetActorLocation()
                                        logger:log(2, string.format("Teleporting %s to %s at (%.1f, %.1f, %.1f)", sourcePlayer, targetPlayer, location.X, location.Y, location.Z))
                                        QueueTeleport(sourcePlayer, location.X, location.Y, location.Z)
                                        break
                                    end
                                end
                            end
                        end
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
