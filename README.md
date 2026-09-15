# Palworld-Takaro Bridge

🦖 Connect your Palworld dedicated server to the Takaro game server management platform.

[![GitHub release](https://img.shields.io/github/v/release/mad-001/Palworld-Bridge)](https://github.com/mad-001/Palworld-Bridge/releases/latest)
[![License](https://img.shields.io/github/license/mad-001/Palworld-Bridge)](LICENSE)

## 🌟 Features

- **Full v1 API Integration** - All 11 Palworld REST API endpoints supported
- **Console Commands** - Run commands directly from Takaro's web console
- **Real-time Player Tracking** - Monitor player locations and activity
- **WebSocket Connection** - Instant server events and status updates
- **Player Management** - Ban, kick, and manage players by name or Steam ID, with a
  local ban ledger so Takaro's ban list is populated
- **Server Control** - Save, shutdown, stop, and announce commands
- **Chat Integration** - In-game chat forwarding to Takaro/Discord (UE4SS mod)
- **Item Catalog** - 1891 Palworld items exposed to Takaro, so the shop item
  picker and `giveItem` work (see [Item catalog](#-item-catalog))

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

   Download the latest release (`Palworld-Bridge-vX.X.X.tar.gz` from the
   [Releases page](https://github.com/mad-001/Palworld-Bridge/releases/latest)) and
   extract it. The download includes everything: the prebuilt bridge, a ready-to-edit
   `TakaroConfig.txt`, and the `TakaroChat` UE4SS mod. Then install dependencies:

   ```bash
   cd Palworld-Bridge
   npm install
   ```

   > Building from source instead? `git clone` this repo, then `npm install && npm run build`.

3. **Configure**

   Create `TakaroConfig.txt`:
   ```ini
   # Takaro Connection
   SERVER_NAME=Give your server a name
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

- **UE4SS (Palworld-specific build)** - Download `UE4SS-Palworld.zip` from
  [Okaetsu's RE-UE4SS `experimental-palworld` release](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld)
  - ⚠️ **Do NOT use the generic/mainline UE4SS** — since Palworld patch `0.4.1.5`
    the engine changed and only the Palworld-specific build works. The generic
    build will crash the server on startup.
  - If you previously installed another UE4SS, delete the old `dwmapi.dll` and
    `ue4ss` folder from `Pal\Binaries\Win64\` before installing this one.

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

   a. Copy the `TakaroChat` folder (included in the release download / this
      repository) to:
      ```
      PalServer\Pal\Binaries\Win64\ue4ss\Mods\TakaroChat\
      ```

   b. Your directory structure should look like:
      ```
      PalServer\Pal\Binaries\Win64\
      └── ue4ss\
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
   config.BridgeURL = "http://localhost:3001/chat"  -- Bridge endpoint (default 3001)
   config.EnableBridge = true

   -- Chat Categories (Palworld chat types)
   -- 1 = Say (local), 2 = Guild, 3 = Global
   config.SendCategories = {1, 2, 3}  -- Which categories to send
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
- Ensure `dwmapi.dll` is in the `Win64\ue4ss\` directory
- Check Windows didn't block the DLL (right-click → Properties → Unblock)
- Verify UE4SS version compatibility (3.0.0+)

**Chat not appearing in Discord:**
- Check bridge logs for connection from UE4SS mod
- Verify `config.BridgeURL` uses correct port (default: `http://localhost:3001/chat`)
- Ensure chat forwarding module is installed in Takaro

**Mod not loading:**
- Confirm `enabled.txt` exists in `ue4ss\Mods\TakaroChat\` folder
- Check `ue4ss\Mods\mods.txt` includes TakaroChat entry
- Review UE4SS logs in `ue4ss\UE4SS.log`

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
| `unban <steam_id\|player_name>` | Unban a player by Steam ID or by name |
| `teleportplayer <source> <target>` | Teleport a player to another player |
| `teleportplayer <source> <x> <y> <z>` | Teleport a player to coordinates |
| `location <player>` | Show a player's current coordinates |

## 🎮 Takaro actions

Everything Takaro's Generic game server can ask for, and what the bridge does with it:

| Action | Supported | Notes |
|---|---|---|
| `testReachability` | yes | Uses the Palworld REST API, so it also works off-box |
| `getPlayers` | yes | Fails loudly on a REST error instead of reporting an empty server |
| `getPlayer` | yes | Single player lookup by `gameId`; `null` when not online |
| `getPlayerLocation` | yes | Needs the `TakaroChat` UE4SS mod; `null` (not `0,0,0`) on failure |
| `getPlayerInventory` | yes | Needs the UE4SS mod and `EnableInventoryTracking` |
| `sendMessage` | yes | Mapped to the REST `announce` endpoint |
| `executeConsoleCommand` | yes | See the console command table above |
| `giveItem` | yes | Needs the UE4SS mod; Palworld has no item quality tiers |
| `teleportPlayer` | yes | Needs the UE4SS mod; coordinates or another player |
| `kickPlayer` / `banPlayer` / `unbanPlayer` | yes | Takaro's reason is used as the in-game message |
| `listBans` | yes | Bans the bridge issued (see below) |
| `listItems` | yes | 1891 item catalog |
| `shutdown` | yes | REST `/v1/api/shutdown` with a 10 second countdown |
| `listEntities` / `listLocations` / `getMapInfo` | no | Palworld exposes no such data |

Notes on identity and bans:

- Palworld reports accounts as `steam_7656...`. The bridge keeps that raw form as the
  player's `gameId` (stable identity) but reports `steamId` as the bare 17-digit Steam64
  id, which is what Takaro's Steam profile enrichment needs.
- Palworld's REST API can ban and unban but offers no way to read the ban list, so the
  bridge keeps its own ledger in `bans.json` beside the bridge and serves that to
  `listBans`. Bans made outside the bridge are not listed. Palworld's ban endpoint has no
  expiry parameter either, so a temporary ban from Takaro is permanent in-game and only
  Takaro tracks when it should end.

## 🎒 Item catalog

The Palworld REST API has no item endpoint, so the bridge ships its own catalog
and answers Takaro's `listItems` from it. Takaro therefore sees **1891 items**
(`code` = the in-game `DT_ItemDataTable` row name, plus an English `name` and
`description`), which is what the shop item picker and item-giving modules need.

- Source of truth: `data/palworld-items.json`, embedded into the bundled JS (and
  therefore into `PalworldBridge.exe`) at build time by
  `scripts/generate-embedded-items.js`, which runs from `npm run build`.
- **Item ids change with Palworld game patches.** Regenerate
  `data/palworld-items.json` after a Palworld update and rebuild. The list is
  derived from `DT_ItemDataTable` (rows flagged `bLegalInGame`) cross-checked
  against paldb.cc display names and the wiki's item descriptions; the full
  method is documented in `palworld-items.SOURCES.md` alongside the data set.
- `giveItem` validates the requested code against this catalog before touching
  the in-game mod, and returns `Unknown item code: <code>` for anything not in
  it. This matters because the UE4SS mod cannot validate ids at runtime: an
  unknown `FName` makes `RequestAddItem` silently do nothing. The mod now
  reports the *real* outcome back to the bridge (player offline, no inventory
  data, etc.) instead of always claiming success.

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
SERVER_NAME=Give your server a name
REGISTRATION_TOKEN=your-registration-token

# Optional: Palworld server connection (defaults shown)
PALWORLD_HOST=127.0.0.1
PALWORLD_PORT=8212
PALWORLD_USERNAME=admin
PALWORLD_PASSWORD=your-admin-password

# Optional: verbose troubleshooting logs (default 0)
TAKARO_DEBUG=0
```

`TAKARO_DEBUG=1` sets the log level to debug and writes every WebSocket frame
exchanged with Takaro to the log file as `WS SEND ...` / `WS RECV ...` (frames
are truncated at 2000 characters and your registration token is redacted). It
is noisy - turn it back to `0` once you have what you need.

The bridge decides whether your Palworld server is up by polling its REST API
(`GET /v1/api/info`) every 5 seconds, so it also works when the bridge runs on
Linux or in a container; the Windows process check is only an extra hint.

### Getting Takaro Tokens

1. Visit [Takaro.io](https://takaro.io/pricing/?via=zach550)
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
- Verify SERVER_NAME and REGISTRATION_TOKEN are correct
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
- [Takaro Platform](https://takaro.io/pricing/?via=zach550)
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
