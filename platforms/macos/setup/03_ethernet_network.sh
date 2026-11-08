#!/usr/bin/env bash
# ==============================================================================
# ALTERNATIVE SETUP: CONFIGURE ETHERNET INTERFACE (1GbE / 2.5GbE / 10GbE)
# Use this if connecting both Macs via USB-C to RJ-45 adapters or an offline switch
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

echo "=========================================================="
echo " macOS Direct Ethernet Interconnect Setup"
echo " (1GbE / 2.5GbE / 10GbE USB-C Adapters or Direct Auto-MDIX)"
echo "=========================================================="

ROLE="${1:-}"
if [[ "$ROLE" != "node-a" && "$ROLE" != "node-b" ]]; then
    echo "Usage: sudo $0 <node-a|node-b> [Ethernet Service Name]"
    echo "  node-a: Configures M2 MacBook Air (16 GB) as 192.168.100.1"
    echo "  node-b: Configures M2 MacBook Pro (8 GB)  as 192.168.100.2"
    echo "  Example: sudo $0 node-a \"USB 10/100/1000 LAN\""
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root (use sudo)."
   exit 1
fi

ETH_SERVICE="${2:-}"

# Auto-detect Ethernet service if not explicitly provided
if [[ -z "$ETH_SERVICE" ]]; then
    echo "[*] Auto-detecting Ethernet services..."
    ETH_SERVICE=$(networksetup -listallnetworkservices | grep -iE 'ethernet|lan|usb.*10' | head -n 1 || true)
    if [[ -z "$ETH_SERVICE" ]]; then
        echo "[!] No obvious Ethernet service detected. Available network services:"
        networksetup -listallnetworkservices
        echo "Please rerun specifying your Ethernet adapter service name: sudo $0 $ROLE \"<ServiceName>\""
        exit 1
    fi
fi

echo "[*] Selected Ethernet Service: '$ETH_SERVICE'"

# Identify underlying BSD hardware port (e.g. en0, en5, en7)
ETH_DEV=$(networksetup -listallhardwareports | awk -v svc="$ETH_SERVICE" '
    $0 ~ "Hardware Port: " svc { getline; print $2 }
')

if [[ -z "$ETH_DEV" ]]; then
    echo "[!] Could not map service '$ETH_SERVICE' to a BSD device name."
    echo "    Will apply settings via networksetup only."
else
    echo "[*] BSD Device Interface: '$ETH_DEV'"
fi

# Set Static IP
if [[ "$ROLE" == "node-a" ]]; then
    MY_IP="$NODE_A_IP"
    PEER_IP="$NODE_B_IP"
    echo "[*] Assigning Node A (Air 16GB) IP: $MY_IP"
else
    MY_IP="$NODE_B_IP"
    PEER_IP="$NODE_A_IP"
    echo "[*] Assigning Node B (Pro 8GB) IP: $MY_IP"
fi

networksetup -setmanual "$ETH_SERVICE" "$MY_IP" "$CLUSTER_NETMASK" ""
echo "[✓] Static IP assigned: $MY_IP / $CLUSTER_NETMASK"

# Configure MTU
# 10GbE / 2.5GbE typically support MTU 9000 (Jumbo Frames). 1GbE might support 1500 or 9000.
echo "[*] Attempting to set MTU 9000 on $ETH_SERVICE..."
if networksetup -setMTU "$ETH_SERVICE" 9000 2>/dev/null; then
    echo "[✓] Jumbo Frames (MTU 9000) successfully configured."
else
    echo "[!] MTU 9000 not supported by adapter; falling back to standard MTU 1500."
    networksetup -setMTU "$ETH_SERVICE" 1500 2>/dev/null || true
fi

# Disable sleep
pmset -a disablesleep 1 2>/dev/null || true
pmset -a sleep 0 2>/dev/null || true

# Test connectivity
echo "----------------------------------------------------------"
echo "Testing connectivity to peer ($PEER_IP)..."
if ping -c 3 -W 1000 "$PEER_IP" >/dev/null 2>&1; then
    echo "[✓] SUCCESS: Connected to peer $PEER_IP over Ethernet!"
    ping -c 3 "$PEER_IP"
else
    echo "[i] Peer $PEER_IP is currently unreachable."
    echo "    1. Ensure the RJ-45 cable is connected between both Macs (Cat6 / Cat6a recommended)."
    echo "    2. Run this script on the other Mac with the corresponding role."
fi
echo "=========================================================="
