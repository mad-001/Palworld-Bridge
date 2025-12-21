# Palworld REST API Documentation

## Overview

The Palworld REST API is "a simple REST API for Palworld server." To utilize it, administrators must enable the feature by setting `RESTAPIEnabled=True` in their configuration.

### Key Requirements
- Configuration setting required: `RESTAPIEnabled=True`
- Current version: 0.7.0
- API version: v0.2.0.0

### Security Considerations
The documentation emphasizes that this API is not intended for direct internet exposure. According to the guide, "Publishing directly to the Internet may result in unauthorized manipulation of the server, which may interfere with play." Instead, the creators recommend deploying these endpoints exclusively within local area networks.

### Authentication Method
The API implements HTTP Basic Authentication as its security scheme. This means requests require standard username and password credentials transmitted via the HTTP Authorization header.

### Available Endpoints
The REST API provides functionality for:
- Server information and metrics retrieval
- Player management (list, kick, ban, unban)
- Server configuration access
- Administrative actions (announcements, saving, shutdown, force stop)

**License:** Apache 2.0

---

## Endpoints

### GET /info

**Purpose:** "To get the server information"

**Response (200 Success):**
```json
{
  "version": "v0.1.5.0",
  "servername": "Palworld example Server",
  "description": "This is a Palworld server.",
  "worldguid": "A7E97BAA767DB9029EF013BB71E993A0"
}
```

**Response Fields:**
- **version:** The server version number
- **servername:** The server's display name
- **description:** Server description text
- **worldguid:** A unique identifier for the world

**Error Responses:**
- **400:** Request error
- **401:** Unauthorized access

---

### GET /players

**Purpose:** "To get the player list"

**Response (200 Success):**
Returns a JSON object containing a `players` array with player details.

**Player Object Properties:**

| Field | Type | Description |
|-------|------|-------------|
| name | string | "The player name" |
| accountName | string | "User's platform account name" |
| playerId | string | "The player ID" |
| userId | string | "The user ID" |
| ip | string | "The player IP address" |
| ping | number | "The player ping" |
| location_x | number | "The player location X" |
| location_y | number | "The player location Y" |
| level | integer | "Current player game level" |
| building_count | integer | "The number of buildings owned by the player" |

**Error Responses:**
- **400:** Request error
- **401:** Unauthorized access

---

### GET /settings

**Purpose:** "To get the server settings."

**Response (200 Success):**
Returns a JSON object containing comprehensive server configuration parameters.

**Key Settings Categories:**

**Game Difficulty & Rates:**
- Difficulty level
- Day/night time speed rates
- Experience, capture, and spawn rates
- Damage rates for players and pals
- Stamina and stomach decrease rates
- HP regeneration rates

**Gameplay Features:**
- Player-to-player damage toggle
- Friendly fire settings
- Invader enemy encounters
- Aim assist options (pad/keyboard)
- Fast travel availability
- Location selection by map

**Server Configuration:**
- Server name and description
- Player capacity (coop and total)
- Public IP and port
- RCON and REST API settings
- Authentication requirements
- Platform restrictions
- Backup save data usage

**Error Responses:**
- **400:** Request error
- **401:** Unauthorized access

---

### GET /metrics

**Purpose:** "To get the server metrics"

**Response (200 Success):**
```json
{
  "serverfps": 57,
  "currentplayernum": 10,
  "serverframetime": 16.7671,
  "maxplayernum": 32,
  "uptime": 3600,
  "days": 1
}
```

**Response Fields:**
- **serverfps** (integer) - "The server FPS"
- **currentplayernum** (integer) - "The number of current players"
- **serverframetime** (number) - Server frame time measured in milliseconds
- **maxplayernum** (integer) - "The maximum number of players"
- **uptime** (integer) - Server uptime expressed in seconds
- **days** (integer) - In-game day count on the server

**Error Responses:**
- **400:** Request error
- **401:** Unauthorized access

---

### POST /announce

**Purpose:** Broadcast messages to a server

**Content Type:** application/json

**Request Body:**
```json
{
  "message": "string (required)"
}
```

**Parameters:**
- **message** (string, required): "The message to announce"

**Response Codes:**
- **200:** "The message was announced"
- **400:** "Bad request"
- **401:** "Unauthorized"

---

### POST /kick

**Purpose:** Remove a player from the server

**Content Type:** application/json

**Request Body:**
```json
{
  "userid": "string (required)",
  "message": "string (optional)"
}
```

**Parameters:**
- **userid** (string, required): "The player ID to kick."
- **message** (string, optional): "The message to display to the kicked player."

**Response Codes:**
- **200:** The player was successfully removed from the server
- **400:** Invalid request (bad formatting or missing required fields)
- **401:** Authentication failed or insufficient permissions

---

### POST /ban

**Purpose:** Ban a player from the server

**Content Type:** application/json

**Request Body:**
```json
{
  "userid": "string (required)",
  "message": "string (optional)"
}
```

**Parameters:**
- **userid** (string, required): "The player ID to ban"
- **message** (string, optional): "The message to display to the banned player"

**Response Codes:**
- **200:** "The player was banned"
- **400:** "Bad request"
- **401:** "Unauthorized"

---

### POST /unban

**Purpose:** Remove a player ban from the server

**Content Type:** application/json

**Request Body:**
```json
{
  "userid": "string (required)"
}
```

**Parameters:**
- **userid** (string, required): "The player ID to unban"

**Response Codes:**
- **200:** The player was successfully unbanned
- **400:** Malformed or invalid request
- **401:** Request lacks proper authorization

---

### POST /save

**Purpose:** "To save the world."

**Content Type:** application/json

**Response Codes:**
- **200:** "Successfully saved the world."
- **400:** "Request error."
- **401:** "Unauthorized."

---

### POST /shutdown

**Purpose:** Gracefully terminate the Palworld server

**Content Type:** application/json

**Request Body:**
```json
{
  "waittime": 0,
  "message": "string (optional)"
}
```

**Parameters:**
- **waittime** (integer, required): "The time to wait before shutting down the server."
- **message** (string, optional): "The message to display before shutting down the server."

**Response Codes:**
- **200:** The server will shutdown successfully
- **400:** Bad request (invalid parameters)
- **401:** Unauthorized (authentication failed)

---

### POST /stop

**Purpose:** "To force stop the server."

**Content Type:** application/json

**Response Codes:**
- **200:** "The server force stopped."
- **400:** "Request error."
- **401:** "Unauthorized."

**Note:** This endpoint offers a forceful termination method rather than a graceful shutdown (use `/shutdown` for graceful shutdown).
