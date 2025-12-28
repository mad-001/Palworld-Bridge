-- Chat integration module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Chat = {}

-- Send chat to Takaro Bridge
local function SendToBridge(playerName, message, category)
    if not config.EnableBridge then
        return
    end

    local categoryNames = {"Say", "Guild", "Global"}
    local json = string.format(
        '{"type":"chat","playerName":"%s","message":"%s","category":%d,"categoryName":"%s","timestamp":"%s"}',
        Utils.EscapeJSON(playerName),
        Utils.EscapeJSON(message),
        category,
        categoryNames[category] or "Unknown",
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute('start /B "" ' .. command .. ' >nul 2>&1')
    logger:log(3, string.format("Sent to bridge: %s: %s", playerName, message))
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
        Utils.EscapeJSON(playerName),
        Utils.EscapeJSON(message)
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        discordJson:gsub('"', '\\"'),
        config.DiscordWebhookURL
    )

    os.execute('start /B "" ' .. command .. ' >nul 2>&1')
    logger:log(3, string.format("Sent to Discord: %s: %s", playerName, message))
end

-- Initialize chat hooks
function Chat.Initialize()
    logger:log(2, "Registering chat hook...")

    RegisterHook("/Script/Pal.PalPlayerState:EnterChat_Receive", function(playerState, chatData)
        local success, err = pcall(function()
            local message = chatData:get().Message:ToString()
            local category = chatData:get().Category
            local playerName = playerState:get().PlayerNamePrivate:ToString()

            -- Log the chat
            logger:log(2, string.format("[%d] %s: %s", category, playerName, message))

            -- Skip blacklisted messages
            if Utils.IsBlacklisted(message) then
                return
            end

            -- Only send if category is enabled
            if not Utils.ShouldSendCategory(category) then
                return
            end

            -- Send to bridge
            SendToBridge(playerName, message, category)

            -- Send to Discord webhook
            SendToDiscord(playerName, message, category)
        end)

        if not success then
            logger:log(1, "Error in chat hook: " .. tostring(err))
        end
    end)

    logger:log(2, "Chat hook registered")
end

return Chat
