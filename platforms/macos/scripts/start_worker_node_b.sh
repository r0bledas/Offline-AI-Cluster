#!/usr/bin/env bash
# ==============================================================================
# START RPC WORKER ON NODE B (M2 MacBook Pro - 8 GB RAM)
# Automatically boosts VRAM during execution and restores normal memory on exit.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

RPC_BIN=$(resolve_binary "rpc-server")

echo "=========================================================="
echo " Starting RPC Worker on Node B (M2 Pro 8GB)"
echo "=========================================================="

if [[ -z "$RPC_BIN" || ! -f "$RPC_BIN" ]]; then
    echo "[!] Error: rpc-server binary not found."
    echo "    Either drop precompiled binaries into $PREBUILT_BIN_DIR"
    echo "    or run $SCRIPT_DIR/../setup/02_build_llamacpp.sh first."
    exit 1
fi

# 1. Ephemeral VRAM Booster Trap
# Automatically sets iogpu.wired_limit_mb=6144 and restores 0 on exit
cleanup() {
    echo ""
    echo "----------------------------------------------------------"
    echo "[*] Worker shutting down..."
    echo "[*] Reverting VRAM limit to macOS dynamic default (0)..."
    sudo sysctl -w iogpu.wired_limit_mb=0 >/dev/null 2>&1 || true
    sudo purge >/dev/null 2>&1 || true
    echo "[✓] macOS normal memory restored. Inactive cache purged."
    echo "=========================================================="
}
trap cleanup EXIT INT TERM

echo "[*] Boosting Node B VRAM to 6.0 GB (6144 MB)..."
sudo sysctl -w iogpu.wired_limit_mb=6144 >/dev/null 2>&1 || true
sudo purge 2>/dev/null || true

# Check if port is already in use
if lsof -Pi :"$RPC_PORT" -sTCP:LISTEN -t >/dev/null ; then
    echo "[!] Port $RPC_PORT is already in use. Terminating previous instance..."
    kill -9 $(lsof -Pi :"$RPC_PORT" -sTCP:LISTEN -t) || true
    sleep 1
fi

echo "[*] Binding rpc-server to $NODE_B_IP:$RPC_PORT with Metal acceleration..."
echo "[*] Waiting for coordinator (Node A) to connect and offload tensors..."
echo "----------------------------------------------------------"

# Launch rpc-server
exec "$RPC_BIN" \
    -H "$NODE_B_IP" \
    -p "$RPC_PORT" \
    -v
