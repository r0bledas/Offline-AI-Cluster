#!/usr/bin/env node
/**
 * Offline AI Cluster — Unified Controller CLI
 * Seamlessly manages inference, workers, telemetry, and remote operations across T470 and T450.
 */

const http = require('http');
const net = require('net');
const { spawn, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

const CONFIG = {
  coordinator: {
    name: 'T470 (Coordinator)',
    lanIp: '192.168.1.2',
    tailscaleIp: '100.77.73.92',
    bridgePort: 50050,
    serverPort: 8000
  },
  worker: {
    name: 'T450 (Worker)',
    lanIp: '192.168.1.18',
    tailscaleIp: '100.79.207.24',
    bridgePort: 50050,
    rpcPort: 50052
  },
  authToken: '694200',
  defaultModel: 'D:\\llms\\Llama-3.2-1B-Instruct-Q4_K_M.gguf'
};

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
      reject(new Error('Inference request timed out after 120s'));
    });
    if (postData) {
      req.write(typeof postData === 'string' ? postData : JSON.stringify(postData));
    }
    req.end();
  });
}

function checkPort(host, port, timeout = 1200) {
  return new Promise(resolve => {
    const s = new net.Socket();
    s.setTimeout(timeout);
    s.on('connect', () => { s.destroy(); resolve(true); });
    s.on('timeout', () => { s.destroy(); resolve(false); });
    s.on('error', () => { s.destroy(); resolve(false); });
    s.connect(port, host);
  });
}

async function cmdStatus() {
  console.log('='.repeat(70));
  console.log(' OFFLINE AI CLUSTER — STATUS & TOPOLOGY');
  console.log('='.repeat(70));

  // Check coordinator
  const coordServerUp = await checkPort('127.0.0.1', CONFIG.coordinator.serverPort);
  console.log(`[Coordinator: T470]`);
  console.log(`  LAN IP:        ${CONFIG.coordinator.lanIp}`);
  console.log(`  Tailscale IP:  ${CONFIG.coordinator.tailscaleIp}`);
  console.log(`  Master Server: ${coordServerUp ? '✓ ONLINE (Port ' + CONFIG.coordinator.serverPort + ')' : '○ Offline'}`);

  // Check worker
  const workerRpcUp = await checkPort(CONFIG.worker.lanIp, CONFIG.worker.rpcPort);
  const workerBridgeUp = await checkPort(CONFIG.worker.lanIp, CONFIG.worker.bridgePort);

  console.log(`\n[Worker: T450]`);
  console.log(`  LAN IP:        ${CONFIG.worker.lanIp}`);
  console.log(`  Tailscale IP:  ${CONFIG.worker.tailscaleIp}`);
  console.log(`  RPC Worker:    ${workerRpcUp ? '✓ ONLINE (Port ' + CONFIG.worker.rpcPort + ')' : '○ Offline'}`);
  console.log(`  Cluster Bridge:${workerBridgeUp ? '✓ ONLINE (Port ' + CONFIG.worker.bridgePort + ')' : '○ Offline'}`);

  if (workerBridgeUp) {
    try {
      const res = await httpRequest({
        hostname: CONFIG.worker.lanIp,
        port: CONFIG.worker.bridgePort,
        path: '/api/status',
        headers: { 'X-Cluster-Token': CONFIG.authToken }
      });
      if (res.data) {
        const mem = res.data.memory;
        console.log(`  System RAM:    ${mem.usedGB} GB / ${mem.totalGB} GB (${mem.usedPercent}% used)`);
        console.log(`  CPU Cores:     ${res.data.cpus}`);
        if (res.data.models && res.data.models.length > 0) {
          console.log(`  Models Found:  ${res.data.models.map(m => m.name).join(', ')}`);
        }
      }
    } catch (e) {
      console.log(`  Telemetry:     Error fetching: ${e.message}`);
    }
  }

  console.log('='.repeat(70));
}

async function cmdWorkerStart() {
  console.log(`[*] Requesting T450 worker to start ggml-rpc-server on port ${CONFIG.worker.rpcPort}...`);
  try {
    const res = await httpRequest({
      hostname: CONFIG.worker.lanIp,
      port: CONFIG.worker.bridgePort,
      path: '/api/worker/start',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
    }, { threads: 4, port: CONFIG.worker.rpcPort });

    console.log('[✓] Response from T450:', res.data || res.raw);
  } catch (e) {
    console.error(`[-] Could not contact bridge on ${CONFIG.worker.lanIp}:${CONFIG.worker.bridgePort}:`, e.message);
    console.log('[*] Tip: Ensure Cluster Bridge is running on T450.');
  }
}

