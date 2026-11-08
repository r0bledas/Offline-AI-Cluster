#!/usr/bin/env bash
# ==============================================================================
# FETCH PREBUILT MACOS ARM64 BINARIES FOR LLAMA-SERVER & LLAMA-CLI
# Downloads official release binaries from ggml-org/llama.cpp
# Note: Upstream release binaries do NOT include rpc-server (which requires
# -DGGML_RPC=ON). For the full cluster, run 02_build_llamacpp.sh.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster_env.sh"

BIN_DIR="$LLAMA_DIR/build/bin"
mkdir -p "$BIN_DIR"
cd "$CLUSTER_ROOT"

echo "=========================================================="
echo " Checking for Official Prebuilt macOS ARM64 llama.cpp Release"
echo "=========================================================="

# Fetch latest release tag metadata from GitHub API
RELEASE_JSON=$(curl -s "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=3" || true)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o 'https://github.com/ggml-org/llama.cpp/releases/download/[^"]*macos-arm64\.tar\.gz' | head -n 1 || true)

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "[!] Could not automatically resolve latest prebuilt tar.gz."
    echo "    Defaulting to source build via 02_build_llamacpp.sh..."
    exec "$SCRIPT_DIR/02_build_llamacpp.sh"
fi

ARCHIVE_NAME=$(basename "$DOWNLOAD_URL")
echo "[*] Found prebuilt release: $ARCHIVE_NAME"
echo "[*] Downloading from: $DOWNLOAD_URL"

curl -L -o "$ARCHIVE_NAME" "$DOWNLOAD_URL"

echo "[*] Extracting binaries..."
tar -xzf "$ARCHIVE_NAME" -C "$CLUSTER_ROOT"

# Move extracted binaries into standard bin directory if needed
if [[ -d "$CLUSTER_ROOT/build/bin" ]]; then
    echo "[✓] Binaries extracted to $BIN_DIR"
fi

# Remove quarantine attribute on macOS
echo "[*] Clearing macOS quarantine flags..."
xattr -dr com.apple.quarantine "$BIN_DIR" 2>/dev/null || true

echo "=========================================================="
echo "[✓] Official prebuilt binaries installed!"
echo "NOTE: Upstream prebuilts contain llama-server and llama-cli."
echo "If rpc-server is missing, run: ./setup/02_build_llamacpp.sh"
echo "=========================================================="
