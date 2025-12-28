# Palworld Bridge - Takaro Modules

These modules use the Palworld Bridge's location and teleport systems to provide enhanced functionality.

## Available Modules

### 1. Location Command (`location-command.js`)

Get live player coordinates using the bridge's location system.

**Usage:**
```
!location              - Get your own location
!location <player>     - Get another player's location
```

**Features:**
- Real-time X/Y/Z coordinates
- Works for any online player
- Accurate Z-coordinate (unlike Palworld API polling)

**Module Configuration:**
- **Command Name:** `location`
- **Command Arguments:**
  - `player` (optional, string) - Player name to look up

---

### 2. SetHome Command (`sethome-command.js`)

Save your current location as your home point.

**Usage:**
```
!sethome
```

**Features:**
- Uses live location system for accurate coordinates
- Stores location in Takaro variables
- Per-player, per-server storage

**Module Configuration:**
- **Command Name:** `sethome`
- **No arguments required**

**Pairs with:** `home` command (teleports you back to saved location)

---

## How the Location System Works

1. **Module calls bridge command:**
   ```javascript
   const locationCmd = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
       command: `location ${gameId}`
   });
   ```

2. **Bridge queues location request:**
   - Request added to `locationRequestQueue`
   - Includes player name and unique requestId

3. **Lua polls for requests:**
   - Every 1 second, Lua checks `/location-queue`
   - Finds online player using `PlayerNamePrivate`
   - Gets coordinates using `K2_GetActorLocation()`

4. **Lua sends response:**
   - Posts location data to `/location-response`
   - Bridge receives and matches requestId

5. **Module gets result:**
   ```javascript
   const location = locationCmd.data?.data || locationCmd.data;
   // { x: -714269.9, y: -452173.1, z: -1262.5 }
   ```

---

## Troubleshooting

### "Unable to get your current position"

**Causes:**
- Player not online
- Player name mismatch between Takaro and in-game name
- Location request timeout (5 seconds)

**Debug:**
Check UE4SS logs for:
```
[LOCATION] Looking for 'PlayerName'. Available players:
[LOCATION]   - 'ActualName1'
[LOCATION]   - 'ActualName2'
```

If player name doesn't match, check the bridge's player name mapping.

### Location returns (0, 0, 0)

**Causes:**
- Palworld server not running
- UE4SS mod not loaded
- TakaroChat scripts not initialized

**Fix:**
1. Restart Palworld server
2. Check UE4SS.log for TakaroChat initialization
3. Verify bridge is connected to Palworld API

---

## Dependencies

**Required:**
- Palworld Bridge running and connected
- UE4SS mod installed on Palworld server
- TakaroChat Lua scripts deployed
- Bridge's location queue system enabled

**Bridge Version:** v1.3.0+

---

## File Locations

**Modules:** `/home/zmedh/Takaro-Projects/Palworld-Bridge/modules/`
**Lua Scripts:** `C:\gameservers\palworld\Pal\Binaries\Win64\Mods\TakaroChat\Scripts\`
**Bridge:** `C:\gameservers\Palworld-Bridge\`

---

## Module Installation in Takaro

1. Go to Takaro → Modules → Create Custom Module
2. Add a new command
3. Paste the module code
4. Configure command name and arguments
5. Enable module on your game server

---

## Example: Using Location in Your Own Module

```javascript
import { data, takaro } from '@takaro/helpers';

async function main() {
    const { gameServerId, pog } = data;

    // Get player's current location
    const locationCmd = await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
        command: `location ${pog.gameId}`
    });

    const location = locationCmd.data?.data || locationCmd.data;

    if (!location || (location.x === 0 && location.y === 0 && location.z === 0)) {
        console.log("Failed to get location");
        return;
    }

    // Use the location
    console.log(`Player at: ${location.x}, ${location.y}, ${location.z}`);
}

await main();
```

---

## Related Commands

- **!visit <player>** - Teleport to another player (uses same location system)
- **!home** - Teleport to your saved home location
- **!sethome** - Save your current location as home
