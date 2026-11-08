#!/usr/bin/env python3
"""
test_offline_inference.py - Zero-Dependency Cluster Client
Tests the offline OpenAI-compatible endpoint running on Node A.
Works with pure Python standard library (no pip packages needed).
"""

import sys
import json
import time
import urllib.request
import urllib.error

ENDPOINT = "http://127.0.0.1:8080/v1/chat/completions"
# Can also query from Node B using: "http://192.168.100.1:8080/v1/chat/completions"

def run_test_prompt(prompt="Explain why Apple Silicon Unified Memory is advantageous for distributed LLM inference in 3 concise bullet points.", endpoint=ENDPOINT):
    print("=" * 65)
    print(" OFFLINE CLUSTER INFERENCE TEST")
    print(f" Target Endpoint: {endpoint}")
    print("=" * 65)
    print(f"Prompt: {prompt}\n")
    print("Streaming Response:")
    print("-" * 65)

    payload = {
        "messages": [
            {"role": "system", "content": "You are a concise, high-performance offline AI running across a dual-Mac M2 cluster."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.7,
        "max_tokens": 512,
        "stream": True
    }

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    start_time = time.time()
    ttft = None
    token_count = 0

    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8").strip()
                if not line or not line.startswith("data: "):
                    continue
                data_str = line[6:]
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        if ttft is None:
                            ttft = time.time() - start_time
                        sys.stdout.write(content)
                        sys.stdout.flush()
                        token_count += 1
                except json.JSONDecodeError:
                    continue
    except urllib.error.URLError as e:
        print(f"\n[ERROR] Could not connect to cluster: {e}")
        print("Ensure 'start_coordinator_node_a.sh' is active on Node A.")
        sys.exit(1)

    total_time = time.time() - start_time
    gen_time = total_time - (ttft if ttft else 0)
    tps = (token_count / gen_time) if gen_time > 0 else 0

    print("\n" + "-" * 65)
    print("BENCHMARK METRICS:")
    print(f"  Time to First Token (TTFT) : {(ttft or 0)*1000:.1f} ms")
    print(f"  Generated Tokens           : {token_count} tokens")
    print(f"  Generation Time            : {gen_time:.2f} s")
    print(f"  Throughput                 : {tps:.2f} tokens/second")
    print(f"  Total Wall Time            : {total_time:.2f} s")
    print("=" * 65)

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else ENDPOINT
    test_prompt = sys.argv[2] if len(sys.argv) > 2 else "Explain why Apple Silicon Unified Memory is advantageous for distributed LLM inference in 3 concise bullet points."
    run_test_prompt(test_prompt, target)
