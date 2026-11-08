#!/usr/bin/env node
/**
 * Offline-AI-Cluster Direct Update Manager (Node.js engine)
 * Zero external npm dependencies. Direct GitHub release synchronization.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

const GITHUB_API = 'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=5';
const USER_AGENT = 'Offline-AI-Cluster-Updater/1.0';

const args = process.argv.slice(2);
const isCheckOnly = args.includes('--check');
const isForce = args.includes('--force');
const preferredBackend = args.includes('--backend') ? args[args.indexOf('--backend') + 1] : 'vulkan';

const repoRoot = path.resolve(__dirname, '..');
const binDir = path.join(repoRoot, 'bin');

if (!fs.existsSync(binDir)) {
  fs.mkdirSync(binDir, { recursive: true });
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT } }, (res) => {
      let data = '';
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return resolve(fetchJson(res.headers.location));
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`GitHub API returned status ${res.statusCode}`));
      }
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

function getInstalledVersion() {
  const vFile = path.join(binDir, '.llama_cpp_version');
  if (fs.existsSync(vFile)) {
    return fs.readFileSync(vFile, 'utf8').trim();
  }
  const exePath = path.join(binDir, process.platform === 'win32' ? 'llama-server.exe' : 'llama-server');
  if (fs.existsSync(exePath)) {
    try {
      const out = execSync(`"${exePath}" --version`, { timeout: 4000, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const m = out.match(/version:\s*(\d+|b\d+)/i);
      if (m) return m[1].startsWith('b') ? m[1] : `b${m[1]}`;
    } catch (e) {}
  }
  return 'unknown';
}

function parseBuildNumber(tag) {
  if (!tag) return 0;
  const m = tag.match(/b(\d+)/i);
  return m ? parseInt(m[1], 10) : 0;
}

function findBestAsset(release) {
  const assets = release.assets || [];
  const isWin = process.platform === 'win32';
  const isMac = process.platform === 'darwin';
  const isLinux = process.platform === 'linux';
  const isArm = process.arch === 'arm64';

  for (const a of assets) {
    const name = a.name.toLowerCase();
    if (isWin) {
      if (!name.endsWith('.zip') || !name.includes('win')) continue;
      if (name.includes('x64')) {
        if (preferredBackend === 'vulkan' && name.includes('vulkan')) return a;
        if (preferredBackend === 'cpu' && name.includes('cpu') && !name.includes('vulkan') && !name.includes('cuda')) return a;
        if (name.includes('bin') && !name.includes('cuda')) return a;
      }
    } else if (isMac) {
      if (name.includes('macos') || name.includes('osx') || name.includes('darwin')) {
        if (isArm && name.includes('arm64')) return a;
        if (!isArm && name.includes('x64')) return a;
      }
    } else if (isLinux) {
      if (name.includes('ubuntu') || name.includes('linux')) {
        if (!isArm && name.includes('x64')) {
          if (preferredBackend === 'vulkan' && name.includes('vulkan')) return a;
          if (name.includes('bin')) return a;
        }
      }
    }
  }
  return assets[0] || null;
}

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    console.log(`[*] Downloading: ${url}`);
    const file = fs.createWriteStream(dest);
    https.get(url, { headers: { 'User-Agent': USER_AGENT } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        file.close();
        if (fs.existsSync(dest)) fs.unlinkSync(dest);
        return resolve(downloadFile(res.headers.location, dest));
      }
      if (res.statusCode !== 200) {
        file.close();
        if (fs.existsSync(dest)) fs.unlinkSync(dest);
        return reject(new Error(`Download failed with status ${res.statusCode}`));
      }
      const total = parseInt(res.headers['content-length'] || '0', 10);
      let downloaded = 0;
      res.on('data', chunk => {
        downloaded += chunk.length;
        if (total > 0) {
          const pct = ((downloaded / total) * 100).toFixed(1);
          process.stdout.write(`\r    -> ${(downloaded / 1024 / 1024).toFixed(1)} MB / ${(total / 1024 / 1024).toFixed(1)} MB (${pct}%)`);
        }
      });
      res.pipe(file);
      file.on('finish', () => {
        file.close(() => {
          console.log('\n[+] Download completed successfully.');
          resolve();
        });
      });
    }).on('error', err => {
      file.close();
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      reject(err);
    });
  });
}

function extractZip(zipPath, targetDir) {
  console.log(`[*] Extracting ${path.basename(zipPath)} to ${targetDir} ...`);
  if (process.platform === 'win32') {
    execSync(`powershell -NoProfile -Command "Expand-Archive -Path '${zipPath}' -DestinationPath '${targetDir}' -Force"`, { stdio: 'inherit' });
  } else {
    execSync(`unzip -o "${zipPath}" -d "${targetDir}"`, { stdio: 'inherit' });
  }
  console.log('[+] Extraction completed successfully.');
}

async function run() {
  console.log('='.repeat(60));
  console.log(' Offline-AI-Cluster Update Manager');
  console.log(' Inspired by eLlama Direct-Update Architecture');
  console.log('='.repeat(60));

  const currentVer = getInstalledVersion();
  console.log(`[*] Platform: ${process.platform}-${process.arch} | Preferred backend: ${preferredBackend}`);
  console.log(`[*] Current installed version: ${currentVer}`);

  let releases;
  try {
    releases = await fetchJson(GITHUB_API);
  } catch (err) {
    console.error(`[-] Failed to query GitHub releases: ${err.message}`);
    process.exit(1);
  }

  const latest = releases[0];
  const tag = latest.tag_name;
  const currentNum = parseBuildNumber(currentVer);
  const latestNum = parseBuildNumber(tag);

  console.log(`[*] Latest upstream release: ${tag} (build #${latestNum})`);

  const asset = findBestAsset(latest);
  const hasUpdate = (latestNum > currentNum) || (currentVer === 'unknown');

  if (isCheckOnly) {
    if (hasUpdate) {
      console.log(`[!] Update AVAILABLE: ${currentVer} -> ${tag}`);
      if (asset) console.log(`    Asset: ${asset.name} (${(asset.size / 1024 / 1024).toFixed(1)} MB)`);
    } else {
      console.log(`[✓] Binaries are up to date (${currentVer}).`);
    }
    return;
  }

  if (!hasUpdate && !isForce) {
    console.log(`[✓] Binaries are already up to date (${currentVer}). Use --force to re-download.`);
    return;
  }

  if (!asset) {
    console.error(`[-] No compatible binary asset found for ${process.platform}-${process.arch}`);
    process.exit(1);
  }

  const tmpZip = path.join(binDir, asset.name);
  try {
    await downloadFile(asset.browser_download_url, tmpZip);
    extractZip(tmpZip, binDir);
    fs.writeFileSync(path.join(binDir, '.llama_cpp_version'), tag, 'utf8');
    console.log(`[✓] Successfully updated llama.cpp to ${tag} in ${binDir}`);
  } finally {
    if (fs.existsSync(tmpZip)) {
      try { fs.unlinkSync(tmpZip); } catch (e) {}
    }
  }
}

run().catch(err => {
  console.error(`[-] Error: ${err.message}`);
  process.exit(1);
});
