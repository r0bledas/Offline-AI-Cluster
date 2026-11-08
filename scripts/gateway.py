#!/usr/bin/env python3
"""
Offline-AI-Cluster Gateway, Load Balancer & Auto-Discovery Beacon
- Listens on HTTP port 8000 for OpenAI-compatible chat requests and status.
- Listens on UDP port 50050 for automatic peer discovery from portable worker nodes.
- Exposes dynamic /cluster/status with auto-calculated --rpc and --tensor-split flags.
- Handles circuit breaker failover if any active node drops offline.
"""

import http.server
import json
import os
import sys
import time
import socket
import threading
import urllib.request
import urllib.error

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "cluster.json")

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[Warning] Failed to parse cluster.json: {e}")
    return {
        "gateway": {"listen_port": 8000, "failover_timeout_sec": 1.5, "beacon_port": 50050},
        "nodes": []
    }

CONFIG = load_config()
HTTP_PORT = CONFIG.get("gateway", {}).get("listen_port", 8000)
BEACON_PORT = CONFIG.get("gateway", {}).get("beacon_port", 50050)

# In-memory dynamic node registry: thread-safe dictionary { ip: node_data }
REGISTRY_LOCK = threading.Lock()
ACTIVE_REGISTRY = {}

# Pre-populate registry with statically configured nodes from cluster.json
for n in CONFIG.get("nodes", []):
    ACTIVE_REGISTRY[n["ip"]] = {
        "id": n.get("id", n["name"]),
        "name": n["name"],
        "ip": n["ip"],
        "rpc_port": n.get("rpc_port", 50052),
        "http_port": n.get("http_port", 8080),
        "memory_gb": n.get("memory_gb", 8),
        "accelerator": n.get("accelerator", "cpu"),
        "priority": n.get("priority", 99),
        "last_seen": time.time(),
        "dynamic": False
    }

def register_node(ip, name, rpc_port=50052, http_port=8080, memory_gb=8, accelerator="cpu"):
    with REGISTRY_LOCK:
        ACTIVE_REGISTRY[ip] = {
            "id": f"node-{ip.replace('.', '-')}",
            "name": name,
            "ip": ip,
            "rpc_port": rpc_port,
            "http_port": http_port,
            "memory_gb": memory_gb,
            "accelerator": accelerator,
            "priority": 10 if "gpu" in accelerator.lower() or "metal" in accelerator.lower() else 50,
            "last_seen": time.time(),
            "dynamic": True
        }
    print(f"[AutoDiscovery] Node registered: '{name}' at {ip} ({memory_gb} GB RAM, RPC port {rpc_port})")

