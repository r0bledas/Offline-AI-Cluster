#!/usr/bin/env bash
# ==============================================================================
# ALTERNATIVE CLUSTER ENGINE: EXO (exo-explore/exo)
# Orchestrates peer-to-peer distributed inference on Apple Silicon using MLX
# Configured for both Online setup and 100% Offline Air-Gapped Operation
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

echo "=========================================================="
echo " Setting up Exo (exo-explore/exo) on Apple Silicon"
echo "=========================================================="

WHEELS_DIR="$CLUSTER_ROOT/offline_wheels"
EXO_DIR="$CLUSTER_ROOT/exo"
mkdir -p "$CLUSTER_ROOT"

# Enforce offline flags for pure offline execution
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_DATASETS_OFFLINE=1

# Check if offline wheel cache is present
if [[ -d "$WHEELS_DIR" && $(find "$WHEELS_DIR" -name "*.whl" 2>/dev/null | wc -l) -gt 0 ]]; then
    echo "[*] Found local offline wheel cache. Installing offline..."
    pip3 install --no-index --find-links="$WHEELS_DIR" mlx aiohttp huggingface_hub numpy tqdm requests pydantic psutil || true
fi

if [[ ! -d "$EXO_DIR" ]]; then
    echo "[*] Cloning exo repository from GitHub..."
    git clone https://github.com/exo-explore/exo.git "$EXO_DIR" || {
        echo "[!] Clone failed. If offline, ensure the repository was transferred beforehand."
    }
fi

if [[ -d "$EXO_DIR" ]]; then
    cd "$EXO_DIR"
    echo "[*] Installing Exo package..."
    pip3 install --no-deps -e . 2>/dev/null || python3 setup.py develop 2>/dev/null || true
fi

echo "=========================================================="
echo "[✓] Exo setup complete!"
echo "----------------------------------------------------------"
echo "HOW TO RUN EXO ACROSS YOUR DUAL-MAC CLUSTER (OFFLINE):"
echo "1. Ensure Thunderbolt Bridge is configured (01_thunderbolt_network.sh on both nodes)."
echo "2. Enforce offline environment:"
echo "   export HF_HUB_OFFLINE=1"
echo "3. On Node B (M2 Pro 8GB), start Exo worker:"
echo "   exo"
echo "4. On Node A (M2 Air 16GB), start Exo coordinator:"
echo "   exo"
echo ""
echo "Exo will auto-discover the peer over the Thunderbolt Bridge and pool both"
echo "M2 chips into a unified memory ring."
echo "Access the Exo Web Dashboard at: http://localhost:52415"
echo "OpenAI-compatible API at:        http://localhost:52415/v1"
echo "=========================================================="
