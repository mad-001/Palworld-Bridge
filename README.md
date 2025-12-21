# Palworld-Takaro Bridge

🦖 Connect your Palworld dedicated server to the Takaro game server management platform.

[![GitHub release](https://img.shields.io/github/v/release/mad-001/Palworld-Bridge)](https://github.com/mad-001/Palworld-Bridge/releases/latest)
[![License](https://img.shields.io/github/license/mad-001/Palworld-Bridge)](LICENSE)

## 🌟 Features

- **Full v1 API Integration** - All 11 Palworld REST API endpoints supported
- **Console Commands** - Run commands directly from Takaro's web console
- **Real-time Player Tracking** - Monitor player locations and activity
- **WebSocket Connection** - Instant server events and status updates
- **Player Management** - Ban, kick, and manage players by name
- **Server Control** - Save, shutdown, stop, and announce commands
- **Chat Integration** - In-game chat forwarding to Takaro/Discord (UE4SS mod)

## 📥 Installation

### Prerequisites

- Palworld dedicated server with REST API enabled
- Node.js 18 or higher
- Takaro account and server registration token

### Quick Start

1. **Enable Palworld REST API**

   Edit your `PalWorldSettings.ini`:
   ```ini
   RESTAPIEnabled=True
   RESTAPIPort=8212
   AdminPassword=YourSecurePassword
   ```

2. **Install Bridge**

   ```bash
   git clone https://github.com/mad-001/Palworld-Bridge.git
   cd Palworld-Bridge
   npm install
   npm run build
   ```

3. **Configure**

   Create `TakaroConfig.txt`:
   ```ini
   # Takaro Connection
   IDENTITY_TOKEN=YourIdentityToken
   REGISTRATION_TOKEN=YourRegistrationToken

   # Palworld Server Settings
   PALWORLD_HOST=127.0.0.1
   PALWORLD_PORT=8212
   PALWORLD_USERNAME=admin
   PALWORLD_PASSWORD=YourAdminPassword
   ```

4. **Start Bridge**

   ```bash
   npm start
   # Or with PM2 for production:
   pm2 start dist/index.js --name palworld-bridge
   ```

## 💬 Chat Integration (Optional)

The TakaroChat UE4SS mod enables real-time chat forwarding from Palworld to Takaro and Discord.

### Prerequisites

- **UE4SS** - Download from [UE4SS Releases](https://github.com/UE4SS-RE/RE-UE4SS/releases)
  - Get the latest `UE4SS_v3.x.x.zip` release
  - Version 3.0.0 or higher recommended

### Installation Steps

1. **Install UE4SS**

   a. Download UE4SS from the link above

   b. Extract the ZIP file

   c. Copy these files to your Palworld server directory `PalServer\Pal\Binaries\Win64\`:
      - `dwmapi.dll`
      - `UE4SS.dll`
      - `UE4SS-settings.ini`
      - The entire `Mods` folder

2. **Install TakaroChat Mod**

   a. Copy the `TakaroChat` folder from this repository to:
      ```
      PalServer\Pal\Binaries\Win64\Mods\TakaroChat\
      ```

   b. Your directory structure should look like:
      ```
      PalServer\Pal\Binaries\Win64\
      ├── dwmapi.dll
      ├── UE4SS.dll
      ├── UE4SS-settings.ini
      └── Mods\
          └── TakaroChat\
              ├── enabled.txt
              └── Scripts\
                  ├── main.lua
                  └── config.lua
      ```

3. **Configure TakaroChat**

   Edit `TakaroChat/Scripts/config.lua`:
   ```lua
   -- Bridge Connection
   config.BridgeHost = "127.0.0.1"  -- Bridge IP (same machine)
   config.BridgePort = 3000          -- Bridge port (default 3000)

   -- Chat Settings
   config.EnableChatForwarding = true
   config.CaptureCategories = {1, 2, 3}  -- Say, Guild, Global
   ```

4. **Restart Palworld Server**

   Stop and start your Palworld server to load UE4SS and the mod.

### Features
- ✅ Game chat → Takaro platform → Discord
- ✅ Discord → Takaro → Game chat relay
- ✅ Player connect/disconnect events
- ✅ Support for Say, Guild, and Global chat channels
- ✅ Real-time event forwarding
- ✅ Configurable logging and filtering

### Troubleshooting

**UE4SS not loading:**
- Ensure `dwmapi.dll` is in the correct directory
- Check Windows didn't block the DLL (right-click → Properties → Unblock)
- Verify UE4SS version compatibility (3.0.0+)

**Chat not appearing in Discord:**
- Check bridge logs for connection from UE4SS mod
- Verify `config.BridgePort` matches bridge's HTTP server port
- Ensure chat forwarding module is installed in Takaro

**Mod not loading:**
- Confirm `enabled.txt` exists in `TakaroChat` folder
- Check `UE4SS\Mods\mods.txt` includes TakaroChat entry
- Review UE4SS logs in `UE4SS\UE4SS.log`

See [TakaroChat/README.md](TakaroChat/README.md) for detailed configuration options.

## 💻 Console Commands

Use these commands in the Takaro web console:

| Command | Description |
|---------|-------------|
| `help` | Show all available commands |
| `players` | List all online players |
| `serverinfo` | Get server information |
| `metrics` | Get server metrics |
| `settings` | Get server settings |
| `announce <message>` | Send announcement to all players |
| `save` | Save the world |
| `shutdown [seconds] [message]` | Shutdown server with countdown |
| `stop` | Stop server immediately |
| `ban <player_name>` | Ban a player by name |
| `kick <player_name>` | Kick a player by name |
| `unban <steam_id>` | Unban a player by Steam ID |

## 🔌 Supported API Endpoints

### GET Endpoints
- `/v1/api/info` - Server information
- `/v1/api/players` - Player list with locations
- `/v1/api/settings` - Server settings
- `/v1/api/metrics` - Server metrics

### POST Endpoints
- `/v1/api/announce` - Send announcements
- `/v1/api/save` - Save world
- `/v1/api/shutdown` - Graceful shutdown
- `/v1/api/stop` - Immediate stop
- `/v1/api/kick` - Kick player
- `/v1/api/ban` - Ban player
- `/v1/api/unban` - Unban player

## 🔧 Configuration

### TakaroConfig.txt

```ini
# Required: Takaro authentication
IDENTITY_TOKEN=your-identity-token
REGISTRATION_TOKEN=your-registration-token

# Optional: Palworld server connection (defaults shown)
PALWORLD_HOST=127.0.0.1
PALWORLD_PORT=8212
PALWORLD_USERNAME=admin
PALWORLD_PASSWORD=your-admin-password
```

### Getting Takaro Tokens

1. Visit [Takaro.io](https://takaro.io)
2. Register your Palworld server
3. Copy the Identity Token and Registration Token
4. Add them to `TakaroConfig.txt`

## 📊 Monitoring

View bridge logs in real-time:

```bash
# If using npm start
tail -f palworld-bridge.log

# If using PM2
pm2 logs palworld-bridge
```

## 🐛 Troubleshooting

### Bridge won't connect to Takaro
- Verify IDENTITY_TOKEN and REGISTRATION_TOKEN are correct
- Check bridge logs for connection errors
- Ensure internet connectivity

### Can't connect to Palworld server
- Confirm REST API is enabled in PalWorldSettings.ini
- Verify AdminPassword matches between config and server
- Check server is running and port 8212 is accessible

### Commands not working
- Ensure bridge is connected (check logs)
- Verify you're typing commands in Takaro console, not in-game
- Check command syntax with `help` command

## 🔄 Updates

To update the bridge to the latest version:

```bash
git pull
npm install
npm run build
pm2 restart palworld-bridge  # if using PM2
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🔗 Links

- [Documentation](https://mad-001.github.io/Palworld-Bridge/)
- [Takaro Platform](https://takaro.io)
- [Takaro Documentation](https://docs.takaro.io)
- [Report Issues](https://github.com/mad-001/Palworld-Bridge/issues)

## 💖 Support

If you find this project helpful, consider:
- ⭐ Starring the repository
- 🐛 Reporting bugs
- 💡 Suggesting new features
- 📖 Improving documentation

---

Created with ❤️ for the Palworld community
