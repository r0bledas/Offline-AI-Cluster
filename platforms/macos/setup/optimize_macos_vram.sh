#!/usr/bin/env bash
# ==============================================================================
# OPTIMIZE MACOS VRAM & WIRED MEMORY LIMITS (iogpu.wired_limit_mb)
# Unlocks maximum Unified Memory for Metal GPU on Apple Silicon (M2 Air & Pro)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

echo "=========================================================="
echo " macOS Unified Memory VRAM Maximizer (iogpu.wired_limit_mb)"
echo "=========================================================="

ROLE="${1:-}"
ACTION="${2:-apply}"

if [[ "$ROLE" != "node-a" && "$ROLE" != "node-b" && "$ROLE" != "status" && "$ROLE" != "reset" ]]; then
    echo "Usage: sudo $0 <node-a|node-b|status|reset> [apply|persist]"
    echo ""
    echo "  node-a : Optimizes M2 MacBook Air (16 GB RAM)"
    echo "           Sets VRAM limit to 13,312 MB (~13 GB), leaving 2.7 GB for macOS."
    echo "  node-b : Optimizes M2 MacBook Pro (8 GB RAM)"
    echo "           Sets VRAM limit to 6,144 MB (~6 GB), leaving 1.8 GB for headless macOS."
    echo "  status : Displays current sysctl VRAM limit and active memory usage."
    echo "  reset  : Resets VRAM limit to macOS dynamic default (0)."
    echo ""
    echo "  Options:"
    echo "    apply   : Applies limit immediately for current session (default)."
    echo "    persist : Generates and activates a persistent LaunchDaemon across reboots."
    exit 1
fi

# 1. Status Check
CURRENT_LIMIT=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo "0")
echo "[*] Current sysctl iogpu.wired_limit_mb: $CURRENT_LIMIT MB"
if [[ "$CURRENT_LIMIT" -eq 0 ]]; then
    echo "    (Value 0 = Default dynamic macOS allocation, capped at ~75% of total RAM)"
else
    CURRENT_GB=$(awk "BEGIN {printf \"%.2f\", $CURRENT_LIMIT/1024}")
    echo "    (Custom ceiling active: ~$CURRENT_GB GB dedicated to Metal)"
fi

if [[ "$ROLE" == "status" ]]; then
    echo "----------------------------------------------------------"
    vm_stat | perl -ne '/page size of (\d+)/ and $size=$1; /Pages free:\s+(\d+)/ and $free=$1; /Pages active:\s+(\d+)/ and $act=$1; /Pages inactive:\s+(\d+)/ and $inact=$1; /Pages wired down:\s+(\d+)/ and $wired=$1; END { printf("Active RAM: %.2f GB | Inactive: %.2f GB | Wired: %.2f GB | Free: %.2f GB\n", $act*$size/1e9, $inact*$size/1e9, $wired*$size/1e9, $free*$size/1e9); }'
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Setting memory limits requires root privileges. Please run with sudo."
   exit 1
fi

# 2. Reset Handling
if [[ "$ROLE" == "reset" ]]; then
    echo "[*] Resetting iogpu.wired_limit_mb to default (0)..."
    sysctl -w iogpu.wired_limit_mb=0
    if [[ -f "/Library/LaunchDaemons/com.cluster.wiredlimit.plist" ]]; then
        echo "[*] Removing persistent LaunchDaemon..."
        launchctl unload /Library/LaunchDaemons/com.cluster.wiredlimit.plist 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.cluster.wiredlimit.plist
    fi
    echo "[✓] Reset complete. macOS dynamic memory management restored."
    exit 0
fi

# 3. Determine Target Limit in Megabytes
if [[ "$ROLE" == "node-a" ]]; then
    # 16 GB Total: 13,312 MB (~13.0 GB) for Metal, ~2.7 GB reserved for OS
    TARGET_MB="13312"
    TARGET_GB="13.0"
    TARGET_DESC="Node A (M2 Air 16GB)"
else
    # 8 GB Total: 6,144 MB (~6.0 GB) for Metal, ~1.8 GB reserved for headless OS
    TARGET_MB="6144"
    TARGET_GB="6.0"
    TARGET_DESC="Node B (M2 Pro 8GB)"
fi

echo "[*] Target Profile: $TARGET_DESC"
echo "[*] Setting GPU wired limit to $TARGET_MB MB (~$TARGET_GB GB)..."
sysctl -w iogpu.wired_limit_mb="$TARGET_MB"
echo "[✓] GPU memory ceiling updated successfully for the current session!"

# 4. Optional Persistence via LaunchDaemon
if [[ "$ACTION" == "persist" ]]; then
    PLIST_PATH="/Library/LaunchDaemons/com.cluster.wiredlimit.plist"
    echo "[*] Creating persistent LaunchDaemon at $PLIST_PATH..."
    cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cluster.wiredlimit</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sysctl</string>
        <string>iogpu.wired_limit_mb=$TARGET_MB</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    chmod 644 "$PLIST_PATH"
    chown root:wheel "$PLIST_PATH"
    launchctl load -w "$PLIST_PATH" 2>/dev/null || true
    echo "[✓] Persistence enabled! This limit will automatically apply on every reboot."
fi

# Purge cache to reclaim immediate headroom
echo "[*] Purging inactive disk cache..."
purge 2>/dev/null || true

echo "=========================================================="
echo "Memory optimization complete."
echo "New effective Metal VRAM limit: ~$TARGET_GB GB"
echo "=========================================================="
