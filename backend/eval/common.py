"""Shared helpers for offline model evaluation. The labeled set is every analysis you rated in the app:
'good' -> the predicted mood was right, 'bad' + a correction -> the corrected mood. Embeddings and the middle frame of each
video were saved at analysis time, so changes to prompts, heads and image preprocessing can be scored without the videos."""

import json
import os
import sqlite3
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from neurolens import logstore  # noqa: E402
from neurolens.analyzer import CATEGORY_PROMPTS  # noqa: E402

CATEGORIES = list(CATEGORY_PROMPTS.keys())
CIDX = {c: i for i, c in enumerate(CATEGORIES)}


def load_dataset():
    con = sqlite3.connect(logstore.DB_PATH)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        """SELECT job_id, dominant_mood, feedback, corrected_mood, averages_json, visual_averages_json,
                  thumbnail_path, visual_embedding_path, audio_embedding_path, source_kind, source_title
           FROM analyses WHERE error IS NULL AND feedback IS NOT NULL AND visual_embedding_path IS NOT NULL"""
    ).fetchall()
    ds = {k: [] for k in ["id", "y", "pipeline", "vis", "aud", "thumb", "title"]}
    for r in rows:
        label = r["dominant_mood"] if r["feedback"] == "good" else r["corrected_mood"]
        if not label:
            continue
        ds["id"].append(r["job_id"])
        ds["y"].append(CIDX[label])
        ds["pipeline"].append(CIDX[r["dominant_mood"]])
        ds["vis"].append(np.load(logstore.resolve("embed", r["visual_embedding_path"])))
        a = logstore.resolve("embed", r["audio_embedding_path"]) if r["audio_embedding_path"] else None
        ds["aud"].append(np.load(a) if a and a.exists() else None)
        ds["thumb"].append(str(logstore.resolve("thumb", r["thumbnail_path"])) if r["thumbnail_path"] else None)
        ds["title"].append(r["source_title"])
    out = {k: (np.array(v) if k in ("y", "pipeline") else v) for k, v in ds.items()}
    out["vis"] = np.stack(ds["vis"]).astype(np.float32)
    return out


def metrics(y, pred, scores=None):
    """Top-1, balanced accuracy (mean per-class recall), macro-F1 over classes that occur, top-3 and per-class recall."""
    y, pred = np.asarray(y), np.asarray(pred)
    classes = sorted(set(y.tolist()))
    rec, f1 = {}, []
    for c in classes:
        tp = int(((pred == c) & (y == c)).sum()); fn = int(((pred != c) & (y == c)).sum()); fp = int(((pred == c) & (y != c)).sum())
        rec[CATEGORIES[c]] = tp / max(tp + fn, 1)
        f1.append(2 * tp / max(2 * tp + fp + fn, 1))
    out = {"acc": float((pred == y).mean()), "bal_acc": float(np.mean(list(rec.values()))), "macro_f1": float(np.mean(f1)), "recall": rec}
    if scores is not None:
        top3 = np.argsort(-scores, axis=1)[:, :3]
        out["top3"] = float(np.mean([y[i] in top3[i] for i in range(len(y))]))
    return out


def fmt(m):
    t3 = f" top3 {m['top3']*100:4.1f}%" if "top3" in m else ""
    return f"acc {m['acc']*100:5.1f}%  balanced {m['bal_acc']*100:5.1f}%  macroF1 {m['macro_f1']*100:5.1f}%{t3}"
