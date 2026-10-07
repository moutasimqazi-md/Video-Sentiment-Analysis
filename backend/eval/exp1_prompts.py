"""Experiment 1: prompt ensembles and logit calibration (zero-shot only; no labels are used to fit anything here).
Run: .venv\\Scripts\\python -m eval.exp1_prompts"""
import numpy as np
import torch

from eval.common import CATEGORIES, fmt, load_dataset, metrics
from eval.prompt_sets import V2
from neurolens import analyzer

ds = load_dataset()
y, X = ds["y"], ds["vis"]
model, processor = analyzer._load_model()


def text_protos(prompt_map, template=None):
    out = []
    with torch.no_grad():
        for c in CATEGORIES:
            ps = [template.format(p) for p in prompt_map[c]] if template else prompt_map[c]
            f = analyzer._text_embedding(model, processor(text=ps, return_tensors="pt", padding=True))
            f = f / f.norm(dim=-1, keepdim=True)
            m = f.mean(0)
            out.append((m / m.norm()).numpy())
    return np.stack(out)


def run(name, T, scale=100, calib=None):
    lg = scale * X @ T.T
    if calib is not None:
        lg = (lg - calib[0]) / calib[1]
    m = metrics(y, lg.argmax(1), lg)
    print(f"{name:52s} {fmt(m)}")
    return m, lg


T0 = text_protos(analyzer.CATEGORY_PROMPTS)
T2 = text_protos(V2)
T2t = text_protos(V2, "a video frame showing {}")

# unsupervised calibration statistics: mean/std of each class logit over ALL stored analyses (labeled or not; no labels used)
import sqlite3
from neurolens import logstore
con = sqlite3.connect(logstore.DB_PATH)
allX = np.stack([np.load(logstore.resolve("embed", r[0])) for r in con.execute("SELECT visual_embedding_path FROM analyses WHERE error IS NULL AND visual_embedding_path IS NOT NULL")]).astype(np.float32)
print(f"calibration statistics from {len(allX)} stored analyses (no labels)\n")

def stats(T, scale=100):
    lg = scale * allX @ T.T
    return lg.mean(0), lg.std(0) + 1e-6

print("--- zero-shot, visual only, mean embedding ---")
run("A  current prompts (2-3 per mood)", T0)
run("B  V2 ensemble (5-9 per mood)", T2)
run("C  V2 ensemble + 'a video frame showing' template", T2t)
for nm, T in [("A", T0), ("B", T2), ("C", T2t)]:
    run(f"{nm} + per-class logit standardisation (unsupervised)", T, calib=stats(T))
mean_only = lambda T: (stats(T)[0], np.ones(16))
for nm, T in [("A", T0), ("B", T2)]:
    run(f"{nm} + per-class mean-centering only", T, calib=mean_only(T))
print("\n--- sensitivity to the softmax temperature does not change argmax; shown for calibration of probabilities only ---")
np.save("eval/_T2.npy", T2)
