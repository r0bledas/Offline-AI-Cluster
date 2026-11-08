/**
 * Offline AI Cluster - Lightweight Cross-Node Bridge Daemon
 * Runs on worker nodes (e.g. ThinkPad T450) and coordinator nodes (ThinkPad T470).
 * Provides authenticated RPC management, telemetry, file transfer, and remote command execution.
 */

const http = require('http');
const os = require('os');
const fs = require('fs');
const path = require('path');
const { exec, spawn } = require('child_process');

const PORT = process.env.CLUSTER_BRIDGE_PORT || 50050;
const AUTH_TOKEN = process.env.CLUSTER_AUTH_TOKEN || '694200';
const BASE_DIR = path.resolve(__dirname, '..');
const BIN_DIR = path.join(BASE_DIR, 'bin');
const RPC_EXE = path.join(BIN_DIR, 'ggml-rpc-server.exe');

let rpcProcess = null;

function authenticate(req, res) {
  const token = req.headers['x-cluster-token'] || new URL(req.url, `http://${req.headers.host}`).searchParams.get('token');
  if (token !== AUTH_TOKEN) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Unauthorized: Invalid cluster authentication token.' }));
    return false;
  }
  return true;
}

function parseJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function checkPortListening(port) {
  return new Promise(resolve => {
    const net = require('net');
    const s = new net.Socket();
    s.setTimeout(500);
    s.on('connect', () => { s.destroy(); resolve(true); });
    s.on('timeout', () => { s.destroy(); resolve(false); });
    s.on('error', () => { s.destroy(); resolve(false); });
    s.connect(port, '127.0.0.1');
  });
}

function getMemoryInfo() {
  const total = os.totalmem();
  const free = os.freemem();
  const used = total - free;
  return {
    totalBytes: total,
    freeBytes: free,
    usedBytes: used,
    totalGB: (total / (1024 ** 3)).toFixed(2),
    freeGB: (free / (1024 ** 3)).toFixed(2),
    usedGB: (used / (1024 ** 3)).toFixed(2),
    usedPercent: ((used / total) * 100).toFixed(1)
  };
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Cluster-Token');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check / ping (unauthenticated)
  if (pathname === '/api/ping') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', node: os.hostname(), timestamp: Date.now() }));
    return;
  }

  // All other endpoints require authentication
  if (!authenticate(req, res)) return;

  try {
    // 1. TELEMETRY & STATUS
    if (pathname === '/api/status' && req.method === 'GET') {
      const isListening = await checkPortListening(50052);
      
      let models = [];
      ['D:\\llms', 'C:\\llms', path.join(BASE_DIR, 'models')].forEach(dir => {
        if (fs.existsSync(dir)) {
          const files = fs.readdirSync(dir).filter(f => f.endsWith('.gguf')).map(f => {
            const stat = fs.statSync(path.join(dir, f));
            return { name: f, path: path.join(dir, f), sizeGB: (stat.size / (1024 ** 3)).toFixed(2) };
          });
          models.push(...files);
        }
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        node: os.hostname(),
        platform: os.platform(),
        arch: os.arch(),
        uptimeSeconds: Math.floor(os.uptime()),
        cpus: os.cpus().length,
        memory: getMemoryInfo(),
        worker: {
          running: isListening,
          port: 50052,
          pid: rpcProcess ? rpcProcess.pid : null
        },
        models: models
      }, null, 2));
      return;
    }

    // 2. START RPC WORKER
    if (pathname === '/api/worker/start' && req.method === 'POST') {
      const isListening = await checkPortListening(50052);
      if (isListening) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'Worker is already listening on port 50052.' }));
        return;
      }

      const body = await parseJsonBody(req);
      const threads = body.threads || Math.max(2, os.cpus().length - 1);
      const port = body.port || 50052;

      // Locate ggml-rpc-server
      let binaryPath = RPC_EXE;
      if (!fs.existsSync(binaryPath)) {
        // Search in common local folders
        const candidates = [
          path.join(process.cwd(), 'ggml-rpc-server.exe'),
          'C:\\Offline-AI-Cluster\\bin\\ggml-rpc-server.exe',
          'D:\\Offline-AI-Cluster\\bin\\ggml-rpc-server.exe',
          path.join(os.tmpdir(), 'worker_node', 'ggml-rpc-server.exe')
        ];
        binaryPath = candidates.find(p => fs.existsSync(p)) || 'ggml-rpc-server.exe';
      }

      console.log(`[Bridge] Starting RPC worker: ${binaryPath} -H 0.0.0.0 -p ${port} -t ${threads}`);
      rpcProcess = spawn(binaryPath, ['-H', '0.0.0.0', '-p', String(port), '-t', String(threads)], {
        detached: true,
        stdio: 'ignore'
      });
      rpcProcess.unref();

      // Wait 1.5s to verify port
      await new Promise(r => setTimeout(r, 1500));
      const up = await checkPortListening(port);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: up,
        pid: rpcProcess.pid,
        port: port,
        threads: threads,
        binary: binaryPath
      }));
      return;
    }

    // 3. STOP RPC WORKER
    if (pathname === '/api/worker/stop' && req.method === 'POST') {
      exec('taskkill /F /IM ggml-rpc-server.exe', (err, stdout, stderr) => {
        rpcProcess = null;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: 'RPC worker stopped.', stdout: stdout.trim() }));
      });
      return;
    }

    // 4. REMOTE COMMAND EXECUTION
    if (pathname === '/api/exec' && req.method === 'POST') {
      const body = await parseJsonBody(req);
      if (!body.command) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Missing command field.' }));
        return;
      }

      console.log(`[Bridge] Executing remote command: ${body.command}`);
      const timeoutMs = (body.timeoutSec || 30) * 1000;
      exec(body.command, { timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          exitCode: err ? (err.code || 1) : 0,
          stdout: stdout.toString(),
          stderr: stderr.toString(),
          killed: err ? err.killed : false
        }));
      });
      return;
    }

    // 5. FILE UPLOAD (Streamed)
    if (pathname === '/api/upload' && req.method === 'POST') {
      const targetFileName = parsedUrl.searchParams.get('filename') || 'uploaded_file';
      const targetDir = parsedUrl.searchParams.get('dir') || path.join(BASE_DIR, 'bin');
      if (!fs.existsSync(targetDir)) fs.mkdirSync(targetDir, { recursive: true });

      const destPath = path.join(targetDir, path.basename(targetFileName));
      const fileStream = fs.createWriteStream(destPath);

      req.pipe(fileStream);
      fileStream.on('finish', () => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, path: destPath, bytes: fs.statSync(destPath).size }));
      });
      fileStream.on('error', err => {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      });
      return;
    }

    // Default 404
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Endpoint not found.' }));

  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(` Offline AI Cluster — Node Bridge Daemon Online`);
  console.log(` Host:     ${os.hostname()} (${os.platform()} ${os.arch()})`);
  console.log(` Port:     ${PORT}`);
  console.log(` Token:    ${AUTH_TOKEN}`);
  console.log(` Endpoints:`);
  console.log(`   GET  /api/ping         (Health probe)`);
  console.log(`   GET  /api/status       (Telemetry & RPC state)`);
  console.log(`   POST /api/worker/start (Launch ggml-rpc-server)`);
  console.log(`   POST /api/worker/stop  (Halt ggml-rpc-server)`);
  console.log(`   POST /api/exec         (Run remote command)`);
  console.log(`   POST /api/upload       (Stream file transfer)`);
  console.log(`=======================================================`);
});
