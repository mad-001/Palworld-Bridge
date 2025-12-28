# Palworld Bridge - Takaro Modules

Working Takaro modules for Palworld home/teleport functionality.

## Available Modules

### 1. SetHome Command (`sethome-command.js`)

Save your current location as your home point.

**Usage:**
```
!sethome
```

**How it works:**
- Uses Takaro's cached player position (from polling)
- Saves X/Y/Z coordinates to Takaro variables
- Per-player, per-server storage

**Module Configuration in Takaro:**
- **Command Name:** `sethome`
- **No arguments required**

---

### 2. Home Command (`home-command.js`)

Teleport to your saved home location.

**Usage:**
```
!home
```

**How it works:**
- Retrieves saved coordinates from Takaro variables
- Uses `teleportplayer` command to teleport
- Same reliable system as `!visit` command

**Module Configuration in Takaro:**
- **Command Name:** `home`
- **No arguments required**

---

### 3. Location Command (`location-command.js`)

Get live player coordinates (for testing/admin use).

**Usage:**
```
!location              - Get your own location
!location <player>     - Get another player's location
```

**Module Configuration in Takaro:**
- **Command Name:** `location`
- **Command Arguments:**
  - `player` (optional, string) - Player name to look up

---

## Installation in Takaro

1. Go to **Takaro → Modules → Create Custom Module**
2. Add a new **Command**
3. Paste the module code from the `.js` file
4. Set command name and arguments as specified above
5. Enable module on your game server

---

## How It Works

### SetHome
1. Gets player's current position from `pog.positionX/Y/Z`
2. Saves to Takaro variables with key `home_location`
3. Stores as JSON: `{"x": -713855, "y": -453462, "z": -1586}`

### Home
1. Loads saved position from Takaro variables
2. Executes: `teleportplayer PlayerName X Y Z`
3. Bridge queues teleport → Lua processes → Player teleports

### Why This Approach?

**Position Source:**
- Uses Takaro's cached position data (updated every poll)
- No need for complex command execution and response parsing
- X/Y accurate, Z may be 0 (Palworld API limitation)

**Teleport Method:**
- Uses proven `teleportplayer` command (same as `!visit`)
- Reliable queue-based system
- Works with both player-to-player and coordinate teleports

---

## Dependencies

**Required:**
- Palworld Bridge running and connected to Takaro
- UE4SS mod with TakaroChat Lua scripts
- Bridge teleport queue system enabled

**Bridge Version:** v1.3.0+

---

## Troubleshooting

### "Unable to get your position"
- Wait a few seconds for Takaro to poll player positions
- Make sure you're online when setting home

### Teleport fails
- Check bridge logs for teleport queue activity
- Verify Palworld server has UE4SS + TakaroChat mod loaded
- Ensure bridge is connected to both Palworld and Takaro

### Z coordinate is 0
- This is expected - Palworld API doesn't provide Z coordinate
- X/Y are accurate for teleport purposes
- Z=0 will place you at ground level

---

## Example Module Code

### Minimal SetHome
```javascript
import { data, takaro } from '@takaro/helpers';

async function main() {
    const { gameServerId, player, pog, module } = data;

    const position = {
        x: pog.positionX,
        y: pog.positionY,
        z: pog.positionZ || 0
    };

    // Save to variable...
}

await main();
```

### Minimal Home
```javascript
import { data, takaro } from '@takaro/helpers';

async function main() {
    const { gameServerId, player } = data;

    // Load from variable...
    const position = JSON.parse(homeVar.value);

    await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, {
        command: `teleportplayer ${player.name} ${position.x} ${position.y} ${position.z}`
    });
}

await main();
```

---

## Files in This Directory

- `sethome-command.js` - Working sethome implementation ✅
- `home-command.js` - Working home implementation ✅
- `location-command.js` - Location lookup (testing/admin)
- `get-player-location-helper.js` - Helper functions (legacy)
- `README.md` - This file

---

## Related Commands

- **!visit <player>** - Teleport to another player
- **!sethome** - Save current location as home
- **!home** - Teleport to saved home location
