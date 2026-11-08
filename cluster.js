#!/usr/bin/env node
/**
 * Offline AI Cluster — Multi-Node Distributed Controller CLI
 * Fully dynamic: supports arbitrary N-node heterogeneous clusters.
 * Zero hardcoded hostnames, IPs, or credentials.
 */

const http = require('http');
const net = require('net');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { spawn, exec } = require('child_process');

const REPO_ROOT = path.resolve(__dirname);
const CONFIG_PATH = path.join(REPO_ROOT, 'cluster.config.json');

function loadConfig() {
  let config = {
    coordinator: {
      host: '0.0.0.0',
      port: 8000,
      bridgePort: 50050,
      model: path.join(REPO_ROOT, 'models', 'model.gguf'),
      contextSize: 2048,
      threads: Math.max(2, os.cpus().length - 1)
    },
    workers: [],
    authToken: process.env.CLUSTER_AUTH_TOKEN || ''
  };

  if (fs.existsSync(CONFIG_PATH)) {
    try {
      const fileData = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
      config = { ...config, ...fileData };
      if (fileData.coordinator) config.coordinator = { ...config.coordinator, ...fileData.coordinator };
      if (fileData.workers) config.workers = fileData.workers;
    } catch (e) {
      console.warn(`[Config] Warning: Could not parse ${CONFIG_PATH}: ${e.message}`);
    }
  }

  // Allow environment variables to override or define workers
  if (process.env.CLUSTER_WORKERS) {
    // Comma-separated list of host:port or host:rpcPort:bridgePort
    const entries = process.env.CLUSTER_WORKERS.split(',').map(s => s.trim()).filter(Boolean);
    config.workers = entries.map((entry, idx) => {
      const parts = entry.split(':');
      return {
        name: `Node-${idx + 1}`,
        host: parts[0],
        rpcPort: parseInt(parts[1] || '50052', 10),
        bridgePort: parseInt(parts[2] || '50050', 10),
        threads: 4
      };
    });
  }

  return config;
}

const CONFIG = loadConfig();

function getLocalIpAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        addresses.push({ interface: name, address: iface.address });
      }
    }
  }
  return addresses;
}

function httpRequest(options, postData = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, headers: res.headers, data: body ? JSON.parse(body) : null });
        } catch (e) {
          resolve({ status: res.statusCode, headers: res.headers, raw: body });
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(120000, () => {
      req.destroy();
      reject(new Error('Request timed out'));
    });
    if (postData) {
      req.write(typeof postData === 'string' ? postData : JSON.stringify(postData));
    }
    req.end();
  });
}

function checkPort(host, port, timeout = 1000) {
  return new Promise(resolve => {
    const s = new net.Socket();
    s.setTimeout(timeout);
    s.on('connect', () => { s.destroy(); resolve(true); });
    s.on('timeout', () => { s.destroy(); resolve(false); });
    s.on('error', () => { s.destroy(); resolve(false); });
    s.connect(port, host);
  });
}

function getRpcArgString() {
  if (!CONFIG.workers || CONFIG.workers.length === 0) return '';
  return CONFIG.workers.map(w => `${w.host}:${w.rpcPort}`).join(',');
}

