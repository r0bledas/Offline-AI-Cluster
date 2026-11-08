#!/usr/bin/env bash
# ==============================================================================
# CLUSTER SENTINEL: AUTOMATIC PROCESS-AWARE VRAM WATCHER
# Runs silently in the background. Detects when llama-server, rpc-server, or exo
# starts, raises VRAM to maximum, and immediately drops VRAM back to macOS normal
# when the AI process terminates.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

ROLE="${1:-auto}"

# Detect role based on hardware memory if auto
if [[ "$ROLE" == "auto" ]]; then
    TOTAL_RAM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/(1024*1024*1024)}')
    if [[ "$TOTAL_RAM_GB" -ge 14 ]]; then
        ROLE="node-a"
    else
        ROLE="node-b"
    fi
fi

if [[ "$ROLE" == "node-a" ]]; then
    TARGET_MB="13312"
    TARGET_GB="13.0"
else
    TARGET_MB="6144"
    TARGET_GB="6.0"
fi

echo "=========================================================="
echo " Starting Cluster Sentinel (Auto-VRAM Watcher)"
echo " Role: $ROLE | Boost Target: $TARGET_MB MB (~$TARGET_GB GB)"
echo " Monitoring for: llama-server, rpc-server, exo, llama-cli"
echo " Press Ctrl+C to stop sentinel."
echo "=========================================================="

cleanup() {
    echo ""
    echo "[*] Shutting down Sentinel. Ensuring VRAM limit is reset to 0..."
    sudo sysctl -w iogpu.wired_limit_mb=0 >/dev/null 2>&1 || true
    sudo purge >/dev/null 2>&1 || true
    echo "[✓] VRAM reset to normal macOS management."
    exit 0
}

trap cleanup EXIT INT TERM

AI_PATTERN="llama-server|rpc-server|exo|llama-cli"
IS_BOOSTED=0

while true; do
    if pgrep -f "$AI_PATTERN" >/dev/null 2>&1; then
        # AI process is actively running
        if [[ "$IS_BOOSTED" -eq 0 ]]; then
            echo "[$(date '+%H:%M:%S')] [AI ACTIVE] AI process detected! Boosting Metal VRAM to $TARGET_GB GB ($TARGET_MB MB)..."
            sudo sysctl -w iogpu.wired_limit_mb="$TARGET_MB" >/dev/null 2>&1 || true
            IS_BOOSTED=1
        fi
    else
        # No AI process running
        if [[ "$IS_BOOSTED" -eq 1 ]]; then
            echo "[$(date '+%H:%M:%S')] [AI IDLE] AI process exited. Reverting VRAM to normal macOS dynamic allocation..."
            sudo sysctl -w iogpu.wired_limit_mb=0 >/dev/null 2>&1 || true
            sudo purge >/dev/null 2>&1 || true
            IS_BOOSTED=0
            echo "[$(date '+%H:%M:%S')] [RESTORED] Full memory available for normal macOS apps."
        fi
    fi
    sleep 2
done
