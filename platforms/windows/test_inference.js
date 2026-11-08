#!/usr/bin/env node
/**
 * Offline-AI-Cluster Benchmark & Inference Verification Tool (Node.js engine)
 * Zero external dependencies.
 */

const http = require('http');

const apiUrl = process.argv[2] || 'http://127.0.0.1:8000/v1/chat/completions';
const prompt = process.argv[3] || 'Explain the concept of an offline distributed AI cluster in two concise sentences.';

console.log('='.repeat(60));
console.log(' Offline-AI-Cluster Verification & Benchmark Test');
console.log('='.repeat(60));
console.log(`[*] Target Endpoint: ${apiUrl}`);
console.log(`[*] Test Prompt: "${prompt}"`);
console.log('[*] Transmitting request to cluster orchestrator...');

const payload = JSON.stringify({
  messages: [
    { role: 'system', content: 'You are a concise, helpful assistant.' },
    { role: 'user', content: prompt }
  ],
  temperature: 0.2,
  max_tokens: 120,
  stream: false
});

const urlObj = new URL(apiUrl);
const reqOptions = {
  hostname: urlObj.hostname,
  port: urlObj.port || 80,
  path: urlObj.pathname,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload)
  }
};

const t0 = process.hrtime.bigint();

const req = http.request(reqOptions, (res) => {
  let body = '';
  res.on('data', chunk => body += chunk);
  res.on('end', () => {
    const t1 = process.hrtime.bigint();
    const elapsedSec = Number(t1 - t0) / 1e9;

    if (res.statusCode !== 200) {
      console.error(`[-] Cluster returned error status: ${res.statusCode}`);
      console.error(body);
      process.exit(1);
    }

    try {
      const data = JSON.parse(body);
      const answer = data.choices[0].message.content.trim();
      const usage = data.usage || {};
      const promptTokens = usage.prompt_tokens || 0;
      const completionTokens = usage.completion_tokens || 0;
      const totalTokens = usage.total_tokens || 0;
      const tps = completionTokens > 0 ? (completionTokens / elapsedSec).toFixed(2) : '0';

      console.log('\n' + '='.repeat(60));
      console.log(' CLUSTER INFERENCE RESPONSE');
      console.log('='.repeat(60));
      console.log(answer);
      console.log('='.repeat(60));
      console.log(`[*] Elapsed Time:         ${elapsedSec.toFixed(2)} seconds`);
      console.log(`[*] Prompt Tokens:        ${promptTokens}`);
      console.log(`[*] Generated Tokens:     ${completionTokens}`);
      console.log(`[*] Total Tokens:         ${totalTokens}`);
      console.log(`[*] Generation Speed:     ${tps} tokens/sec`);
      console.log('='.repeat(60));
      console.log('[✓] Verification: SUCCESS - Cluster is fully operational!');
      process.exit(0);
    } catch (err) {
      console.error('[-] Failed to parse response:', err.message);
      console.error(body);
      process.exit(1);
    }
  });
});

req.on('error', (err) => {
  console.error(`[-] Request failed: ${err.message}`);
  console.error('[-] Ensure the cluster Master Orchestrator is running on port 8000.');
  process.exit(1);
});

req.write(payload);
req.end();
