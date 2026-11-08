#!/usr/bin/env python3
"""
Offline-AI-Cluster Gateway & Fault-Tolerant Load Balancer
Monitors node health, provides unified OpenAI-compatible endpoint,
and dynamically failovers to surviving machines when nodes disconnect.
"""

import http.server
import json
import os
import sys
import time
import urllib.request
import urllib.error
import socket

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "cluster.json")

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[Warning] Failed to parse cluster.json: {e}")
    # Default fallback fleet
    return {
        "gateway": {"listen_port": 8000, "failover_timeout_sec": 1.5},
        "nodes": [
            {"name": "MacBook Air M2", "ip": "192.168.1.10", "http_port": 8080, "priority": 1},
            {"name": "MacBook Pro M2", "ip": "192.168.1.11", "http_port": 8080, "priority": 2},
            {"name": "ThinkPad T450",  "ip": "192.168.1.12", "http_port": 8080, "priority": 3},
            {"name": "ThinkPad T470",  "ip": "192.168.1.13", "http_port": 8080, "priority": 4},
            {"name": "Nintendo Switch","ip": "192.168.1.14", "http_port": 8080, "priority": 5},
        ]
    }

CONFIG = load_config()
PORT = CONFIG.get("gateway", {}).get("listen_port", 8000)
NODES = CONFIG.get("nodes", [])

def get_node_url(node):
    return f"http://{node['ip']}:{node.get('http_port', 8080)}"

def check_node_alive(node, timeout=1.5):
    url = get_node_url(node)
    # Check status endpoint
    for endpoint in ["/api/status", "/health", "/"]:
        try:
            req = urllib.request.Request(f"{url}{endpoint}", headers={"User-Agent": "ClusterGateway/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status == 200:
                    return True
        except Exception:
            continue
    return False

def get_active_nodes():
    active = []
    for node in sorted(NODES, key=lambda x: x.get("priority", 99)):
        if check_node_alive(node):
            active.append(node)
    return active

class ClusterGatewayHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Clean formatted logging
        sys.stderr.write(f"[Gateway] {self.client_address[0]} - {format % args}\n")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health" or self.path == "/cluster/status":
            self.send_cluster_status()
            return
        self.forward_request("GET")

    def do_POST(self):
        self.forward_request("POST")

    def send_cluster_status(self):
        status_report = []
        for node in NODES:
            alive = check_node_alive(node)
            status_report.append({
                "name": node["name"],
                "ip": node["ip"],
                "url": get_node_url(node),
                "alive": alive,
                "memory_gb": node.get("memory_gb", "unknown"),
                "accelerator": node.get("accelerator", "unknown"),
                "priority": node.get("priority", 99)
            })

        body = json.dumps({
            "gateway_status": "operational",
            "cluster_nodes": status_report,
            "healthy_count": sum(1 for n in status_report if n["alive"])
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
            self.send_error(503, "No available LLM worker nodes in offline cluster")
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
                # Upstream application error, return to client
                err_data = e.read()
                self.send_response(e.code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(err_data)
                return
            except Exception as e:
                print(f"[CircuitBreaker] Node '{node['name']}' ({node['ip']}) failed during {method}: {e}")
                print(f"[CircuitBreaker] Rerouting to next priority node in cluster...")
                continue

        self.send_error(502, "All candidate cluster nodes failed to respond")

if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), ClusterGatewayHandler)
    print("=" * 60)
    print("      OFFLINE AI CLUSTER GATEWAY & LOAD BALANCER")
    print("=" * 60)
    print(f"Listening on: http://0.0.0.0:{PORT}")
    print(f"Cluster Status API: http://localhost:{PORT}/cluster/status")
    print(f"Configured nodes: {len(NODES)}")
    for n in NODES:
        print(f"  - [{n.get('priority', '?')}] {n['name']} ({n['ip']}) - {n.get('memory_gb', '?')}GB RAM ({n.get('accelerator', 'cpu')})")
    print("-" * 60)
    print("Ready. Forwarding local queries with dynamic failover.\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nGateway stopped.")
