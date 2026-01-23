-- Player location lookup module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Location = {}

-- Fetch location requests from bridge
local function FetchLocationRequests()
    -- Silent polling - only log errors and actual activity

    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            logger:log(1, "[LOCATION] Could not extract bridge host from URL")
            return
        end

        local url = string.format('http://%s/location-queue', bridgeHost)
        local command = string.format('curl -s %s', url)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "[LOCATION] Failed to fetch location queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        if result and result ~= "" and result ~= '{"requests":[]}' then
            -- Parse JSON response for location requests
            for playerName, requestId in result:gmatch('"name"%s*:%s*"([^"]+)"%s*,[^}]*"requestId"%s*:%s*"([^"]+)"') do
                logger:log(2, string.format("[LOCATION] Processing request %s for player %s", requestId, playerName))

                -- Find the player
                local PlayersList = FindAllOf("PalPlayerCharacter")
                if not PlayersList then
                    logger:log(1, "[LOCATION] ERROR: FindAllOf returned nil")
                else
                    -- Count total players found
                    local totalCount = 0
                    for _ in ipairs(PlayersList) do totalCount = totalCount + 1 end

                    -- Log all available player names for debugging
                    logger:log(2, string.format("[LOCATION] Looking for '%s'. FindAllOf returned %d players. Valid players:", playerName, totalCount))
                    for _, Player in ipairs(PlayersList) do
                        if Player ~= nil and Player and Player:IsValid() then
                            -- Use direct property access like teleport.lua (AdminEngine pattern)
                            local success, availableName = pcall(function() return Player.PlayerState.PlayerNamePrivate:ToString() end)
                            if success and availableName then
                                logger:log(2, string.format("[LOCATION]   - '%s'", availableName))
                            else
                                logger:log(1, "[LOCATION] WARNING: Player has invalid PlayerState")
                            end
                        else
                            logger:log(1, "[LOCATION] WARNING: Player object is invalid")
                        end
                    end

                    -- Find the player (use direct access like teleport.lua)
                    local playerFound = false
                    for _, Player in ipairs(PlayersList) do
                        -- ATOMIC EXTRACTION: Get name and location in one operation to prevent crashes
                        local playerData = nil
                        local extractSuccess = pcall(function()
                            if Player and Player:IsValid() and
                               Player.PlayerState and Player.PlayerState:IsValid() and
                               Player.PlayerState.PlayerNamePrivate then
                                local name = Player.PlayerState.PlayerNamePrivate:ToString()
                                -- Get location immediately while object is still valid
                                local loc = Player:K2_GetActorLocation()
                                if loc then
                                    playerData = {
                                        name = name,
                                        location = loc
                                    }
                                end
                            end
                        end)

                        -- Check if extraction succeeded and name matches (case-insensitive)
                        if extractSuccess and playerData and playerData.name and playerData.name:lower() == playerName:lower() then
                            playerFound = true

                            -- Send location back to bridge using curl
                            local json = string.format(
                                '{"requestId":"%s","name":"%s","x":%.2f,"y":%.2f,"z":%.2f,"timestamp":"%s"}',
                                requestId,
                                playerName,
                                playerData.location.X,
                                playerData.location.Y,
                                playerData.location.Z,
                                os.date("!%Y-%m-%dT%H:%M:%SZ")
                            )

                            -- Escape double quotes for curl (need to use \" in Windows)
                            local jsonEscaped = json:gsub('"', '\\"')

                            -- Use curl with timeout for reliable JSON POST
                            local curlCommand = string.format(
                                'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/location-response',
                                jsonEscaped,
                                bridgeHost
                            )

                            -- Execute synchronously and capture result
                            local handle = io.popen(curlCommand .. ' 2>&1')
                            if handle then
                                local result = handle:read("*a")
                                local success = handle:close()

                                if success and result:match('"success"%s*:%s*true') then
                                    logger:log(2, string.format("[LOCATION] Sent response for %s: (%.1f, %.1f, %.1f)", playerName, playerData.location.X, playerData.location.Y, playerData.location.Z))
                                else
                                    logger:log(1, string.format("[LOCATION] Failed to send response for %s: %s", playerName, result))
                                end
                            else
                                logger:log(1, string.format("[LOCATION] Failed to execute curl for %s", playerName))
                            end
                            break
                        end
                    end

                    if not playerFound then
                        logger:log(1, string.format("[LOCATION] ERROR: Player '%s' not found online", playerName))

                        -- Send error response to bridge to clear the stuck request
                        local json = string.format(
                            '{"requestId":"%s","name":"%s","x":0,"y":0,"z":0,"timestamp":"%s"}',
                            requestId,
                            playerName,
                            os.date("!%Y-%m-%dT%H:%M:%SZ")
                        )
                        local jsonEscaped = json:gsub('"', '\\"')
                        local curlCommand = string.format(
                            'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/location-response',
                            jsonEscaped,
                            bridgeHost
                        )
                        local handle = io.popen(curlCommand .. ' 2>&1')
                        if handle then
                            handle:read("*a")
                            handle:close()
                        end
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
