# TakaroChat - Palworld Chat Integration

Bidirectional chat integration between Palworld, Takaro, and Discord.

## Features

- **Game → Takaro**: Send in-game chat to Takaro platform
- **Game → Discord**: Optional direct Discord webhook support
- **Discord → Game**: Optional polling to display Discord messages in-game
- **Logging**: File and console logging with configurable levels
- **Filtering**: Blacklist commands and control which chat categories to send

## Requirements

- Palworld dedicated server
- UE4SS (Unreal Engine Scripting System) installed
- Palworld-Takaro Bridge running
- curl (pre-installed on Windows 10/11)

## Installation

1. Copy the `TakaroChat` folder to your Palworld server's UE4SS mods directory:
   ```
   C:\...\PalServer\Pal\Binaries\Win64\ue4ss\Mods\TakaroChat\
   ```

2. Ensure `enabled.txt` exists in the mod folder

3. Configure the mod by editing `Scripts/config.lua`

4. Restart your Palworld server

## Configuration

Edit `Scripts/config.lua`:

### Bridge Settings
```lua
config.BridgeURL = "http://localhost:3001/chat"  -- Takaro bridge endpoint
config.EnableBridge = true                        -- Send to bridge
```

### Discord Webhook (Optional)
```lua
config.EnableDiscordWebhook = false
config.DiscordWebhookURL = "https://discord.com/api/webhooks/..."
```

### Discord to Game (Optional)
```lua
config.EnableDiscordToGame = false
config.DiscordBotToken = "your-bot-token"
config.DiscordChannelID = "your-channel-id"
config.DiscordPollInterval = 2                    -- Check every 2 seconds
config.DiscordMessageFormat = "[Discord] {name}: {message}"
```

### Logging
```lua
config.EnableLogging = true
config.LogFile = "TakaroChat.log"
config.LogLevel = 2  -- 1=Errors, 2=Info, 3=Debug
```

### Filtering
```lua
config.BlacklistedPrefixes = {"/", "!"}  -- Don't send commands
config.SendCategories = {1, 2, 3}        -- 1=Say, 2=Guild, 3=Global
config.MaxMessageLength = 500
```

## Chat Categories

Palworld has 3 chat types:
- **1 - Say**: Local chat (nearby players)
- **2 - Guild**: Guild/Team chat
- **3 - Global**: Server-wide chat

Configure which categories to send in `config.SendCategories`.

## How It Works

1. **Game Chat Hook**: Hooks into Palworld's chat system using UE4SS
2. **HTTP POST**: Sends chat to bridge at `http://localhost:3001/chat`
3. **Bridge**: Forwards chat to Takaro via WebSocket
4. **Takaro**: Displays chat in web dashboard and can route to Discord

### Chat Flow

```
Player → Game Chat → UE4SS Hook → HTTP POST → Bridge → Takaro → Discord
                                                              ↓
Discord Bot → HTTP Poll → Game Chat ←────────────────────────┘
```

## Troubleshooting

### Mod not loading
- Check `enabled.txt` exists
- Verify UE4SS is installed correctly
- Check server console for errors

### Chat not appearing in Takaro
- Verify bridge is running (`pm2 status palworld-bridge`)
- Check bridge logs: `pm2 logs palworld-bridge`
- Verify `config.BridgeURL` is correct
- Ensure port 3001 is accessible

### Discord webhook not working
- Verify webhook URL is correct
- Test webhook manually with curl
- Check mod logs in `TakaroChat.log`

## File Structure

```
TakaroChat/
├── enabled.txt          # Enables the mod
├── Scripts/
│   ├── main.lua        # Main mod logic
│   └── config.lua      # Configuration (edit this)
└── README.md           # This file
```

## Log Location

Logs are written to `TakaroChat.log` in the Palworld server directory:
```
C:\...\PalServer\TakaroChat.log
```

## Advanced: Discord Bot Setup

To enable Discord → Game chat:

1. Create Discord bot at https://discord.com/developers/applications
2. Enable "Message Content Intent" in bot settings
3. Copy bot token to `config.DiscordBotToken`
4. Get channel ID (enable Developer Mode in Discord, right-click channel, Copy ID)
5. Paste channel ID to `config.DiscordChannelID`
6. Set `config.EnableDiscordToGame = true`

## Performance

- **CPU**: Minimal (~0.1% per chat message)
- **Memory**: ~2-5 MB
- **Network**: Small HTTP POST per chat message

## Version

Version: 1.0.0
Compatible with: Palworld dedicated server

## License

MIT License

## Support

For issues or questions:
- Check Palworld-Takaro Bridge documentation
- Review logs in `TakaroChat.log`
- Verify UE4SS is working with other mods
