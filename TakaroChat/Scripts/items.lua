-- Item giving module - processes item requests from bridge
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Items = {}

-- Fetch item requests from bridge
local function FetchItemRequests()
    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            logger:log(1, "[ITEMS] Could not extract bridge host from URL")
            return
        end

        local url = string.format('http://%s/item-queue', bridgeHost)
        local command = string.format('curl -s %s', url)
        local handle = io.popen(command)
        if not handle then
            logger:log(1, "[ITEMS] Failed to fetch item queue")
            return
        end

        local result = handle:read("*a")
        handle:close()

        if result and result ~= "" and result ~= '{"requests":[]}' then
            -- Parse JSON response for item requests
            -- Format: {"requests":[{"playerName":"...", "itemId":"...", "quantity":1, "requestId":"..."}]}
            for playerName, itemId, quantity, requestId in result:gmatch('"playerName"%s*:%s*"([^"]+)"[^}]*"itemId"%s*:%s*"([^"]+)"[^}]*"quantity"%s*:%s*(%d+)[^}]*"requestId"%s*:%s*"([^"]+)"') do
                logger:log(2, string.format("[ITEMS] Processing request %s: Give %d x %s to %s", requestId, tonumber(quantity), itemId, playerName))

                local success = GiveItemToPlayer(playerName, itemId, tonumber(quantity))

                -- Send response to bridge
                SendItemResponse(requestId, playerName, itemId, quantity, success)
            end
        end
    end)

    if not success then
        logger:log(1, "[ITEMS] Error fetching item requests: " .. tostring(err))
    end
end

-- Give item to a player
function GiveItemToPlayer(playerName, itemId, quantity)
    local success, err = pcall(function()
        -- Find the player by name
        local PlayersList = FindAllOf("PalPlayerCharacter")
        if not PlayersList then
            logger:log(1, "[ITEMS] ERROR: FindAllOf returned nil")
            return false
        end

        local playerFound = false
        for _, Player in ipairs(PlayersList) do
            if Player ~= nil and Player and Player:IsValid() then
                local playerState = Player.PlayerState
                if playerState and playerState:IsValid() then
                    local currentName = playerState.PlayerNamePrivate:ToString()
                    if currentName == playerName then
                        playerFound = true

                        -- Get inventory data using the correct approach
                        local inventoryData = playerState:GetInventoryData()
                        if inventoryData and inventoryData:IsValid() then
                            -- Add item using RequestAddItem (client-side request)
                            -- For server-side, would use AddItem_ServerInternal but requires server context check
                            inventoryData:RequestAddItem(FName(itemId), quantity, false)

                            logger:log(2, string.format("[ITEMS] Gave %d x %s to %s", quantity, itemId, playerName))
                            return true
                        else
                            logger:log(1, string.format("[ITEMS] Failed to get inventory data for %s", playerName))
                            return false
                        end
                    end
                end
            end
        end

        if not playerFound then
            logger:log(1, string.format("[ITEMS] ERROR: Player '%s' not found online", playerName))
            return false
        end
    end)

    if not success then
        logger:log(1, string.format("[ITEMS] Error giving item: %s", tostring(err)))
        return false
    end

    return true
end

-- Send item response back to bridge
function SendItemResponse(requestId, playerName, itemId, quantity, success)
    local bridgeHost = config.BridgeURL:match("http://([^/]+)")
    if not bridgeHost then
        return
    end

    local json = string.format(
        '{"requestId":"%s","playerName":"%s","itemId":"%s","quantity":%d,"success":%s,"timestamp":"%s"}',
        requestId,
        playerName,
        itemId,
        quantity,
        tostring(success),
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    local jsonEscaped = json:gsub('"', '\\"')
    local curlCommand = string.format(
        'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/item-response',
        jsonEscaped,
        bridgeHost
    )

    local handle = io.popen(curlCommand .. ' 2>&1')
    if handle then
        local result = handle:read("*a")
        handle:close()
        logger:log(3, string.format("[ITEMS] Sent response for request %s", requestId))
    end
end

-- Initialize item system
function Items.Initialize()
    logger:log(2, "[ITEMS] Initializing item giving system...")

    -- Poll bridge for item requests every second
    LoopAsync(1000, function()
        FetchItemRequests()
        return false
    end)

    logger:log(2, "[ITEMS] Item giving system initialized")
end

return Items
