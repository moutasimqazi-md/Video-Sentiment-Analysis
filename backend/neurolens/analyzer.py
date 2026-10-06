"""Core video sentiment analysis: samples frames, scores them against emotion
prompts with CLIP zero-shot classification, and adds color/pacing metrics."""

import os
import threading

import cv2
import numpy as np
import torch
from transformers import CLIPModel, CLIPProcessor
from PIL import Image

_model = None
_processor = None
_text_embeds = None
_load_lock = threading.Lock()

VISUAL_WEIGHT = 0.6  # audio gets the remaining 0.4 when the video has usable sound
torch.set_num_threads(os.cpu_count() or 4)  # torch defaults to physical cores; all threads is ~1.5x faster here

MIN_FRAMES = 12
MAX_FRAMES = 40
FRAMES_PER_SECOND = 1.2  # sampling density, so short reels aren't over-sampled
FRAME_SHORT_SIDE = 224  # CLIP's input size; frames are shrunk once, at read time
CLIP_BATCH = 16
SEQUENTIAL_READ_LIMIT = 3000  # above this many frames, seeking beats decoding every frame

CATEGORY_PROMPTS = {
    "confident": [
        "a person striking a confident, stylish pose with strong attitude",
        "a swagger walk, sunglasses, bold fashion, self-assured look",
    ],
    "motivated": [
        "an intense motivational scene of someone pushing to succeed",
        "a person working hard toward a goal at sunrise",
    ],
    "focused": [
        "a person lifting weights or working out in a gym",
        "an athlete training with intense focus and discipline",
    ],
    "inspired": [
        "a before and after body transformation",
        "a dramatic glow-up or life transformation moment",
    ],
    "excited": [
        "a celebration with confetti, fireworks and cheering people",
        "a party or festive event with excited crowds",
    ],
    "happy": [
        "friends laughing, dancing and having fun together",
        "a bright, cheerful, playful trending video moment",
    ],
    "funny": [
        "a comedic scene with a silly, exaggerated funny expression",
        "a relatable humorous situation that makes people laugh",
    ],
    "romantic": [
        "a romantic couple hugging, kissing or holding hands",
        "a love scene with flowers, candlelight or a wedding",
    ],
    "hungry": [
        "a photo of delicious appetizing food",
        "a close-up of someone eating food",
        "a plate of tasty food being prepared or served",
    ],
    "peaceful": [
        "a serene aesthetic nature landscape with soft light",
        "calm mountains, ocean, forest or sunset scenery",
    ],
    "heartbroken": [
        "a person crying alone after a breakup",
        "a torn photo, empty room and emotional heartbreak",
    ],
    "sad": [
        "a sad person looking down with tears, feeling low",
        "a rainy window with a gloomy, melancholic mood",
    ],
    "angry": [
        "an angry person shouting with a furious face",
        "a rage scene with clenched fists and intense aggression",
    ],
    "lost": [
        "a lonely person standing alone in a vast empty place",
        "a silhouette lost in deep thought at night",
    ],
    "tired": [
        "an exhausted stressed person overwhelmed by work",
        "a person with their head down, drained and burnt out",
    ],
    "depressed": [
        "a very dark, hopeless, depressing scene in shadows",
        "a person isolated in a dark room, emotionally numb",
    ],
}

MOOD_LABELS = {
    "confident": "Attitude Reels",
    "motivated": "Motivation Reels",
    "focused": "Gym / Goals Reels",
    "inspired": "Transformation Reels",
    "excited": "Celebration Reels",
    "happy": "Fun / Trending Reels",
    "funny": "Comedy / Relatable Reels",
    "romantic": "Love / Couple Reels",
    "hungry": "Food / Cravings Reels",
    "peaceful": "Aesthetic / Nature Reels",
    "heartbroken": "Breakup / Emotional Reels",
    "sad": "Sad-song / Feeling-low Reels",
    "angry": "Savage / Rage Reels",
    "lost": "Deep-thought / Alone Reels",
    "tired": "Stress / Life-struggle Reels",
    "depressed": "Dark / Healing Reels",
}


def _load_model():
    global _model, _processor
    with _load_lock:
        if _model is None:
            model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
            model.eval()
            _processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
            _model = model
    return _model, _processor


