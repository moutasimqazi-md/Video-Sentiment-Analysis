"""Baseline: how good is the model today on the labeled set? Run: .venv\\Scripts\\python -m eval.baseline"""
import collections

import numpy as np
import torch

from eval.common import CATEGORIES, fmt, load_dataset, metrics
from neurolens import analyzer

ds = load_dataset()
y, X = ds["y"], ds["vis"]
print(f"labeled examples: {len(y)} across {len(set(y.tolist()))} of {len(CATEGORIES)} classes")
print("label counts:", dict(collections.Counter(CATEGORIES[i] for i in y).most_common()))

print("\n1) the full production pipeline (visual + audio, as it ran when you rated it):")
m = metrics(y, ds["pipeline"]); print("  ", fmt(m))
pc = collections.Counter(CATEGORIES[i] for i in ds["pipeline"])
print("   predicted:", dict(pc.most_common(8)))

print("\n2) offline re-run: today's zero-shot prompts on the saved mean visual embedding:")
te = analyzer._category_text_embeddings()
T = torch.stack([te[c] for c in CATEGORIES]).numpy()          # 16 x 512
logits = 100 * X @ T.T
m = metrics(y, logits.argmax(1), logits); print("  ", fmt(m))
pc = collections.Counter(CATEGORIES[i] for i in logits.argmax(1))
print("   predicted:", dict(pc.most_common(8)))
print("   per-class recall:", {k: round(v, 2) for k, v in m["recall"].items()})
print("\n   most common errors (true -> predicted):")
err = collections.Counter((CATEGORIES[a], CATEGORIES[b]) for a, b in zip(y, logits.argmax(1)) if a != b)
for (a, b), n in err.most_common(8): print(f"     {a:11s} -> {b:11s} x{n}")
