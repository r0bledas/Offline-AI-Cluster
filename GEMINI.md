# Offline AI Cluster — Multi-Node Workflow & Operations Guide

## Cluster Topology & Architecture

This environment operates an offline, distributed edge AI cluster sharded across two interconnected ThinkPad nodes over a gigabit local LAN and encrypted Tailscale overlay network.

### Node Specifications

| Parameter | Coordinator Node (Current Host) | Worker Node |
| :--- | :--- | :--- |
| **Model** | ThinkPad T470 (`20HD000TUS`) | ThinkPad T450 |
| **Installed RAM** | 8 GB DDR4 | 16 GB DDR3L |
| **Local LAN IP** | `192.168.1.2` | `192.168.1.18` |
| **Tailscale IP** | `100.77.73.92` (`t470`) | `100.79.207.24` (`t450`) |
| **Default User** | `T470` | `T450` |
| **Password** | Current Session | `694200` |
| **Role** | Master Coordinator / Inference Server | Tensor Worker / RPC Offload |

---

## Authentication & Persistence

- **Cluster Auth Token**: `694200` (Passed via `X-Cluster-Token` HTTP header or `?token=694200`).
- **RDP Target Credentials**: Pre-authenticated in Windows Credential Manager under `TERMSRV/192.168.1.18` and `TERMSRV/100.79.207.24` with user `T450` and password `694200`.
- **RDP Port**: `3389` (Console session: `mstsc.exe /v:192.168.1.18`).

---

## Unified Cluster CLI (`cluster`)

The cluster provides a unified controller located at [`D:\Offline-AI-Cluster\cluster.cmd`](file:///D:/Offline-AI-Cluster/cluster.cmd) and [`D:\Offline-AI-Cluster\cluster.js`](file:///D:/Offline-AI-Cluster/cluster.js).

### Core Commands

```bat
:: 1. Check health, telemetry, RAM usage, and active ports on both nodes
cluster status

:: 2. Send an inference prompt to the distributed cluster
cluster prompt "Explain distributed tensor parallelization in two sentences."

:: 3. Remotely start the tensor RPC worker on T450
cluster worker-start

:: 4. Remotely stop the tensor RPC worker on T450
cluster worker-stop

:: 5. Execute any shell command on T450 remotely and display output
cluster exec "systeminfo"

:: 6. Launch Remote Desktop session to T450 in 1 click
cluster rdp

:: 7. Check and hot-update llama.cpp binaries directly from GitHub upstream
cluster update
```

---

## Port Allocation & Service Map

| Port | Protocol | Host | Description |
| :--- | :--- | :--- | :--- |
| **8000** | HTTP | T470 / T450 | Master Coordinator (`llama-server.exe`) on T470 / Vaultwarden on T450 |
| **50050** | HTTP | T470 & T450 | Cluster Node Bridge Daemon (`cluster-bridge.js`) |
| **50052** | TCP RPC | T450 | GGML RPC Tensor Worker (`ggml-rpc-server.exe`) |
| **9999** | HTTP | T470 | Binary & package distribution daemon (`serve_bin.js`) |
| **3389** | RDP | T450 | Windows Remote Desktop Protocol (User `T450`) |
| **8020** | HTTP | T450 | Navidrome Music Streaming Server |
| **8080** | HTTP | T450 | Raudel Portal Web Dashboard (`Python 3.11.9 SimpleHTTP`) |
| **8090** | HTTP | T450 | Kiwix Wikipedia & iFixit Offline Archives |
| **8095** | HTTP | T450 | Raudel Send (`/api/upload`, `/api/download`, `/api/slots`) |
| **8100** | HTTP | T450 | Minecraft Server Playit Tunnel Controller (`/api/restart`) |

---

## Operational Guidelines & Constraints

1. **Strictly Native Execution**:
   - **NO Ollama, NO LM Studio**.
   - Always run native `llama-server.exe`, `llama-cli.exe`, and `ggml-rpc-server.exe`.
2. **Model Storage**:
   - Primary model directory: `D:\llms\`.
   - Production Default Model: [`D:\llms\Llama-3.2-1B-Instruct-Q4_K_M.gguf`](file:///D:/llms/Llama-3.2-1B-Instruct-Q4_K_M.gguf) (807 MB, benchmarked at 33.76 t/s eval, 11.42 t/s generation).
3. **Cross-Node File Sync**:
   - Binaries and scripts are staged in [`D:\Offline-AI-Cluster\bin\`](file:///D:/Offline-AI-Cluster/bin/).
   - Complete worker archive is staged at [`D:\worker_t450.zip`](file:///D:/worker_t450.zip).
   - Fast transfer between nodes can use Taildrop (`tailscale file cp`), Raudel Send (port 8095), or Cluster Bridge streaming (`POST /api/upload`).
