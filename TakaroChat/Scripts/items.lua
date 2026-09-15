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

                local gave, giveErr = GiveItemToPlayer(playerName, itemId, tonumber(quantity))

                -- Send response to bridge (real result, including the failure reason)
                SendItemResponse(requestId, playerName, itemId, quantity, gave, giveErr)
            end
        end
    end)

    if not success then
        logger:log(1, "[ITEMS] Error fetching item requests: " .. tostring(err))
    end
end

-- Resolve an item id to an FName.
--
-- UE4SS exposes FName(name, EFindName.FNAME_Find), which resolves a name only if
-- it already exists in the global name pool. That is the cheapest runtime hint
-- that an item id is bogus, but it is NOT a data-table row check and it is not
-- verified on the Palworld UE4SS build (Okaetsu fork), so the result is only
-- logged as a warning - we still attempt the give. Item-id validity is
-- guaranteed bridge-side by the embedded catalog (data/palworld-items.json),
-- which rejects unknown codes before they ever reach this queue.
local function ResolveItemFName(itemId)
    if type(EFindName) == "table" and EFindName.FNAME_Find ~= nil then
        local found, name = pcall(FName, itemId, EFindName.FNAME_Find)
        if found and name ~= nil then
            local readable, asString = pcall(function() return name:ToString() end)
            if readable and (asString == nil or asString == "" or asString == "None") then
                logger:log(1, string.format("[ITEMS] WARNING: item id '%s' is not in the name pool - the give may silently no-op", itemId))
            end
        end
    end

    local built, name = pcall(FName, itemId)
    if not built or name == nil then
        return nil, "failed to build FName for item id"
    end
    return name
end

-- Give item to a player.
-- Returns (ok, err). The previous version put its return statements inside the
-- pcall closure, so their values were discarded and every call that did not
-- throw reported success - including "player not found online" and "failed to
-- get inventory data". The result is now carried out in locals.
function GiveItemToPlayer(playerName, itemId, quantity)
    local ok = false
    local err = nil

    local ran, pcallErr = pcall(function()
        -- Find the player by name
        local PlayersList = FindAllOf("PalPlayerCharacter")
        if not PlayersList then
            logger:log(1, "[ITEMS] ERROR: FindAllOf returned nil")
            err = "no player list available"
            return
        end

        for _, Player in ipairs(PlayersList) do
            if Player ~= nil and Player and Player:IsValid() then
                local playerState = Player.PlayerState
                if playerState and playerState:IsValid() then
                    local currentName = playerState.PlayerNamePrivate:ToString()
                    if currentName == playerName then
                        -- Get inventory data using the correct approach
                        local inventoryData = playerState:GetInventoryData()
                        if not (inventoryData and inventoryData:IsValid()) then
                            logger:log(1, string.format("[ITEMS] Failed to get inventory data for %s", playerName))
                            err = "failed to get inventory data"
                            return
                        end

                        local itemName, resolveErr = ResolveItemFName(itemId)
                        if itemName == nil then
                            logger:log(1, string.format("[ITEMS] %s for '%s'", tostring(resolveErr), itemId))
                            err = resolveErr
                            return
                        end

                        -- Add item using RequestAddItem (client-side request)
                        -- For server-side, would use AddItem_ServerInternal but requires server context check
                        inventoryData:RequestAddItem(itemName, quantity, false)

                        logger:log(2, string.format("[ITEMS] Gave %d x %s to %s", quantity, itemId, playerName))
                        ok = true
                        return
                    end
                end
            end
        end

        logger:log(1, string.format("[ITEMS] ERROR: Player '%s' not found online", playerName))
        err = "player not found online"
    end)

    if not ran then
        logger:log(1, string.format("[ITEMS] Error giving item: %s", tostring(pcallErr)))
        return false, "lua error: " .. tostring(pcallErr)
    end

    if not ok and err == nil then
        err = "item give failed"
    end

    return ok, err
end

-- Send item response back to bridge
function SendItemResponse(requestId, playerName, itemId, quantity, success, err)
    local bridgeHost = config.BridgeURL:match("http://([^/]+)")
    if not bridgeHost then
        return
    end

    -- Keep the reason shell- and JSON-safe: the POST below goes through a
    -- double-quoted curl command line.
    local reason = ""
    if not success then
        reason = tostring(err or "item give failed"):gsub('[^%w %-_%.:/]', ' ')
        reason = reason:sub(1, 120)
    end

    local json = string.format(
        '{"requestId":"%s","playerName":"%s","itemId":"%s","quantity":%d,"success":%s,"error":"%s","timestamp":"%s"}',
        requestId,
        playerName,
        itemId,
        quantity,
        tostring(success and true or false),
        reason,
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
