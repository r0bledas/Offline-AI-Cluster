#!/usr/bin/env bash
# ==============================================================================
# STEP 2: BUILD LLAMA.CPP WITH METAL & RPC ON APPLE SILICON
# Run this on both Node A and Node B
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

echo "=========================================================="
echo " Building llama.cpp with Apple Metal + RPC Support"
echo " Target Architecture: Apple Silicon (M2 / arm64)"
echo "=========================================================="

# Check prerequisites
if ! command -v cmake >/dev/null 2>&1; then
    echo "[!] Error: 'cmake' not found. Please install it (e.g. 'brew install cmake') or download CMake from cmake.org."
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "[!] Error: 'git' not found."
    exit 1
fi

# Create target directories
mkdir -p "$CLUSTER_ROOT"
mkdir -p "$MODELS_DIR"

cd "$CLUSTER_ROOT"

# Clone or update llama.cpp
if [[ -d "$LLAMA_DIR" ]]; then
    echo "[*] llama.cpp repository found. Updating..."
    cd "$LLAMA_DIR"
    git fetch origin || true
else
    echo "[*] Cloning llama.cpp repository..."
    git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    cd "$LLAMA_DIR"
fi

# Configure CMake with Metal and RPC enabled
# -DGGML_METAL=ON: Enables Apple Silicon GPU hardware acceleration via Metal
# -DGGML_RPC=ON: Enables Remote Procedure Call backend for distributed clustering
# -DGGML_METAL_EMBED_LIBRARY=ON: Bundles Metal shaders into the binary
echo "[*] Configuring CMake build system..."
rm -rf build
cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DGGML_RPC=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DBUILD_SHARED_LIBS=OFF

# Compile binaries using all available CPU performance cores
NUM_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || sysctl -n hw.ncpu)
echo "[*] Compiling binaries using $NUM_CORES cores..."
cmake --build build --config Release -j "$NUM_CORES" --target llama-cli llama-server rpc-server llama-bench

echo "=========================================================="
echo "[✓] Build complete! Built binaries verified in: $LLAMA_DIR/build/bin"
echo "----------------------------------------------------------"
ls -la "$LLAMA_DIR/build/bin/llama-server" "$LLAMA_DIR/build/bin/rpc-server" "$LLAMA_DIR/build/bin/llama-cli" "$LLAMA_DIR/build/bin/llama-bench"
echo "=========================================================="
