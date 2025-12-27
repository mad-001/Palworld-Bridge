-- Player events module (connect/disconnect/death)
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Events = {}
local knownPlayers = {}
local playerCheckInterval = 10000 -- Check every 10 seconds

-- Send event to Takaro Bridge
local function SendEventToBridge(eventType, playerName, data)
    if not config.EnableBridge then
        return
    end

    local json = string.format(
        '{"type":"%s","playerName":"%s","timestamp":"%s","data":%s}',
        eventType,
        Utils.EscapeJSON(playerName),
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        data or "{}"
    )

    local command = string.format(
        'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
        json:gsub('"', '\\"'),
        config.BridgeURL
    )

    os.execute('start /B "" ' .. command .. ' >nul 2>&1')
    logger:log(2, string.format("Event %s: %s", eventType, playerName))
end

-- Get list of online players
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

-- Check for player changes (connect/disconnect)
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

-- Initialize player events
function Events.Initialize()
    logger:log(2, "Initializing player event monitoring...")

    -- Start player monitoring loop
    ExecuteWithDelay(5000, function()
        -- Initial player list
        knownPlayers = GetOnlinePlayers()
        logger:log(2, "Player monitoring started")

        -- Set up recurring check
        LoopAsync(playerCheckInterval, function()
            CheckPlayerChanges()
            return false  -- Continue looping
        end)
    end)

    -- Hook player state creation (player connect)
    local connectHookSuccess = pcall(function()
        RegisterHook("/Script/Pal.PalPlayerState:ReceiveBeginPlay", function(playerState)
            local success, err = pcall(function()
                if playerState and playerState:IsValid() then
                    ExecuteWithDelay(1000, function()
                        if playerState:IsValid() then
                            local playerName = playerState:get().PlayerNamePrivate:ToString()
                            if playerName and playerName ~= "" then
                                SendEventToBridge("player_connect", playerName, "{}")
                                logger:log(2, string.format("Player connected: %s", playerName))
                            end
                        end
                    end)
                end
            end)

            if not success then
                logger:log(1, "Error in connect hook: " .. tostring(err))
            end
        end)
    end)

    if connectHookSuccess then
        logger:log(2, "Registered player connect hook")
    else
        logger:log(1, "Warning: Could not register player connect hook")
    end

    -- Hook player state destruction (player disconnect)
    local disconnectHookSuccess = pcall(function()
        RegisterHook("/Script/Pal.PalPlayerState:ReceiveEndPlay", function(playerState, reason)
            local success, err = pcall(function()
                if playerState and playerState:IsValid() then
                    local playerName = playerState:get().PlayerNamePrivate:ToString()
                    if playerName and playerName ~= "" then
                        SendEventToBridge("player_disconnect", playerName, "{}")
                        logger:log(2, string.format("Player disconnected: %s", playerName))
                    end
                end
            end)

            if not success then
                logger:log(1, "Error in disconnect hook: " .. tostring(err))
            end
        end)
    end)

    if disconnectHookSuccess then
        logger:log(2, "Registered player disconnect hook")
    else
        logger:log(1, "Warning: Could not register player disconnect hook")
    end

    -- Hook player death
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
                logger:log(1, "Error in death hook: " .. tostring(err))
            end
        end)
    end)

    if deathHookSuccess then
        logger:log(2, "Registered death hook")
    else
        logger:log(1, "Warning: Could not register player death hook")
    end

    logger:log(2, "Player event hooks registration complete")
end

return Events
