#!/usr/bin/env node
/**
 * Offline-AI-Cluster: Real Cross-Node Execution Harness
 * Waits for T450 worker on port 50052, launches Master with --rpc, and runs a long-form task.
 */

const net = require('net');
const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

const T450_IP = '192.168.1.18';
const T450_PORT = 50052;
const MODEL_PATH = 'D:/llms/Llama-3.2-1B-Instruct-Q4_K_M.gguf';
const BIN_DIR = 'D:/Offline-AI-Cluster/bin';
const LLAMA_SERVER = path.join(BIN_DIR, 'llama-server.exe');

function checkPort(host, port, timeout = 1200) {
  return new Promise(resolve => {
    const s = new net.Socket();
    s.setTimeout(timeout);
    s.connect(port, host, () => {
      s.destroy();
      resolve(true);
    });
    s.on('timeout', () => { s.destroy(); resolve(false); });
    s.on('error', () => { s.destroy(); resolve(false); });
  });
}

async function waitForWorker(maxWaitSec = 60) {
  console.log(`[*] Checking for active RPC Worker on T450 (${T450_IP}:${T450_PORT})...`);
  for (let i = 0; i < maxWaitSec; i++) {
    const isUp = await checkPort(T450_IP, T450_PORT);
    if (isUp) {
      console.log(`[✓] T450 RPC Worker is ONLINE at ${T450_IP}:${T450_PORT}!`);
      return true;
    }
    process.stdout.write(`\r    [Waiting] T450 not listening yet... (${i + 1}/${maxWaitSec}s)`);
    await new Promise(r => setTimeout(r, 1000));
  }
  console.log('\n[-] Timeout waiting for T450 worker.');
  return false;
}

async function run() {
  const isReady = await waitForWorker(1800);
  if (!isReady) {
    console.log('\n[!] T450 worker is not active on port 50052.');
    console.log('[!] To connect: Run `start_worker.bat` on the ThinkPad T450.');
    process.exit(1);
  }

  console.log('[*] Starting Master Orchestrator on T470 connected to T450 over LAN...');
  const server = spawn(LLAMA_SERVER, [
    '-m', MODEL_PATH,
    '--rpc', `${T450_IP}:${T450_PORT}`,
    '-c', '2048',
    '-t', '2',
    '--host', '127.0.0.1',
    '--port', '8000'
  ], {
    env: { ...process.env, PATH: `${BIN_DIR};${process.env.PATH}` }
  });

  server.stdout.on('data', d => process.stdout.write(`[SERVER] ${d}`));
  server.stderr.on('data', d => process.stderr.write(`[SERVER ERR] ${d}`));

  // Wait for server to load model
  await new Promise(r => setTimeout(r, 6000));

  console.log('\n[*] Sending LONG-FORM reasoning benchmark task (500 tokens)...');
  const longPrompt = "Write a comprehensive technical guide on how distributed tensor splitting works across network-connected nodes using GGML RPC. Include the tensor sharding mathematical formula, KV cache management, and failure recovery. Be extremely detailed.";

  const payload = JSON.stringify({
    messages: [
      { role: "system", content: "You are an expert distributed systems engineer. Provide detailed, exhaustive explanations." },
      { role: "user", content: longPrompt }
    ],
    temperature: 0.3,
    max_tokens: 500,
    stream: false
  });

  const t0 = process.hrtime.bigint();
  const req = http.request({
    hostname: '127.0.0.1',
    port: 8000,
    path: '/v1/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload)
    }
  }, (res) => {
    let body = '';
    res.on('data', chunk => body += chunk);
    res.on('end', () => {
      const t1 = process.hrtime.bigint();
      const elapsed = Number(t1 - t0) / 1e9;
      const data = JSON.parse(body);
      const text = data.choices[0].message.content;
      const usage = data.usage || {};
      
      console.log('\n' + '='.repeat(60));
      console.log(' REAL CROSS-NODE CLUSTER RESPONSE (T470 + T450)');
      console.log('='.repeat(60));
      console.log(text);
      console.log('='.repeat(60));
      console.log(`[*] Elapsed: ${elapsed.toFixed(2)}s | Tokens: ${usage.completion_tokens} | Speed: ${(usage.completion_tokens / elapsed).toFixed(2)} tokens/sec`);
      console.log('='.repeat(60));
      server.kill();
      process.exit(0);
    });
  });

  req.write(payload);
  req.end();
}

run();