async function cmdStatus() {
  console.log('='.repeat(72));
  console.log(' OFFLINE AI CLUSTER — TOPOLOGY & MULTI-NODE STATUS');
  console.log('='.repeat(72));

  // Dynamic Coordinator Information
  const localIps = getLocalIpAddresses();
  const coordPort = CONFIG.coordinator.port;
  const coordServerUp = await checkPort('127.0.0.1', coordPort);

  console.log(`[Coordinator: ${os.hostname()} (${os.platform()} ${os.arch()})]`);
  console.log(`  Local IPs:     ${localIps.map(i => `${i.address} (${i.interface})`).join(', ') || '127.0.0.1'}`);
  console.log(`  Master Engine: ${coordServerUp ? '✓ ONLINE (Port ' + coordPort + ')' : '○ Offline'}`);
  console.log(`  System RAM:    ${(os.freemem() / 1e9).toFixed(2)} GB free / ${(os.totalmem() / 1e9).toFixed(2)} GB total`);
  console.log(`  Model Config:  ${CONFIG.coordinator.model || 'None'}`);

  // Dynamic Worker Nodes (arbitrary N nodes)
  const workers = CONFIG.workers || [];
  console.log(`\n[Configured Worker Nodes: ${workers.length}]`);

  if (workers.length === 0) {
    console.log('  (No remote workers configured. Define in cluster.config.json or CLUSTER_WORKERS)');
  }

  for (let idx = 0; idx < workers.length; idx++) {
    const w = workers[idx];
    const rpcPort = w.rpcPort || 50052;
    const bridgePort = w.bridgePort || 50050;
    const rpcUp = await checkPort(w.host, rpcPort);
    const bridgeUp = await checkPort(w.host, bridgePort);

    console.log(`\n  Worker #${idx + 1}: ${w.name || w.host}`);
    console.log(`    Address:     ${w.host}`);
    console.log(`    RPC Worker:  ${rpcUp ? `✓ ONLINE (Port ${rpcPort})` : `○ Offline (Port ${rpcPort})`}`);
    console.log(`    Node Bridge: ${bridgeUp ? `✓ ONLINE (Port ${bridgePort})` : `○ Offline (Port ${bridgePort})`}`);

    if (bridgeUp) {
      try {
        const res = await httpRequest({
          hostname: w.host,
          port: bridgePort,
          path: '/api/status',
          headers: { 'X-Cluster-Token': CONFIG.authToken }
        });
        if (res.data) {
          const mem = res.data.memory;
          console.log(`    Remote RAM:  ${mem.usedGB} GB / ${mem.totalGB} GB (${mem.usedPercent}% used)`);
          console.log(`    CPU Cores:   ${res.data.cpus}`);
          if (res.data.models && res.data.models.length > 0) {
            console.log(`    Models:      ${res.data.models.map(m => m.name).join(', ')}`);
          }
        }
      } catch (e) {
        console.log(`    Telemetry:   Error reading telemetry: ${e.message}`);
      }
    }
  }

  console.log('\n' + '='.repeat(72));
}

async function cmdWorkerStart(targetNode) {
  const workers = CONFIG.workers || [];
  if (workers.length === 0) {
    console.error('[-] No worker nodes configured. Add workers to cluster.config.json');
    return;
  }

  const targets = (targetNode !== undefined && workers[targetNode]) 
    ? [workers[targetNode]] 
    : workers;

  for (const w of targets) {
    const bridgePort = w.bridgePort || 50050;
    const rpcPort = w.rpcPort || 50052;
    console.log(`[*] Requesting ${w.name || w.host} to start ggml-rpc-server on port ${rpcPort}...`);
    try {
      const res = await httpRequest({
        hostname: w.host,
        port: bridgePort,
        path: '/api/worker/start',
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
      }, { threads: w.threads || 4, port: rpcPort });

      console.log(`[✓] Response from ${w.name || w.host}:`, res.data || res.raw);
    } catch (e) {
      console.error(`[-] Could not contact bridge on ${w.host}:${bridgePort}:`, e.message);
    }
  }
}

async function cmdWorkerStop(targetNode) {
  const workers = CONFIG.workers || [];
  const targets = (targetNode !== undefined && workers[targetNode]) 
    ? [workers[targetNode]] 
    : workers;

  for (const w of targets) {
    const bridgePort = w.bridgePort || 50050;
    console.log(`[*] Halting ggml-rpc-server on ${w.name || w.host}...`);
    try {
      const res = await httpRequest({
        hostname: w.host,
        port: bridgePort,
        path: '/api/worker/stop',
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
      });
      console.log(`[✓] Response from ${w.name || w.host}:`, res.data || res.raw);
    } catch (e) {
      console.error(`[-] Error contacting ${w.host}:`, e.message);
    }
  }
}

async function cmdExec(targetNode, command) {
  const workers = CONFIG.workers || [];
  if (workers.length === 0) {
    console.error('[-] No worker nodes configured.');
    return;
  }

  let node = workers[0];
  let cmd = command;

  // Check if first arg is a node index
  if (!isNaN(parseInt(targetNode, 10)) && workers[parseInt(targetNode, 10)]) {
    node = workers[parseInt(targetNode, 10)];
  } else {
    // Treat targetNode as part of command
    cmd = targetNode + (command ? ' ' + command : '');
  }

  if (!cmd) {
    console.error('Usage: cluster exec [node_index] "<command>"');
    return;
  }

  const bridgePort = node.bridgePort || 50050;
  console.log(`[*] Dispatching command to ${node.name || node.host}: "${cmd}"...`);
  try {
    const res = await httpRequest({
      hostname: node.host,
      port: bridgePort,
      path: '/api/exec',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
    }, { command: cmd });

    if (res.data) {
      if (res.data.stdout) console.log(res.data.stdout.trim());
      if (res.data.stderr) console.error('[STDERR]', res.data.stderr.trim());
      console.log(`[✓] Exit code: ${res.data.exitCode}`);
    } else {
      console.log(res.raw);
    }
  } catch (e) {
    console.error(`[-] Command execution failed on ${node.host}:`, e.message);
  }
}

