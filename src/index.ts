import WebSocket from 'ws';
import winston from 'winston';
import axios, { AxiosInstance } from 'axios';
import express from 'express';
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

// Version
const VERSION = '1.3.2-discovery';

// Load configuration from TakaroConfig.txt
function loadConfig() {
  const configPath = path.join(process.cwd(), 'TakaroConfig.txt');

  if (!fs.existsSync(configPath)) {
    console.error('ERROR: TakaroConfig.txt not found!');
    console.error('Please create TakaroConfig.txt with your server settings.');
    process.exit(1);
  }

  const configContent = fs.readFileSync(configPath, 'utf-8');

  configContent.split('\n').forEach(line => {
    line = line.trim();
    if (line && !line.startsWith('#')) {
      const [key, ...valueParts] = line.split('=');
      const value = valueParts.join('=').trim();
      if (key && value) {
        process.env[key.trim()] = value;
      }
    }
  });
}

loadConfig();

// Create logs directory if it doesn't exist
const logsDir = path.join(process.cwd(), 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

// Function to get current log filename
function getLogFilename(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hour = String(now.getHours()).padStart(2, '0');
  return path.join(logsDir, `${year}-${month}-${day}_${hour}.log`);
}

// Logger state for hourly rotation
let currentLogFilename = getLogFilename();
let fileTransport = new winston.transports.File({ filename: currentLogFilename });

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ timestamp, level, message }) => {
      return `${timestamp} [${level.toUpperCase()}] ${message}`;
    })
  ),
  transports: [
    new winston.transports.Console(),
    fileTransport
  ]
});

// Rotate log file every hour
setInterval(() => {
  const newLogFilename = getLogFilename();
  if (newLogFilename !== currentLogFilename) {
    logger.info('Rotating log file...');

    // Remove old file transport
    logger.remove(fileTransport);

    // Create new file transport
    currentLogFilename = newLogFilename;
    fileTransport = new winston.transports.File({ filename: currentLogFilename });
    logger.add(fileTransport);

    logger.info('Log file rotated to: ' + currentLogFilename);
  }
}, 60000); // Check every minute

// Configuration
const TAKARO_WS_URL = process.env.TAKARO_WS_URL || 'wss://connect.next.takaro.dev/';
const IDENTITY_TOKEN = process.env.IDENTITY_TOKEN || '';
const REGISTRATION_TOKEN = process.env.REGISTRATION_TOKEN || '';

// Palworld REST API Configuration
const PALWORLD_HOST = process.env.PALWORLD_HOST || '127.0.0.1';
const PALWORLD_PORT = parseInt(process.env.PALWORLD_PORT || '8212', 10);
const PALWORLD_BASE_URL = `http://${PALWORLD_HOST}:${PALWORLD_PORT}`;
const PALWORLD_USERNAME = process.env.PALWORLD_USERNAME || 'admin';
const PALWORLD_PASSWORD = process.env.PALWORLD_PASSWORD || '';

// HTTP Server Configuration (for receiving chat from UE4SS mod)
const HTTP_PORT = parseInt(process.env.HTTP_PORT || '3001', 10);

// Takaro WebSocket connection
let takaroWs: WebSocket | null = null;
let isConnectedToTakaro = false;
let reconnectTimeout: NodeJS.Timeout | null = null;

// Palworld API client
let palworldApi: AxiosInstance;
let isServerRunning = false;
let serverCheckInterval: NodeJS.Timeout | null = null;

// Reconnection state
let reconnectAttempts = 0;
const MAX_RECONNECT_DELAY = 60000; // 60 seconds
const BASE_RECONNECT_DELAY = 3000; // 3 seconds
const SERVER_CHECK_INTERVAL = 5000; // Check server every 5 seconds

// Player inventory cache
interface PlayerInventory {
  playerName: string;
  inventory: any[];
  timestamp: string;
}
const playerInventories = new Map<string, PlayerInventory>();

// Track online players to detect connect/disconnect
let lastKnownPlayers = new Set<string>();
let hasInitializedPlayerList = false; // Track if we've done first poll
const playerCache = new Map<string, { gameId: string; name: string; steamId: string }>();

// Teleport queue for pending teleports
interface TeleportRequest {
  sourcePlayer: string;
  targetPlayer?: string;  // Optional - used for player-to-player
  x?: number;             // Optional - used for coordinate teleport
  y?: number;
  z?: number;
  timestamp: string;
}
const teleportQueue: TeleportRequest[] = [];

// Location queue for getting player positions
interface LocationRequest {
  playerName: string;
  requestId: string;
  timestamp: string;
}
interface LocationResponse {
  playerName: string;
  requestId: string;
  x: number;
  y: number;
  z: number;
  timestamp: string;
}
const locationRequestQueue: LocationRequest[] = [];
const locationResponseQueue: LocationResponse[] = [];

// Metrics
const metrics = {
  requestsReceived: 0,
  responsesSent: 0,
  errors: 0,
  lastRequestTime: Date.now(),
  startTime: Date.now()
};

// Initialize Express app for chat endpoint
const app = express();
app.use(express.json());

/**
 * Chat/Events endpoint - receives in-game events from UE4SS mod
 */
