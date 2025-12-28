-- Takaro Chat Bridge for Palworld v1.4.0-location-discovery
-- Modular bidirectional chat integration between Palworld, Takaro, and Discord

print("=== Takaro Chat Bridge v1.4.0-location-discovery ===")

-- Load configuration
local config = require("config")

-- Load utility functions
local Utils = require("utils")
local logger = Utils.Logger:new()

logger:log(2, "Loading TakaroChat modules...")

-- Load and initialize modules
-- Comment out any module to disable that feature

-- Chat integration (required for basic functionality)
local Chat = require("chat")
Chat.Initialize()

-- Player events (connect/disconnect/death)
local Events = require("events")
Events.Initialize()

-- Discord integration (bidirectional Discord <-> Game chat)
local Discord = require("discord")
Discord.Initialize()

-- Teleport system (player teleportation via bridge)
local Teleport = require("teleport")
Teleport.Initialize()

-- Location lookup system (get player positions with Z coordinate)
local Location = require("location")
Location.Initialize()

-- Deep Discovery (comprehensive inventory and guild data discovery)
local DeepDiscovery = require("deep_discovery")
DeepDiscovery.Initialize()

-- Inventory tracking (DISABLED - causes crashes)
-- Uncomment the lines below to enable (also set config.EnableInventoryTracking = true)
-- local Inventory = require("inventory")
-- Inventory.Initialize()

-- Status summary
print("")
print("==========================")
print("Status:")
print("  Bridge: " .. (config.EnableBridge and "Enabled" or "Disabled"))
print("  Discord Webhook: " .. (config.EnableDiscordWebhook and "Enabled" or "Disabled"))
print("  Discord->Game: " .. (config.EnableDiscordToGame and "Enabled" or "Disabled"))
print("  Logging: " .. (config.EnableLogging and "Enabled" or "Disabled"))
print("  Teleport: Enabled (coordinate + player-to-player)")
print("  Location Lookup: Enabled (full X/Y/Z coordinates)")
print("  Deep Discovery: Running (inventory + guild properties)")
print("==========================")
print("")

logger:log(2, "TakaroChat v1.4.0-location-discovery initialized successfully")
