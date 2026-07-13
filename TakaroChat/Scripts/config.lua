local config = {}

-- Takaro Bridge Settings
config.BridgeURL = "http://localhost:3001/chat"
config.EnableBridge = true

-- Logging Settings
config.EnableLogging = true
config.LogFile = "TakaroChat.log"
config.LogLevel = 3 -- 1=Errors only, 2=Info, 3=Debug

-- Message Filtering
config.BlacklistedPrefixes = {"/"} -- Don't send / commands (allow ! for Takaro)
config.MaxMessageLength = 500

-- Chat Categories (Palworld chat types)
-- 1 = Say (local), 2 = Guild, 3 = Global
config.SendCategories = {1, 2, 3} -- Which categories to send

-- Inventory Tracking
config.EnableInventoryTracking = false -- DISABLED - causes errors
config.InventoryUpdateInterval = 30 -- Send inventory updates every N seconds

return config