def _text_embedding(model, inputs):
    """Return the projected text embedding tensor.

    Newer transformers versions (>=5) have get_text_features return a
    BaseModelOutputWithPooling wrapper instead of a plain tensor. Its
    `pooler_output` is already the final projected embedding (its size
    matches the shared projection_dim, not the raw encoder hidden size), so
    it's used directly rather than re-applying a projection head.
    """
    out = model.get_text_features(**inputs)
    if isinstance(out, torch.Tensor):
        return out
    return out.pooler_output


def _image_embedding(model, inputs):
    out = model.get_image_features(**inputs)
    if isinstance(out, torch.Tensor):
        return out
    return out.pooler_output


def _category_text_embeddings():
    global _text_embeds
    if _text_embeds is not None:
        return _text_embeds

    model, processor = _load_model()
    embeds = {}
    with torch.no_grad():
        for cat, prompts in CATEGORY_PROMPTS.items():
            inputs = processor(text=prompts, return_tensors="pt", padding=True)
            text_features = _text_embedding(model, inputs)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)
            mean_vec = text_features.mean(dim=0)
            embeds[cat] = mean_vec / mean_vec.norm()
    _text_embeds = embeds
    return embeds


def _shrink(frame):
    h, w = frame.shape[:2]
    scale = FRAME_SHORT_SIDE / min(h, w)
    if scale >= 1:
        return frame
    return cv2.resize(frame, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)


def sample_frames(video_path, max_frames=MAX_FRAMES):
    """Evenly spaced frames, already shrunk to CLIP size. Returns (frames, duration, fps)."""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 25
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / fps if fps else 0

    if total_frames <= 0:
        cap.release()
        return [], 0, fps

    wanted_count = min(max_frames, max(MIN_FRAMES, round(duration * FRAMES_PER_SECOND)), total_frames)
    targets = sorted(set(np.linspace(0, total_frames - 1, wanted_count).round().astype(int).tolist()))
    frames = []

    if total_frames <= SEQUENTIAL_READ_LIMIT:
        # grab() skips the colour conversion, so walking every frame is much cheaper than seeking
        wanted = iter(targets)
        nxt = next(wanted, None)
        idx = 0
        while nxt is not None:
            if idx == nxt:
                ok, frame = cap.read()
                if not ok:
                    break
                frames.append((idx / fps, _shrink(frame)))
                nxt = next(wanted, None)
            elif not cap.grab():
                break
            idx += 1
    else:
        for idx in targets:
            cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
            ok, frame = cap.read()
            if not ok:
                break
            frames.append((idx / fps, _shrink(frame)))

    cap.release()
    return frames, duration, fps


def warm_up():
    """Load both models and run one tiny inference each, so the first real request is fast."""
    model, processor = _load_model()
    _category_text_embeddings()
    with torch.no_grad():
        dummy = Image.fromarray(np.zeros((224, 224, 3), np.uint8))
        _image_embedding(model, processor(images=[dummy], return_tensors="pt"))
    try:
        import audio_analyzer

        audio_analyzer.warm_up()
    except Exception as e:
        print(f"audio warm-up skipped: {e}")


def _color_metrics(frame_bgr):
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
    brightness = float(np.mean(hsv[:, :, 2])) / 255.0
    saturation = float(np.mean(hsv[:, :, 1])) / 255.0
    return brightness, saturation


def _build_verdict(averages, dominant, cuts_per_minute):
    lines = []

    ranked = sorted(averages, key=averages.get, reverse=True)
    lines.append(
        f"This feels like {'an' if dominant[0] in 'aeiou' else 'a'} {dominant} reel — "
        f"{MOOD_LABELS[dominant]} ({averages[dominant]:.0f}%)."
    )
    runners = ", ".join(f"{m} {averages[m]:.0f}%" for m in ranked[1:3])
    lines.append(f"Next strongest vibes: {runners}.")

    if cuts_per_minute > 30:
        lines.append(
            "Fast cut pacing detected — likely to feel stimulating or overstimulating to viewers."
        )
    elif cuts_per_minute < 5:
        lines.append("Slow, steady pacing — likely to feel calm, or possibly monotonous.")

    return " ".join(lines)