async function cmdWorkerStop() {
  console.log(`[*] Requesting T450 worker to halt ggml-rpc-server...`);
  try {
    const res = await httpRequest({
      hostname: CONFIG.worker.lanIp,
      port: CONFIG.worker.bridgePort,
      path: '/api/worker/stop',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
    });
    console.log('[✓] Response from T450:', res.data || res.raw);
  } catch (e) {
    console.error(`[-] Error:`, e.message);
  }
}

async function cmdExec(command) {
  if (!command) {
    console.error('Usage: cluster.js exec "<command>"');
    process.exit(1);
  }
  console.log(`[*] Dispatching remote command to T450: "${command}"...`);
  try {
    const res = await httpRequest({
      hostname: CONFIG.worker.lanIp,
      port: CONFIG.worker.bridgePort,
      path: '/api/exec',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Cluster-Token': CONFIG.authToken }
    }, { command });

    if (res.data) {
      if (res.data.stdout) console.log(res.data.stdout.trim());
      if (res.data.stderr) console.error('[STDERR]', res.data.stderr.trim());
      console.log(`[✓] Exit code: ${res.data.exitCode}`);
    } else {
      console.log(res.raw);
    }
  } catch (e) {
    console.error(`[-] Execution failed:`, e.message);
  }
}

async function cmdPrompt(userPrompt) {
  if (!userPrompt) {
    userPrompt = "Explain how distributed tensor sharding works across heterogeneous AI nodes. Be concise.";
  }

  console.log('='.repeat(70));
  console.log(` RUNNING CLUSTER INFERENCE PROMPT`);
  console.log('='.repeat(70));
  console.log(`[*] Target: http://127.0.0.1:${CONFIG.coordinator.serverPort}/v1/chat/completions`);
  console.log(`[*] Prompt: "${userPrompt}"`);

  const payload = JSON.stringify({
    messages: [
      { role: 'system', content: 'You are a helpful distributed AI assistant.' },
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
      port: CONFIG.coordinator.serverPort,
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

      console.log('\n' + '='.repeat(70));
      console.log(text);
      console.log('='.repeat(70));
      console.log(`[*] Latency:      ${elapsed.toFixed(2)}s`);
      console.log(`[*] Output Speed: ${tps} tokens/sec (${compTokens} tokens)`);
      console.log('='.repeat(70));
    } else {
      console.log(res.raw || res.data);
    }
  } catch (e) {
    console.error('[-] Inference Failed:', e.message);
    console.log('[*] Tip: Make sure Master Coordinator is running (`cluster coordinator-start`)');
  }
}

function cmdRdp() {
  console.log(`[*] Launching RDP connection to T450 (${CONFIG.worker.lanIp})...`);
  const rdp = spawn('mstsc.exe', [`/v:${CONFIG.worker.lanIp}`], { detached: true, stdio: 'ignore' });
  rdp.unref();
  console.log('[✓] RDP client launched.');
}

function printHelp() {
  console.log(`
Offline AI Cluster — CLI Controller

Usage:
  node cluster.js <command> [arguments]
  cluster <command> [arguments]

Commands:
  status               Check health, ports, and telemetry of T470 & T450
  prompt "<text>"      Send an inference prompt to the distributed cluster
  worker-start         Start the ggml-rpc-server on T450 remotely
  worker-stop          Stop the ggml-rpc-server on T450 remotely
  exec "<command>"     Run any shell command on T450 and receive output
  rdp                  Open Remote Desktop connection to T450 (saved password)
  update               Check and hot-update llama.cpp binaries from upstream
  help                 Display this manual
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
      await cmdWorkerStart();
      break;
    case 'worker-stop':
      await cmdWorkerStop();
      break;
    case 'exec':
      await cmdExec(args.slice(1).join(' '));
      break;
    case 'prompt':
      await cmdPrompt(args.slice(1).join(' '));
      break;
    case 'rdp':
      cmdRdp();
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

module.exports = { CONFIG, httpRequest, checkPort };
