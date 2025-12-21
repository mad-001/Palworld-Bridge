# References

## Astroneer Bridge (Working Reference Implementation)

**Location:** `/home/zmedh/Takaro-Projects/astroneer bridge/`

The Astroneer bridge is a working Node.js application that successfully integrates an Astroneer game server with the Takaro platform. It serves as a reference implementation for building the Palworld bridge.

### Key Features:
- Uses Node.js with the 'ws' library for WebSocket communication with Takaro
- Connects to game server's HTTP API endpoints
- Handles bidirectional communication (Takaro ↔ Game Server)
- Implements all required Takaro protocol messages (identify, events, requests, responses)
- Auto-reconnects on connection loss

### Main File:
`/home/zmedh/Takaro-Projects/astroneer bridge/src/index.ts`

### Takaro Integration Pattern:
1. Connects to `wss://connect.takaro.io/` using WebSocket
2. Sends `identify` message with `registrationToken` and `identityToken`
3. Receives `identifyResponse` with `gameServerId`
4. Handles incoming `request` messages from Takaro (testReachability, getPlayers, executeCommand, etc.)
5. Sends `response` messages back to Takaro
6. Sends game events to Takaro (player-connected, player-disconnected, chat-message)

### Technologies Used:
- Node.js + TypeScript
- 'ws' library for WebSocket
- HTTP requests to game server API

## Palworld REST API Documentation

See [RestApi.md](./RestApi.md) for complete Palworld REST API documentation.

**Base URL:** `http://localhost:8212/` (default port)
**Authentication:** HTTP Basic Auth
**Configuration Required:** `RESTAPIEnabled=True` in Palworld server settings