def analyze_video(video_path, max_frames=MAX_FRAMES, progress=None):
    report = progress or (lambda stage, frac: None)

    report("Getting ready", 0.02)
    model, processor = _load_model()
    text_embeds = _category_text_embeddings()
    categories = list(CATEGORY_PROMPTS.keys())
    text_matrix = torch.stack([text_embeds[c] for c in categories])

    report("Reading video frames", 0.06)
    frames, duration, fps = sample_frames(video_path, max_frames=max_frames)
    if not frames:
        raise ValueError("Could not read any frames from this video")

    n = len(frames)
    prob_chunks = []
    feat_chunks = []
    with torch.inference_mode():
        for i in range(0, n, CLIP_BATCH):
            imgs = [
                Image.fromarray(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
                for _, f in frames[i : i + CLIP_BATCH]
            ]
            feats = _image_embedding(model, processor(images=imgs, return_tensors="pt"))
            feats = feats / feats.norm(dim=-1, keepdim=True)
            prob_chunks.append(torch.softmax(feats @ text_matrix.T * 100, dim=-1).clone())
            feat_chunks.append(feats.clone())
            done = min(i + CLIP_BATCH, n)
            report(f"Scoring frames ({done}/{n})", 0.12 + 0.6 * done / n)
    probs = torch.cat(prob_chunks).numpy()

    # Mean embedding across frames: the raw feature a future fine-tuned classifier
    # would train on, as opposed to `probs` above which is already biased by our
    # hand-written prompts. Kept out of the API response (see main.py's _finish).
    mean_visual_embedding = torch.cat(feat_chunks).mean(dim=0)
    mean_visual_embedding = (mean_visual_embedding / mean_visual_embedding.norm()).tolist()

    thumbnail_jpg = None
    if frames:
        mid_frame = frames[n // 2][1]
        ok, buf = cv2.imencode(".jpg", mid_frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ok:
            thumbnail_jpg = buf.tobytes()

    timeline = []
    brightness_vals = []
    saturation_vals = []
    prev_hist = None
    cut_count = 0

    for k, (t, frame_bgr) in enumerate(frames):
        frame_scores = {cat: float(probs[k, j]) for j, cat in enumerate(categories)}
        frame_scores["t"] = round(t, 1)
        timeline.append(frame_scores)

        b, s = _color_metrics(frame_bgr)
        brightness_vals.append(b)
        saturation_vals.append(s)

        hist = cv2.calcHist([frame_bgr], [0, 1, 2], None, [8, 8, 8], [0, 256, 0, 256, 0, 256])
        hist = cv2.normalize(hist, hist).flatten()
        if prev_hist is not None:
            corr = cv2.compareHist(prev_hist, hist, cv2.HISTCMP_CORREL)
            if corr < 0.6:
                cut_count += 1
        prev_hist = hist

    visual = {cat: round(float(np.mean([f[cat] for f in timeline])) * 100, 1) for cat in categories}

    report("Listening to the audio", 0.76)
    try:
        from neurolens.audio_analyzer import analyze_audio

        audio = analyze_audio(video_path)
    except Exception as e:
        print(f"audio analysis failed: {e}", flush=True)  # detail stays in the server log
        audio = {"available": False, "reason": "the audio couldn't be analyzed"}
    report("Writing the verdict", 0.97)

    if audio.get("available"):
        averages = {
            c: round(VISUAL_WEIGHT * visual[c] + (1 - VISUAL_WEIGHT) * audio["averages"][c], 1)
            for c in categories
        }
    else:
        averages = dict(visual)

    dominant = max(averages, key=averages.get)

    cuts_per_minute = (cut_count / (duration / 60)) if duration > 0 else 0

    verdict = _build_verdict(averages, dominant, cuts_per_minute)
    if audio.get("available"):
        verdict += (
            f" Audio sounds {audio['dominant']} ({MOOD_LABELS[audio['dominant']]}), "
            f"visuals look {max(visual, key=visual.get)}."
        )

    return {
        "duration_seconds": round(duration, 1),
        "frames_analyzed": len(frames),
        "timeline": timeline,
        "averages": averages,
        "visual_averages": visual,
        "audio": audio,
        "dominant_mood": dominant,
        "color_metrics": {
            "avg_brightness": round(float(np.mean(brightness_vals)) * 100, 1),
            "avg_saturation": round(float(np.mean(saturation_vals)) * 100, 1),
            "cuts_per_minute": round(cuts_per_minute, 1),
        },
        "verdict": verdict,
        "mood_labels": MOOD_LABELS,
        "_embeddings": {
            "visual": mean_visual_embedding,
            "audio": audio.get("embedding"),
        },
        "_thumbnail_jpg": thumbnail_jpg,
    }
