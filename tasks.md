# Palworld-Takaro Bridge - Implementation Tasks

## Project Goal

Build a Node.js bridge application that connects a Palworld game server to the Takaro platform, enabling server management, player tracking, and event monitoring through Takaro's web interface.

## Architecture Overview

```
Palworld Server (REST API) ←→ Bridge (Node.js) ←→ Takaro Platform (WebSocket)
     Port 8212                                        wss://connect.takaro.io/
```

The bridge acts as a translator between:
- **Palworld's REST API** (HTTP endpoints for server management)
- **Takaro's WebSocket API** (real-time bidirectional communication)

## Reference Implementation

Use the **Astroneer bridge** as a reference:
- Location: `/home/zmedh/Takaro-Projects/astroneer bridge/src/index.ts`
- This is a working implementation that successfully integrates with Takaro
- Follow the same patterns for WebSocket communication and message handling

## Configuration Requirements

### Palworld Server
- Must have `RESTAPIEnabled=True` in server configuration
- REST API runs on port 8212 (default)
- HTTP Basic Authentication enabled

### Takaro Platform
- Registration Token: `I52qvjDlTtKzTnzk1ayK9J1xu9y/QUH/tzd0Ay9D4NI=`
- Identity Token: `Palworld`
- WebSocket URL: `wss://connect.takaro.io/`

## Implementation Tasks

### Phase 1: Project Setup
- [ ] Initialize Node.js project with TypeScript
- [ ] Install dependencies: `ws`, `node-fetch` or `axios`, `winston` (logging)
- [ ] Set up project structure (src/, config/, types/)
- [ ] Create configuration file for Palworld server connection and Takaro credentials

### Phase 2: Takaro WebSocket Connection
- [ ] Implement WebSocket connection to `wss://connect.takaro.io/`
- [ ] Send `identify` message with registrationToken and identityToken
- [ ] Handle `identifyResponse` and store gameServerId
- [ ] Implement reconnection logic on disconnect
- [ ] Add keep-alive/ping mechanism

### Phase 3: Palworld REST API Client
- [ ] Create HTTP client for Palworld REST API (port 8212)
- [ ] Implement authentication (HTTP Basic Auth)
- [ ] Create methods for each endpoint:
  - [ ] GET /info - Server information
  - [ ] GET /players - Current player list
  - [ ] GET /settings - Server settings
  - [ ] GET /metrics - Server metrics
  - [ ] POST /announce - Broadcast message
  - [ ] POST /kick - Kick player
  - [ ] POST /ban - Ban player
  - [ ] POST /unban - Unban player
  - [ ] POST /save - Save world
  - [ ] POST /shutdown - Graceful shutdown
  - [ ] POST /stop - Force stop

### Phase 4: Takaro Request Handling
Implement handlers for incoming Takaro requests:
- [ ] `testReachability` - Verify server is reachable
- [ ] `getPlayers` - Return current player list
- [ ] `executeCommand` - Execute server command (announce, kick, ban, etc.)
- [ ] `kickPlayer` - Kick specific player
- [ ] `banPlayer` - Ban specific player
- [ ] `unbanPlayer` - Unban specific player
- [ ] `sendMessage` - Broadcast message to server
- [ ] Map Takaro requests to Palworld REST API calls
- [ ] Send proper `response` messages back to Takaro

### Phase 5: Game Event Monitoring
- [ ] Poll Palworld /players endpoint periodically
- [ ] Detect player join events (new players in list)
- [ ] Detect player leave events (players removed from list)
- [ ] Send `player-connected` events to Takaro
- [ ] Send `player-disconnected` events to Takaro
- [ ] Format player data correctly (name, playerId, steamId/userId, ip)

### Phase 6: Error Handling & Logging
- [ ] Implement comprehensive error handling
- [ ] Add logging for all operations (Winston)
- [ ] Handle Palworld server offline/unreachable scenarios
- [ ] Handle Takaro WebSocket disconnections
- [ ] Retry logic for failed operations

### Phase 7: Testing & Deployment
- [ ] Test with local Palworld server
- [ ] Verify all Takaro requests work correctly
- [ ] Test player join/leave event detection
- [ ] Deploy to production server
- [ ] Create start/stop scripts
- [ ] Set up as Windows service or systemd service

## Key Implementation Notes

### Player Data Mapping
When sending player events to Takaro, map Palworld player fields:
```javascript
{
  playerName: player.name,
  playerId: player.playerId,
  steamId: player.userId,  // Palworld uses 'userId' for Steam ID
  ip: player.ip
}
```

### Message Format Examples

**Identify Message (to Takaro):**
```json
{
  "type": "identify",
  "payload": {
    "identityToken": "Palworld",
    "registrationToken": "I52qvjDlTtKzTnzk1ayK9J1xu9y/QUH/tzd0Ay9D4NI="
  }
}
```

**Response Message (to Takaro):**
```json
{
  "type": "response",
  "requestId": "uuid-from-request",
  "payload": {
    // Response data
  }
}
```

**Game Event (to Takaro):**
```json
{
  "type": "gameEvent",
  "payload": {
    "eventType": "player-connected",
    "gameServerId": "uuid-from-identify-response",
    "timestamp": 1234567890,
    "data": {
      "playerName": "PlayerName",
      "playerId": "12345",
      "steamId": "76561198012345678",
      "ip": "192.168.1.100"
    }
  }
}
```

## Success Criteria

- [ ] Bridge connects to Takaro WebSocket successfully
- [ ] Server shows as "ONLINE" in Takaro dashboard
- [ ] Takaro can retrieve player list
- [ ] Takaro can send announcements to server
- [ ] Takaro can kick/ban players
- [ ] Player join/leave events appear in Takaro
- [ ] Bridge auto-reconnects on connection loss
- [ ] All operations are logged properly

## Directory Structure

```
Palworld-Bridge/
├── src/
│   ├── index.ts           # Main entry point
│   ├── takaro/
│   │   ├── websocket.ts   # Takaro WebSocket client
│   │   └── types.ts       # Takaro message types
│   ├── palworld/
│   │   ├── client.ts      # Palworld REST API client
│   │   └── types.ts       # Palworld API types
│   ├── bridge/
│   │   ├── eventMonitor.ts  # Player event detection
│   │   └── requestHandler.ts # Handle Takaro requests
│   └── config.ts          # Configuration management
├── config/
│   └── default.json       # Default configuration
├── package.json
├── tsconfig.json
└── README.md
```

## Next Steps

1. Review the Astroneer bridge implementation (`/home/zmedh/Takaro-Projects/astroneer bridge/src/index.ts`)
2. Set up the Node.js project structure
3. Implement Takaro WebSocket connection first (verify server shows online)
4. Add Palworld REST API client
5. Implement request handlers
6. Add event monitoring
7. Test and deploy
