-- Shared utilities for TakaroChat
local config = require("config")

local Utils = {}

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

Utils.Logger = Logger

-- Check if message should be filtered
function Utils.IsBlacklisted(message)
    for _, prefix in ipairs(config.BlacklistedPrefixes) do
        if string.sub(message, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- Check if category should be sent
function Utils.ShouldSendCategory(category)
    for _, cat in ipairs(config.SendCategories) do
        if cat == category then
            return true
        end
    end
    return false
end

-- Escape string for JSON
function Utils.EscapeJSON(str)
    return str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
end

return Utils
