local config = {}

-- Takaro Bridge Settings
config.BridgeURL = "http://localhost:3001/chat"
config.EnableBridge = true

-- Discord Webhook Settings (optional - sends directly to Discord)
config.EnableDiscordWebhook = false
config.DiscordWebhookURL = "" -- Your Discord webhook URL

-- Discord to Game Settings
config.EnableDiscordToGame = false
config.DiscordBotToken = "" -- Discord bot token
config.DiscordChannelID = "" -- Discord channel ID
config.DiscordPollInterval = 2 -- Check Discord every N seconds
config.DiscordMessageFormat = "[Discord] {name}: {message}"

-- Logging Settings
config.EnableLogging = true
config.LogFile = "TakaroChat.log"
config.LogLevel = 2 -- 1=Errors only, 2=Info, 3=Debug

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
