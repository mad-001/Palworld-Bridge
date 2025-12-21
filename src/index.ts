import WebSocket from 'ws';
import winston from 'winston';
import axios, { AxiosInstance } from 'axios';
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

// Version
const VERSION = '1.0.1';

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
    new winston.transports.File({ filename: 'palworld-bridge.log' })
  ]
});

// Configuration
const TAKARO_WS_URL = 'wss://connect.takaro.io/';
const IDENTITY_TOKEN = process.env.IDENTITY_TOKEN || '';
const REGISTRATION_TOKEN = process.env.REGISTRATION_TOKEN || '';

// Palworld REST API Configuration
const PALWORLD_HOST = process.env.PALWORLD_HOST || '127.0.0.1';
const PALWORLD_PORT = parseInt(process.env.PALWORLD_PORT || '8212', 10);
const PALWORLD_BASE_URL = `http://${PALWORLD_HOST}:${PALWORLD_PORT}`;
const PALWORLD_USERNAME = process.env.PALWORLD_USERNAME || 'admin';
const PALWORLD_PASSWORD = process.env.PALWORLD_PASSWORD || '';

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

// Metrics
const metrics = {
  requestsReceived: 0,
  responsesSent: 0,
  errors: 0,
  lastRequestTime: Date.now(),
  startTime: Date.now()
};

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
  logger.info(`Received from Takaro: ${message.type}`);

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
    logger.error(`Identification failed: ${message.payload.error}`);
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

  logger.info(`Takaro request: ${action} (ID: ${requestId})`);

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

  logger.info(`Sending response for ${action}: ${JSON.stringify(responsePayload)}`);
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
async function handleGetPlayers() {
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

    logger.info(`Got ${players.length} players from Palworld server`);
    return players.map((player: any) => ({
      gameId: String(player.userId),
      name: String(player.name),
      platformId: `palworld:${player.userId}`,
      steamId: String(player.userId),
      ip: player.ip || undefined,
      ping: player.ping !== undefined ? player.ping : undefined,
      positionX: player.location_x !== undefined ? player.location_x : (player.x !== undefined ? player.x : undefined),
      positionY: player.location_y !== undefined ? player.location_y : (player.y !== undefined ? player.y : undefined),
      positionZ: player.location_z !== undefined ? player.location_z : (player.z !== undefined ? player.z : undefined)
    }));
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

    // Get all players to find the requested player
    const players = await handleGetPlayers();
    const player = players.find((p: any) => p.gameId === playerId || p.steamId === playerId);

    if (!player) {
      logger.warn(`Player ${playerId} not found for location lookup`);
      return { x: 0, y: 0, z: 0 };
    }

    // Return location in Takaro's expected format
    return {
      x: player.positionX !== undefined ? player.positionX : 0,
      y: player.positionY !== undefined ? player.positionY : 0,
      z: player.positionZ !== undefined ? player.positionZ : 0
    };
  } catch (error: any) {
    logger.error(`Failed to get player location: ${error.message}`);
    return { x: 0, y: 0, z: 0 };
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
  unban <steamid> - Unban a player by Steam ID`
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

// Connect to Takaro
connectToTakaro();

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
