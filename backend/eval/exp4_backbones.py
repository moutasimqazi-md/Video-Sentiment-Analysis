"""Experiment 4: bigger CLIP backbones on the same saved frames (3-crop), zero-shot and with the leave-one-out prototype adapter.
Run: .venv\\Scripts\\python -m eval.exp4_backbones [model ids...]"""
import sys
import time
import warnings

import numpy as np
import torch
from PIL import Image
from transformers import CLIPModel, CLIPProcessor

from eval.common import CATEGORIES, fmt, load_dataset, metrics
from neurolens.analyzer import CATEGORY_PROMPTS

warnings.filterwarnings("ignore")
torch.set_num_threads(__import__("os").cpu_count() or 4)
ds = load_dataset()
y = ds["y"]; pipe = ds["pipeline"]; n = len(y)
corrected = pipe != y; accepted = ~corrected
imgs = [Image.open(p).convert("RGB") for p in ds["thumb"]]
K = len(CATEGORIES)


def crops3(im):
    w, h = im.size
    if h <= w:
        return [im, im, im]
    return [im.crop((0, 0, w, w)), im.crop((0, (h - w) // 2, w, (h - w) // 2 + w)), im.crop((0, h - w, w, h))]


def feats(out):
    return out if isinstance(out, torch.Tensor) else out.pooler_output


def run(model_id):
    t0 = time.time()
    model = CLIPModel.from_pretrained(model_id).eval(); proc = CLIPProcessor.from_pretrained(model_id)
    load = time.time() - t0
    with torch.no_grad():
        T = []
        for c in CATEGORIES:
            f = feats(model.get_text_features(**proc(text=CATEGORY_PROMPTS[c], return_tensors="pt", padding=True))); f = f / f.norm(dim=-1, keepdim=True)
            m = f.mean(0); T.append((m / m.norm()).numpy())
        T = np.stack(T)
    t1 = time.time(); E = []
    with torch.inference_mode():
        for k in range(3):
            part = []
            batch = [crops3(i)[k] for i in imgs]
            for i in range(0, len(batch), 16):
                f = feats(model.get_image_features(**proc(images=batch[i:i + 16], return_tensors="pt"))); part.append((f / f.norm(dim=-1, keepdim=True)).numpy())
            E.append(np.concatenate(part))
    per_img = (time.time() - t1) / (3 * len(imgs))
    X = np.mean(E, axis=0); X /= np.linalg.norm(X, axis=1, keepdims=True)
    ZS = 100 * X @ T.T
    m0 = metrics(y, ZS.argmax(1), ZS)
    fix0 = (ZS.argmax(1)[corrected] == y[corrected]).mean() * 100; keep0 = (ZS.argmax(1)[accepted] == y[accepted]).mean() * 100
    # leave-one-out prototype adapter
    best = None
    for beta in (0.5, 1.0):
        S = np.zeros_like(ZS)
        for i in range(n):
            tr = np.arange(n) != i
            P = np.zeros((K, X.shape[1]), np.float32); has = np.zeros(K, bool)
            for c in range(K):
                mk = tr & (y == c)
                if mk.any():
                    p = X[mk].mean(0); P[c] = p / np.linalg.norm(p); has[c] = True
            sim = 100 * X[i:i + 1] @ P.T; sim[:, ~has] = 0
            S[i] = ZS[i] + beta * sim[0]
        m1 = metrics(y, S.argmax(1), S)
        fix1 = (S.argmax(1)[corrected] == y[corrected]).mean() * 100; keep1 = (S.argmax(1)[accepted] == y[accepted]).mean() * 100
        if best is None or m1["acc"] > best[1]["acc"]: best = (beta, m1, fix1, keep1)
    print(f"\n{model_id}   (load {load:.0f}s, {per_img*1000:.0f} ms per image crop on this CPU)")
    print(f"   zero-shot              {fmt(m0)} | fixes {fix0:3.0f}%, keeps {keep0:3.0f}%")
    print(f"   + prototype adapter    {fmt(best[1])} | fixes {best[2]:3.0f}%, keeps {best[3]:3.0f}%  (beta {best[0]})")
    np.save(f"eval/_emb_{model_id.split('/')[-1]}.npy", X)


for mid in (sys.argv[1:] or ["openai/clip-vit-base-patch32", "openai/clip-vit-base-patch16", "openai/clip-vit-large-patch14"]):
    try:
        run(mid)
    except Exception as e:
        print(f"\n{mid}: skipped ({type(e).__name__}: {str(e)[:120]})")
