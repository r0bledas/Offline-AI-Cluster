#!/usr/bin/env bash
# ======================================================================
#   Offline AI Cluster — Automated 1-Click Setup (macOS & Linux)
# ======================================================================
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "======================================================================"
echo "       OFFLINE AI CLUSTER — AUTOMATED 1-CLICK NEW PC SETUP"
echo "======================================================================"
echo "  Host: $(hostname) ($(uname -s) $(uname -m))"
echo "  Path: $REPO_ROOT"
echo "======================================================================"
echo ""

# 1. Check Node.js
if command -v node >/dev/null 2>&1; then
    echo "[✓] Node.js detected: $(node -v)"
else
    echo "[!] Node.js is not installed. Recommended for cluster CLI and bridge."
    echo "    Install via: brew install node (macOS) or apt install nodejs (Linux)"
fi

# 2. Permissions
echo "[*] Setting script permissions..."
chmod +x scripts/*.sh platforms/linux/*.sh platforms/macos/*.sh cluster.js setup.sh 2>/dev/null || true

# 3. Initialize cluster.config.json
if [ ! -f "cluster.config.json" ]; then
    echo "[*] Creating cluster.config.json from template..."
    cp cluster.config.example.json cluster.config.json
    echo "[✓] Created cluster.config.json"
else
    echo "[✓] Local cluster.config.json already exists."
fi

# 4. Fetch native llama.cpp binaries
echo ""
echo "[*] Checking native llama.cpp execution binaries in bin/..."
if [ ! -f "bin/llama-server" ] && [ ! -f "bin/llama-server.exe" ]; then
    echo "[!] llama-server missing. Fetching official release from upstream..."
    ./scripts/update_llama_cpp.sh || true
else
    echo "[✓] llama-server present in bin/."
fi

# 5. Check Models
echo ""
mkdir -p models
MODEL_COUNT=$(find models -name "*.gguf" 2>/dev/null | wc -l || echo 0)

if [ "$MODEL_COUNT" -eq 0 ]; then
    echo "[!] No GGUF models found in models/."
    echo "    1) Download starter model (Llama-3.2-1B-Instruct-Q4_K_M, 807 MB)"
    echo "    2) Skip model download"
    read -r -p "Select [1-2] (Default: 1): " MODEL_CHOICE
    MODEL_CHOICE=${MODEL_CHOICE:-1}
    if [ "$MODEL_CHOICE" = "1" ]; then
        echo "[*] Downloading Llama-3.2-1B-Instruct-Q4_K_M.gguf from Hugging Face..."
        curl -L "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf" -o "models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
        echo "[✓] Download complete: models/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
    fi
else
    echo "[✓] GGUF models detected in models/."
fi

# 6. Global CLI symlink
if [ -w "/usr/local/bin" ]; then
    ln -sf "$REPO_ROOT/cluster.js" /usr/local/bin/cluster
    echo "[✓] Created symlink: /usr/local/bin/cluster"
else
    echo "[*] To use 'cluster' globally, add this to your ~/.zshrc or ~/.bashrc:"
    echo "    export PATH=\"\$PATH:$REPO_ROOT\""
    echo "    alias cluster=\"node $REPO_ROOT/cluster.js\""
fi

echo ""
echo "======================================================================"
echo "  SETUP COMPLETE! The Offline AI Cluster is ready."
echo "======================================================================"
echo "  Run: node cluster.js status"
echo "  Run: node cluster.js prompt \"Hello cluster!\""
echo ""

if [ -f "cluster.js" ]; then
    node cluster.js status || true
fi
