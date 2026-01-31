/**
 * SAP RFC TCP Proxy Server
 *
 * A simple TCP proxy that forwards connections to an SAP system.
 * Designed to run in ECS Fargate to enable local Docker containers
 * to connect to SAP when VPN restricts direct connections.
 *
 * Environment Variables:
 *   SAP_TARGET_HOST - SAP system hostname (required)
 *   SAP_TARGET_PORT - SAP RFC port (default: 3300)
 *   LISTEN_PORT     - Port to listen on (default: 3300)
 *   LOG_LEVEL       - Logging verbosity: debug, info, error (default: info)
 */

import net from 'node:net';

// Configuration from environment
const config = {
  targetHost: process.env.SAP_TARGET_HOST,
  targetPort: parseInt(process.env.SAP_TARGET_PORT || '3300', 10),
  listenPort: parseInt(process.env.LISTEN_PORT || '3300', 10),
  logLevel: process.env.LOG_LEVEL || 'info',
};

// Simple logger
const LOG_LEVELS = { debug: 0, info: 1, error: 2 };
const currentLevel = LOG_LEVELS[config.logLevel] ?? LOG_LEVELS.info;

const log = {
  debug: (...args) => currentLevel <= LOG_LEVELS.debug && console.log('[DEBUG]', new Date().toISOString(), ...args),
  info: (...args) => currentLevel <= LOG_LEVELS.info && console.log('[INFO]', new Date().toISOString(), ...args),
  error: (...args) => currentLevel <= LOG_LEVELS.error && console.error('[ERROR]', new Date().toISOString(), ...args),
};

// Validate configuration
if (!config.targetHost) {
  log.error('SAP_TARGET_HOST environment variable is required');
  process.exit(1);
}

// Connection counter for logging
let connectionId = 0;

// Track active connections for graceful shutdown
const activeConnections = new Set();

/**
 * Handle an incoming client connection
 */
function handleConnection(clientSocket) {
  const connId = ++connectionId;
  const clientAddr = `${clientSocket.remoteAddress}:${clientSocket.remotePort}`;

  log.info(`[${connId}] New connection from ${clientAddr}`);

  // Connect to SAP target
  const targetSocket = net.createConnection({
    host: config.targetHost,
    port: config.targetPort,
  });

  // Track this connection pair
  const connectionPair = { client: clientSocket, target: targetSocket };
  activeConnections.add(connectionPair);

  // Pipe data bidirectionally
  clientSocket.pipe(targetSocket);
  targetSocket.pipe(clientSocket);

  // Handle target connection success
  targetSocket.on('connect', () => {
    log.debug(`[${connId}] Connected to SAP ${config.targetHost}:${config.targetPort}`);
  });

  // Handle errors
  clientSocket.on('error', (err) => {
    log.error(`[${connId}] Client error: ${err.message}`);
    targetSocket.destroy();
  });

  targetSocket.on('error', (err) => {
    log.error(`[${connId}] Target error: ${err.message}`);
    clientSocket.destroy();
  });

  // Handle connection close
  const cleanup = (source) => () => {
    log.debug(`[${connId}] ${source} closed connection`);
    clientSocket.destroy();
    targetSocket.destroy();
    activeConnections.delete(connectionPair);
  };

  clientSocket.on('close', cleanup('Client'));
  targetSocket.on('close', cleanup('Target'));

  // Handle timeouts (optional, SAP connections can be long-lived)
  clientSocket.setTimeout(300000); // 5 minutes
  targetSocket.setTimeout(300000);

  clientSocket.on('timeout', () => {
    log.debug(`[${connId}] Client timeout`);
    clientSocket.end();
  });

  targetSocket.on('timeout', () => {
    log.debug(`[${connId}] Target timeout`);
    targetSocket.end();
  });
}

// Create the proxy server
const server = net.createServer(handleConnection);

// Handle server errors
server.on('error', (err) => {
  log.error(`Server error: ${err.message}`);
  process.exit(1);
});

// Graceful shutdown
function shutdown(signal) {
  log.info(`Received ${signal}, shutting down gracefully...`);

  server.close(() => {
    log.info('Server closed, no new connections accepted');
  });

  // Close all active connections
  for (const conn of activeConnections) {
    conn.client.destroy();
    conn.target.destroy();
  }

  // Force exit after 10 seconds
  setTimeout(() => {
    log.info('Forcing exit');
    process.exit(0);
  }, 10000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Start the server
server.listen(config.listenPort, '0.0.0.0', () => {
  log.info('='.repeat(60));
  log.info('SAP RFC TCP Proxy Server');
  log.info('='.repeat(60));
  log.info(`Listening on port ${config.listenPort}`);
  log.info(`Forwarding to ${config.targetHost}:${config.targetPort}`);
  log.info(`Log level: ${config.logLevel}`);
  log.info('='.repeat(60));
});

// Health check endpoint (optional HTTP server for ECS health checks)
if (process.env.HEALTH_CHECK_PORT) {
  const healthPort = parseInt(process.env.HEALTH_CHECK_PORT, 10);
  const http = await import('node:http');

  const healthServer = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'healthy',
        connections: activeConnections.size,
        target: `${config.targetHost}:${config.targetPort}`,
      }));
    } else {
      res.writeHead(404);
      res.end();
    }
  });

  healthServer.listen(healthPort, () => {
    log.info(`Health check endpoint: http://0.0.0.0:${healthPort}/health`);
  });
}
