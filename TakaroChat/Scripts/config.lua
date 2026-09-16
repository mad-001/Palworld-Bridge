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

-- Inventory Reading (F22)
-- On-demand only: the bridge POSTs an inventory request, the Lua enumerates the
-- player's containers once and replies once (like teleport/location/items). This
-- flag gates ONLY that on-demand poller. The old periodic every-N-seconds push
-- loop - the thing that spammed "[INVENTORY] Error updating inventories" and got
-- this disabled - is gone, so enabling this no longer reintroduces the errors.
config.EnableInventoryTracking = true

return config
