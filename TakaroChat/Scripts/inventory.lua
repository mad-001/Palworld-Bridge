-- Inventory reading module (F22)
--
-- ON-DEMAND request/response, NOT a periodic push.
--
-- The previous version ran a LoopAsync every InventoryUpdateInterval (30s) that
-- walked every online player, ran ForEachProperty() reflection-discovery logging
-- on both PlayerState and InventoryData, and pushed a `type:"inventory"` frame to
-- /chat for every player every cycle. Any reflected read that threw was caught by
-- one big outer pcall that logged "[INVENTORY] Error updating inventories:" at
-- error level - so a single bad read turned into an error logged every 30s forever,
-- for every connected player. That is the "causes errors" spam that got the whole
-- module disabled (config.EnableInventoryTracking = false).
--
-- This rewrite serves inventory the SAME way teleport/location/items already do:
-- the bridge POSTs an inventory request onto a queue, the Lua polls the queue,
-- enumerates once, and replies once. No periodic push, no discovery spam.
--
-- Enumeration mirrors the proven give path (items.lua) plus the Palworld 1.0 SDK
-- container layout (verified against a CXX header dump of PalServer):
--   playerState:GetInventoryData()          -> UPalPlayerInventoryData  (same call items.lua uses to give)
--     .InventoryMultiHelper                  -> UPalItemContainerMultiHelper  (public UPROPERTY, 0x160)
--       .Containers                          -> TArray<UPalItemContainer*>    (public UPROPERTY)
--         container:Num()                    -> slot count (reflected UFunction)
--         container:Get(i)                   -> UPalItemSlot (0-based, reflected UFunction)
--           slot.ItemId.StaticId:ToString()  -> item code FName e.g. "Wood"  (FPalItemId.StaticId, BlueprintVisible)
--           slot.StackCount                  -> quantity (int32, BlueprintVisible)
-- Reference for the runtime path (UPalPlayerInventoryData->InventoryMultiHelper->
-- Containers[0]->Get(idx)->GetItemId()/GetStackCount()):
--   SoTMaulder/SoTMaulder-Palworld feature.cpp (IncrementInventoryItemCountByIndex),
--   SDK/Pal_classes.hpp (UPalItemContainer::Num/Get, UPalItemSlot::ItemId/StackCount),
--   SDK/Pal_structs.hpp (FPalItemId::StaticId). Give-path precedent: dkoz/AdminCommands
--   Scripts/modules/items.lua (playerState:GetInventoryData()).
--
-- Every reflected call is pcall-guarded with IsValid() checks (F17 lesson): a wrong
-- instance-method call raises a Lua-catchable error, never a native crash, so the
-- enumeration can never take the server down. Empty slots (StaticId "None", count 0)
-- are filtered out. code->English-name mapping is done bridge-side from the embedded
-- catalog, so this module only returns {code, count}.

local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Inventory = {}

-- Enumerate a player's inventory into a { [code] = count } table.
-- Never throws; returns an empty table on any failure.
local function EnumeratePlayerInventory(playerState)
    local items = {}

    local ok, err = pcall(function()
        -- Same resolution as the working give path (items.lua / dkoz AdminCommands).
        local inventoryData = playerState:GetInventoryData()
        if not (inventoryData and inventoryData:IsValid()) then
            logger:log(1, "[INVENTORY] GetInventoryData() returned nothing")
            return
        end

        local multiHelper = inventoryData.InventoryMultiHelper
        if not (multiHelper and multiHelper:IsValid()) then
            logger:log(3, "[INVENTORY] InventoryMultiHelper unavailable")
            return
        end

        local containers = multiHelper.Containers
        if not containers then
            logger:log(3, "[INVENTORY] Containers array unavailable")
            return
        end

        -- Iterate the TArray with the codebase idiom (guild.lua): ForEach + :get().
        if type(containers.ForEach) ~= "function" then
            logger:log(3, "[INVENTORY] Containers is not iterable (no ForEach)")
            return
        end

        containers:ForEach(function(_, containerWrapper)
            local container = containerWrapper:get()
            if not (container and container:IsValid()) then
                return
            end

            -- Slot count via the reflected UFunction Num(); fall back to a bound.
            local slotCount = 0
            pcall(function() slotCount = container:Num() end)
            if not slotCount or slotCount <= 0 then
                return
            end

            for slotIdx = 0, slotCount - 1 do
                local gotSlot, slot = pcall(function() return container:Get(slotIdx) end)
                if gotSlot and slot and slot:IsValid() then
                    -- Read code + count directly from the reflected properties.
                    -- Empty slots have StaticId "None" and StackCount 0, filtered below.
                    local code = nil
                    local count = 0
                    pcall(function() code = slot.ItemId.StaticId:ToString() end)
                    pcall(function() count = slot.StackCount end)

                    if code and code ~= "" and code ~= "None" and count and count > 0 then
                        items[code] = (items[code] or 0) + count
                    end
                end
            end
        end)
    end)

    if not ok then
        logger:log(1, "[INVENTORY] enumeration error: " .. tostring(err))
    end

    return items