def start_udp_beacon_listener():
    """Listens for UDP broadcast packets from portable worker nodes running node_agent.py."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", BEACON_PORT))
        print(f"[Beacon] UDP auto-discovery listening on 0.0.0.0:{BEACON_PORT}")
    except Exception as e:
        print(f"[Beacon Warning] Could not bind UDP discovery port {BEACON_PORT}: {e}")
        return

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            payload = json.loads(data.decode("utf-8"))
            if payload.get("event") == "discover":
                worker_name = payload.get("name", "Unknown-Worker")
                rpc_port = payload.get("rpc_port", 50052)
                memory_gb = payload.get("memory_gb", 8)
                accelerator = payload.get("accelerator", "cpu")

                register_node(addr[0], worker_name, rpc_port=rpc_port, memory_gb=memory_gb, accelerator=accelerator)

                # Send acknowledgment back to worker
                reply = json.dumps({
                    "status": "registered",
                    "orchestrator_ip": socket.gethostbyname(socket.gethostname()),
                    "gateway_port": HTTP_PORT
                }).encode("utf-8")
                sock.sendto(reply, addr)
        except Exception:
            continue

def get_node_url(node):
    return f"http://{node['ip']}:{node.get('http_port', 8080)}"

def check_node_alive(node, timeout=1.5):
    url = get_node_url(node)
    for endpoint in ["/api/status", "/health", "/"]:
        try:
            req = urllib.request.Request(f"{url}{endpoint}", headers={"User-Agent": "ClusterGateway/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status == 200:
                    node["last_seen"] = time.time()
                    return True
        except Exception:
            continue
    return False

def get_active_nodes():
    with REGISTRY_LOCK:
        nodes = list(ACTIVE_REGISTRY.values())
    active = []
    for node in sorted(nodes, key=lambda x: x.get("priority", 99)):
        if check_node_alive(node):
            active.append(node)
    return active

def build_orchestrator_cli():
    """Generates the exact --rpc and --tensor-split flags for llama-server."""
    with REGISTRY_LOCK:
        nodes = list(ACTIVE_REGISTRY.values())

    rpc_endpoints = []
    tensor_weights = []
    for n in nodes:
        rpc_endpoints.append(f"{n['ip']}:{n['rpc_port']}")
        tensor_weights.append(str(int(n.get("memory_gb", 8))))

    rpc_flag = "--rpc " + ",".join(rpc_endpoints) if rpc_endpoints else ""
    split_flag = "--tensor-split " + ",".join(tensor_weights) if tensor_weights else ""
    return rpc_flag, split_flag

class ClusterGatewayHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        sys.stderr.write(f"[Gateway] {self.client_address[0]} - {format % args}\n")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_GET(self):
        if self.path in ["/health", "/cluster/status", "/api/cluster"]:
            self.send_cluster_status()
            return
        self.forward_request("GET")

    def do_POST(self):
        if self.path == "/cluster/register":
            self.handle_self_registration()
            return
        self.forward_request("POST")

    def handle_self_registration(self):
        """Allows workers to self-register via HTTP POST /cluster/register."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            payload = json.loads(body.decode("utf-8"))
            client_ip = self.client_address[0]
            name = payload.get("name", f"Worker-{client_ip}")
            rpc_port = payload.get("rpc_port", 50052)
            http_port = payload.get("http_port", 8080)
            memory_gb = payload.get("memory_gb", 8)
            accelerator = payload.get("accelerator", "cpu")

            register_node(client_ip, name, rpc_port=rpc_port, http_port=http_port, memory_gb=memory_gb, accelerator=accelerator)

            rpc_flag, split_flag = build_orchestrator_cli()
            res = json.dumps({
                "status": "success",
                "registered_ip": client_ip,
                "cluster_total_nodes": len(ACTIVE_REGISTRY),
                "orchestrator_flags": f"{rpc_flag} {split_flag}"
            }).encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(res)
        except Exception as e:
            self.send_error(400, f"Registration failed: {e}")

    def send_cluster_status(self):
        with REGISTRY_LOCK:
            nodes = list(ACTIVE_REGISTRY.values())

        report = []
        total_ram = 0
        for node in nodes:
            alive = check_node_alive(node)
            mem = float(node.get("memory_gb", 0))
            if alive:
                total_ram += mem
            report.append({
                "name": node["name"],
                "ip": node["ip"],
                "rpc_endpoint": f"{node['ip']}:{node['rpc_port']}",
                "alive": alive,
                "memory_gb": mem,
                "accelerator": node.get("accelerator", "cpu"),
                "dynamic": node.get("dynamic", False)
            })

        rpc_flag, split_flag = build_orchestrator_cli()

        body = json.dumps({
            "gateway_status": "operational",
            "cluster_nodes": report,
            "healthy_node_count": sum(1 for n in report if n["alive"]),
            "total_pooled_ram_gb": round(total_ram, 1),
            "generated_launch_command": f"./llama-server -m <model.gguf> {rpc_flag} {split_flag} -ngl 99"
        }, indent=2).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def forward_request(self, method):
        active_nodes = get_active_nodes()
        if not active_nodes:
            self.send_error(503, "No available compute nodes in offline cluster")
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        for attempt, node in enumerate(active_nodes):
            target_url = get_node_url(node) + self.path
            req = urllib.request.Request(target_url, data=body, method=method)
            for k, v in self.headers.items():
                if k.lower() not in ["host", "content-length"]:
                    req.add_header(k, v)

            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    resp_data = resp.read()
                    self.send_response(resp.status)
                    for hk, hv in resp.headers.items():
                        if hk.lower() not in ["transfer-encoding", "content-length"]:
                            self.send_header(hk, hv)
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Content-Length", str(len(resp_data)))
                    self.end_headers()
                    self.wfile.write(resp_data)
                    return
            except urllib.error.HTTPError as e:
                err_data = e.read()
                self.send_response(e.code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(err_data)
                return
            except Exception as e:
                print(f"[CircuitBreaker] Node '{node['name']}' ({node['ip']}) unreachable during {method}: {e}")
                print(f"[CircuitBreaker] Rerouting to next available node...")
                continue

        self.send_error(502, "All candidate cluster nodes failed to respond")

if __name__ == "__main__":
    beacon_thread = threading.Thread(target=start_udp_beacon_listener, daemon=True)
    beacon_thread.start()

    server = http.server.ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), ClusterGatewayHandler)
    print("=" * 65)
    print("      OFFLINE AI CLUSTER GATEWAY & AUTO-DISCOVERY BEACON")
    print("=" * 65)
    print(f"HTTP Gateway & API:  http://0.0.0.0:{HTTP_PORT}")
    print(f"UDP Discovery Beacon: Port {BEACON_PORT} (Zero-Config Worker Auto-Join)")
    print(f"Status & Flags API:   http://localhost:{HTTP_PORT}/cluster/status")
    print("-" * 65)
    print("Ready. Start worker nodes with 'python scripts/node_agent.py'.\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nGateway stopped.")
