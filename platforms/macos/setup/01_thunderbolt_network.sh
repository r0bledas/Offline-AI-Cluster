#!/usr/bin/env bash
# ==============================================================================
# STEP 1: CONFIGURE THUNDERBOLT BRIDGE FOR LOW-LATENCY INTER-NODE LINK
# Run this on both Node A (M2 Air) and Node B (M2 Pro)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

echo "=========================================================="
echo " macOS Thunderbolt Direct Interconnect Setup"
echo "=========================================================="

ROLE="${1:-}"
if [[ "$ROLE" != "node-a" && "$ROLE" != "node-b" ]]; then
    echo "Usage: sudo $0 <node-a|node-b>"
    echo "  node-a: Configures M2 MacBook Air (16 GB) as 192.168.100.1"
    echo "  node-b: Configures M2 MacBook Pro (8 GB)  as 192.168.100.2"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root (use sudo)."
   exit 1
fi

# 1. Identify Thunderbolt Bridge Service Name
TB_SERVICE="Thunderbolt Bridge"

# Verify if service exists
if ! networksetup -listallnetworkservices | grep -Fxq "$TB_SERVICE"; then
    echo "[!] '$TB_SERVICE' not found directly. Checking existing hardware ports..."
    networksetup -listallhardwareports
    echo "[!] Please connect a Thunderbolt 3/4 cable between both Macs and enable Thunderbolt Bridge in System Settings > Network."
    exit 1
fi

echo "[*] Found network service: '$TB_SERVICE'"

# 2. Get hardware device interface (e.g., bridge0)
TB_DEV=$(networksetup -listallhardwareports | awk -v svc="$TB_SERVICE" '
    $0 ~ "Hardware Port: " svc { getline; print $2 }
')

if [[ -z "$TB_DEV" ]]; then
    TB_DEV="bridge0"
    echo "[*] Defaulting device name to '$TB_DEV'"
else
    echo "[*] Network device mapped to interface: '$TB_DEV'"
fi

# 3. Apply Static IP based on Role
if [[ "$ROLE" == "node-a" ]]; then
    MY_IP="$NODE_A_IP"
    PEER_IP="$NODE_B_IP"
    echo "[*] Configuring Node A (Air 16GB) with IP: $MY_IP"
else
    MY_IP="$NODE_B_IP"
    PEER_IP="$NODE_A_IP"
    echo "[*] Configuring Node B (Pro 8GB) with IP: $MY_IP"
fi

networksetup -setmanual "$TB_SERVICE" "$MY_IP" "$CLUSTER_NETMASK" ""
echo "[✓] Static IP assigned: $MY_IP / $CLUSTER_NETMASK"

# 4. Configure Jumbo Frames (MTU 9000) for high-speed tensor transfers
echo "[*] Setting MTU to $CLUSTER_MTU on $TB_DEV..."
if ifconfig "$TB_DEV" mtu "$CLUSTER_MTU" 2>/dev/null; then
    echo "[✓] MTU set to $CLUSTER_MTU successfully."
else
    echo "[!] Warning: Setting MTU directly on bridge failed. Trying networksetup..."
    networksetup -setMTU "$TB_SERVICE" "$CLUSTER_MTU" 2>/dev/null || echo "[!] Jumbo frames not supported by this bridge profile, keeping standard MTU."
fi

# 5. Disable sleep modes for cluster stability
echo "[*] Optimizing power management (preventing sleep during compute)..."
pmset -a disablesleep 1 2>/dev/null || true
pmset -a sleep 0 2>/dev/null || true
pmset -a tcpkeepalive 1 2>/dev/null || true
echo "[✓] Sleep disabled and TCP keepalive enforced."

# 6. Connectivity verification
echo "----------------------------------------------------------"
echo "Testing connectivity to peer ($PEER_IP)..."
echo "Note: If the peer is not yet configured or cable is disconnected, this may timeout."
if ping -c 3 -W 1000 "$PEER_IP" >/dev/null 2>&1; then
    echo "[✓] SUCCESS: Connected to peer $PEER_IP!"
    ping -c 3 "$PEER_IP"
else
    echo "[i] Peer $PEER_IP is currently unreachable."
    echo "    1. Connect Thunderbolt 3/4 cable between both Macs."
    echo "    2. Run this script on the other Mac with the corresponding role."
fi

echo "=========================================================="
echo "Setup complete for $ROLE ($MY_IP)."
echo "=========================================================="
