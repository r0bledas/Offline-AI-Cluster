#!/usr/bin/env bash
# ==============================================================================
# START CLUSTER COORDINATOR ON NODE A (M2 MacBook Air - 16 GB RAM)
# Launches llama-server (OpenAI-compatible) distributing layers to Node B via RPC
# Automatically boosts VRAM during execution and restores normal memory on exit.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

SERVER_BIN=$(resolve_binary "llama-server")

echo "=========================================================="
echo " Starting Cluster Coordinator on Node A (M2 Air 16GB)"
echo "=========================================================="

if [[ -z "$SERVER_BIN" || ! -f "$SERVER_BIN" ]]; then
    echo "[!] Error: llama-server binary not found."
    echo "    Either drop precompiled binaries into $PREBUILT_BIN_DIR"
    echo "    or run $SCRIPT_DIR/../setup/02_build_llamacpp.sh first."
    exit 1
fi

MODEL_PATH="${1:-}"
if [[ -z "$MODEL_PATH" ]]; then
    FIRST_GGUF=$(find "$MODELS_DIR" -name "*.gguf" 2>/dev/null | head -n 1 || true)
    if [[ -n "$FIRST_GGUF" ]]; then
        MODEL_PATH="$FIRST_GGUF"
        echo "[*] Auto-selected model: $MODEL_PATH"
    else
        echo "Usage: $0 <path_to_model.gguf> [context_size] [tensor_split]"
        echo "Example: $0 $MODELS_DIR/qwen2.5-14b-instruct-q4_k_m.gguf 8192 13.0,6.0"
        exit 1
    fi
fi

CTX_SIZE="${2:-8192}"
TENSOR_SPLIT="${3:-$DEFAULT_TENSOR_SPLIT}"

# 1. Ephemeral VRAM Booster Trap
# Automatically sets iogpu.wired_limit_mb=13312 and restores 0 on exit
cleanup() {
    echo ""
    echo "----------------------------------------------------------"
    echo "[*] Coordinator shutting down..."
    echo "[*] Reverting VRAM limit to macOS dynamic default (0)..."
    sudo sysctl -w iogpu.wired_limit_mb=0 >/dev/null 2>&1 || true
    sudo purge >/dev/null 2>&1 || true
    echo "[✓] macOS normal memory restored. Inactive cache purged."
    echo "=========================================================="
}
trap cleanup EXIT INT TERM

echo "[*] Boosting Node A VRAM to 13.0 GB (13312 MB)..."
sudo sysctl -w iogpu.wired_limit_mb=13312 >/dev/null 2>&1 || true

# 2. Connectivity check to Node B RPC Worker
echo "[*] Verifying RPC Worker connectivity at $NODE_B_IP:$RPC_PORT..."
if ! nc -z -w 3 "$NODE_B_IP" "$RPC_PORT" 2>/dev/null; then
    echo "[!] ERROR: Cannot connect to RPC Worker at $NODE_B_IP:$RPC_PORT"
    echo "    Ensure:"
    echo "    1. Thunderbolt cable (or Ethernet) is connected."
    echo "    2. Node B static IP is set to $NODE_B_IP."
    echo "    3. Node B has started the worker (run start_worker_node_b.sh)."
    exit 1
fi
echo "[✓] Worker reachable!"

# 3. Print memory allocation info
echo "[*] Model File: $MODEL_PATH"
echo "[*] Context Window: $CTX_SIZE tokens"
echo "[*] Tensor Split Ratio: $TENSOR_SPLIT (Air : Pro)"
echo "[*] API Endpoint: http://$NODE_A_IP:$LLAMA_API_PORT/v1/chat/completions"
echo "----------------------------------------------------------"
echo "[*] Initializing distributed Metal inference..."

"$SERVER_BIN" \
    -m "$MODEL_PATH" \
    --rpc "$NODE_B_IP:$RPC_PORT" \
    --tensor-split "$TENSOR_SPLIT" \
    -ngl 99 \
    -c "$CTX_SIZE" \
    -fa \
    -t "$LLAMA_THREADS" \
    --host "$LLAMA_API_HOST" \
    --port "$LLAMA_API_PORT" \
    -v
