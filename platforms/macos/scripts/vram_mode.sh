#!/usr/bin/env bash
# ==============================================================================
# ON-DEMAND VRAM CONTROLLER (vram_mode.sh)
# Dynamically boosts Metal VRAM only when AI workloads run, and automatically
# restores macOS to default dynamic memory when inference stops.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

ACTION="${1:-status}"

# Helper to identify node type if not explicitly supplied
detect_node() {
    local total_ram_gb
    total_ram_gb=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/(1024*1024*1024)}')
    if [[ "$total_ram_gb" -ge 14 ]]; then
        echo "node-a"  # ~16GB
    else
        echo "node-b"  # ~8GB
    fi
}

get_target_mb() {
    local node="$1"
    if [[ "$node" == "node-a" ]]; then
        echo "13312"  # 13 GB Metal, 2.7 GB OS
    else
        echo "6144"   # 6 GB Metal, 1.8 GB OS
    fi
}

case "$ACTION" in
    on)
        NODE="${2:-$(detect_node)}"
        TARGET_MB=$(get_target_mb "$NODE")
        echo "[*] Activating Boosted VRAM Mode for $NODE ($TARGET_MB MB)..."
        sudo sysctl -w iogpu.wired_limit_mb="$TARGET_MB"
        echo "[✓] VRAM Boost Active: $(awk "BEGIN {printf \"%.2f\", $TARGET_MB/1024}") GB allocated to GPU."
        ;;

    off)
        echo "[*] Deactivating Boosted VRAM Mode (restoring macOS default dynamic allocation)..."
        sudo sysctl -w iogpu.wired_limit_mb=0
        sudo purge 2>/dev/null || true
        echo "[✓] Default macOS memory management restored. Cache purged."
        ;;

    status)
        CURRENT=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "0")
        echo "=========================================================="
        echo " Current Metal VRAM Allocation Status"
        echo "=========================================================="
        if [[ "$CURRENT" -eq 0 ]]; then
            echo " State: NORMAL (Default dynamic macOS allocation, capped at ~75%)"
        else
            GB=$(awk "BEGIN {printf \"%.2f\", $CURRENT/1024}")
            echo " State: BOOSTED ($CURRENT MB / ~$GB GB dedicated to Metal)"
        fi
        echo "----------------------------------------------------------"
        echo "Active AI Processes:"
        pgrep -fl "llama-server|rpc-server|exo" || echo "  No AI inference processes running."
        echo "=========================================================="
        ;;

    run)
        # Ephemeral Wrapper: Boosts VRAM, executes command, restores default on exit
        NODE="${2:-$(detect_node)}"
        shift 2 || true
        if [[ $# -eq 0 ]]; then
            echo "Usage: $0 run <node-a|node-b> <command...>"
            echo "Example: $0 run node-a ./scripts/start_coordinator_node_a.sh"
            exit 1
        fi

        TARGET_MB=$(get_target_mb "$NODE")
        ORIGINAL_LIMIT=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "0")

        cleanup() {
            echo ""
            echo "----------------------------------------------------------"
            echo "[*] AI Workload Terminated. Reverting VRAM limit to original ($ORIGINAL_LIMIT)..."
            sudo sysctl -w iogpu.wired_limit_mb="$ORIGINAL_LIMIT" >/dev/null 2>&1 || true
            sudo purge >/dev/null 2>&1 || true
            echo "[✓] System memory restored to normal."
            echo "=========================================================="
        }

        trap cleanup EXIT INT TERM

        echo "=========================================================="
        echo " Ephemeral Boosted AI Execution Wrapper"
        echo " Target Profile: $NODE (GPU Limit: $TARGET_MB MB)"
        echo " Command: $@"
        echo "=========================================================="
        sudo sysctl -w iogpu.wired_limit_mb="$TARGET_MB" >/dev/null 2>&1 || true

        # Execute target command
        "$@"
        ;;

    *)
        echo "Usage: $0 <on|off|status|run> [node-a|node-b] [command...]"
        echo ""
        echo "  on   : Manually enable boosted VRAM limit for current Mac"
        echo "  off  : Restore standard macOS dynamic memory limit"
        echo "  status: Show current VRAM allocation and active AI processes"
        echo "  run  : Run an AI command with boosted VRAM, restoring normal memory when stopped"
        echo ""
        echo "Example (Ephemeral Wrapper):"
        echo "  $0 run node-a ./scripts/start_coordinator_node_a.sh ~/models/qwen.gguf"
        exit 1
        ;;
esac
