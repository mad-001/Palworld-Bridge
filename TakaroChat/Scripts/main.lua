-- Takaro Chat Bridge for Palworld v1.5.0
-- Modular bidirectional chat integration between Palworld, Takaro, and Discord
-- Features: Chat, Events, Discord, Teleport, Location, Items, Inventory

print("=== Takaro Chat Bridge v1.5.0 ===")

-- Load configuration
local config = require("config")

-- Load utility functions
local Utils = require("utils")
local logger = Utils.Logger:new()

logger:log(2, "Loading TakaroChat modules...")

-- Load and initialize modules
-- Comment out any module to disable that feature
-- Each module is initialized independently: a failure in one (e.g. a game
-- update changing a hooked function) is logged and skipped, so it can never
-- abort the whole mod and take the other features down with it.
local function safeInit(name, mod)
    local ok, err = pcall(function() mod.Initialize() end)
    if not ok then
        logger:log(1, string.format("[%s] Initialize failed (skipped): %s", name, tostring(err)))
    end
end

-- Chat integration (required for basic functionality)
local Chat = require("chat")
safeInit("Chat", Chat)

-- Player events (connect/disconnect/death)
local Events = require("events")
safeInit("Events", Events)

-- Discord integration (bidirectional Discord <-> Game chat)
local Discord = require("discord")
safeInit("Discord", Discord)

-- Teleport system (player teleportation via bridge)
local Teleport = require("teleport")
safeInit("Teleport", Teleport)

-- Location lookup system (get player positions with Z coordinate)
local Location = require("location")
safeInit("Location", Location)

-- Item giving system (allows giving items to players via bridge)
local Items = require("items")
safeInit("Items", Items)

-- Inventory tracking (Fixed - now uses PlayerState:GetInventoryData)
-- Enable in config.lua by setting config.EnableInventoryTracking = true
local Inventory = require("inventory")
safeInit("Inventory", Inventory)

-- Guild data tracking (DISABLED - unable to get guild info, causes crashes)
-- local Guild = require("guild")
-- Guild.Initialize()

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
print("  Item Giving: Enabled (via bridge API)")
print("  Inventory Tracking: " .. (config.EnableInventoryTracking and "Enabled" or "Disabled"))
print("  Guild Tracking: Disabled (unable to retrieve)")
print("==========================")
print("")

logger:log(2, "TakaroChat v1.5.0 initialized successfully")
