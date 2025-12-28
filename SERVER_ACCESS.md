# Server Access Information

## Network Paths

### Game Server (Palworld)
- **Path**: `\\SERVER\GameServers\palworld`
- **Mods Location**: `\\SERVER\GameServers\palworld\Pal\Binaries\Win64\Mods\TakaroChat\Scripts`
- **UE4SS Log**: `\\SERVER\GameServers\palworld\Pal\Binaries\Win64\UE4SS.log`

### Bridge Server
- **Path**: `\\SERVER\GameServers\Palworld-Bridge`

## Credentials
- **Username**: `Server`
- **Password**: `iheartj3nn`
- **IP**: `192.168.1.100`

## Deployment Commands

### Deploy Lua Scripts to Game Server
```bash
# Copy from local WSL to server
powershell.exe -Command "Copy-Item 'C:\\Users\\Public\\<filename>' -Destination '\\\\SERVER\\GameServers\\palworld\\Pal\\Binaries\\Win64\\Mods\\TakaroChat\\Scripts\\<filename>' -Force"
```

### Check Logs
```bash
# View UE4SS log (last 100 lines)
powershell.exe -Command "Get-Content '\\\\SERVER\\GameServers\\palworld\\Pal\\Binaries\\Win64\\UE4SS.log' -Tail 100"

# Search for specific pattern
powershell.exe -Command "Get-Content '\\\\SERVER\\GameServers\\palworld\\Pal\\Binaries\\Win64\\UE4SS.log' -Tail 100 | Select-String -Pattern 'TELEPORT' -Context 2"
```

## Deployment Workflow
1. Edit files locally in `/home/zmedh/Takaro-Projects/Palworld-Bridge/TakaroChat/Scripts/`
2. Copy to Windows temp: `cp <file> /mnt/c/Users/Public/<file>`
3. Deploy to server using PowerShell command above
