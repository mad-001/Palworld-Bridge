-- Player location lookup module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Location = {}

-- Fetch location requests from bridge
local function FetchLocationRequests()
    logger:log(2, "[LOCATION] Polling queue...")

    if not config.EnableBridge then
        logger:log(1, "[LOCATION] Bridge disabled, skipping")
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            logger:log(1, "[LOCATION] Could not extract bridge host from URL")
            return
        end

        local url = string.format('http://%s/location-queue', bridgeHost)
        logger:log(2, string.format("[LOCATION] Polling URL: %s", url))
        local command = string.format('curl -s %s', url)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "[LOCATION] Failed to fetch location queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        logger:log(2, string.format("[LOCATION] Queue response: %s", result or "nil"))

        if result and result ~= "" then
            -- Parse JSON response for location requests
            for playerName, requestId in result:gmatch('"playerName"%s*:%s*"([^"]+)"%s*,[^}]*"requestId"%s*:%s*"([^"]+)"') do
                logger:log(2, string.format("[LOCATION] Request %s for player %s", requestId, playerName))

                -- Find the player
                local PlayersList = FindAllOf("PalPlayerCharacter")
                if not PlayersList then
                    logger:log(1, "[LOCATION] ERROR: FindAllOf returned nil")
                else
                    local playerFound = false
                    for _, Player in ipairs(PlayersList) do
                        if Player ~= nil and Player and Player:IsValid() then
                            local playerState = Player.PlayerState
                            if playerState and playerState:IsValid() then
                                local currentName = playerState.PlayerNamePrivate:ToString()
                                if currentName == playerName then
                                    playerFound = true

                                    -- Get player location using K2_GetActorLocation (same as teleport)
                                    local location = Player:K2_GetActorLocation()

                                    -- Send location back to bridge
                                    local json = string.format(
                                        '{"requestId":"%s","playerName":"%s","x":%.2f,"y":%.2f,"z":%.2f,"timestamp":"%s"}',
                                        requestId,
                                        playerName,
                                        location.X,
                                        location.Y,
                                        location.Z,
                                        os.date("!%Y-%m-%dT%H:%M:%SZ")
                                    )

                                    -- Write JSON to temp file for curl (avoids quoting hell)
                                    local tempFile = os.getenv("TEMP") .. "\\loc_" .. requestId .. ".json"
                                    local file = io.open(tempFile, "w")
                                    if file then
                                        file:write(json)
                                        file:close()

                                        local postCommand = string.format(
                                            'curl -s -X POST -H "Content-Type: application/json" -d @"%s" http://%s/location-response && del "%s"',
                                            tempFile,
                                            bridgeHost,
                                            tempFile
                                        )

                                        os.execute('start /B "" ' .. postCommand .. ' >nul 2>&1')
                                        logger:log(2, string.format("[LOCATION] Sent response for %s: (%.1f, %.1f, %.1f)", playerName, location.X, location.Y, location.Z))
                                    else
                                        logger:log(1, "[LOCATION] Failed to write temp file")
                                    end
                                    break
                                end
                            end
                        end
                    end

                    if not playerFound then
                        logger:log(1, string.format("[LOCATION] ERROR: Player '%s' not found online", playerName))
                    end
                end
            end
        end
    end)

    if not success then
        logger:log(1, "[LOCATION] Error fetching location requests: " .. tostring(err))
    end
end

-- Initialize location system
function Location.Initialize()
    logger:log(2, "Initializing location lookup system...")

    -- Poll bridge for location requests every second
    LoopAsync(1000, function()
        FetchLocationRequests()
        return false
    end)

    logger:log(2, "Location lookup system initialized")
end

return Location
