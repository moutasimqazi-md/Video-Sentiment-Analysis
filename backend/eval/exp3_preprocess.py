"""Experiment 3: frame preprocessing for vertical video. CLIP's default (resize short side, center-crop a square) discards the top and
bottom of a portrait frame. Compare: default crop, letterbox (pad to square), and 3-crop average (top / middle / bottom squares).
Uses the saved middle frame of each rated video (same frames for every variant). Run: .venv\\Scripts\\python -m eval.exp3_preprocess"""
import warnings

import numpy as np
import torch
from PIL import Image

from eval.common import CATEGORIES, fmt, load_dataset, metrics
from neurolens import analyzer

warnings.filterwarnings("ignore")
ds = load_dataset()
y = ds["y"]; pipe = ds["pipeline"]
corrected = pipe != y; accepted = ~corrected
model, processor = analyzer._load_model()
te = analyzer._category_text_embeddings()
T = torch.stack([te[c] for c in CATEGORIES]).numpy()

imgs = [Image.open(p).convert("RGB") for p in ds["thumb"]]
print(f"{len(imgs)} frames; portrait share: {np.mean([i.height > i.width for i in imgs])*100:.0f}% | mean size {np.mean([i.width for i in imgs]):.0f}x{np.mean([i.height for i in imgs]):.0f}")


def embed(images):
    out = []
    with torch.inference_mode():
        for i in range(0, len(images), 16):
            f = analyzer._image_embedding(model, processor(images=images[i:i + 16], return_tensors="pt"))
            out.append((f / f.norm(dim=-1, keepdim=True)).numpy())
    return np.concatenate(out)


def letterbox(im, fill=(0, 0, 0)):
    s = max(im.size); c = Image.new("RGB", (s, s), fill); c.paste(im, ((s - im.width) // 2, (s - im.height) // 2)); return c


def crops3(im):
    w, h = im.size
    if h <= w:
        return [im, im, im]
    s = w
    return [im.crop((0, 0, s, s)), im.crop((0, (h - s) // 2, s, (h - s) // 2 + s)), im.crop((0, h - s, s, h))]


def score(name, E):
    lg = 100 * E @ T.T
    m = metrics(y, lg.argmax(1), lg)
    fix = (lg.argmax(1)[corrected] == y[corrected]).mean() * 100; keep = (lg.argmax(1)[accepted] == y[accepted]).mean() * 100
    print(f"{name:34s} {fmt(m)} | fixes {fix:4.0f}%, keeps {keep:4.0f}%")
    return lg

E_default = embed(imgs)
E_letter = embed([letterbox(i) for i in imgs])
E_crops = np.mean([embed([crops3(i)[k] for i in imgs]) for k in range(3)], axis=0)
E_crops /= np.linalg.norm(E_crops, axis=1, keepdims=True)
E_mix = (E_default + E_letter + E_crops); E_mix /= np.linalg.norm(E_mix, axis=1, keepdims=True)
print("\nsingle middle frame, zero-shot prompts A (labels are partly derived from the production model, so compare variants to each other):")
score("default center-crop", E_default)
score("letterbox (pad to square)", E_letter)
score("3-crop average (top/mid/bottom)", E_crops)
score("default + letterbox + 3-crop", E_mix)
print("\nfor reference, the saved MEAN of 12-40 frames from the real pipeline:")
score("mean embedding (production input)", ds["vis"])
