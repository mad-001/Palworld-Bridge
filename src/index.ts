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

      case 'listBans':
        responsePayload = [];
        break;

      case 'getPlayerLocation':
        responsePayload = { x: 0, y: 0, z: 0 };
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
    isServerRunning = stdout.includes('PalServer-Win64-Shipping-Cmd.exe');

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
  // Try multiple endpoint variations
  const endpoints = ['/v1/api/players', '/api/players', '/players', '/api/rest-api/players'];

  for (const endpoint of endpoints) {
    try {
      const response = await palworldApi.get(endpoint);
      const players = response.data.players || [];

      logger.info(`Successfully got players from ${endpoint}`);
      return players.map((player: any) => ({
        gameId: String(player.userId),
        name: String(player.name),
        platformId: `palworld:${player.userId}`,
        steamId: String(player.userId),
        ip: player.ip || undefined,
        ping: player.ping !== undefined ? player.ping : undefined
      }));
    } catch (error: any) {
      if (error.response?.status === 404 && endpoint !== endpoints[endpoints.length - 1]) {
        continue; // Try next endpoint
      }
      logger.error(`Failed to get players from ${endpoint}: ${error}`);
    }
  }

  return [];
}

/**
 * Execute command on Palworld server
 */
async function handleExecuteCommand(args: any) {
  const cmdArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const command = cmdArgs.command || cmdArgs.message || '';

  logger.info(`Executing command: ${command}`);

  // Handle announce/message commands
  if (command.toLowerCase().includes('announce') || cmdArgs.message) {
    const message = cmdArgs.message || command;
    try {
      await palworldApi.post('/api/rest-api/announce', { message });
      return {
        success: true,
        rawResult: 'Message announced'
      };
    } catch (error: any) {
      return {
        success: false,
        rawResult: `Error: ${error.message}`
      };
    }
  }

  // Handle save command
  if (command.toLowerCase().includes('save')) {
    try {
      await palworldApi.post('/api/rest-api/save');
      return {
        success: true,
        rawResult: 'World saved'
      };
    } catch (error: any) {
      return {
        success: false,
        rawResult: `Error: ${error.message}`
      };
    }
  }

  // Handle shutdown command
  if (command.toLowerCase().includes('shutdown')) {
    try {
      await palworldApi.post('/api/rest-api/shutdown', {
        waittime: 10,
        message: 'Server shutting down'
      });
      return {
        success: true,
        rawResult: 'Server shutdown initiated'
      };
    } catch (error: any) {
      return {
        success: false,
        rawResult: `Error: ${error.message}`
      };
    }
  }

  return {
    success: false,
    rawResult: 'Command not supported'
  };
}

/**
 * Kick a player from Palworld server
 */
async function handleKickPlayer(args: any) {
  const kickArgs = typeof args === 'string' ? JSON.parse(args) : args;
  const userId = kickArgs.gameId || kickArgs.userId;

  try {
    await palworldApi.post('/api/rest-api/kick', {
      userid: userId,
      message: 'You have been kicked from the server'
    });
    return { success: true };
  } catch (error: any) {
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
    await palworldApi.post('/api/rest-api/ban', {
      userid: userId,
      message: 'You have been banned from the server'
    });
    return { success: true };
  } catch (error: any) {
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
    await palworldApi.post('/api/rest-api/unban', { userid: userId });
    return { success: true };
  } catch (error: any) {
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
