-- Guild data module
local config = require("config")
local Utils = require("utils")
local logger = Utils.Logger:new()

local Guild = {}

-- Send guild data to bridge
local function SendGuildDataToBridge(guildData)
    if not config.EnableBridge then
        return
    end

    local bridgeHost = config.BridgeURL:match("http://([^/]+)")
    if not bridgeHost then
        logger:log(1, "[GUILD] Could not extract bridge host from URL")
        return
    end

    local json = string.format(
        '{"type":"guild","timestamp":"%s","guilds":%s}',
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        guildData
    )

    local jsonEscaped = json:gsub('"', '\\"')
    local curlCommand = string.format(
        'curl -s -m 3 -X POST -H "Content-Type: application/json" -d "%s" http://%s/guild-data',
        jsonEscaped,
        bridgeHost
    )

    local handle = io.popen(curlCommand .. ' 2>&1')
    if handle then
        local result = handle:read("*a")
        local success = handle:close()

        if success and result:match('"success"%s*:%s*true') then
            logger:log(3, "[GUILD] Sent guild data successfully")
        else
            logger:log(1, string.format("[GUILD] Failed to send guild data: %s", result))
        end
    end
end

-- Get all guild data
local function GetAllGuilds()
    local success, err = pcall(function()
        -- Find game state
        local GameState = FindFirstOf("PalGameStateInGame")
        if not GameState or not GameState:IsValid() then
            logger:log(1, "[GUILD] Could not find PalGameStateInGame")
            return
        end

        logger:log(3, "[GUILD] Found GameState")

        -- Discover all properties on GameState
        local GameStateClass = GameState:GetClass()
        local foundProperties = {}
        if GameStateClass and GameStateClass:IsValid() then
            GameStateClass:ForEachProperty(function(Property)
                local propName = Property:GetFName():ToString()
                table.insert(foundProperties, propName)
                -- Look for guild-related properties
                if propName:lower():find("guild") or propName:lower():find("group") then
                    logger:log(2, string.format("[GUILD] Found potential guild property: %s", propName))
                end
            end)
        end

        logger:log(3, string.format("[GUILD] GameState has %d properties total", #foundProperties))

        -- Try different property names for guild manager
        local GuildManager = nil
        local possibleNames = {"GroupGuildManager", "GuildManager", "GroupManager", "GuildManageComponent", "GroupManager_Component"}

        for _, propName in ipairs(possibleNames) do
            local propSuccess, manager = pcall(function() return GameState[propName] end)
            if propSuccess and manager and (type(manager) == "table" or type(manager) == "userdata") then
                if type(manager.IsValid) == "function" and manager:IsValid() then
                    GuildManager = manager
                    logger:log(2, string.format("[GUILD] Found GuildManager via property: %s", propName))
                    break
                elseif type(manager.IsValid) ~= "function" then
                    -- Might be a valid object without IsValid method
                    GuildManager = manager
                    logger:log(2, string.format("[GUILD] Found potential GuildManager via property: %s (no IsValid method)", propName))
                    break
                end
            end
        end

        if not GuildManager then
            logger:log(1, "[GUILD] Could not get GuildManager from any known property")
            return
        end

        -- Discover properties on GuildManager
        if type(GuildManager.GetClass) == "function" then
            local GuildManagerClass = GuildManager:GetClass()
            if GuildManagerClass and GuildManagerClass:IsValid() then
                logger:log(3, "[GUILD] Discovering GuildManager properties...")
                GuildManagerClass:ForEachProperty(function(Property)
                    local propName = Property:GetFName():ToString()
                    logger:log(3, string.format("[GUILD] GuildManager property: %s (type: %s)",
                        propName, Property:GetClass():GetFName():ToString()))
                end)
            end
        end

        -- Get guilds array
        local Guilds = nil
        local guildArrayNames = {"Guilds", "Groups", "GuildMap", "GuildArray"}

        for _, arrayName in ipairs(guildArrayNames) do
            local arraySuccess, guilds = pcall(function() return GuildManager[arrayName] end)
            if arraySuccess and guilds then
                Guilds = guilds
                logger:log(2, string.format("[GUILD] Found guilds via property: %s", arrayName))
                break
            end
        end

        if not Guilds then
            logger:log(1, "[GUILD] Could not get Guilds array from any known property")
            return
        end

        local guildsJson = {}
        local guildCount = 0

        -- Iterate through guilds
        if type(Guilds.ForEach) == "function" then
            Guilds:ForEach(function(Index, GuildWrapper)
                local guild = GuildWrapper:get()
                if guild and guild:IsValid() then
                    guildCount = guildCount + 1

                    local guildInfo = {
                        guild_id = "unknown",
                        guild_name = "unnamed",
                        admin_player_uid = "unknown",
                        member_count = 0,
                        members = {}
                    }

                    -- Try to get guild ID
                    local idSuccess, guildId = pcall(function() return guild.GroupId:ToString() end)
                    if idSuccess and guildId then
                        guildInfo.guild_id = guildId
                    end

                    -- Try to get guild name
                    local nameSuccess, guildName = pcall(function() return guild.GroupName:ToString() end)
                    if nameSuccess and guildName then
                        guildInfo.guild_name = guildName
                    end

                    -- Try to get admin UID
                    local adminSuccess, adminUid = pcall(function() return guild.AdminPlayerUId:ToString() end)
                    if adminSuccess and adminUid then
                        guildInfo.admin_player_uid = adminUid
                    end

                    -- Try to get members
                    local membersSuccess, members = pcall(function() return guild.Players end)
                    if membersSuccess and members and type(members.ForEach) == "function" then
                        members:ForEach(function(MemberIndex, MemberWrapper)
                            local member = MemberWrapper:get()
                            if member and member:IsValid() then
                                local memberInfo = {
                                    player_uid = "unknown",
                                    player_name = "unknown"
                                }

                                local uidSuccess, uid = pcall(function() return member.PlayerUId:ToString() end)
                                if uidSuccess and uid then
                                    memberInfo.player_uid = uid
                                end

                                local nameSuccess, name = pcall(function() return member.PlayerName:ToString() end)
                                if nameSuccess and name then
                                    memberInfo.player_name = name
                                end

                                guildInfo.member_count = guildInfo.member_count + 1
                                table.insert(guildInfo.members, memberInfo)
                            end
                        end)
                    end

                    table.insert(guildsJson, guildInfo)
                end
            end)
        end

        logger:log(2, string.format("[GUILD] Found %d guilds", guildCount))

        if guildCount > 0 then
            -- Convert to JSON manually (simple version)
            local jsonParts = {}
            for _, guildInfo in ipairs(guildsJson) do
                local membersParts = {}
                for _, member in ipairs(guildInfo.members) do
                    table.insert(membersParts, string.format(
                        '{"player_uid":"%s","player_name":"%s"}',
                        Utils.EscapeJSON(member.player_uid),
                        Utils.EscapeJSON(member.player_name)
                    ))
                end
                local membersJson = "[" .. table.concat(membersParts, ",") .. "]"

                table.insert(jsonParts, string.format(
                    '{"guild_id":"%s","guild_name":"%s","admin_player_uid":"%s","member_count":%d,"members":%s}',
                    Utils.EscapeJSON(guildInfo.guild_id),
                    Utils.EscapeJSON(guildInfo.guild_name),
                    Utils.EscapeJSON(guildInfo.admin_player_uid),
                    guildInfo.member_count,
                    membersJson
                ))
            end

            local finalJson = "[" .. table.concat(jsonParts, ",") .. "]"
            SendGuildDataToBridge(finalJson)
        end
    end)

    if not success then
        logger:log(1, "[GUILD] Error getting guild data: " .. tostring(err))
    end
end

-- Initialize guild tracking
function Guild.Initialize()
    logger:log(2, "[GUILD] Starting guild data tracking...")

    -- Update guild data every 30 seconds
    LoopAsync(30000, function()
        GetAllGuilds()
        return false
    end)

    logger:log(2, "[GUILD] Guild tracking started (every 30s)")
end

return Guild
