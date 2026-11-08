#!/usr/bin/env python3
"""
Offline-AI-Cluster: Local RAG (Retrieval-Augmented Generation) Engine
100% Air-Gapped, Zero-Cloud Dependencies.
Extracts, chunks, embeds, indexes, and retrieves local documents for generation.
"""

import os
import sys
import json
import math
import argparse
import urllib.request
import urllib.error

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
DEFAULT_INDEX_PATH = os.path.join(DATA_DIR, "vector_store.json")

# Default local embedding server (e.g. llama-server running an embedding model like bge-small on port 8081)
DEFAULT_EMBED_URL = "http://localhost:8081/v1/embeddings"
DEFAULT_GATEWAY_URL = "http://localhost:8000/v1/chat/completions"

class LocalEmbeddingClient:
    """Interfaces with a local GGUF embedding model running via llama-server."""
    def __init__(self, endpoint=DEFAULT_EMBED_URL):
        self.endpoint = endpoint

    def get_embedding(self, text):
        data = json.dumps({"input": text, "model": "local-embedding"}).encode("utf-8")
        req = urllib.request.Request(
            self.endpoint,
            data=data,
            headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                res = json.loads(resp.read().decode("utf-8"))
                return res["data"][0]["embedding"]
        except Exception:
            # Fallback to local deterministic bag-of-words / hashing vectorizer
            # if an embedding server is not actively running
            return self._fallback_hash_vector(text, dim=384)

    def _fallback_hash_vector(self, text, dim=384):
        """Zero-dependency deterministic hashing embedding fallback."""
        vec = [0.0] * dim
        words = text.lower().split()
        if not words:
            return vec
        for w in words:
            h = hash(w) % dim
            vec[h] += 1.0
        # Normalize vector
        norm = math.sqrt(sum(x * x for x in vec))
        if norm > 0:
            vec = [x / norm for x in vec]
        return vec

def cosine_similarity(v1, v2):
    if len(v1) != len(v2):
        return 0.0
    dot = sum(a * b for a, b in zip(v1, v2))
    norm1 = math.sqrt(sum(a * a for a in v1))
    norm2 = math.sqrt(sum(b * b for b in v2))
    if norm1 == 0 or norm2 == 0:
        return 0.0
    return dot / (norm1 * norm2)

class DocumentChunker:
    """Splits documents into overlapping chunks with sentence awareness."""
    def __init__(self, chunk_size=512, overlap=64):
        self.chunk_size = chunk_size
        self.overlap = overlap

    def chunk_text(self, text, source="unknown"):
        paragraphs = text.split("\n\n")
        chunks = []
        cur_chunk = ""
        cur_tokens = 0

        for p in paragraphs:
            p = p.strip()
            if not p:
                continue
            words = p.split()
            word_count = len(words)

            if cur_tokens + word_count <= self.chunk_size:
                cur_chunk += ("\n\n" if cur_chunk else "") + p
                cur_tokens += word_count
            else:
                if cur_chunk:
                    chunks.append({"text": cur_chunk, "source": source, "tokens": cur_tokens})
                # Handle overlap
                tail = " ".join(cur_chunk.split()[-self.overlap:]) if self.overlap > 0 else ""
                cur_chunk = (tail + "\n\n" + p) if tail else p
                cur_tokens = len(cur_chunk.split())

        if cur_chunk:
            chunks.append({"text": cur_chunk, "source": source, "tokens": cur_tokens})

        return chunks

class LocalVectorStore:
    """In-memory cosine vector store with JSON persistence."""
    def __init__(self, index_path=DEFAULT_INDEX_PATH):
        self.index_path = index_path
        self.records = []
        self.load()

    def load(self):
        if os.path.exists(self.index_path):
            try:
                with open(self.index_path, "r", encoding="utf-8") as f:
                    self.records = json.load(f)
            except Exception as e:
                print(f"[RAG Store] Warning loading store: {e}")
                self.records = []

    def save(self):
        os.makedirs(os.path.dirname(os.path.abspath(self.index_path)), exist_ok=True)
        with open(self.index_path, "w", encoding="utf-8") as f:
            json.dump(self.records, f, indent=2)

    def add(self, chunk, embedding):
        self.records.append({
            "text": chunk["text"],
            "source": chunk["source"],
            "embedding": embedding
        })

    def search(self, query_vector, top_k=3):
        scored = []
        for r in self.records:
            score = cosine_similarity(query_vector, r["embedding"])
            scored.append((score, r))
        scored.sort(key=lambda x: x[0], reverse=True)
        return scored[:top_k]

class RAGPipeline:
    def __init__(self, embed_client=None, vector_store=None):
        self.embed_client = embed_client or LocalEmbeddingClient()
        self.store = vector_store or LocalVectorStore()
        self.chunker = DocumentChunker()

    def ingest_file(self, filepath):
        print(f"[RAG Ingest] Reading: {filepath}")
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            text = f.read()

        source_name = os.path.basename(filepath)
        chunks = self.chunker.chunk_text(text, source=source_name)
        print(f"[RAG Ingest] Extracted {len(chunks)} chunks. Generating embeddings...")

        for i, c in enumerate(chunks):
            emb = self.embed_client.get_embedding(c["text"])
            self.store.add(c, emb)

        self.store.save()
        print(f"[RAG Ingest] Successfully indexed {filepath} (Total in index: {len(self.store.records)})")

    def ingest_directory(self, dirpath):
        for root, _, files in os.walk(dirpath):
            for file in files:
                if file.endswith((".txt", ".md", ".json", ".csv", ".py", ".cpp", ".c", ".h")):
                    self.ingest_file(os.path.join(root, file))

    def query(self, user_query, top_k=3):
        q_emb = self.embed_client.get_embedding(user_query)
        results = self.store.search(q_emb, top_k=top_k)

        context_blocks = []
        for rank, (score, r) in enumerate(results, start=1):
            context_blocks.append(f"--- Document Source: {r['source']} (Relevance Score: {score:.3f}) ---\n{r['text']}")

        augmented_context = "\n\n".join(context_blocks)
        prompt = f"""You are a specialized offline AI assistant with access to verified local knowledge.
Answer the user's inquiry accurately using ONLY the context provided below. If the context does not contain the answer, explicitly state that the information is not in the local knowledge base.

[VERIFIED LOCAL CONTEXT]:
{augmented_context}

[USER QUESTION]:
{user_query}

[RESPONSE]:"""
        return prompt, results

def query_cluster(prompt, gateway_url=DEFAULT_GATEWAY_URL):
    data = json.dumps({
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
        "max_tokens": 512
    }).encode("utf-8")

    req = urllib.request.Request(gateway_url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            return res["choices"][0]["message"]["content"]
    except Exception as e:
        return f"[Cluster Query Error] {e}"

def main():
    parser = argparse.ArgumentParser(description="Offline RAG Engine for Offline-AI-Cluster")
    subparsers = parser.add_subparsers(dest="command")

    ingest_p = subparsers.add_parser("ingest", help="Ingest a file or directory")
    ingest_p.add_argument("--file", help="File to index")
    ingest_p.add_argument("--dir", help="Directory of files to index")

    query_p = subparsers.add_parser("query", help="Query with RAG context")
    query_p.add_argument("question", help="User question")
    query_p.add_argument("--top_k", type=int, default=3, help="Number of context passages")
    query_p.add_argument("--send", action="store_true", help="Send prompt to cluster gateway")

    args = parser.parse_args()
    pipeline = RAGPipeline()

    if args.command == "ingest":
        if args.file:
            pipeline.ingest_file(args.file)
        elif args.dir:
            pipeline.ingest_directory(args.dir)
        else:
            print("Specify --file or --dir")

    elif args.command == "query":
        prompt, hits = pipeline.query(args.question, top_k=args.top_k)
        print("\n" + "=" * 60)
        print("          RETRIEVED LOCAL CONTEXT (TOP HITS)")
        print("=" * 60)
        for score, r in hits:
            print(f"[{score:.3f}] {r['source']}: {r['text'][:140]}...")
        print("=" * 60)

        if args.send:
            print("\nDispatching augmented prompt to cluster gateway...")
            answer = query_cluster(prompt)
            print("\n[Cluster Answer]:\n" + answer)
        else:
            print("\nGenerated Augmented Prompt:\n")
            print(prompt)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
