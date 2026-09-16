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

-- Deliver an item into a player's inventory (F21).
--
-- hardtest-7R-A13.txt: on PalServer v1.0.5.102999 the queued give reported success
-- but the item never landed, and a valid `Wood` threw
--   "attempt to call a TrivialObject value method" at items.lua:120,
-- i.e. inventoryData:RequestAddItem is unresolvable on a DEDICATED SERVER. That
-- call is the CLIENT-side request path (it asks the owning client to add the item),
-- so it is a no-op / trivial object when there is no client context - exactly the
-- dedicated-server case.
--
-- The working Palworld 1.0 dedicated-server admin mod dkoz/AdminCommands uses the
-- server-internal path instead (AdminCommands/Scripts/modules/items.lua):
--     if isServerSide() then
--         inventory:AddItem_ServerInternal(FName(item), quantity, false, 0.0, true)
--     else
--         inventory:RequestAddItem(FName(item), quantity, false)
--     end
-- Source: https://github.com/dkoz/AdminCommands (Scripts/modules/items.lua),
-- the upstream of waze3174/AdminCommands-Palhaven cited in research/ue4ss-hooks-1.0.md.
-- We mirror that: prefer AddItem_ServerInternal, fall back to RequestAddItem.
--
-- Every reflected call is existence-guarded the F17 way. RegisterHook could
-- native-crash on a missing path; an instance method call raises a *Lua-catchable*
-- error (A13 caught the TrivialObject error via pcall), so pcall is the real
-- protection here, and a StaticFindObject pre-check on the method's UFunction (built
-- from the inventory object's own class name) avoids even attempting a call the
-- build does not expose. When the class path cannot be determined we still attempt
-- under pcall, since that cannot crash the server.
--
-- Returns (delivered, err, method). `delivered` is true only when a reflected add
-- call completed without error; whether the item is physically in the bag still
-- needs the live retest to confirm (documented as unverified).

-- Does <inventoryData>'s class expose UFunction <methodName>?
--   "yes"     -> StaticFindObject resolved it, safe & sensible to call
--   "no"      -> class known and StaticFindObject did NOT resolve it -> skip
--   "unknown" -> class name could not be read -> caller may still try under pcall
local function InventoryMethodStatus(inventoryData, methodName)
    local okClass, className = pcall(function()
        return inventoryData:GetClass():GetFName():ToString()
    end)
    if not okClass or not className or className == "" then
        return "unknown"
    end
    -- Palworld's inventory-data classes live in the /Script/Pal package.
    local path = string.format("/Script/Pal.%s:%s", className, methodName)
    local okFind, obj = pcall(function() return StaticFindObject(path) end)
    if not okFind or obj == nil then
        return "no"
    end
    local okValid, valid = pcall(function() return obj:IsValid() end)
    if not okValid then
        return "yes" -- IsValid unavailable on this build; non-nil is enough
    end
    return valid == true and "yes" or "no"
end

-- Try one add-item UFunction. Returns (ok, err).
--
-- The StaticFindObject status is ADVISORY, not a gate: it is checked and logged,
-- but a "no" does not skip the call. StaticFindObject resolves a UFunction only on
-- the exact class in the path, while UE4SS instance calls walk the class hierarchy,
-- so an inherited AddItem_ServerInternal (which dkoz/AdminCommands calls directly
-- and which works) can be reported absent on the concrete subclass. Blocking on
-- that would break delivery. The genuine crash-safety comes from pcall: an instance
-- method call raises a Lua-catchable error (proven in A13), never a native crash, so
-- attempting under pcall can never take the server down even on a wrong signature.
local function TryInventoryAdd(inventoryData, methodName, callFn)
    local status = InventoryMethodStatus(inventoryData, methodName)
    logger:log(3, string.format("[ITEMS] %s existence check: %s", methodName, status))
    local ran, callErr = pcall(callFn)
    if ran then
        return true, nil
    end
    return false, string.format("%s failed: %s", methodName, tostring(callErr))
end

local function DeliverItem(inventoryData, itemName, quantity)
    -- 1) Server-side add (correct path on a dedicated server) - the 5-arg signature
    --    from dkoz/AdminCommands: AddItem_ServerInternal(FName, count, false, 0.0, true).
    local ok, serverErr = TryInventoryAdd(inventoryData, "AddItem_ServerInternal", function()
        inventoryData:AddItem_ServerInternal(itemName, quantity, false, 0.0, true)
    end)
    if ok then
        return true, nil, "AddItem_ServerInternal"
    end

    -- 2) Client-request fallback (works on a listen server / single player).
    local ok2, err2 = TryInventoryAdd(inventoryData, "RequestAddItem", function()
        inventoryData:RequestAddItem(itemName, quantity, false)
    end)
    if ok2 then
        return true, nil, "RequestAddItem"
    end

    local reason = serverErr or err2 or "no usable add-item UFunction (tried AddItem_ServerInternal, RequestAddItem)"
    return false, reason, nil
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

                        -- F21: deliver via the server-internal path (RequestAddItem
                        -- is a client request that no-ops / throws "TrivialObject" on a
                        -- dedicated server - hardtest-7R-A13.txt). DeliverItem prefers
                        -- AddItem_ServerInternal and reports the REAL result.
                        local delivered, deliverErr, method = DeliverItem(inventoryData, itemName, quantity)
                        if not delivered then
                            logger:log(1, string.format("[ITEMS] Failed to deliver %d x %s to %s: %s",
                                quantity, itemId, playerName, tostring(deliverErr)))
                            err = deliverErr
                            return
                        end

                        logger:log(2, string.format("[ITEMS] Gave %d x %s to %s (via %s)",
                            quantity, itemId, playerName, tostring(method)))
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
