-- Player teleport module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Teleport = {}
local teleportQueue = {}

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
                local playerState = player:get().PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState:get().PlayerNamePrivate:ToString()

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

                            -- Teleport player using K2_SetActorLocation
                            player:K2_SetActorLocation(NewLocation, false, true)

                            logger:log(2, string.format("Teleported %s to (%.1f, %.1f, %.1f)", playerName, teleport.x, teleport.y, teleport.z))

                            -- Remove from queue
                            table.remove(teleportQueue, i)
                        end
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
    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            return
        end

        local command = string.format('curl -s http://%s/teleport-queue', bridgeHost)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "Failed to fetch teleport queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        if result and result ~= "" then
            -- Parse JSON response (simple parsing for teleports array)
            for playerName, x, y, z in result:gmatch('"playerName":"([^"]+)"[^}]-"x":([%d%.%-]+),"y":([%d%.%-]+),"z":([%d%.%-]+)') do
                QueueTeleport(playerName, tonumber(x), tonumber(y), tonumber(z))
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

    -- Check for teleport chat commands
    RegisterHook("/Script/Pal.PalPlayerState:EnterChat_Receive", function(playerState, chatData)
        local success, err = pcall(function()
            local message = chatData:get().Message:ToString()
            local playerName = playerState:get().PlayerNamePrivate:ToString()

            -- Check for teleport request command: /tp @targetPlayer
            if message:match("^/tp%s+@") then
                local targetPlayer = message:match("^/tp%s+@(.+)")
                if targetPlayer then
                    -- Send teleport request to bridge
                    local json = string.format(
                        '{"type":"teleport_request","playerName":"%s","targetPlayer":"%s","timestamp":"%s"}',
                        Utils.EscapeJSON(playerName),
                        Utils.EscapeJSON(targetPlayer),
                        os.date("!%Y-%m-%dT%H:%M:%SZ")
                    )

                    local command = string.format(
                        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
                        json:gsub('"', '\\"'),
                        config.BridgeURL
                    )

                    os.execute('start /B "" ' .. command .. ' >nul 2>&1')
                    logger:log(2, string.format("%s requested teleport to %s", playerName, targetPlayer))
                end
            end
        end)

        if not success then
            logger:log(1, "Error in teleport chat hook: " .. tostring(err))
        end
    end)

    -- Poll bridge for teleports and process them every second
    LoopAsync(1000, function()
        FetchTeleportQueue()
        ProcessTeleports()
        return false
    end)

    logger:log(2, "Teleport system initialized")
end

return Teleport
