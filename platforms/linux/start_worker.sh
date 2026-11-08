#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_DIR="$REPO_ROOT/bin"
RPC_SERVER="$BIN_DIR/ggml-rpc-server"

if [ ! -f "$RPC_SERVER" ]; then
    echo "[!] ggml-rpc-server not found in $BIN_DIR!"
    echo "[*] Running updater to download latest binaries..."
    "$REPO_ROOT/scripts/update_llama_cpp.sh" --update
fi

HOST="0.0.0.0"
PORT="50052"
THREADS=$(nproc 2>/dev/null || echo 4)

echo "========================================================"
echo "  Offline-AI-Cluster :: Linux Worker Compute Node"
echo "========================================================"
echo "[Config] Binding: $HOST:$PORT"
echo "[Config] Threads: $THREADS"
echo ""

export LD_LIBRARY_PATH="$BIN_DIR:$LD_LIBRARY_PATH"
exec "$RPC_SERVER" -H "$HOST" -p "$PORT" -t "$THREADS"
