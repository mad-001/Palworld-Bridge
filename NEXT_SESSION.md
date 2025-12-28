# Palworld Bridge - Session Context

## Server Access

**Server Machine**: `server` (accessible from WSL)
- Access files via UNC path: `\\server\c$\...`
- Copy files from WSL:
  ```bash
  powershell.exe -Command "Copy-Item -Path 'local/path/file.js' -Destination '\\\\server\\c$\\remote\\path\\file.js' -Force"
  ```

## File Locations

### Bridge (Node.js)
- **Local**: `/home/zmedh/Takaro-Projects/Palworld-Bridge/`
- **Server**: `C:\gameservers\Palworld-Bridge`
- **Source**: `src/index.ts`
- **Compiled**: `dist/index.js`
- **Logs**: `C:\gameservers\Palworld-Bridge\logs\YYYY-MM-DD_HH.log`

### Palworld + UE4SS Lua Scripts
- **Server**: `C:\gameservers\palworld\Pal\Binaries\Win64\Mods\TakaroChat\Scripts\`
- **Local**: `/home/zmedh/Takaro-Projects/Palworld-Bridge/TakaroChat/Scripts/`
- **UE4SS Log**: `C:\gameservers\palworld\Pal\Binaries\Win64\UE4SS.log`

**Key Scripts**:
- `main.lua` - Entry point, loads all modules
- `location.lua` - Player location lookup (BROKEN - Lua not responding)
- `teleport.lua` - Player teleportation (WORKING)
- `events.lua` - Player join/leave/death events
- `chat.lua` - Chat bridge
- `discord.lua` - Discord integration
- `deep_discovery.lua` - Property discovery (BROKEN)

## Git Workflow

**CRITICAL**: Commit EVERY change to local git before deploying:
```bash
git add -A && git commit -m "Description of change"
```

## Current Issues

### Location System (!sethome)
- **Problem**: Lua polls `/location-queue` but gets empty arrays even though bridge queues requests
- **Why**: Unknown - requests are queued in bridge but not reaching Lua
- **Pattern**: Should work like `!visit`/teleportplayer but Claude keeps refusing to use that pattern
- **Status**: BROKEN - don't try to fix without understanding teleport pattern first

### Deep Discovery
- **File**: `deep_discovery.lua`
- **Status**: BROKEN - needs investigation
- **Purpose**: Discover inventory and guild properties

## How Teleport Works (REFERENCE FOR LOCATION)

1. Takaro module calls: `await takaro.gameserver.gameServerControllerExecuteCommand(gameServerId, { command: 'teleportplayer player1 player2' })`
2. Bridge receives command, queues teleport in `teleportQueue`
3. Lua polls `/teleport-queue` every second
4. Lua gets queue, finds players, executes teleport
5. Queue is cleared after polling

**Location should work the same way but doesn't - investigate why**

## Bridge Process Management

- **NEVER** use Stop-Process, kill, or restart commands
- User handles bridge restarts
- Bridge runs on port 3001
- If "EADDRINUSE" error, bridge already running - user will kill it

## Deployment Checklist

1. Make changes to local files
2. Commit to git: `git add -A && git commit -m "..."`
3. Build if needed: `npm run build`
4. Copy to server:
   - Bridge: `powershell.exe -Command "Copy-Item -Path 'dist\index.js' -Destination '\\\\server\\c$\\gameservers\\Palworld-Bridge\\dist\\index.js' -Force"`
   - Lua: `powershell.exe -Command "Copy-Item -Path 'TakaroChat\Scripts\file.lua' -Destination '\\\\server\\c$\\gameservers\\palworld\\Pal\\Binaries\\Win64\\Mods\\TakaroChat\\Scripts\\file.lua' -Force"`
5. User restarts bridge/server

## Important Notes

- **Time zones**: Bridge logs are UTC, UE4SS logs are local time (CST = UTC-6)
- **Players have people online**: Don't break things that are working
- **Ask before acting**: Get confirmation before major changes
- **Use TODO list**: Track tasks with TodoWrite tool
- **No temp files**: Copy directly, don't create intermediary temp files