async function cmdPrompt(userPrompt) {
  if (!userPrompt) {
    userPrompt = "Explain how distributed tensor sharding works across heterogeneous AI nodes. Be concise.";
  }

  console.log('='.repeat(72));
  console.log(` RUNNING CLUSTER INFERENCE PROMPT`);
  console.log('='.repeat(72));
  console.log(`[*] Target: http://127.0.0.1:${CONFIG.coordinator.port}/v1/chat/completions`);
  console.log(`[*] Model:  ${CONFIG.coordinator.model || 'Default'}`);
  console.log(`[*] Prompt: "${userPrompt}"`);

  const payload = JSON.stringify({
    messages: [
      { role: 'system', content: 'You are an expert distributed systems engineer.' },
      { role: 'user', content: userPrompt }
    ],
    temperature: 0.3,
    max_tokens: 300,
    stream: false
  });

  const t0 = process.hrtime.bigint();
  try {
    const res = await httpRequest({
      hostname: '127.0.0.1',
      port: CONFIG.coordinator.port,
      path: '/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    }, payload);

    const t1 = process.hrtime.bigint();
    const elapsed = Number(t1 - t0) / 1e9;

    if (res.data && res.data.choices) {
      const text = res.data.choices[0].message.content.trim();
      const usage = res.data.usage || {};
      const compTokens = usage.completion_tokens || 0;
      const tps = compTokens > 0 ? (compTokens / elapsed).toFixed(2) : '0';

      console.log('\n' + '='.repeat(72));
      console.log(text);
      console.log('='.repeat(72));
      console.log(`[*] Latency:      ${elapsed.toFixed(2)}s`);
      console.log(`[*] Output Speed: ${tps} tokens/sec (${compTokens} tokens)`);
      console.log('='.repeat(72));
    } else {
      console.log(res.raw || res.data);
    }
  } catch (e) {
    console.error('[-] Inference Failed:', e.message);
    console.log('[*] Tip: Make sure Master Coordinator is running (`cluster coordinator-start`)');
  }
}

function cmdRdp(targetIndex) {
  const workers = CONFIG.workers || [];
  const node = workers[targetIndex || 0];
  if (!node) {
    console.error('[-] No target node configured for RDP.');
    return;
  }
  console.log(`[*] Launching RDP connection to ${node.name || node.host} (${node.host})...`);
  const rdp = spawn('mstsc.exe', [`/v:${node.host}`], { detached: true, stdio: 'ignore' });
  rdp.unref();
  console.log('[✓] RDP client launched.');
}

function printHelp() {
  console.log(`
Offline AI Cluster — Multi-Node CLI Controller

Usage:
  cluster <command> [arguments]
  node cluster.js <command> [arguments]

Multi-Node Commands:
  status                     Check health, ports, and telemetry across all nodes
  prompt "<text>"            Send an inference prompt to the distributed cluster
  worker-start [node_idx]    Start the ggml-rpc-server on all workers (or target node)
  worker-stop [node_idx]     Stop the ggml-rpc-server on all workers (or target node)
  exec [node_idx] "<cmd>"    Run a shell command on a worker node and get output
  rdp [node_idx]             Open Remote Desktop connection to a worker node
  update                     Check and hot-update llama.cpp binaries from upstream
  rpc-args                   Print the generated --rpc argument string for llama-server
  help                       Display this manual

Configuration:
  Settings are loaded dynamically from cluster.config.json (or CLUSTER_WORKERS env).
`);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] ? args[0].toLowerCase() : 'status';

  switch (command) {
    case 'status':
      await cmdStatus();
      break;
    case 'worker-start':
      await cmdWorkerStart(args[1] ? parseInt(args[1], 10) : undefined);
      break;
    case 'worker-stop':
      await cmdWorkerStop(args[1] ? parseInt(args[1], 10) : undefined);
      break;
    case 'exec':
      await cmdExec(args[1], args.slice(2).join(' '));
      break;
    case 'prompt':
      await cmdPrompt(args.slice(1).join(' '));
      break;
    case 'rdp':
      cmdRdp(args[1] ? parseInt(args[1], 10) : 0);
      break;
    case 'rpc-args':
      console.log(getRpcArgString());
      break;
    case 'update':
      require('./scripts/updater.js').runUpdate();
      break;
    case 'help':
    case '--help':
    case '-h':
      printHelp();
      break;
    default:
      console.log(`Unknown command: ${command}`);
      printHelp();
      break;
  }
}

if (require.main === module) {
  main();
}

module.exports = { CONFIG, httpRequest, checkPort, getRpcArgString, loadConfig };
