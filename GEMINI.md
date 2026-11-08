# Offline AI Cluster — Multi-Node Distributed Architecture & Operations Guide

## Overview

The **Offline-AI-Cluster** is a fully decentralized, heterogeneous multi-node edge AI inference cluster. It is designed to pool memory and compute across arbitrary network-connected hardware (laptops, desktops, mini PCs, Macs, Linux boards) over Gigabit LAN or encrypted overlay networks (Tailscale).

---

## Dynamic Multi-Node Architecture

The cluster does **not** rely on hardcoded machine hostnames or static IP addresses. All node coordination is dynamic and driven by [`cluster.config.json`](file:///D:/Offline-AI-Cluster/cluster.config.json) (or environment variables).

### Cluster Configuration (`cluster.config.json`)

To add, remove, or modify nodes in the cluster, edit `cluster.config.json`:

```json
{
  "coordinator": {
    "host": "0.0.0.0",
    "port": 8000,
    "bridgePort": 50050,
    "model": "D:\\llms\\Llama-3.2-1B-Instruct-Q4_K_M.gguf",
    "contextSize": 2048,
    "threads": 4
  },
  "workers": [
    {
      "name": "Node-1",
      "host": "192.168.1.18",
      "rpcPort": 50052,
      "bridgePort": 50050,
      "threads": 4
    },
    {
      "name": "Node-2",
      "host": "192.168.1.19",
      "rpcPort": 50052,
      "bridgePort": 50050,
      "threads": 8
    }
  ],
  "authToken": "cluster-secret-token"
}
```

*Note: `cluster.config.json` is gitignored to keep private IP addresses and credentials local. A template is provided in [`cluster.config.example.json`](file:///D:/Offline-AI-Cluster/cluster.config.example.json).*

---

## Environment Variable Overrides

Any node can participate without modifying config files by using standard environment variables:

| Variable | Description | Example |
| :--- | :--- | :--- |
| `CLUSTER_WORKERS` | Comma-separated list of remote RPC workers | `192.168.1.18:50052,10.0.0.5:50052` |
| `CLUSTER_AUTH_TOKEN` | Shared authentication secret for node bridge | `your-secret-token` |
| `CLUSTER_BRIDGE_PORT`| Port for node telemetry and remote execution | `50050` |
| `CLUSTER_MODEL` | Default GGUF model path | `D:\llms\Llama-3.2-1B-Instruct-Q4_K_M.gguf` |

---

## Multi-Node CLI (`cluster`)

The cluster provides a unified controller located at [`D:\Offline-AI-Cluster\cluster.cmd`](file:///D:/Offline-AI-Cluster/cluster.cmd) and [`D:\Offline-AI-Cluster\cluster.js`](file:///D:/Offline-AI-Cluster/cluster.js).

### Commands

```bat
:: Check health, ports, and telemetry across all configured nodes
cluster status

:: Send an inference prompt to the distributed cluster
cluster prompt "Explain distributed tensor parallelization in two sentences."

:: Start remote worker daemons across all nodes (or a specific node index)
cluster worker-start
cluster worker-start 0

:: Stop remote worker daemons
cluster worker-stop

:: Execute a shell command on a specific worker node
cluster exec 0 "systeminfo"

:: Generate the --rpc CLI argument string for llama-server
cluster rpc-args

:: Launch 1-click Remote Desktop session to a worker node
cluster rdp 0

:: Check and hot-update llama.cpp binaries from GitHub upstream
cluster update
```

---

## Operational Guidelines & Constraints

1. **Strictly Native Execution**:
   - **NO Ollama, NO LM Studio**.
   - Always run native `llama-server.exe`, `llama-cli.exe`, and `ggml-rpc-server.exe`.
2. **Model Storage**:
   - Standard GGUF models are stored in `D:\llms\` or `models/`.
   - Never duplicate models into proprietary blob directories.
3. **Multi-Node Sharding**:
   - When multiple workers are configured, the coordinator automatically builds the multi-endpoint argument:
     `--rpc worker1:50052,worker2:50052,worker3:50052`
   - Tensor graphs are partitioned across all active backends based on available memory and compute threads.
