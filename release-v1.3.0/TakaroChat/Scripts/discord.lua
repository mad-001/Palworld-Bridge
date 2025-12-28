-- Discord integration module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Discord = {}
local lastMessageId = nil

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

    -- Basic JSON parsing for messages
    for messageId, username, displayName, content in result:gmatch('"id":"(%d+)".-"username":"([^"]+)".-"global_name":"([^"]*)".-"content":"([^"]+)"') do
        if not lastMessageId or tonumber(messageId) > tonumber(lastMessageId) then
            lastMessageId = messageId

            -- Skip bot messages if configured
            if config.IgnoreBotMessages and result:match('"id":"' .. messageId .. '".-"bot":true') then
                goto continue
            end

            -- Check for blacklisted prefixes
            if Utils.IsBlacklisted(content) then
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

-- Initialize Discord integration
function Discord.Initialize()
    if config.EnableDiscordToGame then
        logger:log(2, "Starting Discord polling...")

        LoopAsync(config.DiscordPollInterval * 1000, function()
            local success, err = pcall(PollDiscord)
            if not success then
                logger:log(1, "Error polling Discord: " .. tostring(err))
            end
            return false
        end)

        logger:log(2, string.format("Discord polling started (every %ds)", config.DiscordPollInterval))
    end
end

return Discord