end

-- Build the JSON items array from a { [code] = count } table.
local function ItemsToJson(items)
    local parts = {}
    for code, count in pairs(items) do
        -- Item codes are FName strings (alphanumeric + underscore) - JSON-safe.
        table.insert(parts, string.format('{"code":"%s","count":%d}', code, count))
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- POST an inventory response back to the bridge (always sent, even when empty,
-- so the bridge can clear the pending request).
local function SendInventoryResponse(bridgeHost, requestId, playerName, itemsJson)
    local json = string.format(
        '{"requestId":"%s","name":"%s","items":%s,"timestamp":"%s"}',
        requestId,
        Utils.EscapeJSON(playerName),
        itemsJson,
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    local jsonEscaped = json:gsub('"', '\\"')
    local curlCommand = string.format(
        'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/inventory-response',
        jsonEscaped,
        bridgeHost
    )

    local handle = io.popen(curlCommand .. ' 2>&1')
    if handle then
        local result = handle:read("*a")
        handle:close()
        logger:log(3, string.format("[INVENTORY] Sent response for request %s", requestId))
        return result
    end
    return nil
end

-- Poll the bridge for inventory requests and answer each one.
local function FetchInventoryRequests()
    if not config.EnableBridge then
        return
    end

    local success, err = pcall(function()
        local bridgeHost = config.BridgeURL:match("http://([^/]+)")
        if not bridgeHost then
            logger:log(1, "[INVENTORY] Could not extract bridge host from URL")
            return
        end

        local url = string.format('http://%s/inventory-queue', bridgeHost)
        local handle = io.popen(string.format('curl -s %s', url))
        if not handle then
            logger:log(1, "[INVENTORY] Failed to fetch inventory queue")
            return
        end
        local result = handle:read("*a")
        handle:close()

        if not result or result == "" or result == '{"requests":[]}' then
            return
        end

        -- Parse {"requests":[{"name":"...","requestId":"..."}]} (same shape as location).
        for playerName, requestId in result:gmatch('"name"%s*:%s*"([^"]+)"%s*,[^}]*"requestId"%s*:%s*"([^"]+)"') do
            logger:log(2, string.format("[INVENTORY] Processing request %s for player %s", requestId, playerName))

            local items = {}
            local playerFound = false

            local PlayersList = FindAllOf("PalPlayerCharacter")
            if PlayersList then
                for _, Player in ipairs(PlayersList) do
                    local matchName = nil
                    local matchState = nil
                    local extractOk = pcall(function()
                        if Player and Player:IsValid() and
                           Player.PlayerState and Player.PlayerState:IsValid() and
                           Player.PlayerState.PlayerNamePrivate then
                            matchName = Player.PlayerState.PlayerNamePrivate:ToString()
                            matchState = Player.PlayerState
                        end
                    end)

                    if extractOk and matchName and matchState and
                       matchName:lower() == playerName:lower() then
                        playerFound = true
                        items = EnumeratePlayerInventory(matchState)
                        break
                    end
                end
            else
                logger:log(1, "[INVENTORY] ERROR: FindAllOf returned nil")
            end

            if not playerFound then
                logger:log(1, string.format("[INVENTORY] Player '%s' not found online", playerName))
            end

            -- Always reply (empty array when not found / no items) to clear the request.
            local itemsJson = ItemsToJson(items)
            local count = 0
            for _ in pairs(items) do count = count + 1 end
            logger:log(2, string.format("[INVENTORY] Player %s: %d item stack(s)", playerName, count))
            SendInventoryResponse(bridgeHost, requestId, playerName, itemsJson)
        end
    end)

    if not success then
        logger:log(1, "[INVENTORY] Error fetching inventory requests: " .. tostring(err))
    end
end

-- Initialize inventory reading (on-demand poller).
function Inventory.Initialize()
    if not config.EnableInventoryTracking then
        logger:log(2, "[INVENTORY] Inventory reading is disabled in config")
        return
    end

    logger:log(2, "[INVENTORY] Starting on-demand inventory reader...")

    -- Poll the bridge for inventory requests every second (like items/location).
    LoopAsync(1000, function()
        FetchInventoryRequests()
        return false
    end)

    logger:log(2, "[INVENTORY] On-demand inventory reader started")
end

return Inventory
