"""Visual screening for the family use case: flags revealing or suggestive footage, with the frames that triggered it so a parent
can judge for themselves. It does not detect violence, weapons, drugs and so on: zero-shot checks for those fired on ~40% of ordinary
frames in testing, so they are deliberately not shipped. The classifier is strict (everyday dance and swimwear footage can trip it),
so a flag means "worth a look", never "explicit"."""

import threading

import numpy as np
import torch

MODEL = "Falconsai/nsfw_image_detection"
SAMPLE_FRAMES = 8
FLAG_AT = 0.80  # a frame counts when the classifier is at least this sure

_lock = threading.Lock()
_loaded = None
_failed = False


def _load():
    global _loaded, _failed
    with _lock:
        if _loaded is None and not _failed:
            try:
                from transformers import AutoImageProcessor, AutoModelForImageClassification

                proc = AutoImageProcessor.from_pretrained(MODEL)
                model = AutoModelForImageClassification.from_pretrained(MODEL).eval()
                idx = next(i for i, v in model.config.id2label.items() if v.lower() == "nsfw")
                _loaded = (model, proc, int(idx))
            except Exception as e:  # screening is optional: the mood analysis still completes
                print(f"screening model unavailable: {e!r}", flush=True)
                _failed = True
    return _loaded


def warm_up():
    _load()


def screen(frames):
    """frames: [(seconds, bgr)]. Returns {"checked": bool, "level": "clear|review", "flags": [...], "frames_checked": n}."""
    out = {"checked": False, "level": "clear", "flags": [], "frames_checked": 0}
    loaded = _load()
    if loaded is None or not frames:
        return out
    import cv2
    from PIL import Image

    model, proc, idx = loaded
    picks = sorted(set(np.linspace(0, len(frames) - 1, min(SAMPLE_FRAMES, len(frames))).round().astype(int).tolist()))
    with torch.inference_mode():
        imgs = [Image.fromarray(cv2.cvtColor(frames[i][1], cv2.COLOR_BGR2RGB)) for i in picks]
        probs = torch.softmax(model(**proc(images=imgs, return_tensors="pt")).logits, dim=-1)[:, idx].numpy()
    out.update(checked=True, frames_checked=len(picks))
    hits = [(picks[k], float(probs[k])) for k in range(len(picks)) if probs[k] >= FLAG_AT]
    if hits and (len(hits) >= 2 or len(picks) <= 2):
        best_i, best_p = max(hits, key=lambda h: h[1])
        out["level"] = "review"
        out["flags"].append(
            {
                "type": "revealing",
                "label": "Revealing or suggestive content",
                "score": round(best_p * 100, 1),
                "frames": len(hits),
                "of": len(picks),
                "t": round(frames[best_i][0], 1),
                "frame_index": best_i,
            }
        )
    return out
