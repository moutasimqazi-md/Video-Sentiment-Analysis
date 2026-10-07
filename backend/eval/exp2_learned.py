"""Experiment 2: learning from the feedback labels, scored leave-one-out (each example is predicted by a model that never saw it).
Reported separately for the 33 *corrections* (cases the production model got wrong: fixing them is the real gain) and the 59
*accepted* ones (breaking them is the cost). Run: .venv\\Scripts\\python -m eval.exp2_learned"""
import sqlite3
import warnings

import numpy as np
import torch
from sklearn.linear_model import LogisticRegression

from eval.common import CATEGORIES, fmt, load_dataset, metrics
from neurolens import analyzer, logstore

warnings.filterwarnings("ignore")
ds = load_dataset()
y, X, pipe = ds["y"], ds["vis"], ds["pipeline"]
n = len(y)
corrected = pipe != y           # the production pipeline was wrong here
accepted = ~corrected
te = analyzer._category_text_embeddings()
T = torch.stack([te[c] for c in CATEGORIES]).numpy()
ZS = 100 * X @ T.T              # today's zero-shot logits on the mean embedding
K = len(CATEGORIES)


def report(name, pred, scores=None):
    m = metrics(y, pred, scores)
    fix = (pred[corrected] == y[corrected]).mean() * 100
    keep = (pred[accepted] == y[accepted]).mean() * 100
    print(f"{name:46s} {fmt(m)} | fixes {fix:4.0f}% of corrections, keeps {keep:4.0f}% of accepted")
    return m


def loo(fit_predict):
    scores = np.zeros((n, K), dtype=np.float32)
    for i in range(n):
        tr = np.arange(n) != i
        scores[i] = fit_predict(X[tr], y[tr], ZS[tr], X[i:i + 1], ZS[i:i + 1])[0]
    return scores


print("reference points")
report("production pipeline (visual+audio, as rated)", pipe)
report("offline zero-shot A (today's prompts)", ZS.argmax(1), ZS)
print("\nlearned heads, leave-one-out:")

def lr(C):
    def fp(Xtr, ytr, ZStr, Xte, ZSte):
        clf = LogisticRegression(C=C, max_iter=500, class_weight="balanced").fit(Xtr, ytr)
        out = np.full((len(Xte), K), -1e9, dtype=np.float32)
        out[:, clf.classes_] = clf.decision_function(Xte)
        return out
    return fp

def prototypes(beta, shrink=0.0):
    """Tip-Adapter style: zero-shot logits + beta * similarity to the class prototypes built from labeled examples."""
    def fp(Xtr, ytr, ZStr, Xte, ZSte):
        P = np.zeros((K, X.shape[1]), dtype=np.float32); has = np.zeros(K, bool)
        for c in range(K):
            m = ytr == c
            if m.any():
                p = Xtr[m].mean(0); P[c] = p / np.linalg.norm(p); has[c] = True
        sim = 100 * Xte @ P.T
        sim[:, ~has] = 0
        return ZSte + beta * sim
    return fp

def fused(C, w):
    """Logistic regression on [embedding, zero-shot logits]: the zero-shot logits act as a prior the head can correct."""
    def fp(Xtr, ytr, ZStr, Xte, ZSte):
        f = lambda A, Z: np.hstack([A, w * Z / 100])
        clf = LogisticRegression(C=C, max_iter=800, class_weight="balanced").fit(f(Xtr, ZStr), ytr)
        out = np.full((len(Xte), K), -1e9, dtype=np.float32)
        out[:, clf.classes_] = clf.decision_function(f(Xte, ZSte))
        return out
    return fp

for C in (0.3, 1, 3, 10):
    s = loo(lr(C)); report(f"logistic regression, C={C}", s.argmax(1), s)
for b in (0.5, 1, 2, 4):
    s = loo(prototypes(b)); report(f"prototype adapter (zero-shot + {b} x prototypes)", s.argmax(1), s)
for C, w in ((1, 1), (3, 1), (3, 3), (10, 3)):
    s = loo(fused(C, w)); report(f"fused LR on [embedding, zero-shot], C={C}, w={w}", s.argmax(1), s)
