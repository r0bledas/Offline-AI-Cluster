#!/usr/bin/env bash
# ==============================================================================
# CLUSTER ENVIRONMENT CONFIGURATION
# M2 MacBook Air (16 GB) + M2 MacBook Pro (8 GB) Offline AI Cluster
# ==============================================================================

# --- Network Topology (Thunderbolt Bridge & Ethernet) ---
export CLUSTER_SUBNET="192.168.100.0/24"
export NODE_A_IP="192.168.100.1"      # Node A (M2 Air 16GB - Coordinator)
export NODE_B_IP="192.168.100.2"      # Node B (M2 Pro 8GB  - RPC Worker)
export CLUSTER_NETMASK="255.255.255.0"
export CLUSTER_MTU="9000"             # Jumbo Frames for low latency & high throughput

# --- Ports for llama.cpp & Exo ---
export RPC_PORT="50052"               # llama.cpp RPC Server Port
export LLAMA_API_PORT="8080"          # OpenAI-compatible API Port on Node A
export LLAMA_API_HOST="0.0.0.0"       # Listen on all interfaces on Node A
export EXO_API_PORT="52415"           # Exo Dashboard & OpenAI API Port

# --- Optimized Memory Allocation (Using iogpu.wired_limit_mb) ---
# Total Hardware: 16 GB (Node A) + 8 GB (Node B) = 24 GB Unified Memory
# After applying 'optimize_macos_vram.sh':
# Node A (16 GB): 13,312 MB (~13.0 GB) for Metal, ~2.7 GB for macOS
# Node B (8 GB) : 6,144 MB  (~6.0 GB)  for Metal, ~1.8 GB for headless macOS
export NODE_A_SAFE_VRAM_GB="13.0"
export NODE_B_SAFE_VRAM_GB="6.0"
# Total Pooled Cluster VRAM: 19.0 GB!
export DEFAULT_TENSOR_SPLIT="13.0,6.0"

# --- Hardware / Core Tuning (Apple Silicon M2) ---
export LLAMA_THREADS="4"              # Best practice: use performance cores for compute
export LLAMA_FLASH_ATTN="1"           # Enable Flash Attention (Metal optimized)

# --- Offline Flags ---
export HF_HUB_OFFLINE="1"             # Prevent Hugging Face Hub phoning home
export TRANSFORMERS_OFFLINE="1"
export HF_DATASETS_OFFLINE="1"

# --- Default Paths ---
export CLUSTER_ROOT="$HOME/mac-ai-cluster"
export PREBUILT_BIN_DIR="$CLUSTER_ROOT/bin"
export LLAMA_DIR="$CLUSTER_ROOT/llama.cpp"
export MODELS_DIR="$CLUSTER_ROOT/models"
export EXO_DIR="$CLUSTER_ROOT/exo"
export WHEELS_DIR="$CLUSTER_ROOT/offline_wheels"

# Helper function to resolve binary locations (prebuilt bin/ vs compiled build/bin/)
resolve_binary() {
    local bin_name="$1"
    if [[ -x "$PREBUILT_BIN_DIR/$bin_name" ]]; then
        echo "$PREBUILT_BIN_DIR/$bin_name"
    elif [[ -x "$LLAMA_DIR/build/bin/$bin_name" ]]; then
        echo "$LLAMA_DIR/build/bin/$bin_name"
    else
        echo ""
    fi
}

# Helper function to print cluster status
cluster_info() {
    echo "=========================================================="
    echo " M2 Mac Distributed Offline AI Cluster Environment"
    echo "=========================================================="
    echo " Node A (Coordinator): $NODE_A_IP (M2 Air 16GB) [Optimized VRAM: ${NODE_A_SAFE_VRAM_GB} GB]"
    echo " Node B (Worker)     : $NODE_B_IP:$RPC_PORT (M2 Pro 8GB)  [Optimized VRAM: ${NODE_B_SAFE_VRAM_GB} GB]"
    echo " Pooled Cluster VRAM : 19.0 GB (via iogpu.wired_limit_mb)"
    echo " Preferred Link      : Thunderbolt 3/4 Bridge (40 Gbps, MTU 9000)"
    echo " Fallback Link       : Direct USB-C Ethernet (1GbE / 2.5GbE / 10GbE)"
    echo " Engines Supported   : llama.cpp RPC (GGUF direct) & Exo (MLX peer-to-peer)"
    echo " API Endpoints       : llama.cpp -> http://$NODE_A_IP:$LLAMA_API_PORT/v1"
    echo "                       Exo       -> http://$NODE_A_IP:$EXO_API_PORT/v1"
    echo "=========================================================="
}
