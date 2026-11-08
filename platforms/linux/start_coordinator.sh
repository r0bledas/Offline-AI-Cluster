#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$REPO_ROOT/bin"
LLAMA_SERVER="$BIN_DIR/llama-server"

if [ ! -f "$LLAMA_SERVER" ]; then
    echo "[!] llama-server not found in $BIN_DIR!"
    echo "[*] Running updater to download latest binaries..."
    "$REPO_ROOT/scripts/update_llama_cpp.sh" --update
fi

MODEL_PATH="${1:-$REPO_ROOT/models/model.gguf}"
WORKER_RPC="${2:-192.168.1.18:50052}"
HOST="0.0.0.0"
PORT="8000"
CTX="2048"
THREADS=$(nproc 2>/dev/null || echo 4)

echo "========================================================"
echo "  Offline-AI-Cluster :: Linux Master Coordinator"
echo "========================================================"
echo "[Config] Model:   $MODEL_PATH"
echo "[Config] Workers: $WORKER_RPC"
echo "[Config] API:     http://$HOST:$PORT/v1"
echo "[Config] Threads: $THREADS"
echo ""

export LD_LIBRARY_PATH="$BIN_DIR:$LD_LIBRARY_PATH"
exec "$LLAMA_SERVER" -m "$MODEL_PATH" --rpc "$WORKER_RPC" -c "$CTX" -t "$THREADS" --host "$HOST" --port "$PORT"
