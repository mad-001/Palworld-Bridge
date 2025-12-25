-- Takaro Chat Bridge for Palworld
-- Bidirectional chat integration between Palworld, Takaro, and Discord

local config = require("config")

print("=== Takaro Chat Bridge ===")

-- Logging module
local Logger = {}
function Logger:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Logger:log(level, message)
    if config.EnableLogging and level <= config.LogLevel then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local logLevels = {"ERROR", "INFO", "DEBUG"}
        local logMessage = string.format("[%s] [%s] %s\n", timestamp, logLevels[level] or "UNKNOWN", message)

        print(logMessage)

        -- Write to file
        if config.LogFile then
            local file = io.open(config.LogFile, "a")
            if file then
                file:write(logMessage)
                file:close()
            end
        end
    end
end

local logger = Logger:new()

-- Check if message should be filtered
local function IsBlacklisted(message)
    for _, prefix in ipairs(config.BlacklistedPrefixes) do
        if string.sub(message, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- Check if category should be sent
local function ShouldSendCategory(category)
    for _, cat in ipairs(config.SendCategories) do
        if cat == category then
            return true
        end
    end
    return false
end

-- Escape string for JSON
local function EscapeJSON(str)
    return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
end

-- Send chat to Takaro Bridge
local function SendToBridge(playerName, message, category)
    if not config.EnableBridge then
        return
    end

    local categoryNames = {"Say", "Guild", "Global"}
    local json = string.format(
        '{"type":"chat","playerName":"%s","message":"%s","category":%d,"categoryName":"%s","timestamp":"%s"}',
        EscapeJSON(playerName),
        EscapeJSON(message),
        category,
        categoryNames[category] or "Unknown",
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute(command .. " >nul 2>&1 &")
    logger:log(3, string.format("Sent to bridge: %s: %s", playerName, message))
end

-- Send event to Takaro Bridge
local function SendEventToBridge(eventType, playerName, data)
    if not config.EnableBridge then
        return
    end

    local json = string.format(
        '{"type":"%s","playerName":"%s","timestamp":"%s","data":%s}',
        eventType,
        EscapeJSON(playerName),
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        data or "{}"
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute(command .. " >nul 2>&1 &")
    logger:log(2, string.format("Event %s: %s", eventType, playerName))
end

-- Send to Discord webhook
local function SendToDiscord(playerName, message, category)
    if not config.EnableDiscordWebhook or config.DiscordWebhookURL == "" then
        return
    end

    local categoryNames = {"Say", "Guild", "Global"}
    local categoryEmojis = {"💬", "🏰", "🌍"}

    local discordJson = string.format(
        '{"content":"%s **[%s]** %s: %s"}',
        categoryEmojis[category] or "📢",
        categoryNames[category] or "Unknown",
        EscapeJSON(playerName),
        EscapeJSON(message)
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        discordJson:gsub('"', '\\"'),
        config.DiscordWebhookURL
    )

    os.execute(command .. " >nul 2>&1 &")
    logger:log(3, string.format("Sent to Discord: %s: %s", playerName, message))
end

-- Inject message into game chat
local function InjectGameMessage(message, category)
    category = category or 3 -- Default to Global

    -- Get local player
    local localPlayer = FindFirstOf("PalPlayerCharacter")
    if not localPlayer or not localPlayer:IsValid() then
        logger:log(1, "Failed to inject message: No local player found")
        return false
    end

    local playerState = localPlayer:get().PlayerState
    if not playerState or not playerState:IsValid() then
        logger:log(1, "Failed to inject message: No player state")
        return false
    end

    -- Create chat message object
    local chatMessage = {
        Message = message,
        Category = category
    }

    -- Try to call the chat function
    local success = pcall(function()
        playerState:EnterChat_Receive(chatMessage)
    end)

    if success then
        logger:log(3, string.format("Injected to game: %s", message))
        return true
    else
        logger:log(1, "Failed to inject message to game")
        return false
    end
end

-- Poll Discord for new messages
local lastMessageId = nil
local function PollDiscord()
    if not config.EnableDiscordToGame or config.DiscordBotToken == "" or config.DiscordChannelID == "" then
        return
    end

    local url = string.format(
        "https://discord.com/api/v10/channels/%s/messages?limit=5",
        config.DiscordChannelID
    )

    if lastMessageId then
        url = url .. "&after=" .. lastMessageId
    end

    local command = string.format(
        'curl -s -H "Authorization: Bot %s" "%s"',
        config.DiscordBotToken,
        url
    )

    -- Execute and capture output
    local handle = io.popen(command)
    if not handle then
        logger:log(1, "Failed to poll Discord: Could not execute curl")
        return
    end

    local result = handle:read("*a")
    handle:close()

    if not result or result == "" then
        return
    end

    -- Basic JSON parsing for messages (simple implementation)
    -- This is a simplified parser - in production you'd want a proper JSON library
    for messageId, username, displayName, content in result:gmatch('"id":"(%d+)".-"username":"([^"]+)".-"global_name":"([^"]*)".-"content":"([^"]+)"') do
        if not lastMessageId or tonumber(messageId) > tonumber(lastMessageId) then
            lastMessageId = messageId

            -- Skip bot messages if configured
            if config.IgnoreBotMessages and result:match('"id":"' .. messageId .. '".-"bot":true') then
                goto continue
            end

            -- Check for blacklisted prefixes
            if IsBlacklisted(content) then
                goto continue
            end

            -- Format message
            local formattedMessage = config.DiscordMessageFormat
                :gsub("{name}", displayName ~= "" and displayName or username)
                :gsub("{username}", username)
                :gsub("{message}", content)

            -- Inject into game
            InjectGameMessage(formattedMessage, config.DiscordToGameChannel or 3)
            logger:log(2, string.format("Discord -> Game: %s", formattedMessage))
        end
        ::continue::
    end
end

-- Hook into game chat
logger:log(2, "Registering chat hook...")

RegisterHook("/Script/Pal.PalPlayerState:EnterChat_Receive", function(playerState, chatData)
    local success, err = pcall(function()
        local message = chatData:get().Message:ToString()
        local category = chatData:get().Category
        local playerName = playerState:get().PlayerNamePrivate:ToString()

        -- Log the chat
        logger:log(2, string.format("[%d] %s: %s", category, playerName, message))

        -- Check for connect messages (system messages when players join)
        -- Palworld format: "PlayerName joined the server."
        if message:match("joined the server") then
            -- Extract player name from the message
            local connectPlayerName = message:match("^(.+) joined the server")

            if connectPlayerName then
                logger:log(2, string.format("Detected connect via chat: %s", connectPlayerName))
                SendEventToBridge("player_connect", connectPlayerName, "{}")
                return -- Don't send as chat message
            end
        end

        -- Check for disconnect messages (system messages when players leave)
        -- Palworld format: "PlayerName left the server."
        if message:match("left the server") then
            -- Extract player name from the message
            local disconnectPlayerName = message:match("^(.+) left the server")

            if disconnectPlayerName then
                logger:log(2, string.format("Detected disconnect via chat: %s", disconnectPlayerName))
                SendEventToBridge("player_disconnect", disconnectPlayerName, "{}")
                return -- Don't send as chat message
            end
        end

        -- Check filters
        if IsBlacklisted(message) then
            logger:log(3, "Message blacklisted (command prefix)")
            return
        end

        if not ShouldSendCategory(category) then
            logger:log(3, "Category not in send list")
            return
        end

        if #message > config.MaxMessageLength then
            logger:log(3, "Message too long, truncating")
            message = string.sub(message, 1, config.MaxMessageLength) .. "..."
        end

        -- Send to configured destinations
        SendToBridge(playerName, message, category)
        SendToDiscord(playerName, message, category)
    end)

    if not success then
        logger:log(1, "Error in chat hook: " .. tostring(err))
    end
end)

logger:log(2, "Chat hook registered successfully")

-- Player tracking for join/leave detection
local knownPlayers = {}
local playerCheckInterval = 5000 -- Check every 5 seconds

-- Function to get current online players
local function GetOnlinePlayers()
    local players = {}
    local success, err = pcall(function()
        local GameInstance = FindFirstOf("PalGameInstance")
        if not GameInstance or not GameInstance:IsValid() then
            return
        end

        local GameState = GameInstance:get().GameState
        if not GameState or not GameState:IsValid() then
            return
        end

        local PlayerArray = GameState:get().PlayerArray
        if not PlayerArray then
            return
        end

        for i = 1, PlayerArray:GetArrayNum() do
            local PlayerState = PlayerArray:GetArrayElement(i)
            if PlayerState and PlayerState:IsValid() then
                local PlayerName = PlayerState:get().PlayerNamePrivate:ToString()
                if PlayerName and PlayerName ~= "" then
                    players[PlayerName] = true
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error getting online players: " .. tostring(err))
    end

    return players
end

-- Function to check for player changes
local function CheckPlayerChanges()
    local currentPlayers = GetOnlinePlayers()

    -- Check for new players (joined)
    for playerName, _ in pairs(currentPlayers) do
        if not knownPlayers[playerName] then
            SendEventToBridge("player_connect", playerName, "{}")
            logger:log(2, string.format("Player joined: %s", playerName))
        end
    end

    -- Check for disconnected players (left)
    for playerName, _ in pairs(knownPlayers) do
        if not currentPlayers[playerName] then
            SendEventToBridge("player_disconnect", playerName, "{}")
            logger:log(2, string.format("Player left: %s", playerName))
        end
    end

    -- Update known players list
    knownPlayers = currentPlayers
end

-- Start player monitoring loop
ExecuteWithDelay(5000, function()
    -- Initial player list
    knownPlayers = GetOnlinePlayers()
    logger:log(2, "Player monitoring started - initial player count: " .. tostring(#knownPlayers))

    -- Set up recurring check
    LoopAsync(playerCheckInterval, function()
        CheckPlayerChanges()
        return false  -- Continue looping
    end)
end)

logger:log(2, "Player join/leave monitoring initialized")

-- Hook player state creation (player connect)
local connectHookSuccess = pcall(function()
    RegisterHook("/Script/Pal.PalPlayerState:ReceiveBeginPlay", function(playerState)
        local success, err = pcall(function()
            if playerState and playerState:IsValid() then
                -- Small delay to ensure PlayerNamePrivate is set
                ExecuteWithDelay(1000, function()
                    local nameSuccess, playerName = pcall(function()
                        return playerState:get().PlayerNamePrivate:ToString()
                    end)

                    if nameSuccess and playerName and playerName ~= "" then
                        SendEventToBridge("player_connect", playerName, "{}")
                        logger:log(2, string.format("Player connected (BeginPlay): %s", playerName))
                    end
                end)
            end
        end)

        if not success then
            logger:log(1, "Error in player connect hook callback: " .. tostring(err))
        end
    end)
end)

if connectHookSuccess then
    logger:log(2, "Registered player connect hook (BeginPlay)")
else
    logger:log(1, "Warning: Could not register player connect hook")
end

-- Hook player state destruction (player disconnect)
local disconnectHookSuccess = pcall(function()
    RegisterHook("/Script/Pal.PalPlayerState:ReceiveEndPlay", function(playerState, reason)
        local success, err = pcall(function()
            if playerState and playerState:IsValid() then
                local nameSuccess, playerName = pcall(function()
                    return playerState:get().PlayerNamePrivate:ToString()
                end)

                if nameSuccess and playerName and playerName ~= "" then
                    SendEventToBridge("player_disconnect", playerName, "{}")
                    logger:log(2, string.format("Player disconnected (EndPlay): %s", playerName))
                end
            end
        end)

        if not success then
            logger:log(1, "Error in player disconnect hook callback: " .. tostring(err))
        end
    end)
end)

if disconnectHookSuccess then
    logger:log(2, "Registered player disconnect hook (EndPlay)")
else
    logger:log(1, "Warning: Could not register player disconnect hook")
end

-- Hook player death events
local deathHookSuccess = pcall(function()
    RegisterHook("/Script/Pal.PalPlayerCharacter:OnDeath", function(character)
        local success, err = pcall(function()
            if character and character:IsValid() then
                local playerState = character:get().PlayerState
                if playerState and playerState:IsValid() then
                    local playerName = playerState:get().PlayerNamePrivate:ToString()
                    if playerName and playerName ~= "" then
                        SendEventToBridge("player_death", playerName, "{}")
                        logger:log(2, string.format("Player died: %s", playerName))
                    end
                end
            end
        end)

        if not success then
            logger:log(1, "Error in player death hook callback: " .. tostring(err))
        end
    end)
end)

if deathHookSuccess then
    logger:log(2, "Registered death hook")
else
    logger:log(1, "Warning: Could not register player death hook")
end

logger:log(2, "Player event hooks registration complete")

-- Send inventory data to bridge
local function SendInventoryToBridge(playerName, inventoryData)
    if not config.EnableBridge then
        return
    end

    local json = string.format(
        '{"type":"inventory","playerName":"%s","timestamp":"%s","inventory":%s}',
        EscapeJSON(playerName),
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        inventoryData
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute(command .. " >nul 2>&1 &")
    logger:log(3, string.format("Sent inventory for: %s", playerName))
end

-- Get player inventory and send to bridge
local function UpdatePlayerInventories()
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

                    -- Try to get inventory container
                    local inventoryComponent = player:get().InventoryComponent
                    if inventoryComponent and inventoryComponent:IsValid() then
                        local items = {}
                        local container = inventoryComponent:get().Container

                        if container and container:IsValid() then
                            -- Iterate through inventory slots
                            local slots = container:get().Slots
                            if slots then
                                for i = 0, 50 do -- Max 50 slots
                                    local success2, slot = pcall(function() return slots[i] end)
                                    if success2 and slot and slot:IsValid() then
                                        local itemData = slot:get().ItemData
                                        if itemData and itemData:IsValid() then
                                            local staticId = itemData:get().ItemStaticId
                                            local count = itemData:get().Count

                                            if staticId and count and count > 0 then
                                                table.insert(items, string.format(
                                                    '{"id":"%s","count":%d,"slot":%d}',
                                                    tostring(staticId),
                                                    count,
                                                    i
                                                ))
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        local inventoryJson = "[" .. table.concat(items, ",") .. "]"
                        SendInventoryToBridge(playerName, inventoryJson)
                    end
                end
            end
        end
    end)

    if not success then
        logger:log(1, "Error updating inventories: " .. tostring(err))
    end
end

-- Start inventory tracking if enabled
if config.EnableInventoryTracking then
    logger:log(2, "Starting inventory tracking...")

    LoopAsync(config.InventoryUpdateInterval * 1000, function()
        UpdatePlayerInventories()
        return false
    end)

    logger:log(2, string.format("Inventory tracking started (every %ds)", config.InventoryUpdateInterval))
end

-- Start Discord polling if enabled
if config.EnableDiscordToGame then
    logger:log(2, "Starting Discord polling...")

    LoopAsync(config.DiscordPollInterval * 1000, function()
        local success, err = pcall(PollDiscord)
        if not success then
            logger:log(1, "Error polling Discord: " .. tostring(err))
        end
        return false
    end)

    logger:log(2, "Discord polling started")
end

print("Status:")
print("  Bridge: " .. (config.EnableBridge and "Enabled" or "Disabled"))
print("  Discord Webhook: " .. (config.EnableDiscordWebhook and "Enabled" or "Disabled"))
print("  Discord->Game: " .. (config.EnableDiscordToGame and "Enabled" or "Disabled"))
print("  Logging: " .. (config.EnableLogging and "Enabled" or "Disabled"))
print("==========================")