app.post('/chat', async (req, res) => {
  try {
    const { type, playerName, message, category, categoryName, timestamp, data } = req.body;

    // Handle different event types
    switch (type) {
      case 'chat':
        logger.info(`[CHAT] [${categoryName || category}] ${playerName}: ${message}`);
        if (isConnectedToTakaro) {
          await sendChatEvent({
            playerName,
            message,
            category,
            categoryName,
            timestamp
          });
        }
        break;

      case 'player_connect':
        logger.info(`[EVENT] Player connected: ${playerName}`);
        if (isConnectedToTakaro) {
          // Fetch current players to get gameId for the connected player
          const players = await handleGetPlayers();
          const connectedPlayer = players.find((p: any) =>
            p.name.toLowerCase() === playerName.toLowerCase()
          );
          if (connectedPlayer) {
            await sendPlayerEvent('player-connected', connectedPlayer.name, timestamp, connectedPlayer.gameId);
          } else {
            logger.warn(`Could not find gameId for connected player: ${playerName}`);
          }
        }
        break;

      case 'player_disconnect':
        logger.info(`[EVENT] Player disconnected: ${playerName}`);
        if (isConnectedToTakaro) {
          // Use cached gameId for disconnect (player is offline now)
          const cachedPlayer = Array.from(playerCache.values()).find(p =>
            p.name.toLowerCase() === playerName.toLowerCase()
          );
          const gameId = cachedPlayer?.gameId;
          await sendPlayerEvent('player-disconnected', playerName, timestamp, gameId);
        }
        break;

      case 'player_death':
        logger.info(`[EVENT] Player died: ${playerName}`);
        if (isConnectedToTakaro) {
          await sendPlayerEvent('player-death', playerName, timestamp);
        }
        break;

      case 'inventory':
        const { inventory } = req.body;
        // Only log if player has items
        if (inventory && inventory.length > 0) {
          logger.info(`[INVENTORY] Updated for: ${playerName} (${inventory.length} items)`);
        }
        playerInventories.set(playerName, {
          playerName,
          inventory: inventory || [],
          timestamp: timestamp || new Date().toISOString()
        });
        break;

      default:
        logger.warn(`Unknown event type: ${type}`);
    }

    res.status(200).json({ success: true });
  } catch (error: any) {
    logger.error(`Event endpoint error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * Teleport queue endpoint - UE4SS mod polls this for pending teleports
 */
app.get('/teleport-queue', (req, res) => {
  try {
    // Return all pending teleports and clear the queue
    const pending = [...teleportQueue];
    teleportQueue.length = 0; // Clear queue
    res.status(200).json({ teleports: pending });
  } catch (error: any) {
    logger.error(`Teleport queue endpoint error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Location request queue endpoint (polled by Lua)
app.get('/location-queue', (req, res) => {
  try {
    // Return queue WITHOUT clearing it - timeout logic will handle cleanup
    const pending = [...locationRequestQueue];
    res.status(200).json({ requests: pending });
  } catch (error: any) {
    logger.error(`Location queue endpoint error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Location response endpoint (Lua posts location data here)
app.post('/location-response', (req, res) => {
  try {
    const response: LocationResponse = req.body;
    locationResponseQueue.push(response);
    logger.debug(`[LOCATION] Received response for ${response.playerName}: (${response.x}, ${response.y}, ${response.z})`);
    res.status(200).json({ success: true });
  } catch (error: any) {
    logger.error(`Location response endpoint error: ${error.message}`);
    res.status(500).json({ success: false, error: error.message });
  }
});

/**
 * Send chat event to Takaro
 */
async function sendChatEvent(chatData: any) {
  try {
    // Use cached player data instead of API call (calling API during chat causes kicks)
    let player: any = null;
    for (const cachedPlayer of playerCache.values()) {
      if (cachedPlayer.name === chatData.playerName) {
        player = cachedPlayer;
        break;
      }
    }

    // Map Palworld categories to ChatChannel enum - must match exact enum values
    // 1 = Say, 2 = Guild, 3 = Global
    const category = Number(chatData.category);
    const channel = (category === 2) ? 'team' : 'global';

    const event = {
      type: 'gameEvent',
      payload: {
        type: 'chat-message',
        data: {
          type: 'chat-message',
          msg: chatData.message,
          player: player ? {
            name: player.name,
            gameId: player.gameId,
            steamId: player.steamId
          } : {
            name: chatData.playerName,
            gameId: chatData.playerName // Fallback if player not in cache yet
          },
          channel: channel
        }
      }
    };

    if (sendToTakaro(event)) {
      logger.info(`Sent chat-message event to Takaro: ${chatData.playerName}: ${chatData.message}`);
    }
  } catch (error: any) {
    logger.error(`Error sending chat event: ${error.message}`);
  }
}

/**
 * Send player event to Takaro (connect/disconnect/death)
 */
async function sendPlayerEvent(eventType: string, playerName: string, timestamp?: string, gameId?: string) {
  try {
    // Use provided gameId or look up in cache
    let player: any = null;

    if (gameId) {
      // Use provided gameId - ensure it's a string
      const cachedPlayer = playerCache.get(gameId);
      player = cachedPlayer || { name: playerName, gameId: String(gameId), steamId: String(gameId) };
    } else {
      // Try to find in cache by name
      for (const cachedPlayer of playerCache.values()) {
        if (cachedPlayer.name === playerName) {
          player = cachedPlayer;
          break;
        }
      }
    }

    // Don't send event if we don't have a valid gameId
    if (!player || !player.gameId || typeof player.gameId !== 'string') {
      logger.error(`Cannot send ${eventType} event - no valid gameId for player: ${playerName}`);
      return;
    }

    const event = {
      type: 'gameEvent',
      payload: {
        type: eventType,
        data: {
          type: eventType,
          player: {
            name: String(player.name),
            gameId: String(player.gameId),
            steamId: String(player.steamId || player.gameId)
          }
        }
      }
    };

    if (sendToTakaro(event)) {
      logger.info(`Sent ${eventType} event to Takaro: ${playerName} (gameId: ${player.gameId})`);
    }
  } catch (error: any) {
    logger.error(`Error sending player event: ${error.message}`);
  }
}

/**
 * Initialize Palworld REST API client
 */
function initPalworldApi() {
  const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

  palworldApi = axios.create({
    baseURL: PALWORLD_BASE_URL,
    timeout: 10000,
    headers: {
      'Accept': 'application/json',
      'Authorization': `Basic ${authString}`
    }
  });

  logger.info(`Palworld API client initialized for ${PALWORLD_BASE_URL}`);
}

/**
 * Connect to Takaro WebSocket server
 */
function connectToTakaro() {
  if (takaroWs && takaroWs.readyState === WebSocket.OPEN) {
    logger.info('Already connected to Takaro');
    return;
  }

  logger.info(`Connecting to Takaro at ${TAKARO_WS_URL} (attempt ${reconnectAttempts + 1})`);
  takaroWs = new WebSocket(TAKARO_WS_URL);

  takaroWs.on('open', () => {
    logger.info('Connected to Takaro WebSocket');
    reconnectAttempts = 0;
    sendIdentify();
  });

  takaroWs.on('message', (data: WebSocket.Data) => {
    try {
      const message = JSON.parse(data.toString());
      handleTakaroMessage(message);
    } catch (error) {
      metrics.errors++;
      logger.error(`Failed to parse Takaro message: ${error}`);
    }
  });

  takaroWs.on('close', () => {
    logger.warn('Disconnected from Takaro');
    isConnectedToTakaro = false;
    scheduleReconnect();
  });

  takaroWs.on('error', (error) => {
    logger.error(`Takaro WebSocket error: ${error.message}`);
  });
}

/**
 * Send identify message to Takaro
 */
function sendIdentify() {
  if (!takaroWs || takaroWs.readyState !== WebSocket.OPEN) {
    logger.error('Cannot send identify - not connected');
    return;
  }

  const identifyMessage: any = {
    type: 'identify',
    payload: {
      identityToken: IDENTITY_TOKEN
    }
  };

  if (REGISTRATION_TOKEN) {
    identifyMessage.payload.registrationToken = REGISTRATION_TOKEN;
  }

  logger.info('Sending identify message to Takaro');
  takaroWs.send(JSON.stringify(identifyMessage));
}

/**
 * Handle messages from Takaro
 */
function handleTakaroMessage(message: any) {
  switch (message.type) {
    case 'identifyResponse':
      handleIdentifyResponse(message);
      break;

    case 'connected':
      logger.info('Takaro confirmed connection');
      break;

    case 'request':
      handleTakaroRequest(message);
      break;

    case 'ping':
      sendPong();
      break;

    case 'error':
      logger.error(`Takaro error: ${JSON.stringify(message.payload || message)}`);
      break;

    default:
      logger.warn(`Unknown message type from Takaro: ${message.type}`);
  }
}

/**
 * Handle identify response from Takaro
 */
function handleIdentifyResponse(message: any) {
  if (message.payload?.error) {
    logger.error(`Identification failed: ${JSON.stringify(message.payload.error, null, 2)}`);
    logger.error(`Full message: ${JSON.stringify(message, null, 2)}`);
  } else {
    logger.info('Successfully identified with Takaro');
    isConnectedToTakaro = true;
  }
}

/**
 * Handle requests from Takaro
 */
async function handleTakaroRequest(message: any) {
  const { requestId, payload } = message;
  const { action, args } = payload;

  metrics.requestsReceived++;
  metrics.lastRequestTime = Date.now();

  let responsePayload: any;

  try {
    switch (action) {
      case 'testReachability':
        // Check if server is running (using cached flag, like Astroneer checks isConnectedToRcon)
        responsePayload = {
          connectable: isServerRunning,
          reason: isServerRunning ? null : 'Palworld server not running'
        };
        break;

      case 'getPlayers':
        responsePayload = await handleGetPlayers();
        break;

      case 'getServerInfo':
        responsePayload = await handleGetServerInfo();
        break;

      case 'getServerSettings':
        responsePayload = await handleGetServerSettings();
        break;

      case 'getServerMetrics':
        responsePayload = await handleGetServerMetrics();
        break;

      case 'sendMessage':
        // Discord→Game messages: module already formats as "name: message"
        if (args) {
          const messageArgs = typeof args === 'string' ? JSON.parse(args) : args;
          const message = messageArgs.message || '';

          // Use message as-is (already formatted by module)
          responsePayload = await handleExecuteCommand({
            command: `announce ${message}`
          });
        } else {
          responsePayload = { success: false, error: 'No message provided' };
        }
        break;

      case 'executeCommand':
      case 'executeConsoleCommand':
        responsePayload = await handleExecuteCommand(args);
        break;

      case 'kickPlayer':
        responsePayload = await handleKickPlayer(args);
        break;

      case 'banPlayer':
        responsePayload = await handleBanPlayer(args);
        break;

      case 'unbanPlayer':
        responsePayload = await handleUnbanPlayer(args);
        break;

      case 'stopServer':
        responsePayload = await handleStopServer();
        break;

      case 'listBans':
        responsePayload = [];
        break;

      case 'getPlayerLocation':
        responsePayload = await handleGetPlayerLocation(args);
        break;

      case 'getPlayerInventory':
        responsePayload = await handleGetPlayerInventory(args);
        break;

      case 'teleportPlayer':
        responsePayload = await handleTeleportPlayer(args);
        break;

      case 'listItems':
        // Palworld API doesn't provide item list, return empty array
        responsePayload = [];
        break;

      case 'listEntities':
        // Palworld API doesn't provide entity list, return empty array
        responsePayload = [];
        break;

      case 'listLocations':
        // Palworld API doesn't provide location list, return empty array
        responsePayload = [];
        break;

      default:
        logger.warn(`Unknown action: ${action}`);
        responsePayload = { error: `Unknown action: ${action}` };
    }
  } catch (error: any) {
    metrics.errors++;
    logger.error(`Error handling ${action}: ${error.message}`);
    logger.error(`Error stack: ${error.stack}`);
    responsePayload = { error: error.message };
  }

  sendTakaroResponse(requestId, responsePayload);
}

/**
 * Check if Palworld server process is running and update flag
 */
async function checkServerStatus() {
  try {
    const { stdout } = await execPromise('tasklist /FI "IMAGENAME eq PalServer-Win64-Shipping-Cmd.exe" /NH');
    const wasRunning = isServerRunning;
    // tasklist truncates long names, so check for the truncated version
    isServerRunning = stdout.includes('PalServer-Win64-Shipping');

    if (isServerRunning !== wasRunning) {
      logger.info(`Palworld server status changed: ${isServerRunning ? 'ONLINE' : 'OFFLINE'}`);
    }
  } catch (error: any) {
    logger.error(`Failed to check Palworld server process: ${error.message}`);
    isServerRunning = false;
  }
}

/**
 * Start periodic server status checks
 */
function startServerMonitoring() {
  // Do initial check
  checkServerStatus();

  // Set up periodic checks
  serverCheckInterval = setInterval(() => {
    checkServerStatus();
  }, SERVER_CHECK_INTERVAL);

  logger.info(`Started server monitoring (checking every ${SERVER_CHECK_INTERVAL / 1000}s)`);
}

/**
 * Get current players from Palworld server
 */
async function handleGetPlayers(detectChanges: boolean = false) {
  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const config = {
      method: 'get',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/players`,
      headers: {
        'Accept': 'application/json',
        'Authorization': `Basic ${authString}`
      }
    };

    const response = await axios(config);
    const players = response.data.players || [];

    const mappedPlayers = players.map((player: any) => ({
      gameId: String(player.userId),
      name: String(player.name), // Use in-game character name (what PlayerNamePrivate actually returns)
      platformId: `palworld:${player.userId}`,
      steamId: String(player.userId),
      ip: player.ip || undefined,
      ping: player.ping !== undefined ? player.ping : undefined,
      positionX: player.location_x !== undefined ? player.location_x : (player.x !== undefined ? player.x : undefined),
      positionY: player.location_y !== undefined ? player.location_y : (player.y !== undefined ? player.y : undefined),
      positionZ: player.location_z !== undefined ? player.location_z : (player.z !== undefined ? player.z : undefined)
    }));

    // Always cache player data
    for (const player of mappedPlayers) {
      playerCache.set(player.gameId, { gameId: player.gameId, name: player.name, steamId: player.steamId });
    }

    // Only detect connect/disconnect during polling interval (not on Takaro's frequent getPlayers requests)
    if (detectChanges && isConnectedToTakaro) {
      const currentPlayers = new Set<string>(mappedPlayers.map((p: any) => p.gameId));

      logger.debug(`[POLL] Current: ${currentPlayers.size} players, Last known: ${lastKnownPlayers.size} players`);

      // Only detect changes after first poll to avoid false positives on startup
      if (hasInitializedPlayerList) {
        // Detect new players (connected)
        for (const player of mappedPlayers) {
          if (!lastKnownPlayers.has(player.gameId)) {
            logger.info(`[CONNECT DETECTED] Player joined: ${player.name} (gameId: ${player.gameId})`);
            await sendPlayerEvent('player-connected', player.name, new Date().toISOString(), player.gameId);
          }
        }

        // Detect disconnected players
        for (const lastPlayerId of lastKnownPlayers) {
          if (!currentPlayers.has(lastPlayerId)) {
            const cachedPlayer = playerCache.get(lastPlayerId);
            const playerName = cachedPlayer ? cachedPlayer.name : lastPlayerId;
            logger.info(`[DISCONNECT DETECTED] Player left: ${playerName} (gameId: ${lastPlayerId})`);
            await sendPlayerEvent('player-disconnected', playerName, new Date().toISOString(), lastPlayerId);
          }
        }
      } else {
        logger.debug(`[POLL] First poll - initializing player list with ${currentPlayers.size} players`);
        hasInitializedPlayerList = true;
      }

      lastKnownPlayers = currentPlayers;
    }

    return mappedPlayers;
  } catch (error: any) {
    logger.error(`Failed to get players: ${error.message}`);
    return [];
  }
}

/**
 * Get server info from Palworld server
 */
async function handleGetServerInfo() {
  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const config = {
      method: 'get',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/info`,
      headers: {
        'Accept': 'application/json',
        'Authorization': `Basic ${authString}`
      }
    };

    const response = await axios(config);
    logger.info(`Got server info: ${response.data.servername}`);
    return response.data;
  } catch (error: any) {
    logger.error(`Failed to get server info: ${error.message}`);
    return {};
  }
}

/**
 * Get server settings from Palworld server
 */
async function handleGetServerSettings() {
  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const config = {
      method: 'get',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/settings`,
      headers: {
        'Accept': 'application/json',
        'Authorization': `Basic ${authString}`
      }
    };

    const response = await axios(config);
    logger.info('Got server settings');
    return response.data;
  } catch (error: any) {
    logger.error(`Failed to get server settings: ${error.message}`);
    return {};
  }
}

/**
 * Get server metrics from Palworld server
 */
async function handleGetServerMetrics() {
  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const config = {
      method: 'get',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/metrics`,
      headers: {
        'Accept': 'application/json',
        'Authorization': `Basic ${authString}`
      }
    };

    const response = await axios(config);
    logger.info('Got server metrics');
    return response.data;
  } catch (error: any) {
    logger.error(`Failed to get server metrics: ${error.message}`);
    return {};
  }
}

// Track active location requests to prevent duplicates
const activeLocationRequests = new Set<string>();

/**
 * Get player location by player ID
 */
async function handleGetPlayerLocation(args: any) {
  try {
    const locationArgs = typeof args === 'string' ? JSON.parse(args) : args;
    const playerId = locationArgs.gameId || locationArgs.playerId || locationArgs.userId;

    if (!playerId) {
      logger.error('No player ID provided for getPlayerLocation');
      return { x: 0, y: 0, z: 0 };
    }

    // Check if request already in progress for this player
    if (activeLocationRequests.has(playerId)) {
      logger.debug(`[LOCATION] Request already in progress for ${playerId}, skipping duplicate`);
      return { x: 0, y: 0, z: 0 };
    }

    // Get player's actual name from cache (Lua needs display name, not Steam ID)
    const cachedPlayer = playerCache.get(playerId);
    if (!cachedPlayer) {
      logger.warn(`[LOCATION] Player ${playerId} not in cache`);
      return { x: 0, y: 0, z: 0 };
    }

    const playerName = cachedPlayer.name;

    // Mark request as active
    activeLocationRequests.add(playerId);

    // Generate unique request ID
    const requestId = `loc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    // Queue location request for Lua to process (using display name)
    locationRequestQueue.push({
      playerName: playerName,
      requestId,
      timestamp: new Date().toISOString()
    });

    logger.debug(`[LOCATION] Queued request ${requestId} for ${playerName} (${playerId})`);

    // Wait for response from Lua (with timeout)
    const timeout = 5000;
    const startTime = Date.now();

    while (Date.now() - startTime < timeout) {
      const responseIndex = locationResponseQueue.findIndex(r => r.requestId === requestId);

      if (responseIndex !== -1) {
        const response = locationResponseQueue[responseIndex];
        locationResponseQueue.splice(responseIndex, 1);

        logger.debug(`[LOCATION] Got response for ${playerId}: (${response.x}, ${response.y}, ${response.z})`);

        // Remove from active requests
        activeLocationRequests.delete(playerId);

        // Remove the request from queue now that we got response
        const queueIndex = locationRequestQueue.findIndex(r => r.requestId === requestId);
        if (queueIndex !== -1) {
          locationRequestQueue.splice(queueIndex, 1);
        }

        return {
          x: response.x,
          y: response.y,
          z: response.z
        };
      }

      await new Promise(resolve => setTimeout(resolve, 100));
    }

    // Remove from active requests AND delete from queue on timeout
    activeLocationRequests.delete(playerId);
    const queueIndex = locationRequestQueue.findIndex(r => r.requestId === requestId);
    if (queueIndex !== -1) {
      locationRequestQueue.splice(queueIndex, 1);
      logger.debug(`[LOCATION] Removed timed out request ${requestId} from queue`);
    }
    logger.warn(`[LOCATION] Timeout waiting for location of ${playerId}`);
    return { x: 0, y: 0, z: 0 };

  } catch (error: any) {
    // Remove from active requests on error
    if (args && (args.gameId || args.playerId || args.userId)) {
      const playerId = args.gameId || args.playerId || args.userId;
      activeLocationRequests.delete(playerId);
    }
    logger.error(`Failed to get player location: ${error.message}`);
    return { x: 0, y: 0, z: 0 };
  }
}

/**
 * Get player inventory from cache
 */
async function handleGetPlayerInventory(args: any) {
  try {
    const inventoryArgs = typeof args === 'string' ? JSON.parse(args) : args;
    const playerId = inventoryArgs.gameId || inventoryArgs.playerId || inventoryArgs.userId;

    if (!playerId) {
      logger.error('No player ID provided for getPlayerInventory');
      return [];
    }

    // Try to find inventory by player ID or name
    // Since we cache by name, we need to get the player's name first
    const players = await handleGetPlayers();
    const player = players.find((p: any) => p.gameId === playerId || p.steamId === playerId || p.name === playerId);

    if (!player) {
      logger.warn(`Player ${playerId} not found for inventory lookup`);
      return [];
    }

    const cachedInventory = playerInventories.get(player.name);

    if (!cachedInventory) {
      return [];
    }

    return cachedInventory.inventory;
  } catch (error: any) {
    logger.error(`Failed to get player inventory: ${error.message}`);
    return [];
  }
}

/**
 * Teleport a player to another player's location OR to specific coordinates
 */
async function handleTeleportPlayer(args: any) {
  const teleportArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const sourcePlayer = teleportArgs.sourcePlayer || teleportArgs.playerId;
  const targetPlayer = teleportArgs.targetPlayer || teleportArgs.destinationPlayer;
  const x = teleportArgs.x;
  const y = teleportArgs.y;
  const z = teleportArgs.z;

  if (!sourcePlayer) {
    return { success: false, error: 'sourcePlayer is required' };
  }

  // Check if coordinate-based teleport
  const isCoordinateTeleport = x !== undefined && y !== undefined && z !== undefined;

  if (!isCoordinateTeleport && !targetPlayer) {
    return { success: false, error: 'Either targetPlayer or coordinates (x, y, z) are required' };
  }

  try {
    // Get all online players to validate source
    const players = await handleGetPlayers();

    // Find source player
    const source = players.find((p: any) =>
      p.name.toLowerCase() === sourcePlayer.toLowerCase() ||
      p.gameId === sourcePlayer
    );

    if (!source) {
      return { success: false, error: `Source player "${sourcePlayer}" not found online` };
    }

    // Handle coordinate teleport
    if (isCoordinateTeleport) {
      teleportQueue.push({
        sourcePlayer: source.name,
        x,
        y,
        z,
        timestamp: new Date().toISOString()
      });

      logger.info(`[TELEPORT] Queued ${source.name} -> (${x}, ${y}, ${z})`);

      return {
        success: true,
        message: `Teleporting ${source.name} to coordinates (${x}, ${y}, ${z})`
      };
    }

    // Handle player-to-player teleport
    const target = players.find((p: any) =>
      p.name.toLowerCase() === targetPlayer.toLowerCase() ||
      p.gameId === targetPlayer
    );

    if (!target) {
      return { success: false, error: `Target player "${targetPlayer}" not found online` };
    }

    // Add to teleport queue - Lua mod will look up target's position in-game
    teleportQueue.push({
      sourcePlayer: source.name,
      targetPlayer: target.name,
      timestamp: new Date().toISOString()
    });

    logger.info(`[TELEPORT] Queued ${source.name} -> ${target.name}`);

    return {
      success: true,
      message: `Teleporting ${source.name} to ${target.name}`
    };
  } catch (error: any) {
    logger.error(`Failed to teleport player: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Execute command on Palworld server or console command
 */
async function handleExecuteCommand(args: any) {
  const cmdArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const command = cmdArgs.command || cmdArgs.message || '';

  logger.info(`Executing command: ${command}`);

  // Parse command and arguments
  const parts = command.trim().split(/\s+/);
  const cmd = parts[0].toLowerCase();
  const cmdArguments = parts.slice(1);

  // Handle console commands
  switch (cmd) {
    case 'help':
      return {
        success: true,
        rawResult: `Available Commands:
  help - Show this help message
  players - List all online players
  serverinfo - Get server information
  metrics - Get server metrics
  settings - Get server settings
  announce <message> - Send announcement to server
  save - Save the world
  shutdown [seconds] [message] - Shutdown server (default: 10s)
  stop - Stop server immediately
  ban <player> - Ban a player by name
  kick <player> - Kick a player by name
  unban <steamid> - Unban a player by Steam ID
  teleportplayer <source> <target> - Teleport source player to target player`
      };

    case 'players':
    case 'listplayers':
      try {
        const players = await handleGetPlayers();
        if (players.length === 0) {
          return { success: true, rawResult: 'No players online' };
        }
        const playerList = players.map((p: any) =>
          `  ${p.name} (ID: ${p.gameId}, IP: ${p.ip || 'N/A'}, Ping: ${p.ping || 'N/A'})`
        ).join('\n');
        return {
          success: true,
          rawResult: `Online Players (${players.length}):\n${playerList}`
        };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'serverinfo':
    case 'info':
      try {
        const info = await handleGetServerInfo();
        return {
          success: true,
          rawResult: `Server Information:\n${JSON.stringify(info, null, 2)}`
        };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'metrics':
      try {
        const metrics = await handleGetServerMetrics();
        return {
          success: true,
          rawResult: `Server Metrics:\n${JSON.stringify(metrics, null, 2)}`
        };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'settings':
      try {
        const settings = await handleGetServerSettings();
        return {
          success: true,
          rawResult: `Server Settings:\n${JSON.stringify(settings, null, 2)}`
        };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'announce':
      const announceMessage = cmdArguments.join(' ');
      if (!announceMessage) {
        return { success: false, rawResult: 'Usage: announce <message>' };
      }
      try {
        const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');
        const data = JSON.stringify({ message: announceMessage });
        const config = {
          method: 'post',
          maxBodyLength: Infinity,
          url: `${PALWORLD_BASE_URL}/v1/api/announce`,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Basic ${authString}`
          },
          data: data
        };
        await axios(config);
        logger.info('Message announced successfully');
        return { success: true, rawResult: `Announced: "${announceMessage}"` };
      } catch (error: any) {
        logger.error(`Failed to announce message: ${error.message}`);
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'save':
      try {
        const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');
        const config = {
          method: 'post',
          maxBodyLength: Infinity,
          url: `${PALWORLD_BASE_URL}/v1/api/save`,
          headers: { 'Authorization': `Basic ${authString}` }
        };
        await axios(config);
        logger.info('World saved successfully');
        return { success: true, rawResult: 'World saved successfully' };
      } catch (error: any) {
        logger.error(`Failed to save world: ${error.message}`);
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'shutdown':
      try {
        const waittime = parseInt(cmdArguments[0]) || 10;
        const shutdownMsg = cmdArguments.slice(1).join(' ') || 'Server shutting down';
        const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');
        const data = JSON.stringify({ waittime, message: shutdownMsg });
        const config = {
          method: 'post',
          maxBodyLength: Infinity,
          url: `${PALWORLD_BASE_URL}/v1/api/shutdown`,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Basic ${authString}`
          },
          data: data
        };
        await axios(config);
        logger.info('Server shutdown initiated');
        return { success: true, rawResult: `Server shutting down in ${waittime} seconds` };
      } catch (error: any) {
        logger.error(`Failed to shutdown server: ${error.message}`);
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'stop':
      try {
        const result = await handleStopServer();
        return result.success
          ? { success: true, rawResult: 'Server stopped immediately' }
          : { success: false, rawResult: result.error };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'ban':
      if (cmdArguments.length === 0) {
        return { success: false, rawResult: 'Usage: ban <player_name>' };
      }
      try {
        const playerName = cmdArguments.join(' ');
        const players = await handleGetPlayers();
        const player = players.find((p: any) => p.name.toLowerCase() === playerName.toLowerCase());
        if (!player) {
          return { success: false, rawResult: `Player "${playerName}" not found online` };
        }
        const result = await handleBanPlayer({ gameId: player.gameId });
        return result.success
          ? { success: true, rawResult: `Banned player: ${player.name} (${player.gameId})` }
          : { success: false, rawResult: result.error };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'kick':
      if (cmdArguments.length === 0) {
        return { success: false, rawResult: 'Usage: kick <player_name>' };
      }
      try {
        const playerName = cmdArguments.join(' ');
        const players = await handleGetPlayers();
        const player = players.find((p: any) => p.name.toLowerCase() === playerName.toLowerCase());
        if (!player) {
          return { success: false, rawResult: `Player "${playerName}" not found online` };
        }
        const result = await handleKickPlayer({ gameId: player.gameId });
        return result.success
          ? { success: true, rawResult: `Kicked player: ${player.name} (${player.gameId})` }
          : { success: false, rawResult: result.error };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'unban':
      if (cmdArguments.length === 0) {
        return { success: false, rawResult: 'Usage: unban <steam_id>' };
      }
      try {
        const userId = cmdArguments[0];
        const result = await handleUnbanPlayer({ gameId: userId });
        return result.success
          ? { success: true, rawResult: `Unbanned user: ${userId}` }
          : { success: false, rawResult: result.error };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'teleportplayer':
      if (cmdArguments.length < 2) {
        return { success: false, rawResult: 'Usage: teleportplayer <source> <target> OR teleportplayer <source> <x> <y> <z>' };
      }
      try {
        const sourcePlayer = cmdArguments[0];

        // Check if it's coordinate-based (3 numeric arguments after source)
        if (cmdArguments.length === 4) {
          const x = parseFloat(cmdArguments[1]);
          const y = parseFloat(cmdArguments[2]);
          const z = parseFloat(cmdArguments[3]);

          if (!isNaN(x) && !isNaN(y) && !isNaN(z)) {
            const result = await handleTeleportPlayer({
              sourcePlayer,
              x,
              y,
              z
            });
            return result.success
              ? { success: true, rawResult: result.message || `Teleport queued to (${x}, ${y}, ${z})` }
              : { success: false, rawResult: result.error };
          }
        }

        // Player-to-player teleport
        const targetPlayer = cmdArguments.slice(1).join(' '); // Handle spaces in player names
        const result = await handleTeleportPlayer({
          sourcePlayer,
          targetPlayer
        });
        return result.success
          ? { success: true, rawResult: result.message || 'Teleport queued' }
          : { success: false, rawResult: result.error };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    case 'location':
    case 'getlocation':
      if (cmdArguments.length === 0) {
        return { success: false, rawResult: 'Usage: location <player_name_or_gameid>' };
      }
      try {
        const playerIdentifier = cmdArguments.join(' ');
        const location = await handleGetPlayerLocation({ gameId: playerIdentifier, playerId: playerIdentifier, userId: playerIdentifier });
        if (location.x === 0 && location.y === 0 && location.z === 0) {
          return { success: false, rawResult: `Unable to get location for "${playerIdentifier}"` };
        }
        return {
          success: true,
          rawResult: JSON.stringify(location),
          data: location
        };
      } catch (error: any) {
        return { success: false, rawResult: `Error: ${error.message}` };
      }

    default:
      return {
        success: false,
        rawResult: `Unknown command: "${cmd}". Type "help" for available commands.`
      };
  }
}

/**
 * Kick a player from Palworld server
 */
async function handleKickPlayer(args: any) {
  const kickArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const userId = kickArgs.gameId || kickArgs.userId;

  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const data = JSON.stringify({
      userid: userId,
      message: 'You have been kicked from the server'
    });

    const config = {
      method: 'post',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/kick`,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${authString}`
      },
      data: data
    };

    const response = await axios(config);
    logger.info(`Player ${userId} kicked successfully`);
    return { success: true };
  } catch (error: any) {
    logger.error(`Failed to kick player ${userId}: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Ban a player from Palworld server
 */
async function handleBanPlayer(args: any) {
  const banArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const userId = banArgs.gameId || banArgs.userId;

  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const data = JSON.stringify({
      userid: userId,
      message: 'You are banned.'
    });

    const config = {
      method: 'post',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/ban`,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${authString}`
      },
      data: data
    };

    const response = await axios(config);
    logger.info(`Player ${userId} banned successfully`);
    return { success: true };
  } catch (error: any) {
    logger.error(`Failed to ban player ${userId}: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Unban a player from Palworld server
 */
async function handleUnbanPlayer(args: any) {
  const unbanArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const userId = unbanArgs.gameId || unbanArgs.userId;

  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const data = JSON.stringify({
      userid: userId
    });

    const config = {
      method: 'post',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/unban`,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${authString}`
      },
      data: data
    };

    const response = await axios(config);
    logger.info(`Player ${userId} unbanned successfully`);
    return { success: true };
  } catch (error: any) {
    logger.error(`Failed to unban player ${userId}: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Stop the Palworld server immediately
 */
async function handleStopServer() {
  try {
    const authString = Buffer.from(`${PALWORLD_USERNAME}:${PALWORLD_PASSWORD}`).toString('base64');

    const config = {
      method: 'post',
      maxBodyLength: Infinity,
      url: `${PALWORLD_BASE_URL}/v1/api/stop`,
      headers: {
        'Authorization': `Basic ${authString}`
      }
    };

    const response = await axios(config);
    logger.info('Server stop initiated');
    return { success: true, rawResult: 'Server stopped' };
  } catch (error: any) {
    logger.error(`Failed to stop server: ${error.message}`);
    return { success: false, error: error.message };
  }
}

/**
 * Send pong response to Takaro ping
 */
function sendPong() {
  sendToTakaro({ type: 'pong' });
}

/**
 * Send a message to Takaro
 */
function sendToTakaro(message: any) {
  if (!takaroWs || takaroWs.readyState !== WebSocket.OPEN) {
    logger.error(`Cannot send to Takaro - not connected`);
    return false;
  }

  try {
    takaroWs.send(JSON.stringify(message));

    if (message.type === 'response') {
      metrics.responsesSent++;
    }

    return true;
  } catch (error) {
    metrics.errors++;
    logger.error(`Failed to send message to Takaro: ${error}`);
    return false;
  }
}

/**
 * Send a response to Takaro request
 */
function sendTakaroResponse(requestId: string, payload: any) {
  const message = {
    type: 'response',
    requestId: requestId,
    payload: payload
  };

  sendToTakaro(message);
}

/**
 * Schedule reconnection to Takaro with exponential backoff
 */
function scheduleReconnect() {
  if (reconnectTimeout) {
    clearTimeout(reconnectTimeout);
  }

  reconnectAttempts++;

  const exponentialDelay = Math.min(BASE_RECONNECT_DELAY * Math.pow(2, reconnectAttempts - 1), MAX_RECONNECT_DELAY);
  const jitter = Math.random() * exponentialDelay * 0.25;
  const delayMs = exponentialDelay + jitter;

  logger.info(`Scheduling reconnect attempt ${reconnectAttempts} in ${Math.round(delayMs / 1000)}s`);

  reconnectTimeout = setTimeout(() => {
    logger.info('Attempting to reconnect to Takaro...');
    connectToTakaro();
  }, delayMs);
}

// Initialize Palworld API
initPalworldApi();

// Start server monitoring (like Astroneer's RCON connection state)
startServerMonitoring();

// Start HTTP server for chat endpoint
app.listen(HTTP_PORT, () => {
  logger.info(`HTTP server listening on port ${HTTP_PORT} for chat events`);
});

// Connect to Takaro
connectToTakaro();

// Poll for player changes every 10 seconds (Palworld shows join/leave in console, not accessible via UE4SS)
let pollCount = 0;
setInterval(async () => {
  pollCount++;
  if (isConnectedToTakaro) {
    logger.debug(`[POLL #${pollCount}] Checking for player changes...`);
    await handleGetPlayers(true); // Pass true to enable change detection
  } else {
    logger.debug(`[POLL #${pollCount}] Skipping - not connected to Takaro`);
  }
}, 10000);

// Handle process termination
process.on('SIGINT', () => {
  logger.info('Shutting down...');
  if (takaroWs) {
    takaroWs.close();
  }
  process.exit(0);
});

process.on('SIGTERM', () => {
  logger.info('Shutting down...');
  if (takaroWs) {
    takaroWs.close();
  }
  process.exit(0);
});

logger.info(`Palworld-Takaro Bridge v${VERSION} starting...`);
