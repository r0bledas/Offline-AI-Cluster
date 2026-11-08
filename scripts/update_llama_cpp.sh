#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================================"
echo "  Offline-AI-Cluster :: Direct llama.cpp Updater"
echo "  (eLlama-style automated binary synchronization)"
echo "========================================================"
echo ""

if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/updater.py" "$@"
elif command -v python >/dev/null 2>&1; then
    python "$SCRIPT_DIR/updater.py" "$@"
else
    echo "[-] Python 3 is required to run the automated updater."
    exit 1
fi
