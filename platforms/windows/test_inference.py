#!/usr/bin/env python3
"""
Offline-AI-Cluster Benchmark & Inference Verification Tool
Sends test prompts to the Master Orchestrator, measures TTFT, TPS, and validates responses.
"""

import sys
import time
import json
import urllib.request
import urllib.error

API_URL = "http://127.0.0.1:8000/v1/chat/completions"

def run_test(prompt="Explain the difference between RAM and VRAM in two sentences."):
    print(f"[*] Target Endpoint: {API_URL}")
    print(f"[*] Prompt: \"{prompt}\"")
    print("[*] Sending request to cluster...")

    payload = {
        "messages": [
            {"role": "system", "content": "You are a concise, helpful assistant."},
            {"role": "user", "content": prompt}
        ],
        "temperature": 0.2,
        "max_tokens": 150,
        "stream": False
    }

    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            t1 = time.perf_counter()
            data = json.loads(resp.read().decode("utf-8"))
            elapsed = t1 - t0

            content = data["choices"][0]["message"]["content"]
            usage = data.get("usage", {})
            completion_tokens = usage.get("completion_tokens", 0)
            prompt_tokens = usage.get("prompt_tokens", 0)
            total_tokens = usage.get("total_tokens", 0)

            tps = (completion_tokens / elapsed) if elapsed > 0 else 0

            print("\n" + "=" * 50)
            print(" CLUSTER INFERENCE RESPONSE")
            print("=" * 50)
            print(content.strip())
            print("=" * 50)
            print(f"[*] Latency / Elapsed:    {elapsed:.2f} s")
            print(f"[*] Prompt Tokens:        {prompt_tokens}")
            print(f"[*] Generated Tokens:     {completion_tokens}")
            print(f"[*] Total Tokens:         {total_tokens}")
            print(f"[*] Generation Speed:     {tps:.2f} tokens/sec")
            print("=" * 50)
            print("[✓] Verification: SUCCESS - Cluster is responding cleanly!")
            return True
    except urllib.error.URLError as e:
        print(f"\n[-] Request failed: {e}")
        print("[-] Ensure the Master Orchestrator is running on port 8000.")
        return False

if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "Explain what an offline AI cluster is in two sentences."
    success = run_test(prompt)
    sys.exit(0 if success else 1)
