#!/usr/bin/env python3
"""
Test client to query the Offline-AI-Cluster Gateway with optional RAG injection.
"""

import sys
import json
import urllib.request
import urllib.error

GATEWAY_URL = "http://localhost:8000/v1/chat/completions"

def query(prompt, system_prompt=None, max_tokens=256, temperature=0.7):
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": prompt})

    payload = {
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(GATEWAY_URL, data=data, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            return res["choices"][0]["message"]["content"]
    except urllib.error.URLError as e:
        return f"[Connection Error] Could not reach gateway at {GATEWAY_URL}: {e}"

if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "Explain what makes an offline distributed AI cluster resilient."
    print(f"Sending prompt to cluster gateway ({GATEWAY_URL})...\nPrompt: {prompt}\n")
    response = query(prompt)
    print("=" * 60)
    print("Cluster Response:")
    print("=" * 60)
    print(response)
