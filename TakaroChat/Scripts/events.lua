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

        local GameState = GameInstance.GameState
        if not GameState or not GameState:IsValid() then
            return
        end

        local PlayerArray = GameState.PlayerArray
        if not PlayerArray then
            return
        end

        for i = 1, PlayerArray:GetArrayNum() do
            local PlayerState = PlayerArray:GetArrayElement(i)
            if PlayerState and PlayerState:IsValid() then
                local PlayerName = PlayerState.PlayerNamePrivate:ToString()
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
local hooksRetriedForPlayer = false

local function CheckPlayerChanges()
    local currentPlayers = GetOnlinePlayers()

    -- The player Blueprint classes only exist once somebody has spawned, so the
    -- first time the poll sees a player, re-attempt any hook that could not be
    -- registered at boot (F17).
    if not hooksRetriedForPlayer and next(currentPlayers) ~= nil then
        hooksRetriedForPlayer = true
        if Events.RetryHooksNow then
            Events.RetryHooksNow("first-player-seen")
        end
    end

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

-- ---------------------------------------------------------------------------
-- Hook registration (F17)
--
-- UE4SS `RegisterHook` resolves the target by an exact UFunction object path
-- and throws a hard Lua error when nothing is found ("no UFunction with the
-- specified name was found"); the UFunction must already exist in memory at
-- the moment of the call (UE4SS docs, RegisterHook: "Any UFunction that you
-- attempt to register with RegisterHook must already exist in memory when you
-- register it."). v1.7.6 wrapped each call in a bare pcall, discarded the
-- error text and gave up after one attempt, which produced the observed
--   [ERROR] Warning: Could not register player connect/disconnect/death hook
-- at boot with no further detail and no recovery.
--
-- Two independent causes, both handled here:
--   1. Wrong path. ReceiveBeginPlay/ReceiveEndPlay are AActor Blueprint events
--      and are NOT reflected on /Script/Pal.PalPlayerState, and there is no
--      /Script/Pal.PalPlayerCharacter:OnDeath on Palworld 1.0. Candidate lists
--      below put the paths used by working Palworld 1.0 mods first and keep the
--      old v1.7.6 paths as fallbacks.
--   2. Not loaded yet. Blueprint player classes only exist once a player has
--      spawned, so a boot-time registration can never succeed. Every candidate
--      list is therefore retried on a timer and again on the first connect the
--      polling loop sees.
-- ---------------------------------------------------------------------------

local HOOK_RETRY_INTERVAL = 10000 -- ms between registration rounds
local HOOK_RETRY_ATTEMPTS = 30    -- 30 x 10 s = 5 minutes of retrying

local pendingHooks = {}           -- label -> { candidates, handler, mode, attempts, registered }

-- RegisterHook callbacks receive RemoteUnrealParam wrappers; a few UE4SS
-- versions hand the context over as a plain UObject instead. Accept both.
local function Deref(value)
    if type(value) == "userdata" and value.get then
        local ok, inner = pcall(function() return value:get() end)
        if ok and inner then
            return inner
        end
    end
    return value
end

local function PlayerNameFromState(playerState)
    if not (playerState and playerState:IsValid()) then
        return nil
    end
    local ok, name = pcall(function() return playerState.PlayerNamePrivate:ToString() end)
    if ok and name and name ~= "" then
        return name
    end
    return nil
end

local function PlayerNameFromCharacter(character)
    if not (character and character:IsValid()) then
        return nil
    end
    return PlayerNameFromState(character.PlayerState)
end

-- Try every not-yet-registered candidate of every pending hook once.
-- mode "first": stop at the first candidate that registers.
-- mode "all":   register every candidate that resolves (e.g. the male and
--               female player Blueprints are separate classes).
local function AttemptHookRound(trigger)
    local outstanding = 0

    for label, entry in pairs(pendingHooks) do
        if not entry.registered then
            entry.attempts = entry.attempts + 1
            for _, candidate in ipairs(entry.candidates) do
                if not candidate.registered then
                    local ok, err = pcall(function()
                        RegisterHook(candidate.path, entry.handler)
                    end)
                    if ok then
                        candidate.registered = true
                        logger:log(2, string.format(
                            "[HOOKS] Registered %s hook on %s (attempt %d, trigger: %s)",
                            label, candidate.path, entry.attempts, trigger))
                        if entry.mode == "first" then
                            entry.registered = true
                            break
                        end
                    else
                        candidate.lastError = tostring(err)
                        logger:log(3, string.format(
                            "[HOOKS] %s hook: %s not available (attempt %d): %s",
                            label, candidate.path, entry.attempts, candidate.lastError))
                    end
                end
            end

            if entry.mode == "all" then
                for _, candidate in ipairs(entry.candidates) do
                    if candidate.registered then
                        entry.registered = true
                    end
                end
                -- "all" is only finished once every candidate resolved.
                for _, candidate in ipairs(entry.candidates) do
                    if not candidate.registered then
                        entry.registered = false
                        break
                    end
                end
            end

            if not entry.registered then
                outstanding = outstanding + 1
                if entry.attempts >= HOOK_RETRY_ATTEMPTS and not entry.gaveUp then
                    entry.gaveUp = true
                    local details = {}
                    for _, candidate in ipairs(entry.candidates) do
                        table.insert(details, string.format("%s -> %s", candidate.path,
                            candidate.registered and "OK" or (candidate.lastError or "not found")))
                    end
                    logger:log(1, string.format(
                        "[HOOKS] Giving up on the %s hook after %d attempts: %s",
                        label, entry.attempts, table.concat(details, " | ")))
                end
            end
        end
    end

    return outstanding
end

local retryLoopRunning = false

local function ScheduleHookRetries()
    if retryLoopRunning then
        return
    end
    retryLoopRunning = true
    LoopAsync(HOOK_RETRY_INTERVAL, function()
        local outstanding = 0
        local ok, err = pcall(function()
            outstanding = AttemptHookRound("timer")
        end)
        if not ok then
            logger:log(1, "[HOOKS] Retry round failed: " .. tostring(err))
            return false
        end

        -- Stop the loop once everything registered or every entry gave up.
        local stillTrying = false
        for _, entry in pairs(pendingHooks) do
            if not entry.registered and not entry.gaveUp then
                stillTrying = true
            end
        end
        if not stillTrying then
            retryLoopRunning = false
            logger:log(2, string.format(
                "[HOOKS] Retry loop paused (%d hook group(s) still unregistered)", outstanding))
            return true -- stop looping
        end
        return false
    end)
end

-- Called by the polling loop when it sees the first player of a session: the
-- player Blueprint classes are guaranteed to be loaded at that point.
function Events.RetryHooksNow(reason)
    local ok, err = pcall(function()
        -- Give every still-missing hook a fresh attempt budget: a class that was
        -- absent at boot may well be loaded now.
        for _, entry in pairs(pendingHooks) do
            if not entry.registered then
                entry.attempts = 0
                entry.gaveUp = false
            end
        end
        AttemptHookRound(reason or "player-present")
        ScheduleHookRetries()
    end)
    if not ok then
        logger:log(1, "[HOOKS] Triggered retry failed: " .. tostring(err))
    end
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

    -- Player connect. /Script/Pal.PalPlayerCharacter:OnCompleteInitializeParameter
    -- is the path used by working Palworld 1.0 server mods for on-join logic;
    -- the v1.7.6 PalPlayerState:ReceiveBeginPlay path is kept as a fallback.
    pendingHooks["connect"] = {
        mode = "first",
        attempts = 0,
        candidates = {
            { path = "/Script/Pal.PalPlayerCharacter:OnCompleteInitializeParameter" },
            { path = "/Script/Pal.PalPlayerState:ReceiveBeginPlay" },
        },
        handler = function(context)
            local ok, err = pcall(function()
                local obj = Deref(context)
                -- Either a PalPlayerCharacter or (fallback path) a PalPlayerState.
                ExecuteWithDelay(1000, function()
                    local inner = pcall(function()
                        if not (obj and obj:IsValid()) then return end
                        local playerName = PlayerNameFromCharacter(obj) or PlayerNameFromState(obj)
                        if playerName then
                            -- Keep the poll from emitting the same connect again.
                            knownPlayers[playerName] = true
                            SendEventToBridge("player_connect", playerName, "{}")
                            logger:log(2, string.format("Player connected: %s", playerName))
                        end
                    end)
                    if not inner then
                        logger:log(1, "Error resolving connected player name")
                    end
                end)
            end)
            if not ok then
                logger:log(1, "Error in connect hook: " .. tostring(err))
            end
        end,
    }

    -- Player disconnect. ReceiveEndPlay is a Blueprint event, so it exists on the
    -- concrete BP_Player_* classes, not on /Script/Pal.PalPlayerState. Both the
    -- male and female player Blueprints must be hooked, and they only load once
    -- a player has spawned - hence mode "all" plus the retry loop.
    pendingHooks["disconnect"] = {
        mode = "all",
        attempts = 0,
        candidates = {
            { path = "/Game/Pal/Blueprint/Character/Player/Male/BP_Player_Male.BP_Player_Male_C:ReceiveEndPlay" },
            { path = "/Game/Pal/Blueprint/Character/Player/Female/BP_Player_Female.BP_Player_Female_C:ReceiveEndPlay" },
        },
        handler = function(context)
            local ok, err = pcall(function()
                local obj = Deref(context)
                local playerName = PlayerNameFromCharacter(obj) or PlayerNameFromState(obj)
                if playerName then
                    knownPlayers[playerName] = nil
                    SendEventToBridge("player_disconnect", playerName, "{}")
                    logger:log(2, string.format("Player disconnected: %s", playerName))
                end
            end)
            if not ok then
                logger:log(1, "Error in disconnect hook: " .. tostring(err))
            end
        end,
    }

    -- Player death. /Script/Pal.PalCharacter:OnDeadCharacter is the 1.0 death
    -- event; it fires for Pals too, so the handler only reports actors that
    -- carry a valid PlayerState. The v1.7.6 PalPlayerCharacter:OnDeath path is
    -- kept as a fallback.
    pendingHooks["death"] = {
        mode = "first",
        attempts = 0,
        candidates = {
            { path = "/Script/Pal.PalCharacter:OnDeadCharacter" },
            { path = "/Script/Pal.PalPlayerCharacter:OnDeath" },
        },
        handler = function(context, eventParam)
            local ok, err = pcall(function()
                local victim = nil

                -- OnDeadCharacter passes an FPalDeadInfo-like struct whose
                -- SelfActor is the dead character.
                if eventParam ~= nil then
                    local deadInfo = Deref(eventParam)
                    if deadInfo and deadInfo.SelfActor then
                        victim = deadInfo.SelfActor
                    end
                end

                -- Fallback path (PalPlayerCharacter:OnDeath): the context is the
                -- character itself.
                if not victim then
                    victim = Deref(context)
                end

                local playerName = PlayerNameFromCharacter(victim)
                if playerName then
                    SendEventToBridge("player_death", playerName, "{}")
                    logger:log(2, string.format("Player died: %s", playerName))
                else
                    logger:log(3, "[HOOKS] Death event without a PlayerState (Pal or NPC), ignored")
                end
            end)
            if not ok then
                logger:log(1, "Error in death hook: " .. tostring(err))
            end
        end,
    }

    -- First attempt immediately, then keep retrying in the background.
    AttemptHookRound("boot")
    ScheduleHookRetries()

    logger:log(2, "Player event hook registration started (retrying in the background)")
end

return Events
